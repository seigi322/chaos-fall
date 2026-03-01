extends Resource
class_name BoardItem

## Base class for items that can be displayed on the board (cards and jokers)

@export var is_joker: bool = false
@export var joker_id: int = 0  # 1-10 for jokers

func get_texture_path() -> String:
	return ""

func get_display_name() -> String:
	return ""

func _to_string() -> String:
	return get_display_name()
