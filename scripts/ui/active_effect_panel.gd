extends PanelContainer
class_name ActiveEffectPanel

## Displays active jokers that affect scoring

# Use get_node_or_null() so this script works both when attached to the
# standalone ActiveEffectPanel scene (with OuterMargin/...) and when used
# on the simpler PanelContainer in Main.tscn (without those children).
@onready var icon1: TextureRect = get_node_or_null(
	"OuterMargin/VBox/IconRow/IconSlot1/IconPanel1/IconMargin1/Icon1"
)
@onready var icon2: TextureRect = get_node_or_null(
	"OuterMargin/VBox/IconRow/IconSlot2/IconPanel2/IconMargin2/Icon2"
)
@onready var icon3: TextureRect = get_node_or_null(
	"OuterMargin/VBox/IconRow/IconSlot3/IconPanel3/IconMargin3/Icon3"
)
@onready var icon4: TextureRect = get_node_or_null(
	"OuterMargin/VBox/IconRow/IconSlot4/IconPanel4/Icon4"
)

@onready var label1: Label = get_node_or_null(
	"OuterMargin/VBox/IconRow/IconSlot1/Label1"
)
@onready var label2: Label = get_node_or_null(
	"OuterMargin/VBox/IconRow/IconSlot2/Label2"
)
@onready var label3: Label = get_node_or_null(
	"OuterMargin/VBox/IconRow/IconSlot3/Label3"
)
@onready var label4: Label = get_node_or_null(
	"OuterMargin/VBox/IconRow/IconSlot4/Label4"
)

@onready var slot1: VBoxContainer = get_node_or_null(
	"OuterMargin/VBox/IconRow/IconSlot1"
)
@onready var slot2: VBoxContainer = get_node_or_null(
	"OuterMargin/VBox/IconRow/IconSlot2"
)
@onready var slot3: VBoxContainer = get_node_or_null(
	"OuterMargin/VBox/IconRow/IconSlot3"
)
@onready var slot4: VBoxContainer = get_node_or_null(
	"OuterMargin/VBox/IconRow/IconSlot4"
)

@onready var chaos_bar: ProgressBar = get_node_or_null(
	"OuterMargin/VBox/ChaosBarContainer/ChaosBarWrapper/ChaosBar"
)
@onready var chaos_label: Label = get_node_or_null(
	"OuterMargin/VBox/ChaosBarContainer/ChaosValueLabel"
)

# Optional vertical chaos bar (TextureProgressBar) defined in Main.tscn
# Path: ActiveEffectPanel/HBoxContainer/TextureProgressBar
@onready var chaos_bar_texture: TextureProgressBar = get_node_or_null(
	"HBoxContainer/TextureProgressBar"
)
@onready var chaos_bar_texture_label: Label = get_node_or_null(
	"HBoxContainer/Label"
)
# Spark burst when chaos changes (Main.tscn left panel: ChaosSparkLayer/ChaosFX/SparkBurst)
@onready var chaos_fx: Node2D = get_node_or_null("ChaosSparkLayer/ChaosFX")
@onready var spark_burst: GPUParticles2D = get_node_or_null("ChaosSparkLayer/ChaosFX/SparkBurst")

# Chaos change: left = HBoxContainer (image row), right = Label fallback
var chaos_change_display: Control = null
const CHAOS_TEXT_ASSET_PATH := "res://assets/text/"
const CHAOS_CHANGE_DIGIT_H := 44.0
const CHAOS_CHANGE_WORD_H := 36.0
const CHAOS_CHANGE_SIZE_MULT := 1.2  # 120% size
var _chaos_digit_textures: Array = []
var _chaos_plus_texture: Texture2D
var _chaos_minus_texture: Texture2D
var _chaos_word_texture: Texture2D

var game: Node = null
var texture_resolver: CardTextureResolver = null
var icon_slots: Array[TextureRect] = []
var label_slots: Array[Label] = []
var slot_containers: Array[VBoxContainer] = []

# Chaos threshold constants (matching game.gd)
const CHAOS_STABLE := 30
const CHAOS_INSTABILITY := 30
const CHAOS_INTERFERENCE := 60
const CHAOS_COLLAPSE_WARNING := 90
const CHAOS_COLLAPSE := 100
# Chaos bar texture (single image for fill)
const CHAOS_BAR_TEXTURE := "res://assets/background/bar2.png"
const CHAOS_BAR_TWEEN_DURATION := 1  # Smooth bar fill animation
# Chaos value label pop when value changes (scale up then back, near the bar)
const CHAOS_POP_SCALE := 1.35
const CHAOS_POP_UP_DURATION := 0.08
const CHAOS_POP_DOWN_DURATION := 0.2
# Joker icon flash when score effect applies (one quick flash — bright + scale pop)
const JOKER_FLASH_UP_DURATION := 0.3
const JOKER_FLASH_DOWN_DURATION := 0.3
const JOKER_FLASH_BRIGHTNESS := 1.7
const JOKER_FLASH_SCALE := 1.15

var current_chaos: int = 0
var max_chaos: int = 100
var _prev_chaos_for_spark: int = -1
var _pending_chaos_bar_from_spin: bool = false  # Bar value tween runs with chaos change pop on total_score_hidden
var _chaos_bar_updated_this_sequence: bool = false  # True when bar was updated early (before BASE SCORE)
var is_flashing: bool = false
var flash_tween: Tween = null
var chaos_value_tween: Tween = null  # Smooth chaos value change
var _chaos_pop_tween: Tween = null   # Pop animation for chaos value label
var _chaos_change_tween: Tween = null
var _chaos_shown_this_sequence: bool = false  # True after we run chaos gain on total_score_hidden
const CHAOS_CHANGE_DISPLAY_DURATION := 1.0
# Chaos change appears after total disappears; pop from bottom to top
const CHAOS_CHANGE_POP_OFFSET_Y := 56.0
const CHAOS_CHANGE_POP_DURATION := 0.28

