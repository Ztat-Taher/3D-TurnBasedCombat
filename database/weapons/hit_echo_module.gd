class_name HitEchoModule
extends WeaponModule
## Hit-echo weapon mechanic: every landed hostile hit is replayed after a
## delay — a ghost blade traces the recorded swing trajectory and the hit's
## card resolution re-runs through the real combat pipeline (damage, states,
## weapon procs, projectile visuals). The live hit and each ghost replay deal
## [member echo_damage_fraction] of the damage.
##
## Presence of this module IS the opt-in — there is no enable flag.

## Seconds between the original hit and the ghost replica.
@export var echo_delay: float = 0.35
## Fraction of damage dealt by EACH instance of the hit — the live hit and
## every ghost replay (e.g. 0.3333 => each deals 1/3, 2/3 total).
@export var echo_damage_fraction: float = 0.3333


func create_runtime(weapon_system: WeaponSystem) -> Node:
	var echo := HitEcho.new()
	echo.name = "HitEcho"
	echo.setup(weapon_system.weapon, weapon_system.owner_battler, weapon_system, self)
	return echo


func get_damage_dealt_multiplier(_weapon: Weapon) -> float:
	return echo_damage_fraction
