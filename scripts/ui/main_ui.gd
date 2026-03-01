extends Control

## Main UI controller that manages UI overlays like deck panel
## Background: bg.png as base; above it a color overlay (30% opacity) matching chaos step colors.

@export var deck_panel_scene: PackedScene = preload("res://scenes/ui/deck_panel.tscn")
@export var options_panel_scene: PackedScene = preload("res://scenes/ui/options_panel.tscn")

@onready var chaos_overlay: ColorRect = $ChaosOverlay
@onready var vignette_overlay: ColorRect = $VignetteOverlay
@onready var cracks_overlay: Control = $CracksOverlay
@onready var dark_outside_circle_overlay: ColorRect = $DarkOutsideCircleOverlay
@onready var deck_button: Button = $SafeRoot/ScreenPadding/VBoxContainer/Row/CenterColumn/BottomBarWrap/BottomBarRow/SpinWrap/DeckButton
@onready var input_blocker: Control = $InputBlocker
@onready var board_margin: Control = $SafeRoot/ScreenPadding/VBoxContainer/Row/CenterColumn/BoardWrap/BoardAspect/BoardMargin
@onready var music_player: AudioStreamPlayer = $Music

# Closing vignette (irregular creeping darkness) starts at chaos 60, full at chaos 80
const CHAOS_VIGNETTE_THRESHOLD := 60
const CHAOS_DARK_FULL := 80  # Dark effects reach full strength at chaos 80
const VIGNETTE_EDGE_OPACITY := 0.62  # Darkness outside the shrinking clear zone
const VIGNETTE_INNER_RADIUS_MAX := 0.42  # Clear center size at chaos 60
const VIGNETTE_INNER_RADIUS_MIN := 0.22  # Clear center shrinks at chaos 80 (closing vignette)
const VIGNETTE_IRREGULARITY := 0.28  # How wavy/organic the closing boundary is (higher = more irregular)
# Cracks overlay after chaos 80: light opacity at 80, ramps to full visibility at chaos 100
const CHAOS_CRACKS_THRESHOLD := 80
const CRACKS_OPACITY_MIN := 0.28   # Lighter at chaos 80
const CRACKS_OPACITY := 0.72       # More visible at chaos 100
const CRACKS_ICE_COLOR := Color(0.75, 0.92, 1.0, 1.0)  # Light ice blue
const CRACKS_FADE_DURATION := 1.0
var _cracks_tween: Tween = null
# Dark outside circle: starts at chaos 60, ramps to full at chaos 80
const CHAOS_DARK_CIRCLE_THRESHOLD := 60  # Show overlay from 60, strength ramps 60→80
const DARK_OUTSIDE_CIRCLE_OPACITY := 0.72  # Max opacity at chaos 80
const DARK_CIRCLE_INNER_RADIUS := 0.3
const DARK_CIRCLE_TRANSITION_WIDTH := 0.28  # Wider = smoother blend between clear center and dark outside

# Chaos bar step colors (reverted: low chaos = teal, high chaos = black)
# 0-16: teal, 16-33: yellow, 33-50: orange, 50-66: red, 66-83: dark brown, 83-99: dark brown, 100: black
const CHAOS_STEP_PERCENTS := [0, 16, 33, 50, 66, 83, 100]
const CHAOS_STEP_COLORS := [
	Color(0.055, 0.549, 0.467, 1.0),     # 0    #0E8C77 teal
	Color(0.988, 0.922, 0.325, 1.0),     # 16   #FCEB53 yellow
	Color(0.953, 0.278, 0.0, 1.0),       # 33   #F34700 orange
	Color(0.698, 0.071, 0.016, 1.0),     # 50   #B21204 red
	Color(0.196, 0.024, 0.016, 1.0),     # 66   #320604 dark reddish-brown
	Color(0.196, 0.024, 0.016, 1.0),     # 83   #320604 dark reddish-brown
	Color(0.0, 0.0, 0.0, 1.0),           # 100  #000000 black
]

# Overlay = step color with -30% brightness/contrast, then 30% opacity on top of bg.png
const BG_BRIGHTNESS_REDUCTION := 0.30
const BG_CONTRAST_REDUCTION := 0.30
const BG_MID_GRAY := Color(0.5, 0.5, 0.5, 1.0)
const CHAOS_OVERLAY_OPACITY := 0.5
const BG_TRANSITION_DURATION := 1.0
var _bg_tween: Tween = null

var deck_panel_instance: CanvasLayer = null
var options_panel_instance: Popup = null
var game: Node = null

# Short 1s shake when chaos crosses any step (30, 40, 50, 60, 70, 80, 90, 100). BG+UI only, cards stay still.
const CHAOS_SHAKE_STEPS: Array = [30, 40, 50, 60, 70, 80, 90, 100]
const UI_SHAKE_DURATION := 1.0
const UI_SHAKE_AMOUNT := 0.9  # 50% of previous (1.8)
var _ui_shake_remaining: float = 0.0
var _last_chaos_for_shake: int = -1