## When Chaos >= this, we may show atmospheric warning instead of "+N chaos" (rarely)
const CHAOS_WARNING_THRESHOLD := 80
## Chance to show warning when chaos >= threshold and gain > 0 (not every spin)
const CHAOS_WARNING_CHANCE := 0.28
const CHAOS_WARNING_LINES: Array[String] = [
	"It's growing.",
	"You pushed too far.",
	"One more."
]

const TOOLTIP_SCENE: PackedScene = preload("res://scenes/ui/tooltip_popup.tscn")

signal chaos_bar_update_finished()

func _ready() -> void:
	add_to_group("active_effect_panel")
	icon_slots = [icon1, icon2, icon3, icon4]
	label_slots = [label1, label2, label3, label4]
	slot_containers = [slot1, slot2, slot3, slot4]
	
	# Show all slots so panel bg is visible when no joker; hide only slot4 if missing
	# Connect click on the icon (TextureRect) so we receive events — slot container may be covered by child controls
	for i in range(slot_containers.size()):
		if slot_containers[i]:
			slot_containers[i].visible = (i < 3)  # Show first 3 slots always
		if icon_slots[i]:
			icon_slots[i].mouse_filter = Control.MOUSE_FILTER_STOP
			icon_slots[i].gui_input.connect(_on_joker_slot_gui_input.bind(i))
	
	call_deferred("_initialize_game")

func _initialize_game() -> void:
	# Find game controller
	game = get_node_or_null("/root/Main/Game")
	if game == null:
		game = get_tree().get_first_node_in_group("game")
	
	if game == null:
		push_error("Game controller not found in ActiveEffectPanel!")
		return
	
	# Wait for game to be fully initialized
	var attempts := 0
	while (not is_instance_valid(game.texture_resolver) or not is_instance_valid(game.board)) and attempts < 10:
		await get_tree().process_frame
		attempts += 1
	
	if not is_instance_valid(game.texture_resolver):
		push_error("Texture resolver not initialized in ActiveEffectPanel!")
		return
	
	texture_resolver = game.texture_resolver
	# Connect to joker change signals
	game.jokers_changed.connect(_update_joker_display)
	if game.has_signal("spin_started"):
		game.spin_started.connect(_on_spin_started)
	if game.has_signal("spin_breakdown"):
		game.spin_breakdown.connect(_on_spin_breakdown)
	if game.has_signal("total_score_hidden"):
		game.total_score_hidden.connect(_on_total_score_hidden)
	# Connect to chaos change signals
	if game.run_state:
		game.run_state.chaos_changed.connect(_on_chaos_changed)
		# Initialize chaos bar
		_on_chaos_changed(game.run_state.chaos, game.run_state.MAX_CHAOS)
	# Update display with current jokers
	_update_joker_display()
	
	# Resolve chaos change display (left: ChaosChangeContent HBox; right: ChaosChangeLabel)
	chaos_change_display = get_node_or_null("ChaosSparkLayer/ChaosChangeContent")
	if chaos_change_display == null:
		chaos_change_display = get_node_or_null("OuterMargin/VBox/ChaosBarContainer/ChaosChangeLabel")
	_load_chaos_text_assets()
	# Configure chaos bar appearance
	_configure_chaos_bar()

func _update_joker_display() -> void:
	if game == null or texture_resolver == null:
		return
	
	# Clear all icon textures and labels; keep first 3 slots visible so panel bg shows when empty
	var num_slots: int = min(slot_containers.size(), 3)
	for i in range(slot_containers.size()):
		if slot_containers[i]:
			slot_containers[i].visible = (i < num_slots)
		if icon_slots[i]:
			icon_slots[i].texture = null
		if label_slots[i]:
			label_slots[i].text = ""
	
	# Display owned (collected) jokers so reward fly-to-panel lands in the right slot
	var jokers_to_show = game.owned_jokers
	
	for i in range(min(jokers_to_show.size(), icon_slots.size())):
		var joker = jokers_to_show[i]
		if joker == null:
			continue
		
		var joker_id = _get_joker_id(joker)
		if joker_id > 0:
			var tex = texture_resolver.get_joker_texture(joker_id)
			if tex and icon_slots[i]:
				icon_slots[i].texture = tex
			if label_slots[i]:
				var joker_name = joker.get("name")
				var joker_desc = joker.get("description")
				if joker_name:
					label_slots[i].text = joker_name
				elif joker_desc:
					label_slots[i].text = joker_desc
				else:
					label_slots[i].text = "Joker " + str(joker_id)

func _get_joker_id(joker) -> int:
	if joker == null:
		return 0
	
	# Check if it's a JokerCard instance (has joker_id property)
	# Use get() method which works for both Resources and Objects
	var joker_id_value = joker.get("joker_id")
	if joker_id_value != null:
		return int(joker_id_value)
	
	# Try to extract from id string (e.g., "joker1" -> 1)
	var id_value = joker.get("id")
	if id_value != null:
		var id_str = str(id_value)
		if id_str.begins_with("joker"):
			var num_str = id_str.substr(5)  # Remove "joker" prefix
			var num = num_str.to_int()
			if num > 0:
				return num
	
	return 0

func _on_joker_slot_gui_input(event: InputEvent, slot_index: int) -> void:
	if not event is InputEventMouseButton:
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return
	if game == null or game.get("owned_jokers") == null:
		return
	var owned: Array = game.owned_jokers
	if slot_index < 0 or slot_index >= owned.size():
		return
	var text := _get_joker_info_text(slot_index)
	if text.is_empty():
		return
	var center := get_joker_slot_global_center(slot_index)
	if center.is_equal_approx(Vector2.ZERO):
		return
	var tip = TOOLTIP_SCENE.instantiate()
	if tip != null and tip.has_method("show_tooltip"):
		get_tree().root.add_child(tip)
		tip.show_tooltip(text, center)

