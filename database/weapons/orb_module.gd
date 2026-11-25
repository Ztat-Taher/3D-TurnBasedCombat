class_name OrbModule
extends WeaponModule
## Orbiting-orb weapon mechanic. Holds the orb roster; at battle time spawns
## an [OrbSystem] node that cycles the Attuned orb on each landed hostile hit,
## detonates it, and drives the weapon visual's orb rig.

## Orb roster. The Attuned orb (cycle index) detonates on each landed hit,
## then the circuit advances and the next orb is empowered by Overcharge.
@export var orbs: Array[OrbDefinition] = []


func create_runtime(weapon_system: WeaponSystem) -> Node:
	var sys := OrbSystem.new()
	sys.name = "OrbSystem"
	sys.setup(weapon_system, self)
	return sys
