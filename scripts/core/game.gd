extends Node
class_name Game

## Main game controller that coordinates all systems

enum GameState {
	RUNNING,  # Normal gameplay state
	REWARD_CUTSCENE,  # Joker earned: pause input, play reward animation, then continue
	ENDED  # Run has ended, only restart button works
}

signal hand_evaluated(result: Dictionary)
signal spins_exhausted(message: String)
signal run_ended(message: String)
signal jokers_changed()
signal spin_started()  # Emitted when spin button is pressed (before chaos updates); UI delays bar update until total_score_hidden
signal spin_breakdown(breakdown: Dictionary)  # Emits detailed breakdown after each spin
signal retriggered_rows(row_indices: Array)  # Retrigger applied; UI pulses cards in those rows (0-based)
signal retrigger_breakdown(breakdown: Dictionary)  # After first total shown; overlay does second count-up then chaos
signal initial_score_breakdown(breakdown: Dictionary)  # Emitted at game start for initial grid row scores overlay
signal total_score_displayed(breakdown: Dictionary)  # When grid overlay has shown total
signal total_score_hidden(breakdown: Dictionary)  # When grid overlay has faded
signal chaos_show_now(breakdown: Dictionary)  # After final total (+ retrigger) shown; chaos text + sound run here
signal first_row_about_to_show()  # Just before first row score appears; board can run card flicker
signal score_sequence_finished()  # Score overlay + chaos change done; spin button can re-enable
signal game_state_changed(new_state: GameState)  # Emitted when game state changes
signal joker_reward_cutscene(slot_index: int, joker_id: int)  # UI plays reward animation; then call notify_joker_reward_animation_finished
signal ready_for_score_overlay()  # Emitted when reel stopped and any joker reward is done; score overlay can show row scores

var board
var run_state
var spin_resolver
var combo_eval
var texture_resolver: Node
var owned_jokers: Array = []  # Jokers the player owns (up to 5)
var active_jokers: Array = []  # Jokers that are active this spin (capped at 2-3)
var locked_count_this_spin: int = 0
var previous_spin_score: int = 0  # Track previous spin score for trigger conditions
var previous_hand_type: int = -1  # Track previous hand type for stabilization
var same_combo_count: int = 0  # Track consecutive same combos
# Track how many spins each locked card has survived
var locked_card_survival_spins: Dictionary = {}
var spin_count: int = 0  # Track total spins in the run
var cards_locked_before_spin: bool = false  # Track if any cards were locked before spin
var is_run_ended: bool = false  # Track if the run has ended (blocks all input except restart) - DEPRECATED: use game_state instead
var game_state: GameState = GameState.RUNNING  # Current game state

# Joker 2 (Ritual Blade) tracking
var joker2_spins_active: int = 0  # Track how many spins Joker 2 has been active

# Slots that were part of the previous spin's winning rows; user cannot lock these
var _slots_in_previous_win: Array = []

# Lock charge breakdown for Spin Breakdown panel
var _locks_before_spin: int = 0
var _locks_after_spend: int = 0
var _lock_spent_this_spin: bool = false
var _lock_restored_this_spin: bool = false
var _locks_after_restore: int = 0

const MAX_OWNED_JOKERS := 5
const MAX_ACTIVE_JOKERS := 5  # Cap on active jokers per spin (allows all jokers on grid)
const SCORE_MULTIPLIER := 100  # Display: 10 → 1000, 20 → 2000

# Chaos threshold levels (state-based pressure)
const CHAOS_STABLE := 30  # < 30: Stable (no disruption)
const CHAOS_INSTABILITY := 30  # ≥ 30: Instability (minor disruption)
const CHAOS_INTERFERENCE := 60  # ≥ 60: Interference (real pressure)
const CHAOS_COLLAPSE_WARNING := 90  # ≥ 90: Collapse Warning (final tension)
const CHAOS_COLLAPSE := 100  # = 100: Collapse (Game Over)

# Retrigger A: Chaos > 20 and chaos gained this spin > 3 → retrigger one random winning row
const RETRIGGER_CHAOS_MIN := 20
const RETRIGGER_GAIN_MIN := 3
# Retrigger B: Chaos > 70 → retrigger randomly 1 or 2 winning rows (distinct, no duplicate)
const RETRIGGER_B_CHAOS_MIN := 40

# Chaos effects tracking
var next_spin_score_multiplier: float = 1.0  # Applied to next spin's score
var disabled_jokers_for_next_spin: Array = []  # Jokers disabled by chaos effects
var chaos_locked_slots_for_next_spin: Array[int] = []  # Slots locked by chaos effects

# Final Joke tracking
# True when player is on the final spin granted by The Final Joke
var is_final_joke_spin: bool = false
## Set when we grant the final spin (chaos hit 100); clear when user starts that spin. Prevents ending run in the same evaluation that granted the spin.
var _final_spin_just_granted: bool = false
## True when joker was placed via spin_resolver (spins 3, 6, 9) so _check_joker_appearances_from_spins skips spawn.
var _joker_placed_via_resolver_this_spin: bool = false
## Hand result stored so we apply retrigger after first total is shown (spin flow: row scores → total → retrigger → total+retrigger → chaos).
var _last_hand_result_for_retrigger: Dictionary = {}
## When set, run_ended is emitted after score_sequence_finished (so restart button appears after all score effects).
var _pending_run_ended_message: String = ""
## Jokers to collect this spin; each is { "slot_index": int, "joker_id": int }. Reward cutscene runs for each, then spin continues.
var _pending_joker_rewards: Array = []

func _ready() -> void:
	# Add to group for easy access
	add_to_group("game")
	
	# Initialize core systems (using global class names)
	# Note: These classes are globally available via class_name declarations
	var board_class = load("res://scripts/core/board.gd")
	var run_state_class = load("res://scripts/core/run_state.gd")
	var spin_resolver_class = load("res://scripts/core/spin_resolver.gd")
	var combo_eval_class = load("res://scripts/core/combo_eval.gd")
	
	board = board_class.new()
	add_child(board)
	
	run_state = run_state_class.new()
	add_child(run_state)
	
	spin_resolver = spin_resolver_class.new()
	spin_resolver.board = board
	add_child(spin_resolver)
	
	combo_eval = combo_eval_class.new()
	add_child(combo_eval)
	
	texture_resolver = CardTextureResolver.new()
	add_child(texture_resolver)
	
	# Connect signals
	board.card_changed.connect(_on_card_changed)
	spin_resolver.spin_complete.connect(_on_spin_complete)
	run_state.chaos_max_reached.connect(_on_chaos_max_reached)
	total_score_displayed.connect(_on_first_total_displayed)
	if not score_sequence_finished.is_connected(_on_score_sequence_finished):
		score_sequence_finished.connect(_on_score_sequence_finished)
	
	# Deal initial hand after a frame to ensure UI is ready
	call_deferred("_deferred_init")

func _deferred_init() -> void:
	# Deal initial hand but don't evaluate it yet
	# Values should remain at zero until first spin button click
	spin_resolver.deal_initial()
	# Don't evaluate the initial hand - wait for first spin

## Set game state and emit signal
func set_game_state(new_state: GameState) -> void:
	if game_state != new_state:
		game_state = new_state
		game_state_changed.emit(new_state)
		
		# Keep is_run_ended in sync for backward compatibility
		is_run_ended = (new_state == GameState.ENDED)

