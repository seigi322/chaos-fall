extends Node
class_name Board

## Manages the 5x3 grid of cards and jokers (15 slots total)

const GRID_WIDTH := 5
const GRID_HEIGHT := 3
const TOTAL_SLOTS := GRID_WIDTH * GRID_HEIGHT

signal card_changed(slot_index: int, item: BoardItem)
signal board_updated()

var slots: Array[BoardItem] = []
var locked_slots: Array[bool] = []

func _ready() -> void:
	clear_board()

func clear_board() -> void:
	slots.clear()
	locked_slots.clear()
	for i in range(TOTAL_SLOTS):
		slots.append(null)
		locked_slots.append(false)
	board_updated.emit()

func set_card(slot_index: int, item: BoardItem) -> bool:
	if slot_index < 0 or slot_index >= TOTAL_SLOTS:
		push_error("Invalid slot index: " + str(slot_index))
		return false
	
	if locked_slots[slot_index]:
		return false  # Can't change locked cards
	
	slots[slot_index] = item
	card_changed.emit(slot_index, item)
	return true

## Call after bulk updates so UI can refresh all card visuals (e.g. after spin).
func notify_updated() -> void:
	board_updated.emit()

func get_card(slot_index: int) -> BoardItem:
	if slot_index < 0 or slot_index >= TOTAL_SLOTS:
		return null
	return slots[slot_index]

## Returns the slot index that holds the given item, or -1 if not found.
func get_slot_index_for_item(item: BoardItem) -> int:
	if item == null:
		return -1
	for i in range(TOTAL_SLOTS):
		if slots[i] == item:
			return i
	return -1

func is_locked(slot_index: int) -> bool:
	if slot_index < 0 or slot_index >= TOTAL_SLOTS:
		return false
	return locked_slots[slot_index]

func set_locked(slot_index: int, locked: bool) -> void:
	if slot_index < 0 or slot_index >= TOTAL_SLOTS:
		return
	locked_slots[slot_index] = locked

func get_locked_count() -> int:
	var count := 0
	for locked in locked_slots:
		if locked:
			count += 1
	return count

func get_all_cards() -> Array[Card]:
	var result: Array[Card] = []
	for item in slots:
		if item != null and not item.is_joker:
			result.append(item as Card)
	return result

func get_all_items() -> Array[BoardItem]:
	var result: Array[BoardItem] = []
	for item in slots:
		if item != null:
			result.append(item)
	return result

## Get all non‑joker cards in a specific row (0‑based, left → right)
func get_row_cards(row_index: int) -> Array[Card]:
	var result: Array[Card] = []
	if row_index < 0 or row_index >= GRID_HEIGHT:
		return result
	
	for col in range(GRID_WIDTH):
		var slot_index := row_index * GRID_WIDTH + col
		var item := slots[slot_index]
		if item != null and not item.is_joker:
			result.append(item as Card)
	return result

func get_unlocked_cards() -> Array[Card]:
	var result: Array[Card] = []
	for i in range(TOTAL_SLOTS):
		if not locked_slots[i] and slots[i] != null and not slots[i].is_joker:
			result.append(slots[i] as Card)
	return result

func get_locked_cards() -> Array[Card]:
	var result: Array[Card] = []
	for i in range(TOTAL_SLOTS):
		if locked_slots[i] and slots[i] != null and not slots[i].is_joker:
			result.append(slots[i] as Card)
	return result

func get_empty_slots() -> Array[int]:
	var result: Array[int] = []
	for i in range(TOTAL_SLOTS):
		if slots[i] == null:
			result.append(i)
	return result

func get_unlocked_slots() -> Array[int]:
	var result: Array[int] = []
	for i in range(TOTAL_SLOTS):
		if not locked_slots[i]:
			result.append(i)
	return result
