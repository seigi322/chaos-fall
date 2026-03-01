extends Control
class_name GridScoreOverlay

## Flow: (1) Each row score text appears. (2) Total score text appears (first total). (3) Retrigger image appears.
## Flow: (1) Base score appear (sum of 3 rows). (2) Retrigger image show (game on total_score_displayed).
## (3) Base+retrigger count up. (4) Joker bonus animation + multiply on chaos bar. (5) (base+retrigger)*joker*chaos count up → chaos show → overlay_finished.
## Phase 1: Row scores one-by-one. Phase 2: Base at center, total_score_displayed, retrigger wait → retrigger image + count-ups + mult anim → fade.
signal total_score_displayed(breakdown: Dictionary)
signal chaos_show_now(breakdown: Dictionary)  # Emitted after final total (with retrigger if any) is shown; chaos text + sound run here
signal overlay_finished(breakdown: Dictionary)  # Emitted after total has disappeared
@warning_ignore("unused_signal")
signal first_row_about_to_show()  # Emitted via emit_signal.bind(); connected in score_effects_layer
@warning_ignore("unused_signal")
signal row_score_about_to_show(row_index: int)  # Emitted via emit_signal.bind(); connected in score_effects_layer
signal chaos_bar_update_requested(breakdown: Dictionary)  # Flow: after freeze; bar updates then we darken
signal base_score_about_to_show()  # Emitted right before base score; board clears last row yellow
@warning_ignore("unused_signal")
signal row_scoring_done()  # Emitted via emit_signal.bind(); connected in score_effects_layer
signal background_darken_requested()  # Flow: before BASE SCORE, request main to darken background briefly
@warning_ignore("unused_signal")
signal joker_and_chaos_mult_animation_requested(breakdown: Dictionary)  # Flow: after base+retrigger, run joker/chaos mult display
signal multiplier_step_about_to_show(breakdown: Dictionary, step_display_index: int)  # 0=first joker mult, 1=second, ...; last=chaos
signal final_score_displayed(breakdown: Dictionary)  # When final score count-up is done (dark bg is removed on overlay_finished)

@onready var row1_label: Label = $Row1Label
@onready var row2_label: Label = $Row2Label
@onready var row3_label: Label = $Row3Label
@onready var row1_content: HBoxContainer = $Row1Content
@onready var row2_content: HBoxContainer = $Row2Content
@onready var row3_content: HBoxContainer = $Row3Content
@onready var total_label: Label = $TotalLabel
@onready var multiplier_step_label: Label = $MultiplierStepLabel

const TEXT_ASSET_PATH := "res://assets/text/"
const DIGIT_SCALE := 1.0  # Scale factor for digit/word images (1 = native size)

var _digit_textures: Array = []
var _plus_texture: Texture2D
var _minus_texture: Texture2D
var _scores_texture: Texture2D
var _chaos_texture: Texture2D
# Delay after each row's effects (pop + floating number) before resolving next row
const ROW_DELAY_BEFORE_NEXT := 0.12
# Row score appearance: scale 1.0 → 1.12 → 1.0 (winning cards flash yellow right before, per row)
const ROW_SCORE_SCALE_END := 1.12
const ROW_SCORE_SCALE_DURATION := 0.2  # Duration for each of scale-up and scale-down
# Row score: delay before move-up, then move up 30px and fade 100%→0% over 0.35s
const ROW_DELAY_BEFORE_MOVE_UP := 0.5
const FLOATING_POPUP_MOVE_UP_PX := 30
const FLOATING_POPUP_DURATION := 0.35
const ROW_POP_START_SCALE := 0.45    # Legacy; row score now uses 1.0 → ROW_SCORE_SCALE_END
const ROW_POP_SCALE := 1.15
const ROW_POP_UP_DURATION := 0.2
const ROW_POP_DOWN_DURATION := 0.1
const PHASE2_DISPLAY_DURATION := 0.55
const FADE_DURATION := 0.28
# Time final score stays on screen before overlay fades
const FINAL_SCORE_DISPLAY_TIME := 1.5
# Delay before first row score appears (reel stop to first row = this value; 0.1s for fast flow)
const DELAY_BEFORE_FIRST_ROW := 0.1
## Maximum time (seconds) from first row score show to chaos bar + chaos text show (chaos_show_now). Full spin flow except reel.
const MAX_TIME_FROM_ROW1_TO_CHAOS_SHOW := 18.0
# After last row: freeze 0.2s (dark 15% + chaos bar flash), then base score immediately → gap = 0.2s
const FREEZE_AFTER_LAST_ROW := 0.0
# Pause after third row before total count-up (0 = base score right after freeze)
const DELAY_BEFORE_TOTAL := 0.0
# When all row scores are 0, use shorter delays so we reach chaos change sooner
const DELAY_BEFORE_TOTAL_NO_SCORE := 0.2
const PHASE2_DISPLAY_DURATION_NO_SCORE := 0.3
const RETRIGGER_WAIT_TIME_NO_SCORE := 0.1
# When total on grid > 3000, delay showing total by 0.06–0.1s for impact
const BIG_SCORE_DELAY_THRESHOLD := 3000
const BIG_SCORE_DELAY_DURATION := 0.08

# Total: appear at center, count up fast then more and more slowly at end
const TOTAL_COUNT_UP_DURATION := 0.7  # Total time for count-up
const TOTAL_COUNT_UP_FAST_RATIO := 0.22  # First 22% of time: 0 → 85% of value (fast)
const TOTAL_COUNT_UP_END_RATIO := 0.85   # Value ratio reached after fast phase (remaining time: slow crawl to 100%)
const TOTAL_FADE_IN_DURATION := 0.12
# BIG SCORE (legacy): scale pop; final score now uses count-up + bounce
const BIG_SCORE_POP_START_SCALE := 0.6
const BIG_SCORE_POP_PEAK_SCALE := 1.25
const BIG_SCORE_POP_UP_DURATION := 0.18
const BIG_SCORE_SETTLE_DURATION := 0.12

# Final score count-up: value over 0.6–1.0s, scale 1.0→1.15, shake ±2px, then bounce + glow
const FINAL_COUNT_UP_DURATION := 0.85
const FINAL_COUNT_UP_SCALE_END := 1.15
const FINAL_SHAKE_PX := 2.0
const FINAL_SHAKE_STEP_DURATION := 0.06
const FINAL_BOUNCE_UP_DURATION := 0.1
const FINAL_BOUNCE_PEAK_SCALE := 1.28
const FINAL_BOUNCE_SETTLE_SCALE := 1.05
const FINAL_BOUNCE_SETTLE_DURATION := 0.12
const FINAL_BOUNCE_END_DURATION := 0.1
const FINAL_GLOW_COLOR := Color(1.12, 1.08, 0.95, 1.0)
const FINAL_GLOW_DURATION := 0.25

