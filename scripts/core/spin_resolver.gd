extends Node
class_name SpinResolver

## Handles drawing new cards and updating the board

signal spin_complete()

var board
var deck: Array = []

## Reel animation data: 5 columns, each an array of 28 BoardItems.
## First array: indices 10-13 = current 4 cards on grid; 0-9 = front (preserved); 14-27 = random.
## On spin: pop REEL_STEP from front, push REEL_STEP random at end. Grid shows a slice of the new cards.
var reel_columns: Array = []  # Array of 5 Arrays; each inner array has 28 BoardItem
## Front REEL_STEP cards of each column from last spin; reused so visible area doesn't change during animation.
var _prev_front_twelve: Array = []  # Array of 5 Arrays; each inner array has REEL_STEP BoardItem (or empty on first spin)
## Joker placement for spins 3, 6, 9: applied when writing to grid so animation result shows the joker.
var _joker_placement_slot: int = -1
var _joker_placement_card: BoardItem = null
const REEL_LENGTH := 28
const REEL_GRID_FIRST := 10   # First array: front 10 cards (preserved for animation)
const REEL_GRID_LAST_FIRST := 12  # First array: grid = indices 10-12 (3 rows)
const REEL_STEP := 10  # Pop 10, push 10 per spin (flow amount; adjust for more/less random feel)
const REEL_GRID_NEW_COUNT := 3   # We show 3 rows from the REEL_STEP new cards
# After push: new cards at indices (REEL_LENGTH - REEL_STEP)..(REEL_LENGTH-1). Random offset picks which 3 show.

## Creates a standard 52-card deck (4 suits × 13 ranks = 52 cards)
## NOTE: Jokers are NOT in the deck - they are given to the player at spins 3, 6, 9 and Chaos 90
func create_deck() -> void:
	deck.clear()
	var suits := ["diamonds", "spades", "hearts", "clubs"]
	for suit in suits:
		for value in range(1, 14):  # 1-13 (Ace=1, 2-10, Jack=11, Queen=12, King=13)
			var card = Card.new(value, suit)
			deck.append(card)
	# Jokers are NOT added to the deck - they are given to the player automatically:
	# - Spin 3 → Joker #1 (Entropy Engine) or Joker #2 (Ritual Blade)
	# - Spin 6 → Joker #1 (Entropy Engine) or Joker #2 (Ritual Blade)
	# - Spin 9 → Joker #1 (Entropy Engine) or Joker #2 (Ritual Blade)
	# - Chaos ≥ 90 → Joker #4 (The Final Joke)
	# NOTE: Joker #3 (Pressure Valve) is excluded until implementation is complete

## Shuffles the deck (multiple passes for better randomness, avoids J/Q/K clustering)
func shuffle_deck() -> void:
	for _pass in range(3):
		deck.shuffle()

## Draws a random card from the deck
## Cards are NOT removed from the deck - all cards can appear every spin
func draw_card():
	if deck.is_empty():
		create_deck()
		shuffle_deck()
	# Use randi() with wide range for better distribution (avoids same positions)
	var index := randi() % deck.size()
	var card = deck[index]
	return card

## Draws a random card whose identity key is not in used_keys (so grid has no duplicate cards).
func draw_card_excluding(used_keys: Dictionary) -> Card:
	var limit := 100
	while limit > 0:
		limit -= 1
		var card = draw_card()
		if card == null:
			continue
		var key := _card_identity_key(card)
		if not used_keys.has(key):
			return card
	return draw_card()  # Fallback if all 52 were used (shouldn't happen on 15 slots)

## Returns a unique key for a grid card (same card = same key; no duplicate keys on grid).
func _card_identity_key(item: Variant) -> String:
	if item == null:
		return "null"
	if item is JokerCard:
		return "joker_%d" % (item as JokerCard).joker_id
	if item is Card:
		var c := item as Card
		return "%s_%d" % [c.suit, c.value]
	return str(item)

