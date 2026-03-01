extends Control
class_name Notification

## Simple notification popup for displaying messages

signal restart_requested()

@onready var label: RichTextLabel = $VBox/PanelContainer/MarginContainer/VBoxInner/Label
@onready var button_container: HBoxContainer = $VBox/PanelContainer/MarginContainer/VBoxInner/ButtonContainer
@onready var restart_button: Button = $VBox/PanelContainer/MarginContainer/VBoxInner/ButtonContainer/RestartButton
@onready var panel: PanelContainer = $VBox/PanelContainer

var message: String = ""

func _ready() -> void:
	visible = false
	modulate.a = 0.0
	scale = Vector2(0.8, 0.8)
	
	# Center the notification on screen
	anchors_preset = Control.PRESET_CENTER
	
	# Make notification process even when game is paused
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	# Block input to game behind notification (but allow restart button to work)
	mouse_filter = Control.MOUSE_FILTER_STOP
	
	if restart_button:
		restart_button.pressed.connect(_on_restart_pressed)
		button_container.visible = false  # Hide by default

func show_notification(text: String, duration: float = 2.0, show_restart: bool = false) -> void:
	message = text
	
	# Format text with BBCode for better styling
	var formatted_text = "[center][b]%s[/b][/center]" % text
	label.text = formatted_text
	
	# Show/hide restart button
	if button_container:
		button_container.visible = show_restart
	
	# Reset state
	visible = true
	modulate.a = 0.0
	scale = Vector2(0.8, 0.8)
	
	# Beautiful fade in + scale animation
	var tween := create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_OUT)
	
	# Fade in
	tween.tween_property(self, "modulate:a", 1.0, 0.4)
	# Scale up with bounce effect
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.4)
	# Slight upward movement
	tween.tween_property(self, "position:y", position.y - 30, 0.4)
	
	await tween.finished
	
	# If restart button is shown, don't auto-hide
	if show_restart:
		return  # Stay visible until button is pressed
	
	# Wait and fade out
	await get_tree().create_timer(duration).timeout
	
	var tween2 := create_tween()
	tween2.set_parallel(true)
	tween2.set_trans(Tween.TRANS_CUBIC)
	tween2.set_ease(Tween.EASE_IN)
	
	# Fade out
	tween2.tween_property(self, "modulate:a", 0.0, 0.3)
	# Scale down slightly
	tween2.tween_property(self, "scale", Vector2(0.9, 0.9), 0.3)
	# Move down
	tween2.tween_property(self, "position:y", position.y + 20, 0.3)
	
	await tween2.finished
	visible = false
	modulate.a = 1.0
	scale = Vector2(1.0, 1.0)

func _on_restart_pressed() -> void:
	restart_requested.emit()
	# Hide notification after restart
	visible = false
	modulate.a = 1.0