func restart_run() -> void:
	# Reset run ended flag to allow input again
	is_run_ended = false
	_pending_run_ended_message = ""
	_final_spin_just_granted = false

	# Set state back to RUNNING
	set_game_state(GameState.RUNNING)
	
	# Reset run state first (score, chaos, spins, locks) so UI and logic see fresh values
	run_state.reset_run()
	
	# Clear owned and active jokers
	owned_jokers.clear()
	active_jokers.clear()
	previous_spin_score = 0
	previous_hand_type = -1
	same_combo_count = 0
	locked_card_survival_spins.clear()
	spin_count = 0
	cards_locked_before_spin = false
	joker2_spins_active = 0  # Reset Joker 2 stacking multiplier
	_locks_before_spin = 0
	_locks_after_spend = 0
	_lock_spent_this_spin = false
	_lock_restored_this_spin = false
	_locks_after_restore = 0
	is_initial_deal = true  # Reset initial deal flag
	is_final_joke_spin = false  # Reset final joke spin flag
	jokers_changed.emit()
	
	# Clear board and all locks
	board.clear_board()
	
	# Deal new initial hand (but don't evaluate it)
	spin_resolver.deal_initial()
	
	# Clear any highlights
	var board_view = get_tree().get_first_node_in_group("board_view")
	if board_view and board_view.has_method("clear_scoring_highlights"):
		board_view.clear_scoring_highlights()
	
	# Force UI to sync score/chaos/spins/locks (in case signals were missed after unpause)
	call_deferred("_refresh_ui_after_restart")

func _refresh_ui_after_restart() -> void:
	if run_state != null:
		run_state.notify_listeners()
	var init_chaos: int = run_state.chaos if run_state != null else RunState.INITIAL_CHAOS
	# Force board to reset card alignment so all cards are correctly aligned after new run
	var board_view = get_tree().get_first_node_in_group("board_view")
	if board_view != null and board_view.has_method("sync_chaos_and_reset_alignment"):
		board_view.sync_chaos_and_reset_alignment(init_chaos)
	# Reset chaos bar and right panel: emit a "reset" breakdown so ScoreBreakdownBlock, MathExpressionLabel, etc. show init values
	var reset_breakdown: Dictionary = {
		"score": {
			"base_score": 0,
			"multipliers": [],
			"row_hands": [{"row_index": 0, "score": 0}, {"row_index": 1, "score": 0}, {"row_index": 2, "score": 0}]
		},
		"chaos": {
			"chaos_before": init_chaos,
			"chaos_after": init_chaos,
			"net_change": 0
		},
		"active_jokers": [],
		"locks": {
			"before": run_state.lock_charges if run_state != null else 10,
			"after": run_state.lock_charges if run_state != null else 10
		}
	}
	spin_breakdown.emit(reset_breakdown)
	# Reset Current Bonus card to "No Hand" and 0,0,0
	hand_evaluated.emit({
		"name": "No Hand",
		"row_hands": [{"row_index": 0, "score": 0}, {"row_index": 1, "score": 0}, {"row_index": 2, "score": 0}]
	})
	# Reset breakdown panel to show fresh run state (score 0, chaos 10, etc.)
	var breakdown_panel = get_tree().get_first_node_in_group("spin_breakdown_panel")
	if breakdown_panel != null and breakdown_panel.has_method("_set_initial_breakdown_text"):
		breakdown_panel.call_deferred("_set_initial_breakdown_text")

func _on_card_changed(_slot_index: int, _item: BoardItem) -> void:
	# Jokers are now activated based on what's on the grid each spin
	# No need to add to owned_jokers - they activate only when on the grid
	pass

var is_initial_deal: bool = true  # Track if this is the first initial deal

func _on_spin_complete() -> void:
	# Skip evaluation on initial deal - values should stay at zero
	if is_initial_deal:
		is_initial_deal = false
		# Clear all locks after initial deal
		_clear_all_locks()
		return  # Don't evaluate or change any values on initial deal
	
	# Check for joker appearances from spin count (before evaluation)
	_check_joker_appearances_from_spins()
	
	# Determine which jokers should activate this spin (before evaluation)
	# This uses previous spin's state for conditions
	_activate_jokers_for_spin()
	
	# After spin, evaluate the hand (with active jokers affecting score)
	var hand_result = evaluate_hand()
	
	# Check for stabilization moments (chaos reduction opportunities)
	_check_stabilization_moments(hand_result)
	
	# Update chaos based on spin results
	_update_chaos_after_spin(hand_result)

	# Retrigger is applied AFTER first total is shown (see _on_first_total_displayed)
	_last_hand_result_for_retrigger = hand_result

	# Check for The Final Joke at Chaos ≥ 90 (after chaos is updated)
	_check_final_joke_appearance()
	
	# Restore lock charge if player scored a valid combo
	_restore_lock_charge_on_combo(hand_result)
	
	# Build and emit breakdown information
	_emit_spin_breakdown(hand_result)

	# Remember which slots were in scoring rows (user cannot lock these until next spin)
	_update_slots_in_previous_win(hand_result)

	# Update tracking variables for next spin
	previous_spin_score = run_state.chips
	previous_hand_type = hand_result.get("type", -1)
	
	# Update locked card survival tracking
	_update_locked_card_survival()
	
	# Locks are cleared when scroll animation finishes (so lock icons stay visible until cards stop)

	# Reset lock tracking for next spin
	cards_locked_before_spin = false
	_joker_placed_via_resolver_this_spin = false
	
	# Check if this was the final joke spin - if so, end the game (only after the granted spin runs, not the spin that granted it)
	# Only end if Joker 4 was actually active (chaos >= 100)
	# All effects have been applied by this point (hand evaluated, breakdown emitted, etc.)
	if is_final_joke_spin and not _final_spin_just_granted:
		# Verify Joker 4 was active (should be true if chaos >= 100)
		var joker4_was_active = false
		for joker in active_jokers:
			var joker_id = _get_joker_id_from_instance(joker)
			if joker_id == 4:  # The Final Joke
				joker4_was_active = true
				break
		
		# Only end game if Joker 4 was actually active and applied its effect (this was the actual final spin)
		if joker4_was_active:
			is_final_joke_spin = false
			# Defer run_ended and ENDED until score overlay + chaos done (no pause, no restart yet)
			_pending_run_ended_message = "Final Spin Complete! Final Score: %d chips" % run_state.total_chips
			return
		else:
			# Joker 4 wasn't active - reset flag and continue
			is_final_joke_spin = false
	
	# Check if run should end (no spins remaining)
	if run_state.spins_remaining <= 0:
		# Defer run_ended and ENDED until score overlay + chaos done (no pause, no restart yet)
		_pending_run_ended_message = "Run Ended! Final Score: %d chips" % run_state.total_chips

func _on_chaos_max_reached() -> void:
	# Chaos has reached 100 - check if The Final Joke (Joker 4) can prevent game end
	# Check if The Final Joke (Joker 4) is on the grid or owned
	var has_final_joke := false
	
	# Check if owned
	for owned_joker in owned_jokers:
		var owned_id = _get_joker_id_from_instance(owned_joker)
		if owned_id == 4:  # The Final Joke
			has_final_joke = true
			break
	
	# Check if on grid
	if not has_final_joke:
		for i in range(board.TOTAL_SLOTS):
			var item = board.get_card(i)
			if item != null and item.is_joker:
				var joker_card = item as JokerCard
				if joker_card != null and joker_card.joker_id == 4:
					has_final_joke = true
					break
	
	if has_final_joke:
		# The Final Joke prevents game end and grants one final spin with ×2 score
		# Joker 4 will activate on the next spin (chaos >= 100) and apply ×2 multiplier
		is_final_joke_spin = true
		_final_spin_just_granted = true  # So we don't end run in this same hand evaluation
		# Grant one more spin
		run_state.spins_remaining += 1
		run_state.spins_changed.emit(run_state.spins_remaining, run_state.SPINS_PER_LEVEL)
		# Show notification that Joker 4 effect is active
		var notification_text = (
			"Chaos reached 100! The Final Joke is active!\n"
			+ "Final spin with ×2 score! You have only one final spin now.\n"
		)
		spins_exhausted.emit(notification_text)
		# Don't end game here - wait until after final spin completes
	else:
		# No Final Joke - but don't end game immediately when chaos reaches 100
		# Game will end naturally when spins run out or after final spin if Joker 4 was active
		# Just grant one more spin to allow player to see the situation
		run_state.spins_remaining += 1
		run_state.spins_changed.emit(run_state.spins_remaining, run_state.SPINS_PER_LEVEL)

