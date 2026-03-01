extends NinePatchRect

@onready var xp_bar: TextureProgressBar = get_node_or_null("XPBar")
@onready var level_label: Label = $CapsuleContent/LevelLabel
@onready var xp_label: Label = $CapsuleContent/XPLabel
@onready var chips_label: Label = $CapsuleContent/ChipsLabel
@onready var chaos_label: Label = $CapsuleContent/ChaosLabel
@onready var lock_charges_label: Label = get_node_or_null("CapsuleContent/LockChargesLabel")

var game: Node  # Game controller
var level := 1
var xp := 0
var xp_max := 100
var chips := 0
var total_chips := 0  # Total chips accumulated in the run
var chaos := 0
var chaos_max := 100
var lock_charges := 0
var lock_charges_max := 3

# Chips label counts up gradually from previous to new value
var _displayed_chips: int = 0
var _chips_tween: Tween = null
const CHIPS_TWEEN_DURATION := 0.5

func _ready() -> void:
	# Wait for Game to be ready
	call_deferred("_initialize_game")

func _initialize_game() -> void:
	# Find game controller
	game = get_node_or_null("/root/Main/Game")
	if game == null:
		game = get_tree().get_first_node_in_group("game")
	
	if game == null:
		return
	
	# Wait for game to be fully initialized (retry if needed)
	var attempts := 0
	while not is_instance_valid(game.run_state) and attempts < 10:
		await get_tree().process_frame
		attempts += 1
	
	if game != null and is_instance_valid(game.run_state):
		# Connect to run state signals
		game.run_state.level_changed.connect(_on_level_changed)
		game.run_state.xp_changed.connect(_on_xp_changed)
		game.run_state.chips_changed.connect(_on_chips_changed)
		game.run_state.total_chips_changed.connect(_on_total_chips_changed)
		game.run_state.chaos_changed.connect(_on_chaos_changed)
		game.run_state.lock_charges_changed.connect(_on_lock_charges_changed)
		
		# Initialize with current values
		level = game.run_state.level
		xp = game.run_state.xp
		xp_max = game.run_state.xp_max
		chips = game.run_state.chips
		total_chips = game.run_state.total_chips
		_displayed_chips = total_chips
		chaos = game.run_state.chaos
		chaos_max = game.run_state.MAX_CHAOS
		lock_charges = game.run_state.lock_charges
		lock_charges_max = game.run_state.MAX_LOCK_CHARGES
	
	update_ui()

func _on_level_changed(new_level: int) -> void:
	level = new_level
	update_ui()

func _on_xp_changed(new_xp: int, max_xp: int) -> void:
	xp = new_xp
	xp_max = max_xp
	update_ui()

func _on_chips_changed(new_chips: int) -> void:
	chips = new_chips
	update_ui()

func _on_total_chips_changed(new_total: int) -> void:
	total_chips = new_total
	# Tween from current displayed value to new total so chips count up gradually
	if _chips_tween != null and _chips_tween.is_valid():
		_chips_tween.kill()
	var tw := create_tween()
	_chips_tween = tw
	tw.set_trans(Tween.TRANS_QUAD)
	tw.set_ease(Tween.EASE_OUT)
	tw.tween_method(
		_set_displayed_chips,
		float(_displayed_chips),
		float(new_total),
		CHIPS_TWEEN_DURATION
	)
	tw.finished.connect(func() -> void:
		if _chips_tween == tw:
			_chips_tween = null
		_displayed_chips = total_chips
		if chips_label:
			chips_label.text = "CHIPS: %s" % format_int(total_chips)
	)

func _set_displayed_chips(value: float) -> void:
	_displayed_chips = int(round(value))
	if chips_label:
		chips_label.text = "CHIPS: %s" % format_int(_displayed_chips)

func _on_chaos_changed(new_chaos: int, max_chaos: int) -> void:
	chaos = new_chaos
	chaos_max = max_chaos
	update_ui()

func _on_lock_charges_changed(new_charges: int, max_charges: int) -> void:
	lock_charges = new_charges
	lock_charges_max = max_charges
	update_ui()

# XP displayed ×100 to match chip scale (1 XP = 100 chips)
const XP_DISPLAY_SCALE := 100

func update_ui() -> void:
	level_label.text = "LEVEL %d" % level
	var xp_display: int = xp * XP_DISPLAY_SCALE
	var xp_max_display: int = xp_max * XP_DISPLAY_SCALE
	if xp_bar:
		xp_bar.max_value = xp_max_display
		xp_bar.value = xp_display
	xp_label.text = "%s / %s" % [format_int(xp_display), format_int(xp_max_display)]
	if chips_label:
		# Show total chips; use displayed value if tween is running so we don't jump
		if _chips_tween != null and _chips_tween.is_valid():
			chips_label.text = "CHIPS: %s" % format_int(_displayed_chips)
		else:
			_displayed_chips = total_chips
			chips_label.text = "CHIPS: %s" % format_int(total_chips)
	if chaos_label:
		# Color chaos label based on threshold phases
		# 🟢 < 30: Stable (white/green)
		# 🟡 ≥ 30: Instability (yellow)
		# 🟠 ≥ 60: Interference (orange)
		# 🔴 ≥ 90: Collapse Warning (red)
		if chaos >= 90:
			chaos_label.modulate = Color(1.0, 0.2, 0.2)  # Red (Collapse Warning)
		elif chaos >= 60:
			chaos_label.modulate = Color(1.0, 0.6, 0.2)  # Orange (Interference)
		elif chaos >= 30:
			chaos_label.modulate = Color(1.0, 0.8, 0.3)  # Yellow (Instability)
		else:
			chaos_label.modulate = Color(0.7, 1.0, 0.7)  # Light green (Stable)
		chaos_label.text = "CHAOS: %d/%d" % [chaos, chaos_max]
	
	if lock_charges_label:
		# Display lock charges (e.g., "LOCKS: 10")
		lock_charges_label.text = "LOCKS: %d" % lock_charges
		# Color based on availability (green if has charges, red if none)
		if lock_charges > 0:
			lock_charges_label.modulate = Color(0.7, 1.0, 0.7)  # Light green (has charges)
		else:
			lock_charges_label.modulate = Color(1.0, 0.5, 0.5)  # Light red (no charges)

func set_xp(new_xp: int) -> void:
	xp = new_xp
	var xp_display: int = xp * XP_DISPLAY_SCALE
	var xp_max_display: int = xp_max * XP_DISPLAY_SCALE
	if xp_bar:
		var tween := create_tween()
		tween.tween_property(xp_bar, "value", xp_display, 0.35)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	xp_label.text = "%s / %s" % [format_int(xp_display), format_int(xp_max_display)]

func format_int(n: int) -> String:
	var s := str(n)
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count == 3 and i != 0:
			out = "," + out
			count = 0
	return out


func _on_option_button_pressed() -> void:
	var main: Node = get_node_or_null("/root/Main")
	if main != null and main.has_method("open_options"):
		main.open_options()
