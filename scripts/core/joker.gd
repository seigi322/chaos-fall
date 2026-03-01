extends Resource
class_name Joker

## Base class for Joker cards that modify gameplay
## Jokers are owned by the player but only activate when conditions are met

@export var id: String = ""
@export var name: String = ""
@export var description: String = ""
@export var texture_path: String = ""
@export var priority: int = 0  # Higher priority jokers activate first when cap is reached
@export var chaos_cost: int = 1  # Chaos gained when this joker triggers (default: 1)
@export var can_reduce_chaos: bool = false  # Can this joker reduce chaos?
@export var chaos_reduction: int = 0  # How much chaos to reduce (if can_reduce_chaos is true)

func _init(p_id: String = "", p_name: String = "", p_description: String = "") -> void:
	id = p_id
	name = p_name
	description = p_description

## Check if this joker should activate based on current game state
## Returns true if conditions are met for this joker to become active
## _context: Dictionary with game state info (hand_type, board, chaos, previous_score, etc.)
func should_trigger(_context: Dictionary) -> bool:
	# Override in subclasses to define trigger conditions
	# Default: always trigger (for jokers that should always be active)
	return true

## Called when evaluating a hand - can modify the score
## board: The current board state for context
func modify_score(base_score: int, _hand_type: int, _board: Board) -> int:
	return base_score

## Called when drawing cards - can modify which cards are drawn
func modify_draw(cards: Array[Card]) -> Array[Card]:
	return cards

## Called when calculating chips - can multiply or add chips
func modify_chips(base_chips: int) -> int:
	return base_chips

## Called after spin to check if this joker should reduce chaos
## Returns amount of chaos to reduce (0 = no reduction)
## _context: Dictionary with game state (score, hand_type, board, etc.)
func get_chaos_reduction(_context: Dictionary) -> int:
	# Override in subclasses for conditional chaos reduction
	# Default: no reduction
	return 0

## Extra multiplier for chaos gain this spin (stacks with tier and other jokers). Default 1.0.
## _context: chaos_before, active_jokers, hand_result, etc.
func get_chaos_gain_multiplier(_context: Dictionary) -> float:
	return 1.0