# 60%+: continuous shake. 60–89: BG+UI only (cards stay still). 90%+: full screen including cards.
const CHAOS_SHAKE_BG_ONLY_START := 60   # Shake BG+UI only, counter-shake board so cards don't move
const CHAOS_SHAKE_FULL_START := 90      # Shake everything including cards (no counter-shake)
const SCREEN_SHAKE_AT_60 := 0.6         # Light at 60 (50% of previous)
const SCREEN_SHAKE_AT_90 := 1.4         # Medium at 90 (50% of previous)
const SCREEN_SHAKE_AT_100 := 2.0        # Strong at 100 (50% of previous)

# Chaos ≥ 80%: slow game down 10% (Engine.time_scale = 0.9)
const CHAOS_SLOW_THRESHOLD := 80
const CHAOS_SLOW_TIME_SCALE := 0.9

# Music: RazvanSketch1.wav, loop on, default −20 dB. Chaos tiers with 2–3 s tween; overload at 100 = 0.2 s drop.
const MUSIC_BUS_NAME := "Music"
const MUSIC_TWEEN_DURATION := 2.5
const MUSIC_OVERLOAD_DROP_DURATION := 0.2
const MUSIC_SILENCE_DB := -80.0
# Tier: 0 (0–39) −20 dB no filter, 1 (40–59) −18 dB slight LP, 2 (60–79) −16 dB stronger LP, 3 (80–100) −14 dB strong LP + subtle distortion
const MUSIC_TIER_VOLUME := [-20.0, -18.0, -16.0, -14.0]
const MUSIC_TIER_LOWPASS_HZ := [22050.0, 8000.0, 4000.0, 2000.0]  # 22050 = effectively off
const MUSIC_TIER_DISTORTION := [0.0, 0.0, 0.0, 0.12]  # Very subtle at tier 3
var _music_bus_idx: int = -1
var _music_lowpass_idx: int = -1
var _music_distortion_idx: int = -1
var _music_tier: int = 0
var _music_tween: Tween = null

# Dedicated dim overlay for BASE SCORE → total moment (not chaos-related)
var _score_dim_overlay: ColorRect = null
var _score_dim_tween: Tween = null
const SCORE_DIM_ALPHA := 0.15  # Black overlay opacity when base score appears (15%)
const SCORE_DIM_TWEEN_IN := 0.22
const SCORE_DIM_TWEEN_OUT := 0.28
# After last row: black overlay 15% to signal "row scoring done, big reveal starts"
const ROW_SCORING_DONE_DARK_ALPHA := 0.15
const ROW_SCORING_DONE_TWEEN_IN := 0.12

# When final score count-up ends: Step I = short hit shake (2–3 frames), Step J = chaos bar pulse
const FINAL_SCORE_HIT_SHAKE_DURATION := 0.1  # ~3 frames at 60 fps
const FINAL_SCORE_HIT_SHAKE_AMOUNT := 2

# Win tier effects by final score: T1 <3k, T2 3k–7k, T3 7k–11k, T4 >11k
const WIN_TIER_T2 := 3000
const WIN_TIER_T3 := 7000
const WIN_TIER_T4 := 11000
const WIN_SHAKE_T1_AMOUNT := 0.3
const WIN_SHAKE_T1_DURATION := 0.28
const WIN_SHAKE_T2_AMOUNT := 0.65
const WIN_SHAKE_T2_DURATION := 0.45
const WIN_SHAKE_T3_AMOUNT := 0.5
const WIN_SHAKE_T3_DURATION := 1.15
const WIN_SHAKE_T4_AMOUNT := 1.7
const WIN_SHAKE_T4_DURATION := 1.0
const WIN_FREEZE_T4_DURATION := 0.15
const WIN_WHITE_FLASH_DURATION := 0.2
const WIN_CRACK_FLASH_DURATION := 0.35
var _win_shake_remaining: float = 0.0
var _win_shake_amount: float = 0.0
var _win_white_flash: ColorRect = null
var _saved_time_scale: float = 1.0