func _get_joker_info_text(slot_index: int) -> String:
	if game == null or game.get("owned_jokers") == null:
		return ""
	var owned: Array = game.owned_jokers
	if slot_index < 0 or slot_index >= owned.size():
		return ""
	var joker = owned[slot_index]
	if joker == null:
		return ""
	var joker_id: int = _get_joker_id(joker)
	if joker_id <= 0:
		return ""
	var joker_desc: String = ""
	if joker.get("description") != null:
		joker_desc = str(joker.description)
	if joker_desc.is_empty():
		joker_desc = "Joker card"
	var chaos_info: Array = []
	# Resource.get() takes one argument only; use default when null
	var cost_val = joker.get("chaos_cost")
	var cost: int = int(cost_val) if cost_val != null else 0
	if cost > 0:
		chaos_info.append("+%d chaos" % cost)
	var can_reduce_val = joker.get("can_reduce_chaos")
	var can_reduce: bool = bool(can_reduce_val) if can_reduce_val != null else false
	var reduction_val = joker.get("chaos_reduction")
	var reduction: int = int(reduction_val) if reduction_val != null else 0
	if can_reduce and reduction > 0:
		chaos_info.append("-%d chaos" % reduction)
	if not chaos_info.is_empty():
		joker_desc += " (" + ", ".join(chaos_info) + ")"
	return "Joker %d: %s" % [joker_id, joker_desc]

## Returns global center of the joker icon at slot_index (for reward fly-to-panel animation).
func get_joker_slot_global_center(slot_index: int) -> Vector2:
	if slot_index < 0 or slot_index >= icon_slots.size():
		return Vector2.ZERO
	var icon: TextureRect = icon_slots[slot_index]
	if icon == null or not is_instance_valid(icon):
		return Vector2.ZERO
	var rect := icon.get_global_rect()
	return rect.get_center()

func _on_total_score_hidden(breakdown: Dictionary) -> void:
	# After total + retrigger overlay have fully disappeared; chaos text + sound + bar run here
	_run_chaos_gain_from_breakdown(breakdown)

func _run_chaos_gain_from_breakdown(breakdown: Dictionary) -> void:
	var chaos_data: Dictionary = breakdown.get("chaos", {})
	if chaos_data == null:
		_emit_score_sequence_finished()
		return
	var chaos_before: int = int(chaos_data.get("chaos_before", current_chaos))
	var chaos_after: int = int(chaos_data.get("chaos_after", current_chaos))
	var net_change: int = int(chaos_data.get("net_change", 0))

	# Spin flow order: (1) Tier effects (2) Camera shake (3) Chaos bar pulse
	_check_chaos_thresholds(chaos_after)
	var main_ui_node = get_tree().get_first_node_in_group("main_ui")
	if main_ui_node != null and main_ui_node.has_method("trigger_chaos_tier_shake"):
		main_ui_node.trigger_chaos_tier_shake(chaos_before, chaos_after)

	if _pending_chaos_bar_from_spin and not _chaos_bar_updated_this_sequence:
		_pending_chaos_bar_from_spin = false
		_chaos_shown_this_sequence = true
		_tween_chaos_bar_with_chaos_change(chaos_before, chaos_after)
		if chaos_label:
			chaos_label.text = "%d / %d" % [chaos_after, max_chaos]
		if chaos_bar_texture_label != null:
			chaos_bar_texture_label.text = "%d / %d" % [chaos_after, max_chaos]
		if chaos_after != chaos_before:
			_play_chaos_spark(chaos_before, chaos_after)
			_pop_chaos_value()
		_prev_chaos_for_spark = chaos_after
	elif _chaos_bar_updated_this_sequence:
		_chaos_shown_this_sequence = true
		if chaos_label:
			chaos_label.text = "%d / %d" % [chaos_after, max_chaos]
		if chaos_bar_texture_label != null:
			chaos_bar_texture_label.text = "%d / %d" % [chaos_after, max_chaos]
		if chaos_after != chaos_before:
			_play_chaos_spark(chaos_before, chaos_after)
			_pop_chaos_value()
		_prev_chaos_for_spark = chaos_after

	# Show chaos change text only when bar was not already updated in score phase (then text was shown in sync with bar)
	if net_change != 0 and chaos_change_display != null and not _chaos_bar_updated_this_sequence:
		if _chaos_change_tween != null and _chaos_change_tween.is_valid():
			_chaos_change_tween.kill()
		var chaos_mult: float = float(chaos_data.get("chaos_multiplier", 1.0))
		var warning_text: String = _get_chaos_warning_display(chaos_after, net_change)
		if not warning_text.is_empty():
			if chaos_change_display is HBoxContainer:
				_build_chaos_warning_label(chaos_change_display as HBoxContainer, warning_text)
			elif chaos_change_display is Label:
				(chaos_change_display as Label).text = warning_text
		else:
			if chaos_change_display is HBoxContainer:
				_build_chaos_change_row(chaos_change_display as HBoxContainer, net_change, chaos_mult)
			elif chaos_change_display is Label:
				var txt: String = "+%d chaos" % net_change if net_change > 0 else "%d chaos" % net_change
				(chaos_change_display as Label).text = txt
		chaos_change_display.visible = true
		var parent := chaos_change_display.get_parent()
		if parent != null and parent.name == "ChaosBarContainer":
			parent.visible = true
		chaos_change_display.modulate = Color(1, 1, 1, 0)
		var sm = get_node_or_null("/root/SfxManager")
		if sm:
			sm.play_chaos_threshold_if_crossed(chaos_before, chaos_after)
		if chaos_bar_texture != null and chaos_change_display.get_parent() is CanvasLayer:
			_play_chaos_change_pop_over_bar()
		else:
			chaos_change_display.modulate.a = 1.0
			_position_chaos_change_over_bar()
			_start_chaos_change_hide_tween()
	if net_change == 0:
		_emit_score_sequence_finished()

