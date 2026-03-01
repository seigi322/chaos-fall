extends Button
class_name CardView

var art: TextureRect
var highlight_border: PanelContainer
var score_highlight: PanelContainer
var lightning_effect: ColorRect
var lock_icon: TextureRect

var slot_index: int = -1
var is_animating: bool = false
var is_locked: bool = false
var is_scoring: bool = false
var is_displaying_joker: bool = false  # Track if currently displaying a joker

# Scoring pulse animation (used instead of highlight border)
var _scoring_pulse_tween: Tween = null
var _scoring_pulse_token: int = 0
var _lightning_tween: Tween = null
var _glitch_tween: Tween = null

# 70%+ chaos: suit distort / glitch on card art (brief stretch, wobble, color)
var _chaos_level: int = 0
var _glitch_timer: float = 0.0
const CHAOS_GLITCH_THRESHOLD := 70
const GLITCH_INTERVAL := 0.28
# Suit distort: stretch vertical + wobble (increased time and scale so effect is visible)
const GLITCH_STRETCH_DURATION := 0.12
const GLITCH_WOBBLE_DURATION := 0.10
const GLITCH_RECOVER_DURATION := 0.15
const GLITCH_STRETCH_SCALE := Vector2(0.88, 1.38)
const GLITCH_WOBBLE_SCALE := Vector2(1.22, 0.82)

signal card_pressed(slot_index: int)
signal animation_complete()

func _ready() -> void:
	# Get node references (using get_node_or_null for safety)
	art = get_node_or_null("Art")
	highlight_border = get_node_or_null("HighlightBorder")
	score_highlight = get_node_or_null("ScoreHighlight")
	lightning_effect = get_node_or_null("LightningEffect")
	lock_icon = get_node_or_null("LockIcon")
	
	if art == null:
		push_error("CardView: Art node not found! Check scene structure.")
		return
	
	# Ensure art is visible and properly configured
	art.visible = true
	art.modulate = Color.WHITE
	
	focus_mode = Control.FOCUS_NONE
	pressed.connect(_on_pressed)
	# Set pivot point to center for rotation
	_update_pivot()
	# Ensure highlight border starts hidden
	if highlight_border != null:
		highlight_border.visible = false
		highlight_border.modulate.a = 1.0  # Set to full opacity when visible
	if score_highlight != null:
		score_highlight.visible = false
		score_highlight.modulate.a = 1.0
	if lightning_effect != null:
		lightning_effect.visible = false
		# Each card needs its own material instance so intensity is independent
		if lightning_effect.material != null:
			lightning_effect.material = lightning_effect.material.duplicate()
	if lock_icon != null:
		lock_icon.visible = false

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		# Update pivot point when card is resized
		_update_pivot()

func set_chaos_level(level: int) -> void:
	_chaos_level = level

func _process(delta: float) -> void:
	# 70%+: suit distort / glitch on art
	if _chaos_level >= CHAOS_GLITCH_THRESHOLD and art != null:
		_glitch_timer += delta
		if _glitch_timer >= GLITCH_INTERVAL:
			_glitch_timer = 0.0
			_trigger_suit_glitch()

