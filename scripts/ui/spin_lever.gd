extends Control

## Lever: ball (top) + line (shaft). Ball moves down and back like a 90° pull.
## Ball scale: (1,1) at top → (1.5,1.5) at bottom. Line is fixed at bottom; top shortens to follow ball.

@onready var ball: TextureRect = $LeverPivot/Ball
@onready var line: TextureRect = $LeverPivot/Line

var _pulling: bool = false
var _ball_rest_position: Vector2 = Vector2.ZERO
var _line_rest_scale: Vector2 = Vector2(1.0, 1.0)

const BALL_MOVE_DOWN_PX := 120.0
const PULL_DURATION := 0.2
const RETURN_DURATION := 0.3
const BOTTOM_HOLD_DURATION := 0.1
const BALL_SCALE_REST := Vector2(1.0, 1.0)
const BALL_SCALE_AT_BOTTOM := Vector2(1.5, 1.5)

func _ready() -> void:
	_call_deferred_connect_spin_button()
	call_deferred("_store_ball_rest_position")
	call_deferred("_setup_line_pivot")

func _store_ball_rest_position() -> void:
	if ball != null:
		_ball_rest_position = ball.position

func _setup_line_pivot() -> void:
	## Pivot at bottom so line reduces from top; bottom stays fixed, top follows ball.
	if line != null:
		_line_rest_scale = line.scale
		line.pivot_offset = Vector2(line.size.x * 0.5, line.size.y)

func _call_deferred_connect_spin_button() -> void:
	await get_tree().process_frame
	var spin_btn = get_tree().get_first_node_in_group("spin_button")
	if spin_btn != null and spin_btn.has_signal("pressed"):
		spin_btn.pressed.connect(_on_spin_triggered)

func _process(_delta: float) -> void:
	if not _pulling or line == null or ball == null:
		return
	var progress: float = (ball.position.y - _ball_rest_position.y) / BALL_MOVE_DOWN_PX
	progress = clamp(progress, 0.0, 1.0)
	## Ball: scale (1,1) at top → (1.5,1.5) at bottom (90° pull toward user).
	var s: Vector2 = BALL_SCALE_REST.lerp(BALL_SCALE_AT_BOTTOM, progress)
	ball.scale = s
	## Line: same scale as ball (s) + reducing (length 1→0); pivot at bottom so top follows ball.
	line.scale = Vector2(_line_rest_scale.x * s.x, _line_rest_scale.y * (1.0 - progress) * s.y)

func _on_spin_triggered() -> void:
	if _pulling:
		return
	_pull_lever()

func _pull_lever() -> void:
	if ball == null or line == null:
		return
	_pulling = true
	ball.scale = BALL_SCALE_REST
	line.scale = _line_rest_scale
	var target_down := _ball_rest_position + Vector2(0, BALL_MOVE_DOWN_PX)
	var t := create_tween()
	t.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(ball, "position", target_down, PULL_DURATION)
	t.tween_interval(BOTTOM_HOLD_DURATION)
	t.tween_property(ball, "position", _ball_rest_position, RETURN_DURATION)
	t.finished.connect(func() -> void:
		_pulling = false
		ball.position = _ball_rest_position
		ball.scale = BALL_SCALE_REST
		line.scale = _line_rest_scale
	)
