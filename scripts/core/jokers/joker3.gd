extends Joker
class_name Joker3

## Joker 3: Pressure Valve
## Purpose: Delay Chaos effects
## Effect: Cancels the first Chaos effect that would trigger each spin
## Chaos meter still increases normally
## Only blocks 1 effect per spin
## Does not block Chaos reaching 100

func _init() -> void:
	super._init("joker3", "Pressure Valve", "Cancels first chaos effect per spin")
	priority = 6  # High priority to ensure it activates
	chaos_cost = 0  # Does not increase chaos gain

func should_trigger(_context: Dictionary) -> bool:
	# Always active if owned
	return true

func modify_chips(base_chips: int) -> int:
	return base_chips

func modify_score(base_score: int, _hand_type: int, _board: Board) -> int:
	return base_score

func get_chaos_reduction(_context: Dictionary) -> int:
	# Never reduces chaos
	return 0
