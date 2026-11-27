class_name Battler
extends CharacterBody3D

signal hit_moment(attacker: Battler)
signal attack_start()
signal attack_end()
signal health_changed(current_health: int, max_health: int)
signal ap_changed(current_ap: int, max_ap: int)
signal state_applied(state_name: String)
signal state_removed(state_name: String)
## Any state on this battler changed: applied, re-applied, ticked, removed,
## or changed itself (a shield hit used, a bar filled). The HUD redraws on it.
signal states_changed
signal level_up(new_level: int)
signal exp_gained(amount: int, current_exp: int, exp_needed: int)
enum TEAM {ALLY, ENEMY}

@export_group("Stats Configuration")
@export var stats: BattlerStats ## Configuration for player/ally battlers
@export var enemy_stats: EnemyStats ## Configuration for enemy battlers

@export var inventory: Inventory
## Equipped weapon. When set, a [WeaponSystem] child is spawned in _ready()
## (or immediately via [method set_weapon]) and procs the weapon's effects.
@export var weapon: Weapon = null
var weapon_system: WeaponSystem = null
## Scene-authored socket node (e.g. a BoneAttachment3D) that handheld weapon
## models instance into. Empty = no socket (ORB/root-space weapons unaffected).
@export var weapon_socket_path: NodePath = NodePath("")
## Last canonical combat animation slot played ("melee_combo_1", "ranged_cast_1", ...)
## Exposed for the weapon system to distinguish melee vs ranged hits.
var _last_combat_slot: String = ""

@export_group("Team and AI Controls")
## Define the battler's Team - Allies are Player-controlled
@export var team: TEAM # This will default to ALLY
## If the battler will act independent of player selection, how optimal is it?
## 0 = Randumb, 100 = Big Brain
@export_range(0, 100, 1) var intelligence:int
enum AIType {AGGRESSIVE, DEFENSIVE}
## If this battler acts on its own, what is its strategy/approach to combat?
## Interacts with intelligence to make "optimal" decision.
@export var ai_type:AIType

var character_name: String
var max_health: int
var attack: int
var defense: int
var agility: int
var magic: int
var crit_chance: int  ## Percent chance for a card's damage to crit
var max_ap: int = 3
var current_ap: int = 3
var ap_regen_per_turn: int = 3

# XP and Leveling System
var current_level: int = 1
var current_exp: int = 0
var exp_to_next_level: int = 100

var _current_health_internal: int
var _old_health: int = 0  # Track previous health for healing detection
var _cached_effect_center: Vector3 = Vector3.ZERO  # Cached effect center position
var _cached_effect_top: Vector3 = Vector3.ZERO  # Cached effect top position
var _cached_effect_bottom: Vector3 = Vector3.ZERO  # Cached effect bottom position
var _cached_effect_depth: float = 0.0  # Cached battler depth (Z size)
var _effect_center_cached: bool = false  # Whether the cache is valid
var _is_initialized: bool = false  # Prevent healing effect during initialization

var current_health: int:
	get:
		return _current_health_internal
	set(value):
		if _current_health_internal != value:
			var old_value = _current_health_internal
			_current_health_internal = value
			health_changed.emit(_current_health_internal, max_health)
			notify_battle_event(BattleEvents.HEALTH_CHANGED, {"old_health": old_value, "new_health": value, "max_health": max_health})
			
			# Play healing effect if health increased (but not during initialization)
			if value > old_value and _is_initialized:
				_play_healing_effect()
var is_defending: bool = false
var current_target = null
var is_counter_stunned: bool = false  # Stunned by being hit with a counter attack
## True while this battler is mid-combo with another strike to follow: the hits
## it lands don't wait out the target's flinch (counters and deaths still do).
var chaining_strikes: bool = false
var _is_despawning: bool = false

## The vestiges this battler carries (allies; enemies carry none). The
## battler's single link to the vestige system.
var vestiges: VestigeHolder = VestigeHolder.new(self)

## Stats before any modifier source (level progression for allies, the enemy
## stats for enemies); see [method refresh_stats].
var _base_stats: Dictionary = {}

# Walking animation system
var is_advancing: bool = false
var advance_target_position: Vector3
var original_position: Vector3
var original_rotation: Vector3
var _counter_handled_return: bool = false
var _original_position_saved_this_turn: bool = false

# Per-battler movement settings
@export_group("Movement Settings", "movement")
## Distance at which this battler requires movement to target
@export var custom_movement_distance: float = 2.0
## Speed of movement animation for this battler
@export var custom_movement_speed: float = 4.0
## Movement animation name for this battler
@export var custom_movement_animation: String = ""
## Whether this battler requires movement before attacking
@export var requires_walking: bool = true
## Force movement animation to sync immediately when moving toward positive Z (toward enemy)
@export var sync_movement_animation_forward: bool = true
## Maximum time (seconds) this battler can be stuck in advancing state before auto-return
@export var stuck_movement_timeout: float = 5.0
## If true, fallback damage applies if animation callback doesn't fire
@export var allow_animation_fallback: bool = true
## Animation mapping resource for character-specific animation remapping
## Maps generic animation names (from cards) to character-specific animations
## Example: Card uses "magic_cast", Wizard maps it to "wizard_spell_cast"
@export var animation_mapping: AnimationMapping = null

## Sets an AnimationTree condition on BaseSM and its combat_actions sub-machine.
## Conditions only matter on Auto transitions; the live one is allow_combat_to_idle
## (multi-strike combos hold it false so no idle plays between strikes).
func set_animation_condition(condition_name: String, value: bool) -> void:
	if not anim_tree:
		return
	anim_tree.set("parameters/BaseSM/conditions/" + condition_name, value)
	anim_tree.set("parameters/BaseSM/combat_actions/conditions/" + condition_name, value)



## All MeshInstance3D children discovered at ready-time for the outline/highlight system.
## Populated once by _collect_meshes(); no hardcoded node names required.
var _highlight_meshes: Array[MeshInstance3D] = []

## Collects every MeshInstance3D descendant that should receive the selection outline.
## Skips nodes added to the "ignore_outline" group so special-purpose meshes can opt out.
func _collect_meshes() -> void:
	_highlight_meshes.clear()
	for child in find_children("*", "MeshInstance3D", true, false):
		if child is MeshInstance3D and not child.is_in_group("ignore_outline"):
			# Duplicate the active surface material into material_override so the
			# original texture is preserved while we can safely mutate next_pass.
			if not child.material_override:
				var surf_mat: Material = child.get_active_material(0)
				if surf_mat:
					child.material_override = surf_mat.duplicate()
				else:
					# Mesh has no material at all; create a blank one so next_pass works
					child.material_override = StandardMaterial3D.new()
			_highlight_meshes.append(child)

## Overlay Management System
## Manages stacking of multiple shader overlays (status effects, highlights, etc.)

enum OverlayType {
	STATUS = 0,
	HIGHLIGHT = 1
}

class OverlayEntry:
	var overlay_type: OverlayType
	var material: ShaderMaterial
	var priority: int
	var key: String  # Unique identifier for this overlay

	func _init(p_type: OverlayType, p_material: ShaderMaterial, p_priority: int, p_key: String):
		overlay_type = p_type
		material = p_material
		priority = p_priority
		key = p_key

var _active_overlays: Array[OverlayEntry] = []

## Add an overlay to the stack
func add_overlay(overlay_type: OverlayType, material: ShaderMaterial, priority: int, key: String) -> void:
	# Remove existing overlay with same key
	remove_overlay(key)
	
	# Add new overlay
	var entry = OverlayEntry.new(overlay_type, material, priority, key)
	_active_overlays.append(entry)
	
	# Rebuild overlay chain
	_rebuild_overlay_chain()

## Remove an overlay by key
func remove_overlay(key: String) -> void:
	_active_overlays = _active_overlays.filter(func(entry): return entry.key != key)
	_rebuild_overlay_chain()

## Rebuild the overlay chain based on priority (lower priority = closer to base material)
func _rebuild_overlay_chain() -> void:
	if _highlight_meshes.is_empty():
		return
	
	# Sort overlays by priority
	_active_overlays.sort_custom(func(a, b): return a.priority < b.priority)
	
	for mesh in _highlight_meshes:
		if not is_instance_valid(mesh) or not mesh.material_override:
			continue
		
		# Ensure mesh has material_override
		if not mesh.material_override:
			var surf_mat = mesh.get_active_material(0)
			if surf_mat:
				mesh.material_override = surf_mat.duplicate()
		
		# Clear existing chain
		mesh.material_override.next_pass = null
		
		# Chain overlays in priority order
		var current = mesh.material_override
		for entry in _active_overlays:
			var overlay_instance = entry.material.duplicate()
			current.next_pass = overlay_instance
			current = overlay_instance

@onready var select_outline: Shader = preload("res://assets/shaders/battler_select_shader.gdshader")
var select_ring_scene: PackedScene = null
var select_ring_vfx: VFXInstance = null
var use_vfx_selection: bool = true

var is_selectable: bool = false:
	set(value):
		is_selectable = value
		if !is_selectable:
			is_targeted = false
		_update_highlight()

var is_targeted: bool = false:
	set(value):
		is_targeted = value
		_update_highlight()

var mouse_hover: bool = false:
	set(value):
		mouse_hover = value
		_update_highlight()
		# AOE targeting: every target shows the hover together
		if _in_aoe_targeting():
			for b in _aoe_group():
				if b != self:
					b._update_highlight()

var is_valid_target: bool = false
var is_default_target: bool = false
var is_keyboard_selected: bool = false  # Track if selected via keyboard
var is_mouse_selected: bool = false    # Track if selected via mouse

func _update_highlight() -> void:
	if _highlight_meshes.is_empty():
		return
	
	# Remove existing highlight overlay
	remove_overlay("highlight")
	
	# Remove existing selection ring VFX
	if select_ring_vfx and is_instance_valid(select_ring_vfx):
		select_ring_vfx.stop()
		select_ring_vfx.queue_free()
		select_ring_vfx = null
	
	if !is_selectable or !is_valid_target:
		return
	
	# Use VFX selection if enabled and available (lazy load)
	if use_vfx_selection:
		# Lazy load the scene only when needed
		if not select_ring_scene:
			select_ring_scene = load("res://assets/effects/ground/vfx_battler_select.tscn") as PackedScene
		
		if select_ring_scene:
			if _shows_hover() and is_selectable:
				_spawn_selection_ring(Color.WHITE)
			elif is_targeted or is_mouse_selected or is_keyboard_selected or is_default_target:
				_spawn_selection_ring(Color.CYAN)
			return
	
	# Fallback to shader overlay system
	if _shows_hover() and is_selectable:
		var hover_mat = ShaderMaterial.new()
		hover_mat.shader = select_outline
		hover_mat.set_shader_parameter("color", Color.WHITE)
		hover_mat.set_shader_parameter("thickness", 0.02)
		hover_mat.set_shader_parameter("alpha", 0.6)
		add_overlay(OverlayType.HIGHLIGHT, hover_mat, 10, "highlight")
	elif is_targeted or is_mouse_selected or is_keyboard_selected or is_default_target:
		var shader_mat = ShaderMaterial.new()
		shader_mat.shader = select_outline
		shader_mat.set_shader_parameter("color", Color.CYAN)
		shader_mat.set_shader_parameter("thickness", 0.025)
		shader_mat.set_shader_parameter("alpha", 1.0)
		add_overlay(OverlayType.HIGHLIGHT, shader_mat, 10, "highlight")

func _spawn_selection_ring(color: Color) -> void:
	if not select_ring_scene:
		return
	
	select_ring_vfx = select_ring_scene.instantiate() as VFXInstance
	if not select_ring_vfx:
		return
	
	# Add VFX as child of battler so it moves with it
	add_child(select_ring_vfx)
	
	# Position at ground level relative to battler (y=0 relative to battler's y)
	select_ring_vfx.position = Vector3(0, -global_position.y, 0)
	
	# Set ring color directly on the shader material
	var ring_mesh = select_ring_vfx.get_node("SelectionRing") as MeshInstance3D
	if ring_mesh and ring_mesh.material_override is ShaderMaterial:
		ring_mesh.material_override.set_shader_parameter("color", color)
	
	select_ring_vfx.play()

