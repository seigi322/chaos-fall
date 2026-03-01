extends PanelContainer
class_name CurrentBonusCard

## Displays the current hand bonus and score after each spin.
## When multiple rows win, cycles through each row's hand (Row 1: One Pair, Row 2: Flush, etc.).

@onready var bonus_label_wrap: PanelContainer = $OuterMargin/VBox/InnerPanel/InnerMargin/VBoxInner/BonusLabelWrap
@onready var carousel_slide: Control = $OuterMargin/VBox/InnerPanel/InnerMargin/VBoxInner/BonusLabelWrap/CarouselSlide
@onready var bonus_label: Label = $OuterMargin/VBox/InnerPanel/InnerMargin/VBoxInner/BonusLabelWrap/CarouselSlide/BonusLabel
@onready var row1_label: Label = $OuterMargin/VBox/InnerPanel/InnerMargin/VBoxInner/HRow/Row1Pill/Row1Label
@onready var row2_label: Label = $OuterMargin/VBox/InnerPanel/InnerMargin/VBoxInner/HRow/Row2Pill/Row2Label
@onready var row3_label: Label = $OuterMargin/VBox/InnerPanel/InnerMargin/VBoxInner/HRow/Row3Pill/Row3Label
@onready var h_row: HBoxContainer = $OuterMargin/VBox/InnerPanel/InnerMargin/VBoxInner/HRow

var game: Node = null
var row_labels: Array[Label] = []
var row_pills: Array[Control] = []  # Row1Pill, Row2Pill, Row3Pill for show/hide

# Winning rows to cycle through: { row_number (1-based), name, score }
var _winning_rows: Array[Dictionary] = []
# All three row scores (from last hand_evaluated) so we can show them under the score text
var _row_scores: Array[int] = [0, 0, 0]
var _cycle_index: int = 0
var _cycle_timer: Timer = null
var _carousel_tween: Tween = null
const CYCLE_INTERVAL := 2.5
const CAROUSEL_DURATION := 0.35

func _ready() -> void:
	call_deferred("_initialize_game")

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_size_bonus_label_to_center()

func _size_bonus_label_to_center() -> void:
	if bonus_label == null or bonus_label_wrap == null:
		return
	var wrap_size: Vector2 = bonus_label_wrap.size
	if wrap_size.x > 0 and wrap_size.y > 0:
		bonus_label.size = wrap_size
		bonus_label.position.y = 0.0

func _initialize_game() -> void:
	game = get_node_or_null("/root/Main/Game")
	if game == null:
		game = get_tree().get_first_node_in_group("game")

	row_labels = [row1_label, row2_label, row3_label]
	for lbl in row_labels:
		if lbl and lbl.get_parent():
			row_pills.append(lbl.get_parent())

	if game:
		game.hand_evaluated.connect(_on_hand_evaluated)
	# Ensure hand name label is visible and centered
	if bonus_label:
		bonus_label.position.x = 0
	call_deferred("_size_bonus_label_to_center")
	_update_display_single("No Hand", [0, 0, 0])

func _on_hand_evaluated(result: Dictionary) -> void:
	var row_hands = result.get("row_hands", [])
	if row_hands == null:
		row_hands = []

	# Store all three row scores for display under the hand text
	_row_scores = [0, 0, 0]
	for row_result in row_hands:
		var ri: int = int(row_result.get("row_index", 0))
		var sc: int = int(row_result.get("score", 0))
		if ri >= 0 and ri < 3:
			_row_scores[ri] = sc

	# Build list of winning rows (score > 0) with hand name and score
	_winning_rows.clear()
	for row_result in row_hands:
		var row_index: int = int(row_result.get("row_index", 0))
		var row_score: int = int(row_result.get("score", 0))
		if row_score <= 0:
			continue
		var name_str: String = str(row_result.get("name", "Unknown"))
		_winning_rows.append({
			"row_number": row_index + 1,
			"name": name_str,
			"score": row_score
		})

	_stop_cycle_timer()

	if _winning_rows.is_empty():
		var row_scores: Array[int] = [0, 0, 0]
		for row_result in row_hands:
			var ri: int = int(row_result.get("row_index", 0))
			var sc: int = int(row_result.get("score", 0))
			if ri >= 0 and ri < 3:
				row_scores[ri] = sc
		_update_display_single("No Hand", row_scores)
		return

	if _winning_rows.size() == 1:
		_show_cycle_item(0)
		return

	# Multiple winning rows: cycle through them
	_cycle_index = 0
	_show_cycle_item(0)
	_start_cycle_timer()

func _start_cycle_timer() -> void:
	_stop_cycle_timer()
	_cycle_timer = Timer.new()
	_cycle_timer.one_shot = false
	_cycle_timer.wait_time = CYCLE_INTERVAL
	_cycle_timer.timeout.connect(_on_cycle_tick)
	add_child(_cycle_timer)
	_cycle_timer.start()

func _stop_cycle_timer() -> void:
	if _cycle_timer != null:
		if _cycle_timer.is_inside_tree():
			_cycle_timer.stop()
			_cycle_timer.queue_free()
		_cycle_timer = null

func _on_cycle_tick() -> void:
	if _winning_rows.is_empty():
		_stop_cycle_timer()
		return
	_cycle_index = (_cycle_index + 1) % _winning_rows.size()
	_show_cycle_item(_cycle_index)

func _show_cycle_item(index: int) -> void:
	if index < 0 or index >= _winning_rows.size():
		return
	var w: Dictionary = _winning_rows[index]
	var name_str: String = w.get("name", "Unknown")

	_size_bonus_label_to_center()
	if bonus_label:
		bonus_label.text = name_str.to_upper()

	# Carousel: new hand name slides in from right to left
	if bonus_label and bonus_label_wrap:
		if _carousel_tween and _carousel_tween.is_valid():
			_carousel_tween.kill()
		var wrap_width: float = float(bonus_label_wrap.size.x)
		var start_x: float = wrap_width if wrap_width > 10.0 else 280.0
		bonus_label.position.x = start_x
		_carousel_tween = create_tween()
		_carousel_tween.set_ease(Tween.EASE_OUT)
		_carousel_tween.set_trans(Tween.TRANS_CUBIC)
		_carousel_tween.tween_property(bonus_label, "position:x", 0.0, CAROUSEL_DURATION)

	if h_row != null:
		h_row.visible = true
	# Show all three row score pills
	for i in range(3):
		var pill: Control = row_pills[i] if i < row_pills.size() else null
		var lbl: Label = row_labels[i] if i < row_labels.size() else null
		if pill != null:
			pill.visible = true
		if lbl != null:
			var sc: int = _row_scores[i] if i < _row_scores.size() else 0
			lbl.text = str(sc)

func _update_display_single(hand_name: String, row_scores: Array[int]) -> void:
	if _carousel_tween and _carousel_tween.is_valid():
		_carousel_tween.kill()
	_size_bonus_label_to_center()
	if bonus_label:
		bonus_label.position.x = 0
		bonus_label.text = hand_name.to_upper()

	while row_scores.size() < 3:
		row_scores.append(0)

	if h_row != null:
		h_row.visible = true
	for i in range(min(3, row_labels.size())):
		if row_labels[i]:
			row_labels[i].text = str(row_scores[i])
		if i < row_pills.size() and row_pills[i]:
			row_pills[i].visible = true