func _emit_score_sequence_finished() -> void:
	if game != null and game.has_signal("score_sequence_finished"):
		game.emit_signal("score_sequence_finished")

func _on_spin_started() -> void:
	_chaos_shown_this_sequence = false
	_chaos_bar_updated_this_sequence = false
	_pending_chaos_bar_from_spin = true

func _on_spin_breakdown(_breakdown: Dictionary) -> void:
	# Chaos change + bar tween happen after total disappears (see _on_total_score_hidden)
	_pending_chaos_bar_from_spin = true
	# Joker icon flash now happens in play_joker_bonus_and_chaos_multiplier_animation (spin flow)

## Joker bonus impact: golden color for light burst (bright, visible).
const JOKER_BONUS_GOLD := Color(1.15, 0.9, 0.35, 1.0)
const JOKER_BONUS_FLASH_DURATION := 0.38

## Spin flow: "JOKER BONUS" text is shown by overlay; here we flash the joker icon + golden light burst.
func show_multiplier_step(breakdown: Dictionary, step_display_index: int) -> void:
	var score_data: Dictionary = breakdown.get("score", {})
	var multipliers: Array = score_data.get("multipliers", []) if score_data else []
	if step_display_index >= multipliers.size():
		return
	var mult_entry: Dictionary = multipliers[step_display_index]
	var joker_id: int = int(mult_entry.get("joker_id", 0))
	if game == null or joker_id <= 0:
		return
	var active_jokers = game.active_jokers
	for slot_idx in range(min(active_jokers.size(), icon_slots.size())):
		if _get_joker_id(active_jokers[slot_idx]) == joker_id:
			_flash_joker_icon(slot_idx)
			break
	# Golden light burst (flash on chaos bar / panel)
	_flash_chaos_bar(JOKER_BONUS_GOLD, JOKER_BONUS_FLASH_DURATION, false)

