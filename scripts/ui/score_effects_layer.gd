extends CanvasLayer
class_name ScoreEffectsLayer

## Row 1 score appears only after cards have finished scrolling (scroll_animation_finished).

const GRID_SCORE_OVERLAY_SCENE: PackedScene = preload("res://scenes/ui/grid_score_overlay.tscn")
## If scroll_animation_finished never fires (e.g. first-spin), create overlay after this delay (seconds)
const OVERLAY_FALLBACK_DELAY := 2.6

@onready var container: Control = $Container
var game: Node = null
var _pending_breakdown: Dictionary = {}
var _scroll_finished_before_breakdown: bool = false
var _fallback_timer: SceneTreeTimer = null

func _ready() -> void:
	_connect_game()
	if game == null:
		call_deferred("_connect_game")

func _connect_game() -> void:
	if game == null:
		game = get_node_or_null("/root/Main/Game")
	if game == null:
		game = get_tree().get_first_node_in_group("game")
	if game != null and game.has_signal("spin_breakdown"):
		if not game.spin_breakdown.is_connected(_on_spin_breakdown):
			game.spin_breakdown.connect(_on_spin_breakdown)
	if game != null and game.has_signal("initial_score_breakdown"):
		if not game.initial_score_breakdown.is_connected(_on_initial_score_breakdown):
			game.initial_score_breakdown.connect(_on_initial_score_breakdown)
	if game != null and game.has_signal("ready_for_score_overlay"):
		if not game.ready_for_score_overlay.is_connected(_on_ready_for_score_overlay):
			game.ready_for_score_overlay.connect(_on_ready_for_score_overlay)
	var board: Control = get_tree().get_first_node_in_group("board_view") as Control
	if board != null and board.has_signal("scroll_animation_finished"):
		if not board.scroll_animation_finished.is_connected(_on_cards_stopped):
			board.scroll_animation_finished.connect(_on_cards_stopped)

func _on_initial_score_breakdown(breakdown: Dictionary) -> void:
	# Show row scores on grid as soon as game starts (no scroll to wait for)
	call_deferred("_create_overlay_for_breakdown", breakdown)

func _on_spin_breakdown(breakdown: Dictionary) -> void:
	_stop_fallback_timer()
	_pending_breakdown = breakdown
	# If scroll already finished (e.g. fast evaluation), show overlay now
	if _scroll_finished_before_breakdown:
		_scroll_finished_before_breakdown = false
		call_deferred("_create_overlay_for_breakdown", _pending_breakdown)
		_pending_breakdown = {}
	else:
		# Fallback: if scroll_animation_finished never fires, show overlay after delay
		_fallback_timer = get_tree().create_timer(OVERLAY_FALLBACK_DELAY)
		_fallback_timer.timeout.connect(_on_overlay_fallback_timeout)

func _on_overlay_fallback_timeout() -> void:
	_fallback_timer = null
	if _pending_breakdown.is_empty():
		return
	_scroll_finished_before_breakdown = false
	call_deferred("_create_overlay_for_breakdown", _pending_breakdown)
	_pending_breakdown = {}

func _stop_fallback_timer() -> void:
	if _fallback_timer != null:
		_fallback_timer.timeout.disconnect(_on_overlay_fallback_timeout)
		_fallback_timer = null

func _on_cards_stopped() -> void:
	_stop_fallback_timer()
	if _pending_breakdown.is_empty():
		_scroll_finished_before_breakdown = true
		return
	_scroll_finished_before_breakdown = false
	# Joker reward (if any) runs first; overlay shows when game emits ready_for_score_overlay
	if game != null and game.has_method("reel_stopped"):
		game.reel_stopped()

func _on_ready_for_score_overlay() -> void:
	if _pending_breakdown.is_empty():
		return
	call_deferred("_create_overlay_for_breakdown", _pending_breakdown)
	_pending_breakdown = {}

