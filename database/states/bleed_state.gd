## BleedState
## A hidden bar fills with the damage its battler takes; when full it procs
## for a share of max HP and empties. Each application adds its own bar
## (weapons apply it with some), and a full bar procs at once.

class_name BleedState
extends State

@export var bleed_proc_damage_percent: float = 0.2  ## Proc damage, as a share of max HP
@export var accumulation_per_damage_taken: float = 0.5  ## Share of damage taken that fills the bar

## True while the proc deals its damage (that damage builds no Bleed).
var _procing := false

func _init():
	state_name = "Bleed"
	state_type = StateType.DOT
	state_description = "Accumulates bleed from damage taken. Triggers massive damage when full."
	icon_texture = preload("res://assets/images/ui/status_effects/bleeding.png")
	accumulation_max = 100  # Threshold for bleed proc
	turns_active = -1  # Persists until cured

## Damage taken builds the bar (once per hit); a full bar procs.
func on_hit_taken(owner: Node, hit: Dictionary) -> void:
	await super(owner, hit)
	var damage := int(hit.get("damage", 0))
	if _procing or damage <= 0 or owner.is_defeated():
		return
	add_accumulation(int(damage * accumulation_per_damage_taken))
	owner.states_changed.emit()
	await _proc_if_full(owner)

## Applied with a bar already (a weapon's bleed): it may be full at once.
func on_applied(owner: Node) -> void:
	_proc_if_full(owner)

## Re-applying adds the new application's bar.
func merge(incoming: State, owner: Node) -> void:
	super(incoming, owner)
	if incoming.accumulation_value > 0:
		add_accumulation(incoming.accumulation_value)
		_proc_if_full(owner)

## A full bar procs and empties (the proc's own damage builds no bar).
func _proc_if_full(owner: Node) -> void:
	if _procing or not should_proc() or owner.is_defeated():
		return
	_procing = true
	reset_accumulation()
	owner.states_changed.emit()
	await owner.take_damage(int(owner.max_health * bleed_proc_damage_percent), null)
	_procing = false
