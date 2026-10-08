class_name Battler
extends CharacterBody3D

signal hit_moment(attacker: Battler)
signal attack_start()
signal attack_end()
signal health_changed(current_health: int, max_health: int)
signal ap_changed(current_ap: int, max_ap: int)
signal state_applied(state_name: String)
signal state_removed(state_name: String)
signal bleed_proc_triggered(damage: int)
signal shield_broken()
signal shield_changed(shield_count: int)
signal burn_stack_changed(stack_count: int)
signal level_up(new_level: int)
signal exp_gained(amount: int, current_exp: int, exp_needed: int)
enum TEAM {ALLY, ENEMY}

@export_group("Stats Configuration")
@export var stats: BattlerStats ## Configuration for player/ally battlers
@export var enemy_stats: EnemyStats ## Configuration for enemy battlers

@export var inventory: Inventory
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
			
			# Play healing effect if health increased (but not during initialization)
			if value > old_value and _is_initialized:
				_play_healing_effect()
var is_defending: bool = false
var current_target = null
var is_counter_stunned: bool = false  # Stunned by being hit with a counter attack
var _is_despawning: bool = false

# Walking animation system
var is_advancing: bool = false
var advance_target_position: Vector3
var original_position: Vector3
var _counter_handled_return: bool = false

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

## Helper method to set animation tree conditions
func set_animation_condition(condition_name: String, value: bool) -> void:
	if anim_tree:
		print("[Battler %s] Setting %s = %s" % [character_name, condition_name, value])
		anim_tree.set("parameters/conditions/" + condition_name, value)
		print("[Battler %s] After set, %s = %s" % [character_name, condition_name, anim_tree.get("parameters/conditions/" + condition_name)])



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

var is_valid_target: bool = false
var is_default_target: bool = false
var is_keyboard_selected: bool = false  # Track if selected via keyboard
var is_mouse_selected: bool = false    # Track if selected via mouse

func _update_highlight() -> void:
	if _highlight_meshes.is_empty():
		return
	
	# Remove existing highlight overlay
	remove_overlay("highlight")
	
	if !is_selectable or !is_valid_target:
		return
	
	# Mouse hover takes priority over everything else
	if mouse_hover and is_selectable:
		# White hover outline (highest priority)
		var hover_mat = ShaderMaterial.new()
		hover_mat.shader = select_outline
		hover_mat.set_shader_parameter("color", Color.WHITE)
		hover_mat.set_shader_parameter("thickness", 0.02)
		hover_mat.set_shader_parameter("alpha", 0.6)
		add_overlay(OverlayType.HIGHLIGHT, hover_mat, 10, "highlight")
	elif is_targeted or is_mouse_selected or is_keyboard_selected or is_default_target:
		# Main selection outline (cyan for all input methods)
		var shader_mat = ShaderMaterial.new()
		shader_mat.shader = select_outline
		shader_mat.set_shader_parameter("color", Color.CYAN)
		shader_mat.set_shader_parameter("thickness", 0.025)
		shader_mat.set_shader_parameter("alpha", 1.0)
		add_overlay(OverlayType.HIGHLIGHT, shader_mat, 10, "highlight")

@export_group("Special Dependencies")
@onready var anim_tree: AnimationTree = $AnimationTree
var state_machine: AnimationNodeStateMachinePlayback
@export var number_indicator: NumberIndicator3D = null
@export var attack_indicator_scene: PackedScene = preload("res://scenes/battle/effects/attack_indicator/attack_indicator_3d.tscn")
var attack_indicator: AttackIndicator3D = null

@export_group("Counter Stun Settings", "stun")
## Duration (seconds) before recovering from being hit by a counter attack
@export var counter_stun_duration: float = 1.5