## Builds 5 column arrays (first array). Length 28:
## indices 0-9 = front; 10-12 = current 3 cards on grid; 13-27 = random.
func _build_reel_columns() -> void:
	reel_columns.clear()
	create_deck()
	shuffle_deck()
	for col in range(5):
		var column: Array = []  # 28 BoardItems
		for i in range(REEL_GRID_FIRST):
			column.append(draw_card())
		for row in range(3):
			var slot_index := row * 5 + col
			var item: BoardItem = board.get_card(slot_index)
			column.append(item)
		for i in range(REEL_LENGTH - 1 - REEL_GRID_LAST_FIRST):
			column.append(draw_card())
		reel_columns.append(column)

## Call before spin() when a joker will appear this spin (3, 6, 9). Spin will place it when applying second array to grid.
func set_joker_placement(slot_index: int, joker_card: BoardItem) -> void:
	_joker_placement_slot = slot_index
	_joker_placement_card = joker_card

## Prepares the first array for the spin animation. Call before start_spin_animation().
## Builds reel_columns with indices 0-9 = previous front REEL_STEP; 10-12 = current grid (3 rows); 13-27 = random.
func prepare_first_array() -> void:
	if board == null:
		push_error("Board is null in SpinResolver")
		return
	reel_columns.clear()
	randomize()  # Fresh entropy each spin so J/Q/K don't stick to same positions
	create_deck()
	shuffle_deck()
	for col in range(5):
		var column: Array = []  # 28 BoardItems
		# Indices 0-11: reuse previous front 12 so they don't change in visible area; otherwise random (first spin)
		if col < _prev_front_twelve.size():
			var prev: Array = _prev_front_twelve[col]
			if prev.size() >= REEL_GRID_FIRST:
				for i in range(REEL_GRID_FIRST):
					column.append(prev[i])
			else:
				for i in range(REEL_GRID_FIRST):
					column.append(draw_card())
		else:
			for i in range(REEL_GRID_FIRST):
				column.append(draw_card())
		# Indices 10-12: current 3 cards on the grid (visible window)
		for row in range(3):
			var slot_index := row * 5 + col
			var item: BoardItem = board.get_card(slot_index)
			column.append(item)
		# Indices 14-27: random
		for i in range(REEL_LENGTH - 1 - REEL_GRID_LAST_FIRST):
			column.append(draw_card())
		reel_columns.append(column)
	# Remember this spin's front REEL_STEP for next spin
	while _prev_front_twelve.size() < 5:
		_prev_front_twelve.append([])
	for col in range(5):
		var column: Array = reel_columns[col]
		var front: Array = []
		for i in range(REEL_GRID_FIRST):
			front.append(column[i])
		_prev_front_twelve[col] = front

