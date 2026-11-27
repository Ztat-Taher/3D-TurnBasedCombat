## MarkedState
## The next attack on its battler deals bonus damage and spends the mark.
## Bonus damage (weapon and orb procs) is neither boosted nor spends it.

class_name MarkedState
extends State

@export_range(1.0, 3.0, 0.1) var marked_damage_bonus: float = 1.5  ## Damage multiplier of the attack that spends the mark
@export var remove_after_hit: bool = true  ## The attack spends the mark (false: it lasts its duration)

func _init():
	state_name = "Marked"
	state_type = StateType.DEBUFF
	state_description = "Next attack deals bonus damage"
	turns_active = 3  # Lasts 3 turns if not hit

## Attacks on a marked battler hit harder.
func modify_damage_taken(damage: int, owner: Node, hit: Dictionary) -> int:
	if hit.get("is_attack", false):
		damage = int(damage * marked_damage_bonus)
	return super(damage, owner, hit)

## The mark is spent by the attack that lands on it.
func on_hit_taken(owner: Node, hit: Dictionary) -> void:
	await super(owner, hit)
	if hit.get("is_attack", false) and remove_after_hit:
		owner.remove_state(state_name)