func _exit_tree():
	# Clean up selection ring VFX when battler is destroyed
	if select_ring_vfx and is_instance_valid(select_ring_vfx):
		select_ring_vfx.stop()
		select_ring_vfx.queue_free()
		select_ring_vfx = null

@export_group("Special Dependencies")
@onready var anim_tree: AnimationTree = $AnimationTree

var state_machine: AnimationNodeStateMachinePlayback
@export var number_indicator: NumberIndicator3D = null
@export var attack_indicator_scene: PackedScene = preload("res://scenes/battle/effects/attack_indicator/attack_indicator_3d.tscn")
var attack_indicator: AttackIndicator3D = null

@export_group("Counter Stun Settings", "stun")
## Duration (seconds) before recovering from being hit by a counter attack
@export var counter_stun_duration: float = 1.5

@export_group("Hit Effects")
## Optional per-battler override for hit effect library
## If null, uses the global GlobalHitEffectLibrary
@export var hit_effect_library: HitEffectLibrary = null

func _ready():
	_collect_meshes()
	
	# Set battler depth on number indicator if available
	if number_indicator and number_indicator.has_method("set_battler_depth"):
		number_indicator.set_battler_depth(get_effect_depth())
	
	# Disconnect any existing connections first
	if SignalBus.select_target.is_connected(check_select_target):
		SignalBus.select_target.disconnect(check_select_target)
	if SignalBus.allow_select_target.is_connected(set_selectable):
		SignalBus.allow_select_target.disconnect(set_selectable)
	if SignalBus.hover_target.is_connected(check_hover_target):
		SignalBus.hover_target.disconnect(check_hover_target)
	if SignalBus.clear_default_selection.is_connected(_clear_default_selection):
		SignalBus.clear_default_selection.disconnect(_clear_default_selection)
	
	# Now connect
	SignalBus.select_target.connect(check_select_target)
	SignalBus.allow_select_target.connect(set_selectable)
	SignalBus.hover_target.connect(check_hover_target)
	SignalBus.clear_default_selection.connect(_clear_default_selection)
	
	state_machine = anim_tree.get("parameters/BaseSM/playback") as AnimationNodeStateMachinePlayback

	# Verify state_machine is valid
	if not state_machine:
		push_error("AnimationNodeStateMachinePlayback not found! Check AnimationTree setup.")
		return

	# Initialize animation conditions
	if anim_tree:
		anim_tree.set("parameters/BaseSM/conditions/allow_combat_to_idle", true)
	
	# Meshes are collected in _collect_meshes() at the start of _ready().
	# Material overrides with duplicated surface materials are set there;
	# no further setup is required here.
	
	if enemy_stats:
		team = TEAM.ENEMY
		character_name = enemy_stats.enemy_name
		_base_stats = {
			"max_health": enemy_stats.max_health,
			"attack": enemy_stats.attack,
			"defense": enemy_stats.defense,
			"agility": enemy_stats.agility,
			"magic": enemy_stats.magic,
		}
		refresh_stats()
		current_health = max_health
		_is_initialized = true
	elif stats:
		# Basic stats for ally
		character_name = stats.character_name
		# Apply level-focused progression (calculates stats based on level)
		apply_level_progression()
		# Initialize XP and level
		current_level = stats.level if stats else 1
		calculate_exp_for_next_level()
		_is_initialized = true
	else:
		push_error("Neither BattlerStats nor EnemyStats resource set for %s!" % name)
	
	# Assign to group based on team
	if team == TEAM.ENEMY:
		add_to_group("enemies")
	elif team == TEAM.ALLY:
		add_to_group("players")
	
	# Initialize attack indicator for enemies
	_initialize_attack_indicator()
	
	# Vestiges the run gives this ally (re-read at combat start, which also
	# fires their combat-start triggers)
	if team == TEAM.ALLY:
		vestiges.reload()
		refresh_stats()

	# Spawn the weapon system for the equipped weapon (if any).
	if weapon != null:
		set_weapon(weapon)

## Equips [param p_weapon], spawning/refreshing the [WeaponSystem] child.
## Safe to call before or after _ready (party sync configures allies early).
func set_weapon(p_weapon: Weapon) -> void:
	weapon = p_weapon
	if weapon_system and is_instance_valid(weapon_system):
		weapon_system.queue_free()
		weapon_system = null
	if weapon == null:
		refresh_stats()
		_hide_socket_weapon()
		return
	if not is_inside_tree():
		return
	weapon_system = WeaponSystem.new()
	weapon_system.name = "WeaponSystem"
	weapon_system.setup(weapon, self)
	add_child(weapon_system)


## Animation callback methods called by AnimationPlayer method tracks
## These are the new reference point system replacing timer-based hit frames

func _on_attack_start():
	"""Called by AnimationPlayer method track at animation start frame"""
	attack_start.emit()

func _on_attack_hit():
	"""Called by AnimationPlayer method track at hit moment frame"""
	hit_moment.emit(self)

func _on_attack_end():
	"""Called by AnimationPlayer method track at animation end frame"""
	attack_end.emit()