func _update_chaos_after_spin(hand_result: Dictionary) -> void:
	# NEW CHAOS SYSTEM: Simplified increases
	# Normal spin: +5 chaos
	# Failed spin (no poker hand in any row): +10 chaos total
	# At ≥90: +1 extra chaos per spin
	
	var chaos_gain := 0
	var base_score = hand_result.get("base_score", 0)
	var is_failed_spin = (base_score == 0)  # No poker hand in any row
	
	# Track chaos breakdown for UI
	var chaos_breakdown := {
		"base_spin": 0,
		"failed_penalty": 0,
		"collapse_warning_extra": 0,
		"total_gain": 0,
		"reductions": [],
		"total_reduction": 0,
		"net_change": 0,
		"chaos_before": run_state.chaos
	}
	
	# Base spin increase: +5 chaos
	chaos_gain += 5
	chaos_breakdown["base_spin"] = 5
	
	# Failed spin penalty: +5 additional (total +10)
	if is_failed_spin:
		chaos_gain += 5
		chaos_breakdown["failed_penalty"] = 5
	
	# Collapse Warning (≥90): +1 extra chaos per spin
	if run_state.chaos >= CHAOS_COLLAPSE_WARNING:
		chaos_gain += 1
		chaos_breakdown["collapse_warning_extra"] = 1
	
	# Joker 2 (Ritual Blade): +2 chaos per spin when active
	var joker2_chaos_gain = 0
	for joker in active_jokers:
		var joker_id = _get_joker_id_from_instance(joker)
		if joker_id == 2:  # Ritual Blade
			joker2_chaos_gain = 2
			chaos_gain += 2
			break
	
	chaos_breakdown["joker2_chaos"] = joker2_chaos_gain
	
	chaos_breakdown["total_gain"] = chaos_gain
	
	# Chaos tier multiplier (0–25 → x1, 25–50 → x1.2, 50–75 → x1.5, 75–100 → x2); stacks with joker extra
	var tier_mult: float = run_state.get_chaos_tier_multiplier()
	var joker_mult: float = 1.0
	var mult_context: Dictionary = {
		"chaos_before": run_state.chaos,
		"active_jokers": active_jokers,
		"hand_result": hand_result
	}
	for joker in active_jokers:
		if joker != null and joker.has_method("get_chaos_gain_multiplier"):
			joker_mult *= joker.get_chaos_gain_multiplier(mult_context)
	var combined_mult: float = tier_mult * joker_mult
	var final_gain: int = int(round(chaos_gain * combined_mult))
	final_gain = maxi(0, final_gain)
	
	chaos_breakdown["chaos_tier_mult"] = tier_mult
	chaos_breakdown["chaos_joker_mult"] = joker_mult
	chaos_breakdown["chaos_multiplier"] = combined_mult
	
	# Apply chaos gains (multiplied)
	run_state.add_chaos(final_gain)
	
	# No joker chaos reductions in new system
	chaos_breakdown["reductions"] = []
	chaos_breakdown["total_reduction"] = 0
	chaos_breakdown["net_change"] = final_gain
	chaos_breakdown["chaos_after"] = run_state.chaos
	
	# Store chaos breakdown in hand_result for later use
	hand_result.chaos_breakdown = chaos_breakdown

func _apply_retrigger_if_condition(hand_result: Dictionary) -> bool:
	var chaos_breakdown = hand_result.get("chaos_breakdown", {})
	if chaos_breakdown == null:
		return false
	var chaos_after: int = int(chaos_breakdown.get("chaos_after", 0))
	var net_change: int = int(chaos_breakdown.get("net_change", 0))

	var score_breakdown = hand_result.get("score_breakdown", {})
	if score_breakdown == null:
		return false
	var row_hands: Array = score_breakdown.get("row_hands", [])
	if row_hands.is_empty():
		return false

	# Collect winning row indices (score > 0; scores in breakdown are display units)
	var winning_indices: Array[int] = []
	for i in range(row_hands.size()):
		var row_data = row_hands[i]
		if row_data is Dictionary and int(row_data.get("score", 0)) > 0:
			winning_indices.append(i)
	if winning_indices.is_empty():
		return false

	var base_score: int = int(hand_result.get("base_score", 0))
	if base_score <= 0:
		return false
	var chips_earned: int = int(hand_result.get("score", 0))
	var total_retrigger_added: int = 0  # Display scale: for overlay (base + this = pre-mult sum); then × joker × chaos
	var available: Array[int] = winning_indices.duplicate()
	var retriggered_row_indices: Array = []  # For visual feedback: pulse these rows' cards

	# Retrigger adds the row's display score; final = (base + retrigger) × joker mults × current chaos mult
	var final_joke_display_mult: float = 2.0 if hand_result.get("is_final_joke_spin", false) else 1.0

	# Condition A: Chaos > 20 and gain > 3 → retrigger exactly 1
	if chaos_after > RETRIGGER_CHAOS_MIN and net_change > RETRIGGER_GAIN_MIN and not available.is_empty():
		var idx: int = available[randi() % available.size()]
		available.erase(idx)
		retriggered_row_indices.append(idx)
		var row_data: Dictionary = row_hands[idx]
		var row_display: int = int(row_data.get("score", 0))
		var extra: int = int(round(float(row_display) / final_joke_display_mult))
		total_retrigger_added += extra

	# Condition B: Chaos > 70 → retrigger randomly 1 or 2 winning rows (distinct)
	if chaos_after > RETRIGGER_B_CHAOS_MIN and not available.is_empty():
		var num_retriggers: int = randi() % 2 + 1  # 1 or 2
		for _k in range(num_retriggers):
			if available.is_empty():
				break
			var idx: int = available[randi() % available.size()]
			available.erase(idx)
			retriggered_row_indices.append(idx)
			var row_data: Dictionary = row_hands[idx]
			var row_display: int = int(row_data.get("score", 0))
			var extra: int = int(round(float(row_display) / final_joke_display_mult))
			total_retrigger_added += extra

	# Apply (base + retrigger) × joker mults × chaos mult (use chaos at spin start to match score)
	if total_retrigger_added > 0:
		var chaos_before: int = int(chaos_breakdown.get("chaos_before", chaos_after))
		var combined_mult: float = 1.0
		for mult_entry in score_breakdown.get("multipliers", []):
			combined_mult *= float(mult_entry.get("multiplier", 1.0))
		combined_mult *= (1.0 + float(chaos_before) / 100.0)
		var delta: int = int(round(float(total_retrigger_added) * combined_mult))
		var total_score: int = chips_earned + delta
		hand_result["score"] = total_score
		score_breakdown["final_score"] = total_score
		run_state.add_chips(delta)
		run_state.add_xp(int(delta / float(SCORE_MULTIPLIER)))
		score_breakdown["flat_bonuses"].append({
			"joker": "Retrigger",
			"joker_id": -1,
			"amount": int(round(float(delta) / float(SCORE_MULTIPLIER)))
		})
		score_breakdown["retrigger_added"] = total_retrigger_added
	if not retriggered_row_indices.is_empty():
		retriggered_rows.emit(retriggered_row_indices)
	return not retriggered_row_indices.is_empty()

