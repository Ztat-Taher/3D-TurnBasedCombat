class_name WeaponSystem
extends Node3D
## Runtime for a battler's equipped [Weapon]. Spawned as a child of the
## [Battler] when [member battler.weapon] is set.
##
## Visual resolution has two paths:
## - **Socketed** (handheld models, e.g. BLADE): when the battler defines
##   [member Battler.weapon_socket_path], the weapon's [member Weapon.model_scene]
##   is instanced as a child named `"Weapon"` under that socket — spawning at
##   the socket's origin like a normal instantiation. The `"Weapon"` name
##   convention preserves baked animation-track paths such as
##   `.../WeaponAttachement/Weapon/WeaponTrail`.
## - **Root-space** (ORB weapons): the model scene is reused from the battler's
##   scene when present (e.g. ally2's baked PrismOrbWeapon) or instanced under
##   this node.
##
## Mechanics are composed via [Weapon.modules]: each [WeaponModule] spawns its
## own runtime child (OrbSystem, HitEcho, ...) — this script only handles the
## weapon's intrinsic data (model, stats, generic effects, procs) and stays
## mechanic-agnostic.

## Weapon being used. Set via [method setup] before add_child().
var weapon: Weapon = null
## The battler owning this weapon.
var owner_battler: Battler = null
## Instantiated model scene (weapon.model_scene), if any.
var weapon_visual: Node = null

var _stacks: Dictionary = {}  ## stack_id -> count (weapon-internal)
var _battle_manager: Node = null
var _orb_system: OrbSystem = null


func setup(p_weapon: Weapon, p_owner: Battler) -> void:
	weapon = p_weapon
	owner_battler = p_owner


func _ready() -> void:
	if weapon == null or owner_battler == null:
		push_warning("WeaponSystem on '%s' missing weapon or owner." % name)
		return
	_battle_manager = get_tree().get_first_node_in_group("battle_manager")
	# Resolve the weapon's model scene. Socketed (handheld) weapons instance
	# into the battler's authored socket; root-space weapons (ORB rigs) reuse
	# a scene-baked visual or instance under this node.
	if weapon.model_scene and _has_socket():
		weapon_visual = _instance_model_into_socket()
	elif weapon.model_scene:
		var existing := _find_scene_visual()
		if existing and existing.scene_file_path == weapon.model_scene.resource_path:
			weapon_visual = existing
		else:
			if existing:
				existing.queue_free()
			weapon_visual = weapon.model_scene.instantiate()
			add_child(weapon_visual)
	else:
		var existing := _find_scene_visual()
		if existing:
			weapon_visual = existing
	if weapon_visual:
		_wire_trail_fallback(weapon_visual)
	# Apply the weapon's stat modifiers to the battler.
	owner_battler.apply_weapon_stat_modifiers(weapon)
	if owner_battler.has_signal("hit_moment"):
		owner_battler.hit_moment.connect(_on_hit_moment)
	# Composed mechanics: each WeaponModule spawns its own runtime child
	# (OrbSystem, HitEcho, ...). New mechanics are new module subclasses —
	# no edits here or in the card/battle pipelines.
	for mod in weapon.modules:
		if mod == null:
			continue
		var runtime := mod.create_runtime(self)
		if runtime:
			add_child(runtime)
			if runtime is OrbSystem:
				_orb_system = runtime
	_run_trigger(WeaponEffect.Trigger.ON_BATTLE_START, owner_battler, {})


func _exit_tree() -> void:
	if owner_battler and is_instance_valid(owner_battler):
		_run_trigger(WeaponEffect.Trigger.ON_BATTLE_END, owner_battler, {})


## Called by the battler's hit_moment signal (emitted at the hit frame of any
## attack animation). [param attacker] is the battler itself.
func _on_hit_moment(attacker: Battler) -> void:
	if attacker != owner_battler:
		return
	var target: Battler = owner_battler.current_target
	if target == null or target == owner_battler or not is_instance_valid(target):
		return
	var context := {"slot": owner_battler._last_combat_slot}
	notify_attack_hit(target, context)


## A hit landed. [param context] may carry "slot" (the canonical animation
## slot, e.g. "ranged_cast_1") for weapons that care about melee vs ranged.
func notify_attack_hit(target: Battler, context: Dictionary = {}, is_replay: bool = false) -> void:
	if weapon == null:
		return
	# Weapons are hostile tools: never proc on allies (shield/buff cards,
	# self-targets, etc.). This is the single gate for ALL weapon procs.
	if owner_battler == null or target == null or target.team == owner_battler.team:
		return
	if not is_replay:
		weapon.add_weapon_xp(1)
	# Composed mechanics hook the same hit: an OrbModule's OrbSystem detonates
	# the Attuned orb; other modules listen via their own runtime nodes.
	if _orb_system:
		_orb_system.detonate(target, context)
	_run_trigger(WeaponEffect.Trigger.ON_ATTACK_HIT, target, context)


