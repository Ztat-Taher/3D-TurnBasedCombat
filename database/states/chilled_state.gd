## ChilledState
## Causes the entity to skip their turn in the turn queue (skip_turn).
## Its ice overlay and aura are set on its resource (State visuals).

class_name ChilledState
extends State

func _init():
	state_name = "Chilled"
	state_type = StateType.DEBUFF
	state_description = "Frozen solid - skips their next turn"
	icon_texture = preload("res://assets/images/ui/status_effects/chilled.png")
	skip_turn = true  # Skip turn in the queue
	turns_active = 1  # Lasts 1 turn by default
