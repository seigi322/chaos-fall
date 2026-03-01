# res://scripts/ui/board_view.gd
extends Control

## Emitted when the card scroll (reel) animation has fully stopped. Score overlay waits for this.
signal scroll_animation_finished()

@onready var grid: GridContainer = $PanelContainer/Grid

var card_scene: PackedScene = preload("res://scenes/ui/card_view.tscn")
var notification_scene: PackedScene = preload("res://scenes/ui/notification.tscn")
var tooltip_scene: PackedScene = preload("res://scenes/ui/tooltip_popup.tscn")
var game: Node  # Game controller
var texture_resolver: CardTextureResolver
var card_views: Array[CardView] = []
var notification_popup: Node = null  # Notification instance
var waiting_for_evaluation: bool = false  # Track if we're waiting for hand evaluation to complete
var evaluation_completed: bool = false  # Track if evaluation has already completed
var _last_evaluation_result: Dictionary = {}  # Used to re-apply row dimming after spin refresh
var _scoring_slots: Array[int] = []  # Slots with yellow highlight; cleared before next row or before base score

# Layout (used by spawn_cards)
var strips: Array[Control] = []  # References to all 5 Strip nodes
var cell_h: float = 0.0  # Cell height (card height + separation)
# Card face is 121x121 (75% of 161); total size includes drop shadow (5px right, 8px down) for float effect
var card_size: Vector2 = Vector2(100, 100)
var v_separation: float = 20.0  # Vertical separation between cards
# Column dividers between card columns (5px, brown)
const COLUMN_DIVIDER_WIDTH := 5
const COLUMN_DIVIDER_COLOR := Color(0.45, 0.32, 0.22)  # Brown / aged copper

# Spin scroll animation (move down by 12 card heights per spin)
var is_spin_animating: bool = false
const SPIN_SCROLL_CARDS := 10  # Match REEL_STEP in spin_resolver (flow amount)
const SPIN_SCROLL_DURATION := 2  # Base seconds; each column gets a random duration in [MIN, MAX]
const SPIN_SCROLL_DURATION_MIN := 1.2  # Min seconds per column
const SPIN_SCROLL_DURATION_MAX := 2.4  # Max seconds per column (stop at random moment per column)
var _spin_strips_finished: int = 0
var _spin_strips_total: int = 0
# Locked cards reparented to ReelWindow during spin so they don't scroll; restored when spin finishes
var _locked_cards_reparented: Array = []  # [{ "slot_index": int, "strip": Control, "row": int }]

# Chaos: pass to cards for 70%+ suit distort; one-card flicker and instability also at 70+
var current_chaos: int = 0
# Chaos > 70: suit distort, one-card flicker, and card instability (offset 1–3 px, rotation ±1°, jitter)
const CHAOS_INSTABILITY_THRESHOLD := 70
const INSTABILITY_OFFSET_MIN := 1.0
const INSTABILITY_OFFSET_MAX := 3.0
const INSTABILITY_ROTATION_DEG := 1.0  # ±1°
const INSTABILITY_JITTER_PX := 0.35
var _instability_offsets: Array[Vector2] = []   # size 15, base random offset per card
var _instability_rotations: Array[float] = []   # size 15, radians
var _instability_jitter_timer: float = 0.0

# Dim inactive rows after spin so winning row pops (slightly dim = 0.7)
const INACTIVE_ROW_MODULATE := Color(0.6, 0.6, 0.6, 1.0)
# Yellow tint for winning (scoring) cards
const WINNING_ROW_MODULATE := Color(1.0, 0.9, 0.0, 1.0)
const YELLOW_GLOW_DURATION := 0.3  # Yellow glow lasts 0.3s then clears (no row order)

# One random card flickers just before first row score appears (0.1s), purely visual
const FLICKER_DURATION := 0.1

# Joker reward cutscene: pop + fly to right panel
const REWARD_POP_UP_DURATION := 0.2
const REWARD_POP_DOWN_DURATION := 0.15
const REWARD_POP_SCALE := 1.2
const REWARD_FLASH_MODULATE := Color(1.4, 1.4, 1.2, 1.0)
const REWARD_FLY_DURATION := 0.5
const REWARD_LAYER := 90

func _ready() -> void:
	# Add to group for easy access
	add_to_group("board_view")
	# Wait for Game to be ready
	call_deferred("_initialize_game")

func _process(delta: float) -> void:
	if current_chaos <= CHAOS_INSTABILITY_THRESHOLD:
		return
	_instability_jitter_timer += delta
	if _instability_jitter_timer >= 0.08:
		_instability_jitter_timer = 0.0
		_apply_card_instability(true)

func _initialize_game() -> void:
	# Find game controller in scene tree
	game = get_node_or_null("/root/Main/Game")
	if game == null:
		# Try alternative path or group
		game = get_tree().get_first_node_in_group("game")
	
	if game == null:
		push_error("Game controller not found! Make sure Game node exists in scene tree.")
		return
	
	# Wait for game to be fully initialized (retry if needed)
	var attempts := 0
	while not is_instance_valid(game.board) and attempts < 10:
		await get_tree().process_frame
		attempts += 1
	
	if not is_instance_valid(game.board):
		push_error("Game board not initialized!")
		return
	
	texture_resolver = game.texture_resolver
	
	# Connect to board signals
	if game.board:
		game.board.card_changed.connect(_on_card_changed)
		game.board.board_updated.connect(_on_board_updated)
	
	# Connect to spin resolver (update visuals when spin completes)
	if game.spin_resolver:
		game.spin_resolver.spin_complete.connect(_on_spin_complete)
	
	# Connect to core game signals
	if game:
		game.spins_exhausted.connect(_on_spins_exhausted)
		game.hand_evaluated.connect(_on_hand_evaluated)
		game.run_ended.connect(_on_run_ended)
		if game.has_signal("score_sequence_finished"):
			game.score_sequence_finished.connect(_on_score_sequence_finished)
		if game.has_signal("retriggered_rows"):
			game.retriggered_rows.connect(_on_retriggered_rows)
		if game.has_signal("first_row_about_to_show"):
			game.first_row_about_to_show.connect(_on_first_row_about_to_show)
	if game and game.run_state:
		game.run_state.chaos_changed.connect(_on_chaos_changed)
	if game and game.has_signal("joker_reward_cutscene"):
		game.joker_reward_cutscene.connect(_on_joker_reward_cutscene)
	
	# Create notification instance
	_create_notification()
	
	# Initialize UI
	spawn_cards()
	if game and game.run_state:
		current_chaos = game.run_state.chaos
		_update_cards_chaos_level(current_chaos)
	_on_board_updated()
	
	# Enable clipping on grid to hide cards outside boundaries
	if grid:
		grid.clip_contents = true
	
	# Disable spin button until first state flow finishes (row score + chaos overlay then score_sequence_finished)
	call_deferred("_set_spin_button_enabled", false)
	# Evaluate initial hand to show highlights (triggers initial overlay; spin enables on score_sequence_finished)
	call_deferred("_evaluate_initial_hand")

