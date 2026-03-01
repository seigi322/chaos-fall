extends Node
class_name ComboEval

## Evaluates poker hands and calculates scores
## NOTE: In game rules, only ROWS (5 cards) are evaluated as poker hands.

enum HandType {
	HIGH_CARD,
	PAIR,
	TWO_PAIR,
	THREE_OF_A_KIND,
	STRAIGHT,
	FLUSH,
	FULL_HOUSE,
	FOUR_OF_A_KIND,
	STRAIGHT_FLUSH,
	ROYAL_FLUSH
}

const HAND_NAMES := {
	HandType.HIGH_CARD: "High Card",
	HandType.PAIR: "One Pair",
	HandType.TWO_PAIR: "Two Pair",
	HandType.THREE_OF_A_KIND: "Three of a Kind",
	HandType.STRAIGHT: "Straight",
	HandType.FLUSH: "Flush",
	HandType.FULL_HOUSE: "Full House",
	HandType.FOUR_OF_A_KIND: "Four of a Kind",
	HandType.STRAIGHT_FLUSH: "Straight Flush",
	HandType.ROYAL_FLUSH: "Royal Flush"
}

## Final scoring table (per 5‑card row, before jokers)
const BASE_SCORES := {
	HandType.HIGH_CARD: 0,          # No score for high card only
	HandType.PAIR: 10,              # One Pair
	HandType.TWO_PAIR: 30,          # Two Pair
	HandType.THREE_OF_A_KIND: 50,   # Three of a Kind
	HandType.STRAIGHT: 80,          # Straight
	HandType.FLUSH: 100,            # Flush
	HandType.FULL_HOUSE: 150,       # Full House
	HandType.FOUR_OF_A_KIND: 200,   # Four of a Kind
	HandType.STRAIGHT_FLUSH: 300,   # Straight Flush (non‑royal)
	HandType.ROYAL_FLUSH: 500       # Royal Flush
}