func _on_first_total_displayed(_breakdown: Dictionary) -> void:
	if _last_hand_result_for_retrigger.is_empty():
		return
	var applied: bool = _apply_retrigger_if_condition(_last_hand_result_for_retrigger)
	if applied:
		var breakdown_dict: Dictionary = _build_breakdown_dict(_last_hand_result_for_retrigger)
		if not breakdown_dict.is_empty():
			retrigger_breakdown.emit(breakdown_dict)
			# Do not emit spin_breakdown here — it would create a second overlay. Right panel updates from total_score_hidden when overlay finishes.
	_last_hand_result_for_retrigger = {}  # Clear so next spin gets fresh state

func _on_score_sequence_finished() -> void:
	# Show restart / run ended notification only after all score effects (row scores, total, retrigger, chaos) are done
	if _pending_run_ended_message != "":
		var msg: String = _pending_run_ended_message
		_pending_run_ended_message = ""
		is_run_ended = true
		set_game_state(GameState.ENDED)
		run_ended.emit(msg)

func notify_total_score_hidden(breakdown: Dictionary) -> void:
	emit_signal("total_score_hidden", breakdown)

func notify_chaos_show_now(breakdown: Dictionary) -> void:
	emit_signal("chaos_show_now", breakdown)

func notify_first_row_about_to_show() -> void:
	emit_signal("first_row_about_to_show")

func _check_chaos_threshold_effects() -> void:
	# Check current chaos level and apply threshold-based effects
	# This creates clear phases of tension as chaos increases
	# Note: Current chaos level is available via run_state.chaos when needed
	
	# 🟢 Chaos < 30 — Stable: No disruption, board behaves normally
	# 🟡 Chaos ≥ 30 — Instability: Minor disruption, certain jokers unlock
	# 🟠 Chaos ≥ 60 — Interference: Real pressure, reduced multiplier caps
	# 🔴 Chaos ≥ 90 — Collapse Warning: Final tension, urgency cues
	# ☠️ Chaos = 100 — Collapse: Game Over (handled by chaos_max_reached signal)
	
	# Future: Implement visual/mechanical effects at each threshold
	# For now, thresholds are used for joker trigger conditions
	# Visual effects (glitches, UI stress cues) can be added later
	pass

func _check_joker_chaos_reduction(hand_result: Dictionary, current_score: int) -> Dictionary:
	# Some jokers can directly reduce chaos level when they trigger
	# This happens after chaos is calculated and applied
	var total_reduction := 0
	var reductions_list := []
	
	for joker in active_jokers:
		if joker.has_method("get_chaos_reduction"):
			var reduction_context := {
				"score": current_score,
				"final_score": current_score,
				"board": board,
				"chaos": run_state.chaos,  # Current chaos level after increase
				"hand_type": hand_result.get("type", -1) if hand_result else -1,
				"spin_count": spin_count,
				"locked_count": board.get_locked_count()
			}
			var reduction = joker.get_chaos_reduction(reduction_context)
			if reduction > 0:
				total_reduction += reduction
				var joker_id = _get_joker_id_from_instance(joker)
				var joker_name = joker.get("name") if joker.get("name") else "Unknown"
				reductions_list.append({
					"joker": joker_name,
					"joker_id": joker_id,
					"reduction": reduction
				})
	
	# Apply direct chaos reduction (reduces current chaos level)
	if total_reduction > 0:
		var _chaos_before = run_state.chaos
		run_state.reduce_chaos(total_reduction)
		var _msg = "Jokers reduced chaos by %d (Before: %d, After: %d)"
	
	return {"reductions": reductions_list, "total_reduction": total_reduction}

func _check_stabilization_moments(hand_result: Dictionary) -> void:
	# Check for perfect stabilization moments that reduce chaos
	var current_hand_type = hand_result.get("type", -1)
	var chaos_reduction := 0
	
	# 1. Same combo repeats 3 times → -1 Chaos
	if current_hand_type == previous_hand_type and current_hand_type != -1:
		same_combo_count += 1
		if same_combo_count >= 3:
			chaos_reduction += 1
			same_combo_count = 0  # Reset counter
	else:
		same_combo_count = 0  # Reset if combo changed
	
	# 2. Locked card survives 5 spins → -2 Chaos
	for slot_index in locked_card_survival_spins.keys():
		var survival_count = locked_card_survival_spins[slot_index]
		if survival_count >= 5:
			chaos_reduction += 2
			locked_card_survival_spins.erase(slot_index)  # Remove after reward
	
	# Apply chaos reduction (rare, controlled)
	if chaos_reduction > 0:
		run_state.reduce_chaos(chaos_reduction)

func _update_locked_card_survival() -> void:
	# Track how many spins each locked card has survived
	var new_survival: Dictionary = {}
	
	for i in range(board.TOTAL_SLOTS):
		if board.is_locked(i):
			# Card is locked - increment survival count
			var current_count = locked_card_survival_spins.get(i, 0)
			new_survival[i] = current_count + 1
		else:
			# Card is not locked - remove from tracking if it was there
			if locked_card_survival_spins.has(i):
				locked_card_survival_spins.erase(i)
	
	locked_card_survival_spins = new_survival