func spawn_cards() -> void:
	# Remove old cards if any
	for child in grid.get_children():
		child.queue_free()
	
	card_views.clear()
	# Pre-allocate array to ensure correct indexing by slot_index (5x3 = 15 slots)
	card_views.resize(15)
	
	# Card dimensions (match card_view.tscn: face 121x121 + shadow offset 5,8 — 75% of original)
	card_size = Vector2(100, 100)
	var h_separation: float = grid.get_theme_constant("h_separation", "GridContainer")
	if h_separation == 0:
		h_separation = 12
	v_separation = grid.get_theme_constant("v_separation", "GridContainer")
	if v_separation == 0:
		v_separation = 20
	
	# Calculate cell height (card height + separation)
	cell_h = card_size.y + v_separation
	
	# Clear strips array
	strips.clear()
	
	# Calculate ReelWindow height: 3 cards + 2 separations (visible area)
	var reel_height := card_size.y * 3 + v_separation * 2
	var reel_width := card_size.x
	
	# Ensure grid has minimum size (5 cols + 4 gaps + 4 dividers, 3 rows + 2 gaps)
	var min_width := 5 * reel_width + 4 * int(h_separation) + 4 * COLUMN_DIVIDER_WIDTH
	var min_height := reel_height
	grid.custom_minimum_size = Vector2(min_width, min_height)
	grid.columns = 9  # 5 reels + 4 dividers between columns
	
	# Total cards per column: 28 (3 visible + 25 buffer for reel length; match REEL_LENGTH in spin_resolver)
	var total_cards_per_column := 28
	# Calculate Strip height: 28 cards (27 separations between them)
	var strip_height := card_size.y * total_cards_per_column + v_separation * (total_cards_per_column - 1)
	
	# Create 5 ReelWindow controls with 4 dividers between columns
	for col in range(5):
		# Add divider before this column (except before first)
		if col > 0:
			var divider := ColorRect.new()
			divider.name = "ColumnDivider%d" % col
			divider.color = COLUMN_DIVIDER_COLOR
			divider.custom_minimum_size = Vector2(COLUMN_DIVIDER_WIDTH, 0)
			divider.size_flags_vertical = Control.SIZE_FILL
			divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
			grid.add_child(divider)
		# Create ReelWindow Control
		var reel_window := Control.new()
		reel_window.name = "ReelWindow%d" % col
		reel_window.clip_contents = true
		reel_window.custom_minimum_size = Vector2(reel_width, reel_height)
		grid.add_child(reel_window)
		
		# Create Strip Control inside ReelWindow (Control for manual positioning)
		var strip := Control.new()
		strip.name = "Strip"
		# Make Strip fill the ReelWindow width but extend beyond height
		strip.anchors_preset = Control.PRESET_TOP_WIDE
		strip.anchor_left = 0.0
		strip.anchor_top = 0.0
		strip.anchor_right = 1.0
		strip.anchor_bottom = 0.0
		strip.offset_left = 0.0
		strip.offset_top = 0.0
		strip.offset_right = 0.0
		strip.custom_minimum_size = Vector2(reel_width, strip_height)
		reel_window.add_child(strip)
		
		# Store strip reference
		strips.append(strip)
		
		# Create 28 cards for this column (3 visible + 25 buffer)
		for card_index in range(total_cards_per_column):
			var card_view: CardView = card_scene.instantiate() as CardView
			if card_view == null:
				push_error("Failed to instantiate CardView!")
				continue
			
			# Position card at y = index * cell_h
			# Disable anchors for manual positioning
			card_view.anchors_preset = Control.PRESET_TOP_LEFT
			card_view.anchor_left = 0.0
			card_view.anchor_top = 0.0
			card_view.anchor_right = 0.0
			card_view.anchor_bottom = 0.0
			card_view.position = Vector2(0, card_index * cell_h)
			card_view.size = card_size
			
			# Add card to scene tree FIRST so _ready() runs and art node is initialized
			strip.add_child(card_view)
			
			# For visible cards (indices 0-2), assign slot_index and connect signals
			if card_index < 3:
				var row := card_index
				var slot_index := row * 5 + col  # Calculate slot index: row * columns + col
				card_view.slot_index = slot_index
				card_view.card_pressed.connect(_on_card_pressed)
				# Store card at correct slot_index position in array
				card_views[slot_index] = card_view
			else:
				# Buffer cards: assign invalid slot_index and disable interaction
				card_view.slot_index = -1
				card_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
				# Assign random card texture to buffer card (after _ready() has run)
				# Use call_deferred to ensure _ready() has completed
				if texture_resolver != null:
					var suits := ["diamonds", "spades", "hearts", "clubs"]
					var random_suit: String = suits[randi() % 4]
					var random_value := randi_range(1, 13)
					var random_tex := texture_resolver.get_card_texture(random_value, random_suit)
					if random_tex != null:
						# Defer setting visual to ensure art node is initialized
						card_view.call_deferred("set_card_visual", "", random_tex)
	

