## ElectrocutedState
## Makes the entity vulnerable (takes more damage) and weak (deals less damage).
## Its lightning overlay is set on its resource (State visuals).

class_name ElectrocutedState
extends State

func _init():
	state_name = "Electrocuted"
	state_type = StateType.DEBUFF
	state_description = "Takes 50% more damage and deals 50% less damage"
	icon_texture = preload("res://assets/images/ui/status_effects/electrocuted.png")
	damage_taken_multiplier = 1.5  # Take 50% more damage
	damage_dealt_multiplier = 0.5  # Deal 50% less damage
	turns_active = 2  # Lasts 2 turns by default
