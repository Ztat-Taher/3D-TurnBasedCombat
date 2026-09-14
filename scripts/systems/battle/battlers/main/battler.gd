class_name Battler
extends CharacterBody3D

signal anim_damage()
signal hit_moment(attacker: Battler)
signal health_changed(current_health: int, max_health: int)
signal ap_changed(current_ap: int, max_ap: int)
enum TEAM {ALLY, ENEMY}

@export_range(0.0, 1.0, 0.01) var hit_frame_ratio: float = 0.55 ## Default contact frame ratio for attacks (e.g. 0.55 = 55% of animation duration)

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

var current_health: int
var is_defending: bool = false
var current_target = null
var is_counter_stunned: bool = false  # Stunned by being hit with a counter attack
var _is_despawning: bool = false

# Walking animation system
var is_advancing: bool = false
var advance_target_position: Vector3
var original_position: Vector3

# Per-battler movement settings (override global if set)
@export_group("Movement Settings", "movement")
## Distance at which this battler requires movement to target. -1.0 = use global setting
@export var custom_movement_distance: float = -1.0
## Speed of movement animation for this battler. -1.0 = use global setting  
@export var custom_movement_speed: float = -1.0
## Movement animation name for this battler. Empty = use global setting
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
##
## CUSTOM MOVEMENT SETTINGS EXPLAINED:
## -1.0 values mean "use the global setting from BattleManager"
## Set positive values to override global settings for this specific battler
## Example: Set custom_movement_distance = 5.0 for a big monster that needs more space
## Example: Set custom_movement_speed = 1.0 for a slow character
## Example: Set custom_movement_animation = "my_movement_anim" for custom animation



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

## Applies a ShaderMaterial as next_pass on every collected mesh.
func _apply_next_pass(shader_mat: ShaderMaterial) -> void:
	for mesh in _highlight_meshes:
		if is_instance_valid(mesh) and mesh.material_override:
			mesh.material_override.next_pass = shader_mat

## Clears next_pass on every collected mesh.
func _clear_next_pass() -> void:
	for mesh in _highlight_meshes:
		if is_instance_valid(mesh) and mesh.material_override:
			mesh.material_override.next_pass = null

@onready var select_outline: Shader = preload("res://assets/shaders/battler_select_shader.gdshader")
var is_selectable: bool = false:
	set(value):
		is_selectable = value
		if !is_selectable:
			is_targeted = false
			_clear_next_pass()
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
	
	if !is_selectable or !is_valid_target:
		_clear_next_pass()
		return
	
	# Clear any existing highlight first
	_clear_next_pass()
	
	# Mouse hover takes priority over everything else
	if mouse_hover and is_selectable:
		# White hover outline (highest priority)
		var hover_mat = ShaderMaterial.new()
		hover_mat.shader = select_outline
		hover_mat.set_shader_parameter("color", Color.WHITE)
		hover_mat.set_shader_parameter("thickness", 0.02)
		hover_mat.set_shader_parameter("alpha", 0.6)
		_apply_next_pass(hover_mat)
	elif is_targeted or is_mouse_selected or is_keyboard_selected or is_default_target:
		# Main selection outline (cyan for all input methods)
		var shader_mat = ShaderMaterial.new()
		shader_mat.shader = select_outline
		shader_mat.set_shader_parameter("color", Color.CYAN)
		shader_mat.set_shader_parameter("thickness", 0.025)
		shader_mat.set_shader_parameter("alpha", 1.0)
		_apply_next_pass(shader_mat)

@export_group("Special Dependencies")
## Deprecated — kept only for backwards compatibility with older card/skill code.
## Use AnimationMapping slots directly in new code.
@onready var basic_attack_animation = AnimationMapping.MELEE_COMBO_1
@onready var anim_tree: AnimationTree = $AnimationTree
var state_machine: AnimationNodeStateMachinePlayback
@onready var exp_node: Experience = get_node("Experience")
@export var damage_indicator_subviewport:SubViewport = null

@export_group("Counter Stun Settings", "stun")
## Duration (seconds) before recovering from being hit by a counter attack
@export var counter_stun_duration: float = 1.5