func _trigger_one_card_flicker() -> int:
	var slot := randi() % card_views.size()
	var cv: CardView = card_views[slot]
	if cv == null or not cv.has_method("apply_flicker_visual"):
		return -1
	var item: BoardItem = game.board.get_card(slot) if game != null and game.board != null else null
	# 0 = wrong suit, 1 = joker silhouette, 2 = dark version, 3 = corrupted (wrong suit + tint)
	var kind := randi() % 4
	var tex: Texture2D = null
	var mod := Color.WHITE
	var suits := ["diamonds", "spades", "hearts", "clubs"]
	if kind == 0 or kind == 3:
		var wrong_value := randi_range(1, 13)
		var wrong_suit: String = suits[randi() % 4]
		if item is Card:
			var c := item as Card
			while wrong_value == c.value and wrong_suit == c.suit:
				wrong_value = randi_range(1, 13)
				wrong_suit = suits[randi() % 4]
		tex = texture_resolver.get_card_texture(wrong_value, wrong_suit)
		if kind == 3:
			mod = Color(1.15, 0.45, 0.45, 1.0)
	elif kind == 1:
		var joker_id := randi_range(1, 5)
		tex = texture_resolver.get_joker_texture(joker_id)
		mod = Color(0.22, 0.22, 0.22, 1.0)
	else:
		# dark version: keep current texture, darken
		tex = texture_resolver.get_texture_for_item(item) if item != null else null
		mod = Color(0.28, 0.28, 0.28, 1.0)
	if tex == null:
		tex = texture_resolver.get_card_texture(randi_range(1, 13), suits[randi() % 4])
	cv.apply_flicker_visual(tex, mod)
	return slot

func _restore_flicker_card(slot_index: int) -> void:
	update_card_visual(slot_index)

## Win tier: trigger 1 or more card flickers (T2 = 1 card, T4 = 5 fast). Count = number of cards to flicker.
func trigger_win_card_flicker(count: int) -> void:
	if game == null or texture_resolver == null or card_views.size() < 15:
		return
	var delay_step: float = 0.06 if count > 1 else 0.0
	var restore_after: float = 0.06 if count > 1 else FLICKER_DURATION
	for i in range(count):
		get_tree().create_timer(delay_step * float(i)).timeout.connect(func() -> void:
			var slot := _trigger_one_card_flicker()
			if slot >= 0:
				get_tree().create_timer(restore_after).timeout.connect(
					_restore_flicker_card.bind(slot), CONNECT_ONE_SHOT
				)
		, CONNECT_ONE_SHOT)

## Win tier T1: brief card outline pulse (soft glow on all cards).
func trigger_win_card_outline_pulse() -> void:
	if card_views.is_empty():
		return
	var saved: Array[Color] = []
	saved.resize(card_views.size())
	for i in range(card_views.size()):
		if card_views[i] != null:
			saved[i] = card_views[i].modulate
	var t: Tween = create_tween()
	t.set_parallel(true)
	for i in range(card_views.size()):
		var cv = card_views[i]
		if cv == null:
			continue
		var c: Color = saved[i]
		t.tween_property(cv, "modulate", Color(c.r * 1.12, c.g * 1.12, c.b, c.a), 0.12)
	t.chain().set_parallel(true)
	for i in range(card_views.size()):
		var cv = card_views[i]
		if cv == null:
			continue
		t.tween_property(cv, "modulate", saved[i], 0.18)
	t.tween_callback(func() -> void:
		for idx in range(card_views.size()):
			update_card_visual(idx)
	)

func _on_first_row_about_to_show() -> void:
	if is_spin_animating or game == null or texture_resolver == null or card_views.size() < 15:
		return
	# One-card flicker only when chaos > 70
	if current_chaos <= CHAOS_INSTABILITY_THRESHOLD:
		return
	var slot := _trigger_one_card_flicker()
	if slot >= 0:
		get_tree().create_timer(FLICKER_DURATION).timeout.connect(_restore_flicker_card.bind(slot), CONNECT_ONE_SHOT)

func _on_chaos_changed(new_chaos: int, _max_chaos: int) -> void:
	var was_above := current_chaos > CHAOS_INSTABILITY_THRESHOLD
	current_chaos = new_chaos
	_update_cards_chaos_level(new_chaos)
	if new_chaos > CHAOS_INSTABILITY_THRESHOLD:
		if not was_above or _instability_offsets.is_empty():
			_rebuild_instability_params()
	else:
		_clear_instability_params()
	_apply_card_instability(false)

## Call when run restarts so cards realign. Restores cards to strips, clears instability, applies alignment.
func sync_chaos_and_reset_alignment(chaos_value: int) -> void:
	current_chaos = chaos_value
	_update_cards_chaos_level(chaos_value)
	is_spin_animating = false
	_restore_all_cards_to_strips()
	_locked_cards_reparented.clear()
	_clear_instability_params()
	_apply_card_instability(false)

func _restore_all_cards_to_strips() -> void:
	if strips.is_empty() or card_views.is_empty() or cell_h <= 0.0:
		return
	for i in range(card_views.size()):
		var cv: CardView = card_views[i] as CardView
		if cv == null:
			continue
		var col: int = i % 5
		var row: int = int(i / 5.0)
		if col >= strips.size():
			continue
		var strip: Control = strips[col]
		if strip == null:
			continue
		if cv.get_parent() != strip:
			cv.top_level = false
			cv.reparent(strip)
			strip.move_child(cv, row)
			cv.z_index = 0
		cv.position = Vector2(0, row * cell_h)
		cv.rotation = 0.0
	for strip in strips:
		if strip != null:
			strip.position.y = 0.0

func _update_cards_chaos_level(chaos: int) -> void:
	for card_view in card_views:
		if card_view != null and card_view.has_method("set_chaos_level"):
			card_view.set_chaos_level(chaos)

func _rebuild_instability_params() -> void:
	var n := card_views.size()
	if _instability_offsets.size() != n:
		_instability_offsets.resize(n)
		_instability_rotations.resize(n)
	var rot_rad: float = deg_to_rad(INSTABILITY_ROTATION_DEG)
	for i in range(n):
		var ox := randf_range(-INSTABILITY_OFFSET_MAX, INSTABILITY_OFFSET_MAX)
		var oy := randf_range(-INSTABILITY_OFFSET_MAX, INSTABILITY_OFFSET_MAX)
		if abs(ox) < INSTABILITY_OFFSET_MIN and abs(oy) < INSTABILITY_OFFSET_MIN:
			ox = sign(randf() - 0.5) * randf_range(INSTABILITY_OFFSET_MIN, INSTABILITY_OFFSET_MAX)
			oy = sign(randf() - 0.5) * randf_range(INSTABILITY_OFFSET_MIN, INSTABILITY_OFFSET_MAX)
		_instability_offsets[i] = Vector2(ox, oy)
		_instability_rotations[i] = randf_range(-rot_rad, rot_rad)

func _clear_instability_params() -> void:
	var n := card_views.size()
	if _instability_offsets.size() != n:
		_instability_offsets.resize(n)
		_instability_rotations.resize(n)
	for i in range(n):
		_instability_offsets[i] = Vector2.ZERO
		_instability_rotations[i] = 0.0

