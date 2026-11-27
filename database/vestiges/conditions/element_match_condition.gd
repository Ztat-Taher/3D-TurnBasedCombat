class_name ElementMatchCondition
extends VestigeCondition
## Passes when the event's element matches. The element is the context's
## "element" (e.g. the element of damage taken), else the played card's.

## Element name as damage reports it ("fire", "ice", ...); empty/"none" = any.
@export var required_element: String = ""


func should_trigger(_vestige: Vestige, _battler: Battler, context: Dictionary) -> bool:
	var required := required_element.to_lower()
	if required.is_empty() or required == "none":
		return true
	return _event_element(context) == required


static func _event_element(context: Dictionary) -> String:
	if context.has("element"):
		return str(context["element"]).to_lower()
	var card = context.get("card")
	if card and "element" in card:
		return str(card.element).to_lower()
	return "none"