## The owner played a card (wired from the card battle manager).
func notify_card_play(_card) -> void:
	_run_trigger(WeaponEffect.Trigger.ON_CARD_PLAY, owner_battler, {})


## The owner took damage.
func notify_damage_taken(attacker: Battler, _damage: int) -> void:
	_run_trigger(WeaponEffect.Trigger.ON_DAMAGE_TAKEN, owner_battler, {"attacker": attacker})


func get_weapon() -> Weapon:
	return weapon


## Finds an [OrbWeaponVisual] already present anywhere in the battler's scene
## (authored as a nested node — e.g. under a BoneAttachment — so it can be
## edited in the editor).
func _find_scene_visual() -> OrbWeaponVisual:
	if owner_battler == null:
		return null
	for c in owner_battler.find_children("*", "", true, false):
		if c is OrbWeaponVisual:
			return c
	return null


# ---------------------------------------------------------------------------
# Socketed weapon models
# ---------------------------------------------------------------------------

## True when the battler defines a weapon socket that resolves in the tree.
func _has_socket() -> bool:
	if owner_battler == null or owner_battler.weapon_socket_path == NodePath(""):
		return false
	return owner_battler.get_node_or_null(owner_battler.weapon_socket_path) != null


## Instances [member Weapon.model_scene] as a child named `"Weapon"` under the
## battler's [member Battler.weapon_socket_path] node, replacing any existing
## `"Weapon"` child (placeholder or previous weapon). When the socket contains
## a `"WeaponSocket"` marker child, the instance copies that marker's transform
## (authored palm placement) while staying a sibling of it. The `"Weapon"`
## name preserves baked animation-track paths like
## `.../WeaponAttachement/Weapon/WeaponTrail`.
func _instance_model_into_socket() -> Node:
	var socket := owner_battler.get_node_or_null(owner_battler.weapon_socket_path)
	if socket == null:
		push_warning("WeaponSystem: weapon_socket_path '%s' did not resolve on '%s'." % [owner_battler.weapon_socket_path, owner_battler.name])
		return null
	var existing := socket.get_node_or_null("Weapon")
	if existing is Node and existing.scene_file_path == weapon.model_scene.resource_path:
		return existing
	if existing:
		# Detach immediately so the "Weapon" name is free for the instance
		# (queue_free alone would defer removal past this frame).
		socket.remove_child(existing)
		existing.queue_free()
	var instance := weapon.model_scene.instantiate()
	instance.name = "Weapon"
	socket.add_child(instance)
	# Authored grip offset: a "WeaponSocket" marker child of the socket carries
	# the tuned palm transform. The weapon is instanced as the marker's
	# sibling and copies its exact transform, preserving the "Weapon" node
	# path (and baked animation tracks) while landing in the right spot.
	var marker := socket.get_node_or_null("WeaponSocket") as Node3D
	if marker and instance is Node3D:
		(instance as Node3D).transform = marker.transform
	return instance


## WeaponTrail nodes driven by baked AnimationPlayer method tracks are left
## alone; trails at any other path get wired to the battler's attack_start /
## attack_end signals so they emit for the whole swing.
func _wire_trail_fallback(visual: Node) -> void:
	if visual == null or owner_battler == null:
		return
	var anim_player := owner_battler.find_children("*", "AnimationPlayer", true, false)
	var track_paths := {}
	if not anim_player.is_empty():
		var ap: AnimationPlayer = anim_player[0]
		for anim_name in ap.get_animation_list():
			var anim := ap.get_animation(anim_name)
			if anim == null:
				continue
			for i in anim.get_track_count():
				if anim.track_get_type(i) == Animation.TYPE_METHOD:
					track_paths[str(anim.track_get_path(i))] = true
	for trail in visual.find_children("*", "", true, false):
		if not (trail is WeaponTrail):
			continue
		# Path of the trail relative to the battler root, matching how
		# animation track paths are written (e.g. "Armature/.../WeaponTrail").
		var rel := str(trail.get_path()).trim_prefix(str(owner_battler.get_path()) + "/")
		if track_paths.has(rel):
			continue  # animation-driven
		if not owner_battler.attack_start.is_connected(trail._on_trail_start):
			owner_battler.attack_start.connect(trail._on_trail_start)
		if not owner_battler.attack_end.is_connected(trail._on_trail_end):
			owner_battler.attack_end.connect(trail._on_trail_end)