func _ready() -> void:
	# Add to group for easy access
	add_to_group("main_ui")
	_setup_score_dim_overlay()
	
	# Find game controller
	game = get_node_or_null("Game")
	if game == null:
		game = get_tree().get_first_node_in_group("game")
	
	# Connect to game state changes
	if game and game.has_signal("game_state_changed"):
		game.game_state_changed.connect(_on_game_state_changed)
		# Set initial state
		call_deferred("_update_input_blocker")
	
	# Connect to chaos changes for background
	if game and game.get("run_state") != null:
		game.run_state.chaos_changed.connect(_on_chaos_changed)
		_update_background_from_chaos(game.run_state.chaos)
		# Initial time scale (slow 10% when chaos > 80%)
		if game.run_state.chaos > CHAOS_SLOW_THRESHOLD:
			Engine.time_scale = CHAOS_SLOW_TIME_SCALE
		else:
			Engine.time_scale = 1.0
	
	# Connect to deck button signal
	if deck_button != null:
		if deck_button.has_signal("deck_pressed"):
			deck_button.deck_pressed.connect(_on_deck_pressed)
		else:
			# Fallback: connect directly to pressed signal if custom signal doesn't exist
			deck_button.pressed.connect(_on_deck_pressed)
	else:
		push_error("Deck button not found in Main UI!")
	
	# Initialize input blocker
	if input_blocker:
		input_blocker.visible = false
		input_blocker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Vignette: darken edges when chaos > 60
	_setup_vignette()
	# Dark outside circle: when chaos > 80, darken area outside central circle
	_setup_dark_outside_circle()
	# Cracks: show when chaos >= 80
	if game and game.get("run_state") != null:
		_update_cracks_from_chaos(game.run_state.chaos)
		_update_dark_outside_circle_from_chaos(game.run_state.chaos)

	# Music: bus with low-pass + distortion, loop, chaos-based tiers
	_setup_music_bus()
	if music_player != null:
		music_player.volume_db = MUSIC_TIER_VOLUME[0]
		music_player.finished.connect(_on_music_finished)
		if game and game.get("run_state") != null:
			_music_tier = _get_music_tier(game.run_state.chaos)
			_apply_music_tier(_music_tier, 0.0)

func _process(delta: float) -> void:
	# Win tier shake (from final score) takes precedence when active
	if _win_shake_remaining > 0.0:
		_win_shake_remaining -= delta
		var amt: float = _win_shake_amount
		var offset := Vector2(randf_range(-amt, amt), randf_range(-amt, amt))
		self.position = offset
		if board_margin != null:
			board_margin.position = -offset
		if _win_shake_remaining <= 0.0:
			_win_shake_remaining = 0.0
			self.position = Vector2.ZERO
			if board_margin != null:
				board_margin.position = Vector2.ZERO
		return
	if _ui_shake_remaining > 0.0:
		# 30% one-time shake (BG + UI, board counter-shaken)
		_ui_shake_remaining -= delta
		var offset := Vector2(
			randf_range(-UI_SHAKE_AMOUNT, UI_SHAKE_AMOUNT),
			randf_range(-UI_SHAKE_AMOUNT, UI_SHAKE_AMOUNT)
		)
		self.position = offset
		if board_margin != null:
			board_margin.position = -offset
		if _ui_shake_remaining <= 0.0:
			_ui_shake_remaining = 0.0
			self.position = Vector2.ZERO
			if board_margin != null:
				board_margin.position = Vector2.ZERO
		return

	# No continuous shake when chaos > 60 (removed)
	self.position = Vector2.ZERO
	if board_margin != null:
		board_margin.position = Vector2.ZERO

func _on_game_state_changed(_new_state: int) -> void:
	_update_input_blocker()

func _on_chaos_changed(new_chaos: int, _max_chaos: int) -> void:
	# Shake is triggered by spin flow (trigger_chaos_tier_shake); keep last for non-spin chaos changes (e.g. restart)
	_last_chaos_for_shake = new_chaos
	_update_background_from_chaos(new_chaos)
	_update_cracks_from_chaos(new_chaos)
	_update_dark_outside_circle_from_chaos(new_chaos)

	# Music: chaos-based tier with smooth tween; overload at 100 = brief drop then resume
	if music_player != null and _music_bus_idx >= 0:
		if new_chaos >= 100:
			_play_music_overload_drop()
		else:
			var tier := _get_music_tier(new_chaos)
			if tier != _music_tier:
				_music_tier = tier
				_apply_music_tier(_music_tier, MUSIC_TWEEN_DURATION)

	# Chaos ≥ 80%: slow game down 10%
	if new_chaos > CHAOS_SLOW_THRESHOLD:
		Engine.time_scale = CHAOS_SLOW_TIME_SCALE
	else:
		Engine.time_scale = 1.0

func _on_music_finished() -> void:
	if music_player != null:
		music_player.play()

