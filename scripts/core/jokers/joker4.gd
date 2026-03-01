extends Joker
class_name Joker4

## Joker 4: The Final Joke
## Purpose: Dramatic ending
## Effect: When Chaos reaches 100, allows one final spin (×2 score, ignores chaos effects)
## Run ends automatically after that spin

func _init() -> void:
	super._init("joker4", "The Final Joke", "Allows one final spin at Chaos 100 with ×2 score")
	priority = 10  # Highest priority - critical for game ending
	chaos_cost = 0  # Does not increase chaos gain

func should_trigger(context: Dictionary) -> bool:
	# Only active when chaos >= 100 (prevents game end and grants ×2 score)
	var chaos = context.get("chaos", 0)
	return chaos >= 100

func modify_chips(base_chips: int) -> int:
	return base_chips

func modify_score(base_score: int, _hand_type: int, _board: Board) -> int:
	return base_score

func get_chaos_reduction(_context: Dictionary) -> int:
	# Never reduces chaos
	return 0
