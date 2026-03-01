extends Control
## Shows a one-line math expression under Active Effects: base × hand × jokers × chaos(%) = result

@onready var label: Label = $MathExpressionLabel

var _game: Node = null

func _ready() -> void:
	call_deferred("_connect_game")

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
		_set_placeholder()

func _set_placeholder() -> void:
	if label:
		label.text = "— × — = —"

func _on_spin_breakdown(breakdown: Dictionary) -> void:
	var score_data: Dictionary = breakdown.get("score", {})
	if score_data == null:
		score_data = {}
	var chaos_data: Dictionary = breakdown.get("chaos", {})
	if chaos_data == null:
		chaos_data = {}

	var base_score: int = int(score_data.get("base_score", 0))
	var multipliers: Array = score_data.get("multipliers", [])
	var chaos_after: int = int(chaos_data.get("chaos_after", chaos_data.get("chaos_before", 0)))

	# Chaos multiplier = 1 + chaos% / 100 (e.g. 15% → 1.15), exact double
	var chaos_mult: float = 1.0 + float(chaos_after) / 100.0

	# Calculate result exactly with double (float)
	var result_f: float = float(base_score)
	for mult_entry in multipliers:
		var mult_val: float = float(mult_entry.get("multiplier", 1.0))
		if mult_val <= 1.0:
			continue
		result_f *= mult_val
	result_f *= chaos_mult

	var parts: Array[String] = []
	parts.append("%d" % base_score)

	for mult_entry in multipliers:
		var joker_name: String = str(mult_entry.get("joker", "?"))
		var mult_val: float = float(mult_entry.get("multiplier", 1.0))
		if mult_val <= 1.0:
			continue
		if mult_val == int(mult_val):
			parts.append("%s(%d)" % [joker_name, int(mult_val)])
		else:
			parts.append("%s(%.2f)" % [joker_name, mult_val])

	# Show chaos as multiplier value: 15% → 1.15
	parts.append("chaos(%.2f)" % chaos_mult)

	var result_str: String
	if is_equal_approx(result_f, round(result_f)):
		result_str = "%d" % int(round(result_f))
	else:
		result_str = "%.2f" % result_f

	var line: String = " × ".join(parts) + " = " + result_str
	if label:
		label.text = line