func _ready():
	_collect_meshes()
	
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
	
	state_machine = anim_tree.get("parameters/playback") as AnimationNodeStateMachinePlayback

	# Verify state_machine is valid
	if not state_machine:
		push_error("AnimationNodeStateMachinePlayback not found! Check AnimationTree setup.")
		return

	# Initialize animation conditions
	if anim_tree:
		anim_tree.set("parameters/conditions/allow_combat_to_idle", true)
	
	# Meshes are collected in _collect_meshes() at the start of _ready().
	# Material overrides with duplicated surface materials are set there;
	# no further setup is required here.
	
	if enemy_stats:
		team = TEAM.ENEMY
		character_name = enemy_stats.enemy_name
		max_health = enemy_stats.max_health
		current_health = max_health
		attack = enemy_stats.attack
		defense = enemy_stats.defense
		agility = enemy_stats.agility
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
	if target != self and is_targeted:
		deselect_as_target()

func check_hover_target(_target: Battler) -> void:
	SignalBus.clear_default_selection.emit()

func _clear_default_selection() -> void:
	# Clear this battler's default selection if it has one
	if is_default_target:
		is_default_target = false
		_update_highlight()

func select_target() -> void:
	# Will probably want to also add logic that prevents selecting invalid targets
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

func take_damage(amount: int, attacker: Battler = null) -> void:
	# Check for Protected state (shield) - ignores hit entirely
	if active_states.has("Protected"):
		var protected_state = active_states["Protected"] as ProtectedState
		if protected_state and protected_state.has_shield():
			# Consume one shield hit
			protected_state.consume_shield()
			# Show shield break visual
			if number_indicator:
				number_indicator.show_shield_break()
			# Emit signal for UI update
			shield_changed.emit(protected_state.get_remaining_shields())
			# Remove state if no shields left
			if not protected_state.has_shield():
				remove_state("Protected")
			# Return early - no damage taken, no effects applied
			return
	
	var damage_taken = max(1, amount) if amount > 0 else 0
	if is_defending:
		damage_taken = max(1, int(damage_taken * 0.5))
		is_defending = false
	
	# Check for weakness state BEFORE applying damage
	var weakness_multiplier = 1.0
	var is_weakness = false
	if active_states.has("Weakness"):
		weakness_multiplier = 1.5  # Takes 50% more damage
		is_weakness = true
	
	damage_taken = int(float(damage_taken) * weakness_multiplier)
	
	# Add bleed accumulation when taking damage
	add_bleed_accumulation(damage_taken)
	
	# Show damage number
	if number_indicator:
		number_indicator.show_damage(damage_taken, false, is_weakness)
	
	current_health -= damage_taken
	if current_health < 0:
		current_health = 0
	
	# WAKE UP FROM SLEEP WHEN ATTACKED
	if active_states.has("Sleep"):
		remove_state("Sleep")
	
	# PLAY HIT REACTION FLINCH — skipped when fully avoided (0 damage) or defeated
	if damage_taken > 0 and current_health > 0:
		await play_hit_reaction()
	
	# TRIGGER COUNTER IF ACTIVE - await so attacker stays in place during counter
	if attacker and active_states.has("Counter"):
		var counter_state = active_states["Counter"] as CounterState
		if counter_state:
			await counter_state.perform_counter(self, attacker)
	
	# Check if this battler is defeated and should be removed
	if current_health <= 0:
		if _is_despawning:
			return
		_is_despawning = true
		var battle_manager = get_tree().get_first_node_in_group("battle_manager")
		
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
			# For players, just update the turn queue when they die
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
	var healing = min(amount, max_health - current_health)

	current_health += healing
	return healing

func defend():
	is_defending = true
	# FORCE use idle1, not the dictionary
	_try_animation("idle1")

func battle_item(item: Item, target: Battler) -> void:
	# Apply item effects
	if item.damage_amount > 0:
		var damage = item.damage_amount
		target.take_damage(damage, self)
	elif item.heal_amount > 0:
		var _healing = target.take_healing(item.heal_amount)
	
	# Remove item from inventory
	if inventory and inventory.collection.has(item):
		var quantity = inventory.collection[item]
		if quantity > 1:
			inventory.collection[item] = quantity - 1
		else:
			inventory.collection.erase(item)

