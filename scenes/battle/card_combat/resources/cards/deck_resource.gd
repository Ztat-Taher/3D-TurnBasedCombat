class_name DeckResource
extends Resource
## Resource for defining a deck of cards

@export var deck_name: String = "Default Deck"
@export var cards: Array[CardData] = []

## Add a card to the deck
func add_card(card: CardData):
	if card:
		cards.append(card)

## Remove a card from the deck
func remove_card(card: CardData):
	cards.erase(card)

## Get card count
func get_card_count() -> int:
	return cards.size()

## Clear the deck
func clear_deck():
	cards.clear()