func _apply_card_instability(jitter: bool) -> void:
	if is_spin_animating or card_views.is_empty() or cell_h <= 0.0:
		return
	if current_chaos <= CHAOS_INSTABILITY_THRESHOLD:
		# Ensure we're at base position/rotation when below threshold
		for i in range(card_views.size()):
			var cv: CardView = card_views[i]
			if cv == null:
				continue
			var row: int = int(i / 5.0)
			cv.position = Vector2(0, row * cell_h)
			cv.rotation = 0.0
		return
	var n := mini(card_views.size(), _instability_offsets.size())
	if _instability_rotations.size() != n:
		return
	for i in range(n):
		var cv: CardView = card_views[i]
		if cv == null:
			continue
		var row: int = int(i / 5.0)
		var base_pos := Vector2(0, row * cell_h)
		var offset: Vector2 = _instability_offsets[i]
		if jitter:
			offset += Vector2(randf_range(-INSTABILITY_JITTER_PX, INSTABILITY_JITTER_PX), randf_range(-INSTABILITY_JITTER_PX, INSTABILITY_JITTER_PX))
		cv.position = base_pos + offset
		cv.rotation = _instability_rotations[i]

func _on_board_updated() -> void:
	if game == null:
		return
	if is_spin_animating:
		return  # Don't update visuals during scroll animation
	for i in range(card_views.size()):
		update_card_visual(i)

func _on_card_changed(slot_index: int, _item: BoardItem) -> void:
	if is_spin_animating:
		return
	update_card_visual(slot_index)

## Call after spin() to set strip grid (first 3 cards per column) to new board state so they don't change at animation stop.
func refresh_strip_grid_from_board() -> void:
	for i in range(card_views.size()):
		update_card_visual(i)