func _setup_music_bus() -> void:
	if music_player == null:
		return
	# Reuse existing bus if present (e.g. from project bus layout)
	_music_bus_idx = AudioServer.get_bus_index(MUSIC_BUS_NAME)
	if _music_bus_idx < 0:
		_music_bus_idx = AudioServer.bus_count
		AudioServer.add_bus(_music_bus_idx)
		AudioServer.set_bus_name(_music_bus_idx, MUSIC_BUS_NAME)
		var lowpass := AudioEffectLowPassFilter.new()
		lowpass.cutoff_hz = MUSIC_TIER_LOWPASS_HZ[0]
		AudioServer.add_bus_effect(_music_bus_idx, lowpass, 0)
		var distortion := AudioEffectDistortion.new()
		distortion.drive = 0.0
		AudioServer.add_bus_effect(_music_bus_idx, distortion, 1)
	else:
		# Existing bus may have no effects; add lowpass + distortion if missing
		var n := AudioServer.get_bus_effect_count(_music_bus_idx)
		if n <= 0:
			var lowpass := AudioEffectLowPassFilter.new()
			lowpass.cutoff_hz = MUSIC_TIER_LOWPASS_HZ[0]
			AudioServer.add_bus_effect(_music_bus_idx, lowpass, 0)
		if AudioServer.get_bus_effect_count(_music_bus_idx) <= 1:
			var distortion := AudioEffectDistortion.new()
			distortion.drive = 0.0
			AudioServer.add_bus_effect(_music_bus_idx, distortion, 1)
	_music_lowpass_idx = 0
	_music_distortion_idx = 1
	if _music_bus_idx >= 0:
		music_player.bus = MUSIC_BUS_NAME

func _get_music_tier(chaos: int) -> int:
	if chaos < 40:
		return 0
	if chaos < 60:
		return 1
	if chaos < 80:
		return 2
	return 3

func _apply_music_tier(tier: int, duration_sec: float) -> void:
	if music_player == null or _music_bus_idx < 0 or tier < 0 or tier > 3:
		return
	var effect_count: int = AudioServer.get_bus_effect_count(_music_bus_idx)
	if effect_count <= _music_distortion_idx:
		# Bus has no/few effects; only adjust volume
		var vol: float = MUSIC_TIER_VOLUME[tier]
		if _music_tween != null and _music_tween.is_valid():
			_music_tween.kill()
		if duration_sec <= 0.0:
			music_player.volume_db = vol
		else:
			_music_tween = create_tween()
			_music_tween.tween_method(
				func(v: float): music_player.volume_db = v,
				music_player.volume_db, vol, duration_sec
			).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		return
	var target_vol: float = MUSIC_TIER_VOLUME[tier]
	var target_lp: float = MUSIC_TIER_LOWPASS_HZ[tier]
	var target_dist: float = MUSIC_TIER_DISTORTION[tier]
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	if duration_sec <= 0.0:
		music_player.volume_db = target_vol
		var lp_eff = AudioServer.get_bus_effect(_music_bus_idx, _music_lowpass_idx) as AudioEffectLowPassFilter
		var dist_eff = AudioServer.get_bus_effect(_music_bus_idx, _music_distortion_idx) as AudioEffectDistortion
		if lp_eff:
			lp_eff.cutoff_hz = target_lp
		if dist_eff:
			dist_eff.drive = target_dist
		return
	_music_tween = create_tween()
	_music_tween.set_parallel(true)
	var from_vol: float = music_player.volume_db
	var eff_lp = AudioServer.get_bus_effect(_music_bus_idx, _music_lowpass_idx) as AudioEffectLowPassFilter
	var eff_dist = AudioServer.get_bus_effect(_music_bus_idx, _music_distortion_idx) as AudioEffectDistortion
	var from_lp: float = eff_lp.cutoff_hz if eff_lp else target_lp
	var from_dist: float = eff_dist.drive if eff_dist else target_dist
	_music_tween.tween_method(func(v: float): music_player.volume_db = v, from_vol, target_vol, duration_sec).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_music_tween.tween_method(func(hz: float): if eff_lp: eff_lp.cutoff_hz = hz, from_lp, target_lp, duration_sec).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_music_tween.tween_method(func(d: float): if eff_dist: eff_dist.drive = d, from_dist, target_dist, duration_sec).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _play_music_overload_drop() -> void:
	if music_player == null or _music_bus_idx < 0:
		return
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	var current_vol: float = music_player.volume_db
	_music_tween = create_tween()
	_music_tween.tween_method(func(v: float): music_player.volume_db = v, current_vol, MUSIC_SILENCE_DB, 0.05)
	_music_tween.tween_interval(MUSIC_OVERLOAD_DROP_DURATION)
	_music_tween.tween_callback(func():
		_music_tier = 3
		_apply_music_tier(3, 0.3)
	)

## Chaos value 0–100 maps to palette steps; lerp between nearest steps for smooth progression.
func _get_step_color_for_chaos(chaos: int) -> Color:
	var t: float = clamp(float(chaos) / 100.0, 0.0, 1.0)
	var percents := CHAOS_STEP_PERCENTS
	var colors := CHAOS_STEP_COLORS
	if t <= 0.0:
		return colors[0]
	if t >= 1.0:
		return colors[colors.size() - 1]
	for i in range(percents.size() - 1):
		var p0: float = float(percents[i]) / 100.0
		var p1: float = float(percents[i + 1]) / 100.0
		if t >= p0 and t <= p1:
			var local: float = (t - p0) / (p1 - p0) if p1 > p0 else 0.0
			return colors[i].lerp(colors[i + 1], local)
	return colors[colors.size() - 1]

