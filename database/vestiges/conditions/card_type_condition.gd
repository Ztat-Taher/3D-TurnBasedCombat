@tool
class_name CardTypeCondition
extends VestigeCondition
## Condition that triggers only for specific card types

@export var required_tags: Array[String] = []  # Card tags to match
@export var require_all_tags: bool = false  # If true, all tags must match; if false, any tag can match


func should_trigger(vestige: Vestige, battler: Battler, context: Dictionary) -> bool:
	if required_tags.is_empty():
		return true  # No tag restriction
	
	if not context.has("card"):
		return false
	
	var card = context["card"]
	if card == null:
		return false
	
	if not card.has_property("card_tags"):
		return false
	
	var card_tags: Array[String] = card.card_tags
	
	if require_all_tags:
		# All required tags must be present
		for tag in required_tags:
			if not tag in card_tags:
				return false
		return true
	else:
		# Any required tag can match
		for tag in required_tags:
			if tag in card_tags:
				return true
		return false