## XP and Leveling System
func add_experience(amount: int) -> void:
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
	
	var rtdm: RealTimeDefenseManager = get_tree().get_first_node_in_group("real_time_defense_manager")
	if rtdm and target.team == TEAM.ALLY:
		rtdm.open_buffer(self, target, attack_config)
	
	# Show attack indicator for enemies attacking allies
	if team == TEAM.ENEMY and target.team == TEAM.ALLY and attack_indicator:
		var indicator_type = _get_indicator_type(attack_config)
		attack_indicator.show_indicator(indicator_type)
	
	if advance_to_target(target):
		_try_animation(AnimationMapping.WALK)
		while is_advancing:
			await get_tree().create_timer(0.016).timeout
	
	var battle_manager = get_tree().get_first_node_in_group("battle_manager")
	var chosen_anim = AnimationMapping.MELEE_COMBO_1
	if attack_config and not attack_config.animation_name.is_empty():
		chosen_anim = attack_config.animation_name
	
	var _attack_ended = false
	var _on_attack_end = func(): _attack_ended = true
	attack_end.connect(_on_attack_end, CONNECT_ONE_SHOT)

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
	
	if battle_manager and target and mitigated > 0:
		await battle_manager.damage_calculation(self, target, mitigated, attack_config)
		if target.is_defeated():
			if rtdm:
				rtdm.close_buffer()
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
	
	if not _counter_handled_return and original_position != Vector3.ZERO:
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
	# Clear all animation conditions so no state is accidentally held
	if anim_tree:
		anim_tree.set("parameters/conditions/is_walking", false)
		anim_tree.set("parameters/conditions/is_attacking", false)
		anim_tree.set("parameters/conditions/is_dodging", false)
		anim_tree.set("parameters/conditions/is_parrying", false)
		anim_tree.set("parameters/conditions/is_jumping", false)
		anim_tree.set("parameters/conditions/is_hit", false)
		anim_tree.set("parameters/conditions/allow_combat_to_idle", true)

## Plays the standardised hit flinch. The "hit" root state plays once, then
## the code explicitly travels back to idle1 (hit_to_idle is manual advance_mode=0).
func play_hit_reaction() -> void:
	if not anim_tree:
		return
	# Ensure the is_hit condition is set so the idle->hit transition can fire.
	anim_tree.set("parameters/conditions/is_hit", true)
	# From any state, first return to idle1 (which has incoming transitions from
	# every other state), then travel to hit via the idle_to_hit transition.
	# Reset any combat_actions sub-machine playback first so we actually land in
	# idle1 instead of staying visually stuck in a previous attack/cast pose.
	var root_sm := anim_tree.tree_root as AnimationNodeStateMachine
	# REMOVED: Resetting to Start here causes T-pose because Start has no animation!
	# if root_sm.has_node("combat_actions"):
	# 	var ca_sm := anim_tree.get("parameters/combat_actions/playback") as AnimationNodeStateMachinePlayback
	# 	if ca_sm:
	# 		ca_sm.travel("Start")
	state_machine.travel("idle1")
	await get_tree().create_timer(0.1).timeout
	_try_animation(AnimationMapping.HIT)
	# Wait for the hit clip so the flinch plays fully before take_damage continues
	# (counter logic, defeat check, etc. should not interrupt the reaction).
	var duration = _get_animation_duration(AnimationMapping.HIT)
	if duration > 0.0:
		await get_tree().create_timer(duration).timeout
	# Explicitly travel back to idle1 (hit_to_idle no longer auto-advances).
	# Clear is_hit first so the idle_to_hit transition doesn't immediately re-fire.
	anim_tree.set("parameters/conditions/is_hit", false)
	state_machine.travel("idle1")