func evaluate_hand(apply_rewards: bool = true) -> Dictionary:
	# Evaluate poker hands per ROW (left → right), 4 hands total
	# Columns are NOT evaluated for poker.
	var row_results: Array = []
	var total_base_score := 0
	var all_matching_cards: Array[Card] = []
	var best_hand_type: int = -1
	var best_hand_name: String = "None"
	
	for row in range(board.GRID_HEIGHT):
		var row_cards: Array[Card] = board.get_row_cards(row)
		if row_cards.size() == 0:
			continue
		
		var row_result: Dictionary = combo_eval.evaluate_hand(row_cards)
		row_result["row_index"] = row
		row_results.append(row_result)
		
		var row_score: int = row_result.get("score", 0)
		total_base_score += row_score
		
		# Collect matching cards for highlighting (only if this row scores > 0)
		if row_score > 0:
			var matching: Array = row_result.get("matching_cards", [])
			for c in matching:
				if c != null:
					all_matching_cards.append(c)
		
		# Track best hand type for stabilisation logic
		var row_type: int = row_result.get("type", -1)
		if row_type > best_hand_type:
			best_hand_type = row_type
			best_hand_name = row_result.get("name", "None")
	
	# Build aggregate result for this spin
	var result: Dictionary = {
		"type": best_hand_type,
		"name": best_hand_name,
		"score": total_base_score,
		"matching_cards": all_matching_cards,
		"row_hands": row_results,
		"is_final_joke_spin": is_final_joke_spin
	}
	
	# Store base score before joker modifications
	var base_score := total_base_score
	result.base_score = base_score
	
	# Track score breakdown for UI
	var score_breakdown := {
		"base_score": base_score,
		"hand_name": best_hand_name,
		"flat_bonuses": [],
		"multipliers": [],
		"chaos_penalty": 0.0,
		"final_score": 0,
		"row_hands": row_results
	}
	# Use chaos at spin start for score (so first spin uses 1.1 when chaos=10; overlay shows chaos_before)
	# Apply joker score modifications first (adds bonuses)
	var score_after_bonuses := base_score
	for joker in active_jokers:
		var before := score_after_bonuses
		score_after_bonuses = joker.modify_score(score_after_bonuses, best_hand_type, board)
		var bonus := score_after_bonuses - before
		if bonus > 0:
			var joker_id = _get_joker_id_from_instance(joker)
			var joker_name = joker.get("name") if joker.get("name") else "Unknown"
			score_breakdown["flat_bonuses"].append({
				"joker": joker_name,
				"joker_id": joker_id,
				"amount": bonus
			})
	
	# Then apply joker chip multipliers
	var chips_earned := score_after_bonuses
	
	# Check for Entropy Engine (Joker 1) - applies multiplier based on chaos at spin start
	for joker in active_jokers:
		var joker_id = _get_joker_id_from_instance(joker)
		if joker_id == 1:  # Entropy Engine
			var entropy_multiplier: float = round((1.0 + float(run_state.chaos) / 100.0) * 10.0) / 10.0
			chips_earned = int(float(chips_earned) * entropy_multiplier)
			var mult = entropy_multiplier
			var joker_name = joker.get("name") if joker.get("name") else "Entropy Engine"
			score_breakdown["multipliers"].append({
				"joker": joker_name,
				"joker_id": 1,
				"multiplier": mult
			})
			break  # Only one Entropy Engine
	
	# Check for Joker 2 (Ritual Blade) - stacking multiplier +0.2× per spin
	for joker in active_jokers:
		var joker_id = _get_joker_id_from_instance(joker)
		if joker_id == 2:  # Ritual Blade
			# Increment spin count for Joker 2
			joker2_spins_active += 1
			# Calculate stacking multiplier: 1.0 + (spins_active * 0.2)
			var ritual_multiplier: float = 1.0 + (float(joker2_spins_active) * 0.2)
			chips_earned = int(float(chips_earned) * ritual_multiplier)
			var joker_name = joker.get("name") if joker.get("name") else "Ritual Blade"
			score_breakdown["multipliers"].append({
				"joker": joker_name,
				"joker_id": 2,
				"multiplier": ritual_multiplier
			})
			break
	
	# Check for The Final Joke (Joker 4) - applies ×2 score when active (chaos >= 100)
	# Check if Joker 4 is in active jokers (will be active when chaos >= 100)
	for joker in active_jokers:
		var joker_id = _get_joker_id_from_instance(joker)
		if joker_id == 4:  # The Final Joke
			chips_earned = chips_earned * 2
			var joker_name = joker.get("name") if joker.get("name") else "The Final Joke"
			score_breakdown["multipliers"].append({
				"joker": joker_name,
				"joker_id": 4,
				"multiplier": 2.0
			})
			break
	
	# Apply other joker chip multipliers (if any)
	for joker in active_jokers:
		var joker_id = _get_joker_id_from_instance(joker)
		if joker_id == 1 or joker_id == 2 or joker_id == 4:  # Skip Entropy Engine, Ritual Blade, and Final Joke (already applied)
			continue
		var before_mult := chips_earned
		chips_earned = joker.modify_chips(chips_earned)
		if chips_earned != before_mult:
			var joker_id_mult = _get_joker_id_from_instance(joker)
			var joker_name_mult = joker.get("name") if joker.get("name") else "Unknown"
			var mult = float(chips_earned) / float(before_mult) if before_mult > 0 else 1.0
			score_breakdown["multipliers"].append({
				"joker": joker_name_mult,
				"joker_id": joker_id_mult,
				"multiplier": mult
			})
	
	# Chaos penalty system removed
	score_breakdown["chaos_penalty"] = 1.0
	# Final score = running (after all mults) + chaos bonus; use chaos at spin start (e.g. first spin 10 → 1.1)
	var base_display: float = float(base_score * SCORE_MULTIPLIER)
	var running_display: float = base_display
	for mult_entry in score_breakdown["multipliers"]:
		var m: float = round(float(mult_entry["multiplier"]) * 10.0) / 10.0
		running_display *= m
	var chaos_bonus_display: float = running_display * (float(run_state.chaos) / 100.0)
	chips_earned = int(round(running_display + chaos_bonus_display))
	score_breakdown["final_score"] = chips_earned
	score_breakdown["base_score"] = base_score * SCORE_MULTIPLIER
	for row_data in score_breakdown["row_hands"]:
		if row_data is Dictionary and row_data.has("score"):
			row_data["score"] = row_data["score"] * SCORE_MULTIPLIER
	# Final Joke (Joker 4) final spin: double each row score and total for display (×2 already in chips_earned/final_score)
	if is_final_joke_spin:
		for row_data in score_breakdown["row_hands"]:
			if row_data is Dictionary and row_data.has("score"):
				row_data["score"] = row_data["score"] * 2
	
	# Store breakdown in result for later use
	result.score_breakdown = score_breakdown
	
	# Update result with final score
	result.score = chips_earned
	
	if apply_rewards:
		run_state.add_chips(chips_earned)
		run_state.add_xp(int(chips_earned / float(SCORE_MULTIPLIER)))
	
	hand_evaluated.emit(result)
	var _active_count := active_jokers.size()
	var _msg := "Hand (rows): Base Sum: %d, Final: %d chips (Active Jokers: %d)"
	
	return result

func add_owned_joker(joker) -> void:
	# Add joker to owned collection (if under limit)
	if owned_jokers.size() >= MAX_OWNED_JOKERS:
		return  # Can't own more than max
	
	# Check if already owned
	for owned in owned_jokers:
		if _get_joker_id_from_instance(owned) == _get_joker_id_from_instance(joker):
			return  # Already owned
	
	owned_jokers.append(joker)
	# Jokers do NOT increase chaos just by existing
	# Chaos only increases when jokers trigger (in _update_chaos_after_spin)
	jokers_changed.emit()

func remove_owned_joker(joker) -> void:
	owned_jokers.erase(joker)
	jokers_changed.emit()

func _get_joker_placement_for_spin():  # -> { slot_index: int, joker_card: JokerCard } or null
	# Used at spins 3, 6, 9 to pre-determine joker so spin_resolver can place it when applying reel (animation result).
	if spin_count != 3 and spin_count != 6 and spin_count != 9:
		return null
	var available_jokers: Array[int] = []
	for joker_id in [1, 2, 5]:
		var already_has = false
		for owned_joker in owned_jokers:
			var owned_id = _get_joker_id_from_instance(owned_joker)
			if owned_id == joker_id:
				already_has = true
				break
		if not already_has:
			var joker_on_board = false
			for i in range(board.TOTAL_SLOTS):
				var item = board.get_card(i)
				if item != null and item.is_joker and item.joker_id == joker_id:
					joker_on_board = true
					break
			if not joker_on_board:
				available_jokers.append(joker_id)
	if available_jokers.is_empty():
		return null
	var available_slots: Array[int] = []
	for i in range(board.TOTAL_SLOTS):
		if board.is_locked(i):
			continue
		var item = board.get_card(i)
		if item != null and item.is_joker:
			continue
		available_slots.append(i)
	if available_slots.is_empty():
		return null
	var random_joker_id = available_jokers[randi() % available_jokers.size()]
	var slot_index = available_slots[randi() % available_slots.size()]
	var joker_card = JokerCard.new(random_joker_id)
	return { "slot_index": slot_index, "joker_card": joker_card }