## Overlay color = step color with -30% contrast/brightness, alpha = 30%.
func _get_overlay_color_for_chaos(chaos: int) -> Color:
	var step_color := _get_step_color_for_chaos(chaos)
	var flatter := step_color.lerp(BG_MID_GRAY, BG_CONTRAST_REDUCTION)
	var darker := Color(
		flatter.r * (1.0 - BG_BRIGHTNESS_REDUCTION),
		flatter.g * (1.0 - BG_BRIGHTNESS_REDUCTION),
		flatter.b * (1.0 - BG_BRIGHTNESS_REDUCTION),
		CHAOS_OVERLAY_OPACITY
	)
	return darker

## Called by spin flow when chaos crosses a tier (30,40,50,60,70,80,90,100). Triggers camera shake.
func trigger_chaos_tier_shake(chaos_before: int, chaos_after: int) -> void:
	for step in CHAOS_SHAKE_STEPS:
		if chaos_after >= step and chaos_before < step:
			_ui_shake_remaining = UI_SHAKE_DURATION
			break
	_last_chaos_for_shake = chaos_after

## Win tier from final score: 1 = <3k, 2 = 3k–7k, 3 = 7k–11k, 4 = >11k
func get_win_tier(final_score: int) -> int:
	if final_score >= WIN_TIER_T4:
		return 4
	if final_score >= WIN_TIER_T3:
		return 3
	if final_score >= WIN_TIER_T2:
		return 2
	return 1

## Called when overlay emits final_score_displayed. Step I: hit shake (2–3 frames). Step J: chaos bar pulse. Then tier effects.
func trigger_win_tier_effects(breakdown: Dictionary) -> void:
	# Step I — Very short shake burst (2–3 frames) for impact
	_win_shake_remaining = FINAL_SCORE_HIT_SHAKE_DURATION
	_win_shake_amount = FINAL_SCORE_HIT_SHAKE_AMOUNT
	# Step J — Chaos bar pulse (brighten/glow) after hit; then run tier effects
	var timer := get_tree().create_timer(FINAL_SCORE_HIT_SHAKE_DURATION)
	timer.timeout.connect(func() -> void:
		var effect_panel: Node = get_tree().get_first_node_in_group("active_effect_panel")
		if effect_panel != null and effect_panel.has_method("pulse_chaos_bar_on_final_score"):
			effect_panel.pulse_chaos_bar_on_final_score()
		_run_tier_effects_after_hit(breakdown)
	, CONNECT_ONE_SHOT)

func _run_tier_effects_after_hit(breakdown: Dictionary) -> void:
	var score_data: Dictionary = breakdown.get("score", {})
	var final_score: int = int(score_data.get("final_score", 0))
	var tier: int = get_win_tier(final_score)

	if tier >= 1:
		_win_shake_remaining = WIN_SHAKE_T1_DURATION
		_win_shake_amount = WIN_SHAKE_T1_AMOUNT
		var board: Node = get_tree().get_first_node_in_group("board_view")
		if board != null and board.has_method("trigger_win_card_outline_pulse"):
			board.trigger_win_card_outline_pulse()

	if tier >= 2:
		_win_shake_remaining = WIN_SHAKE_T2_DURATION
		_win_shake_amount = WIN_SHAKE_T2_AMOUNT
		var board: Node = get_tree().get_first_node_in_group("board_view")
		if board != null and board.has_method("trigger_win_card_flicker"):
			board.trigger_win_card_flicker(1)
		var effect_panel: Node = get_tree().get_first_node_in_group("active_effect_panel")
		if effect_panel != null and effect_panel.has_method("flash_chaos_bar"):
			effect_panel.flash_chaos_bar()

	if tier >= 3:
		_win_shake_remaining = WIN_SHAKE_T3_DURATION
		_win_shake_amount = WIN_SHAKE_T3_AMOUNT
		_tween_win_tier3_darken()

	if tier >= 4:
		_play_win_tier4_sequence()

func _tween_win_tier3_darken() -> void:
	if _score_dim_overlay == null:
		return
	var prev: Color = _score_dim_overlay.color
	if _score_dim_tween != null and _score_dim_tween.is_valid():
		_score_dim_tween.kill()
	_score_dim_tween = create_tween()
	var extra: Color = Color(0, 0, 0, 0.18)
	_score_dim_tween.tween_property(_score_dim_overlay, "color", prev + extra, 0.15)
	_score_dim_tween.tween_interval(0.4)
	_score_dim_tween.tween_property(_score_dim_overlay, "color", prev, 0.25)

