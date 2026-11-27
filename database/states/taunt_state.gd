## TauntState
## Enemy AI must target its battler (is_taunting). Optionally breaks after
## its battler takes enough attack damage; re-taunting starts the count over.

class_name TauntState
extends State

@export var break_after_damage: int = 0  ## Attack damage taken that breaks the taunt (0 = never)

var damage_taken_while_taunting: int = 0

func _init():
	state_name = "Taunt"
	state_type = StateType.BUFF
	state_description = "Forces enemies to target this battler"
	is_taunting = true
	turns_active = 2  # Lasts 2 turns by default

## Attacks on the taunter count toward breaking the taunt.
func on_hit_taken(owner: Node, hit: Dictionary) -> void:
	await super(owner, hit)
	if not hit.get("is_attack", false) or break_after_damage <= 0:
		return
	damage_taken_while_taunting += int(hit.get("damage", 0))
	if damage_taken_while_taunting >= break_after_damage:
		owner.remove_state(state_name)

func merge(incoming: State, owner: Node) -> void:
	super(incoming, owner)
	damage_taken_while_taunting = 0