# Big score impact: size (1.3–1.5x), glow/bloom spike
const TOTAL_SCORE_SIZE_MULT := 1.4
const GLOW_SPIKE_DURATION := 0.25
const BLOOM_SPIKE_DURATION := 0.12
const GLOW_COLOR := Color(1.5, 1.5, 1.35, 1.0)
const BLOOM_COLOR := Color(1.9, 1.9, 1.6, 1.0)

var _grid_size: Vector2 = Vector2.ZERO
var _grid_center_x: float = 0.0  # Grid center X in overlay-local (for row score)
var _grid_center_global_x: float = 0.0  # Board center X in global; used when re-applying
var _screen_center_for_total: Vector2 = Vector2.ZERO  # Screen center (overlay-local) for total, final score
var _row_center_ys: Array = []  # Overlay-local Y of each row center (from board); used to re-apply row score position
var _breakdown: Dictionary = {}
# Used by total count-up tween
var _count_up_total: int = 0
var _count_up_center_x: float = 0.0
var _count_up_digit_h: float = 0.0
var _count_up_word_h: float = 0.0
# Retrigger phase: after first total shown, game may send retrigger_breakdown for second count-up
var _pending_retrigger_breakdown: Dictionary = {}
var _first_total_value: int = 0  # Total displayed before retrigger; second count-up starts from this
var _is_no_score: bool = false  # True when total and all row scores are 0; use shorter delays
var _phase2_center_x: float = 0.0
var _phase2_total: int = 0
var _phase2_total_digit_h: float = 0.0
var _phase2_total_word_h: float = 0.0
const RETRIGGER_WAIT_TIME := 0.25
## Extra time to show total (first + retrigger) before fading
const RETRIGGER_TOTAL_HOLD := 0.4
# Duration per step when counting up through joker steps (one by one)
const PER_STEP_COUNT_UP_DURATION := 0.5
# Hold multiplier (joker name / chaos) text at center for 1s total; then count-up 0.5s then 0.5s delay
const MULTIPLIER_TEXT_HOLD := 1.0
# Joker bonus: show "JOKER BONUS", then instant impact (no slow count-up)
const JOKER_BONUS_HOLD := 0.4
const JOKER_IMPACT_SHAKE_PX := 12.0
const JOKER_IMPACT_SHAKE_DURATION := 0.08
const JOKER_IMPACT_SHAKE_CYCLES := 2
const JOKER_IMPACT_FLASH_DURATION := 0.22
const JOKER_IMPACT_PULSE_SCALE := 1.14
const JOKER_IMPACT_GOLD := Color(1.2, 0.92, 0.35, 1.0)
const JOKER_LIGHT_BURST_ALPHA := 0.5
const JOKER_LIGHT_BURST_DURATION := 0.28
# Chaos multiplier step: score emphasis (scale 1.0 → 1.2, shake ±6px)
const CHAOS_STEP_SHAKE_PX := 6.0
const CHAOS_STEP_SCALE_PEAK := 1.2
const CHAOS_STEP_SCALE_DURATION := 0.15
const CHAOS_STEP_SHAKE_DURATION := 0.06
const CHAOS_STEP_SHAKE_CYCLES := 3
# Delay after each count-up before next multiplier text
const DELAY_AFTER_COUNT_UP := 0.5

# Win tier by final score: T1 <3k, T2 3k–7k, T3 7k–11k, T4 >11k
const WIN_TIER_T2 := 3000
const WIN_TIER_T3 := 7000
const WIN_TIER_T4 := 11000
# Scale: fast grow 0.12–0.18s, slight bounce back
const WIN_GROW_DURATION := 0.15
const WIN_BOUNCE_DURATION := 0.2
const WIN_T1_SCALE := 1.15   # Ivory, small pop
const WIN_T2_SCALE := 1.3   # Gold, bigger
const WIN_T3_SCALE := 1.5   # Orange, strong
const WIN_T4_SCALE := 1.8   # Gold-orange, + overshoot
const WIN_T4_OVERSHOOT := 1.95
const WIN_T1_COLOR := Color(1.0, 1.0, 0.941, 1.0)      # #FFFFF0 Ivory
const WIN_T2_COLOR := Color(0.96, 0.78, 0.42, 1.0)     # #F5C76B Gold
const WIN_T3_COLOR := Color(1.0, 0.663, 0.302, 1.0)    # #FFA94D Orange
const WIN_T4_COLOR := Color(1.0, 0.353, 0.165, 1.0)    # #FF5A2A Gold-orange


func _load_text_assets() -> void:
	if not _digit_textures.is_empty():
		return
	for i in range(10):
		var tex: Texture2D = load(TEXT_ASSET_PATH + str(i) + ".png") as Texture2D
		_digit_textures.append(tex if tex else null)
	_plus_texture = load(TEXT_ASSET_PATH + "plus.png") as Texture2D
	_minus_texture = load(TEXT_ASSET_PATH + "minus.png") as Texture2D
	_scores_texture = load(TEXT_ASSET_PATH + "scores.png") as Texture2D
	_chaos_texture = load(TEXT_ASSET_PATH + "chaos.png") as Texture2D


func _clear_content(cont: HBoxContainer) -> void:
	if cont == null:
		return
	for c in cont.get_children():
		cont.remove_child(c)
		c.queue_free()

## Set one row content's position: X = grid center, Y = row center (from board).
func _apply_row_content_position(content: Control, row_index: int, row_h: float) -> void:
	if content == null:
		return
	var pos_y: float = float(row_index) * row_h
	if row_index >= 0 and row_index < _row_center_ys.size():
		pos_y = float(_row_center_ys[row_index]) - row_h * 0.5
	var pos_x: float = _grid_center_x - content.size.x * 0.5
	content.position = Vector2(pos_x, pos_y)

## Re-apply row score positions (call deferred so overlay layout is stable).
func _apply_all_row_score_positions() -> void:
	if _grid_size.y <= 0:
		return
	_grid_center_x = _grid_center_global_x - get_global_rect().position.x
	var row_h: float = _grid_size.y / 3.0
	var row_contents: Array[HBoxContainer] = [row1_content, row2_content, row3_content]
	for i in range(3):
		var content: HBoxContainer = row_contents[i] if i < row_contents.size() else null
		if content != null:
			content.set("layout_mode", 0)  # LAYOUT_MODE_POSITION (Control.LayoutMode not in API)
			var min_sz: Vector2 = content.get_combined_minimum_size()
			content.size = Vector2(min_sz.x, row_h)
			content.pivot_offset = Vector2(content.size.x * 0.5, row_h * 0.5)
			_apply_row_content_position(content, i, row_h)