func _setup_win_white_flash() -> void:
	if _win_white_flash != null:
		return
	_win_white_flash = ColorRect.new()
	_win_white_flash.name = "WinWhiteFlash"
	_win_white_flash.color = Color(1, 1, 1, 0)
	_win_white_flash.visible = true
	_win_white_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_win_white_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_win_white_flash.z_index = 180
	add_child(_win_white_flash)

func _play_win_tier4_sequence() -> void:
	_saved_time_scale = Engine.time_scale
	Engine.time_scale = 0.0
	_win_shake_remaining = WIN_SHAKE_T4_DURATION
	_win_shake_amount = WIN_SHAKE_T4_AMOUNT
	_setup_win_white_flash()
	# Unfreeze after WIN_FREEZE_T4_DURATION (ignore_time_scale so timer runs in real time)
	var timer: SceneTreeTimer = get_tree().create_timer(WIN_FREEZE_T4_DURATION, true, false, true)
	timer.timeout.connect(func() -> void:
		Engine.time_scale = _saved_time_scale
		if _win_white_flash != null:
			_win_white_flash.color = Color(1, 1, 1, 0)
			_win_white_flash.visible = true
			var t: Tween = create_tween()
			t.tween_property(_win_white_flash, "color", Color(1, 1, 1, 0.5), WIN_WHITE_FLASH_DURATION * 0.3)
			t.tween_property(_win_white_flash, "color", Color(1, 1, 1, 0), WIN_WHITE_FLASH_DURATION * 0.7)
			t.tween_callback(func() -> void:
				if _win_white_flash != null:
					_win_white_flash.visible = false
			)
	, CONNECT_ONE_SHOT)
	# Crack overlay flash (briefly show at full then restore to chaos level)
	if cracks_overlay != null:
		if _cracks_tween != null and _cracks_tween.is_valid():
			_cracks_tween.kill()
		cracks_overlay.visible = true
		cracks_overlay.modulate = Color(CRACKS_ICE_COLOR.r, CRACKS_ICE_COLOR.g, CRACKS_ICE_COLOR.b, 0.85)
		_cracks_tween = create_tween()
		_cracks_tween.tween_interval(WIN_CRACK_FLASH_DURATION)
		_cracks_tween.tween_callback(func() -> void:
			if game != null and game.get("run_state") != null:
				_update_cracks_from_chaos(game.run_state.chaos)
		)
	# Fast card flicker (multiple cards)
	var board: Node = get_tree().get_first_node_in_group("board_view")
	if board != null and board.has_method("trigger_win_card_flicker"):
		board.trigger_win_card_flicker(5)

func _setup_score_dim_overlay() -> void:
	_score_dim_overlay = ColorRect.new()
	_score_dim_overlay.name = "ScoreDimOverlay"
	_score_dim_overlay.color = Color(0.0, 0.0, 0.0, 0.0)
	_score_dim_overlay.visible = true
	_score_dim_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_score_dim_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_score_dim_overlay.z_index = 50
	add_child(_score_dim_overlay)

## After last row resolves: show dark overlay 15% (signals "row scoring done, big reveal starts"). Then base score phase tweens to full dim.
func request_row_scoring_done_overlay() -> void:
	if _score_dim_overlay == null:
		return
	if _score_dim_tween != null and _score_dim_tween.is_valid():
		_score_dim_tween.kill()
	var dark: Color = Color(0.0, 0.0, 0.0, ROW_SCORING_DONE_DARK_ALPHA)
	_score_dim_tween = create_tween()
	_score_dim_tween.set_trans(Tween.TRANS_SINE)
	_score_dim_tween.set_ease(Tween.EASE_IN_OUT)
	_score_dim_tween.tween_property(_score_dim_overlay, "color", dark, ROW_SCORING_DONE_TWEEN_IN)

## Spin flow: darken background when base score is about to show. Removed when overlay finishes (brighten_after_total_score on overlay_finished).
func request_background_darken_for_score() -> void:
	if _score_dim_overlay == null:
		return
	if _score_dim_tween != null and _score_dim_tween.is_valid():
		_score_dim_tween.kill()
	var dark: Color = Color(0.0, 0.0, 0.0, SCORE_DIM_ALPHA)
	_score_dim_tween = create_tween()
	_score_dim_tween.set_trans(Tween.TRANS_SINE)
	_score_dim_tween.set_ease(Tween.EASE_IN_OUT)
	_score_dim_tween.tween_property(_score_dim_overlay, "color", dark, SCORE_DIM_TWEEN_IN)

