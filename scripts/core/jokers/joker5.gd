extends Joker
class_name Joker5

## Joker 5: Steady Hand
## Purpose: Consistency / reliability
## Effect: Each spin, one randomly chosen locked card stays locked for an extra spin
## All other locks behave normally (expire after 1 spin)

func _init() -> void:
	super._init("joker5", "Steady Hand", "One locked card stays locked for extra spin")
	priority = 3
	chaos_cost = 0  # Does not increase chaos gain

func should_trigger(_context: Dictionary) -> bool:
	# Always active (like Jokers 1 and 2)
	# Effect only applies when there are locked cards (checked in _clear_all_locks)
	return true

func modify_chips(base_chips: int) -> int:
	return base_chips

func modify_score(base_score: int, _hand_type: int, _board: Board) -> int:
	return base_score

func get_chaos_reduction(_context: Dictionary) -> int:
	# Never reduces chaos
	return 0