## Evaluates a 5‑card hand and returns hand type, score, and matching cards
func evaluate_hand(cards: Array[Card]) -> Dictionary:
	if cards.is_empty():
		return {
			"type": HandType.HIGH_CARD,
			"score": 0,
			"name": "No Cards",
			"matching_cards": []
		}
	
	# Count values and suits
	var value_counts := {}
	var suit_counts := {}
	var cards_by_value := {}  # value -> Array[Card]
	var cards_by_suit := {}  # suit -> Array[Card]
	
	for card in cards:
		if card == null:
			continue
		value_counts[card.value] = value_counts.get(card.value, 0) + 1
		suit_counts[card.suit] = suit_counts.get(card.suit, 0) + 1
		
		if not cards_by_value.has(card.value):
			cards_by_value[card.value] = []
		cards_by_value[card.value].append(card)
		
		if not cards_by_suit.has(card.suit):
			cards_by_suit[card.suit] = []
		cards_by_suit[card.suit].append(card)
	
	var values := value_counts.keys()
	values.sort()
	
	# Track highest multiplicity for pairs/sets
	var max_count := 0
	var max_value := 0
	for value in value_counts.keys():
		var count = value_counts[value]
		if count > max_count:
			max_count = count
			max_value = value
	
	# Detect full house and pair/three info up‑front
	var has_three := false
	var has_pair := false
	var three_value := 0
	var pair_values: Array[int] = []
	for value in value_counts.keys():
		var count = value_counts[value]
		if count == 3:
			has_three = true
			three_value = value
		elif count == 2:
			has_pair = true
			pair_values.append(value)
	
	# Check for flush (5 cards same suit)
	var flush_suit := ""
	for suit in suit_counts.keys():
		if suit_counts[suit] >= 5:
			flush_suit = suit
			break
	
	# Check for straight (including A‑low and A‑high)
	var straight_start := -1
	var has_ace := values.has(1)
	if values.size() >= 5:
		# Standard consecutive check (2-3-4-5-6, 3-4-5-6-7, etc.)
		for i in range(values.size() - 4):
			var consecutive := true
			for j in range(1, 5):
				if values[i + j] != values[i] + j:
					consecutive = false
					break
			if consecutive:
				straight_start = values[i]
				break
		
		# Ace-low straight: A-2-3-4-5 (values 1, 2, 3, 4, 5)
		if has_ace and values.has(2) and values.has(3) and values.has(4) and values.has(5):
			straight_start = 1  # Ace-low straight
		
		# Ace-high straight: 10-J-Q-K-A (values 10, 11, 12, 13, 1)
		if has_ace and values.has(10) and values.has(11) and values.has(12) and values.has(13):
			if straight_start < 10:  # Only use Ace-high if no other straight found
				straight_start = 10  # Ace-high straight (Royal Flush when same suit)
	
	# Determine straight / flush / straight flush / royal flush
	var is_straight := straight_start >= 0
	var is_flush := flush_suit != ""
	var is_straight_flush := false
	var is_royal := false
	var straight_matching: Array[Card] = []
	
	if is_straight and is_flush:
		# Collect cards that are part of the straight flush
		for card in cards:
			if card != null and card.suit == flush_suit:
				var in_straight := false
				if straight_start == 1:  # Ace-low straight
					in_straight = card.value >= 1 and card.value <= 5
				elif straight_start == 10:  # Ace-high straight (Royal Flush)
					in_straight = (card.value >= 10 and card.value <= 13) or card.value == 1
				else:  # Standard straight
					in_straight = card.value >= straight_start and card.value <= straight_start + 4
				
				if in_straight:
					straight_matching.append(card)
		
		if straight_matching.size() == 5:
			is_straight_flush = true
			# Royal flush: Ace-high straight flush (10-J-Q-K-A of same suit)
			if straight_start == 10:
				is_royal = true
	
	# Royal Flush
	if is_straight_flush and is_royal:
		return {
			"type": HandType.ROYAL_FLUSH,
			"score": BASE_SCORES[HandType.ROYAL_FLUSH],
			"name": HAND_NAMES[HandType.ROYAL_FLUSH],
			"matching_cards": straight_matching
		}
	
	# Straight Flush (non‑royal)
	if is_straight_flush:
		return {
			"type": HandType.STRAIGHT_FLUSH,
			"score": BASE_SCORES[HandType.STRAIGHT_FLUSH],
			"name": HAND_NAMES[HandType.STRAIGHT_FLUSH],
			"matching_cards": straight_matching
		}
	
	# Four of a Kind
	if max_count == 4:
		var matching_four = cards_by_value.get(max_value, [])
		return {
			"type": HandType.FOUR_OF_A_KIND,
			"score": BASE_SCORES[HandType.FOUR_OF_A_KIND],
			"name": HAND_NAMES[HandType.FOUR_OF_A_KIND],
			"matching_cards": matching_four
		}
	
	# Full House (three + pair)
	if has_three and has_pair:
		var matching_full: Array[Card] = []
		matching_full.append_array(cards_by_value.get(three_value, []))
		# Use the highest pair value if there are multiple pairs
		pair_values.sort()
		var best_pair_value = pair_values.back()
		matching_full.append_array(cards_by_value.get(best_pair_value, []))
		return {
			"type": HandType.FULL_HOUSE,
			"score": BASE_SCORES[HandType.FULL_HOUSE],
			"name": HAND_NAMES[HandType.FULL_HOUSE],
			"matching_cards": matching_full
		}
	
	# Flush
	if is_flush:
		return {
			"type": HandType.FLUSH,
			"score": BASE_SCORES[HandType.FLUSH],
			"name": HAND_NAMES[HandType.FLUSH],
			"matching_cards": cards_by_suit.get(flush_suit, [])
		}
	
	# Straight
	if is_straight:
		var matching_straight: Array[Card] = []
		for card in cards:
			if card != null:
				var in_straight := false
				if straight_start == 1:  # Ace-low straight
					in_straight = card.value >= 1 and card.value <= 5
				elif straight_start == 10:  # Ace-high straight
					in_straight = (card.value >= 10 and card.value <= 13) or card.value == 1
				else:  # Standard straight
					in_straight = card.value >= straight_start and card.value <= straight_start + 4
				
				if in_straight:
					matching_straight.append(card)
		return {
			"type": HandType.STRAIGHT,
			"score": BASE_SCORES[HandType.STRAIGHT],
			"name": HAND_NAMES[HandType.STRAIGHT],
			"matching_cards": matching_straight
		}
	
	# Three of a Kind
	if max_count == 3:
		var matching_three = cards_by_value.get(max_value, [])
		return {
			"type": HandType.THREE_OF_A_KIND,
			"score": BASE_SCORES[HandType.THREE_OF_A_KIND],
			"name": HAND_NAMES[HandType.THREE_OF_A_KIND],
			"matching_cards": matching_three
		}
	
	# Two Pair
	if pair_values.size() >= 2:
		pair_values.sort()
		var best_two: Array[int] = pair_values.slice(pair_values.size() - 2, pair_values.size())
		var matching_two_pair: Array[Card] = []
		for value in best_two:
			matching_two_pair.append_array(cards_by_value.get(value, []))
		return {
			"type": HandType.TWO_PAIR,
			"score": BASE_SCORES[HandType.TWO_PAIR],
			"name": HAND_NAMES[HandType.TWO_PAIR],
			"matching_cards": matching_two_pair
		}
	
	# One Pair
	if pair_values.size() == 1:
		var matching_pair = cards_by_value.get(pair_values[0], [])
		return {
			"type": HandType.PAIR,
			"score": BASE_SCORES[HandType.PAIR],
			"name": HAND_NAMES[HandType.PAIR],
			"matching_cards": matching_pair
		}
	
	# High card – no scoring combo
	return {
		"type": HandType.HIGH_CARD,
		"score": BASE_SCORES[HandType.HIGH_CARD],
		"name": HAND_NAMES[HandType.HIGH_CARD],
		"matching_cards": cards
	}