func advance_to_target(target: Battler) -> bool:
	var battle_manager = get_tree().get_first_node_in_group("battle_manager")
	if not battle_manager:
		return false
		
	if not requires_walking:
		return false
	
	# SAFETY: Prevent overlapping advances
	if is_advancing:
		return false
	
	var movement_distance = custom_movement_distance
	var movement_speed = custom_movement_speed
	
	# Apply speed multiplier from battle manager
	movement_speed *= battle_manager.speed_multiplier
	
	var distance_to_target = global_position.distance_to(target.global_position)
	if distance_to_target <= movement_distance:
		return false
	
	# Reset original_position to current position before moving
	original_position = global_position
	
	var direction = (target.global_position - global_position).normalized()
	advance_target_position = target.global_position - direction * movement_distance
	
	set_advancing(true)
	var tween = create_tween()
	tween.set_speed_scale(battle_manager.speed_multiplier)
	tween.tween_property(self, "global_position", advance_target_position, 
		global_position.distance_to(advance_target_position) / movement_speed)
	tween.tween_callback(_on_advance_complete)
	
	# Start movement timeout timer
	_start_movement_timeout()
	
	return true

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
	if not anim_tree or not (anim_tree.tree_root is AnimationNodeStateMachine):
		return false

	var root_sm := anim_tree.tree_root as AnimationNodeStateMachine

	# Resolve via animation mapping (slot -> character-specific state name).
	var resolved_name := get_resolved_animation(anim_name)

	print("[Battler %s] _try_animation(%s) -> %s, current_root=%s, allow_combat_to_idle=%s" % [character_name, anim_name, resolved_name, state_machine.get_current_node() if state_machine else "null", anim_tree.get("parameters/conditions/allow_combat_to_idle") if anim_tree else "null"])

	# Canonical offensive slots live inside the combat_actions sub-machine.
	var combat_slots: Array = [
		AnimationMapping.MELEE_COMBO_1, AnimationMapping.MELEE_COMBO_2, AnimationMapping.MELEE_COMBO_3,
		AnimationMapping.RANGED_CAST_1, AnimationMapping.RANGED_CAST_2,
	]
	var leaf_name := resolved_name
	var is_combat_slot := (resolved_name in combat_slots) or (anim_name in combat_slots)

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

		var ca_sm := anim_tree.get("parameters/combat_actions/playback") as AnimationNodeStateMachinePlayback
		if not ca_sm:
			push_warning("[Battler] Missing combat_actions/playback on '%s'" % character_name)
			return false

		if was_outside:
			ca_sm.start(leaf_name)
		else:
			ca_sm.travel(leaf_name)
		print("[Battler %s] After CA travel to %s, CA current node: %s" % [character_name, leaf_name, ca_sm.get_current_node() if ca_sm else "null"])

		# Resolve clip duration and schedule hit_moment at the correct frame.
		var resolved_clip_name = _resolve_state_animation_name(leaf_name)
		
		return true

	# Root-level state — force-exit combat_actions sub-machine first if needed,
	# then travel directly to the target root state.
	var current_node := state_machine.get_current_node()
	if current_node == "combat_actions":
		# With switch_mode=Immediate on combat_to_idle, the outer SM will blend
		# directly from the held last-combat-frame into the target state without
		# needing to push the inner sub-machine to End first (which caused a T-pose).
		print("[Battler %s] Exiting combat_actions (Immediate blend) before travelling to %s" % [character_name, resolved_name])

	if not root_sm.has_node(resolved_name):
		push_error("[Battler] Animation state '%s' does not exist on '%s'" % [resolved_name, character_name])
		return false
	print("[Battler %s] Final travel to %s" % [character_name, resolved_name])
	state_machine.travel(resolved_name)
	print("[Battler %s] After final travel, current_node: %s" % [character_name, state_machine.get_current_node()])
	return true

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
	var root_sm := anim_tree.tree_root as AnimationNodeStateMachine
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

	# Root-level states (idle1, walk, dodge, parry, jump, jump_land, hit, death, …)
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
	
	var tween = create_tween()
	tween.set_speed_scale(battle_manager.speed_multiplier)
	tween.tween_property(self, "global_position", original_position,
		global_position.distance_to(original_position) / movement_speed)
	tween.tween_callback(_on_return_complete)

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
	
	set_advancing(true)
	# Play the standardised dodge animation (falls back to walk if unavailable).
	await _try_animation(AnimationMapping.DODGE)
	if not _try_animation(AnimationMapping.DODGE):
		await _try_animation(AnimationMapping.WALK)
	
	var movement_speed = custom_movement_speed
	movement_speed *= battle_manager.speed_multiplier * 1.5  # Faster movement for dodge
	
	var tween = create_tween()
	tween.set_speed_scale(battle_manager.speed_multiplier)
	tween.tween_property(self, "global_position", dodge_target_position,
		global_position.distance_to(dodge_target_position) / movement_speed)
	tween.tween_callback(_on_dodge_dash_complete.bind(dodge_start_position))

