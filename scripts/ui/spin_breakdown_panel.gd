extends PanelContainer

## Displays detailed breakdown of score, chaos changes, and active jokers after each spin

const SCORE_MULTIPLIER := 100  # Must match game.gd: display scale 10 → 1000

@onready var breakdown_label: RichTextLabel = \
	$OuterMargin/ScrollContainer/VBoxContainer/BreakdownLabel

var game: Node = null
var last_card_info_line: int = -1  # Track the line number of the last card info

func _ready() -> void:
	# Panel visibility is controlled by the parent scene (hidden by default)
	call_deferred("_initialize_game")
	call_deferred("_debug_visibility")

func _initialize_game() -> void:
	# Wait for Game to be ready (retry up to 10 times)
	var attempts := 0
	while attempts < 10:
		await get_tree().process_frame
		
		# Find game controller
		game = get_node_or_null("/root/Main/Game")
		if game == null:
			game = get_tree().get_first_node_in_group("game")
		
		if game != null and game.has_signal("spin_breakdown"):
			if not game.spin_breakdown.is_connected(_on_spin_breakdown):
				game.spin_breakdown.connect(_on_spin_breakdown)
			if game.has_signal("total_score_hidden"):
				if not game.total_score_hidden.is_connected(_on_spin_breakdown):
					game.total_score_hidden.connect(_on_spin_breakdown)
			_set_initial_breakdown_text()
			return
		
		attempts += 1
	
	# If we get here, we couldn't find the game
	push_error("SpinBreakdownPanel: Game controller not found after %d attempts!" % attempts)
	# Still set initial text even if game not found
	_set_initial_breakdown_text()

func _set_initial_breakdown_text() -> void:
	# Set initial breakdown text in the same format as spin breakdown
	var text := ""
	
	# Evaluate current board state to get actual row scores
	var row_scores := [0, 0, 0]
	var total_score := 0
	
	if game != null and game.board != null and game.combo_eval != null:
		# Evaluate each row to get current scores (3 rows for 5x3 grid)
		for row in range(3):
			var row_cards: Array = game.board.get_row_cards(row)
			if row_cards.size() > 0:
				var row_result: Dictionary = game.combo_eval.evaluate_hand(row_cards)
				var row_score: int = row_result.get("score", 0)
				row_scores[row] = row_score
				total_score += row_score
	
	# Score: show actual row scores
	text += "[b]Score: %d[/b] = " % total_score
	var row_parts: Array[String] = []
	for i in range(row_scores.size()):
		# Rows are 1-based for player (row 1..3)
		row_parts.append("%d(row %d)" % [row_scores[i], i + 1])
	text += " + ".join(row_parts)
	text += "\n"
	
	# Chaos: get initial value from run_state if available
	var initial_chaos := RunState.INITIAL_CHAOS
	if game != null and game.run_state != null:
		initial_chaos = game.run_state.chaos
	text += "[b]Chaos:[/b] %d\n" % initial_chaos
	
	# Active Jokers: none
	text += "[b]Active Jokers:[/b] none\n"
	
	# Locks: get initial value from run_state if available
	var initial_locks := 10
	if game != null and game.run_state != null:
		initial_locks = game.run_state.lock_charges
	text += "[b]Locks:[/b] %d\n" % initial_locks
	
	# Set the text
	if breakdown_label == null:
		breakdown_label = get_node_or_null(
			"OuterMargin/ScrollContainer/VBoxContainer/BreakdownLabel"
		)
	
	if breakdown_label != null:
		breakdown_label.text = text

func _format_multiplier(mult: float) -> String:
	if mult == int(mult):
		return "%d" % int(mult)
	# Show 2 decimals so expression matches game result (e.g. 1.93 not 1.9)
	return "%.2f" % mult

