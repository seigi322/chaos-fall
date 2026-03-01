extends Joker
class_name Joker1

## Joker 1: Entropy Engine
## Purpose: Risk = reward
## Effect: Score × (1 + Chaos / 100)
## Examples: Chaos 40 → ×1.4, Chaos 75 → ×1.75
## Does not change Chaos gain
## Multiplier updates dynamically each spin

func _init() -> void:
	super._init("joker1", "Entropy Engine", "Score × (1 + Chaos / 100)")
	priority = 5
	chaos_cost = 0  # Does not increase chaos gain

func should_trigger(_context: Dictionary) -> bool:
	# Always active
	return true

func modify_chips(base_chips: int) -> int:
	return base_chips

func modify_score(base_score: int, _hand_type: int, _board: Board) -> int:
	# This joker modifies chips via modify_chips, not score
	# Score modification happens in game.gd after getting chaos level
	return base_score

func get_chaos_reduction(_context: Dictionary) -> int:
	# Never reduces chaos
	return 0
