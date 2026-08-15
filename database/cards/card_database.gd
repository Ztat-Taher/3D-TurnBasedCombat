class_name CardDatabase
extends Resource
## Database for loading card resources
## Loads CardData resources from the cards folder

var cards: Dictionary = {}

func _init():
	load_cards()

func load_cards():
	cards.clear()
	
	var card_dir = "res://database/cards/"
	var dir = DirAccess.open(card_dir)
	if not dir:
		push_error("CardDatabase: Could not open cards directory: " + card_dir)
		return
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var card_path = card_dir + file_name
			var card = load(card_path)
			if card and card is CardData:
				cards[card.card_id] = card
				print("Loaded card: ", card.name)
		file_name = dir.get_next()
	dir.list_dir_end()
	
	print("CardDatabase loaded ", cards.size(), " cards")

func get_card(card_id: String) -> CardData:
	if cards.has(card_id):
		return cards[card_id]
	return null

func get_all_cards() -> Array[CardData]:
	return cards.values()

func get_cards_by_type(card_type: String) -> Array[CardData]:
	var result: Array[CardData] = []
	for card in cards.values():
		if card.metadata.get("card_type", "") == card_type:
			result.append(card)
	return result

func get_random_cards(count: int) -> Array[CardData]:
	var all_cards = get_all_cards()
	all_cards.shuffle()
	
	var result: Array[CardData] = []
	for i in range(min(count, all_cards.size())):
		result.append(all_cards[i])
	return result
