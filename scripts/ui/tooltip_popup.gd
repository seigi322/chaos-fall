extends CanvasLayer

## White pill tooltip. show_tooltip(text, anchor_global_pos). Auto-hides or tap to close.

const AUTO_HIDE_SECONDS := 1.5

@onready var backdrop: Control = $Backdrop
@onready var pill: PanelContainer = $Backdrop/Pill
@onready var label: Label = $Backdrop/Pill/Margin/Label

var _hide_timer: Timer = null

## Above ScoreEffectsLayer (100) so tooltip always draws on top
const TOOLTIP_LAYER := 100

func _ready() -> void:
	layer = TOOLTIP_LAYER
	if backdrop:
		backdrop.gui_input.connect(_on_backdrop_input)
	if pill:
		pill.gui_input.connect(_on_backdrop_input)
	if pill:
		pill.visible = false

func show_tooltip(text: String, anchor_global_pos: Vector2) -> void:
	if label:
		label.add_theme_color_override("font_color", Color(0.12, 0.12, 0.12))
		label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.3))
		label.text = text if not text.is_empty() else "—"
	pill.visible = true
	# Position pill on next frame when size is valid
	call_deferred("_place_pill", anchor_global_pos)
	_start_auto_hide()

func _place_pill(anchor_global_pos: Vector2) -> void:
	if not is_instance_valid(pill):
		return
	pill.set_anchors_preset(Control.PRESET_TOP_LEFT)
	var pill_size := pill.get_combined_minimum_size()
	if pill_size.x < 40:
		pill_size.x = 40
	if pill_size.y < 24:
		pill_size.y = 24
	var viewport_size := get_viewport().get_visible_rect().size
	var half_w := pill_size.x * 0.5
	var max_x := viewport_size.x - pill_size.x - 8.0
	var max_y := viewport_size.y - pill_size.y - 8.0
	var px := clampf(anchor_global_pos.x - half_w, 8.0, max_x)
	var py := clampf(anchor_global_pos.y - pill_size.y - 12.0, 8.0, max_y)
	if py < 8.0:
		py = clampf(anchor_global_pos.y + 12.0, 8.0, max_y)
	pill.position = Vector2(px, py)

func _start_auto_hide() -> void:
	if _hide_timer != null and is_instance_valid(_hide_timer):
		_hide_timer.stop()
		_hide_timer.queue_free()
	_hide_timer = Timer.new()
	_hide_timer.one_shot = true
	_hide_timer.timeout.connect(_hide_tooltip_callback)
	add_child(_hide_timer)
	_hide_timer.start(AUTO_HIDE_SECONDS)

func _hide_tooltip_callback() -> void:
	_close()

func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_close()

func _close() -> void:
	if _hide_timer != null and is_instance_valid(_hide_timer):
		_hide_timer.stop()
		_hide_timer.queue_free()
		_hide_timer = null
	queue_free()
