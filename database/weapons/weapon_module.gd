class_name WeaponModule
extends Resource
## Base class for composable weapon mechanics. A [Weapon] carries an array of
## these instead of mechanic-specific fields, so new behaviors are added as new
## module subclasses — no changes to Weapon, WeaponSystem, or the combat
## pipelines.
##
## Modules are data: they live on the weapon .tres and describe configuration.
## At battle time [method create_runtime] produces an optional Node child under
## the battler's [WeaponSystem] that runs the mechanic (e.g. OrbSystem,
## HitEcho).


## Creates the runtime node for this module, or null if the module is
## data-only. Called by [WeaponSystem] during setup; the returned node is
## added as a child of the weapon system before its _ready runs.
func create_runtime(_weapon_system: WeaponSystem) -> Node:
	return null


## Damage-dealt multiplier contributed by this module (default: none).
## [WeaponSystem.get_damage_dealt_multiplier] multiplies the weapon's base
## multiplier by every module's contribution.
func get_damage_dealt_multiplier(_weapon: Weapon) -> float:
	return 1.0
