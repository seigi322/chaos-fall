extends Control

## Startup/Menu screen that auto-transitions to main game after 1-2 seconds

const MAIN_SCENE_PATH := "res://scenes/Main.tscn"
const AUTO_TRANSITION_DELAY := 2.0  # Wait 2 seconds before auto-transition

func _ready() -> void:
	# Start auto-transition timer
	await get_tree().create_timer(AUTO_TRANSITION_DELAY).timeout
	_transition_to_main()

func _transition_to_main() -> void:
	# Change scene to main game
	if ResourceLoader.exists(MAIN_SCENE_PATH):
		get_tree().change_scene_to_file(MAIN_SCENE_PATH)
	else:
		push_error("Startup: Main scene not found at: %s" % MAIN_SCENE_PATH)