func _input_event(_camera: Camera3D, event: InputEvent, _position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	var battle_manager = get_tree().get_first_node_in_group("battle_manager")
	if battle_manager and not battle_manager.mouse_input_toggle:
		return
		
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if is_selectable and is_valid_target:
			select_target()

func _mouse_enter() -> void: 
	var battle_manager = get_tree().get_first_node_in_group("battle_manager")
	if battle_manager and not battle_manager.mouse_input_toggle:
		return
		
	if is_valid_target:
		has_hover(true)
		
func _mouse_exit() -> void: 
	var battle_manager = get_tree().get_first_node_in_group("battle_manager")
	if battle_manager and not battle_manager.mouse_input_toggle:
		return
		
	has_hover(false)

func has_hover(hover:bool = false) -> void:
	# Only allow hover if this battler is a valid target
	if hover and !is_valid_target:
		return
	mouse_hover = hover
	
	# Emit hover signal when hovering over a valid target
	if hover and is_valid_target:
		SignalBus.hover_target.emit(self)

func set_selectable(can_target: bool) -> void:
	is_selectable = can_target and is_valid_target
	
	if !is_selectable:
		clear_all_selections()
	_update_highlight()

func check_select_target(target:Battler) -> void:
	# Check if we're in AOE mode - if so, don't deselect other targets
	var battle_manager = get_tree().get_first_node_in_group("battle_manager")
	var is_aoe = false
	if battle_manager and battle_manager.has_meta("is_aoe_mode"):
		is_aoe = battle_manager.get_meta("is_aoe_mode", false)
	
	if not is_aoe:
		if target != self and is_targeted:
			deselect_as_target()

func check_hover_target(_target: Battler) -> void:
	SignalBus.clear_default_selection.emit()

func _clear_default_selection() -> void:
	# Clear this battler's default selection if it has one
	if is_default_target:
		is_default_target = false
		_update_highlight()

## True while the player is picking an AOE card's targets: every valid
## target is picked together, never one alone.
func _in_aoe_targeting() -> bool:
	if not is_inside_tree():
		return false
	var bm = get_tree().get_first_node_in_group("battle_manager")
	return bm != null and bm.in_target_selection and bool(bm.get_meta("is_aoe_mode", false))


## The targets an AOE card is being aimed at.
func _aoe_group() -> Array:
	var bm = get_tree().get_first_node_in_group("battle_manager")
	return bm.valid_targets.filter(func(b): return is_instance_valid(b) and b is Battler) if bm else []


## Draw the hover highlight: this battler is hovered, or (AOE targeting) any
## of the AOE's targets is.
func _shows_hover() -> bool:
	if mouse_hover:
		return true
	if not _in_aoe_targeting() or not is_valid_target:
		return false
	return _aoe_group().any(func(b): return b.mouse_hover)


func select_target() -> void:
	# AOE: clicking any target confirms the whole group; don't single it out
	if _in_aoe_targeting():
		SignalBus.select_target.emit(self)
		return
	# Clear all other selection states first
	is_keyboard_selected = false
	is_default_target = false
	is_mouse_selected = true
	is_targeted = true
	SignalBus.select_target.emit(self)

func deselect_as_target() -> void:
	is_targeted = false
	is_mouse_selected = false
	is_keyboard_selected = false
	is_default_target = false
	# Force update the highlight to clear it
	_update_highlight()

func set_as_default_target() -> void:
	# Clear other selection states first
	is_mouse_selected = false
	is_keyboard_selected = false
	is_default_target = true
	is_targeted = true
	# Force update the highlight
	_update_highlight()

func set_as_keyboard_target() -> void:
	# Clear other selection types first
	is_mouse_selected = false
	is_default_target = false
	is_keyboard_selected = true
	is_targeted = true
	# Force update the highlight
	_update_highlight()

func clear_all_selections() -> void:
	is_targeted = false
	is_mouse_selected = false
	is_keyboard_selected = false
	is_default_target = false
	mouse_hover = false
	remove_overlay("highlight")


func is_defeated() -> bool:
	return current_health <= 0

func get_attack_damage(target) -> int:
	var damage = attack + randi() % 5
	return Formulas.physical_damage(self, target, damage)

## Play hit effects based on damage type and element
## damage_type: e.g., "physical", "magical", "true_damage"
## element: e.g., "fire", "ice", "lightning", "none"
## attacker: Optional attacker reference
func play_hit_effects(damage_type: String, element: String, attacker: Battler = null) -> void:
	# Get the global hit effect library
	var library = get_hit_effect_library()
	if not library:
		return
	
	# Get effects for this damage/element combination
	var effects = library.get_effects_for_type(damage_type, element)
	if effects.is_empty():
		return
	
	# Get center position for spawning effects
	var center_position = get_effect_position(EffectPosition.CENTER)
	
	# Get battler depth for dynamic Z offset
	var battler_depth = get_effect_depth()
	
	# Spawn all effects with smart spacing
	for i in range(effects.size()):
		var effect = effects[i]
		effect.spawn(self, center_position, i, effects.size(), battler_depth)

## Get the hit effect library to use (global or per-battler override)
func get_hit_effect_library() -> HitEffectLibrary:
	# Check for per-battler override first
	if hit_effect_library:
		return hit_effect_library
	
	# Fall back to global library
	if has_node("/root/GlobalHitEffectLibrary"):
		var global_lib = get_node("/root/GlobalHitEffectLibrary")
		if global_lib and global_lib.has_method("get_library"):
			return global_lib.get_library()
	
	return null

## [param is_attack]: true for an attack (card or enemy attack, counter), false
## for bonus damage (weapon procs, vestiges, DOTs). Rides on DAMAGE_TAKEN /
## DAMAGE_DEALT so on-hit effects react to attacks only.
## [param is_critical]: the hit was a crit (shown as such, and in the events).
func take_damage(amount: int, attacker: Battler = null, damage_type: String = "physical", element: String = "none", is_attack: bool = false, is_critical: bool = false) -> void:
	# Get battle manager once for use throughout the function
	var battle_manager = get_tree().get_first_node_in_group("battle_manager")
	
	amount = int(float(amount) * get_multiplier(&"damage_taken"))
	
	# Play hit effects before damage calculation
	play_hit_effects(damage_type, element, attacker)
	
	var hit := {"attacker": attacker, "damage": 0, "damage_type": damage_type, "element": element, "is_attack": is_attack, "is_critical": is_critical, "battle_manager": battle_manager}

	# A state may stop the hit outright (Protected): no damage, no effects
	for state in active_states.values():
		if state is State and state.blocks_hit(self, hit):
			return

	var damage_taken = max(1, amount) if amount > 0 else 0
	if is_defending:
		damage_taken = max(1, int(damage_taken * 0.5))
		is_defending = false
	
	# Show damage number
	if number_indicator:
		number_indicator.show_damage(damage_taken, is_critical)

	hit["damage"] = damage_taken
	_lose_health(hit)
	
	# PLAY HIT REACTION FLINCH— skipped when fully avoided (0 damage) or defeated
	if damage_taken > 0 and current_health > 0:
		if attacker is Battler and is_instance_valid(attacker) and attacker.chaining_strikes:
			play_hit_reaction()  # flinch, but let the combo's next strike come in
		else:
			await play_hit_reaction()
	
	# The states react to the hit (Bleed builds, Marked is spent, counters...).
	# Awaited, so an attacker stays in place during a counter
	for state in active_states.values().duplicate():
		if state is State and active_states.values().has(state):
			await state.on_hit_taken(self, hit)
	
	if current_health <= 0:
		await _handle_defeat(attacker)


## Takes [code]hit["damage"][/code] off this battler's health (a lethal amount
## first gives revive effects their chance) and tells the battle about it.
## [param hit]: attacker, damage, damage_type, element, is_attack,
## is_critical, battle_manager. Shared by hits and by states' turn damage.
func _lose_health(hit: Dictionary) -> void:
	var damage_taken := int(hit.get("damage", 0))
	var attacker = hit.get("attacker")
	var new_health := maxi(current_health - damage_taken, 0)
	if new_health == 0 and damage_taken > 0:
		# Passive systems may save the battler (e.g. a revive vestige)
		notify_battle_event(BattleEvents.LETHAL_DAMAGE, hit)
		new_health = maxi(int(hit.get("revive_health", 0)), 0)
		hit.erase("revive_health")
	current_health = new_health
	if damage_taken > 0:
		notify_battle_event(BattleEvents.DAMAGE_TAKEN, hit.duplicate())
		if is_instance_valid(attacker) and attacker != self:
			var dealt := hit.duplicate()
			dealt.erase("attacker")
			dealt["target"] = self
			attacker.notify_battle_event(BattleEvents.DAMAGE_DEALT, dealt)


## This battler just fell (to [param killer]'s hit, or a state's damage):
## defeat events, XP and rewards, then off the field. If it was the acting
## battler, the battle moves on to the next turn. Runs once per defeat.
func _handle_defeat(killer: Node) -> void:
	var battle_manager = get_tree().get_first_node_in_group("battle_manager")
	var attacker: Battler = killer as Battler if is_instance_valid(killer) else null
	if current_health <= 0:
		if _is_despawning:
			return
		_is_despawning = true
		# The fallen keep no states (or their overlays and auras)
		clear_states()
		if battle_manager:
			battle_manager.notify_opponents_of(self, BattleEvents.ENEMY_DEFEATED, {"defeated": self, "attacker": attacker})

		# Unregister from impact frame system when defeated
		if battle_manager and battle_manager.effect_manager:
			battle_manager.effect_manager.unregister_impact_node(self)
		
		# Award XP to the attacker who killed the enemy
		if battle_manager and team == TEAM.ENEMY and enemy_stats and attacker:
			var exp_reward = enemy_stats.exp_reward
			if attacker.current_health > 0 and attacker.team == TEAM.ALLY:
				attacker.add_experience(exp_reward)
		
		if battle_manager and battle_manager.has_method("register_enemy_defeat_reward"):
			battle_manager.register_enemy_defeat_reward(self)
		if battle_manager and battle_manager.remove_defeated_enemies and team == TEAM.ENEMY:
			if battle_manager.turn_order.has(self):
				battle_manager.turn_order.erase(self)
			if battle_manager.enemies.has(self):
				battle_manager.enemies.erase(self)
			# Update HUD turn queue immediately
			if battle_manager.hud and battle_manager.hud.turn_queue_ui:
				battle_manager.hud.turn_queue_ui.update_queue(battle_manager.turn_order, battle_manager.current_turn)
			elif battle_manager.hud and battle_manager.hud.has_method("update_turn_queue"):
				battle_manager.hud.update_turn_queue(battle_manager.turn_order, battle_manager.current_turn)
			# Out-of-band kills (parry counters etc.) don't go through the normal
			# turn cycle. If the ACTING battler was just defeated, its own attack
			# coroutine can no longer end the turn - advance the flow now, whether
			# the battle is over or not (start_next_turn checks the win condition).
			if battle_manager.current_battler == self or battle_manager.is_battle_over():
				battle_manager.start_next_turn()
			await _fade_and_remove()
		elif battle_manager and team == TEAM.ALLY:
			# Fallen allies stay on the field in their death pose
			_play_death_animation()
			if battle_manager.turn_order.has(self):
				battle_manager.turn_order.erase(self)
			if battle_manager.players.has(self):
				battle_manager.players.erase(self)
			# Update HUD turn queue immediately
			if battle_manager.hud and battle_manager.hud.turn_queue_ui:
				battle_manager.hud.turn_queue_ui.update_queue(battle_manager.turn_order, battle_manager.current_turn)
			elif battle_manager.hud and battle_manager.hud.has_method("update_turn_queue"):
				battle_manager.hud.update_turn_queue(battle_manager.turn_order, battle_manager.current_turn)
			# If the ACTING battler was just defeated (e.g. killed by a counter),
			# its turn can no longer end on its own - advance now, win or not.
			if battle_manager.current_battler == self or battle_manager.is_battle_over():
				battle_manager.start_next_turn()
		else:
			_is_despawning = false

func take_healing(amount: int):
	# Get battle manager for vestige hooks
	var battle_manager = get_tree().get_first_node_in_group("battle_manager")

	amount = int(float(amount) * get_multiplier(&"healing"))

	var healing = maxi(mini(amount, max_health - current_health), 0)

	current_health += healing
	if healing > 0:
		notify_battle_event(BattleEvents.HEALED, {"heal_amount": healing, "battle_manager": battle_manager})
	return healing

func defend():
	is_defending = true
	# FORCE use idle1, not the dictionary
	_try_animation("idle1")

func battle_item(item: Item, target: Battler) -> void:
	# Apply item effects
	# Item.hp_delta: negative = damage, positive = healing
	if item.hp_delta < 0:
		target.take_damage(-item.hp_delta, self)
	elif item.hp_delta > 0:
		var _healing = target.take_healing(item.hp_delta)
	
	# Remove item from inventory
	if inventory and inventory.collection.has(item):
		var quantity = inventory.collection[item]
		if quantity > 1:
			inventory.collection[item] = quantity - 1
		else:
			inventory.collection.erase(item)

## XP and Leveling System
func add_experience(amount: int) -> void:
	amount = roundi(amount * get_multiplier(&"xp"))
	current_exp += amount
	if number_indicator:
		number_indicator.show_xp(amount)
	exp_gained.emit(amount, current_exp, exp_to_next_level)
	check_level_up()

func check_level_up() -> void:
	while current_exp >= exp_to_next_level:
		current_exp -= exp_to_next_level
		current_level += 1
		calculate_exp_for_next_level()
		apply_level_progression()
		level_up.emit(current_level)
		play_level_up_effect()

func calculate_exp_for_next_level() -> void:
	# Minecraft-style exponential formula
	# Level 1→2: 100 XP
	# Level 2→3: 110 XP (100 * 1.1)
	# Level 3→4: 121 XP (110 * 1.1)
	exp_to_next_level = int(100 * pow(1.1, current_level - 1))

func play_level_up_effect() -> void:
	var vfx = preload("res://assets/effects/ground/vfx_level_up.tscn").instantiate()
	add_child(vfx)
	vfx.global_position = global_position
	# Auto-cleanup after effect plays
	await get_tree().create_timer(3.0).timeout
	if is_instance_valid(vfx):
		vfx.queue_free()

## Initialize attack indicator for enemies
func _initialize_attack_indicator() -> void:
	if team != TEAM.ENEMY:
		return
	
	if not attack_indicator_scene:
		return
	
	if attack_indicator:
		return
	
	attack_indicator = attack_indicator_scene.instantiate() as AttackIndicator3D
	if not attack_indicator:
		push_error("Failed to instantiate attack indicator for %s" % name)
		return
	
	# Position indicator at the top of the battler with an offset
	var top_pos = get_effect_position(EffectPosition.TOP)
	attack_indicator.position = Vector3(0, top_pos.y + 0.8, 0)
	add_child(attack_indicator)


# ---------------------------------------------------------------------------
# Stats and passive systems
# ---------------------------------------------------------------------------

## Recomputes the stats: base stats plus the deltas of every modifier source
## (see [method _stat_modifier_sources]). Idempotent - call it whenever the
## base or a source changes; nothing ever adds to a stat directly.
func refresh_stats() -> void:
	if _base_stats.is_empty():
		return
	var totals := {}
	for source in _stat_modifier_sources():
		var mods: Dictionary = source.get_stat_modifiers(_base_stats)
		for stat in mods:
			totals[stat] = int(totals.get(stat, 0)) + int(mods[stat])
	for stat in _base_stats:
		set(stat, int(_base_stats[stat]) + int(totals.get(stat, 0)))
	if max_health > 0 and current_health > max_health:
		current_health = max_health
	if current_ap > max_ap:
		current_ap = max_ap


## Everything that modifies this battler's stats. Each answers
## [code]get_stat_modifiers(base: Dictionary) -> Dictionary[/code] (stat ->
## delta); a new kind of source only needs adding here.
func _stat_modifier_sources() -> Array:
	var sources: Array = []
	if weapon:
		sources.append(weapon)
	if vestiges:
		sources.append(vestiges)
	return sources


## Tells this battler's passive systems about a battle event (one of
## [BattleEvents]). Battle and card code call only this; each system maps the
## event to its own behaviour.
func notify_battle_event(event: StringName, context: Dictionary = {}) -> void:
	for listener in _event_listeners():
		listener.handle_event(event, context)


## Everything that reacts to battle events; each answers
## [code]handle_event(event, context)[/code]. A new kind only needs adding here.
func _event_listeners() -> Array:
	var listeners: Array = []
	if vestiges:
		listeners.append(vestiges)
	if weapon_system and is_instance_valid(weapon_system) and not weapon_system.is_queued_for_deletion():
		listeners.append(weapon_system)
	return listeners


## Everything that adjusts this battler's combat numbers beyond its stats.
## Each may answer [code]get_multiplier(name) -> float[/code] and
## [code]get_bonus(name) -> int[/code]; a new kind only needs adding here.
func _passive_sources() -> Array:
	var sources: Array = []
	if vestiges:
		sources.append(vestiges)
	if weapon_system:
		sources.append(weapon_system)
	return sources


## Combined multiplier [param name] of every passive source, e.g.
## [code]&"damage_dealt"[/code], [code]&"damage_taken"[/code],
## [code]&"healing"[/code], [code]&"xp"[/code].
func get_multiplier(name: StringName) -> float:
	var multiplier := 1.0
	for source in _passive_sources():
		if source.has_method("get_multiplier"):
			multiplier *= source.get_multiplier(name)
	return multiplier


## Summed bonus [param name] of every passive source, e.g.
## [code]&"ap_cost_reduction"[/code], [code]&"cards_drawn_per_turn"[/code],
## [code]&"starting_hand_size"[/code].
func get_bonus(name: StringName) -> int:
	var total := 0
	for source in _passive_sources():
		if source.has_method("get_bonus"):
			total += int(source.get_bonus(name))
	return total


## AP this battler pays to play [param card] (never below 0).
func get_card_ap_cost(card: CardConfig) -> int:
	return maxi(card.ap_cost - get_bonus(&"ap_cost_reduction"), 0)


## Hides the socket's placeholder "Weapon" child (unarmed state). The node
## stays in the tree so animation method tracks keep resolving.
func _hide_socket_weapon() -> void:
	if weapon_socket_path == NodePath("") or not is_inside_tree():
		return
	var socket := get_node_or_null(weapon_socket_path)
	if socket == null:
		return
	var weapon_node := socket.get_node_or_null("Weapon")
	if weapon_node:
		weapon_node.visible = false


## Determine indicator type from attack config
func _get_indicator_type(attack_config: EnemyAttackConfig) -> AttackIndicator3D.AttackType:
	if not attack_config:
		return AttackIndicator3D.AttackType.DODGE_ONLY
	
	if attack_config.requires_jump:
		return AttackIndicator3D.AttackType.JUMPABLE
	
	if attack_config.can_parry and not attack_config.can_dodge:
		return AttackIndicator3D.AttackType.PARRIABLE_ONLY
	
	if not attack_config.can_parry and attack_config.can_dodge:
		return AttackIndicator3D.AttackType.DODGE_ONLY
	
	# If both are allowed, default to dodge-only (gold circle)
	return AttackIndicator3D.AttackType.DODGE_ONLY

## Performs an attack animation and damage application on target
## Optionally accepts an EnemyAttackConfig for custom animation/timing/multiplier
func attack_anim(target, attack_config: EnemyAttackConfig = null) -> void:
	if target == self:
		return
	
	current_target = target
	_counter_handled_return = false
	
	# Save original position before any movement
	save_original_position()
	
	var rtdm: RealTimeDefenseManager = get_tree().get_first_node_in_group("real_time_defense_manager")
	if rtdm and target.team == TEAM.ALLY:
		rtdm.open_buffer(self, target, attack_config)
	
	# Show attack indicator for enemies attacking allies
	if team == TEAM.ENEMY and target.team == TEAM.ALLY and attack_indicator:
		var indicator_type = _get_indicator_type(attack_config)
		attack_indicator.show_indicator(indicator_type)
	
	if await advance_to_target(target):
		_try_animation(AnimationMapping.WALK)
		while is_advancing:
			await get_tree().create_timer(0.016).timeout
	
	var battle_manager = get_tree().get_first_node_in_group("battle_manager")
	var chosen_anim = AnimationMapping.MELEE_COMBO_1
	if attack_config and not attack_config.animation_name.is_empty():
		chosen_anim = attack_config.animation_name
	
	var _attack_ended = false
	var _on_attack_end_callback = func(): _attack_ended = true
	attack_end.connect(_on_attack_end_callback, CONNECT_ONE_SHOT)

	if not _try_animation(chosen_anim):
		_try_animation(AnimationMapping.MELEE_COMBO_1)
	
	await hit_moment
	var exact_hit_time = Time.get_ticks_msec() / 1000.0
	
	# Late forgiveness window: wait briefly so slightly late inputs are still captured
	if rtdm and target.team == TEAM.ALLY:
		await get_tree().create_timer(0.15).timeout
	
	var defense_result := "none"
	if rtdm and target.team == TEAM.ALLY:
		defense_result = rtdm.lock_and_evaluate(exact_hit_time)
	
	var base_atk := attack if attack > 0 else 15
	var multiplier := attack_config.damage_multiplier if attack_config else 1.0
	var raw_damage := int(base_atk * multiplier)
	var mitigated := _apply_defense_to_damage(raw_damage, defense_result)
	
	# Save whether we need to return before damage
	var should_return = original_position != Vector3.ZERO and not _counter_handled_return
	
	if battle_manager and target and mitigated > 0:
		await battle_manager.damage_calculation(self, target, mitigated, attack_config)
		if target.is_defeated():
			if rtdm:
				rtdm.close_buffer()
			# Still return to original position even if target died
			if should_return:
				return_to_original_position()
				while is_advancing:
					await get_tree().create_timer(0.1).timeout
			return
	
	if defense_result == "perfect_parry" and rtdm:
		await rtdm.execute_perfect_parry_counter(target, self)
	
	if not _counter_handled_return and not _attack_ended:
		var timeout_t = 0.0
		while not _attack_ended and timeout_t < 1.5:
			await get_tree().process_frame
			timeout_t += get_process_delta_time()
	
	if rtdm:
		rtdm.close_buffer()
	
	# Hide attack indicator after attack completes
	if attack_indicator:
		attack_indicator.hide_indicator()
	
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.1).timeout
	
	if is_counter_stunned:
		await get_tree().create_timer(counter_stun_duration).timeout
		is_counter_stunned = false
	
	if should_return:
		return_to_original_position()
		while is_advancing:
			await get_tree().create_timer(0.1).timeout
	
	if not _counter_handled_return:
		battle_idle()

