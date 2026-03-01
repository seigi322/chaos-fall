extends BoardItem
class_name JokerCard

## Represents a joker card displayed on the board

func _init(p_joker_id: int = 1) -> void:
	is_joker = true
	joker_id = p_joker_id

func get_texture_path() -> String:
	return CardTextureResolver.JOKERS_DIR + "joker" + str(joker_id) + ".png"

func get_display_name() -> String:
	return "Joker " + str(joker_id)
