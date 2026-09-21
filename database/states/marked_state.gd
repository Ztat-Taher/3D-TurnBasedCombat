## MarkedState
## Next attack against this target deals bonus damage, then state removes
## Execution setup effect

class_name MarkedState
extends State

@export var remove_after_hit: bool = true  # Remove state after first hit
@export var can_stack: bool = true  # Allow multiple marks for bigger bonus

func _init():
	state_name = "Marked"
	state_type = StateType.DEBUFF
	state_description = "Next attack deals bonus damage"
	marked_damage_bonus = 1.5  # 50% bonus damage
	turns_active = 3  # Lasts 3 turns if not hit
	can_be_cured = true
	remove_after_hit = true
	can_stack = true

## Calculate the bonus damage multiplier
func get_damage_multiplier() -> float:
	return marked_damage_bonus

## Check if state should be removed after hit
func should_remove_after_hit() -> bool:
	return remove_after_hit

## Apply additional mark (stacking)
func add_mark(bonus_increase: float = 0.5) -> void:
	if can_stack:
		marked_damage_bonus += bonus_increase