## ProtectedState
## Each shield hit blocks one whole hit (damage and on-hit effects); the last
## one ends the state. Shielding a shielded battler adds the hits. Its hits
## show as the battler's shield row, not a status icon.

class_name ProtectedState
extends State

@export var shield_hits: int = 1  ## Hits it blocks

func _init():
	state_name = "Protected"
	state_type = StateType.BUFF
	state_description = "Ignores the next hit (damage and effects)"
	turns_active = -1  # Persists until its hits are used or cured

func set_shield_hits(amount: int) -> void:
	shield_hits = amount

func get_shield_hits() -> int:
	return shield_hits

func blocks_hit(owner: Node, _hit: Dictionary) -> bool:
	if shield_hits <= 0:
		return false
	shield_hits -= 1
	if owner.number_indicator:
		owner.number_indicator.show_shield_break()
	owner.states_changed.emit()
	if shield_hits <= 0:
		owner.remove_state(state_name)
	return true

func merge(incoming: State, owner: Node) -> void:
	super(incoming, owner)
	if incoming is ProtectedState:
		shield_hits += incoming.shield_hits