func _check_joker_appearances_from_spins() -> void:
	# Joker Appearance Rules:
	# Spin 3 → Random joker from 1, 2, or 5 appears on grid
	# Spin 6 → Random joker from 1, 2, or 5 appears on grid (if not already owned)
	# Spin 9 → Random joker from 1, 2, or 5 appears on grid (if not already owned)
	# NOTE: Joker 3 (Pressure Valve) is excluded until implementation is complete
	
	# If joker was already placed via spin_resolver (for animation integration), skip spawn
	if _joker_placed_via_resolver_this_spin:
		return
	# Place one random joker on grid at spins 3, 6, 9
	# NOTE: Joker 3 (Pressure Valve) is not ready yet, so only jokers 1, 2, and 5 can appear
	if spin_count == 3 or spin_count == 6 or spin_count == 9:
		# Get list of available jokers (1, 2, 5) that player doesn't have
		# Joker 3 excluded until implementation is complete
		var available_jokers: Array[int] = []
		for joker_id in [1, 2, 5]:
			var already_has = false
			
			# Check if player already owns this joker
			for owned_joker in owned_jokers:
				var owned_id = _get_joker_id_from_instance(owned_joker)
				if owned_id == joker_id:
					already_has = true
					break
			
			# Check if joker is already on the board
			if not already_has:
				var joker_on_board = false
				for i in range(board.TOTAL_SLOTS):
					var item = board.get_card(i)
					if item != null and item.is_joker and item.joker_id == joker_id:
						joker_on_board = true
						break
				
				if not joker_on_board:
					available_jokers.append(joker_id)
		
		# Spawn a random available joker
		if not available_jokers.is_empty():
			var random_joker_id = available_jokers[randi() % available_jokers.size()]
			_spawn_joker_on_grid(random_joker_id)

func _check_final_joke_appearance() -> void:
	# Place The Final Joke on grid only after chaos reaches 90 (if not already owned/on board)
	# Check that chaos is >= 90 (after chaos is updated)
	if run_state.chaos >= CHAOS_COLLAPSE_WARNING:
		var has_final_joke = false
		for owned_joker in owned_jokers:
			var owned_id = _get_joker_id_from_instance(owned_joker)
			if owned_id == 4:  # The Final Joke
				has_final_joke = true
				break
		
		# Also check if joker is already on the board
		var joker_on_board = false
		if not has_final_joke:
			for i in range(board.TOTAL_SLOTS):
				var item = board.get_card(i)
				if item != null and item.is_joker and item.joker_id == 4:
					joker_on_board = true
					break
		
		if not has_final_joke and not joker_on_board:
			_spawn_joker_on_grid(4)  # The Final Joke

func _spawn_joker_on_grid(joker_id: int) -> void:
	# Place a joker card on the grid at a random unlocked slot (jokers persist once placed)
	if joker_id < 1 or joker_id > 5:
		return  # Invalid joker ID
	
	if board == null:
		return
	
	# Find available slots (not locked, and not already containing a joker)
	var available_slots: Array[int] = []
	for i in range(board.TOTAL_SLOTS):
		if board.is_locked(i):
			continue  # Skip locked slots
		var item = board.get_card(i)
		if item != null and item.is_joker:
			continue  # Skip slots that already have jokers
		available_slots.append(i)
	
	if available_slots.is_empty():
		# No available slots - skip this spin
		return
	
	# Pick a random available slot
	var slot_index = available_slots[randi() % available_slots.size()]
	
	# Create and place the joker card on the board (can replace a card, but jokers persist)
	var joker_card = JokerCard.new(joker_id)
	board.set_card(slot_index, joker_card)

func _give_joker_to_player(joker_id: int) -> void:
	# Create and add joker instance to owned collection
	# This is called when player interacts with a joker on the board
	if joker_id < 1 or joker_id > 5:
		return  # Invalid joker ID
	
	var joker_class = load("res://scripts/core/jokers/joker" + str(joker_id) + ".gd")
	if joker_class:
		var joker_instance = joker_class.new()
		add_owned_joker(joker_instance)

func _activate_jokers_for_spin() -> void:
	# Clear previous active jokers
	active_jokers.clear()
	
	# Activate jokers from owned_jokers AND jokers currently on the grid
	# (Jokers on grid appear at spins 3,6,9 and will be collected after spin)
	var jokers_to_check: Array = []
	
	# Add owned jokers
	for owned_joker in owned_jokers:
		if owned_joker != null:
			jokers_to_check.append(owned_joker)
	
	# Add jokers currently on the grid (for the spin they appear on)
	for i in range(board.TOTAL_SLOTS):
		var item = board.get_card(i)
		if item != null and item.is_joker:
			var joker_card = item as JokerCard
			if joker_card != null:
				var joker_id = joker_card.joker_id
				# Skip Final Joke (Joker 4) - it persists on grid when chaos >= 90
				if joker_id == 4:
					# Create joker instance for Final Joke on grid
					var joker_path = "res://scripts/core/jokers/joker" + str(joker_id) + ".gd"
					var joker_class = load(joker_path)
					if joker_class:
						var joker_instance = joker_class.new()
						jokers_to_check.append(joker_instance)
				else:
					# Normal jokers (1,2,3,5) - create instance for this spin
					var joker_path = "res://scripts/core/jokers/joker" + str(joker_id) + ".gd"
					var joker_class = load(joker_path)
					if joker_class:
						var joker_instance = joker_class.new()
						jokers_to_check.append(joker_instance)
	
	var _owned_count = owned_jokers.size()
	
	# Build context for trigger conditions
	var context := {
		"board": board,
		"chaos": run_state.chaos,
		"previous_score": previous_spin_score,
		"locked_count": board.get_locked_count(),
		"hand_type": -1  # Will be set after evaluation
	}
	
	# Get all jokers that should trigger
	var triggered_jokers: Array = []
	for joker in jokers_to_check:
		if joker != null and joker.has_method("should_trigger"):
			if joker.should_trigger(context):
				triggered_jokers.append(joker)
			else:
				pass
		else:
			pass
	
	# Sort by priority (higher priority first)
	triggered_jokers.sort_custom(
		func(a, b): return a.priority > b.priority
	)
	
	# Apply cap: only activate top N jokers
	var max_activate = min(triggered_jokers.size(), MAX_ACTIVE_JOKERS)
	var jokers_to_activate = triggered_jokers.slice(0, max_activate)
	active_jokers = jokers_to_activate
	
	for joker in active_jokers:
		var _joker_id = _get_joker_id_from_instance(joker)
	
	jokers_changed.emit()

func _activate_joker_from_board(joker_card: BoardItem) -> void:
	# Convert JokerCard on board to owned Joker instance
	# NOTE: Jokers are now given automatically at spins 3, 6, 9 and Chaos 90
	# This function is kept for backward compatibility but should not be used in normal gameplay
	if joker_card == null or not joker_card.is_joker:
		return
	
	var joker_id = joker_card.joker_id
	if joker_id < 1 or joker_id > 5:
		return  # Only jokers 1-5 exist now
	
	# Check if this joker is already owned
	for owned_joker in owned_jokers:
		var owned_id = _get_joker_id_from_instance(owned_joker)
		if owned_id == joker_id:
			return  # Already owned
	
	# Create and add the corresponding Joker instance to owned collection
	var joker_class = load("res://scripts/core/jokers/joker" + str(joker_id) + ".gd")
	if joker_class:
		var joker_instance = joker_class.new()
		add_owned_joker(joker_instance)

