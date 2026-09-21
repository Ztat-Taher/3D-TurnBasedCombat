## BerserkState
## Risk/reward effect - deals more damage but takes more damage
## High damage output at the cost of vulnerability

class_name BerserkState
extends State

func _init():
	state_name = "Berserk"
	state_type = StateType.BUFF  # Net positive but with tradeoff
	state_description = "Deals 50% more damage but takes 25% more damage"
	damage_dealt_multiplier = 1.5  # Deal 50% more damage
	damage_taken_multiplier = 1.25  # Take 25% more damage
	turns_active = 2  # Lasts 2 turns by default
	can_be_cured = true