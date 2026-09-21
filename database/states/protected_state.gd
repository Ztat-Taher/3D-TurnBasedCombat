## ProtectedState
## Hit-based shielding - each shield ignores one hit (damage and effects)
## Shield mechanic that protects the battler

class_name ProtectedState
extends State

@export var shield_hits: int = 1  # Number of hits the shield can absorb

func _init():
	icon_texture = null 
	state_name = "Protected"
	state_type = StateType.BUFF
	state_description = "Ignores the next hit (damage and effects)"
	shield_hits = 1  # Default: 1 shield hit
	turns_active = -1  # Persists until shield breaks or cured
	can_be_cured = true

## Initialize shield with specific number of hits
func set_shield_hits(amount: int) -> void:
	shield_hits = amount

## Check if shield is still active
func has_shield() -> bool:
	return shield_hits > 0

## Consume one shield hit
func consume_shield() -> void:
	if shield_hits > 0:
		shield_hits -= 1

## Get remaining shield hits
func get_remaining_shields() -> int:
	return shield_hits
