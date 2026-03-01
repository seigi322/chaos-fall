extends Button
class_name SpinButton

## Handles the spin button interaction.

@onready var label: Label = $CenterContainer/Label

var game: Node = null  # Game controller
var run_state: Node = null

const DISABLED_MODULATE := Color(0.4, 0.4, 0.4, 1.0)  # Darker when disabled

var _last_disabled: bool = false

func _ready() -> void:
	add_to_group("spin_button")
	_last_disabled = disabled
	_update_disabled_appearance()
	pressed.connect(_on_spin_pressed)
	call_deferred("_initialize_game")

func _process(_delta: float) -> void:
	if disabled != _last_disabled:
		_last_disabled = disabled
		_update_disabled_appearance()

func _update_disabled_appearance() -> void:
	modulate = DISABLED_MODULATE if disabled else Color.WHITE

func _initialize_game() -> void:
	# Find game controller
	game = get_node_or_null("/root/Main/Game")
	if game == null:
		game = get_tree().get_first_node_in_group("game")
	
	if game == null:
		push_error("Game controller not found!")
		return
	
	# Get run_state from game
	run_state = game.run_state
	if run_state:
		run_state.spins_changed.connect(_on_spins_changed)
		_update_spin_display()

func _on_spins_changed(remaining: int, _max_spins: int) -> void:
	_update_spin_display()
	# Only disable when no spins left; do not enable here — board_view re-enables after score + chaos sequence (score_sequence_finished)
	if remaining <= 0:
		disabled = true

func _update_spin_display() -> void:
	if label == null or run_state == null:
		return
	
	# Check if this is the final joke spin
	if game != null and game.is_final_joke_spin:
		label.text = "Final"
	else:
		var remaining = run_state.spins_remaining
		var max_spins = run_state.SPINS_PER_LEVEL
		label.text = "%d/%d" % [remaining, max_spins]

const SPIN_SOUND_DELAY := 0.7  # Reel starts after this (spin button press.wav is ~1s)

func _on_spin_pressed() -> void:
	# Block input if run has ended, ENDED, or reward cutscene
	if game != null:
		if game.get("is_run_ended") == true or game.get("game_state") == game.GameState.ENDED:
			return
		if game.get("game_state") == game.GameState.REWARD_CUTSCENE:
			return

	var sm = get_node_or_null("/root/SfxManager")
	if sm:
		sm.play_spin_button()
	disabled = true
	var timer := get_tree().create_timer(SPIN_SOUND_DELAY)
	timer.timeout.connect(_do_spin_after_delay, CONNECT_ONE_SHOT)

func _do_spin_after_delay() -> void:
	if game != null:
		var success = game.spin()
		if not success:
			disabled = false  # Re-enable only if spin failed (e.g. no spins left)
	# If spin succeeded, board_view keeps button disabled until score_sequence_finished
