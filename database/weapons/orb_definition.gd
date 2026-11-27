class_name OrbDefinition
extends Resource
## One orb inside an ORB weapon's cycle. The Attuned orb (the one the circuit
## is currently pointing at) detonates on each landed hit — applying its
## state/damage — then the circuit advances. A detonation that procs
## empowers the next one with Overcharge (the next orb's own
## [member overcharge_multiplier]); a failed proc breaks the chain.

@export var orb_name: String = "Orb"
@export var color: Color = Color.WHITE
@export var emission_energy: float = 1.0

@export_group("Detonation")
@export var state: State = null
## Stacks applied to state.stack_count on detonation (0 = leave as authored).
@export var stack_count: int = 0
## Bonus damage dealt exactly (rounded, min 1); not fed through the
## attack/defense formula.
@export var damage: int = 0
@export var damage_is_attack_percent: bool = false  ## damage = owner.attack * damage / 100
@export var chance: float = 1.0
@export var element: String = "none"
## Overcharge potency: scales THIS orb's detonation damage and state stacks
## when the previous detonation procced (never its [member chance]).
## 1.0 = no overcharge.
@export var overcharge_multiplier: float = 1.5

@export_group("Attuned Passive")
## Optional WeaponEffect evaluated on every landed hit while this orb is
## Attuned (in addition to its detonation).
@export var attuned_effect: WeaponEffect = null
