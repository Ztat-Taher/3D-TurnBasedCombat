class_name DrawCardsOnTrigger
extends VestigeEffect
## Draws extra cards into the battler's hand during its turn (e.g. on card
## play or when hit). For extra cards every turn, use the vestige's
## cards_drawn_per_turn instead: a turn-start draw is replaced by the fresh hand.

@export var cards_to_draw: int = 1


func execute(_vestige: Vestige, battler: Battler, _context: Dictionary) -> bool:
	if battler == null or not battler.is_inside_tree():
		return false
	var card_manager = battler.get_tree().get_first_node_in_group("card_battle_manager")
	if card_manager == null:
		return false
	return card_manager.draw_cards(battler, cards_to_draw) > 0