func _format_score_text(value: int) -> String:
	var s: String = str(abs(value))
	var sign_str: String = "+" if value >= 0 else "-"
	var grouped: String = ""
	var i: int = s.length() - 1
	var count: int = 0
	while i >= 0:
		if count > 0 and count % 3 == 0:
			grouped = "," + grouped
		grouped = s.substr(i, 1) + grouped
		count += 1
		i -= 1
	return sign_str + grouped

func _count_up_update_total_display(v: float) -> void:
	var n: int = clampi(int(round(v)), 0, _count_up_total)
	_set_total_score_text(n)

func _set_total_score_text(value: int, _at_screen_center: bool = false) -> void:
	if total_label == null:
		return
	total_label.text = _format_score_text(value)
	total_label.visible = true
	# All total/base/NO SCORE text at screen center (same as final score)
	_position_total_at_screen_center()

func _position_total_at_screen_center() -> void:
	if total_label == null:
		return
	total_label.set_anchors_preset(Control.PRESET_TOP_LEFT, true)
	total_label.reset_size()
	var sz: Vector2 = total_label.get_combined_minimum_size()
	total_label.position = _screen_center_for_total - sz * 0.5
	total_label.size = sz

## Position total label at screen center (used for base score, total, NO SCORE, multiplier text, final score).
func _position_total_at_grid_center() -> void:
	_position_total_at_screen_center()

func _prepare_big_score_pop() -> void:
	if total_label == null:
		return
	total_label.reset_size()
	var sz: Vector2 = total_label.get_combined_minimum_size()
	total_label.pivot_offset = sz * 0.5
	total_label.position = _screen_center_for_total - sz * 0.5
	total_label.size = sz
	total_label.scale = Vector2(BIG_SCORE_POP_START_SCALE, BIG_SCORE_POP_START_SCALE)

func _reset_total_label_pivot_after_pop() -> void:
	if total_label != null:
		total_label.pivot_offset = Vector2.ZERO
		total_label.scale = Vector2.ONE

func _trigger_final_score_pop(final_val: int) -> void:
	if total_label == null:
		return
	total_label.visible = true
	_set_total_score_text(final_val)
	_prepare_big_score_pop()

## Prepare for final score count-up: screen center, start at 0, scale 1.0, pivot for scaling.
func _prepare_final_score_count_up(_final_val: int) -> void:
	if total_label == null:
		return
	total_label.reset_size()
	var sz: Vector2 = total_label.get_combined_minimum_size()
	total_label.pivot_offset = sz * 0.5
	total_label.position = _screen_center_for_total - sz * 0.5
	total_label.size = sz
	total_label.scale = Vector2.ONE
	total_label.modulate = Color.WHITE
	_set_total_score_text(0, true)

## Update display during final score count-up (keeps label at screen center).
func _final_score_count_up_update(v: float) -> void:
	var n: int = clampi(int(round(v)), 0, 999999999)
	_set_total_score_text(n, true)

## Continuous subtle shake during final count-up: t 0..1 maps to ±2px.
func _final_score_shake_update(t: float) -> void:
	if total_label == null:
		return
	var label_w: float = total_label.get_combined_minimum_size().x
	var base_x: float = _screen_center_for_total.x - label_w * 0.5
	total_label.position.x = base_x + FINAL_SHAKE_PX * sin(t * 40.0)

