class_name OrbSystem
extends Node
## Runtime for an [OrbModule]: cycles the Attuned orb on each landed hostile
## hit, detonates it (damage + state + attuned effect), empowers the next orb
## with Overcharge, and drives the weapon visual's orb rig. Spawned by
## [OrbModule.create_runtime] as a child of [WeaponSystem].

signal orb_detonated(index: int, orb: OrbDefinition, target_pos: Vector3)
signal orb_attuned_changed(index: int)

## The weapon system this orb circuit belongs to.
var weapon_system: WeaponSystem = null
## The orb roster + configuration.
var module: OrbModule = null

var _orb_index: int = 0       ## index of the currently Attuned orb
var _overcharge_next: bool = false  ## next orb detonation gets overcharge_mult


func setup(p_weapon_system: WeaponSystem, p_module: OrbModule) -> void:
	weapon_system = p_weapon_system
	module = p_module


func _ready() -> void:
	if weapon_system == null or module == null:
		push_warning("OrbSystem on '%s' missing weapon system or module." % name)
		return
	var visual := weapon_system.weapon_visual
	if visual and visual.has_method("setup_orbs"):
		visual.setup_orbs(module.orbs)
	if visual and visual.has_method("set_attuned_orb"):
		visual.set_attuned_orb(_orb_index % maxi(module.orbs.size(), 1))


## Index of the currently Attuned orb (for echo nodes / debugging).
func attuned_index() -> int:
	return _orb_index % maxi(module.orbs.size() if module else 1, 1)


## The scene node for the currently Attuned orb ("OrbN" under the visual),
## used by hit-echo recording.
func echo_node() -> Node3D:
	var visual := weapon_system.weapon_visual if weapon_system else null
	if visual == null or not is_instance_valid(visual) or module == null:
		return null
	var count := maxi(module.orbs.size(), 1)
	var orb_node := visual.get_node_or_null("Orb%d" % (_orb_index % count))
	return orb_node as Node3D


## Called by [WeaponSystem.notify_attack_hit] on each landed hostile hit.
func detonate(target: Battler, context: Dictionary) -> void:
	if module == null or module.orbs.is_empty() or target == null:
		return
	var idx := _orb_index % module.orbs.size()
	var orb := module.orbs[idx]
	var mult := orb.overcharge_multiplier if _overcharge_next else 1.0
	_overcharge_next = false
	var owner: Battler = weapon_system.owner_battler
	var battle_manager: Node = weapon_system.get_battle_manager()

	if randf() <= orb.chance * mult:
		var dmg := orb.damage
		if orb.damage_is_attack_percent and owner:
			dmg = int(owner.attack * orb.damage / 100.0)
		dmg = int(dmg * mult)
		if dmg > 0 and battle_manager:
			battle_manager.damage_calculation(owner, target, dmg, null, "magic", orb.element)
		if orb.state:
			target.apply_state(weapon_system.make_state(orb.state, orb.stack_count, 0))

	# Attuned passive fires on every hit while this orb is active.
	if orb.attuned_effect:
		weapon_system.run_effect(orb.attuned_effect, target, context)

	_orb_index += 1
	_overcharge_next = true
	var new_idx := _orb_index % module.orbs.size()
	orb_detonated.emit(idx, orb, target.global_position)
	orb_attuned_changed.emit(new_idx)
	var visual := weapon_system.weapon_visual
	if visual and visual.has_method("set_attuned_orb"):
		visual.set_attuned_orb(new_idx)
	if visual and visual.has_method("play_detonation"):
		visual.play_detonation(idx, target.global_position)
