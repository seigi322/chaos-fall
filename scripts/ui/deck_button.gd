extends Button

## Deck button that emits signal when pressed
## The Main UI controller handles instantiating the deck panel

signal deck_pressed

func _ready() -> void:
	pressed.connect(_on_pressed)

func _on_pressed() -> void:
	deck_pressed.emit()
