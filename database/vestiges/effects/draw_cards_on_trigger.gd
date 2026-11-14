@tool
class_name DrawCardsOnTrigger
extends VestigeEffect
## Draw cards when a specific trigger occurs

@export var cards_to_draw: int = 1
@export var trigger_limit: int = -1  # -1 = unlimited, otherwise max times per combat

var _trigger_count: int = 0


func execute(vestige: Vestige, battler: Battler, context: Dictionary) -> void:
	if trigger_limit > 0 and _trigger_count >= trigger_limit:
		return
	
	if battler == null:
		return
	
	# Trigger card draw through the card system
	# This would need to be integrated with the card battle manager
	_trigger_count += 1
	
	# For now, log the effect
	print("[VESTIGE] %s: Drawing %d cards (trigger count: %d/%d)" % [vestige.vestige_name, cards_to_draw, _trigger_count, trigger_limit])