var _current_attack_duration: float = 1.0

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
		health_changed.emit(current_health, max_health)
	elif stats:
		# Basic stats for ally
		character_name = stats.character_name
		# Apply level-focused progression (calculates stats based on level)
		apply_level_progression()
	else:
		push_error("Neither BattlerStats nor EnemyStats resource set for %s!" % name)
	
	# Assign to group based on team
	if team == TEAM.ENEMY:
		add_to_group("enemies")
	elif team == TEAM.ALLY:
		add_to_group("players")

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
	_clear_next_pass()


func is_defeated() -> bool:
	return current_health <= 0

func get_attack_damage(target) -> int:
	var damage = attack + randi() % 5
	return Formulas.physical_damage(self, target, damage)

@onready var floating_damage_num:PackedScene = preload("res://scenes/battle/effects/damage/damage_number.tscn")
func take_damage(amount: int, attacker: Battler = null) -> void:
	var damage_taken = max(1, amount) if amount > 0 else 0
	if is_defending:
		damage_taken = max(1, int(damage_taken * 0.5))
		is_defending = false
	
	# Check for weakness state BEFORE applying damage
	var weakness_multiplier = 1.0
	if active_states.has("Weakness"):
		weakness_multiplier = 1.5  # Takes 50% more damage
	
	damage_taken = int(float(damage_taken) * weakness_multiplier)
	
	var damage_num: DamageNumber = floating_damage_num.instantiate()
	damage_num.value = damage_taken
	if damage_indicator_subviewport:
		damage_indicator_subviewport.add_child(damage_num)
	current_health -= damage_taken
	if current_health < 0:
		current_health = 0
	
	health_changed.emit(current_health, max_health)
	
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
	health_changed.emit(current_health, max_health)
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

## Performs an attack animation and damage application on target
## Optionally accepts an EnemyAttackConfig for custom animation/timing/multiplier
func attack_anim(target, attack_config: EnemyAttackConfig = null) -> void:
	# SAFETY: Prevent self-attacks
	if target == self:
		return
	
	current_target = target
	
	if advance_to_target(target):
		_try_animation(AnimationMapping.WALK)
		while is_advancing:
			await get_tree().create_timer(0.016).timeout
	
	var battle_manager = get_tree().get_first_node_in_group("battle_manager")
	var chosen_anim = AnimationMapping.MELEE_COMBO_1
	if attack_config and not attack_config.animation_name.is_empty():
		chosen_anim = attack_config.animation_name
	
	if not _try_animation(chosen_anim):
		_try_animation(AnimationMapping.MELEE_COMBO_1)
	
	# Wait for hit_moment (contact frame) to apply damage.
	# Precedence: EnemyAttackConfig > AnimationMapping per-slot ratio > battler default.
	var ratio = hit_frame_ratio
	if attack_config and attack_config.hit_frame_ratio >= 0.0:
		ratio = attack_config.hit_frame_ratio
	elif animation_mapping:
		var mapping_ratio = animation_mapping.get_hit_frame_ratio(chosen_anim)
		if mapping_ratio >= 0.0:
			ratio = mapping_ratio
	
	var hit_time = _current_attack_duration * ratio
	var remaining_time = max(0.1, _current_attack_duration - hit_time)
	
	await hit_moment
	
	# Apply damage at exact contact frame
	if battle_manager and target:
		var base_atk = attack if attack > 0 else 15
		var multiplier = attack_config.damage_multiplier if attack_config else 1.0
		var atk_damage = int(base_atk * multiplier)
		await battle_manager.damage_calculation(self, target, atk_damage, attack_config)
	
	# Wait for follow-through of the attack animation
	await get_tree().create_timer(remaining_time + 0.12).timeout
	
	# CRITICAL: Wait for damage callback and counters to complete before returning
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.1).timeout
	
	# If stunned by counter, wait before returning to position
	if is_counter_stunned:
		await get_tree().create_timer(counter_stun_duration).timeout
		is_counter_stunned = false
	
	# NOW return to original position after damage/counter completed
	if original_position != Vector3.ZERO:
		return_to_original_position()
		# Wait for return movement to complete
		while is_advancing:
			await get_tree().create_timer(0.1).timeout
	
	# Return to idle state
	battle_idle()