func _trigger_suit_glitch() -> void:
	if art == null:
		return
	if _glitch_tween != null and _glitch_tween.is_valid():
		_glitch_tween.kill()
	# Start from clean scale so tween is visible
	art.scale = Vector2.ONE
	# Center pivot so stretch/wobble distorts from middle
	var art_size := art.size
	if art_size.x <= 0 or art_size.y <= 0:
		art_size = art.custom_minimum_size
	if art_size.x > 0 and art_size.y > 0:
		art.pivot_offset = art_size * 0.5
	_glitch_tween = create_tween()
	var tween: Tween = _glitch_tween
	tween.set_parallel(true)
	# Color flash (slightly longer so it's visible)
	tween.tween_property(art, "modulate", Color(1.18, 0.82, 0.9, 1.0), 0.05)
	tween.chain().tween_property(art, "modulate", Color(0.85, 1.1, 0.95, 1.0), 0.05)
	tween.chain().tween_property(art, "modulate", Color.WHITE, 0.08)
	# Stretch vertical + wobble then recover (longer durations, bigger scale)
	tween.tween_property(art, "scale", GLITCH_STRETCH_SCALE, GLITCH_STRETCH_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(art, "scale", GLITCH_WOBBLE_SCALE, GLITCH_WOBBLE_DURATION).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(art, "scale", Vector2.ONE, GLITCH_RECOVER_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_callback(func() -> void:
		if art != null:
			art.scale = Vector2.ONE
		_glitch_tween = null
	)

func _update_pivot() -> void:
	# Set pivot to center of the card for rotation
	if size.x > 0 and size.y > 0:
		pivot_offset = size / 2.0

func _on_pressed() -> void:
	# Don't show highlight here - it will be shown only if lock succeeds
	card_pressed.emit(slot_index)

func show_highlight() -> void:
	if highlight_border == null:
		push_error("HighlightBorder node not found in CardView!")
		return
	
	# Show highlight border immediately
	highlight_border.visible = true
	highlight_border.modulate.a = 1.0
	
	# Pulse animation for visual feedback
	var tween := create_tween()
	tween.set_loops(2)
	tween.tween_property(highlight_border, "modulate:a", 0.8, 0.1)
	tween.tween_property(highlight_border, "modulate:a", 1.0, 0.1)

func hide_highlight() -> void:
	if highlight_border == null:
		return
	
	# Fade out highlight
	var tween := create_tween()
	tween.tween_property(highlight_border, "modulate:a", 0.0, 0.2)
	tween.tween_callback(func(): 
		if highlight_border != null:
			highlight_border.visible = false
	)

func set_locked(locked: bool) -> void:
	is_locked = locked
	
	# Lock UX: show a lock icon instead of a green border
	if lock_icon != null:
		lock_icon.visible = is_locked
	
	# Remove the green lock border to reduce visual noise
	if highlight_border != null:
		highlight_border.visible = false
		highlight_border.modulate.a = 0.0

func set_scoring(scoring: bool) -> void:
	is_scoring = scoring
	
	if score_highlight == null:
		pass
	
	if scoring:
		if score_highlight != null:
			score_highlight.visible = false
		_start_lightning()
	else:
		_stop_scoring_pulse()
		_stop_lightning()
		if score_highlight != null:
			score_highlight.visible = false
			score_highlight.modulate.a = 0.0

func _start_scoring_pulse() -> void:
	_scoring_pulse_token += 1
	var token := _scoring_pulse_token
	_stop_scoring_pulse()
	
	# Reset baseline scale before pulsing
	scale = Vector2.ONE
	
	_scoring_pulse_tween = create_tween()
	_scoring_pulse_tween.set_trans(Tween.TRANS_SINE)
	_scoring_pulse_tween.set_ease(Tween.EASE_IN_OUT)
	_scoring_pulse_tween.set_loops() # loop until we stop it
	
	# 95% -> 102% -> 95% (feel: breathing pulse)
	var min_scale := Vector2(0.95, 0.95)
	var max_scale := Vector2(1.02, 1.02)
	# Slower pulse (less twitchy): ~1.2s per full cycle
	_scoring_pulse_tween.tween_property(self, "scale", max_scale, 0.6)
	_scoring_pulse_tween.tween_property(self, "scale", min_scale, 0.6)
	
	# Stop after 1 second (glow flash then remove)
	call_deferred("_stop_scoring_pulse_after", token, 1.0)

func _stop_scoring_pulse_after(token: int, seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
	if token != _scoring_pulse_token:
		return
	_stop_scoring_pulse()

func _stop_scoring_pulse() -> void:
	_scoring_pulse_token += 1
	if _scoring_pulse_tween != null:
		_scoring_pulse_tween.kill()
		_scoring_pulse_tween = null
	scale = Vector2.ONE

## Quick pulse/glow when this row is retriggered (scale bounce + brief flash)
func play_retrigger_pulse() -> void:
	var orig_mod := modulate
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector2(1.14, 1.14), 0.08)
	tween.tween_property(self, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	# Brief purple flash for retrigger, then restore
	var purple_flash := Color(0.92, 0.75, 1.0, 1.0)
	var flash := create_tween()
	flash.tween_property(self, "modulate", purple_flash, 0.06)
	flash.tween_property(self, "modulate", orig_mod, 0.14)

func _start_lightning() -> void:
	if lightning_effect == null:
		return
	_stop_lightning_tween()
	lightning_effect.visible = true
	# Ramp intensity from 0 to full over 0.15s for a sharp strike-in feel
	var mat := lightning_effect.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("intensity", 0.0)
		_lightning_tween = create_tween()
		_lightning_tween.tween_method(
			func(v: float): mat.set_shader_parameter("intensity", v),
			0.0, 1.0, 0.15
		)
	# No duration limit: lightning stays until next spin (clear_scoring_highlights)

func _stop_lightning() -> void:
	_stop_lightning_tween()
	if lightning_effect != null:
		lightning_effect.visible = false
		var mat := lightning_effect.material as ShaderMaterial
		if mat:
			mat.set_shader_parameter("intensity", 0.0)

func _stop_lightning_tween() -> void:
	if _lightning_tween != null:
		_lightning_tween.kill()
		_lightning_tween = null

## Purely visual: show alternate texture/modulate for 0.1s flicker. Caller restores with set_card_visual/update_card_visual.
func apply_flicker_visual(tex: Texture2D, mod: Color = Color.WHITE) -> void:
	if art == null:
		return
	art.texture = tex
	art.modulate = mod
	if tex != null:
		art.visible = true

func set_card_visual(_text_value: String, tex: Texture2D) -> void:
	if art == null:
		push_error("CardView: Cannot set card visual - art node is null!")
		return
	
	art.texture = tex
	
	# Make sure the art is visible and properly configured
	if tex != null:
		art.visible = true
		art.modulate = Color.WHITE
		# Ensure art fills the button
		art.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		
	else:
		# Empty slot - hide the art
		art.visible = false
	
	# Check if this is a joker texture (jokers have specific pixel-art requirements)
	if tex != null:
		var tex_path = tex.resource_path
		if tex_path != null and "joker" in tex_path.to_lower():
			is_displaying_joker = true
			_configure_joker_display()
		else:
			is_displaying_joker = false
			_configure_card_display()
	else:
		is_displaying_joker = false

func _configure_joker_display() -> void:
	# Configure TextureRect for pixel-perfect joker display
	# Following client's pixel-art template requirements:
	# - Keep aspect centered (no stretching)
	# - No filtering (pixel-perfect) - handled by import settings
	if art == null:
		return
	
	# Set stretch mode to keep aspect (no stretching)
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	
	# Ensure art is visible and properly sized
	art.visible = true
	art.modulate = Color.WHITE
	
	# Note: Texture filtering is controlled by import settings
	# Joker textures should have Filter = Off in import settings for pixel-perfect rendering

func _configure_card_display() -> void:
	# Configure TextureRect for regular card display
	if art == null:
		return
	
	# Regular cards can use standard stretch mode
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	
	# Ensure art is visible and properly sized
	art.visible = true
	art.modulate = Color.WHITE

## Animates card rotation from center axis when changing
func animate_rotate(new_texture: Texture2D, duration: float = 0.4) -> void:
	if is_animating:
		return
	
	is_animating = true
	
	# Ensure pivot is at center
	_update_pivot()
	
	# Store initial rotation
	var start_rotation = rotation_degrees
	
	# Create tween for rotation animation
	var tween := create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_IN_OUT)
	
	# Rotate 180 degrees and fade out
	tween.tween_property(self, "rotation_degrees", start_rotation + 180.0, duration * 0.5)
	tween.tween_property(self, "modulate:a", 0.0, duration * 0.5)
	
	# Change texture at midpoint (when card is fully rotated and invisible)
	await tween.finished
	
	# Update texture
	art.texture = new_texture
	
	# Continue rotation from 180 to 360 (completing full rotation)
	var tween2 := create_tween()
	tween2.set_parallel(true)
	tween2.set_trans(Tween.TRANS_CUBIC)
	tween2.set_ease(Tween.EASE_IN_OUT)
	tween2.tween_property(self, "rotation_degrees", start_rotation + 360.0, duration * 0.5)
	tween2.tween_property(self, "modulate:a", 1.0, duration * 0.5)
	
	await tween2.finished
	
	# Reset rotation to start position (normalize to 0-360 range)
	rotation_degrees = fmod(rotation_degrees, 360.0)
	if rotation_degrees < 0:
		rotation_degrees += 360.0
	
	is_animating = false
	animation_complete.emit()

## Animates card flip when changing (kept for compatibility)
func animate_flip(new_texture: Texture2D, duration: float = 0.3) -> void:
	# Use rotation animation instead
	animate_rotate(new_texture, duration)

## Animates card fade when changing
func animate_fade(new_texture: Texture2D, duration: float = 0.25) -> void:
	if is_animating:
		return
	
	is_animating = true
	
	var tween := create_tween()
	tween.set_parallel(true)
	
	# Fade out
	tween.tween_property(self, "modulate:a", 0.0, duration * 0.5)
	
	await tween.finished
	
	# Change texture
	art.texture = new_texture
	
	# Fade in
	var tween2 := create_tween()
	tween2.tween_property(self, "modulate:a", 1.0, duration * 0.5)
	
	await tween2.finished
	is_animating = false
	animation_complete.emit()

## Animates card with scale bounce
func animate_bounce(new_texture: Texture2D, duration: float = 0.3) -> void:
	if is_animating:
		return
	
	is_animating = true
	
	var tween := create_tween()
	tween.set_parallel(true)
	
	# Scale down and fade
	tween.tween_property(self, "scale", Vector2(0.8, 0.8), duration * 0.4)
	tween.tween_property(self, "modulate:a", 0.3, duration * 0.4)
	
	await tween.finished
	
	# Change texture
	art.texture = new_texture
	
	# Bounce back with overshoot
	var tween2 := create_tween()
	tween2.set_parallel(true)
	tween2.tween_property(self, "scale", Vector2(1.1, 1.1), duration * 0.3)
	tween2.tween_property(self, "modulate:a", 1.0, duration * 0.3)
	
	await tween2.finished
	
	# Settle to normal size
	var tween3 := create_tween()
	tween3.tween_property(self, "scale", Vector2(1.0, 1.0), duration * 0.3)
	
	await tween3.finished
	is_animating = false
	animation_complete.emit()