func _on_dodge_dash_complete(p_original_position: Vector3):

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

	var tween = create_tween()
	tween.set_speed_scale(battle_manager.speed_multiplier)
	tween.tween_property(self, "global_position", p_original_position,
		global_position.distance_to(p_original_position) / movement_speed)
	tween.tween_callback(_on_return_complete)

func _on_return_complete():
	set_advancing(false)
	# NOTE: Do NOT travel to idle1 here - it fights whatever the caller triggers next

## Performs a jump-dodge evasion: plays jump -> jump_land -> idle1.
## jump and jump_land are defensive maneuvers used to avoid ground-sweeping attacks.
## Falls back to a simple tween arc when neither animation state exists.
func perform_jump_evade() -> void:
	var has_jump := state_machine != null and anim_tree.tree_root is AnimationNodeStateMachine \
		and (anim_tree.tree_root as AnimationNodeStateMachine).has_node(AnimationMapping.JUMP)

	if has_jump:
		# Play the jump ascent animation.
		_try_animation(AnimationMapping.JUMP)
		var jump_dur: float = max(0.25, _get_animation_duration(AnimationMapping.JUMP))
		await get_tree().create_timer(jump_dur).timeout

		# Transition to landing animation if it exists.
		var root_sm := anim_tree.tree_root as AnimationNodeStateMachine
		if root_sm.has_node(AnimationMapping.JUMP_LAND):
			_try_animation(AnimationMapping.JUMP_LAND)
			var land_dur: float = max(0.2, _get_animation_duration(AnimationMapping.JUMP_LAND))
			await get_tree().create_timer(land_dur).timeout

		_try_animation("idle1")
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

# And add these helper functions for state management
func apply_state(state: State) -> void:
	if state == null:
		return
	
	var key = state.state_name
	var existing_state = active_states.get(key) as State
	
	if existing_state:
		# State already exists - handle stacking/refreshing
		if "stack_count" in state and existing_state.has_method("add_stacks"):
			# For stacking states like Burning
			# The incoming state has the NEW stack count to add, not the total
			if state.stack_count > 0:
				existing_state.add_stacks(state.stack_count)
				# Emit signal for UI update
				if key == "Burning":
					burn_stack_changed.emit(existing_state.stack_count)
		# For Protected state, add shield hits (stacking)
		if key == "Protected" and existing_state.has_method("set_shield_hits"):
			if "shield_hits" in state:
				var current_shields = existing_state.get_remaining_shields()
				var new_shields = current_shields + state.shield_hits
				existing_state.set_shield_hits(new_shields)
				shield_changed.emit(existing_state.get_remaining_shields())
			# Also emit if shield state is refreshed without adding shields
			elif existing_state.has_method("get_remaining_shields"):
				shield_changed.emit(existing_state.get_remaining_shields())
		# Refresh duration
		if state.turns_active > 0:
			existing_state.turns_active = state.turns_active
		# Preserve icon texture
		if state.icon_texture and not existing_state.icon_texture:
			existing_state.icon_texture = state.icon_texture
	else:
		# New state - apply directly
		var state_copy = state.duplicate()
		# Force state_name to be set properly after duplication
		state_copy.state_name = state.state_name
		# Preserve stack_count from incoming state
		if "stack_count" in state and "stack_count" in state_copy:
			state_copy.stack_count = state.stack_count
		active_states[key] = state_copy
		
		# Apply visual overlay if the state supports it
		if state_copy.has_method("apply_overlay_to_battler"):
			state_copy.apply_overlay_to_battler(self)
		
		# Apply aura effect if the state supports it
		if state_copy.has_method("apply_aura_effect"):
			state_copy.apply_aura_effect(self)
		
		# Emit shield_changed signal for new Protected state
		if key == "Protected" and state_copy.has_method("get_remaining_shields"):
			shield_changed.emit(state_copy.get_remaining_shields())
	
	state_applied.emit(key)

