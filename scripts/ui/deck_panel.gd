extends CanvasLayer

signal closed

@export var deck_card_item_scene: PackedScene = preload("res://scenes/ui/deck_card_item.tscn")

var close_button: Button = null
var backdrop: TextureRect = null
var deck_grid: GridContainer = null
var game: Node = null
var texture_resolver: CardTextureResolver = null

func _ready() -> void:
	# Wait a frame to ensure all nodes are ready
	call_deferred("_setup_connections")
	call_deferred("_setup_deck_grid")
	call_deferred("_initialize_game")

func _setup_connections() -> void:
	# Find close button
	close_button = get_node_or_null("SafeRoot/ScreenPadding/Panel/Content/Header/Close")
	if close_button != null:
		close_button.pressed.connect(_close)
	else:
		var error_msg = "Deck panel: Close button not found at path: "
		error_msg += "SafeRoot/ScreenPadding/Panel/Content/Header/Close"
		push_error(error_msg)
		# Try alternative path
		close_button = get_node_or_null("SafeRoot/ScreenPadding/Panel/Content/Header/CloseButton")
		if close_button != null:
			close_button.pressed.connect(_close)
	
	# Find backdrop
	backdrop = get_node_or_null("Backdrop")
	if backdrop != null:
		backdrop.gui_input.connect(_on_backdrop_input)
	else:
		push_error("Deck panel: Backdrop not found!")

func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_close()

func _initialize_game() -> void:
	# Find game controller
	game = get_node_or_null("/root/Main/Game")
	if game == null:
		game = get_tree().get_first_node_in_group("game")
	
	if game == null:
		push_error("Deck panel: Game controller not found!")
		return
	
	# Get texture resolver
	var resolver = game.get("texture_resolver")
	if resolver != null:
		texture_resolver = resolver
	
	# Load deck data and display
	_load_and_display_deck()

func _setup_deck_grid() -> void:
	# Find deck grid (now inside CenterContainer)
	var grid_path = "SafeRoot/ScreenPadding/Panel/Content/DeckScroll/CenterContainer/DeckGrid"
	deck_grid = get_node_or_null(grid_path)
	if deck_grid == null:
		push_error("Deck panel: DeckGrid not found!")
		return
	
	# Clear any existing items (like the placeholder DeckCardItem1)
	for child in deck_grid.get_children():
		child.queue_free()

func _load_and_display_deck() -> void:
	if game == null or texture_resolver == null:
		return
	
	# Get spin resolver from game
	var spin_resolver = game.get("spin_resolver")
	if spin_resolver == null:
		push_error("Deck panel: SpinResolver not found!")
		return
	
	# Get deck state
	var deck_state = spin_resolver.get_deck_state()
	if deck_state.is_empty():
		# Deck might be empty, show empty state
		return
	
	# Convert deck state to display format
	var display_items: Array = []
	for item_data in deck_state:
		var item: BoardItem = item_data.get("item", null)
		var count: int = item_data.get("count", 0)
		
		if item == null:
			continue
		
		# Get texture for the item
		var tex: Texture2D = null
		if texture_resolver != null:
			tex = texture_resolver.get_texture_for_item(item)
		
		# Calculate weight (simple: based on count relative to total deck size)
		# For now, use a simple weight calculation
		var total_deck_size = spin_resolver.deck.size()
		var weight: float = float(count) / float(total_deck_size) if total_deck_size > 0 else 0.0
		
		display_items.append({
			"tex": tex,
			"count": count,
			"weight": weight
		})
	
	# Sort by type (cards first, then jokers) and then by value/id
	display_items.sort_custom(_sort_deck_items)
	
	# Display the deck
	show_deck(display_items)

func _sort_deck_items(_a: Dictionary, _b: Dictionary) -> bool:
	# Simple sort - maintain order as items are already grouped
	# Could be improved to sort by card value/suit or joker ID
	return false

func show_deck(items: Array) -> void:
	# items format: [{tex: Texture2D, count: int, weight: float (0.0-1.0)}, ...]
	if deck_grid == null:
		_setup_deck_grid()
		if deck_grid == null:
			return
	
	# Clear existing items
	for child in deck_grid.get_children():
		child.queue_free()
	
	# Create deck card items
	for item in items:
		if deck_card_item_scene == null:
			push_error("Deck panel: deck_card_item_scene not assigned!")
			continue
		
		var card_item = deck_card_item_scene.instantiate()
		if card_item == null:
			push_error("Deck panel: Failed to instantiate deck card item!")
			continue
		
		deck_grid.add_child(card_item)
		
		# Set data
		var tex = item.get("tex", null)
		var count = item.get("count", 1)
		var weight = item.get("weight", 0.5)
		
		if card_item.has_method("set_data"):
			card_item.set_data(tex, count, weight)

func _close() -> void:
	if is_queued_for_deletion():
		return
	
	emit_signal("closed")
	queue_free()
