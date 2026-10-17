class_name DeckResource
extends Resource
## Resource for defining a deck of cards

@export var deck_name: String = "Default Deck"
@export var cards: Array[CardConfig] = []

## Add a card to the deck
func add_card(card: CardConfig):
	if card:
		cards.append(card)

## Remove a card from the deck
func remove_card(card: CardConfig):
	cards.erase(card)

## Get card count
func get_card_count() -> int:
	return cards.size()

## Clear the deck
func clear_deck():
	cards.clear()

## Shuffle the deck
func shuffle() -> void:
	for i in range(cards.size() - 1, 0, -1):
		var j: int = randi_range(0, i)
		var tmp: CardConfig = cards[i]
		cards[i] = cards[j]
		cards[j] = tmp