func _on_spin_breakdown(breakdown: Dictionary) -> void:
	# Reset card info tracking when new spin breakdown is shown
	last_card_info_line = -1
	var text := ""
	
	# Score Breakdown - Simple format: Score: 200 = 40(full house) + 10(bonus) x 5 (joker3, joker6)
	var score_data = breakdown.get("score", {})
	if score_data == null:
		score_data = {}
	
	var base_score = score_data.get("base_score", 0)
	var hand_name = score_data.get("hand_name", "None")
	var row_hands = score_data.get("row_hands", [])
	
	# Always show score breakdown, even when score is 0
	# Calculate sum of row scores (base scores from each row)
	var row_sum := 0
	var row_scores := [0, 0, 0]
	if row_hands != null and not row_hands.is_empty():
		for row_result in row_hands:
			var row_index: int = int(row_result.get("row_index", 0))
			var row_score: int = int(row_result.get("score", 0))
			if row_index >= 0 and row_index < row_scores.size():
				row_scores[row_index] = row_score
				row_sum += row_score
	else:
		# Fallback: use base_score if no row_hands
		row_sum = base_score
	
	# Show sum of row scores, then breakdown
	text += "[b]Score: %d[/b] = " % row_sum
	
	# Row breakdown: e.g. 34 (row 1) + 10 (row 2) + 30 (row 3)
	if row_hands != null and not row_hands.is_empty():
		var row_parts: Array[String] = []
		for i in range(row_scores.size()):
			# Rows are 1-based for player (row 1..3)
			row_parts.append("%d(row %d)" % [row_scores[i], i + 1])
		
		text += " + ".join(row_parts)
	else:
		# Fallback: show single base score with hand name, or 0(row 1) + 0(row 2) + 0(row 3) if no hand
		if base_score > 0:
			text += "%d(%s)" % [base_score, hand_name.to_lower()]
		else:
			# Show row breakdown format even when score is 0
			text += "0(row 1) + 0(row 2) + 0(row 3)"
	
	# Flat bonuses
	var flat_bonuses = score_data.get("flat_bonuses", [])
	var total_bonus = 0
	for bonus in flat_bonuses:
		total_bonus += bonus.get("amount", 0)
	
	if total_bonus > 0:
		text += " + %d(bonus)" % (total_bonus * SCORE_MULTIPLIER)
	
	# Score before multipliers: row_sum is scaled; flat bonuses from game are unscaled, scale them
	var score_before_multipliers: int = row_sum + total_bonus * SCORE_MULTIPLIER
	
	# Use actual final score from game so display always matches
	var final_score: int = score_data.get("final_score", row_sum)
	
	# Multipliers - special handling for Joker 1 (Entropy Engine)
	var multipliers = score_data.get("multipliers", [])
	var joker1_multiplier = null
	var joker1_chaos = 0
	
	# Check if Joker 1 is active
	for mult in multipliers:
		var joker_id = mult.get("joker_id", 0)
		if joker_id == 1:  # Entropy Engine
			joker1_multiplier = mult.get("multiplier", 1.0)
			# Get chaos level from breakdown data (use parent scope chaos_data declared later)
			var joker1_chaos_data = breakdown.get("chaos", {})
			if joker1_chaos_data != null:
				joker1_chaos = joker1_chaos_data.get("chaos_after", joker1_chaos_data.get("chaos_before", 0))
			break
	
	# If Joker 1 is active, show explicit calculation
	if joker1_multiplier != null and joker1_multiplier > 1.0:
		var calculated_score = int(float(score_before_multipliers) * joker1_multiplier)
		
		# Check for other multipliers (Final Joke, etc.)
		var other_multipliers = []
		for mult in multipliers:
			var joker_id = mult.get("joker_id", 0)
			if joker_id != 1:  # Skip Joker 1 (already shown)
				var mult_val = mult.get("multiplier", 1.0)
				if mult_val > 1.0:
					other_multipliers.append(mult)
		
		# Apply other multipliers if any
		for mult in other_multipliers:
			var mult_val = mult.get("multiplier", 1.0)
			calculated_score = int(float(calculated_score) * mult_val)
		
		# Show Joker 1 calculation; use exact multiplier values so expression matches game result
		text += " × (1 + %d/100) = %d × %s (joker 1)" % [
			joker1_chaos,
			score_before_multipliers,
			_format_multiplier(joker1_multiplier)
		]
		
		if not other_multipliers.is_empty():
			for mult in other_multipliers:
				var mult_val = mult.get("multiplier", 1.0)
				text += " × %s" % _format_multiplier(mult_val)
				var joker_id = mult.get("joker_id", 0)
				if joker_id > 0:
					text += " (joker %d)" % joker_id
		
		# Show final result from game (always matches actual score)
		text += " = %d" % final_score
		
		# Header shows final score
		text = text.replace("[b]Score: %d[/b]" % row_sum, "[b]Score: %d[/b]" % final_score)
	else:
		# No Joker 1, show normal multiplier display with individual joker labels
		if not multipliers.is_empty():
			for mult in multipliers:
				var mult_val = mult.get("multiplier", 1.0)
				if mult_val > 1.0:
					text += " × %s" % _format_multiplier(mult_val)
					var joker_id = mult.get("joker_id", 0)
					if joker_id > 0:
						text += " (joker %d)" % joker_id
			text += " = %d" % final_score
		# Header always shows final score from game
		text = text.replace("[b]Score: %d[/b]" % row_sum, "[b]Score: %d[/b]" % final_score)
	
	# Add line break after score item
	text += "\n"
	
	# Chaos Breakdown - Format: +10 = +5 (every spin) + 5 (failed spin)
	var chaos_data = breakdown.get("chaos", {})
	if chaos_data == null:
		chaos_data = {}
	
	var net_change = chaos_data.get("net_change", 0)
	var chaos_mult: float = float(chaos_data.get("chaos_multiplier", 1.0))
	if net_change != 0 or chaos_data.has("chaos_before"):
		text += "[b]Chaos:[/b] "
		
		# Show net change
		if net_change > 0:
			text += "[color=#FF6B6B]+%d[/color]" % net_change
		elif net_change < 0:
			text += "[color=#4ECDC4]%d[/color]" % net_change
		else:
			text += "0"
		if chaos_mult > 1.0:
			text += " [color=#E8C547](x%.1f)[/color]" % chaos_mult
		
		# Build breakdown components
		var components = []
		
		# Base spin (every spin) - always +5
		var base_spin = chaos_data.get("base_spin", 0)
		if base_spin > 0:
			components.append({
				"value": base_spin,
				"reason": "every spin",
				"is_positive": true
			})
		
		# Failed spin penalty - +5 if no poker hand in any row
		var failed_penalty = chaos_data.get("failed_penalty", 0)
		if failed_penalty > 0:
			components.append({
				"value": failed_penalty,
				"reason": "failed spin",
				"is_positive": true
			})
		
		# Collapse Warning extra - +1 if chaos ≥90
		var collapse_warning_extra = chaos_data.get("collapse_warning_extra", 0)
		if collapse_warning_extra > 0:
			components.append({
				"value": collapse_warning_extra,
				"reason": "collapse warning",
				"is_positive": true
			})
		
		# Joker 2 (Ritual Blade) - +2 chaos per spin when active
		var joker2_chaos = chaos_data.get("joker2_chaos", 0)
		if joker2_chaos > 0:
			components.append({
				"value": joker2_chaos,
				"reason": "joker 2",
				"is_positive": true
			})
		
		# Build the breakdown string
		if not components.is_empty():
			text += " = "
			var component_strings = []
			for comp in components:
				var sign_char = "+" if comp["is_positive"] else "-"
				var color = "#FF6B6B" if comp["is_positive"] else "#4ECDC4"
				component_strings.append(
					"[color=%s]%s%d[/color] (%s)" % [
						color, sign_char, comp["value"], comp["reason"]
					]
				)
			text += " ".join(component_strings)
		
		text += "\n"
	
	# Active Jokers - Show name and effect/description
	var active_jokers = breakdown.get("active_jokers", [])
	if not active_jokers.is_empty():
		text += "[b]Active Jokers:[/b] "
		var joker_strings = []
		for joker in active_jokers:
			var joker_name = joker.get("name", "")
			var joker_desc = joker.get("description", "")
			var joker_id = joker.get("id", 0)
			
			if joker_name != "" and joker_desc != "":
				joker_strings.append("%s: %s" % [joker_name, joker_desc])
			elif joker_name != "":
				joker_strings.append(joker_name)
			elif joker_id > 0:
				joker_strings.append("joker %d" % joker_id)
			else:
				joker_strings.append("Unknown")
		text += ", ".join(joker_strings)
		text += "\n"
	else:
		text += "[b]Active Jokers:[/b] none\n"

	# Lock Charges - Show current value only
	var locks_data = breakdown.get("locks", {})
	if locks_data == null:
		locks_data = {}
	var locks_after = int(locks_data.get("after", 0))
	var spent = bool(locks_data.get("spent", false))
	var restored = bool(locks_data.get("restored", false))
	var locked_cards = int(locks_data.get("locked_cards", 0))
	
	# Show current lock charges value
	text += "[b]Locks:[/b] %d" % locks_after
	if spent:
		text += "  [color=#FF6B6B]-%d[/color] (used %d locked)" % [locked_cards, locked_cards]
	if restored:
		text += "  [color=#4ECDC4]+1[/color] (scored combo)"
	text += "\n"
	
	# If we have no data at all, show a message
	if text == "":
		text = "[color=#FF6B6B]No breakdown data available for this spin.[/color]\n"
	
	# Debug: Check visibility and sizing step by step
	_debug_visibility()
	
	# Set the text
	if breakdown_label == null:
		breakdown_label = get_node_or_null(
			"OuterMargin/ScrollContainer/VBoxContainer/BreakdownLabel"
		)
	
	if breakdown_label != null:
		breakdown_label.text = text
		
		# Force visibility
		breakdown_label.visible = true
		breakdown_label.modulate = Color.WHITE
		
		# Force update and scroll to top
		await get_tree().process_frame
		breakdown_label.queue_redraw()
		
		var scroll_container = breakdown_label.get_parent().get_parent()
		if scroll_container is ScrollContainer:
			scroll_container.scroll_vertical = 0
			scroll_container.queue_redraw()
	else:
		push_error("SpinBreakdownPanel: breakdown_label is null!")