## Legacy: one-shot joker flash + chaos mult (replaced by show_multiplier_step per step).
func play_joker_bonus_and_chaos_multiplier_animation(breakdown: Dictionary) -> void:
	var score_data: Dictionary = breakdown.get("score", {})
	if score_data == null:
		score_data = {}
	var multipliers: Array = score_data.get("multipliers", [])
	var active_jokers = game.active_jokers if game else []
	for mult_entry in multipliers:
		var mult: float = float(mult_entry.get("multiplier", 1.0))
		if mult <= 1.0:
			continue
		var joker_id: int = int(mult_entry.get("joker_id", 0))
		if joker_id <= 0:
			continue
		for slot_idx in range(min(active_jokers.size(), icon_slots.size())):
			if _get_joker_id(active_jokers[slot_idx]) == joker_id:
				_flash_joker_icon(slot_idx)
				break
	var chaos_data: Dictionary = breakdown.get("chaos", {})
	if chaos_data == null:
		chaos_data = {}
	var chaos_mult: float = float(chaos_data.get("chaos_multiplier", 1.0))
	if chaos_mult > 1.0 and chaos_change_display != null:
		if chaos_change_display is Label:
			(chaos_change_display as Label).text = "x%.1f" % chaos_mult
		elif chaos_change_display is HBoxContainer:
			_clear_chaos_content(chaos_change_display as HBoxContainer)
			var lbl: Label = Label.new()
			lbl.text = "x%.1f" % chaos_mult
			lbl.add_theme_font_size_override("font_size", 32)
			lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
			(chaos_change_display as HBoxContainer).add_child(lbl)
		chaos_change_display.visible = true
		chaos_change_display.modulate.a = 0.0
		chaos_change_display.scale = Vector2(0.5, 0.5)
		call_deferred("_position_chaos_multiplier_over_bar")
		var t: Tween = create_tween()
		t.tween_property(chaos_change_display, "modulate:a", 1.0, 0.15)
		t.parallel().tween_property(chaos_change_display, "scale", Vector2(1.2, 1.2), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_property(chaos_change_display, "scale", Vector2.ONE, 0.1)

func _flash_joker_icon(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= icon_slots.size():
		return
	var icon: TextureRect = icon_slots[slot_index]
	if icon == null or not is_instance_valid(icon):
		return
	# Scale from center
	if icon.size.x > 0 and icon.size.y > 0:
		icon.pivot_offset = icon.size * 0.5
	var tween := create_tween()
	tween.set_parallel(true)
	# Brighter modulate
	tween.tween_property(icon, "modulate", Color(JOKER_FLASH_BRIGHTNESS, JOKER_FLASH_BRIGHTNESS, JOKER_FLASH_BRIGHTNESS, 1.0), JOKER_FLASH_UP_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(icon, "scale", Vector2(JOKER_FLASH_SCALE, JOKER_FLASH_SCALE), JOKER_FLASH_UP_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.set_parallel(false)
	tween.tween_property(icon, "modulate", Color.WHITE, JOKER_FLASH_DOWN_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tween.parallel().tween_property(icon, "scale", Vector2.ONE, JOKER_FLASH_DOWN_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)

func _load_chaos_text_assets() -> void:
	if not _chaos_digit_textures.is_empty():
		return
	for i in range(10):
		var tex: Texture2D = load(CHAOS_TEXT_ASSET_PATH + str(i) + ".png") as Texture2D
		_chaos_digit_textures.append(tex if tex else null)
	_chaos_plus_texture = load(CHAOS_TEXT_ASSET_PATH + "plus.png") as Texture2D
	_chaos_minus_texture = load(CHAOS_TEXT_ASSET_PATH + "minus.png") as Texture2D
	_chaos_word_texture = load(CHAOS_TEXT_ASSET_PATH + "chaos.png") as Texture2D

func _clear_chaos_content(container: HBoxContainer) -> void:
	if container == null:
		return
	for c in container.get_children():
		c.queue_free()

## Returns one of the atmospheric warning lines when chaos >= 80 and rarely; else "".
func _get_chaos_warning_display(chaos_after: int, net_change: int) -> String:
	if chaos_after < CHAOS_WARNING_THRESHOLD or net_change <= 0:
		return ""
	if randf() >= CHAOS_WARNING_CHANCE:
		return ""
	if CHAOS_WARNING_LINES.is_empty():
		return ""
	var idx := randi() % CHAOS_WARNING_LINES.size()
	return CHAOS_WARNING_LINES[idx]

func _build_chaos_warning_label(content: HBoxContainer, text: String) -> void:
	if content == null or text.is_empty():
		return
	_clear_chaos_content(content)
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", int(CHAOS_CHANGE_WORD_H * 1.2))
	content.add_child(label)

func _build_chaos_change_row(content: HBoxContainer, value: int, _chaos_multiplier: float = 1.0) -> void:
	if content == null:
		return
	_clear_chaos_content(content)
	var str_val: String = str(abs(value))
	var sign_tex: Texture2D = _chaos_plus_texture if value >= 0 else _chaos_minus_texture
	var digit_h: float = CHAOS_CHANGE_DIGIT_H * CHAOS_CHANGE_SIZE_MULT
	var word_h: float = CHAOS_CHANGE_WORD_H * CHAOS_CHANGE_SIZE_MULT
	if sign_tex:
		var sign_tr: TextureRect = TextureRect.new()
		sign_tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		sign_tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var ss: Vector2 = sign_tex.get_size()
		var sign_h: float = digit_h * 0.85
		sign_tr.custom_minimum_size = Vector2(ss.x * sign_h / ss.y if ss.y > 0 else sign_h, sign_h)
		sign_tr.texture = sign_tex
		content.add_child(sign_tr)
	for i in range(str_val.length()):
		var d: int = str_val.substr(i, 1).to_int()
		if d >= 0 and d < _chaos_digit_textures.size() and _chaos_digit_textures[d] is Texture2D:
			var digit_rect: TextureRect = TextureRect.new()
			digit_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			digit_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			digit_rect.custom_minimum_size = Vector2(digit_h * 0.6, digit_h)
			digit_rect.texture = _chaos_digit_textures[d]
			content.add_child(digit_rect)
	if _chaos_word_texture:
		var word_tr: TextureRect = TextureRect.new()
		word_tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		word_tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var ws: Vector2 = _chaos_word_texture.get_size()
		word_tr.custom_minimum_size = Vector2(ws.x * word_h / ws.y if ws.y > 0 else word_h, word_h)
		word_tr.texture = _chaos_word_texture
		content.add_child(word_tr)

func _position_chaos_change_over_bar() -> void:
	if chaos_change_display == null or chaos_bar_texture == null or not chaos_change_display.visible:
		return
	var bar_rect: Rect2 = chaos_bar_texture.get_global_rect()
	var center: Vector2 = bar_rect.get_center()
	chaos_change_display.global_position = center - chaos_change_display.size * 0.5

func _position_chaos_multiplier_over_bar() -> void:
	if chaos_change_display == null or chaos_bar_texture == null or not chaos_change_display.visible:
		return
	var bar_rect: Rect2 = chaos_bar_texture.get_global_rect()
	var center: Vector2 = bar_rect.get_center()
	chaos_change_display.global_position = center - chaos_change_display.size * 0.5

func _play_chaos_change_pop_over_bar() -> void:
	if chaos_change_display == null or chaos_bar_texture == null:
		return
	var bar_rect: Rect2 = chaos_bar_texture.get_global_rect()
	var center: Vector2 = bar_rect.get_center()
	var final_global: Vector2 = center - chaos_change_display.size * 0.5
	var start_global: Vector2 = final_global + Vector2(0, CHAOS_CHANGE_POP_OFFSET_Y)
	chaos_change_display.global_position = start_global
	if _chaos_change_tween != null and _chaos_change_tween.is_valid():
		_chaos_change_tween.kill()
	_chaos_change_tween = create_tween()
	_chaos_change_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_chaos_change_tween.tween_property(chaos_change_display, "global_position", final_global, CHAOS_CHANGE_POP_DURATION)
	_chaos_change_tween.parallel().tween_property(chaos_change_display, "modulate:a", 1.0, CHAOS_CHANGE_POP_DURATION * 0.6)
	_chaos_change_tween.tween_callback(_start_chaos_change_hide_tween)

func _start_chaos_change_hide_tween() -> void:
	if chaos_change_display == null:
		return
	if _chaos_change_tween != null and _chaos_change_tween.is_valid():
		_chaos_change_tween.kill()
	_chaos_change_tween = create_tween()
	# Show chaos text for 0.5s then enable spin; fade out runs in parallel for polish
	_chaos_change_tween.tween_interval(CHAOS_CHANGE_DISPLAY_DURATION)
	_chaos_change_tween.tween_callback(func() -> void:
		_emit_score_sequence_finished()  # Spin button enables after chaos text + sound (0.5s)
	)
	_chaos_change_tween.tween_property(chaos_change_display, "modulate:a", 0.0, 0.4)
	_chaos_change_tween.tween_callback(func() -> void:
		if chaos_change_display:
			chaos_change_display.visible = false
			var p := chaos_change_display.get_parent()
			if p != null and p.name == "ChaosBarContainer":
				p.visible = false
	)

func _configure_chaos_bar() -> void:
	if chaos_bar == null:
		return
	
	# Set red fill color for dangerous look
	var style_box = StyleBoxFlat.new()
	style_box.bg_color = Color(0.8, 0.1, 0.1, 1.0)  # Dark red base
	style_box.border_width_left = 2
	style_box.border_width_top = 2
	style_box.border_width_right = 2
	style_box.border_width_bottom = 2
	style_box.border_color = Color(1.0, 0.3, 0.3, 1.0)  # Bright red border
	style_box.corner_radius_top_left = 4
	style_box.corner_radius_top_right = 4
	style_box.corner_radius_bottom_right = 4
	style_box.corner_radius_bottom_left = 4
	
	chaos_bar.add_theme_stylebox_override("fill", style_box)
	
	# Set background style
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color(0.1, 0.1, 0.1, 0.8)  # Dark background
	bg_style.border_width_left = 2
	bg_style.border_width_top = 2
	bg_style.border_width_right = 2
	bg_style.border_width_bottom = 2
	bg_style.border_color = Color(0.3, 0.3, 0.3, 1.0)
	bg_style.corner_radius_top_left = 4
	bg_style.corner_radius_top_right = 4
	bg_style.corner_radius_bottom_right = 4
	bg_style.corner_radius_bottom_left = 4
	
	chaos_bar.add_theme_stylebox_override("background", bg_style)

func _on_chaos_changed(new_chaos: int, max_chaos_value: int) -> void:
	var old_chaos: int = current_chaos
	current_chaos = new_chaos
	max_chaos = max_chaos_value

	# When a spin is pending, bar tween + spark + pop run with chaos change on total_score_hidden
	# Exception: if chaos drops to a low value (e.g. restart reset to 10), treat as reset and update bar now
	var is_restart_reset: bool = (new_chaos <= 15 and old_chaos > 50)
	if _pending_chaos_bar_from_spin and not is_restart_reset:
		if chaos_value_tween != null and chaos_value_tween.is_valid():
			chaos_value_tween.kill()
		_update_chaos_bar_texture()
		if chaos_bar != null:
			chaos_bar.max_value = max_chaos
		if chaos_bar_texture != null:
			chaos_bar_texture.max_value = max_chaos
		return
	if is_restart_reset:
		_pending_chaos_bar_from_spin = false

	# Spark burst when chaos value changes (at bar fill position)
	if _prev_chaos_for_spark >= 0 and new_chaos != _prev_chaos_for_spark:
		_play_chaos_spark(_prev_chaos_for_spark, new_chaos)
		_pop_chaos_value()
	_prev_chaos_for_spark = new_chaos

	# Kill any in-progress chaos value tween
	if chaos_value_tween != null and chaos_value_tween.is_valid():
		chaos_value_tween.kill()

	# Update labels immediately (correct number; bar fill animates)
	if chaos_label:
		chaos_label.text = "%d / %d" % [new_chaos, max_chaos]
	if chaos_bar_texture_label != null:
		chaos_bar_texture_label.text = "%d / %d" % [new_chaos, max_chaos]

	# Texture bar uses single chaos.png image
	_update_chaos_bar_texture()

	# Set max_value immediately; tween value smoothly
	if chaos_bar != null:
		chaos_bar.max_value = max_chaos
		chaos_value_tween = create_tween()
		chaos_value_tween.set_trans(Tween.TRANS_CUBIC)
		chaos_value_tween.set_ease(Tween.EASE_OUT)
		chaos_value_tween.tween_property(chaos_bar, "value", float(new_chaos), CHAOS_BAR_TWEEN_DURATION)

	if chaos_bar_texture != null:
		chaos_bar_texture.max_value = max_chaos
		if chaos_value_tween != null and chaos_value_tween.is_valid():
			chaos_value_tween.parallel().tween_property(chaos_bar_texture, "value", float(new_chaos), CHAOS_BAR_TWEEN_DURATION)
		else:
			chaos_value_tween = create_tween()
			chaos_value_tween.set_trans(Tween.TRANS_CUBIC)
			chaos_value_tween.set_ease(Tween.EASE_OUT)
			chaos_value_tween.tween_property(chaos_bar_texture, "value", float(new_chaos), CHAOS_BAR_TWEEN_DURATION)

	# Check thresholds and trigger flash effects
	_check_chaos_thresholds(new_chaos)

## Run chaos bar update before BASE SCORE (score phase). Bar and chaos change text animate in sync. Emits chaos_bar_update_finished when done.
func run_chaos_bar_update_for_score_phase(breakdown: Dictionary) -> void:
	var chaos_data: Dictionary = breakdown.get("chaos", {})
	if chaos_data == null:
		chaos_data = {}
	var chaos_before: int = int(chaos_data.get("chaos_before", current_chaos))
	var chaos_after: int = int(chaos_data.get("chaos_after", current_chaos))
	var max_chaos_val: int = int(chaos_data.get("max_chaos", 100))
	_pending_chaos_bar_from_spin = false
	_chaos_bar_updated_this_sequence = true
	# Start bar fill and chaos change text at the same time
	_tween_chaos_bar_with_chaos_change(chaos_before, chaos_after)
	_show_chaos_change_text_sync(chaos_data, chaos_before, chaos_after)
	if chaos_label:
		chaos_label.text = "%d / %d" % [chaos_after, max_chaos_val]
	if chaos_bar_texture_label != null:
		chaos_bar_texture_label.text = "%d / %d" % [chaos_after, max_chaos_val]
	if chaos_after != chaos_before:
		_play_chaos_spark(chaos_before, chaos_after)
		_pop_chaos_value()
	_prev_chaos_for_spark = chaos_after
	if chaos_value_tween != null and chaos_value_tween.is_valid():
		chaos_value_tween.finished.connect(_emit_chaos_bar_update_finished, CONNECT_ONE_SHOT)

func _emit_chaos_bar_update_finished() -> void:
	chaos_bar_update_finished.emit()

## Build and show chaos change text + pop animation (same frame as bar tween). Used for sync with bar in score phase.
func _show_chaos_change_text_sync(chaos_data: Dictionary, chaos_before: int, chaos_after: int) -> void:
	if chaos_change_display == null:
		return
	var net_change: int = int(chaos_data.get("net_change", 0))
	if net_change == 0:
		return
	if _chaos_change_tween != null and _chaos_change_tween.is_valid():
		_chaos_change_tween.kill()
	var chaos_mult: float = float(chaos_data.get("chaos_multiplier", 1.0))
	var warning_text: String = _get_chaos_warning_display(chaos_after, net_change)
	if not warning_text.is_empty():
		if chaos_change_display is HBoxContainer:
			_build_chaos_warning_label(chaos_change_display as HBoxContainer, warning_text)
		elif chaos_change_display is Label:
			(chaos_change_display as Label).text = warning_text
	else:
		if chaos_change_display is HBoxContainer:
			_build_chaos_change_row(chaos_change_display as HBoxContainer, net_change, chaos_mult)
		elif chaos_change_display is Label:
			var txt: String = "+%d chaos" % net_change if net_change > 0 else "%d chaos" % net_change
			(chaos_change_display as Label).text = txt
	chaos_change_display.visible = true
	var parent := chaos_change_display.get_parent()
	if parent != null and parent.name == "ChaosBarContainer":
		parent.visible = true
	chaos_change_display.modulate = Color(1, 1, 1, 0)
	var sm = get_node_or_null("/root/SfxManager")
	if sm:
		sm.play_chaos_threshold_if_crossed(chaos_before, chaos_after)
	if chaos_bar_texture != null and chaos_change_display.get_parent() is CanvasLayer:
		_play_chaos_change_pop_over_bar()
	else:
		chaos_change_display.modulate.a = 1.0
		_position_chaos_change_over_bar()
		_start_chaos_change_hide_tween()

func _tween_chaos_bar_with_chaos_change(chaos_before: int, chaos_after: int) -> void:
	# Run bar fill in sync with chaos change pop (same duration)
	if chaos_value_tween != null and chaos_value_tween.is_valid():
		chaos_value_tween.kill()
	if chaos_bar != null:
		chaos_bar.value = float(chaos_before)
	if chaos_bar_texture != null:
		chaos_bar_texture.value = float(chaos_before)
	chaos_value_tween = create_tween()
	chaos_value_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var first: bool = true
	if chaos_bar != null:
		chaos_value_tween.tween_property(chaos_bar, "value", float(chaos_after), CHAOS_CHANGE_POP_DURATION)
		first = false
	if chaos_bar_texture != null:
		if first:
			chaos_value_tween.tween_property(chaos_bar_texture, "value", float(chaos_after), CHAOS_CHANGE_POP_DURATION)
		else:
			chaos_value_tween.parallel().tween_property(chaos_bar_texture, "value", float(chaos_after), CHAOS_CHANGE_POP_DURATION)

func _pop_chaos_value() -> void:
	if _chaos_pop_tween != null and _chaos_pop_tween.is_valid():
		_chaos_pop_tween.kill()
	var labels: Array[Control] = []
	if chaos_label:
		labels.append(chaos_label)
	if chaos_bar_texture_label:
		labels.append(chaos_bar_texture_label)
	if labels.is_empty():
		return
	_chaos_pop_tween = create_tween()
	_chaos_pop_tween.set_parallel(true)
	for c in labels:
		c.pivot_offset = Vector2(c.size.x * 0.5, c.size.y * 0.5)
		c.scale = Vector2.ONE
		_chaos_pop_tween.tween_property(c, "scale", Vector2(CHAOS_POP_SCALE, CHAOS_POP_SCALE), CHAOS_POP_UP_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_chaos_pop_tween.chain().set_parallel(true)
	for c in labels:
		_chaos_pop_tween.tween_property(c, "scale", Vector2.ONE, CHAOS_POP_DOWN_DURATION).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_chaos_pop_tween.finished.connect(func(): 
		for c in labels:
			c.scale = Vector2.ONE
			c.pivot_offset = Vector2.ZERO
	)

func _update_chaos_bar_texture() -> void:
	if chaos_bar_texture == null:
		return
	var tex = load(CHAOS_BAR_TEXTURE) as Texture2D
	if tex != null:
		chaos_bar_texture.texture_progress = tex

## Position on the vertical chaos bar (0 = bottom, 1 = top) in global coordinates.
func _chaos_bar_fill_global_pos(t: float) -> Vector2:
	if chaos_bar_texture == null:
		return global_position
	var rect := chaos_bar_texture.get_global_rect()
	var x := rect.position.x + rect.size.x * 0.5
	var y := rect.position.y + rect.size.y * (1.0 - clampf(t, 0.0, 1.0))
	return Vector2(x, y)

## Color for spark by chaos level (green → yellow → orange/red).
func _chaos_spark_color(t: float) -> Color:
	if t < 0.33:
		return Color(0.7, 1.0, 0.7)
	if t < 0.66:
		return Color(1.0, 0.9, 0.5)
	return Color(1.0, 0.5, 0.4)

func _play_chaos_spark(_old_value: int, new_value: int) -> void:
	if chaos_fx == null or spark_burst == null:
		return
	var t := clampf(float(new_value) / 100.0, 0.0, 1.0)
	chaos_fx.global_position = _chaos_bar_fill_global_pos(t)
	spark_burst.modulate = _chaos_spark_color(t)
	spark_burst.emitting = false
	spark_burst.restart()
	spark_burst.emitting = true

func _check_chaos_thresholds(chaos_value: int) -> void:
	# Flash at key thresholds with dangerous effects
	if chaos_value >= CHAOS_COLLAPSE:
		# Maximum danger - constant pulsing red
		_flash_chaos_bar(Color(1.0, 0.0, 0.0), 0.3, true)  # Bright red, fast pulse
	elif chaos_value >= CHAOS_COLLAPSE_WARNING:
		# Very dangerous - strong pulsing
		_flash_chaos_bar(Color(1.0, 0.2, 0.0), 0.4, false)  # Orange-red, medium pulse
	elif chaos_value >= CHAOS_INTERFERENCE:
		# Dangerous - noticeable flash
		_flash_chaos_bar(Color(1.0, 0.4, 0.0), 0.5, false)  # Orange, slower pulse
	elif chaos_value >= CHAOS_INSTABILITY:
		# Warning - subtle flash
		_flash_chaos_bar(Color(1.0, 0.6, 0.0), 0.6, false)  # Yellow-orange, gentle pulse
	else:
		# Stable - no flash, just normal red
		_stop_flash()

## Win tier T2: brief gold flash on chaos bar when final score is medium win (3k–7k). Color #F5C76B
func flash_chaos_bar() -> void:
	_flash_chaos_bar(Color(0.96, 0.78, 0.42, 1.0), 0.35, false)

## After last row: chaos bar flash 0.25s ("row scoring done, big reveal starts").
func flash_chaos_bar_after_rows() -> void:
	_flash_chaos_bar(Color(0.96, 0.78, 0.42, 1.0), 0.25, false)

## Step J: When final score count-up ends — chaos bar briefly brightens, scales, glows ("Chaos gained / power applied").
func pulse_chaos_bar_on_final_score() -> void:
	_flash_chaos_bar(Color(1.0, 0.98, 0.82, 1.0), 0.38, false)
	if chaos_bar_texture != null:
		var bar: Control = chaos_bar_texture
		var prev_scale := bar.scale
		bar.pivot_offset = Vector2(bar.size.x * 0.5, bar.size.y * 0.5)
		var pulse_tween := create_tween()
		pulse_tween.tween_property(bar, "scale", Vector2(prev_scale.x * 1.06, prev_scale.y * 1.06), 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		pulse_tween.tween_property(bar, "scale", prev_scale, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		pulse_tween.tween_callback(func() -> void:
			if is_instance_valid(bar):
				bar.scale = prev_scale
				bar.pivot_offset = Vector2.ZERO
		)

func _flash_chaos_bar(flash_color: Color, duration: float, continuous: bool = false) -> void:
	# Stop any existing flash
	_stop_flash()
	
	is_flashing = true
	
	# Create flash tween
	flash_tween = create_tween()
	if continuous:
		flash_tween.set_loops()  # Infinite loops for continuous
	else:
		flash_tween.set_loops(3)  # 3 loops for one-time flash
	
	# Animated flash for main chaos_bar (stylebox colors)
	if chaos_bar != null:
		# Get the fill stylebox
		var fill_style = chaos_bar.get_theme_stylebox("fill")
		if fill_style == null:
			fill_style = StyleBoxFlat.new()
		
		# Store original color
		var original_color = (
			fill_style.bg_color if fill_style is StyleBoxFlat \
			else Color(0.8, 0.1, 0.1, 1.0)
		)
		
		# Flash animation: brighten then darken
		var update_color_func = func(color: Color):
			if fill_style is StyleBoxFlat:
				fill_style.bg_color = color
				chaos_bar.queue_redraw()
		
		flash_tween.tween_method(
			update_color_func, original_color, flash_color, duration * 0.5
		)
		flash_tween.tween_method(
			update_color_func, flash_color, original_color, duration * 0.5
		)
		
		# Also flash the border for extra danger
		if fill_style is StyleBoxFlat:
			var original_border = fill_style.border_color
			var update_border_func = func(color: Color):
				if fill_style is StyleBoxFlat:
					fill_style.border_color = color
					chaos_bar.queue_redraw()
			
			flash_tween.parallel().tween_method(
				update_border_func,
				original_border,
				Color(1.0, 1.0, 1.0, 1.0),
				duration * 0.5
			)
			flash_tween.parallel().tween_method(
				update_border_func,
				Color(1.0, 1.0, 1.0, 1.0),
				original_border,
				duration * 0.5
			)
	
	# Parallel flash for vertical texture chaos bar using modulate
	if chaos_bar_texture != null:
		var original_modulate: Color = chaos_bar_texture.modulate
		var update_tex_color = func(color: Color):
			chaos_bar_texture.modulate = color
		
		flash_tween.parallel().tween_method(
			update_tex_color,
			original_modulate,
			flash_color,
			duration * 0.5
		)
		flash_tween.parallel().tween_method(
			update_tex_color,
			flash_color,
			original_modulate,
			duration * 0.5
		)
	
	# If not continuous, stop after animation
	if not continuous:
		await flash_tween.finished
		is_flashing = false

func _stop_flash() -> void:
	if flash_tween != null:
		flash_tween.kill()
		flash_tween = null
	
	is_flashing = false
	
	# Reset to normal red color
	if chaos_bar != null:
		var fill_style = chaos_bar.get_theme_stylebox("fill")
		if fill_style is StyleBoxFlat:
			fill_style.bg_color = Color(0.8, 0.1, 0.1, 1.0)  # Dark red
			fill_style.border_color = Color(1.0, 0.3, 0.3, 1.0)  # Bright red border
			chaos_bar.queue_redraw()
	
	# Reset texture bar tint
	if chaos_bar_texture != null:
		chaos_bar_texture.modulate = Color(1, 1, 1, 1)