func _create_overlay_for_breakdown(breakdown: Dictionary) -> void:
	var board: Control = get_tree().get_first_node_in_group("board_view") as Control
	if board == null or container == null or GRID_SCORE_OVERLAY_SCENE == null:
		return
	var rect: Rect2 = board.get_global_rect()
	# If board not laid out yet (e.g. initial load), wait one more frame
	if rect.size.x < 50 or rect.size.y < 50:
		call_deferred("_create_overlay_for_breakdown", breakdown)
		return
	# Convert board rect to container-local so overlay aligns with grid center
	var container_global: Vector2 = container.get_global_rect().position
	var overlay: Control = GRID_SCORE_OVERLAY_SCENE.instantiate() as Control
	container.add_child(overlay)
	overlay.visible = true
	overlay.z_index = 200
	overlay.position = rect.position - container_global
	overlay.size = rect.size
	overlay.layout_mode = 0  # Keep explicit size so grid center = second row center
	# Use overlay's actual global position for row Y (in case layout shifts it)
	var overlay_global: Vector2 = overlay.get_global_rect().position
	var row_center_ys: Array = []
	if board.has_method("get_row_center_global_y_positions"):
		var global_ys: Array = board.get_row_center_global_y_positions()
		for i in range(global_ys.size()):
			row_center_ys.append(global_ys[i] - overlay_global.y)
	if overlay.has_method("setup_from_breakdown"):
		overlay.setup_from_breakdown(breakdown, rect, container.size, overlay.position, row_center_ys)
	if overlay.has_signal("total_score_displayed") and game != null:
		overlay.total_score_displayed.connect(func(b: Dictionary) -> void: game.emit_signal("total_score_displayed", b))
	if overlay.has_signal("final_score_displayed"):
		var main_ui_node = get_tree().get_first_node_in_group("main_ui")
		if main_ui_node != null and main_ui_node.has_method("trigger_win_tier_effects"):
			overlay.final_score_displayed.connect(main_ui_node.trigger_win_tier_effects)
	if overlay.has_signal("multiplier_step_about_to_show"):
		var effect_panel = get_tree().get_first_node_in_group("active_effect_panel")
		if effect_panel != null and effect_panel.has_method("show_multiplier_step"):
			overlay.multiplier_step_about_to_show.connect(effect_panel.show_multiplier_step)
	if overlay.has_signal("chaos_show_now") and game != null and game.has_method("notify_chaos_show_now"):
		overlay.chaos_show_now.connect(game.notify_chaos_show_now)
	if overlay.has_signal("first_row_about_to_show") and game != null:
		if game.has_method("notify_first_row_about_to_show"):
			overlay.first_row_about_to_show.connect(game.notify_first_row_about_to_show)
	if overlay.has_signal("row_score_about_to_show"):
		var board_view_node = get_tree().get_first_node_in_group("board_view")
		if board_view_node != null and board_view_node.has_method("flash_winning_cards_for_row"):
			overlay.row_score_about_to_show.connect(board_view_node.flash_winning_cards_for_row)
	if overlay.has_signal("base_score_about_to_show"):
		var board_view_clear = get_tree().get_first_node_in_group("board_view")
		if board_view_clear != null and board_view_clear.has_method("_clear_scoring_highlights"):
			overlay.base_score_about_to_show.connect(board_view_clear._clear_scoring_highlights)
	if overlay.has_signal("row_scoring_done"):
		var main_ui_rd = get_tree().get_first_node_in_group("main_ui")
		if main_ui_rd != null and main_ui_rd.has_method("request_row_scoring_done_overlay"):
			overlay.row_scoring_done.connect(main_ui_rd.request_row_scoring_done_overlay)
		var effect_panel_rd = get_tree().get_first_node_in_group("active_effect_panel")
		if effect_panel_rd != null and effect_panel_rd.has_method("flash_chaos_bar_after_rows"):
			overlay.row_scoring_done.connect(effect_panel_rd.flash_chaos_bar_after_rows)
	if overlay.has_signal("chaos_bar_update_requested"):
		var effect_panel_bar = get_tree().get_first_node_in_group("active_effect_panel")
		if effect_panel_bar != null and effect_panel_bar.has_method("run_chaos_bar_update_for_score_phase"):
			overlay.chaos_bar_update_requested.connect(
				effect_panel_bar.run_chaos_bar_update_for_score_phase
			)
			if effect_panel_bar.has_signal("chaos_bar_update_finished"):
				if overlay.has_method("continue_after_chaos_bar"):
					effect_panel_bar.chaos_bar_update_finished.connect(
						overlay.continue_after_chaos_bar
					)
	# Dark bg: show when overlay requests it (in continue_after_chaos_bar, before base score); remove on overlay_finished below
	if overlay.has_signal("background_darken_requested"):
		var main_ui_node = get_tree().get_first_node_in_group("main_ui")
		if main_ui_node != null and main_ui_node.has_method("request_background_darken_for_score"):
			overlay.background_darken_requested.connect(main_ui_node.request_background_darken_for_score)
	if overlay.has_signal("joker_and_chaos_mult_animation_requested"):
		var effect_panel = get_tree().get_first_node_in_group("active_effect_panel")
		if effect_panel != null and effect_panel.has_method("play_joker_bonus_and_chaos_multiplier_animation"):
			overlay.joker_and_chaos_mult_animation_requested.connect(effect_panel.play_joker_bonus_and_chaos_multiplier_animation)
	# Dark bg: show = background_darken_requested (before base score). Remove = when overlay is gone (overlay_finished).
	if overlay.has_signal("overlay_finished") and game != null:
		var main_ui_node = get_tree().get_first_node_in_group("main_ui")
		overlay.overlay_finished.connect(func(_b: Dictionary) -> void:
			var sm = get_node_or_null("/root/SfxManager")
			if sm:
				sm.play_final_resolve()
			game.notify_total_score_hidden(_b)
			# Remove dark bg after final score has disappeared (overlay faded and freed)
			if main_ui_node != null and main_ui_node.has_method("brighten_after_total_score"):
				main_ui_node.brighten_after_total_score()
		)
	if game != null and game.has_signal("retrigger_breakdown") and overlay.has_method("receive_retrigger_breakdown"):
		game.retrigger_breakdown.connect(overlay.receive_retrigger_breakdown)