## Finish bounce 1.15 → 1.28 → 1.05 → 1.0 and soft glow.
func _finish_final_score_bounce_and_glow() -> void:
	if total_label == null:
		return
	total_label.reset_size()
	var sz: Vector2 = total_label.get_combined_minimum_size()
	total_label.position = _screen_center_for_total - sz * 0.5
	total_label.size = sz
	var peak := Vector2(FINAL_BOUNCE_PEAK_SCALE, FINAL_BOUNCE_PEAK_SCALE)
	var settle := Vector2(FINAL_BOUNCE_SETTLE_SCALE, FINAL_BOUNCE_SETTLE_SCALE)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(
		total_label, "scale", peak, FINAL_BOUNCE_UP_DURATION
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(
		total_label, "modulate", FINAL_GLOW_COLOR, FINAL_GLOW_DURATION * 0.5
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.set_parallel(false)
	tw.tween_property(
		total_label, "scale", settle, FINAL_BOUNCE_SETTLE_DURATION
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(
		total_label, "scale", Vector2.ONE, FINAL_BOUNCE_END_DURATION
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(
		total_label, "modulate", Color.WHITE, FINAL_GLOW_DURATION * 0.5
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(func() -> void:
		if is_instance_valid(total_label):
			total_label.scale = Vector2.ONE
			total_label.pivot_offset = Vector2.ZERO
	)

func _apply_final_total_display(
	_center_x_val: float, total_val: int, _digit_h: float, _word_h: float
) -> void:
	_set_total_score_text(total_val)

func _get_win_tier(final_score: int) -> int:
	if final_score >= WIN_TIER_T4:
		return 4
	if final_score >= WIN_TIER_T3:
		return 3
	if final_score >= WIN_TIER_T2:
		return 2
	return 1

func _get_win_tier_color(tier: int) -> Color:
	if tier >= 4:
		return WIN_T4_COLOR
	if tier >= 3:
		return WIN_T3_COLOR
	if tier >= 2:
		return WIN_T2_COLOR
	return WIN_T1_COLOR

func _apply_win_tier_effects(breakdown: Dictionary) -> void:
	if total_label == null:
		return
	var score_data: Dictionary = breakdown.get("score", {})
	var final_score: int = int(score_data.get("final_score", 0))
	var tier: int = _get_win_tier(final_score)
	var peak_scale: float = WIN_T1_SCALE
	if tier >= 4:
		peak_scale = WIN_T4_SCALE
	elif tier >= 3:
		peak_scale = WIN_T3_SCALE
	elif tier >= 2:
		peak_scale = WIN_T2_SCALE
	var tier_color: Color = _get_win_tier_color(tier)
	total_label.pivot_offset = total_label.size * 0.5
	var tw: Tween = create_tween()
	# Fast grow (0.12–0.18s) + tier color/glow
	tw.set_parallel(true)
	tw.tween_property(
		total_label, "scale", Vector2(peak_scale, peak_scale), WIN_GROW_DURATION
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(total_label, "modulate", tier_color, WIN_GROW_DURATION)
	# T4: overshoot then bounce back; others: slight bounce back to 1.0
	if tier >= 4:
		tw.chain().tween_property(
			total_label, "scale", Vector2(WIN_T4_OVERSHOOT, WIN_T4_OVERSHOOT), 0.08
		).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(
			total_label, "scale", Vector2.ONE, WIN_BOUNCE_DURATION
		).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		tw.chain().tween_property(
			total_label, "scale", Vector2.ONE, WIN_BOUNCE_DURATION
		).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# T3 only: double pulse (second small pulse after first settle)
	if tier == 3:
		tw.tween_property(
			total_label, "scale", Vector2(WIN_T3_SCALE * 0.92, WIN_T3_SCALE * 0.92), 0.1
		).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(
			total_label, "scale", Vector2.ONE, 0.15
		).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(total_label, "modulate", Color.WHITE, 0.5)
	tw.tween_callback(func() -> void:
		if is_instance_valid(total_label):
			total_label.scale = Vector2.ONE
			total_label.pivot_offset = Vector2.ZERO
	)
	# T2: ghost trail – brief duplicate label behind, fades out
	if tier >= 2 and multiplier_step_label != null:
		var ghost: Label = Label.new()
		ghost.text = total_label.text
		ghost.add_theme_color_override("font_color", tier_color)
		if total_label.get_theme_font_size("font_size") > 0:
			ghost.add_theme_font_size_override("font_size", total_label.get_theme_font_size("font_size"))
		ghost.position = total_label.position + Vector2(-3, 2)
		ghost.modulate = Color(1, 1, 1, 0.35)
		ghost.z_index = total_label.z_index - 1
		total_label.get_parent().add_child(ghost)
		var gt: Tween = create_tween()
		gt.tween_property(ghost, "modulate:a", 0.0, 0.4)
		gt.tween_callback(ghost.queue_free)

## Build display steps: [base], [base+retrigger if any], then after each joker multiplier, then +chaos, ending at final_score. Order matches game: base (× mults) + chaos.
func _build_score_steps(score_dict: Dictionary, chaos_after: int, retrigger_added: int, final_score: int) -> Array:
	var steps: Array = []
	var base_display: int = int(score_dict.get("base_score", 0))
	steps.append(base_display)
	var running: float = float(base_display)
	if retrigger_added > 0:
		running += float(retrigger_added)
		steps.append(int(running))
	var multipliers: Array = score_dict.get("multipliers", [])
	for mult_entry in multipliers:
		var m: float = float(mult_entry.get("multiplier", 1.0))
		if m <= 1.0:
			continue
		running = round(running * m)
		steps.append(int(running))
	var chaos_bonus: float = running * (float(chaos_after) / 100.0)
	running = round(running + chaos_bonus)
	steps.append(int(running))
	if steps.size() > 0 and final_score != steps[-1]:
		steps[-1] = final_score
	return steps


func _build_value_row(content: HBoxContainer, value: int, _word_texture: Texture2D, digit_height: float, _word_height: float) -> void:
	if content == null:
		return
	_clear_content(content)
	var label := Label.new()
	label.text = _format_score_text(value)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.add_theme_font_size_override(
		"font_size", int(digit_height * 0.85)
	)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override(
		"font_outline_color", Color.BLACK
	)
	label.add_theme_constant_override("outline_size", 4)
	content.add_child(label)


func setup_from_breakdown(
	breakdown: Dictionary, grid_rect: Rect2 = Rect2(), container_size: Vector2 = Vector2.ZERO,
	overlay_position_in_container: Vector2 = Vector2.ZERO, row_center_ys: Array = []
) -> void:
	_breakdown = breakdown
	# Keep explicit size so TotalLabel center = grid center (second row)
	set("layout_mode", 0)  # LAYOUT_MODE_POSITION (Control.LayoutMode not in API)
	if grid_rect != Rect2():
		_grid_size = grid_rect.size
		_grid_center_global_x = grid_rect.position.x + grid_rect.size.x * 0.5
		_grid_center_x = _grid_center_global_x - get_global_rect().position.x
	else:
		_grid_size = size
		_grid_center_global_x = get_global_rect().position.x + _grid_size.x * 0.5
		_grid_center_x = _grid_size.x * 0.5
	# row_center_ys (when size >= 3): overlay-local Y of each row center, from board
	# Final score at screen center (overlay-local): container center minus overlay offset
	if container_size.x > 0 and container_size.y > 0:
		_screen_center_for_total = Vector2(
			container_size.x * 0.5 - overlay_position_in_container.x,
			container_size.y * 0.5 - overlay_position_in_container.y
		)
	else:
		_screen_center_for_total = _grid_size * 0.5

	var score_data: Dictionary = breakdown.get("score", {})
	if score_data == null:
		score_data = {}
	var chaos_data: Dictionary = breakdown.get("chaos", {})
	if chaos_data == null:
		chaos_data = {}

	var row_scores_arr: Array = []
	var row_hands = score_data.get("row_hands", [])
	for row_data in row_hands:
		if row_data is Dictionary and row_data.has("score"):
			row_scores_arr.append(int(row_data["score"]))
	while row_scores_arr.size() < 3:
		row_scores_arr.append(0)
	# BASE SCORE = sum of row scores only (no chaos bonus, no joker multipliers)
	var total: int = 0
	for i in range(row_scores_arr.size()):
		total += int(row_scores_arr[i]) if i < row_scores_arr.size() else 0
	_first_total_value = total
	_is_no_score = (total == 0)
	var _chaos_net: int = int(chaos_data.get("net_change", 0))  # Chaos change shown on bar only

	var center_x: float = _grid_size.x * 0.5
	var row_h: float = _grid_size.y / 3.0
	const ROW_DIGIT_H: float = 72.0
	const ROW_WORD_H: float = 48.0
	# Row center Y in overlay-local space (from board); if not provided, use equal thirds
	_row_center_ys.clear()
	for i in range(row_center_ys.size()):
		_row_center_ys.append(float(row_center_ys[i]))

	# Phase 1: build row scores; each row score centered on that row
	_load_text_assets()
	var row_contents: Array[HBoxContainer] = [row1_content, row2_content, row3_content]
	for i in range(3):
		var score_val: int = int(row_scores_arr[i]) if i < row_scores_arr.size() else 0
		var content: HBoxContainer = row_contents[i] if i < row_contents.size() else null
		if content != null:
			_build_value_row(content, score_val, _scores_texture, ROW_DIGIT_H, ROW_WORD_H)
			content.visible = (score_val != 0)
			content.modulate.a = 0.0
			content.scale = Vector2(1.0, 1.0)
			# Use explicit position/size; width = content min so we can center the block on grid
			content.set("layout_mode", 0)  # LAYOUT_MODE_POSITION (Control.LayoutMode not in API)
			var min_sz: Vector2 = content.get_combined_minimum_size()
			content.size = Vector2(min_sz.x, row_h)
			content.pivot_offset = Vector2(content.size.x * 0.5, row_h * 0.5)
			content.alignment = BoxContainer.ALIGNMENT_CENTER
			_apply_row_content_position(content, i, row_h)
		if is_instance_valid(row1_label) and i == 0:
			row1_label.visible = false
		if is_instance_valid(row2_label) and i == 1:
			row2_label.visible = false
		if is_instance_valid(row3_label) and i == 2:
			row3_label.visible = false
	# Re-apply row positions next frame so they stick after layout is stable
	call_deferred("_apply_all_row_score_positions")

	# Phase 1: row 1 → row 2 → row 3; each row score pops up on that row (left to right order)
	var phase1_tween := create_tween()
	phase1_tween.tween_interval(DELAY_BEFORE_FIRST_ROW - 0.1)
	phase1_tween.tween_callback(emit_signal.bind("first_row_about_to_show"))
	phase1_tween.tween_interval(0.1)
	for i in range(3):
		var score_val: int = int(row_scores_arr[i]) if i < row_scores_arr.size() else 0
		if score_val == 0:
			continue
		var content: HBoxContainer = row_contents[i] if i < row_contents.size() else null
		if content == null:
			continue
		# 1) Yellow win flash (right before row score)
		phase1_tween.tween_callback(emit_signal.bind("row_score_about_to_show", i))
		# 2) Row score pop: scale 1.0 → 1.12 → 1.0
		phase1_tween.tween_callback(_play_row_score_for_value.bind(score_val))
		phase1_tween.set_parallel(true)
		phase1_tween.tween_property(
			content, "scale", Vector2(ROW_SCORE_SCALE_END, ROW_SCORE_SCALE_END),
			ROW_SCORE_SCALE_DURATION
		).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		phase1_tween.tween_property(content, "modulate:a", 1.0, ROW_SCORE_SCALE_DURATION)
		phase1_tween.set_parallel(false)
		phase1_tween.tween_property(
			content, "scale", Vector2(1.0, 1.0), ROW_SCORE_SCALE_DURATION
		).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
		# 3) Delay 0.5s, then move up 30px and fade 100%→0% over 0.35s, then hide
		phase1_tween.tween_interval(ROW_DELAY_BEFORE_MOVE_UP)
		var pos_y_start: float = content.position.y
		phase1_tween.set_parallel(true)
		phase1_tween.tween_property(
			content, "position:y",
			pos_y_start - FLOATING_POPUP_MOVE_UP_PX, FLOATING_POPUP_DURATION
		).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		phase1_tween.tween_property(
			content, "modulate:a", 0.0, FLOATING_POPUP_DURATION
		).set_trans(Tween.TRANS_LINEAR)
		phase1_tween.set_parallel(false)
		phase1_tween.tween_callback(_hide_row_content.bind(content))
		# 4) Delay before next row
		phase1_tween.tween_interval(ROW_DELAY_BEFORE_NEXT)
	# After last row: freeze 0.2s → dark overlay 15% + chaos bar flash 0.25s → then base score (big reveal)
	_phase2_center_x = center_x
	_phase2_total = total
	const TOTAL_DIGIT_H_BASE: float = 120.0
	const TOTAL_WORD_H_BASE: float = 80.0
	_phase2_total_digit_h = TOTAL_DIGIT_H_BASE * TOTAL_SCORE_SIZE_MULT
	_phase2_total_word_h = TOTAL_WORD_H_BASE * TOTAL_SCORE_SIZE_MULT
	phase1_tween.tween_interval(FREEZE_AFTER_LAST_ROW)
	phase1_tween.tween_callback(emit_signal.bind("row_scoring_done"))
	phase1_tween.tween_callback(continue_after_chaos_bar)


func _play_row_score_for_value(row_score: int) -> void:
	var sm = get_node_or_null("/root/SfxManager")
	if sm:
		sm.play_row_score_by_level(row_score)

func _play_counting_score_once() -> void:
	var sm = get_node_or_null("/root/SfxManager")
	if sm:
		sm.play_counting_score()

func _stop_counting_score_callback() -> void:
	var sm = get_node_or_null("/root/SfxManager")
	if sm:
		sm.stop_counting_score()

func _emit_total_displayed() -> void:
	var sm = get_node_or_null("/root/SfxManager")
	if sm:
		sm.stop_counting_score()
	total_score_displayed.emit(_breakdown)

func _emit_chaos_bar_update_requested() -> void:
	chaos_bar_update_requested.emit(_breakdown)

## Called when chaos bar has finished updating; then we darken and show BASE SCORE.
func continue_after_chaos_bar() -> void:
	# Clear last row's yellow glow before base score appears
	emit_signal("base_score_about_to_show")
	background_darken_requested.emit()
	var delay_before_total: float = (
		DELAY_BEFORE_TOTAL_NO_SCORE if _is_no_score else float(DELAY_BEFORE_TOTAL)
	)
	var tween := create_tween()
	tween.tween_interval(delay_before_total)
	tween.tween_callback(_hide_row_labels)
	tween.tween_interval(FADE_DURATION)
	# Phase 2: base score at center (or "NO SCORE" when base is 0 — no multipliers)
	_load_text_assets()
	total_label.modulate = Color(BLOOM_COLOR.r, BLOOM_COLOR.g, BLOOM_COLOR.b, 0.0)
	if _phase2_total != 0:
		total_label.visible = true
		_set_total_score_text(0)
		_count_up_total = _phase2_total
		_count_up_center_x = _phase2_center_x
		_count_up_digit_h = _phase2_total_digit_h
		_count_up_word_h = _phase2_total_word_h
		if _phase2_total > BIG_SCORE_DELAY_THRESHOLD:
			tween.tween_interval(BIG_SCORE_DELAY_DURATION)
		tween.tween_callback(_position_total_at_grid_center)
		tween.set_parallel(true)
		tween.tween_property(total_label, "modulate:a", 1.0, TOTAL_FADE_IN_DURATION)
		tween.set_parallel(false)
		tween.tween_callback(_play_counting_score_once)
		var fast_duration: float = TOTAL_COUNT_UP_DURATION * TOTAL_COUNT_UP_FAST_RATIO
		var slow_duration: float = TOTAL_COUNT_UP_DURATION * (1.0 - TOTAL_COUNT_UP_FAST_RATIO)
		var value_after_fast: float = float(_phase2_total) * TOTAL_COUNT_UP_END_RATIO
		tween.tween_method(
			_count_up_update_total_display, 0.0, value_after_fast, fast_duration
		).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_method(
			_count_up_update_total_display, value_after_fast, float(_phase2_total), slow_duration
		).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		tween.tween_callback(_apply_final_total_display.bind(
			_phase2_center_x, _phase2_total, _phase2_total_digit_h, _phase2_total_word_h
		))
		tween.tween_property(
			total_label, "modulate", Color(GLOW_COLOR.r, GLOW_COLOR.g, GLOW_COLOR.b, 1.0),
			BLOOM_SPIKE_DURATION
		).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(
			total_label, "modulate", Color.WHITE, GLOW_SPIKE_DURATION
		).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	else:
		tween.tween_callback(_show_no_score_text)
		tween.tween_callback(_position_total_at_grid_center)
		tween.tween_property(total_label, "modulate:a", 1.0, TOTAL_FADE_IN_DURATION)
	tween.tween_callback(_emit_total_displayed)
	var retrigger_wait: float = (
		RETRIGGER_WAIT_TIME_NO_SCORE if _is_no_score else RETRIGGER_WAIT_TIME
	)
	tween.tween_interval(retrigger_wait)
	tween.tween_callback(_check_retrigger_and_continue)

func _get_multiplier_step_text(breakdown: Dictionary, step_display_index: int) -> String:
	var score_data: Dictionary = breakdown.get("score", {})
	var multipliers: Array = score_data.get("multipliers", []) if score_data else []
	var chaos_data: Dictionary = breakdown.get("chaos", {})
	chaos_data = chaos_data if chaos_data else {}
	if step_display_index < multipliers.size():
		return "JOKER BONUS"
	return "× Chaos Multiplier"

## Position multiplier (chaos/joker) label at screen center, same as total label.
func _position_multiplier_label_at_screen_center() -> void:
	if multiplier_step_label == null:
		return
	multiplier_step_label.set_anchors_preset(Control.PRESET_TOP_LEFT, true)
	multiplier_step_label.reset_size()
	var sz: Vector2 = multiplier_step_label.get_combined_minimum_size()
	multiplier_step_label.position = _screen_center_for_total - sz * 0.5
	multiplier_step_label.size = sz

## Hide total score and show multiplier text at screen center. Emit for joker flash.
func _hide_total_show_multiplier_text(breakdown: Dictionary, step_display_index: int) -> void:
	if total_label != null:
		total_label.visible = false
	var text: String = _get_multiplier_step_text(breakdown, step_display_index)
	if multiplier_step_label != null:
		multiplier_step_label.text = text
		multiplier_step_label.visible = not text.is_empty()
		if multiplier_step_label.visible:
			_position_multiplier_label_at_screen_center()
	emit_signal("multiplier_step_about_to_show", breakdown, step_display_index)

## Hide multiplier text and show total score again at given value (before count-up). Keeps total on second row.
func _hide_multiplier_show_total_at(total_val: int) -> void:
	if multiplier_step_label != null:
		multiplier_step_label.visible = false
	_position_total_at_grid_center()
	_apply_final_total_display(_count_up_center_x, total_val, _count_up_digit_h, _count_up_word_h)

## Joker bonus impact: show score at to_val instantly, shake, golden light burst, flash/pulse on score (no count-up).
func _apply_joker_bonus_impact(to_val: int) -> void:
	if multiplier_step_label != null:
		multiplier_step_label.visible = false
	_position_total_at_grid_center()
	_apply_final_total_display(_count_up_center_x, to_val, _count_up_digit_h, _count_up_word_h)
	if total_label == null:
		return
	total_label.visible = true
	var orig_pos: Vector2 = total_label.position
	var orig_mod: Color = total_label.modulate
	var orig_scale: Vector2 = total_label.scale
	# Shake: multiple left-right cycles for visible impact
	var shake_tween := create_tween()
	for cycle in range(JOKER_IMPACT_SHAKE_CYCLES):
		shake_tween.tween_property(
			total_label, "position:x", orig_pos.x + JOKER_IMPACT_SHAKE_PX, JOKER_IMPACT_SHAKE_DURATION
		).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		shake_tween.tween_property(
			total_label, "position:x", orig_pos.x - JOKER_IMPACT_SHAKE_PX,
			JOKER_IMPACT_SHAKE_DURATION * 2.0
		).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	shake_tween.tween_property(
		total_label, "position:x", orig_pos.x, JOKER_IMPACT_SHAKE_DURATION
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	shake_tween.tween_callback(func() -> void:
		if total_label != null:
			total_label.position = orig_pos
	)
	# Quick golden flash + scale pulse on score
	var flash_tween := create_tween()
	flash_tween.set_parallel(true)
	flash_tween.tween_property(
		total_label, "modulate", JOKER_IMPACT_GOLD, JOKER_IMPACT_FLASH_DURATION * 0.4
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	flash_tween.tween_property(
		total_label, "scale", orig_scale * JOKER_IMPACT_PULSE_SCALE,
		JOKER_IMPACT_FLASH_DURATION * 0.4
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	flash_tween.set_parallel(false)
	flash_tween.tween_property(
		total_label, "modulate", orig_mod, JOKER_IMPACT_FLASH_DURATION * 0.6
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	flash_tween.parallel().tween_property(
		total_label, "scale", orig_scale, JOKER_IMPACT_FLASH_DURATION * 0.6
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Golden light burst (full overlay flash)
	_spawn_joker_light_burst()

## Chaos step: score emphasis — scale 1.0→1.2→1.0 and shake ±6px.
func _apply_chaos_step_impact(to_val: int) -> void:
	if multiplier_step_label != null:
		multiplier_step_label.visible = false
	_position_total_at_grid_center()
	_apply_final_total_display(_count_up_center_x, to_val, _count_up_digit_h, _count_up_word_h)
	if total_label == null:
		return
	total_label.visible = true
	var orig_pos: Vector2 = total_label.position
	var orig_scale: Vector2 = total_label.scale
	# Shake ±6px (stronger emphasis)
	var shake_tween := create_tween()
	for cycle in range(CHAOS_STEP_SHAKE_CYCLES):
		shake_tween.tween_property(
			total_label, "position:x", orig_pos.x + CHAOS_STEP_SHAKE_PX, CHAOS_STEP_SHAKE_DURATION
		).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		shake_tween.tween_property(
			total_label, "position:x", orig_pos.x - CHAOS_STEP_SHAKE_PX,
			CHAOS_STEP_SHAKE_DURATION * 2.0
		).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	shake_tween.tween_property(
		total_label, "position:x", orig_pos.x, CHAOS_STEP_SHAKE_DURATION
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	shake_tween.tween_callback(func() -> void:
		if total_label != null:
			total_label.position = orig_pos
	)
	# Score scale 1.0 → 1.2 → 1.0
	var scale_tween := create_tween()
	scale_tween.tween_property(
		total_label, "scale", orig_scale * CHAOS_STEP_SCALE_PEAK, CHAOS_STEP_SCALE_DURATION
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	scale_tween.tween_property(
		total_label, "scale", orig_scale, CHAOS_STEP_SCALE_DURATION
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _spawn_joker_light_burst() -> void:
	var burst := ColorRect.new()
	burst.name = "JokerLightBurst"
	burst.color = Color(JOKER_IMPACT_GOLD.r, JOKER_IMPACT_GOLD.g, JOKER_IMPACT_GOLD.b, 0.0)
	burst.set_anchors_preset(Control.PRESET_FULL_RECT)
	burst.set_offsets_preset(Control.PRESET_FULL_RECT)
	burst.mouse_filter = Control.MOUSE_FILTER_IGNORE
	burst.z_index = 50
	add_child(burst)
	var peak_color := Color(
		JOKER_IMPACT_GOLD.r, JOKER_IMPACT_GOLD.g, JOKER_IMPACT_GOLD.b, JOKER_LIGHT_BURST_ALPHA
	)
	var end_color := Color(JOKER_IMPACT_GOLD.r, JOKER_IMPACT_GOLD.g, JOKER_IMPACT_GOLD.b, 0.0)
	var t := create_tween()
	t.tween_property(
		burst, "color", peak_color, JOKER_LIGHT_BURST_DURATION * 0.35
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(
		burst, "color", end_color, JOKER_LIGHT_BURST_DURATION * 0.65
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	t.tween_callback(burst.queue_free)

func _hide_center_multiplier_label() -> void:
	if multiplier_step_label != null:
		multiplier_step_label.visible = false

## Show "NO SCORE" at center (base score is 0); no multiplier steps.
func _show_no_score_text() -> void:
	if total_label != null:
		total_label.text = "NO SCORE"
		total_label.visible = true
		_position_total_at_grid_center()

func _emit_chaos_show_now(breakdown: Dictionary) -> void:
	chaos_show_now.emit(breakdown)

func receive_retrigger_breakdown(breakdown: Dictionary) -> void:
	_pending_retrigger_breakdown = breakdown

func _check_retrigger_and_continue() -> void:
	# Base score 0: show only "NO SCORE", no multiplier steps — hold then fade
	if _first_total_value == 0:
		var no_score_tween := create_tween()
		no_score_tween.tween_callback(_hide_center_multiplier_label)
		no_score_tween.tween_callback(func() -> void: emit_signal("final_score_displayed", _breakdown))
		no_score_tween.tween_callback(_emit_chaos_show_now.bind(_breakdown))
		no_score_tween.tween_interval(PHASE2_DISPLAY_DURATION_NO_SCORE)
		no_score_tween.tween_property(self, "modulate:a", 0.0, FADE_DURATION)
		no_score_tween.tween_callback(_on_overlay_finished)
		return
	# Flow: base score already shown → retrigger image (game shows on total_score_displayed) → base+retrigger count-up → joker mult anim → (base+retrigger)*mults count-up → chaos show → fade
	if not _pending_retrigger_breakdown.is_empty():
		var first_total: int = _first_total_value  # Base score (sum of rows)
		var retrigger_score: Dictionary = _pending_retrigger_breakdown.get("score", {})
		var retrigger_added: int = int(retrigger_score.get("retrigger_added", 0))
		var second_total: int = first_total + retrigger_added  # Base + retrigger (pre-mult)
		if second_total <= first_total:
			second_total = int(retrigger_score.get("final_score", first_total))
		var final_score: int = int(retrigger_score.get("final_score", second_total))  # (base+retrigger)*joker*chaos
		var breakdown_to_emit: Dictionary = _pending_retrigger_breakdown
		_pending_retrigger_breakdown = {}
		if second_total > first_total:
			_count_up_total = second_total
			_apply_final_total_display(_count_up_center_x, first_total, _count_up_digit_h, _count_up_word_h)
			var sm_retrigger = get_node_or_null("/root/SfxManager")
			if sm_retrigger:
				sm_retrigger.play_retrigger()
				sm_retrigger.play_counting_score_for_retrigger()
			var count_up_tween := create_tween()
			# 1) Count up: base → base+retrigger
			count_up_tween.tween_method(
				_count_up_update_total_display, float(first_total), float(second_total),
				TOTAL_COUNT_UP_DURATION
			).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			count_up_tween.tween_callback(_apply_final_total_display.bind(
				_count_up_center_x, second_total, _count_up_digit_h, _count_up_word_h
			))
			count_up_tween.tween_callback(_stop_counting_score_callback)
			# 1.5) Delay 0.5s before calculated (joker/chaos) score steps
			count_up_tween.tween_interval(0.5)
			# 2) Count up through joker steps one by one: show each multiplier then count up
			var rt_chaos_data: Dictionary = breakdown_to_emit.get("chaos", {})
			var rt_chaos_after: int = int(rt_chaos_data.get("chaos_after", 0))
			var rt_steps: Array = _build_score_steps(retrigger_score, rt_chaos_after, retrigger_added, final_score)
			var rt_mults: Array = retrigger_score.get("multipliers", [])
			for i in range(1, rt_steps.size() - 1):
				var from_val: int = int(rt_steps[i])
				var to_val: int = int(rt_steps[i + 1])
				var step_idx: int = i - 1
				var is_chaos_step: bool = (step_idx >= rt_mults.size())
				# Skip only if joker step with no score change; always show Chaos Multiplier text before applying chaos
				if to_val <= from_val and not is_chaos_step:
					continue
				_count_up_total = to_val
				count_up_tween.tween_callback(
					_hide_total_show_multiplier_text.bind(breakdown_to_emit, step_idx)
				)
				if is_chaos_step:
					count_up_tween.tween_interval(MULTIPLIER_TEXT_HOLD)
					if to_val > from_val:
						count_up_tween.tween_callback(_play_counting_score_once)
						count_up_tween.tween_callback(_hide_multiplier_show_total_at.bind(from_val))
						count_up_tween.tween_method(
							_count_up_update_total_display, float(from_val), float(to_val),
							PER_STEP_COUNT_UP_DURATION
						).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
						count_up_tween.tween_callback(_apply_chaos_step_impact.bind(to_val))
						count_up_tween.tween_callback(_stop_counting_score_callback)
						count_up_tween.tween_interval(DELAY_AFTER_COUNT_UP)
					else:
						count_up_tween.tween_callback(_hide_multiplier_show_total_at.bind(from_val))
						count_up_tween.tween_callback(_apply_chaos_step_impact.bind(to_val))
						count_up_tween.tween_interval(DELAY_AFTER_COUNT_UP)
				else:
					count_up_tween.tween_interval(JOKER_BONUS_HOLD)
					count_up_tween.tween_callback(_apply_joker_bonus_impact.bind(to_val))
					count_up_tween.tween_interval(DELAY_AFTER_COUNT_UP)
			if rt_steps.size() >= 2 and int(rt_steps[-1]) != int(rt_steps[rt_steps.size() - 2]):
				count_up_tween.tween_callback(_apply_final_total_display.bind(
					_count_up_center_x, final_score, _count_up_digit_h, _count_up_word_h
				))
			# Final score count-up: 0→final 0.6–1s, scale 1.0→1.15, shake ±2px, then bounce + glow
			count_up_tween.tween_callback(_prepare_final_score_count_up.bind(final_score))
			count_up_tween.tween_callback(_play_counting_score_once)
			count_up_tween.set_parallel(true)
			count_up_tween.tween_method(
				_final_score_count_up_update, 0.0, float(final_score), FINAL_COUNT_UP_DURATION
			).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			count_up_tween.tween_property(
				total_label, "scale", Vector2(FINAL_COUNT_UP_SCALE_END, FINAL_COUNT_UP_SCALE_END),
				FINAL_COUNT_UP_DURATION
			).set_trans(Tween.TRANS_LINEAR)
			count_up_tween.tween_method(
				_final_score_shake_update, 0.0, 1.0, FINAL_COUNT_UP_DURATION
			).set_trans(Tween.TRANS_LINEAR)
			count_up_tween.set_parallel(false)
			count_up_tween.tween_callback(_stop_counting_score_callback)
			count_up_tween.tween_callback(_finish_final_score_bounce_and_glow)
			# When final score is on screen: win tier effects on total_label, then emit
			count_up_tween.tween_callback(_apply_win_tier_effects.bind(breakdown_to_emit))
			count_up_tween.tween_callback(func() -> void:
				emit_signal("final_score_displayed", breakdown_to_emit)
			)
			count_up_tween.tween_callback(_hide_center_multiplier_label)
			count_up_tween.tween_callback(_emit_chaos_show_now.bind(breakdown_to_emit))
			count_up_tween.tween_interval(FINAL_SCORE_DISPLAY_TIME)
			count_up_tween.tween_property(self, "modulate:a", 0.0, FADE_DURATION)
			count_up_tween.tween_callback(_finish_overlay_with_breakdown.bind(breakdown_to_emit))
			return
	# No retrigger: joker mult anim → count up through joker steps one by one → chaos show → fade
	var hold_duration: float = (
		PHASE2_DISPLAY_DURATION_NO_SCORE if _is_no_score else FINAL_SCORE_DISPLAY_TIME
	)
	var base_val: int = _first_total_value
	var score_dict: Dictionary = _breakdown.get("score", {})
	var final_val: int = int(score_dict.get("final_score", base_val))
	var chaos_data: Dictionary = _breakdown.get("chaos", {})
	var chaos_after: int = int(chaos_data.get("chaos_after", 0))
	var steps: Array = _build_score_steps(score_dict, chaos_after, 0, final_val)
	var mults: Array = score_dict.get("multipliers", [])
	var tween := create_tween()
	for i in range(steps.size() - 1):
		var from_val: int = int(steps[i])
		var to_val: int = int(steps[i + 1])
		var step_idx: int = i
		var is_chaos_step: bool = (step_idx >= mults.size())
		# Skip only if joker step with no score change; always show Chaos Multiplier text before applying chaos
		if to_val <= from_val and not is_chaos_step:
			continue
		_count_up_total = to_val
		tween.tween_callback(_hide_total_show_multiplier_text.bind(_breakdown, step_idx))
		if is_chaos_step:
			# Chaos: show "× Chaos Multiplier", bar reacts; then count-up + score emphasis (scale 1.2, shake ±6px)
			tween.tween_interval(MULTIPLIER_TEXT_HOLD)
			if to_val > from_val:
				tween.tween_callback(_play_counting_score_once)
				tween.tween_callback(_hide_multiplier_show_total_at.bind(from_val))
				tween.tween_method(
					_count_up_update_total_display, float(from_val), float(to_val),
					PER_STEP_COUNT_UP_DURATION
				).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
				tween.tween_callback(_apply_chaos_step_impact.bind(to_val))
				tween.tween_callback(_stop_counting_score_callback)
				tween.tween_interval(DELAY_AFTER_COUNT_UP)
			else:
				tween.tween_callback(_hide_multiplier_show_total_at.bind(from_val))
				tween.tween_callback(_apply_chaos_step_impact.bind(to_val))
				tween.tween_interval(DELAY_AFTER_COUNT_UP)
		else:
			# Joker bonus: "JOKER BONUS" text, short hold, then instant impact (shake + flash + score jump)
			tween.tween_interval(JOKER_BONUS_HOLD)
			tween.tween_callback(_apply_joker_bonus_impact.bind(to_val))
			tween.tween_interval(DELAY_AFTER_COUNT_UP)
	# Final score count-up: 0 → final over 0.6–1s, scale 1.0→1.15, shake ±2px, then bounce + glow
	tween.tween_callback(_prepare_final_score_count_up.bind(final_val))
	tween.tween_callback(_play_counting_score_once)
	tween.set_parallel(true)
	tween.tween_method(
		_final_score_count_up_update, 0.0, float(final_val), FINAL_COUNT_UP_DURATION
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(
		total_label, "scale", Vector2(FINAL_COUNT_UP_SCALE_END, FINAL_COUNT_UP_SCALE_END),
		FINAL_COUNT_UP_DURATION
	).set_trans(Tween.TRANS_LINEAR)
	tween.tween_method(
		_final_score_shake_update, 0.0, 1.0, FINAL_COUNT_UP_DURATION
	).set_trans(Tween.TRANS_LINEAR)
	tween.set_parallel(false)
	tween.tween_callback(_stop_counting_score_callback)
	tween.tween_callback(_finish_final_score_bounce_and_glow)
	# When final score is on screen: win tier effects on total_label, then emit
	tween.tween_callback(_apply_win_tier_effects.bind(_breakdown))
	tween.tween_callback(func() -> void: emit_signal("final_score_displayed", _breakdown))
	tween.tween_callback(_hide_center_multiplier_label)
	tween.tween_callback(_emit_chaos_show_now.bind(_breakdown))
	tween.tween_interval(hold_duration)
	tween.tween_property(self, "modulate:a", 0.0, FADE_DURATION)
	tween.tween_callback(_on_overlay_finished)

func _finish_overlay_with_breakdown(breakdown: Dictionary) -> void:
	overlay_finished.emit(breakdown)
	queue_free()

func _on_overlay_finished() -> void:
	overlay_finished.emit(_breakdown)
	queue_free()

## Hide a single row's score content (called just before next row or before base score).
func _hide_row_content(content: Control) -> void:
	if is_instance_valid(content):
		content.visible = false

func _hide_row_labels() -> void:
	if is_instance_valid(row1_label):
		row1_label.visible = false
	if is_instance_valid(row2_label):
		row2_label.visible = false
	if is_instance_valid(row3_label):
		row3_label.visible = false
	if is_instance_valid(row1_content):
		row1_content.visible = false
	if is_instance_valid(row2_content):
		row2_content.visible = false
	if is_instance_valid(row3_content):
		row3_content.visible = false
