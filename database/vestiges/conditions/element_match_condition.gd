@tool
class_name ElementMatchCondition
extends VestigeCondition
## Condition that triggers only with specific elements

@export var required_element: GlobalBattleSettings.Elements = GlobalBattleSettings.Elements.NONE
@export var check_card_element: bool = true  # If true, check card element; if false, check attacker element


func should_trigger(vestige: Vestige, battler: Battler, context: Dictionary) -> bool:
	if required_element == GlobalBattleSettings.Elements.NONE:
		return true  # No element restriction
	
	var element_to_check: int = GlobalBattleSettings.Elements.NONE
	
	# Check context for element information
	if check_card_element and context.has("card"):
		var card = context["card"]
		if card and card.has_property("element"):
			element_to_check = card.element
	elif context.has("element"):
		element_to_check = context["element"]
	elif battler and battler.stats and battler.stats.has_property("element"):
		element_to_check = battler.stats.element
	
	return element_to_check == required_element
