extends VBoxContainer

## Reusable deck card item that displays a card with count and weight

var card_icon: TextureRect = null
var count_label: Label = null
var weight_bar: ProgressBar = null

func _ready() -> void:
	# Find nodes (works for both @onready and dynamic instantiation)
	card_icon = get_node_or_null("CardFrame/CardIcon")
	count_label = get_node_or_null("CountLabel")
	weight_bar = get_node_or_null("weightBar")

func set_data(tex: Texture2D, count: int, weight_0_1: float) -> void:
	# Ensure nodes are found
	if card_icon == null:
		card_icon = get_node_or_null("CardFrame/CardIcon")
	if count_label == null:
		count_label = get_node_or_null("CountLabel")
	if weight_bar == null:
		weight_bar = get_node_or_null("weightBar")
	
	# Set card texture
	if card_icon != null:
		card_icon.texture = tex
	
	# Set count label (always show count, including ×1)
	if count_label != null:
		count_label.visible = true
		count_label.text = "×%d" % count
		# Ensure label has proper sizing and color
		count_label.modulate = Color.WHITE
		count_label.custom_minimum_size = Vector2(0, 20)  # Ensure minimum height
	else:
		push_error("DeckCardItem: count_label node not found!")
	
	# Set weight bar (0.0 to 1.0 range, converted to 0-100)
	if weight_bar != null:
		# Ensure weight bar is visible
		weight_bar.visible = true
		# Ensure min/max values are set
		weight_bar.min_value = 0.0
		weight_bar.max_value = 100.0
		# Set the value (convert from 0.0-1.0 to 0-100)
		var weight_value = clamp(weight_0_1, 0.0, 1.0) * 100.0
		weight_bar.value = weight_value
		
		# Ensure it has a minimum height to be visible
		if weight_bar.custom_minimum_size.y < 12:
			weight_bar.custom_minimum_size = Vector2(0, 16)
	else:
		push_error("DeckCardItem: weight_bar node not found!")