## On spin: reel_columns must already be the first array (from prepare_first_array()).
## Pop REEL_STEP from front, push REEL_STEP random at end. Grid shows a random slice of the new cards.
## At Chaos ≥ 60: Locked cards have 25% chance to ignore the lock.
func spin() -> void:
	if board == null:
		push_error("Board is null in SpinResolver")
		return
	if reel_columns.is_empty():
		push_error("SpinResolver: prepare_first_array() must be called before spin()")
		return
	# Fresh shuffle so the REEL_STEP we push each column come from a different order each spin
	shuffle_deck()
	# Step: pop REEL_STEP from front, push REEL_STEP random at end
	for col in range(reel_columns.size()):
		var column: Array = reel_columns[col]
		for i in range(REEL_STEP):
			column.pop_front()
		for i in range(REEL_STEP):
			column.append(draw_card())
	
	# New cards are at indices (REEL_LENGTH - REEL_STEP)..(REEL_LENGTH-1). Pick a random slice of 3 for the grid.
	var new_start: int = REEL_LENGTH - REEL_STEP  # e.g. 18 for step 10
	var max_offset: int = maxi(0, REEL_STEP - REEL_GRID_NEW_COUNT)  # 0..7 for step 10
	var placed_keys: Dictionary = {}  # identity key -> true; ensures same card cannot exist twice on grid
	for col in range(reel_columns.size()):
		var column: Array = reel_columns[col]
		# Random offset so which 3 of the REEL_STEP new cards land on grid varies per column
		var offset: int = randi() % (max_offset + 1) if max_offset > 0 else 0
		for row in range(3):
			var slot_index: int = row * 5 + col
			if board.is_locked(slot_index):
				continue
			# Joker placement (spins 3, 6, 9): put joker on pre-chosen slot so animation result shows it
			if _joker_placement_slot >= 0 and slot_index == _joker_placement_slot and _joker_placement_card != null:
				var joker_key := _card_identity_key(_joker_placement_card)
				placed_keys[joker_key] = true
				board.set_card(slot_index, _joker_placement_card)
				continue
			var current_item = board.get_card(slot_index)
			if current_item != null and current_item.is_joker:
				var joker_card = current_item as JokerCard
				if joker_card != null and joker_card.joker_id == 4:
					continue  # Preserve Final Joke on grid
			# Row 0 (top) = new_start+offset+2, row 2 (bottom) = new_start+offset
			var reel_index: int = new_start + offset + (2 - row)
			if reel_index < column.size():
				var item = column[reel_index]
				if item != null:
					var key := _card_identity_key(item)
					if placed_keys.has(key):
						# Replace with a card not already on grid so same card cannot exist twice
						item = draw_card_excluding(placed_keys)
						key = _card_identity_key(item)
					placed_keys[key] = true
					board.set_card(slot_index, item)
	# Clear joker placement for next spin
	_joker_placement_slot = -1
	_joker_placement_card = null
	# Handle 25% lock ignore chance at Chaos ≥ 60 (replacement card must still be unique on grid)
	var game_node = get_tree().get_first_node_in_group("game")
	if game_node != null:
		var run_state = game_node.get("run_state")
		if run_state != null and run_state.get("chaos") >= 60:
			for i in range(board.TOTAL_SLOTS):
				if board.is_locked(i):
					if randi() % 100 < 25:
						var card = draw_card_excluding(placed_keys)
						placed_keys[_card_identity_key(card)] = true
						board.set_card(i, card)
	
	# Notify board view to refresh all card visuals from the new board state (second array 0-3 on grid)
	board.notify_updated()
	
	spin_complete.emit()

## Fills empty slots only (for initial deal). Clears reel_columns and _prev_front_three so next spin builds fresh.
func deal_initial() -> void:
	if board == null:
		push_error("Board is null in SpinResolver")
		return
	
	reel_columns.clear()
	_prev_front_twelve.clear()  # Next spin will use random for front 12
	randomize()
	create_deck()
	shuffle_deck()
	
	var empty_slots: Array = board.get_empty_slots()
	var deal_keys: Dictionary = {}
	for slot_index in empty_slots:
		var card = draw_card_excluding(deal_keys)
		deal_keys[_card_identity_key(card)] = true
		board.set_card(slot_index, card)
	
	spin_complete.emit()

## Get current deck state as a dictionary of items with counts
## Returns: Array of {item_key: String, item: BoardItem, count: int}
func get_deck_state() -> Array:
	var item_counts: Dictionary = {}
	
	# Count each unique card/joker in the deck
	for item in deck:
		var key: String = ""
		if item.is_joker:
			key = "joker_%d" % item.joker_id
		else:
			var card = item as Card
			if card != null:
				key = "card_%d_%s" % [card.value, card.suit]
		
		if key.is_empty():
			continue
		
		if not item_counts.has(key):
			item_counts[key] = {
				"item": item,
				"count": 0
			}
		item_counts[key].count += 1
	
	# Convert to array format
	var result: Array = []
	for key in item_counts:
		result.append(item_counts[key])
	
	return result