func wait_attack():
	if self.is_defending:
		return
	# Wait for attack animation using duration read from AnimationPlayer at travel time
	await get_tree().create_timer(_current_attack_duration).timeout
	
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
	if root_sm.has_node("combat_actions"):
		var ca_sm := anim_tree.get("parameters/combat_actions/playback") as AnimationNodeStateMachinePlayback
		if ca_sm:
			ca_sm.travel("Start")
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
		
	if not battle_manager.enable_movement_to_target or not requires_walking:
		return false
	
	# SAFETY: Prevent overlapping advances
	if is_advancing:
		return false
		
	var movement_distance = custom_movement_distance if custom_movement_distance > 0 else battle_manager.movement_distance_threshold
	var movement_speed = custom_movement_speed if custom_movement_speed > 0 else battle_manager.movement_speed
	
	# Apply speed multiplier from battle manager
	movement_speed *= battle_manager.speed_multiplier
	
	var distance_to_target = global_position.distance_to(target.global_position)
	if distance_to_target <= movement_distance:
		return false
	
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

		state_machine.travel("combat_actions")
		var ca_sm := anim_tree.get("parameters/combat_actions/playback") as AnimationNodeStateMachinePlayback
		if not ca_sm:
			push_warning("[Battler] Missing combat_actions/playback on '%s'" % character_name)
			return false
		ca_sm.travel(leaf_name)

		# Resolve clip duration and schedule hit_moment at the correct frame.
		_current_attack_duration = max(0.25, _get_animation_duration(leaf_name))
		var ratio_override := -1.0
		if animation_mapping:
			ratio_override = animation_mapping.get_hit_frame_ratio(anim_name)
		_schedule_hit_moment(_current_attack_duration, ratio_override)
		return true

	# Root-level state — travel only when it actually exists on this tree.
	# If the root playback is currently inside the combat_actions sub-machine,
	# reset the sub-machine's playback first so it doesn't keep playing its last
	# state underneath the new root state (which would show the wrong pose).
	if root_sm.has_node("combat_actions"):
		var ca_sm := anim_tree.get("parameters/combat_actions/playback") as AnimationNodeStateMachinePlayback
		if ca_sm:
			ca_sm.travel("Start")
	if not root_sm.has_node(resolved_name):
		push_error("[Battler] Animation state '%s' does not exist on '%s'" % [resolved_name, character_name])
		return false
	state_machine.travel(resolved_name)
	return true

var _hit_moment_timer: SceneTreeTimer = null

## Schedules hit_moment signal based on hit_frame_ratio or explicit duration
func _schedule_hit_moment(duration: float, ratio_override: float = -1.0) -> void:
	var ratio = ratio_override if ratio_override >= 0.0 else hit_frame_ratio
	var hit_delay = max(0.05, duration * ratio)
	var _captured_duration = duration
	_hit_moment_timer = get_tree().create_timer(hit_delay)
	_hit_moment_timer.timeout.connect(func():
		hit_moment.emit(self)
		anim_damage.emit()
	)

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
		return_to_original_position()

func return_to_original_position():
	if is_advancing or global_position.distance_to(original_position) < 0.05:
		return
		
	var battle_manager = get_tree().get_first_node_in_group("battle_manager")
	if not battle_manager:
		return
		
	var movement_speed = custom_movement_speed if custom_movement_speed > 0 else battle_manager.movement_speed
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
	if not _try_animation(AnimationMapping.DODGE):
		_try_animation(AnimationMapping.WALK)
	
	var movement_speed = custom_movement_speed if custom_movement_speed > 0 else battle_manager.movement_speed
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
	
	var movement_speed = custom_movement_speed if custom_movement_speed > 0 else battle_manager.movement_speed
	movement_speed *= battle_manager.speed_multiplier
	
	var tween = create_tween()
	tween.set_speed_scale(battle_manager.speed_multiplier)
	tween.tween_property(self, "global_position", p_original_position, 
		global_position.distance_to(p_original_position) / movement_speed)
	tween.tween_callback(_on_return_complete)

func _on_return_complete():
	set_advancing(false)
	_try_animation("idle1")

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

	
func get_exp_stat():
	return exp_node

# # #
# Animation Damage & Effects Application
# # #
## Called when animation reaches the hit point (either via animation event track or timer) - applies damage and any attached states
func apply_animation_effects():
	hit_moment.emit(self)
	anim_damage.emit()

func call_attack():
	# Deprecated - use apply_animation_effects() instead
	apply_animation_effects()

