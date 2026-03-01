extends BoardItem
class_name Card

## Represents a playing card with suit and value
## Values: 1-13 (Ace=1, 2-10, Jack=11, Queen=12, King=13)
## Suits: "diamonds", "spades", "hearts", "clubs"

@export var value: int = 1  # 1-13 (Ace=1, 2-10, J=11, Q=12, K=13)
@export var suit: String = "diamonds"  # "diamonds", "spades", "hearts", "clubs"

func _init(p_value: int = 1, p_suit: String = "diamonds") -> void:
	is_joker = false
	value = p_value
	suit = p_suit

func get_texture_path() -> String:
	var suit_index: int = CardTextureResolver.SUIT_MAP[suit]
	var card_id := "%d%d" % [suit_index, value]
	return CardTextureResolver.CARDS_DIR + "Card" + card_id + ".png"

func get_display_name() -> String:
	var value_name := ""
	match value:
		1: value_name = "A"
		11: value_name = "J"
		12: value_name = "Q"
		13: value_name = "K"
		10: value_name = "10"
		_: value_name = str(value)
	return value_name + " " + suit.capitalize()

func is_valid() -> bool:
	return value >= 1 and value <= 13 and CardTextureResolver.SUIT_MAP.has(suit)

