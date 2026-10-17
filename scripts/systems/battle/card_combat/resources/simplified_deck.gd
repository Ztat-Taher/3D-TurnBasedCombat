class_name SimplifiedDeck
extends Resource
## Simplified deck management for card-based combat
## Replaces the addon's CombatDeck with a simpler Resource-based approach

signal card_drawn(card: CardConfig)
signal deck_exhausted

var draw_pile: Array[CardConfig] = []
var hand: Array[CardConfig] = []
var graveyard: Array[CardConfig] = []
var max_hand_size: int = -1  # -1 = unlimited

## Setup the deck with card configurations
func setup(cards: Array[CardConfig], p_max_hand_size: int = -1) -> void:
	max_hand_size = p_max_hand_size
	draw_pile.clear()
	hand.clear()
	graveyard.clear()
	
	for card in cards:
		if card:
			draw_pile.append(card)
	
	shuffle()

## Shuffle the draw pile using Fisher-Yates algorithm
func shuffle() -> void:
	for i in range(draw_pile.size() - 1, 0, -1):
		var j: int = randi_range(0, i)
		var tmp: CardConfig = draw_pile[i]
		draw_pile[i] = draw_pile[j]
		draw_pile[j] = tmp

## Draw initial hand
func draw_initial_hand(count: int = 3) -> void:
	for i in count:
		var card := draw_card()
		if card != null:
			hand.append(card)

## Draw a single card from the pile
func draw_card() -> CardConfig:
	if draw_pile.is_empty():
		deck_exhausted.emit()
		return null
	
	var card: CardConfig = draw_pile.pop_back()
	
	if is_hand_full():
		# Overdraw: discard the card instead of holding it
		graveyard.append(card)
	else:
		hand.append(card)
	
	card_drawn.emit(card)
	return card

## Discard a card from hand to graveyard
func discard_card(card: CardConfig) -> bool:
	if not hand.has(card):
		return false
	
	hand.erase(card)
	graveyard.append(card)
	return true

## Check if hand is at max capacity
func is_hand_full() -> bool:
	return max_hand_size >= 0 and hand.size() >= max_hand_size

## Get current hand
func get_hand() -> Array[CardConfig]:
	return hand

## Recycle graveyard back into draw pile and shuffle
func recycle_graveyard() -> void:
	if draw_pile.is_empty() and not graveyard.is_empty():
		draw_pile.append_array(graveyard)
		graveyard.clear()
		shuffle()

## Clear the deck
func clear() -> void:
	draw_pile.clear()
	hand.clear()
	graveyard.clear()