## Spin flow: brighten again after final score has disappeared (called from overlay_finished).
func brighten_after_total_score() -> void:
	if _score_dim_overlay == null:
		return
	if _score_dim_tween != null and _score_dim_tween.is_valid():
		_score_dim_tween.kill()
	_score_dim_tween = create_tween()
	_score_dim_tween.set_trans(Tween.TRANS_SINE)
	_score_dim_tween.set_ease(Tween.EASE_IN_OUT)
	_score_dim_tween.tween_property(_score_dim_overlay, "color", Color(0, 0, 0, 0), SCORE_DIM_TWEEN_OUT)

func _update_background_from_chaos(chaos: int) -> void:
	if chaos_overlay == null:
		return
	var target_color := _get_overlay_color_for_chaos(chaos)
	if _bg_tween != null and _bg_tween.is_valid():
		_bg_tween.kill()
	_bg_tween = create_tween()
	_bg_tween.set_trans(Tween.TRANS_SINE)
	_bg_tween.set_ease(Tween.EASE_IN_OUT)
	_bg_tween.tween_property(chaos_overlay, "color", target_color, BG_TRANSITION_DURATION)
	_update_vignette_from_chaos(chaos)

func _setup_vignette() -> void:
	if vignette_overlay == null:
		return
	# Closing vignette only: irregular boundary (multi-scale noise), clear center shrinks with chaos
	var shader_code := """
shader_type canvas_item;

uniform float edge_opacity : hint_range(0.0, 1.0) = 0.5;
uniform float inner_radius : hint_range(0.0, 1.0) = 0.38;
uniform float irregularity : hint_range(0.0, 0.5) = 0.28;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x);
	float b = mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x);
	return mix(a, b, u.y);
}
// Multi-scale noise for organic, irregular closing edge
float fbm(vec2 p) {
	float v = 0.0;
	v += noise(p) * 0.5;
	v += noise(p * 2.3 + vec2(1.2, 0.7)) * 0.3;
	v += noise(p * 5.1 + vec2(4.0, 2.0)) * 0.2;
	return v;
}

void fragment() {
	vec2 uv = UV;
	vec2 c = vec2(0.5, 0.5);
	float d = distance(uv, c);
	// Strong irregular boundary: fbm perturbs distance so closing edge is wavy/organic, not a smooth circle
	float n = fbm(uv * 4.0) - 0.5;
	d += n * irregularity;
	float transition = 0.18;
	float t = clamp((d - inner_radius) / transition, 0.0, 1.0);
	float alpha = edge_opacity * smoothstep(0.0, 1.0, t);
	COLOR = vec4(0.0, 0.0, 0.0, alpha);
}
"""
	var shader := Shader.new()
	shader.code = shader_code
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("edge_opacity", VIGNETTE_EDGE_OPACITY)
	mat.set_shader_parameter("inner_radius", 0.38)
	mat.set_shader_parameter("irregularity", VIGNETTE_IRREGULARITY)
	vignette_overlay.material = mat

## Returns 0.0 at chaos <= 60, 1.0 at chaos >= 80, smooth linear ramp between 60 and 80.
func _get_dark_strength_60_to_80(chaos: int) -> float:
	if chaos <= CHAOS_VIGNETTE_THRESHOLD:
		return 0.0
	if chaos >= CHAOS_DARK_FULL:
		return 1.0
	return clampf(float(chaos - CHAOS_VIGNETTE_THRESHOLD) / float(CHAOS_DARK_FULL - CHAOS_VIGNETTE_THRESHOLD), 0.0, 1.0)

func _update_vignette_from_chaos(chaos: int) -> void:
	if vignette_overlay == null:
		return
	var strength := _get_dark_strength_60_to_80(chaos)
	vignette_overlay.visible = chaos > CHAOS_VIGNETTE_THRESHOLD
	if vignette_overlay.material is ShaderMaterial:
		var mat := vignette_overlay.material as ShaderMaterial
		mat.set_shader_parameter("edge_opacity", VIGNETTE_EDGE_OPACITY * strength)
		# Focus tightening: bright center shrinks as chaos increases
		var inner := lerpf(VIGNETTE_INNER_RADIUS_MAX, VIGNETTE_INNER_RADIUS_MIN, strength)
		mat.set_shader_parameter("inner_radius", inner)

func _setup_dark_outside_circle() -> void:
	if dark_outside_circle_overlay == null:
		return
	# Shader: clear inside circle, dark outside; wide smoothstep for soft transition
	var shader_code := """
shader_type canvas_item;
uniform float inner_radius : hint_range(0.0, 1.0) = 0.5;
uniform float outside_opacity : hint_range(0.0, 1.0) = 0.7;
uniform float transition_width : hint_range(0.01, 0.5) = 0.28;

void fragment() {
	vec2 uv = UV;
	vec2 c = vec2(0.5, 0.5);
	float d = distance(uv, c);
	float alpha = outside_opacity * smoothstep(inner_radius, inner_radius + transition_width, d);
	COLOR = vec4(0.0, 0.0, 0.0, alpha);
}
"""
	var shader := Shader.new()
	shader.code = shader_code
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("inner_radius", DARK_CIRCLE_INNER_RADIUS)
	mat.set_shader_parameter("outside_opacity", DARK_OUTSIDE_CIRCLE_OPACITY)
	mat.set_shader_parameter("transition_width", DARK_CIRCLE_TRANSITION_WIDTH)
	dark_outside_circle_overlay.material = mat