## Total damage-dealt multiplier: the weapon's base multiplier times every
## module's contribution (e.g. HitEchoModule splits each damage instance so
## original and ghost replay each deal its fraction).
func get_damage_dealt_multiplier() -> float:
	if weapon == null:
		return 1.0
	var m := weapon.damage_dealt_multiplier
	for mod in weapon.modules:
		if mod:
			m *= mod.get_damage_dealt_multiplier(weapon)
	return m


## The battle manager node (group lookup), exposed for module runtimes.
func get_battle_manager() -> Node:
	return _battle_manager


## Public passthroughs so module runtimes (OrbSystem etc.) can evaluate the
## weapon's generic effects without duplicating the logic.
func run_effect(fx: WeaponEffect, target: Battler, context: Dictionary) -> void:
	_execute_effect(fx, target, context)


func effect_amount(fx: WeaponEffect, recipient: Battler) -> float:
	return _effect_amount(fx, recipient)


func make_state(base: State, stack_count: int, accumulation: int) -> State:
	return _state_for(base, stack_count, accumulation)


func get_damage_taken_multiplier() -> float:
	return weapon.damage_taken_multiplier if weapon else 1.0


func get_weapon_stack(stack_id: StringName) -> int:
	return int(_stacks.get(stack_id, 0))


# ---------------------------------------------------------------------------
# Effect evaluation
# ---------------------------------------------------------------------------

func _run_trigger(trigger: WeaponEffect.Trigger, target: Battler, context: Dictionary) -> void:
	if weapon == null:
		return
	for fx in weapon.effects:
		if fx and fx.trigger == trigger:
			_execute_effect(fx, target, context)
	# ORB weapons may also carry per-orb attuned effects handled in detonation.


func _execute_effect(fx: WeaponEffect, target: Battler, context: Dictionary) -> void:
	if fx == null or randf() > fx.chance:
		return
	if fx.requires_stacks > 0 and get_weapon_stack(fx.stack_id) < fx.requires_stacks:
		return
	var recipient: Battler = owner_battler if fx.scope_self else target
	match fx.kind:
		WeaponEffect.Kind.DAMAGE:
			var amount := _effect_amount(fx, recipient)
			if amount > 0 and recipient and _battle_manager:
				_battle_manager.damage_calculation(owner_battler, recipient, amount, null, "physical", "none")
		WeaponEffect.Kind.APPLY_STATE:
			if fx.state and recipient:
				recipient.apply_state(_state_for(fx.state, fx.state_stack_count, fx.state_accumulation))
		WeaponEffect.Kind.HEAL:
			var amount := _effect_amount(fx, recipient)
			if amount > 0 and recipient:
				recipient.take_healing(int(amount))
		WeaponEffect.Kind.GAIN_STACK:
			if fx.stack_id != &"":
				var cur := get_weapon_stack(fx.stack_id) + fx.stacks_per_trigger
				if fx.max_stacks > 0:
					cur = mini(cur, fx.max_stacks)
				_stacks[fx.stack_id] = cur
		WeaponEffect.Kind.CONSUME_STACKS:
			var consumed := get_weapon_stack(fx.stack_id)
			if consumed <= 0 or fx.stack_id == &"":
				return
			_stacks.erase(fx.stack_id)
			var amount := _effect_amount(fx, recipient) * consumed
			if amount > 0 and recipient and _battle_manager:
				_battle_manager.damage_calculation(owner_battler, recipient, int(amount), null, "physical", "none")
			if fx.state and recipient:
				recipient.apply_state(_state_for(fx.state, fx.state_stack_count, fx.state_accumulation))


## Resolves an effect's numeric value: flat, or percent of the owner's attack
## when [member WeaponEffect.value_is_attack_percent]. DAMAGE effects may also
## scale by a weapon stack via [member WeaponEffect.scale_with_stack].
func _effect_amount(fx: WeaponEffect, _recipient: Battler) -> float:
	var amount := fx.value
	if fx.value_is_attack_percent and owner_battler:
		amount = owner_battler.attack * fx.value / 100.0
	if fx.scale_with_stack != &"":
		amount *= float(get_weapon_stack(fx.scale_with_stack))
	return amount


func _state_for(base: State, stack_count: int, accumulation: int) -> State:
	var dup := base.duplicate() as State
	if dup == null:
		return base
	if stack_count > 0 and "stack_count" in dup:
		dup.stack_count = stack_count
	if accumulation > 0 and "accumulation_value" in dup:
		dup.accumulation_value = accumulation
	return dup