# In take_damage, add state application for counter:

# Update the animation callback to use new name:
func _on_anim_damage():
	var battle_manager = get_tree().get_first_node_in_group("battle_manager")
	if not battle_manager:
		return
	
	# This function will be replaced by the card combat system
	# For now, keeping it for compatibility with existing animations
	pass

# # #
# Save System
# # #
func on_save_game(save_data):
	var new_data = BattlerData.new()
	new_data.current_health = current_health  # Using consistent property name

	new_data.current_exp = get_exp_stat().get_total_exp()
	new_data.current_level = get_exp_stat().get_current_level()
	
	save_data["charNameOrID"] = new_data

func on_load_game(load_data):
	var save_data = load_data["charNameOrID"] as BattlerData
	if save_data == null: 
		return
	
	current_health = save_data.current_health  # Using consistent property name

	get_exp_stat().exp_total = save_data.current_exp
	get_exp_stat().char_level = save_data.current_level

var active_states: Dictionary = {}  # {state_name: State}

# And add these helper functions for state management
func apply_state(state: State) -> void:
	if state == null:
		return
	var state_copy = state.duplicate()
	# Force state_name to be set properly after duplication
	state_copy.state_name = state.state_name
	var key = state_copy.state_name
	active_states[key] = state_copy

func remove_state(state_name: String) -> void:
	if active_states.has(state_name):
		active_states.erase(state_name)

func process_states() -> void:
	var states_to_remove = []
	
	for state_name in active_states:
		var state = active_states[state_name]
		
		# Handle DOT/HOT effects with damage multiplier based on target defense
		if state.damage_per_turn != 0:
			# Apply power multiplier and defense reduction: base_damage * power_mult * (1 - (defense / 100))
			var defense_multiplier = max(0.1, 1.0 - (float(defense) / 100.0))
			var actual_damage = int(state.damage_per_turn * state.power_multiplier * defense_multiplier)
			actual_damage = max(1, actual_damage)  # Minimum 1 damage
			
			# Only show damage popup for positive damage (DOT)
			if actual_damage > 0:
				var damage_num: DamageNumber = floating_damage_num.instantiate()
				damage_num.value = actual_damage
				if damage_indicator_subviewport:
					damage_indicator_subviewport.add_child(damage_num)
				current_health -= actual_damage
				if current_health < 0:
					current_health = 0
			else:
				# Healing state (negative damage)
				var healing = abs(actual_damage)
				current_health = min(current_health + healing, max_health)
		
		# Handle duration
		if state.turns_active > 0:
			state.turns_active -= 1
			if state.turns_active <= 0:
				states_to_remove.append(state_name)
	
	# Remove expired states
	for state_name in states_to_remove:
		remove_state(state_name)

func set_advancing(value: bool):
	is_advancing = value
	anim_tree.set("parameters/conditions/is_walking", value)

func set_defending(value: bool):
	is_defending = value

func _fade_and_remove() -> void:
	var tween = create_tween()
	tween.set_parallel(true)
	
	# Fade transparency on all collected mesh instances that support it.
	# This works for any model regardless of node names.
	for mesh in _highlight_meshes:
		if is_instance_valid(mesh) and mesh is GeometryInstance3D:
			mesh.transparency = 0.0
			tween.tween_property(mesh, "transparency", 1.0, 0.35)
	
	# Also scale down the whole battler as a reliable universal effect.
	# Scaling to exactly Vector3.ZERO makes the transform basis singular, which
	# causes 'invert: Condition "det == 0"' errors in skeleton pose updates.
	tween.tween_property(self, "scale", Vector3.ONE * 0.01, 0.35)
	
	await tween.finished
	
	# Safety check: ensure the node hasn't already been destroyed by a scene change
	if is_instance_valid(self):
		queue_free()

## LEVEL-FOCUSED PROGRESSION
## Add experience and check for level up
func gain_experience(amount: int) -> void:
	if not exp_node:
		push_error("Battler %s has no Experience node" % character_name)
		return
	
	exp_node.add_exp(amount)
	
	# Check if level up occurred
	while LevelProgression.check_level_up(self):
		pass

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
	var calculated = LevelProgression.get_stats_at_level(base_stats, stat_multipliers, stats.level)
	
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
