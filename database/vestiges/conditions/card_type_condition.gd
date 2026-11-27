class_name CardTypeCondition
extends VestigeCondition
## Passes when the played card ("card" in the context) has the required tags.

## Card tags to look for; empty = any card.
@export var required_tags: Array[String] = []
## All tags must be present (otherwise any one is enough).
@export var require_all_tags: bool = false


func should_trigger(_vestige: Vestige, _battler: Battler, context: Dictionary) -> bool:
	if required_tags.is_empty():
		return true
	var card = context.get("card")
	if card == null or not "card_tags" in card:
		return false
	var card_tags: Array = card.card_tags
	if require_all_tags:
		return required_tags.all(func(tag): return tag in card_tags)
	return required_tags.any(func(tag): return tag in card_tags)
