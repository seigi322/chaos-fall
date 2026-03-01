extends Node
class_name CardTextureResolver

const CARDS_DIR := "res://assets/cards/"
const JOKERS_DIR := "res://assets/jokers/"

# suit -> index mapping (DO NOT CHANGE)
const SUIT_MAP := {
	"diamonds": 1,
	"spades": 2,
	"hearts": 3,
	"clubs": 4
}

var cache: Dictionary = {}

func get_card_texture(value: int, suit: String) -> Texture2D:
	# Safety checks
	if not SUIT_MAP.has(suit):
		push_error("Unknown suit: " + suit)
		return null

	if value < 1 or value > 13:
		push_error("Invalid card value: " + str(value))
		return null

	# Build card index number
	var suit_index: int = SUIT_MAP[suit]
	var card_id := "%d%d" % [suit_index, value]

	# Example: Card310.png (Ten of Hearts), Card311.png (Jack of Hearts)
	var path := CARDS_DIR + "Card" + card_id + ".png"

	# Cache for performance
	if cache.has(path):
		return cache[path]

	if not ResourceLoader.exists(path):
		push_error("Missing card texture: " + path)
		return null

	var tex: Texture2D = load(path)
	cache[path] = tex
	return tex

func get_joker_texture(joker_id: int) -> Texture2D:
	# Safety check
	if joker_id < 1 or joker_id > 10:
		push_error("Invalid joker ID: " + str(joker_id))
		return null
	
	var path := JOKERS_DIR + "joker" + str(joker_id) + ".png"
	
	# Cache for performance
	if cache.has(path):
		return cache[path]
	
	if not ResourceLoader.exists(path):
		push_error("Missing joker texture: " + path)
		return null
	
	var tex: Texture2D = load(path)
	
	# Note: Texture filtering is controlled by import settings
	# For pixel-perfect joker rendering, joker textures should have:
	# - Filter = Off (in import settings)
	# - Mipmaps = Off (already set in import)
	# - Alpha channel preserved (already set in import)
	# These settings are configured in the .import files
	
	cache[path] = tex
	return tex

func get_texture_for_item(item: BoardItem) -> Texture2D:
	if item == null:
		return null
	
	if item.is_joker:
		return get_joker_texture(item.joker_id)
	
	var card = item as Card
	if card:
		return get_card_texture(card.value, card.suit)
	
	return null
