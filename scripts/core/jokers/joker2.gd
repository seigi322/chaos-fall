extends Joker
class_name Joker2

## Joker 2: Ritual Blade
## Purpose: Greed acceleration
## Effect: Stacking multiplier +0.2× per spin, +2 chaos gain per spin
## Multiplier resets when run ends
## Works together with Entropy Engine if both are owned

func _init() -> void:
	super._init("joker2", "Ritual Blade", "Stacking multiplier +0.2× per spin, +2 chaos per spin")
	priority = 4
	chaos_cost = 2  # +2 chaos per spin when active

func should_trigger(_context: Dictionary) -> bool:
	# Always active
	return true

func modify_chips(base_chips: int) -> int:
	return base_chips

func modify_score(base_score: int, _hand_type: int, _board: Board) -> int:
	# Multiplier applied in game.gd (tracks consecutive spins)
	return base_score

func get_chaos_reduction(_context: Dictionary) -> int:
	# Never reduces chaos
	return 0