func _get_jokers_to_collect() -> Array:
	# Returns list of { "slot_index": int, "joker_id": int } for jokers on grid that will be collected (not owned, not Joker 4).
	var list: Array = []
	for i in range(board.TOTAL_SLOTS):
		var item = board.get_card(i)
		if item == null or not item.is_joker:
			continue
		var joker_card = item as JokerCard
		if joker_card == null:
			continue
		var joker_id = joker_card.joker_id
		if joker_id == 4:
			continue
		var already_owned = false
		for owned_joker in owned_jokers:
			if _get_joker_id_from_instance(owned_joker) == joker_id:
				already_owned = true
				break
		if not already_owned:
			list.append({ "slot_index": i, "joker_id": joker_id })
	return list

func _collect_jokers_from_grid() -> void:
	# Collect jokers from grid and add to owned_jokers, then remove from grid
	# This happens after each spin completes (or after each reward cutscene)
	# Final Joke (Joker 4) persists on grid when chaos >= 90, so skip it
	for i in range(board.TOTAL_SLOTS):
		var item = board.get_card(i)
		if item != null and item.is_joker:
			var joker_card = item as JokerCard
			if joker_card != null:
				var joker_id = joker_card.joker_id
				if joker_id == 4:
					continue
				var already_owned = false
				for owned_joker in owned_jokers:
					var owned_id = _get_joker_id_from_instance(owned_joker)
					if owned_id == joker_id:
						already_owned = true
						break
				if not already_owned:
					var joker_path = "res://scripts/core/jokers/joker" + str(joker_id) + ".gd"
					var joker_class = load(joker_path)
					if joker_class:
						var joker_instance = joker_class.new()
						add_owned_joker(joker_instance)
				
				board.set_card(i, null)

func _get_joker_id_from_instance(joker) -> int:
	# Extract joker ID from a Joker instance
	# Resources don't have has() method, so we access properties directly
	if joker == null:
		return 0
	
	# Try to get the id property (Resources support get() method)
	var id_value = joker.get("id")
	if id_value != null:
		var id_str = str(id_value)
		if id_str.begins_with("joker"):
			var num_str = id_str.substr(5)
			var num = num_str.to_int()
			if num > 0:
				return num
	
	return 0

func spin() -> bool:
	# Block input if run has ended or if we're waiting to show run-ended after score sequence
	if is_run_ended or game_state == GameState.ENDED or _pending_run_ended_message != "":
		return false
	# During reward cutscene, spin is already "in progress" (waiting for animation to finish)
	if game_state == GameState.REWARD_CUTSCENE:
		return false
	
	# Check if player has spins remaining
	if not run_state.use_spin():
		# Show notification that spins are exhausted
		spins_exhausted.emit("Out of spins! Level up to continue.")
		# Reset state back to RUNNING if spin failed
		set_game_state(GameState.RUNNING)
		return false  # No spins remaining

	# Clear "just granted" so the upcoming spin is treated as the actual final spin when it completes
	_final_spin_just_granted = false

	spin_started.emit()

	# Track lock charges for breakdown
	_locks_before_spin = run_state.lock_charges
	_lock_spent_this_spin = false
	_lock_restored_this_spin = false
	_locks_after_spend = run_state.lock_charges
	_locks_after_restore = run_state.lock_charges
	
	# Check if any cards were locked before spin
	var locked_count = board.get_locked_count()
	if locked_count > 0:
		cards_locked_before_spin = true
		# Consume 1 lock charge per locked card
		var charges_needed = locked_count
		var charges_consumed = 0
		for i in range(charges_needed):
			if run_state.use_lock_charge():
				charges_consumed += 1
			else:
				# Not enough charges - unlock all cards and proceed
				_clear_all_locks()
				cards_locked_before_spin = false
				break
		
		if charges_consumed > 0:
			_lock_spent_this_spin = true
	else:
		cards_locked_before_spin = false
	
	_locks_after_spend = run_state.lock_charges
	_locks_after_restore = run_state.lock_charges
	
	# Jokers are collected when reel stops (reel_stopped → reward cutscene → notify), not at start of spin
	spin_count += 1
	active_jokers.clear()
	jokers_changed.emit()
	run_state.reset_chips()
	locked_count_this_spin = 0
	_joker_placed_via_resolver_this_spin = false
	var joker_placement = _get_joker_placement_for_spin()
	if joker_placement != null:
		spin_resolver.set_joker_placement(joker_placement.slot_index, joker_placement.joker_card)
		_joker_placed_via_resolver_this_spin = true
	spin_resolver.prepare_first_array()
	var board_view = get_tree().get_first_node_in_group("board_view")
	if board_view and board_view.has_method("start_spin_animation"):
		board_view.start_spin_animation()
	spin_resolver.spin()
	if board_view and board_view.has_method("refresh_strip_grid_from_board"):
		board_view.refresh_strip_grid_from_board()
	return true

func notify_joker_reward_animation_finished(slot_index: int, joker_id: int) -> void:
	# Add to owned; leave joker on grid so the card stays visible (no black blank). Next spin will overwrite the slot.
	var joker_path = "res://scripts/core/jokers/joker" + str(joker_id) + ".gd"
	var joker_class = load(joker_path)
	if joker_class:
		var joker_instance = joker_class.new()
		add_owned_joker(joker_instance)
	jokers_changed.emit()
	# Remove from pending
	for i in range(_pending_joker_rewards.size()):
		if _pending_joker_rewards[i].slot_index == slot_index and _pending_joker_rewards[i].joker_id == joker_id:
			_pending_joker_rewards.remove_at(i)
			break
	if _pending_joker_rewards.is_empty():
		set_game_state(GameState.RUNNING)
		ready_for_score_overlay.emit()
	else:
		var next_entry = _pending_joker_rewards[0]
		joker_reward_cutscene.emit(next_entry.slot_index, next_entry.joker_id)

## Call when the reel has stopped (before row score overlay). Runs joker reward if any, then emits ready_for_score_overlay.
func reel_stopped() -> void:
	var to_collect = _get_jokers_to_collect()
	if to_collect.is_empty():
		ready_for_score_overlay.emit()
		return
	set_game_state(GameState.REWARD_CUTSCENE)
	_pending_joker_rewards = to_collect.duplicate()
	var first = _pending_joker_rewards[0]
	joker_reward_cutscene.emit(first.slot_index, first.joker_id)

func toggle_lock(slot_index: int) -> bool:
	# Block input if run has ended
	if is_run_ended:
		return false  # Run has ended, ignore input
	
	var currently_locked = board.is_locked(slot_index)
	var board_view = get_tree().get_first_node_in_group("board_view")
	
	if currently_locked:
		# Unlocking is always allowed (no charge cost)
		board.set_locked(slot_index, false)
		# Update visual
		if board_view and board_view.has_method("update_card_visual"):
			board_view.update_card_visual(slot_index)
		return true
	
	# Cannot lock cards that were part of the previous win (scoring rows)
	if _slots_in_previous_win.has(slot_index):
		return false

	# Check if we have lock charges available
	# Players can lock as many cards as they have charges for (no limit on number of cards)
	# Note: Charges are consumed when spin is pressed, not when locking
	if run_state.lock_charges <= 0:
		# No charges available - cannot lock
		return false

	# Lock the card
	board.set_locked(slot_index, true)
	locked_count_this_spin += 1
	var sm = get_node_or_null("/root/SfxManager")
	if sm:
		sm.play_lock()
	# Update visual
	if board_view and board_view.has_method("update_card_visual"):
		board_view.update_card_visual(slot_index)
	
	return true