func update_card_visual(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= card_views.size():
		return
	
	var card_view := card_views[slot_index]
	if card_view == null:
		push_error("CardView at slot %d is null!" % slot_index)
		return
	
	var item: BoardItem = game.board.get_card(slot_index)
	var is_locked: bool = game.board.is_locked(slot_index)
	
	# Update lock state (this will show/hide the highlight border)
	card_view.set_locked(is_locked)
	
	# Preserve scoring highlight state when updating visuals
	var was_scoring = card_view.is_scoring
	
	# Update card visual immediately
	if item != null and texture_resolver != null:
		var tex := texture_resolver.get_texture_for_item(item)
		if tex == null:
			push_warning("Failed to load texture for item at slot %d" % slot_index)
		card_view.set_card_visual("", tex)
	else:
		# Empty slot
		card_view.set_card_visual("", null)
	
	# Restore scoring highlight if it was active
	if was_scoring:
		card_view.set_scoring(true)
	
	# Winning cards keep yellow tint; others full brightness (or dimmed by _show_scoring_highlights)
	card_view.modulate = WINNING_ROW_MODULATE if was_scoring else Color.WHITE
	card_view.visible = true
	
	# Force visual update to ensure card is rendered immediately
	# Control nodes have queue_redraw() method
	card_view.queue_redraw()

func _create_notification() -> void:
	if notification_scene == null:
		return
	
	notification_popup = notification_scene.instantiate()
	if notification_popup:
		# Add to root (full screen viewport) to ensure it's centered on screen
		get_tree().root.add_child(notification_popup)
		# Position at center of full screen
		notification_popup.anchors_preset = Control.PRESET_CENTER
		notification_popup.anchor_left = 0.5
		notification_popup.anchor_top = 0.5
		notification_popup.anchor_right = 0.5
		notification_popup.anchor_bottom = 0.5

func _on_spins_exhausted(message: String) -> void:
	if notification_popup and notification_popup.has_method("show_notification"):
		notification_popup.show_notification(message, 3.0)
	else:
		pass  # Fallback if notification not available

func _on_run_ended(message: String) -> void:
	# Game is already paused when this is called (paused in game.gd when Joker 4 detected)
	# Disable all gameplay input - only restart button should work
	_disable_all_gameplay_input()
	
	# Just show the notification immediately
	if notification_popup and notification_popup.has_method("show_notification"):
		# Connect to restart signal if not already connected
		if notification_popup.has_signal("restart_requested"):
			if not notification_popup.restart_requested.is_connected(_on_restart_requested):
				notification_popup.restart_requested.connect(_on_restart_requested)
		# Show notification with restart button
		# duration 0 means don't auto-hide, show_restart=true
		notification_popup.show_notification(message, 0.0, true)
	else:
		pass  # Fallback if notification not available

func _disable_all_gameplay_input() -> void:
	# Disable spin button (group node is the Button root in new scene)
	var spin_button_node = get_tree().get_first_node_in_group("spin_button")
	if spin_button_node and spin_button_node is BaseButton:
		spin_button_node.disabled = true
	
	# Disable deck button
	var main_ui = get_tree().get_first_node_in_group("main_ui")
	if main_ui:
		var deck_button = main_ui.get_node_or_null("SafeRoot/ScreenPadding/VBoxContainer/Row/RightPanelWrap/RightPanelBg/RightPanel/DeckButton")
		if deck_button:
			deck_button.disabled = true
	
	# Disable all card views (prevent card clicks)
	for card_view in card_views:
		if card_view:
			card_view.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _enable_all_gameplay_input() -> void:
	# Re-enable spin button (state will be updated by spins_changed signal)
	var spin_button_node = get_tree().get_first_node_in_group("spin_button")
	if spin_button_node and spin_button_node is BaseButton:
		spin_button_node.disabled = false
	
	# Re-enable deck button
	var main_ui = get_tree().get_first_node_in_group("main_ui")
	if main_ui:
		var deck_button = main_ui.get_node_or_null("SafeRoot/ScreenPadding/VBoxContainer/Row/RightPanelWrap/RightPanelBg/RightPanel/DeckButton")
		if deck_button:
			deck_button.disabled = false
	
	# Re-enable all card views (allow mouse input)
	for card_view in card_views:
		if card_view:
			card_view.mouse_filter = Control.MOUSE_FILTER_STOP

## Disable inputs during spin (prevents double-click)
func _disable_inputs_during_spin() -> void:
	# Disable all card views (prevent card clicks)
	for card_view in card_views:
		if card_view:
			card_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Disable deck button
	var main_ui = get_tree().get_first_node_in_group("main_ui")
	if main_ui:
		var deck_button = main_ui.get_node_or_null("SafeRoot/ScreenPadding/VBoxContainer/Row/RightPanelWrap/RightPanelBg/RightPanel/DeckButton")
		if deck_button:
			deck_button.disabled = true

## Re-enable inputs after spin
func _enable_inputs_after_spin() -> void:
	# Re-enable all card views (allow mouse input)
	for card_view in card_views:
		if card_view:
			card_view.mouse_filter = Control.MOUSE_FILTER_STOP
	
	# Re-enable deck button
	var main_ui = get_tree().get_first_node_in_group("main_ui")
	if main_ui:
		var deck_button = main_ui.get_node_or_null("SafeRoot/ScreenPadding/VBoxContainer/Row/RightPanelWrap/RightPanelBg/RightPanel/DeckButton")
		if deck_button:
			deck_button.disabled = false

## Enable or disable the Spin button
func _set_spin_button_enabled(enabled: bool) -> void:
	var spin_button_node = get_tree().get_first_node_in_group("spin_button")
	if spin_button_node and spin_button_node is BaseButton:
		spin_button_node.disabled = not enabled

func _on_restart_requested() -> void:
	# Unpause the game before restarting
	get_tree().paused = false
	
	# Re-enable all gameplay input
	_enable_all_gameplay_input()
	
	# Restart the game (this will reset is_run_ended flag)
	if game and game.has_method("restart_run"):
		game.restart_run()

func _on_hand_evaluated(result: Dictionary) -> void:
	# Store result only; do not apply yellow win highlight here (reels may still be moving).
	# Highlights are applied after reel stop in _on_spin_scroll_animation_finished.
	_last_evaluation_result = result
	evaluation_completed = true
	
	if game and game.get("game_state") != game.GameState.ENDED:
		game.set_game_state(game.GameState.RUNNING)
	
	if waiting_for_evaluation:
		waiting_for_evaluation = false

func _show_scoring_highlights(result: Dictionary) -> void:
	_last_evaluation_result = result
	_scoring_slots.clear()
	# Clear previous scoring highlights and row dim
	for card_view in card_views:
		if card_view:
			card_view.set_scoring(false)
			card_view.modulate = Color.WHITE
	
	# Get row_hands to know which rows scored (winning) vs inactive
	var row_hands: Array = result.get("row_hands", [])
	for row_idx in range(3):
		var row_score: int = 0
		if row_idx < row_hands.size():
			var row_data: Dictionary = row_hands[row_idx] if row_hands[row_idx] is Dictionary else {}
			row_score = int(row_data.get("score", 0))
		var is_winning_row: bool = row_score > 0
		for col in range(5):
			var slot_index: int = row_idx * 5 + col
			if slot_index < card_views.size() and card_views[slot_index]:
				# Only dim inactive rows; winning row stays white (yellow applied only to matching cards below)
				card_views[slot_index].modulate = Color.WHITE if is_winning_row else INACTIVE_ROW_MODULATE
	
	# Yellow glow is applied per row when row_score_about_to_show(row_index) fires (see flash_winning_cards_for_row)

## Clear yellow glow from all scoring slots. Called before base score.
func _clear_scoring_highlights() -> void:
	for slot_idx in _scoring_slots:
		if slot_idx >= 0 and slot_idx < card_views.size() and card_views[slot_idx]:
			card_views[slot_idx].set_scoring(false)
			card_views[slot_idx].modulate = Color.WHITE
	_scoring_slots.clear()

## Return global Y of the center of each of the 3 rows (for score overlay alignment). First card per row: slots 0, 5, 10.
func get_row_center_global_y_positions() -> Array:
	var out: Array = []
	for row in range(3):
		var slot: int = row * 5
		if slot < card_views.size() and is_instance_valid(card_views[slot]):
			var rect: Rect2 = card_views[slot].get_global_rect()
			out.append(rect.get_center().y)
		else:
			var br: Rect2 = get_global_rect()
			var row_h: float = br.size.y / 3.0
			out.append(br.position.y + row_h * (float(row) + 0.5))
	while out.size() < 3:
		var br: Rect2 = get_global_rect()
		var row_h: float = br.size.y / 3.0
		out.append(br.position.y + row_h * (float(out.size()) + 0.5))
	return out

## Flash winning cards for this row yellow. Yellow lasts YELLOW_GLOW_DURATION (0.3s) then clears; no row order.
func flash_winning_cards_for_row(row_index: int) -> void:
	if game == null or row_index < 0 or row_index > 2:
		return
	var row_hands: Array = _last_evaluation_result.get("row_hands", [])
	var row_data: Dictionary = {}
	for rh in row_hands:
		if rh is Dictionary and int(rh.get("row_index", -1)) == row_index:
			row_data = rh
			break
	var matching_cards: Array = row_data.get("matching_cards", [])
	var slots_this_row: Array[int] = []
	for i in range(game.board.slots.size()):
		var item = game.board.slots[i]
		if item == null or item.is_joker:
			continue
		var card = item as Card
		if card == null:
			continue
		for match_card in matching_cards:
			if match_card == card:
				if i >= 0 and i < card_views.size() and card_views[i]:
					card_views[i].set_scoring(true)
					card_views[i].modulate = WINNING_ROW_MODULATE
					slots_this_row.append(i)
					if i not in _scoring_slots:
						_scoring_slots.append(i)
				break
	if slots_this_row.is_empty():
		return
	var timer := get_tree().create_timer(YELLOW_GLOW_DURATION)
	timer.timeout.connect(_clear_row_yellow_after_duration.bind(slots_this_row), CONNECT_ONE_SHOT)

func _clear_row_yellow_after_duration(slots_this_row: Array) -> void:
	for slot_idx in slots_this_row:
		if slot_idx >= 0 and slot_idx < card_views.size() and card_views[slot_idx]:
			card_views[slot_idx].set_scoring(false)
			card_views[slot_idx].modulate = Color.WHITE
		_scoring_slots.erase(slot_idx)

const RETRIGGER_IMAGE_PATH := "res://assets/text/retrigger.png"
const RETRIGGER_DISPLAY_DURATION := 3
# Retrigger image under chaos value text: base width (×2 = 200% in code)
const RETRIGGER_IMAGE_WIDTH_CHAOS_BAR := 64
const RETRIGGER_IMAGE_GAP_BELOW_BAR := 6
# Short row flash when retrigger image appears (same moment)
const RETRIGGER_ROW_FLASH_DURATION := 0.2
const RETRIGGER_ROW_FLASH_COLOR := Color(0.92, 0.75, 1.0, 0.4)

func _on_retriggered_rows(row_indices: Array) -> void:
	# Short flash on each retriggered row (same moment as retrigger image)
	for row_idx in row_indices:
		var r: int = int(row_idx)
		if r >= 0 and r < 3:
			_flash_retriggered_row(r)
	# Pulse cards in retriggered rows
	for row_idx in row_indices:
		var r: int = int(row_idx)
		if r < 0 or r >= 3:
			continue
		for col in range(5):
			var slot_index: int = r * 5 + col
			if slot_index >= 0 and slot_index < card_views.size():
				var cv: CardView = card_views[slot_index]
				if cv != null and cv.has_method("play_retrigger_pulse"):
					cv.play_retrigger_pulse()
	# Retrigger image under chaos value text (200% size)
	_show_retrigger_image_under_chaos_value()

func _flash_retriggered_row(row: int) -> void:
	var first_slot: int = row * 5
	var last_slot: int = row * 5 + 4
	if first_slot < 0 or last_slot >= card_views.size():
		return
	var first_card: Control = card_views[first_slot]
	var last_card: Control = card_views[last_slot]
	if first_card == null or last_card == null:
		return
	var container: Control = get_node_or_null("/root/Main/ScoreEffectsLayer/Container") as Control
	if container == null:
		return
	var p0: Vector2 = first_card.global_position
	var p1: Vector2 = last_card.global_position + last_card.size
	var row_global: Rect2 = Rect2(p0.x, p0.y, p1.x - p0.x, p1.y - p0.y)
	var to_local: Transform2D = container.get_global_transform_with_canvas().affine_inverse()
	var local_pos: Vector2 = to_local * row_global.position
	var local_bottom_right: Vector2 = to_local * row_global.end
	var local_size: Vector2 = local_bottom_right - local_pos
	local_size.x = abs(local_size.x)
	local_size.y = abs(local_size.y)
	var flash := ColorRect.new()
	flash.color = RETRIGGER_ROW_FLASH_COLOR
	flash.color.a = 0.0
	flash.position = local_pos
	flash.size = local_size
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(flash)
	flash.z_index = 55
	var tween := flash.create_tween()
	tween.tween_property(flash, "color:a", RETRIGGER_ROW_FLASH_COLOR.a, RETRIGGER_ROW_FLASH_DURATION * 0.35)
	tween.tween_property(flash, "color:a", 0.0, RETRIGGER_ROW_FLASH_DURATION * 0.65)
	tween.tween_callback(flash.queue_free)

func _show_retrigger_image_under_chaos_value() -> void:
	var tex: Texture2D = load(RETRIGGER_IMAGE_PATH) as Texture2D
	if tex == null:
		return
	var base_path: String = "/root/Main/SafeRoot/ScreenPadding/VBoxContainer/Row/MarginContainer/ActiveEffectPanel"
	var chaos_value_label: Control = get_node_or_null(base_path + "/HBoxContainer/Label") as Control
	if chaos_value_label == null:
		chaos_value_label = get_node_or_null(base_path + "/OuterMargin/VBox/ChaosBarContainer/ChaosValueLabel") as Control
	if chaos_value_label == null:
		return
	var label_rect: Rect2 = chaos_value_label.get_global_rect()
	var tex_size: Vector2 = tex.get_size()
	# 200% of base size (base 36 -> 72)
	var overlay_w: float = float(RETRIGGER_IMAGE_WIDTH_CHAOS_BAR) * 2.0
	var overlay_h: float = overlay_w * tex_size.y / tex_size.x if tex_size.x > 0 else overlay_w * 0.3
	# Center horizontally under chaos value text, with gap below label bottom
	var under_label_center: Vector2 = Vector2(
		label_rect.position.x + label_rect.size.x * 0.5,
		label_rect.position.y + label_rect.size.y + RETRIGGER_IMAGE_GAP_BELOW_BAR + overlay_h * 0.5
	)

	var rect := TextureRect.new()
	rect.texture = tex
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.custom_minimum_size = Vector2(overlay_w, overlay_h)
	rect.size = Vector2(overlay_w, overlay_h)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	call_deferred("_place_retrigger_image", rect, under_label_center, overlay_w, overlay_h)

func _place_retrigger_image(rect: TextureRect, bar_center_global: Vector2, overlay_w: float, overlay_h: float) -> void:
	if not is_instance_valid(rect):
		return
	var container: Control = get_node_or_null("/root/Main/ScoreEffectsLayer/Container") as Control
	if container == null:
		rect.queue_free()
		return
	container.add_child(rect)
	rect.z_index = 60
	var local_pos: Vector2 = container.get_global_transform_with_canvas().affine_inverse() * bar_center_global
	rect.position = local_pos - Vector2(overlay_w * 0.5, overlay_h * 0.5)
	var tween := rect.create_tween()
	tween.tween_interval(RETRIGGER_DISPLAY_DURATION * 0.5)
	tween.tween_property(rect, "modulate:a", 0.0, RETRIGGER_DISPLAY_DURATION * 0.5)
	tween.tween_callback(rect.queue_free)

func _on_card_pressed(slot_index: int) -> void:
	if game == null:
		return
	
	# Block input if run has ended, ended state, or reward cutscene
	if game.get("is_run_ended") == true or game.get("game_state") == game.GameState.ENDED:
		return
	if game.get("game_state") == game.GameState.REWARD_CUTSCENE:
		return
	
	# Get card/joker info before toggling lock
	var item: BoardItem = null
	if game.board != null:
		item = game.board.get_card(slot_index)
	
	# Show tooltip on click (joker or card) near the object
	if item != null and slot_index >= 0 and slot_index < card_views.size():
		var cv: CardView = card_views[slot_index]
		if cv != null:
			var rect := cv.get_global_rect()
			var center := rect.get_center()
			var tip := tooltip_scene.instantiate()
			if tip != null and tip.has_method("show_tooltip"):
				get_tree().root.add_child(tip)
				tip.show_tooltip(_get_card_info_text(item), center)
	
	# Toggle lock (now allows switching locks between cards)
	var success = game.toggle_lock(slot_index)
	if success:
		# Lock toggled successfully - update visuals for all cards
		# This ensures the previously locked card's highlight is removed
		# and the newly locked card's highlight is shown
		for i in range(card_views.size()):
			update_card_visual(i)
		
		# Show card/joker info in breakdown panel (both when locking and unlocking)
		if item != null:
			_show_card_info(item)

func _on_joker_reward_cutscene(slot_index: int, joker_id: int) -> void:
	if slot_index < 0 or slot_index >= card_views.size():
		game.notify_joker_reward_animation_finished(slot_index, joker_id)
		return
	var cv: CardView = card_views[slot_index]
	if cv == null or not is_instance_valid(cv):
		game.notify_joker_reward_animation_finished(slot_index, joker_id)
		return
	var joker_tex: Texture2D = null
	if texture_resolver != null:
		joker_tex = texture_resolver.get_joker_texture(joker_id)
	if joker_tex == null:
		game.notify_joker_reward_animation_finished(slot_index, joker_id)
		return
	var start_global := cv.get_global_rect().get_center()
	var panel = get_node_or_null("/root/Main/SafeRoot/ScreenPadding/VBoxContainer/Row/RightPanelWrap/RightPanelBg/RightPanel/ActiveEffectPanel")
	if panel == null or not panel.has_method("get_joker_slot_global_center"):
		game.notify_joker_reward_animation_finished(slot_index, joker_id)
		return
	var target_slot_index: int = game.owned_jokers.size()
	var target_global: Vector2 = panel.get_joker_slot_global_center(target_slot_index)
	if target_global.is_equal_approx(Vector2.ZERO):
		target_global = start_global + Vector2(200, 0)
	var layer := CanvasLayer.new()
	layer.layer = REWARD_LAYER
	get_tree().root.add_child(layer)
	var flying := TextureRect.new()
	flying.texture = joker_tex
	var fly_size := Vector2(80, 80)
	flying.custom_minimum_size = fly_size
	flying.size = fly_size
	flying.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	flying.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	flying.position = start_global - fly_size * 0.5
	flying.pivot_offset = fly_size * 0.5
	layer.add_child(flying)
	var tw := flying.create_tween()
	tw.set_parallel(true)
	tw.tween_property(flying, "scale", Vector2(REWARD_POP_SCALE, REWARD_POP_SCALE), REWARD_POP_UP_DURATION).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(flying, "modulate", REWARD_FLASH_MODULATE, REWARD_POP_UP_DURATION)
	tw.set_parallel(false)
	tw.tween_property(flying, "scale", Vector2.ONE, REWARD_POP_DOWN_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_property(flying, "modulate", Color.WHITE, REWARD_POP_DOWN_DURATION)
	tw.tween_property(flying, "position", target_global - fly_size * 0.5, REWARD_FLY_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(func() -> void:
		if is_instance_valid(layer):
			layer.queue_free()
		if game != null and game.has_method("notify_joker_reward_animation_finished"):
			game.notify_joker_reward_animation_finished(slot_index, joker_id)
	)

func _get_card_info_text(item: BoardItem) -> String:
	if item == null:
		return ""
	# Treat as joker if is_joker is true or runtime type is JokerCard (Resource exports can be lost in some paths)
	var is_joker_item := item.is_joker or item.get_class() == "JokerCard" or (item.get("joker_id") != null and int(item.get("joker_id")) > 0)
	if is_joker_item:
		var joker_id: int = item.joker_id
		var joker_desc := ""
		var joker_instance = null
		if game != null and game.owned_jokers != null:
			for joker in game.owned_jokers:
				if joker != null and joker.id == "joker" + str(joker_id):
					joker_instance = joker
					joker_desc = joker.description
					break
		if joker_instance == null:
			var joker_path := "res://scripts/core/jokers/joker" + str(joker_id) + ".gd"
			if ResourceLoader.exists(joker_path):
				var joker_class = load(joker_path)
				if joker_class != null:
					joker_instance = joker_class.new()
					joker_desc = joker_instance.description
		if joker_desc == "":
			joker_desc = "Joker card"
		if joker_instance != null:
			var chaos_info: Array = []
			if joker_instance.chaos_cost > 0:
				chaos_info.append("+%d chaos" % joker_instance.chaos_cost)
			if joker_instance.can_reduce_chaos and joker_instance.chaos_reduction > 0:
				chaos_info.append("-%d chaos" % joker_instance.chaos_reduction)
			if not chaos_info.is_empty():
				joker_desc += " (" + ", ".join(chaos_info) + ")"
		return "joker %d: %s" % [joker_id, joker_desc]
	else:
		var card = item as Card
		if card != null:
			var suit_name: String = card.suit.to_lower()
			var value_name := ""
			match card.value:
				1: value_name = "Ace"
				10: value_name = "10"
				_: value_name = str(card.value)
			return "%s %s: normal card" % [suit_name, value_name]
	# Fallback so tooltip is never blank (e.g. display name from BoardItem)
	if item.has_method("get_display_name"):
		var name_str: String = item.get_display_name()
		if not name_str.is_empty():
			return name_str
	return "Card"

func _show_card_info(item: BoardItem) -> void:
	var info_text := _get_card_info_text(item)
	if info_text.is_empty():
		return
	var breakdown_panel = get_node_or_null("/root/Main/SafeRoot/ScreenPadding/VBoxContainer/BreakdownPanel")
	if breakdown_panel == null:
		breakdown_panel = get_tree().get_first_node_in_group("spin_breakdown_panel")
	if breakdown_panel != null and breakdown_panel.has_method("show_card_info"):
		breakdown_panel.show_card_info(info_text)

func clear_scoring_highlights() -> void:
	for card_view in card_views:
		if card_view:
			card_view.set_scoring(false)

func start_spin_animation() -> void:
	var sm = get_node_or_null("/root/SfxManager")
	if sm:
		sm.play_reel_spin_primary()
		sm.play_reel_spin_secondary()
	clear_scoring_highlights()
	# Reset row dim so next evaluation can apply fresh
	for card_view in card_views:
		if card_view:
			card_view.modulate = Color.WHITE
	waiting_for_evaluation = true
	evaluation_completed = false
	_disable_inputs_during_spin()
	_set_spin_button_enabled(false)
	is_spin_animating = true
	# Fill each strip with the full 10-length first array so all cards render as they flow into view
	if game != null and game.spin_resolver != null and texture_resolver != null:
		var reel_columns: Array = game.spin_resolver.reel_columns
		const REEL_LENGTH := 28  # Match spin_resolver.REEL_LENGTH
		for col in range(min(reel_columns.size(), strips.size())):
			var column: Array = reel_columns[col]
			var strip_node: Control = strips[col]
			if strip_node == null:
				continue
			var strip_children := strip_node.get_children()
			for i in range(min(REEL_LENGTH, column.size(), strip_children.size())):
				# Don't overwrite visuals for locked slots (visible rows 0–2)
				if i < 3 and game != null and game.board != null and game.board.has_method("is_locked"):
					var slot_i: int = i * 5 + col
					if game.board.is_locked(slot_i):
						continue
				var item = column[i]
				var card_view = strip_children[i] as CardView
				if card_view != null:
					var tex = texture_resolver.get_texture_for_item(item) if item != null else null
					card_view.set_card_visual("", tex)
					card_view.visible = true
					card_view.modulate = Color.WHITE
	# Reparent locked cards to ReelWindow so they stay fixed while the strip scrolls
	_locked_cards_reparented.clear()
	if game != null and game.board != null and game.board.has_method("is_locked"):
		for slot_index in range(card_views.size()):
			if not game.board.is_locked(slot_index):
				continue
			var card_view: CardView = card_views[slot_index] as CardView
			if card_view == null:
				continue
			var row: int = int(slot_index / 5.0)
			var col: int = slot_index % 5
			if col >= strips.size():
				continue
			var strip: Control = strips[col]
			if strip == null:
				continue
			var reel_window: Control = strip.get_parent() as Control
			if reel_window == null:
				continue
			# Keep current global position so card doesn't jump when we reparent
			var global_pos: Vector2 = card_view.global_position
			card_view.reparent(reel_window)
			card_view.top_level = true
			card_view.global_position = global_pos
			card_view.z_index = 1  # Draw above scrolling strip
			_locked_cards_reparented.append({ "slot_index": slot_index, "strip": strip, "row": row })
	# Flow top to down: start strip at -scroll_distance (show reel 12–15), tween to 0 so strip moves down
	# Each column stops at a random moment (random duration per column)
	var scroll_distance := SPIN_SCROLL_CARDS * cell_h
	for strip in strips:
		if strip != null:
			strip.position.y = -scroll_distance
	_spin_strips_finished = 0
	_spin_strips_total = 0
	var max_duration := 0.0
	var durations: Array[float] = []
	for strip in strips:
		if strip == null:
			continue
		var duration := randf_range(SPIN_SCROLL_DURATION_MIN, SPIN_SCROLL_DURATION_MAX)
		durations.append(duration)
		if duration > max_duration:
			max_duration = duration
	var idx := 0
	for strip in strips:
		if strip == null:
			continue
		_spin_strips_total += 1
		var duration: float = durations[idx] if idx < durations.size() else randf_range(SPIN_SCROLL_DURATION_MIN, SPIN_SCROLL_DURATION_MAX)
		idx += 1
		var tween := create_tween()
		tween.set_trans(Tween.TRANS_CUBIC)
		tween.set_ease(Tween.EASE_OUT)  # Fast at start, slow at stop moment
		tween.tween_property(strip, "position:y", 0.0, duration)
		tween.finished.connect(_on_one_strip_animation_finished)
	if _spin_strips_total == 0:
		_on_spin_scroll_animation_finished()

func _on_one_strip_animation_finished() -> void:
	_spin_strips_finished += 1
	if _spin_strips_finished >= _spin_strips_total:
		_on_spin_scroll_animation_finished()

func _on_spin_scroll_animation_finished() -> void:
	# All reels have stopped; play reel stop sound now
	var sm = get_node_or_null("/root/SfxManager")
	if sm:
		sm.stop_reel_spin_primary()
		sm.play_reel_stop()
	# Restore locked cards back into their strips so layout is correct
	for entry in _locked_cards_reparented:
		var slot_index: int = entry["slot_index"]
		var strip: Control = entry["strip"]
		var row: int = entry["row"]
		var card_view: CardView = card_views[slot_index] as CardView
		if card_view != null and strip != null:
			card_view.top_level = false
			card_view.reparent(strip)
			strip.move_child(card_view, row)
			card_view.position = Vector2(0, row * cell_h)
			card_view.z_index = 0
	_locked_cards_reparented.clear()
	_apply_card_instability(false)
	# Clear locks now (so lock icons disappear after cards stop, not when spin was clicked)
	if game != null and game.has_method("clear_locks_after_spin_animation"):
		game.clear_locks_after_spin_animation()
	# Refresh all card visuals from board (new result) and reset strip positions
	for i in range(card_views.size()):
		update_card_visual(i)
	# Re-apply row dimming (update_card_visual sets all modulate to WHITE)
	if not _last_evaluation_result.is_empty():
		_show_scoring_highlights(_last_evaluation_result)
	for strip in strips:
		if strip != null:
			strip.position.y = 0.0
	is_spin_animating = false
	_enable_inputs_after_spin()
	if game and game.get("game_state") != game.GameState.ENDED:
		game.set_game_state(game.GameState.RUNNING)
	if evaluation_completed:
		waiting_for_evaluation = false
		# Spin button re-enables when score + chaos sequence finishes (score_sequence_finished)
	scroll_animation_finished.emit()

func _on_spin_complete() -> void:
	# If scroll animation is running, refresh and re-enable happen in _on_spin_scroll_animation_finished
	if is_spin_animating:
		return
	for i in range(card_views.size()):
		update_card_visual(i)
	# Re-apply row dimming (update_card_visual sets all modulate to WHITE)
	if not _last_evaluation_result.is_empty():
		_show_scoring_highlights(_last_evaluation_result)
	_enable_inputs_after_spin()
	if game and game.get("game_state") != game.GameState.ENDED:
		game.set_game_state(game.GameState.RUNNING)
	if evaluation_completed:
		waiting_for_evaluation = false
		# Spin button re-enables when score + chaos sequence finishes (score_sequence_finished)

func _on_score_sequence_finished() -> void:
	_set_spin_button_enabled(true)

func _evaluate_initial_hand() -> void:
	# Evaluate initial hand for display: scores, breakdown, highlights (no chips/chaos change)
	if game and game.has_method("evaluate_initial_display"):
		var result: Dictionary = game.evaluate_initial_display()
		_show_scoring_highlights(result)