func _update_dark_outside_circle_from_chaos(chaos: int) -> void:
	if dark_outside_circle_overlay == null:
		return
	var strength := _get_dark_strength_60_to_80(chaos)
	dark_outside_circle_overlay.visible = chaos > CHAOS_VIGNETTE_THRESHOLD
	if dark_outside_circle_overlay.material is ShaderMaterial:
		(dark_outside_circle_overlay.material as ShaderMaterial).set_shader_parameter("outside_opacity", DARK_OUTSIDE_CIRCLE_OPACITY * strength)

## Returns 0.0 at chaos 80, 1.0 at chaos 100; smooth ramp for cracks visibility.
func _get_cracks_strength_80_to_100(chaos: int) -> float:
	if chaos <= CHAOS_CRACKS_THRESHOLD:
		return 0.0
	if chaos >= 100:
		return 1.0
	return clampf(float(chaos - CHAOS_CRACKS_THRESHOLD) / float(100 - CHAOS_CRACKS_THRESHOLD), 0.0, 1.0)

func _update_cracks_from_chaos(chaos: int) -> void:
	if cracks_overlay == null:
		return
	var show_cracks := chaos >= CHAOS_CRACKS_THRESHOLD
	if _cracks_tween != null and _cracks_tween.is_valid():
		_cracks_tween.kill()
	var target_modulate: Color
	if show_cracks:
		cracks_overlay.visible = true
		var strength := _get_cracks_strength_80_to_100(chaos)
		var opacity := lerpf(CRACKS_OPACITY_MIN, CRACKS_OPACITY, strength)
		target_modulate = Color(CRACKS_ICE_COLOR.r, CRACKS_ICE_COLOR.g, CRACKS_ICE_COLOR.b, opacity)
	else:
		target_modulate = Color(cracks_overlay.modulate.r, cracks_overlay.modulate.g, cracks_overlay.modulate.b, 0.0)
	_cracks_tween = create_tween()
	_cracks_tween.set_trans(Tween.TRANS_SINE)
	_cracks_tween.set_ease(Tween.EASE_IN_OUT)
	_cracks_tween.tween_property(cracks_overlay, "modulate", target_modulate, CRACKS_FADE_DURATION)
	if not show_cracks:
		_cracks_tween.tween_callback(func() -> void: cracks_overlay.visible = false)

func _update_input_blocker() -> void:
	if not input_blocker:
		return
	
	if not game:
		return
	
	var current_state = game.get("game_state")
	if current_state == null:
		return
	
	# Show and enable blocker when state is ENDED
	if current_state == game.GameState.ENDED:
		input_blocker.visible = true
		input_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	else:
		input_blocker.visible = false
		input_blocker.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _on_deck_pressed() -> void:
	# Block input if run has ended or state is ENDED
	if not game:
		game = get_tree().get_first_node_in_group("game")
	
	if game != null:
		if game.get("is_run_ended") == true or game.get("game_state") == game.GameState.ENDED:
			return  # Run has ended, ignore input
	
	# Prevent opening multiple panels
	if deck_panel_instance != null and is_instance_valid(deck_panel_instance):
		return
	
	# Instantiate the deck panel
	deck_panel_instance = deck_panel_scene.instantiate()
	if deck_panel_instance == null:
		push_error("Failed to instantiate deck panel!")
		return
	
	# Add to scene tree (as a child of root to ensure it's on top)
	get_tree().root.add_child(deck_panel_instance)
	
	# Optional: pause gameplay logic while open
	# get_tree().paused = true
	
	# Connect to closed signal
	if deck_panel_instance.has_signal("closed"):
		deck_panel_instance.closed.connect(_on_deck_closed)
	
	# Deck panel will automatically load and display deck data in its _ready() function

func _on_deck_closed() -> void:
	# Optional: resume gameplay logic
	# get_tree().paused = false
	
	# Clear reference when panel is closed
	deck_panel_instance = null

func open_options() -> void:
	if options_panel_instance != null and is_instance_valid(options_panel_instance):
		return
	options_panel_instance = options_panel_scene.instantiate()
	if options_panel_instance == null:
		push_error("Failed to instantiate options panel!")
		return
	get_tree().root.add_child(options_panel_instance)
	if options_panel_instance.has_signal("closed"):
		options_panel_instance.closed.connect(_on_options_closed)
	options_panel_instance.popup_centered()

func _on_options_closed() -> void:
	options_panel_instance = null