func remove_state(state_name: String) -> void:
	if active_states.has(state_name):
		var state = active_states[state_name]
		
		# Remove visual overlay if the state supports it
		if state.has_method("remove_overlay_from_battler"):
			state.remove_overlay_from_battler(self)
		
		# Remove aura effect if the state supports it
		if state.has_method("remove_aura_effect"):
			state.remove_aura_effect(self)
		
		active_states.erase(state_name)
		state_removed.emit(state_name)

# Helper methods for specific state types
func add_burn_stacks(amount: int) -> void:
	if active_states.has("Burning"):
		var burning_state = active_states["Burning"] as BurningState
		if burning_state:
			burning_state.add_stacks(amount)
			burn_stack_changed.emit(burning_state.stack_count)

func add_bleed_accumulation(amount: int) -> void:
	if active_states.has("Bleed"):
		var bleed_state = active_states["Bleed"] as BleedState
		if bleed_state:
			bleed_state.add_accumulation_from_damage(amount)

func trigger_bleed_proc() -> void:
	if active_states.has("Bleed"):
		var bleed_state = active_states["Bleed"] as BleedState
		if bleed_state and bleed_state.should_proc_bleed():
			# Play bleed aura effect when proc triggers
			if bleed_state.has_method("load_aura_effect"):
				var aura = bleed_state.load_aura_effect()
				if aura:
					var aura_instance = apply_aura_effect(aura)
					# Bleed aura is one-shot, it auto-cleans
					# No need to store reference or play animation
			
			var proc_damage = bleed_state.trigger_bleed_proc(max_health)
			current_health -= proc_damage
			if current_health < 0:
				current_health = 0
			bleed_proc_triggered.emit(proc_damage)

func break_shield() -> void:
	if active_states.has("Protected"):
		remove_state("Protected")
		shield_broken.emit()

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
	var combined_aabb = AABB()
	var has_mesh = false
	
	# Combine AABBs of all MeshInstance3D children
	for child in find_children("*", "MeshInstance3D", true, false):
		if child is MeshInstance3D:
			var mesh_aabb = child.get_aabb()
			if mesh_aabb != AABB():
				if not has_mesh:
					combined_aabb = mesh_aabb
					has_mesh = true
				else:
					combined_aabb = combined_aabb.merge(mesh_aabb)
	
	# If no meshes found, use default height
	if not has_mesh:
		_cached_effect_center = Vector3(0, 0.75, 0)  # Default center for 1.5 height
		_cached_effect_top = Vector3(0, 1.5, 0)
		_cached_effect_bottom = Vector3(0, 0.0, 0)
	else:
		# Calculate positions from combined AABB
		_cached_effect_center = Vector3(0, combined_aabb.position.y + combined_aabb.size.y / 2.0, 0)
		_cached_effect_top = Vector3(0, combined_aabb.position.y + combined_aabb.size.y, 0)
		_cached_effect_bottom = Vector3(0, combined_aabb.position.y, 0)
	
	_effect_center_cached = true

