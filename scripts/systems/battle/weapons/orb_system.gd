class_name OrbSystem
extends Node
## Runtime for an [OrbModule]: cycles the Attuned orb on each landed hostile
## hit, detonates it (damage + state + attuned effect), empowers the next orb
## with Overcharge, and drives the weapon visual's orb rig. Spawned by
## [OrbModule.create_runtime] as a child of [WeaponSystem].

## The weapon system this orb circuit belongs to.
var weapon_system: WeaponSystem = null
## The orb roster + configuration.
var module: OrbModule = null

var _orb_index: int = 0       ## index of the currently Attuned orb
## True while the Overcharge chain is live: the last detonation procced, so
## the next one is empowered. A failed proc breaks the chain.
var _overcharge_next: bool = false


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


## True when the next detonation is overcharged.
func is_overcharged() -> bool:
	return _overcharge_next


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
	# A target the hit just defeated keeps the circuit where it is
	if module == null or module.orbs.is_empty() or target == null or target.is_defeated():
		return
	var idx := _orb_index % module.orbs.size()
	var orb := module.orbs[idx]
	# Overcharge scales what the detonation does (damage, state stacks), never
	# its chance to happen
	var mult := orb.overcharge_multiplier if _overcharge_next else 1.0
	var owner: Battler = weapon_system.owner_battler
	var battle_manager: Node = weapon_system.get_battle_manager()

	var procced := randf() <= orb.chance
	if procced:
		# Final bonus damage (no stat formula); rounded once, at the end.
		var dmg := float(orb.damage)
		if orb.damage_is_attack_percent and owner:
			dmg = owner.attack * orb.damage / 100.0
		dmg *= mult
		if dmg > 0.0 and battle_manager:
			battle_manager.damage_calculation(owner, target, dmg, null, "magic", orb.element, false)
		if orb.state:
			# Overcharge scales the stacks of a stacking state
			var stacks := -1
			if orb.state.uses_stacks():
				stacks = orb.stack_count if orb.stack_count > 0 else orb.state.stack_count
				stacks = maxi(roundi(stacks * mult), 1)
			target.apply_state(orb.state.make_instance(0, stacks), owner)
	# A successful detonation empowers the next orb; a failed one breaks the chain
	_overcharge_next = procced

	# Attuned passive fires on every hit while this orb is active.
	if orb.attuned_effect:
		weapon_system.run_effect(orb.attuned_effect, target, context)

	_orb_index += 1
	var new_idx := _orb_index % module.orbs.size()
	var visual := weapon_system.weapon_visual
	if visual and visual.has_method("set_attuned_orb"):
		visual.set_attuned_orb(new_idx)
	if visual and visual.has_method("play_detonation"):
		visual.play_detonation(idx, target.global_position)