func _apply_defense_to_damage(damage: int, defense_result: String) -> int:
	match defense_result:
		"perfect_parry": return 0
		"dodge", "jump": return 0
		_:               return damage

func wait_attack():
	if self.is_defending:
		return
	# Wait for attack animation to complete via animation callback
	await attack_end
	
	# If we advanced to attack, return to original position
	if original_position != Vector3.ZERO:
		return_to_original_position()
		# Wait for return movement to complete
		while is_advancing:
			await get_tree().create_timer(0.1).timeout
	
	# Always end in idle state
	battle_idle()

func battle_idle():
	_try_animation("idle1")
	# Never leave a combo's "hold in combat_actions" flag set
	set_animation_condition("allow_combat_to_idle", true)

## The hit flinch: a OneShot ("HitShot") filtered to the upper body, blending the
## "Hit" clip over whatever BaseSM is playing. Firing again restarts it.
const HIT_SHOT_REQUEST := "parameters/HitShot/request"
const HIT_CLIP_NODE := "Hit"
## Longest a hit flinch holds up the caller (take_damage -> the attacker's turn).
## The clip itself always plays to the end.
@export var hit_reaction_max_wait: float = 1.0

## Plays the standardised hit flinch animation and waits for it (capped by
## hit_reaction_max_wait).
func play_hit_reaction() -> void:
	if not anim_tree or _is_despawning:
		return
	anim_tree.set(HIT_SHOT_REQUEST, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	_snap_animation()
	var wait := minf(_get_animation_duration(AnimationMapping.HIT), hit_reaction_max_wait)
	await get_tree().create_timer(wait).timeout

func advance_to_target(target: Battler) -> bool:
	var battle_manager = get_tree().get_first_node_in_group("battle_manager")
	if not battle_manager:
		return false

	if not requires_walking:
		return false

	# SAFETY: Prevent overlapping advances
	if is_advancing:
		return false

	# Ensure original transform is saved prior to movement
	save_original_position()

	# Calculate dynamic stop distance based on target's AABB
	var movement_distance = get_target_stop_distance(target)
	var movement_speed = custom_movement_speed

	# Apply speed multiplier from battle manager
	movement_speed *= battle_manager.speed_multiplier

	var distance_to_target = global_position.distance_to(target.global_position)
	if distance_to_target <= movement_distance:
		return false

	var direction = (target.global_position - global_position).normalized()
	advance_target_position = target.global_position - direction * movement_distance

	# Calculate movement duration based on speed
	var movement_duration = global_position.distance_to(advance_target_position) / movement_speed

	set_advancing(true)
	_try_animation(AnimationMapping.WALK)
	# Time the walk so it starts with the move and ends on arrival
	var fit := _fit_locomotion(AnimationMapping.WALK, movement_duration)

	# Rotate to face target horizontally (+Z forward convention)
	var flat_look_dir := target.global_position - global_position
	flat_look_dir.y = 0.0
	var target_yaw := rotation.y
	if flat_look_dir.length_squared() > 0.0001:
		target_yaw = atan2(flat_look_dir.x, flat_look_dir.z)
		# Shortest-angle interpolation
		target_yaw = rotation.y + wrapf(target_yaw - rotation.y, -PI, PI)

	# Wait for animation to start before beginning movement
	await get_tree().process_frame

	var tween = create_tween().set_parallel(true)
	_tween_move(tween, global_position, advance_target_position, fit)
	tween.tween_property(self, "rotation:y", target_yaw, minf(fit["duration"], 0.2))
	tween.chain().tween_callback(_on_advance_complete)

	_set_base_time_scale(fit["scale"])

	# Start movement timeout timer
	_start_movement_timeout()

	return true

## Playback speed of the base locomotion/action layer (the TimeScale node between
## BaseSM and HitShot in every battler tree). The hit flinch is unaffected.
const BASE_TIME_SCALE_PARAM := "parameters/TimeScale/scale"
## Playback-speed limits when a locomotion clip is fitted to a move. A move
## that would need more is lengthened or shortened instead.
const MIN_LOCOMOTION_SCALE := 0.75
const MAX_LOCOMOTION_SCALE := 3.0
## Points sampled from a clip's root-motion travel to shape the move.
const LOCOMOTION_CURVE_SAMPLES := 48
## Share of a clip's root-motion travel that counts as "arrived"; the rest of
## the clip is recovery, cut by whatever plays next.
const LOCOMOTION_ARRIVE_PROGRESS := 0.98

## Fits locomotion state [param state] (walk, walk_back, dodge) to a move that
## should take [param duration] seconds, so the animation starts with the move
## and ends on arrival. Returns {duration, scale, curve}; start the move with
## [method _tween_move] and apply scale with [method _set_base_time_scale].
## - A clip with root motion (the tree extracts it, e.g. a dash) plays once,
##   timed so its travel ends on arrival, and curve is that travel: the body
##   moves when the animation pushes off instead of sliding at a fixed speed.
## - Other clips loop a whole number of times (once if the state doesn't
##   loop) and end on arrival; the move is linear (empty curve).
## duration changes only to keep the speed within the limits above.
func _fit_locomotion(state: String, duration: float) -> Dictionary:
	var fit := {"duration": maxf(duration, 0.01), "scale": 1.0, "curve": PackedFloat32Array()}
	var base_sm := anim_tree.tree_root.get_node("BaseSM") as AnimationNodeStateMachine if anim_tree else null
	if not base_sm or not base_sm.has_node(state):
		return fit
	var node := base_sm.get_node(state) as AnimationNodeAnimation
	if not node or not anim_tree.has_animation(node.animation):
		return fit
	var clip := anim_tree.get_animation(node.animation)
	if clip.length <= 0.0:
		return fit

	var travel := _root_motion_travel(clip, node.play_mode == AnimationNodeAnimation.PLAY_MODE_BACKWARD)
	var clip_time: float = clip.length
	if not travel.is_empty():
		clip_time = travel["end_time"]
		fit["curve"] = travel["curve"]
	else:
		var loops := node.loop_mode != Animation.LOOP_NONE if node.use_custom_timeline else clip.loop_mode != Animation.LOOP_NONE
		if loops:
			clip_time = clip.length * maxf(1.0, roundf(fit["duration"] / clip.length))
		else:
			# A one-shot's automatic at-end exit (e.g. dodge -> idle1) starts its
			# crossfade before the clip ends; make that happen on arrival
			clip_time = maxf(clip.length - _at_end_exit_fade(base_sm, state), clip.length * 0.5)
	fit["duration"] = clampf(fit["duration"], clip_time / MAX_LOCOMOTION_SCALE, clip_time / MIN_LOCOMOTION_SCALE)
	fit["scale"] = clip_time / fit["duration"]
	return fit

## Longest crossfade of [param state]'s automatic at-end exits (0 if none).
func _at_end_exit_fade(machine: AnimationNodeStateMachine, state: String) -> float:
	var fade := 0.0
	for i in machine.get_transition_count():
		if machine.get_transition_from(i) != StringName(state):
			continue
		var tr := machine.get_transition(i)
		if tr.switch_mode == AnimationNodeStateMachineTransition.SWITCH_MODE_AT_END \
				and tr.advance_mode == AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO:
			fade = maxf(fade, tr.xfade_time)
	return fade

## The clip's root-motion travel as {end_time, curve}: end_time is when it
## reaches LOCOMOTION_ARRIVE_PROGRESS of its distance, curve the progress
## (0..1, never going back) at evenly spaced times up to end_time. Empty when
## the tree doesn't extract root motion or this clip barely travels.
## [param reverse]: the state plays the clip backwards (times are then counted
## in play order, as the state machine reports them).
func _root_motion_travel(clip: Animation, reverse: bool = false) -> Dictionary:
	if anim_tree.root_motion_track.is_empty():
		return {}
	var track := clip.find_track(anim_tree.root_motion_track, Animation.TYPE_POSITION_3D)
	if track < 0:
		return {}
	var clip_at := func(t: float) -> float:
		return clip.length - t if reverse else t
	var start: Vector3 = clip.position_track_interpolate(track, clip_at.call(0.0))
	var delta: Vector3 = clip.position_track_interpolate(track, clip_at.call(clip.length)) - start
	var dir := Vector2(delta.x, delta.z)
	if dir.length() < 0.25:
		return {}
	var total := dir.length()
	dir /= total
	var progress_at := func(t: float) -> float:
		var p: Vector3 = clip.position_track_interpolate(track, clip_at.call(t)) - start
		return clampf(Vector2(p.x, p.z).dot(dir) / total, 0.0, 1.0)

	var end_time := clip.length
	var steps := 120
	for i in range(1, steps + 1):
		var t := clip.length * i / steps
		if progress_at.call(t) >= LOCOMOTION_ARRIVE_PROGRESS:
			end_time = t
			break
	var curve := PackedFloat32Array()
	var reached := 0.0
	for i in LOCOMOTION_CURVE_SAMPLES:
		reached = maxf(reached, progress_at.call(end_time * i / (LOCOMOTION_CURVE_SAMPLES - 1)))
		curve.append(reached)
	var last := curve[curve.size() - 1]
	for i in curve.size():
		curve[i] /= last
	return {"end_time": end_time, "curve": curve}

## Adds the move from [param from] to [param to] described by [param fit]
## (from [method _fit_locomotion]) to [param tween].
func _tween_move(tween: Tween, from: Vector3, to: Vector3, fit: Dictionary) -> void:
	tween.tween_method(_apply_move.bind(from, to, fit["curve"]), 0.0, 1.0, fit["duration"])

func _apply_move(t: float, from: Vector3, to: Vector3, curve: PackedFloat32Array) -> void:
	var progress := t
	if curve.size() >= 2:
		var x := clampf(t, 0.0, 1.0) * (curve.size() - 1)
		var i := mini(int(x), curve.size() - 2)
		progress = lerpf(curve[i], curve[i + 1], x - i)
	global_position = from.lerp(to, progress)

func _set_base_time_scale(value: float) -> void:
	if anim_tree:
		anim_tree.set(BASE_TIME_SCALE_PARAM, value)

## Attempts to travel to an animation state by name.
## Accepts canonical slot names (e.g. AnimationMapping.MELEE_COMBO_1) or raw state names.
## Resolves via animation_mapping if set, then routes combat_actions slots through the
## nested sub-state-machine. Reads clip duration and schedules hit_moment for all
## combat_actions slots.
## The target state MUST exist on this character's AnimationTree — cards and configs
## reference canonical slot names. A missing state fails loudly (returns false with a
## clear error) instead of playing a substitute or erroring the engine state machine.
func _try_animation(anim_name: String) -> bool:
	if not anim_name or anim_name.is_empty():
		return false
	if not state_machine:
		return false
	if not anim_tree:
		return false
	# Once defeated, only the death state may play. Coroutines that outlive the
	# defeat (e.g. an attacker killed by a counter still returning / idling)
	# would otherwise travel away from death - with no path, travel() teleports.
	if _is_despawning and anim_name != AnimationMapping.DEATH:
		return false

	# Get the BaseSM state machine from the BlendTree
	var root_sm := anim_tree.tree_root.get_node("BaseSM") as AnimationNodeStateMachine
	if not root_sm:
		push_error("[Battler] BaseSM not found in AnimationTree on '%s'" % character_name)
		return false

	# Resolve via animation mapping (slot -> character-specific state name).
	var resolved_name := get_resolved_animation(anim_name)

	# Canonical offensive slots live inside the combat_actions sub-machine.
	var combat_slots: Array = [
		AnimationMapping.MELEE_COMBO_1, AnimationMapping.MELEE_COMBO_2, AnimationMapping.MELEE_COMBO_3,
		AnimationMapping.RANGED_CAST_1, AnimationMapping.RANGED_CAST_2,
	]
	var leaf_name := resolved_name
	var is_combat_slot := (resolved_name in combat_slots) or (anim_name in combat_slots)
	if is_combat_slot:
		_last_combat_slot = anim_name

	# Accept "combat_actions/leaf" paths; map legacy "basic_attacks/leaf" onto the
	# same routing (that sub-machine no longer exists).
	if resolved_name.begins_with("combat_actions/") or resolved_name.begins_with("basic_attacks/"):
		leaf_name = resolved_name.get_slice("/", 1)
		is_combat_slot = true

	if is_combat_slot:
		# Two-step travel: root -> combat_actions container, then leaf inside it.
		# Validate both hops — a state missing from this tree is a data error, not a
		# reason to spam the engine state machine with invalid travels.
		if not root_sm.has_node("combat_actions"):
			push_error("[Battler] No combat_actions sub-machine on '%s'" % character_name)
			return false
		var ca_node := root_sm.get_node("combat_actions") as AnimationNodeStateMachine
		if not ca_node or not ca_node.has_node(leaf_name):
			push_error("[Battler] Combat animation '%s' does not exist in combat_actions on '%s'" % [leaf_name, character_name])
			return false

		# Only travel to combat_actions if we're not already in it.
		# This prevents resetting the sub-machine during multi-strike combos,
		# which would cause idle to play between consecutive strikes.
		var active_node = state_machine.get_current_node()
		var was_outside = (active_node != "combat_actions")
		if was_outside:
			state_machine.travel("combat_actions")

		var ca_sm := anim_tree.get("parameters/BaseSM/combat_actions/playback") as AnimationNodeStateMachinePlayback
		if not ca_sm:
			push_warning("[Battler] Missing BaseSM/combat_actions/playback on '%s'" % character_name)
			return false

		if was_outside:
			ca_sm.start(leaf_name)
		else:
			# Already attacking (multi-strike combo, back-to-back actions). Use an
			# authored direct transition when there is one (keeps its at-end
			# timing and crossfade), otherwise jump straight to the clip: travel()
			# would path through the other attack clips, playing them and firing
			# their hit frames on the way.
			var current_leaf := ca_sm.get_current_node()
			if current_leaf != StringName(leaf_name) and ca_node.has_transition(current_leaf, leaf_name):
				ca_sm.travel(leaf_name)
			else:
				ca_sm.start(leaf_name)
		_snap_animation()

		# Resolve clip duration and schedule hit_moment at the correct frame.
		var resolved_clip_name = _resolve_state_animation_name(leaf_name)
		
		return true

	# Root-level state. From combat_actions, travel() waits on its at-end exit
	# (combat_actions -> idle1), except for death, which every state reaches
	# immediately.
	if not root_sm.has_node(resolved_name):
		push_error("[Battler] Animation state '%s' does not exist on '%s'" % [resolved_name, character_name])
		return false
	state_machine.travel(resolved_name)
	_snap_animation()
	return true

## Lets a stepped (12fps) AnimationTree show a just-requested change on the next
## frame instead of at its next step.
func _snap_animation() -> void:
	if anim_tree and anim_tree.has_method("request_snap"):
		anim_tree.request_snap()

## Looks up the length of an animation from AnimationPlayer by state name.
## Searches all animation libraries if a direct match is not found.
## Returns 1.0 as a safe fallback if the animation cannot be found.
func _get_animation_duration(anim_name: String) -> float:
	var anim_player = get_node_or_null("AnimationPlayer")
	if not anim_player:
		return 1.0
	
	# Resolve state name -> actual animation clip name from AnimationTree state machine.
	# Example: "attack" state may map to "Locomotion-Library/attack1".
	var resolved_name = _resolve_state_animation_name(anim_name)
	if not resolved_name.is_empty() and anim_player.has_animation(resolved_name):
		return anim_player.get_animation(resolved_name).length
	
	# Try direct name match first
	if anim_player.has_animation(anim_name):
		return anim_player.get_animation(anim_name).length
	# Search all libraries for an animation whose short name matches
	for lib_name in anim_player.get_animation_library_list():
		var lib = anim_player.get_animation_library(lib_name)
		for anim in lib.get_animation_list():
			if anim == anim_name:
				var full_name = (lib_name + "/" + anim) if lib_name != "" else anim
				return anim_player.get_animation(full_name).length
	return 1.0  # Fallback if animation not found

## Gets the time position of the hit moment from the animation method track.
## Searches for the method track that calls "_on_attack_hit" and returns its time.
## Returns 0.0 if no hit moment is found in the animation.
## Least time after a strike's last hit frame before the next strike may cut in.
const STRIKE_FOLLOW_THROUGH := 0.1

## Clip time (seconds) at which the next strike of a combo takes over from
## attack slot [param anim_name]: the clip's _on_attack_end key (where the
## attack itself ends and the recovery starts), [param lead] seconds early,
## but never sooner than STRIKE_FOLLOW_THROUGH after its last hit. The clip
## length when it has no attack-end key.
func get_strike_release_time(anim_name: String, lead: float = 0.0) -> float:
	var clip_name := _resolve_state_animation_name(anim_name)
	if not anim_tree or clip_name.is_empty() or not anim_tree.has_animation(clip_name):
		return _get_animation_duration(anim_name)
	var clip := anim_tree.get_animation(clip_name)
	var attack_end := clip.length
	var last_hit := 0.0
	for t in clip.get_track_count():
		if clip.track_get_type(t) != Animation.TYPE_METHOD:
			continue
		for k in clip.track_get_key_count(t):
			match clip.method_track_get_name(t, k):
				&"_on_attack_end":
					attack_end = minf(attack_end, clip.track_get_key_time(t, k))
				&"_on_attack_hit":
					last_hit = maxf(last_hit, clip.track_get_key_time(t, k))
	return clampf(maxf(attack_end - lead, last_hit + STRIKE_FOLLOW_THROUGH), 0.0, clip.length)

## Waits until attack slot [param anim_name] has played to [param clip_time]
## (by the clip's own clock, so hit-stop freezes and 12fps stepping can't
## desync it), or has stopped playing. Gives up after [param max_wait] seconds.
func await_attack_clip_time(anim_name: String, clip_time: float, max_wait: float = 5.0) -> void:
	var ca := anim_tree.get("parameters/BaseSM/combat_actions/playback") as AnimationNodeStateMachinePlayback if anim_tree else null
	if not ca:
		return
	var deadline := Time.get_ticks_msec() + int(max_wait * 1000.0)
	while Time.get_ticks_msec() < deadline and is_instance_valid(self):
		if state_machine.get_current_node() != &"combat_actions" or ca.get_current_node() != StringName(anim_name):
			return
		if ca.get_current_play_position() >= clip_time - 0.001:
			return
		await get_tree().process_frame

func _get_hit_moment_time(anim_name: String) -> float:
	var anim_player = get_node_or_null("AnimationPlayer")
	if not anim_player:
		return 0.0
	
	# Resolve state name -> actual animation clip name
	var resolved_name = _resolve_state_animation_name(anim_name)
	var anim_name_to_use = resolved_name if not resolved_name.is_empty() else anim_name
	
	# Try to get the animation
	var animation = null
	if anim_player.has_animation(anim_name_to_use):
		animation = anim_player.get_animation(anim_name_to_use)
	else:
		# Search all libraries
		for lib_name in anim_player.get_animation_library_list():
			var lib = anim_player.get_animation_library(lib_name)
			for anim in lib.get_animation_list():
				if anim == anim_name:
					var full_name = (lib_name + "/" + anim) if lib_name != "" else anim
					animation = anim_player.get_animation(full_name)
					break
			if animation:
				break
	
	if not animation:
		return 0.0
	
	# Find the method track that calls "_on_attack_hit"
	for track_idx in animation.get_track_count():
		if animation.track_get_type(track_idx) == Animation.TYPE_METHOD:
			for key_idx in animation.track_get_key_count(track_idx):
				var key_time = animation.track_get_key_time(track_idx, key_idx)
				var key_value = animation.track_get_key_value(track_idx, key_idx)
				# Check if this key calls _on_attack_hit
				if key_value is Dictionary and key_value.has("method"):
					var method_name = key_value["method"]
					if method_name == "_on_attack_hit":
						return key_time
	
	return 0.0  # No hit moment found

## Resolves an AnimationTree state name to the actual AnimationPlayer clip name
## assigned inside the matching AnimationNodeAnimation node.
## Checks the combat_actions sub-machine first, then root-level states.
## Returns empty string if the state cannot be found or is not a clip node.
func _resolve_state_animation_name(state_name: String) -> String:
	if not anim_tree:
		return ""

	# The hit flinch clip lives outside BaseSM, on the HitShot's "Hit" input.
	if state_name == AnimationMapping.HIT:
		var hit_node := (anim_tree.tree_root as AnimationNodeBlendTree).get_node(HIT_CLIP_NODE) as AnimationNodeAnimation \
			if (anim_tree.tree_root as AnimationNodeBlendTree).has_node(HIT_CLIP_NODE) else null
		return str(hit_node.animation) if hit_node else ""

	# Get the BaseSM state machine from the BlendTree
	var root_sm := anim_tree.tree_root.get_node("BaseSM") as AnimationNodeStateMachine
	if not root_sm:
		return ""

	# Strip sub-machine prefix if present (e.g. "combat_actions/melee_combo_1").
	var leaf := state_name
	if state_name.begins_with("combat_actions/") or state_name.begins_with("basic_attacks/"):
		leaf = state_name.get_slice("/", 1)

	# All offensive slots live inside the combat_actions sub-machine.
	var combat_slots: Array = [
		AnimationMapping.MELEE_COMBO_1, AnimationMapping.MELEE_COMBO_2, AnimationMapping.MELEE_COMBO_3,
		AnimationMapping.RANGED_CAST_1, AnimationMapping.RANGED_CAST_2,
	]
	if leaf in combat_slots:
		for sm_name in ["combat_actions", "basic_attacks"]:
			if root_sm.has_node(sm_name):
				var sub_sm := root_sm.get_node(sm_name) as AnimationNodeStateMachine
				if sub_sm and sub_sm.has_node(leaf):
					var anim_node := sub_sm.get_node(leaf) as AnimationNodeAnimation
					if anim_node and str(anim_node.animation) != "":
						return str(anim_node.animation)

	# Root-level states (idle1, walk, dodge, parry, jump, hit, death, …)
	var lookup := leaf if leaf != state_name else state_name
	if root_sm.has_node(lookup):
		var anim_node := root_sm.get_node(lookup) as AnimationNodeAnimation
		if anim_node and str(anim_node.animation) != "":
			return str(anim_node.animation)

	return ""

## Resolve a generic animation name to a character-specific animation using animation mapping
## If no mapping exists, returns the original generic name
func get_resolved_animation(generic_name: String) -> String:
	if generic_name.is_empty():
		return generic_name
	
	if animation_mapping:
		var resolved = animation_mapping.resolve_animation(generic_name)
		return resolved
	
	# No animation mapping, return original name
	return generic_name

func _on_advance_complete():
	set_advancing(false)
	rotation = original_rotation
	# Reset animation speed to normal after synced movement
	_set_base_time_scale(1.0)
	# NOTE: Do NOT travel to idle1 here - it fights whatever the caller triggers next

## Start movement timeout to prevent stuck advancing state
func _start_movement_timeout() -> void:
	var battle_manager = get_tree().get_first_node_in_group("battle_manager")
	if not battle_manager:
		return
	
	var timeout = stuck_movement_timeout
	
	await get_tree().create_timer(timeout / battle_manager.speed_multiplier).timeout
	
	# Check if still advancing (means it got stuck)
	if is_advancing:
		set_advancing(false)
		# Don't return to original position - this interrupts normal movement
		# Just stop the advance and let the caller handle the next step

func return_to_original_position():
	if is_advancing or global_position.distance_to(original_position) < 0.05:
		return

	var battle_manager = get_tree().get_first_node_in_group("battle_manager")
	if not battle_manager:
		return

	var movement_speed = custom_movement_speed
	movement_speed *= battle_manager.speed_multiplier

	set_advancing(true)
	_try_animation(AnimationMapping.WALK_BACK)

	# Time walk_back so it starts with the move and ends on arrival
	var fit := _fit_locomotion(AnimationMapping.WALK_BACK, global_position.distance_to(original_position) / movement_speed)

	# Wait for animation to start before beginning movement
	await get_tree().process_frame

	var return_yaw := original_rotation.y
	return_yaw = rotation.y + wrapf(return_yaw - rotation.y, -PI, PI)

	var tween = create_tween().set_parallel(true)
	_tween_move(tween, global_position, original_position, fit)
	tween.tween_property(self, "rotation:y", return_yaw, fit["duration"])
	tween.chain().tween_callback(_on_return_complete)

	_set_base_time_scale(fit["scale"])

## Performs a backwards evasion dash with the dedicated dodge animation.
## Falls back to walk if no dodge state exists on this character's AnimationTree.
func perform_dodge_dash() -> void:
	if is_advancing:
		return

	var battle_manager = get_tree().get_first_node_in_group("battle_manager")
	if not battle_manager:
		return

	# Store current position before dodge
	var dodge_start_position = global_position

	# Calculate backward direction (opposite to current facing direction)
	var backward_direction = -global_transform.basis.z.normalized()

	# Fixed dodge distance
	var dodge_distance = 2.0
	var dodge_target_position = global_position + backward_direction * dodge_distance

	# Move camera back to keep dodging battler in frame - smooth zoom out
	if battle_manager.battle_camera:
		battle_manager.battle_camera.adjust_camera_distance_for_evasion(1.0, 0.15)

	set_advancing(true)
	# The dodge clip, or a back-step with walk_back for characters without one
	var base_sm := anim_tree.tree_root.get_node("BaseSM") as AnimationNodeStateMachine if anim_tree else null
	var anim_name := AnimationMapping.DODGE if base_sm and base_sm.has_node(AnimationMapping.DODGE) else AnimationMapping.WALK_BACK
	_try_animation(anim_name)

	var movement_speed = custom_movement_speed
	movement_speed *= battle_manager.speed_multiplier * 1.5  # Faster movement for dodge

	# Time the dodge so its travel happens with the dash and ends on arrival
	var fit := _fit_locomotion(anim_name, global_position.distance_to(dodge_target_position) / movement_speed)

	# Wait for animation to start before beginning movement
	await get_tree().process_frame

	var tween = create_tween()
	_tween_move(tween, global_position, dodge_target_position, fit)
	tween.tween_callback(_on_dodge_dash_complete.bind(dodge_start_position))

	_set_base_time_scale(fit["scale"])

func _on_dodge_dash_complete(p_original_position: Vector3):
	# Reset animation speed to normal after dodge
	_set_base_time_scale(1.0)

	# Small pause at the end of dodge
	await get_tree().create_timer(0.15).timeout

	# Return to original position
	var battle_manager = get_tree().get_first_node_in_group("battle_manager")
	if not battle_manager:
		set_advancing(false)
		_try_animation("idle1")
		return

	var movement_speed = custom_movement_speed
	movement_speed *= battle_manager.speed_multiplier

	# Step forward back into place with the walk, timed to the move
	_try_animation(AnimationMapping.WALK)
	var fit := _fit_locomotion(AnimationMapping.WALK, global_position.distance_to(p_original_position) / movement_speed)
	var tween = create_tween()
	_tween_move(tween, global_position, p_original_position, fit)
	tween.tween_callback(_on_dodge_return_complete)
	_set_base_time_scale(fit["scale"])

func _on_dodge_return_complete() -> void:
	_on_return_complete()
	# Nothing else drives the defender after a dodge, so settle back to idle here
	_try_animation("idle1")

func _on_return_complete():
	set_advancing(false)
	rotation = original_rotation

	# Reset animation speed to normal after synced movement
	_set_base_time_scale(1.0)

	# Reset camera distance after dodge is complete
	var battle_manager = get_tree().get_first_node_in_group("battle_manager")
	if battle_manager and battle_manager.battle_camera:
		battle_manager.battle_camera.reset_camera_distance()

	# NOTE: Do NOT travel to idle1 here - it fights whatever the caller triggers next

## How high a jump evasion lifts the battler (meters, peak above the ground),
## counting any height the jump clip itself already gives the body.
const JUMP_HEIGHT := 1.8
## Bones whose lowest point decides when a jump clip leaves / touches the ground.
const JUMP_FOOT_BONES: Array[StringName] = [&"LeftFoot", &"RightFoot"]
## Share of the feet's highest lift that counts as "off the ground".
const JUMP_AIRBORNE_THRESHOLD := 0.25

## Shared jump timing: every battler's jump clip is time-warped, phase by
## phase, to these so all jumps feel the same whatever their clip. They are
## whole 12fps animation steps (1/12 s), so every phase starts exactly on a
## step for every battler instead of rounding to whichever step is nearest.
## Crouch until the feet leave the ground (3 steps):
const JUMP_TAKEOFF_TIME := 3.0 / 12.0
## Feet off the ground, the body's arc (5 steps):
const JUMP_AIR_TIME := 5.0 / 12.0
## From touch-down until the blend back to idle starts (3 steps):
const JUMP_LANDING_TIME := 3.0 / 12.0

## Each jump phase boundary (feet leaving / touching the ground, the idle blend
## triggering) is placed half a 12fps step's worth of clip past the exact
## moment, so the step that starts the phase always shows it: frame jitter is
## smaller than half a step, and the step before can't reach it.
const JUMP_PHASE_STEP := 1.0 / 12.0

var _jump_window_cache: Dictionary = {}

## Performs a jump evasion (avoids ground-sweeping attacks) with the single
## jump clip: crouch, take-off, air, landing. Each phase of the clip is played
## at the speed that fits the shared JUMP_*_TIME timing, so every battler
## leaves the ground, lands and returns to idle at the same moments; the body
## is lifted only during the air phase. jump -> idle1 follows by itself.
## Falls back to a plain arc when there is no jump state.
func perform_jump_evade() -> void:
	# Move camera back to keep jumping battler in frame - smooth zoom out
	var battle_manager = get_tree().get_first_node_in_group("battle_manager")
	if battle_manager and battle_manager.battle_camera:
		battle_manager.battle_camera.adjust_camera_distance_for_evasion(0.8, 0.2)

	var window := _get_jump_air_window()
	if not window.is_empty():
		var start_y := global_position.y
		var height: float = window["arc_height"]
		var total := JUMP_TAKEOFF_TIME + JUMP_AIR_TIME + JUMP_LANDING_TIME
		_try_animation(AnimationMapping.JUMP)
		# The shared timeline starts when the jump clip does (the next frame)
		var started_usec := -1
		var deadline := Time.get_ticks_msec() + 3000
		while is_instance_valid(self) and not _is_despawning and Time.get_ticks_msec() < deadline:
			await get_tree().process_frame
			var in_jump := state_machine.get_current_node() == StringName(AnimationMapping.JUMP)
			if started_usec < 0:
				if not in_jump:
					continue
				started_usec = Time.get_ticks_usec()
			var elapsed := (Time.get_ticks_usec() - started_usec) / 1e6
			# Body: rises and falls during the air phase only
			var air := (elapsed - JUMP_TAKEOFF_TIME) / JUMP_AIR_TIME
			global_position.y = start_y + (4.0 * height * air * (1.0 - air) if air > 0.0 and air < 1.0 else 0.0)
			# Keep pacing until the clip reaches its exit (its blend back to idle
			# starts by itself), even if the last 12fps step lands just after
			if not in_jump or elapsed >= total + 0.25:
				break
			# Clip: aim its next (12fps) step at where the shared timeline says the
			# clip should be then, so crouch / air / landing line up with the body
			var ahead := get_process_delta_time()
			if "just_stepped" in anim_tree:
				ahead = maxf(1.0 / anim_tree.target_fps - anim_tree._accumulator, 0.001)
			var step: float = 1.0 / anim_tree.target_fps if "target_fps" in anim_tree else ahead
			var target := _jump_clip_time(window, elapsed + ahead)
			_set_base_time_scale(clampf((target - state_machine.get_current_play_position()) / step, 0.0, 4.0))
		if is_instance_valid(self):
			global_position.y = start_y
			if not _is_despawning:
				# The blend back to idle runs at normal speed
				_set_base_time_scale(1.0)

		# Reset camera distance after jump is complete
		if battle_manager and battle_manager.battle_camera:
			battle_manager.battle_camera.reset_camera_distance()
	else:
		# Fallback: tween a simple vertical arc when character has no jump clip.
		var jump_height := 1.8
		var jump_duration := 0.45
		var start_y := global_position.y
		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(self, "global_position:y", start_y + jump_height, jump_duration * 0.5) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		await get_tree().create_timer(jump_duration * 0.5).timeout
		var tween2 := create_tween()
		tween2.tween_property(self, "global_position:y", start_y, jump_duration * 0.5) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		await tween2.finished

		# Reset camera distance after jump is complete
		if battle_manager and battle_manager.battle_camera:
			battle_manager.battle_camera.reset_camera_distance()

## Where the jump clip should be [param elapsed] seconds into the shared jump
## timeline: each phase of the clip (window from _get_jump_air_window) is
## stretched over its JUMP_*_TIME.
func _jump_clip_time(window: Dictionary, elapsed: float) -> float:
	if elapsed < JUMP_TAKEOFF_TIME:
		return window["takeoff"] * elapsed / JUMP_TAKEOFF_TIME
	elapsed -= JUMP_TAKEOFF_TIME
	if elapsed < JUMP_AIR_TIME:
		return lerpf(window["takeoff"], window["landing"], elapsed / JUMP_AIR_TIME)
	elapsed -= JUMP_AIR_TIME
	return lerpf(window["landing"], window["exit"], minf(elapsed / JUMP_LANDING_TIME, 1.0))

## When the jump clip's feet leave and touch the ground, read from the clip:
## {takeoff, landing, exit} in clip seconds (exit = where its automatic blend
## back to idle starts), and arc_height, how far to lift the battler so the
## body peaks JUMP_HEIGHT up with the clip's own hip motion. Empty without a
## jump state.
func _get_jump_air_window() -> Dictionary:
	var base_sm := anim_tree.tree_root.get_node("BaseSM") as AnimationNodeStateMachine if anim_tree else null
	if not state_machine or not base_sm or not base_sm.has_node(AnimationMapping.JUMP):
		return {}
	var node := base_sm.get_node(AnimationMapping.JUMP) as AnimationNodeAnimation
	if not node or not anim_tree.has_animation(node.animation):
		return {}
	if _jump_window_cache.has(node.animation):
		return _jump_window_cache[node.animation]

	var clip := anim_tree.get_animation(node.animation)
	# Unreadable clip / skeleton: assume a quick hop in the middle of the clip
	var window := {"takeoff": clip.length * 0.2, "landing": clip.length * 0.6, "arc_height": JUMP_HEIGHT}
	var skeletons := find_children("*", "Skeleton3D", true, false)
	if not skeletons.is_empty():
		var sk := skeletons[0] as Skeleton3D
		var feet: Array[int] = []
		for bone in JUMP_FOOT_BONES:
			if sk.find_bone(bone) >= 0:
				feet.append(sk.find_bone(bone))
		var hips := sk.find_bone(&"Hips")
		if not feet.is_empty():
			var tracks := _bone_tracks(clip)
			var samples := 60
			var foot_y := PackedFloat32Array()
			var hips_y := PackedFloat32Array()
			for i in samples + 1:
				var t := clip.length * i / samples
				var lowest := INF
				for f in feet:
					lowest = minf(lowest, (sk.global_transform * _clip_bone_pose(clip, sk, tracks, f, t)).origin.y)
				foot_y.append(lowest)
				hips_y.append((sk.global_transform * _clip_bone_pose(clip, sk, tracks, hips, t)).origin.y if hips >= 0 else 0.0)
			var peak := 0
			for i in foot_y.size():
				if foot_y[i] > foot_y[peak]:
					peak = i
			var rise := foot_y[peak] - foot_y[0]
			if rise > 0.05:
				var threshold := foot_y[0] + rise * JUMP_AIRBORNE_THRESHOLD
				var takeoff := peak
				while takeoff > 0 and foot_y[takeoff - 1] > threshold:
					takeoff -= 1
				var landing := peak
				while landing < samples and foot_y[landing + 1] > threshold:
					landing += 1
				# Arc height that puts the body's highest point (arc + the clip's own
				# hip motion at the same moment) exactly JUMP_HEIGHT up
				var span := float(landing + 1 - takeoff)
				var peak_for := func(h: float) -> float:
					var best := -INF
					for i in range(takeoff, landing + 1):
						var p := (i - takeoff) / span
						best = maxf(best, 4.0 * h * p * (1.0 - p) + hips_y[i] - hips_y[0])
					return best
				var lo := 0.0
				var hi := JUMP_HEIGHT * 2.0
				for _i in 30:
					var mid := (lo + hi) * 0.5
					if peak_for.call(mid) < JUMP_HEIGHT:
						lo = mid
					else:
						hi = mid
				# Exact crossing moments (between samples)
				var cross := func(a: int, b: int) -> float:
					var f := clampf((threshold - foot_y[a]) / (foot_y[b] - foot_y[a]), 0.0, 1.0) if foot_y[b] != foot_y[a] else 0.0
					return clip.length * (a + f) / samples
				var takeoff_time: float = cross.call(maxi(takeoff - 1, 0), takeoff)
				var landing_time: float = cross.call(landing, mini(landing + 1, samples))
				window = {"takeoff": takeoff_time, "landing": landing_time, "arc_height": lo}
	# Where the automatic blend back to idle triggers
	var trigger := maxf(clip.length - _at_end_exit_fade(base_sm, AnimationMapping.JUMP), window["landing"] + 0.01)
	# Each boundary moves m past its exact moment, m being half of what one step
	# advances the clip in the phase that ends there (that phase grows by m too:
	# m = 0.5 * (span + m) / steps  ->  m = 0.5 * span / (steps - 0.5))
	var half_step_margin := func(span: float, phase_time: float) -> float:
		return 0.5 * maxf(span, 0.0) / maxf(phase_time / JUMP_PHASE_STEP - 0.5, 0.5)
	window["takeoff"] += half_step_margin.call(window["takeoff"], JUMP_TAKEOFF_TIME)
	window["landing"] += half_step_margin.call(window["landing"] - window["takeoff"], JUMP_AIR_TIME)
	trigger = maxf(trigger, window["landing"] + 0.01)
	window["exit"] = minf(trigger + half_step_margin.call(trigger - window["landing"], JUMP_LANDING_TIME), clip.length)
	_jump_window_cache[node.animation] = window
	return window

## {bone name: {position: track, rotation: track}} for a clip's bone tracks.
static func _bone_tracks(clip: Animation) -> Dictionary:
	var map := {}
	for t in clip.get_track_count():
		var kind := clip.track_get_type(t)
		if kind != Animation.TYPE_POSITION_3D and kind != Animation.TYPE_ROTATION_3D:
			continue
		var bone := clip.track_get_path(t).get_concatenated_subnames()
		if not map.has(bone):
			map[bone] = {}
		map[bone]["position" if kind == Animation.TYPE_POSITION_3D else "rotation"] = t
	return map

## Skeleton-space pose of [param bone] at [param time] of [param clip], from
## the clip's tracks and the skeleton's rest pose (no AnimationTree needed).
static func _clip_bone_pose(clip: Animation, sk: Skeleton3D, tracks: Dictionary, bone: int, time: float) -> Transform3D:
	var chain: Array[int] = []
	var b := bone
	while b >= 0:
		chain.push_front(b)
		b = sk.get_bone_parent(b)
	var pose := Transform3D.IDENTITY
	for i in chain:
		var rest := sk.get_bone_rest(i)
		var bone_tracks: Dictionary = tracks.get(sk.get_bone_name(i), {})
		var origin := rest.origin
		if bone_tracks.has("position"):
			origin = clip.position_track_interpolate(bone_tracks["position"], time) * sk.motion_scale
		var rotation := rest.basis.get_rotation_quaternion()
		if bone_tracks.has("rotation"):
			rotation = clip.rotation_track_interpolate(bone_tracks["rotation"], time)
		pose = pose * Transform3D(Basis(rotation).scaled(rest.basis.get_scale()), origin)
	return pose

# # #
# Animation Damage & Effects Application
# # #
## Called when animation reaches the hit point (either via animation event track or timer) - applies damage and any attached states
func apply_animation_effects():
	hit_moment.emit(self)

# # #
# Save System
# # #
func on_save_game(save_data):
	var new_data = BattlerData.new()
	new_data.current_health = current_health  # Using consistent property name

	new_data.current_exp = current_exp
	new_data.current_level = current_level
	
	save_data["charNameOrID"] = new_data

func on_load_game(load_data):
	var save_data = load_data["charNameOrID"] as BattlerData
	if save_data == null: 
		return
	
	current_health = save_data.current_health  # Using consistent property name

	current_exp = save_data.current_exp
	current_level = save_data.current_level
	calculate_exp_for_next_level()
	apply_level_progression()

var active_states: Dictionary = {}  # {state_name: State}

## Current HP as a fraction of max HP (0 when max HP is 0).
func get_health_ratio() -> float:
	return float(current_health) / float(max_health) if max_health > 0 else 0.0

## Whether a state named [param state_name] is on this battler.
func has_state(state_name: String) -> bool:
	return active_states.has(state_name)

# And add these helper functions for state management
## Puts [param state] on this battler. [param source] is the battler that
## applied it (null for environment/system states).
func apply_state(state: State, source: Node = null) -> void:
	# A defeated battler takes no new states
	if state == null or is_defeated():
		return
	
	var key = state.state_name
	var existing_state = active_states.get(key) as State
	
	# Get battle manager for vestige hooks
	var battle_manager = get_tree().get_first_node_in_group("battle_manager")
	
	if existing_state:
		# Already on: the state folds the new application in (stacks, shield
		# hits, a refreshed duration...)
		existing_state.merge(state, self)
		if is_instance_valid(source):
			existing_state.source = source
	else:
		# New state - apply directly
		var state_copy = state.duplicate()
		# Force state_name to be set properly after duplication
		state_copy.state_name = state.state_name
		# A stacking state starts with 1 to its cap; others carry no stacks
		state_copy.stack_count = clampi(state.stack_count, 1, state.stack_max) if state_copy.uses_stacks() else 0
		state_copy.source = source
		active_states[key] = state_copy
		
		state_copy.show_visuals(self)
		state_copy.on_applied(self)

	state_applied.emit(key)
	states_changed.emit()

	# The events carry the state as it now is on this battler
	var live: State = active_states.get(key)
	var reapplied := existing_state != null
	notify_battle_event(BattleEvents.STATE_APPLIED, {"state": live, "state_name": key, "target": self, "source": source, "reapplied": reapplied, "battle_manager": battle_manager})
	if source is Battler and source != self and is_instance_valid(source):
		source.notify_battle_event(BattleEvents.STATE_INFLICTED, {"target": self, "state": live, "state_name": key, "reapplied": reapplied, "battle_manager": battle_manager})

## Hits this battler's states will block (the shield row).
func get_shield_hits() -> int:
	var hits := 0
	for state in active_states.values():
		if state is State:
			hits += state.get_shield_hits()
	return hits

## Takes every state off this battler.
func clear_states() -> void:
	for state_name in active_states.keys():
		remove_state(state_name)

## Takes off the states [param predicate] (a [code]func(state) -> bool[/code])
## accepts, oldest first, at most [param max_count] of them (0 = all).
## Returns the names of those removed.
func remove_states_if(predicate: Callable, max_count: int = 0) -> Array[String]:
	var removed: Array[String] = []
	for state_name in active_states.keys():
		if max_count > 0 and removed.size() >= max_count:
			break
		var state = active_states.get(state_name)
		if state is State and predicate.call(state):
			remove_state(state_name)
			removed.append(state_name)
	return removed

func remove_state(state_name: String) -> void:
	if active_states.has(state_name):
		var state = active_states[state_name]
		active_states.erase(state_name)
		if state is State:
			state.hide_visuals(self)
			state.on_removed(self)
		state_removed.emit(state_name)
		states_changed.emit()
		notify_battle_event(BattleEvents.STATE_REMOVED, {"state": state, "state_name": state_name})

enum EffectPosition { CENTER, TOP, BOTTOM }

## Get a position for visual effects (auras, particles, indicators, etc.)
## Returns the specified vertical position of the battler's mesh in local coordinates
## Combines AABBs of all MeshInstance3D children for accurate position calculation
## Uses caching to avoid recalculating on every call
## position_type: EffectPosition.CENTER, EffectPosition.TOP, or EffectPosition.BOTTOM
func get_effect_position(position_type: EffectPosition = EffectPosition.CENTER) -> Vector3:
	# Calculate and cache all positions if not already cached
	if not _effect_center_cached:
		_calculate_effect_positions()
	
	match position_type:
		EffectPosition.CENTER:
			return _cached_effect_center
		EffectPosition.TOP:
			return _cached_effect_top
		EffectPosition.BOTTOM:
			return _cached_effect_bottom
		_:
			return _cached_effect_center

## Calculate and cache all effect positions
func _calculate_effect_positions() -> void:
	# Battler-local, like the children (auras, indicators) placed with them
	var box := get_combined_aabb()
	_cached_effect_center = Vector3(0, box.position.y + box.size.y / 2.0, 0)
	_cached_effect_top = Vector3(0, box.position.y + box.size.y, 0)
	_cached_effect_bottom = Vector3(0, box.position.y, 0)
	_cached_effect_depth = box.size.z
	
	_effect_center_cached = true

## Get the battler's depth (Z size) for effect positioning
## Returns the combined AABB depth of all MeshInstance3D children
func get_effect_depth() -> float:
	# Calculate and cache if not already cached
	if not _effect_center_cached:
		_calculate_effect_positions()
	return _cached_effect_depth

## Invalidate the cached effect positions
## Call this when meshes are added/removed from the battler
func invalidate_effect_cache() -> void:
	_effect_center_cached = false

## The target's bounding box size in world units (its scale included), for
## the attack stop distance
func _get_target_aabb_size(target: Battler) -> Vector3:
	return target.get_combined_aabb().size * target.global_transform.basis.get_scale().abs()

## Bounding box of every visible mesh, in this battler's local space (its own
## rotation and scale excluded), so global_transform * get_combined_aabb() is
## the box in the world. Each mesh's box is moved by the mesh's offset from the
## battler, so offset, rotated or scaled meshes (weapons, props, imported rigs)
## land where they really are. Rigged meshes report their rest pose. Falls
## back to a 1 x 1.5 x 1 box standing on the origin.
func get_combined_aabb() -> AABB:
	var to_local := global_transform.affine_inverse()
	var combined := AABB()
	var has_mesh := false
	for child in find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		if mesh_instance.mesh == null or not mesh_instance.is_visible_in_tree():
			continue
		var box := (to_local * mesh_instance.global_transform) * mesh_instance.get_aabb()
		combined = box if not has_mesh else combined.merge(box)
		has_mesh = true
	if not has_mesh:
		return AABB(Vector3(-0.5, 0, -0.5), Vector3(1.0, 1.5, 1.0))
	return combined

## Calculate the dynamic stop distance based on target's AABB
## Returns the distance to stop at the edge of target's hit zone
func get_target_stop_distance(target: Battler) -> float:
	var target_aabb_size = _get_target_aabb_size(target)
	var attacker_reach = 0.5  # Attacker's reach distance
	var buffer = 0.2  # Small buffer to prevent clipping
	
	# Calculate stop distance based on target's Z size (depth)
	var stop_distance = target_aabb_size.z / 2.0 + attacker_reach + buffer
	
	# Clamp to reasonable bounds
	stop_distance = clamp(stop_distance, 1.0, 4.0)
	
	return stop_distance

## Save the current position as the original position to return to after attacks
## This should be called at the start of each turn before any movement
func save_original_position() -> void:
	if _original_position_saved_this_turn:
		return
	
	original_position = global_position
	original_rotation = rotation
	_original_position_saved_this_turn = true

## Reset the original position saved flag at the start of a new turn
func reset_original_position_flag() -> void:
	_original_position_saved_this_turn = false

## Apply an aura effect to this battler at the height center
## aura_scene: PackedScene to instantiate
## Returns the created aura instance
func apply_aura_effect(aura_scene: PackedScene) -> Node3D:
	if not aura_scene:
		return null
	
	var aura_instance = aura_scene.instantiate()
	var center_pos = get_effect_position(EffectPosition.CENTER)
	
	add_child(aura_instance)
	aura_instance.position = center_pos
	
	return aura_instance

## Remove an aura effect from this battler
## aura_instance: The aura node to remove
func remove_aura_effect(aura_instance: Node3D) -> void:
	if is_instance_valid(aura_instance):
		# Play close animation if available
		if aura_instance.has_node("AnimationPlayer"):
			var anim_player = aura_instance.get_node("AnimationPlayer")
			if anim_player:
				anim_player.play("close")
				await anim_player.animation_finished
		aura_instance.queue_free()

## Play healing effect when health increases
func _play_healing_effect() -> void:
	var healing_effect = load("res://assets/effects/auras/aura_healing.tscn") as PackedScene
	if not healing_effect:
		return
	
	var healing_instance = apply_aura_effect(healing_effect)
	if not healing_instance:
		return
	
	# Play open animation
	if healing_instance.has_node("AnimationPlayer"):
		var anim_player = healing_instance.get_node("AnimationPlayer")
		if anim_player:
			anim_player.play("open")
	
	# Auto-cleanup after effect finishes using the finished signal
	if healing_instance.has_signal("finished"):
		healing_instance.finished.connect(func():
			if is_instance_valid(healing_instance):
				remove_aura_effect(healing_instance)
		)
	else:
			# Fallback timer if no finished signal
			get_tree().create_timer(1.2).timeout.connect(func():
				if is_instance_valid(healing_instance):
					remove_aura_effect(healing_instance)
			)

## Start of this battler's turn: each state deals its turn damage (Burning,
## poison; negative heals) and does its upkeep, then durations tick down.
## Expired and used-up states are removed.
func process_states() -> void:
	var states_to_remove = []
	var killer: Node = null

	for state_name in active_states.keys():
		var state = active_states.get(state_name) as State
		if state == null:
			continue

		var turn_damage := state.get_turn_damage(self)
		if turn_damage > 0 and current_health > 0:
			if number_indicator:
				number_indicator.show_damage(turn_damage)
			# Not an attack: nothing blocks or reacts to it, but it's damage
			# taken (and dealt, by whoever put the state on) like any other
			_lose_health({"attacker": _state_source(state), "damage": turn_damage,
					"damage_type": "state", "element": "none", "is_attack": false,
					"is_critical": false, "battle_manager": get_tree().get_first_node_in_group("battle_manager"),
					"state": state})
			if current_health <= 0 and killer == null:
				killer = _state_source(state)
		# Regen: a heal like any other (healing multipliers, the HEALED event)
		var turn_heal := state.get_turn_heal(self)
		if turn_heal > 0 and current_health > 0:
			var healed: int = take_healing(turn_heal)
			if healed > 0 and number_indicator:
				number_indicator.show_heal(healed)
		state.on_turn_tick(self)

		# Handle duration
		if state.turns_active > 0:
			state.turns_active -= 1
			if state.turns_active <= 0:
				states_to_remove.append(state_name)
		if state.is_expired() and not states_to_remove.has(state_name):
			states_to_remove.append(state_name)

	# Remove expired states
	for state_name in states_to_remove:
		remove_state(state_name)
	# Durations and stacks ticked
	states_changed.emit()

	# A state's damage defeated this battler: the same defeat as a hit
	if current_health <= 0:
		await _handle_defeat(killer)


## Whoever put [param state] on, if they're still around.
func _state_source(state: State) -> Node:
	return state.source if is_instance_valid(state.source) else null


func set_advancing(value: bool):
	is_advancing = value

func set_defending(value: bool):
	is_defending = value

## Plays the death state (reachable from every BaseSM state) at normal speed.
## Returns the clip length in seconds.
func _play_death_animation() -> float:
	_set_base_time_scale(1.0)
	_try_animation(AnimationMapping.DEATH)
	return _get_animation_duration(AnimationMapping.DEATH)

func _fade_and_remove() -> void:
	# Play death animation instead of scaling down
	var death_duration := _play_death_animation()
	if death_duration > 0.0:
		await get_tree().create_timer(death_duration).timeout

	# Safety check: ensure the node hasn't already been destroyed by a scene change
	if is_instance_valid(self):
		queue_free()

## Apply level-based stat scaling to this battler
## Called on _ready() and after level up
func apply_level_progression() -> void:
	if not stats:
		return
	
	# Calculate stats based on level and multipliers
	var base_stats = {
		"max_health": stats.max_health,
		"attack": stats.attack,
		"defense": stats.defense,
		"agility": stats.agility,
		"magic": stats.magic,
		"max_ap": stats.max_ap
	}
	
	var stat_multipliers = {
		"max_health": stats.health_multiplier,
		"attack": stats.attack_multiplier,
		"defense": stats.defense_multiplier,
		"agility": stats.agility_multiplier,
		"magic": stats.magic_multiplier,
		"max_ap": stats.ap_multiplier
	}
	
	# Get calculated stats at current level
	var calculated = LevelProgression.get_stats_at_level(base_stats, stat_multipliers, current_level)
	
	# Base stats, then every modifier source (weapon, vestiges) on top
	_base_stats = {
		"max_health": calculated["max_health"],
		"attack": calculated["attack"],
		"defense": calculated["defense"],
		"agility": calculated["agility"],
		"magic": calculated["magic"],
		"crit_chance": stats.crit_chance,
		"max_ap": calculated.get("max_ap", stats.max_ap),
		"ap_regen_per_turn": stats.ap_regen_per_turn,
	}
	refresh_stats()
	
	# Set current health to max if first time initialization
	if current_health == 0:
		current_health = max_health
		_is_initialized = true
	
	# Set current AP to max if first time initialization
	if current_ap == 0 or current_ap > max_ap:
		current_ap = max_ap
	
	ap_changed.emit(current_ap, max_ap)

# ============================================================================
# ACTION POINTS (AP) SYSTEM
# ============================================================================

func can_spend_ap(amount: int) -> bool:
	return current_ap >= amount

func spend_ap(amount: int) -> bool:
	if not can_spend_ap(amount):
		return false
	current_ap -= amount
	ap_changed.emit(current_ap, max_ap)
	return true

func regen_ap() -> void:
	current_ap = min(current_ap + ap_regen_per_turn, max_ap)
	ap_changed.emit(current_ap, max_ap)

func add_ap(amount: int) -> void:
	current_ap = min(current_ap + amount, max_ap)
	ap_changed.emit(current_ap, max_ap)

func reset_ap() -> void:
	current_ap = max_ap
	ap_changed.emit(current_ap, max_ap)

func get_current_ap() -> int:
	return current_ap

func get_max_ap() -> int:
	return max_ap

## Universal stat accessor for card effects, damage formulas, and external systems
func get_stat(stat_name: String) -> int:
	match stat_name.to_lower():
		"attack", "atk":
			return attack
		"defense", "def":
			return defense
		"agility", "agi", "speed":
			return agility
		"magic", "mag":
			return magic
		"crit_chance", "crit":
			return crit_chance
		"max_health", "max_hp":
			return max_health
		"current_health", "health", "hp":
			return current_health
		"max_ap":
			return max_ap
		"current_ap", "ap":
			return current_ap
		"level":
			return stats.level if stats else 1
		_:
			if stat_name in self:
				var val = get(stat_name)
				if val is int or val is float:
					return int(val)
			return 0