## Invalidate the cached effect positions
## Call this when meshes are added/removed from the battler
func invalidate_effect_cache() -> void:
	_effect_center_cached = false

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

func process_states() -> void:
	var states_to_remove = []
	
	for state_name in active_states:
		var state = active_states[state_name]
		
		# Handle Burning state (stack-based damage)
		if state_name == "Burning":
			var burning_state = state as BurningState
			if burning_state and burning_state.stack_count > 0:
				var burn_damage = burning_state.get_burn_damage()
				if burn_damage > 0:
					if number_indicator:
						number_indicator.show_damage(burn_damage)
					current_health -= burn_damage
					if current_health < 0:
						current_health = 0
				# Decay stacks by 1 each turn
				if burning_state.has_method("process_turn_end"):
					var old_stacks = burning_state.stack_count
					burning_state.process_turn_end()
					# Emit signal if stacks changed
					if burning_state.stack_count != old_stacks:
						burn_stack_changed.emit(burning_state.stack_count)
		
		# Handle other DOT/HOT effects with damage multiplier based on target defense
		elif state.damage_per_turn != 0:
			# Apply power multiplier and defense reduction: base_damage * power_mult * (1 - (defense / 100))
			var defense_multiplier = max(0.1, 1.0 - (float(defense) / 100.0))
			var actual_damage = int(state.damage_per_turn * state.power_multiplier * defense_multiplier)
			actual_damage = max(1, actual_damage)  # Minimum 1 damage
			
			# Only show damage popup for positive damage (DOT)
			if actual_damage > 0:
				if number_indicator:
					number_indicator.show_damage(actual_damage)
				current_health -= actual_damage
				if current_health < 0:
					current_health = 0
			else:
				# Healing state (negative damage)
				var healing = abs(actual_damage)
				if number_indicator:
					number_indicator.show_heal(healing)
				current_health = min(current_health + healing, max_health)
		
		# Handle duration
		if state.turns_active > 0:
			state.turns_active -= 1
			if state.turns_active <= 0:
				states_to_remove.append(state_name)
		
		# For Burning, also remove if stacks reach 0
		if state_name == "Burning":
			var burning_state = state as BurningState
			if burning_state and burning_state.stack_count <= 0:
				states_to_remove.append(state_name)
	
	# Remove expired states
	for state_name in states_to_remove:
		remove_state(state_name)

func set_advancing(value: bool):
	is_advancing = value
	print("[Battler %s] set_advancing(%s), allow_combat_to_idle = %s" % [character_name, value, anim_tree.get("parameters/conditions/allow_combat_to_idle") if anim_tree else "null"])
	anim_tree.set("parameters/conditions/is_walking", value)

func set_defending(value: bool):
	is_defending = value

func _fade_and_remove() -> void:
	# Play death animation instead of scaling down
	_try_animation(AnimationMapping.DEATH)
	var death_duration = _get_animation_duration(AnimationMapping.DEATH)
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
		"max_ap": stats.max_ap
	}
	
	var stat_multipliers = {
		"max_health": stats.health_multiplier,
		"attack": stats.attack_multiplier,
		"defense": stats.defense_multiplier,
		"agility": stats.agility_multiplier,
		"max_ap": stats.ap_multiplier
	}
	
	# Get calculated stats at current level
	var calculated = LevelProgression.get_stats_at_level(base_stats, stat_multipliers, current_level)
	
	# Apply to battler
	max_health = calculated["max_health"]
	attack = calculated["attack"]
	defense = calculated["defense"]
	agility = calculated["agility"]
	max_ap = calculated.get("max_ap", stats.max_ap)
	ap_regen_per_turn = stats.ap_regen_per_turn
	
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