func _update_slots_in_previous_win(hand_result: Dictionary) -> void:
	_slots_in_previous_win.clear()
	var score_breakdown = hand_result.get("score_breakdown", {})
	if score_breakdown == null:
		return
	var row_hands = score_breakdown.get("row_hands", [])
	if row_hands == null:
		return
	for row_idx in range(row_hands.size()):
		var row_data = row_hands[row_idx]
		if row_data is Dictionary:
			var s = row_data.get("score", 0)
			if s and (int(s) if s is int else int(float(s))) > 0:
				var matching: Array = row_data.get("matching_cards", [])
				for card in matching:
					if card != null:
						var slot: int = board.get_slot_index_for_item(card)
						if slot >= 0 and not _slots_in_previous_win.has(slot):
							_slots_in_previous_win.append(slot)

## Call when scroll animation has finished so lock icons disappear after cards stop (not when spin is clicked).
func clear_locks_after_spin_animation() -> void:
	_clear_all_locks()

func _clear_all_locks() -> void:
	# Clear all locks after spin (locks expire automatically)
	# Exception: Joker 5 (Steady Hand) randomly locks one card on the grid after clearing
	
	# Clear all locks first
	for i in range(board.TOTAL_SLOTS):
		if board.is_locked(i):
			board.set_locked(i, false)
			# Update visual for each unlocked card
			var board_view = get_tree().get_first_node_in_group("board_view")
			if board_view and board_view.has_method("update_card_visual"):
				board_view.update_card_visual(i)
	
	# Check if Joker 5 is active
	var has_joker5 := false
	for joker in active_jokers:
		var joker_id = _get_joker_id_from_instance(joker)
		if joker_id == 5:  # Steady Hand
			has_joker5 = true
			break
	
	# If Joker 5 is active, randomly lock one card on the grid
	if has_joker5:
		# Collect all unlocked slots (cards that can be locked)
		var available_slots: Array[int] = []
		for i in range(board.TOTAL_SLOTS):
			# Only lock slots that have cards (not empty) and are not jokers
			var item = board.get_card(i)
			if item != null and not item.is_joker:
				available_slots.append(i)
		
		# Randomly select one to lock
		if not available_slots.is_empty():
			var selected_slot = available_slots[randi() % available_slots.size()]
			board.set_locked(selected_slot, true)
			
			# Update visual to show the lock
			var board_view = get_tree().get_first_node_in_group("board_view")
			if board_view and board_view.has_method("update_card_visual"):
				board_view.update_card_visual(selected_slot)

func _restore_lock_charge_on_combo(hand_result: Dictionary) -> void:
	# Restore 1 lock charge if score is more than 30 (display: 3000) per spin
	var final_score = hand_result.get("score", 0)
	if final_score > 30 * SCORE_MULTIPLIER:
		var before: int = int(run_state.lock_charges)
		run_state.restore_lock_charge()
		_lock_restored_this_spin = run_state.lock_charges > before
		_locks_after_restore = run_state.lock_charges
	else:
		_lock_restored_this_spin = false
		_locks_after_restore = run_state.lock_charges

func _build_breakdown_dict(hand_result: Dictionary) -> Dictionary:
	var score_breakdown = hand_result.get("score_breakdown", {})
	var chaos_breakdown = hand_result.get("chaos_breakdown", {})
	if score_breakdown == null:
		score_breakdown = {}
	if chaos_breakdown == null:
		chaos_breakdown = {}
	var breakdown := {
		"score": score_breakdown,
		"chaos": chaos_breakdown,
		"active_jokers": [],
		"locks": {
			"before": _locks_before_spin,
			"spent": _lock_spent_this_spin,
			"after_spend": _locks_after_spend,
			"restored": _lock_restored_this_spin,
			"after": _locks_after_restore,
			"locked_cards": board.get_locked_count()
		}
	}
	for joker in active_jokers:
		if joker == null:
			continue
		var joker_id = _get_joker_id_from_instance(joker)
		var joker_info := {
			"name": joker.get("name") if joker.get("name") else "Unknown",
			"id": joker_id,
			"description": joker.get("description") if joker.get("description") else "",
			"priority": int(joker.get("priority")) if joker.get("priority") != null else 0,
			"chaos_cost": joker.get("chaos_cost") if joker.get("chaos_cost") != null else 1
		}
		breakdown["active_jokers"].append(joker_info)
	return breakdown

func _emit_spin_breakdown(hand_result: Dictionary) -> void:
	var breakdown: Dictionary = _build_breakdown_dict(hand_result)
	spin_breakdown.emit(breakdown)
	
	# Check if breakdown contains Joker 4 (The Final Joke) - if so, end the game
	var has_joker4_in_breakdown = false
	var active_jokers_list = breakdown.get("active_jokers", [])
	for joker_info in active_jokers_list:
		var joker_id = joker_info.get("id", 0)
		var joker_name = joker_info.get("name", "").to_lower()
		if joker_id == 4 or "joker 4" in joker_name or "final joke" in joker_name:
			has_joker4_in_breakdown = true
			break
	
	# Also check score breakdown multipliers for Joker 4
	if not has_joker4_in_breakdown:
		var score_breakdown = breakdown.get("score", {})
		var multipliers = score_breakdown.get("multipliers", [])
		for mult in multipliers:
			var mult_joker_id = mult.get("joker_id", 0)
			var mult_joker_name = mult.get("joker", "").to_lower()
			if mult_joker_id == 4 or "joker 4" in mult_joker_name or "final joke" in mult_joker_name:
				has_joker4_in_breakdown = true
				break
	
	# If Joker 4 is in breakdown and this is the final spin, do not pause here — let score overlay run, then run_ended after score_sequence_finished
	if has_joker4_in_breakdown and not is_final_joke_spin:
		get_tree().paused = true
		_show_end_notification_after_delay()

## Call after initial deal to show scores, total, chaos and breakdown on first screen (no chips/chaos change).
func evaluate_initial_display() -> Dictionary:
	_activate_jokers_for_spin()
	var hand_result: Dictionary = evaluate_hand(false)
	var c: int = run_state.chaos
	var chaos_breakdown := {
		"base_spin": 0,
		"failed_penalty": 0,
		"collapse_warning_extra": 0,
		"total_gain": 0,
		"reductions": [],
		"total_reduction": 0,
		"net_change": 0,
		"chaos_before": c,
		"chaos_after": c
	}
	hand_result["chaos_breakdown"] = chaos_breakdown
	var score_breakdown = hand_result.get("score_breakdown", {})
	if score_breakdown == null:
		score_breakdown = {}
	var breakdown := {
		"score": score_breakdown,
		"chaos": chaos_breakdown,
		"active_jokers": [],
		"locks": {
			"before": run_state.lock_charges,
			"spent": false,
			"after_spend": run_state.lock_charges,
			"restored": false,
			"after": run_state.lock_charges,
			"locked_cards": board.get_locked_count()
		}
	}
	initial_score_breakdown.emit(breakdown)
	# Add initial hand score to chips so top bar shows initial state (not 0)
	run_state.add_chips(hand_result.get("score", 0))
	# Block locking cards that were part of this initial scoring hand
	_update_slots_in_previous_win(hand_result)
	return hand_result

func _show_end_notification_after_delay() -> void:
	# Wait 1 second before showing ending notification
	await get_tree().create_timer(1.0).timeout
	# Set state to ENDED
	is_run_ended = true
	set_game_state(GameState.ENDED)
	var message = "Final Spin Complete! Final Score: %d chips" % run_state.total_chips
	run_ended.emit(message)