func show_card_info(info_text: String) -> void:
	# Update card/joker info in the breakdown text (replace previous if exists)
	if breakdown_label == null:
		breakdown_label = get_node_or_null(
			"OuterMargin/ScrollContainer/VBoxContainer/BreakdownLabel"
		)
	
	if breakdown_label == null:
		return
	
	# Get current text
	var current_text = breakdown_label.text
	
	# Remove previous card info if it exists
	if last_card_info_line >= 0:
		var old_lines = current_text.split("\n")
		if last_card_info_line < old_lines.size():
			old_lines.remove_at(last_card_info_line)
			current_text = "\n".join(old_lines)
	
	# Add new card info with formatting at the end
	var card_info_line = "[b][color=#FFD700]%s[/color][/b]" % info_text
	if current_text != "":
		current_text += "\n"
	current_text += card_info_line
	
	# Update last_card_info_line to the new line index
	var new_lines = current_text.split("\n")
	last_card_info_line = new_lines.size() - 1
	
	# Set the updated text
	breakdown_label.text = current_text
	
	# Scroll to bottom to show the new card info
	await get_tree().process_frame
	var scroll_container = breakdown_label.get_parent().get_parent()
	if scroll_container is ScrollContainer:
		await get_tree().process_frame
		scroll_container.scroll_vertical = scroll_container.get_v_scroll_bar().max_value

func _debug_visibility() -> void:
	# Check panel visibility and breakdown_label state
	if breakdown_label == null:
		breakdown_label = get_node_or_null(
			"OuterMargin/ScrollContainer/VBoxContainer/BreakdownLabel"
		)
