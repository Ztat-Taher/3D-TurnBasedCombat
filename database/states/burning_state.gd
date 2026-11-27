## BurningState
## Stacking damage over time: each turn start it deals 5 per stack (defense
## doesn't reduce it), then a stack burns out. It lasts until the last one
## does: more stacks burn longer and harder. Each application adds stacks.

class_name BurningState
extends State

@export var base_damage_per_stack: int = 5  ## Damage per stack per turn

func _init():
	state_name = "Burning"
	state_type = StateType.DOT
	state_description = "Takes fire damage each turn. Damage increases with more stacks."
	icon_texture = preload("res://assets/images/ui/status_effects/burning.png")
	stack_max = 10  # Maximum stacks
	stack_count = 1  # A plain application adds 1 stack
	turns_active = -1  # Lasts until its stacks burn out

func get_turn_damage(_owner: Node) -> int:
	return base_damage_per_stack * stack_count

## A stack burns out each turn.
func on_turn_tick(_owner: Node) -> void:
	remove_stacks(1)

func is_expired() -> bool:
	return stack_count <= 0
