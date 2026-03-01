extends MarginContainer
## Score breakdown rows under Active Effects: Base, mult lines, Chaos Bonus. No title, no total.

const GOLD := Color(0.95, 0.75, 0.25, 1.0)

@onready var vbox: VBoxContainer = $VBox
var _game: Node = null
var _rows: Array[Dictionary] = []  # [{name_label, value_label}, ...]

func _ready() -> void:
	_build_rows()
	call_deferred("_connect_game")

func _build_rows() -> void:
	_rows.clear()
	for i in range(6):
		var row_name = vbox.get_node_or_null("Row%d/NameLabel" % (i + 1)) as Label
		var row_val = vbox.get_node_or_null("Row%d/ValueLabel" % (i + 1)) as Label
		if row_name and row_val:
			_rows.append({"name": row_name, "value": row_val})
			row_val.add_theme_color_override("font_color", GOLD)
			row_name.text = ""
			row_val.text = ""

func _connect_game() -> void:
	_game = get_node_or_null("/root/Main/Game")
	if _game == null:
		_game = get_tree().get_first_node_in_group("game")
	if _game != null:
		if _game.has_signal("spin_breakdown") and not _game.spin_breakdown.is_connected(_on_spin_breakdown):
			_game.spin_breakdown.connect(_on_spin_breakdown)
		if _game.has_signal("total_score_hidden"):
			if not _game.total_score_hidden.is_connected(_on_spin_breakdown):
				_game.total_score_hidden.connect(_on_spin_breakdown)
		_clear_rows()

func _clear_rows() -> void:
	for r in _rows:
		r.name.text = ""
		r.value.text = ""
		r.name.get_parent().visible = false

func _on_spin_breakdown(breakdown: Dictionary) -> void:
	var score_data: Dictionary = breakdown.get("score", {})
	if score_data == null:
		score_data = {}
	var chaos_data: Dictionary = breakdown.get("chaos", {})
	if chaos_data == null:
		chaos_data = {}

	var base_scaled: int = int(score_data.get("base_score", 0))
	var multipliers: Array = score_data.get("multipliers", [])

	var chaos_after: int = int(chaos_data.get("chaos_after", chaos_data.get("chaos_before", 0)))
	var chaos_mult: float = 1.0 + float(chaos_after) / 100.0

	var row_idx: int = 0

	# Base (no "Score" after Base)
	if row_idx < _rows.size():
		_rows[row_idx].name.text = "Base: "
		_rows[row_idx].value.text = "%d" % base_scaled
		_rows[row_idx].name.get_parent().visible = true
		row_idx += 1

	# Single row: total joker multiplier only (e.g. JOKER'S X 1.7)
	var total_joker_mult: float = 1.0
	for mult_entry in multipliers:
		var mult_val: float = float(mult_entry.get("multiplier", 1.0))
		if mult_val > 1.0:
			total_joker_mult *= round(mult_val * 10.0) / 10.0
	if total_joker_mult > 1.0 and row_idx < _rows.size():
		var mult_display: float = round(total_joker_mult * 10.0) / 10.0
		_rows[row_idx].name.text = "JOKER'S X "
		_rows[row_idx].value.text = "%.1f" % mult_display if mult_display != int(mult_display) else "%d" % int(mult_display)
		_rows[row_idx].name.get_parent().visible = true
		row_idx += 1

	# Chaos Bonus X [multiplier] — same style as JOKER'S, multiplier = 1 + chaos% / 100
	if row_idx < _rows.size() and chaos_mult > 1.0:
		var mult_display: float = round(chaos_mult * 10.0) / 10.0
		_rows[row_idx].name.text = "Chaos Bonus X "
		_rows[row_idx].value.text = "%.1f" % mult_display if mult_display != int(mult_display) else "%d" % int(mult_display)
		_rows[row_idx].name.get_parent().visible = true
		row_idx += 1

	# Hide unused rows
	for i in range(row_idx, _rows.size()):
		_rows[i].name.get_parent().visible = false
		_rows[i].name.text = ""
		_rows[i].value.text = ""
