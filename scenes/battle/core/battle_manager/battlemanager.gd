class_name BattleManager
extends Node3D

## BATTLE CONFIGURATION USAGE:
## Look for: assets/globals/battle-settings/battle_config.gd
## 
## How to use:
## 1. Create a .tres file from BattleConfig resource
## 2. Set properties in inspector (starting states, damage multipliers, difficulty, etc.)
## 3. In your scene script BEFORE starting battle:
##    GlobalBattleSettings.set_battle_config(your_config)
## 4. Retrieve config after battle ends to apply effects:
##    var config = GlobalBattleSettings.get_battle_config()
##    # Use config.experience_multiplier, config.gold_multiplier, etc.
## 5. Clean up: GlobalBattleSettings.clear_battle_config()

enum BattleEndCondition { WIN, CUTSCENE, DEFEAT, ESCAPE }

## Execution context for AOE projectiles
## One AOE cast's targets: everyone the card resolves on, and their center
## (where an AOE projectile lands). Built per cast and passed down the card's
## execution context.
class AoeContext:
	var center_position: Vector3
	var targets: Array[Battler]

	## Context for the living battlers in [param list]: aimed 1 m above their
	## mean position (so it follows targets on raised ground too).
	static func from_targets(list: Array) -> AoeContext:
		var ctx := AoeContext.new()
		var sum := Vector3.ZERO
		for t in list:
			if is_instance_valid(t) and t is Battler and not (t as Battler).is_defeated():
				ctx.targets.append(t)
				sum += (t as Battler).global_position
		if not ctx.targets.is_empty():
			ctx.center_position = sum / ctx.targets.size() + Vector3(0, 1.0, 0)
		return ctx

## Emitted once the battle reaches an end condition (WIN, DEFEAT, ESCAPE, CUTSCENE).
## Level wrappers connect to this to continue the run flow (next battle / run over / replay).
signal battle_ended(end_condition: BattleEndCondition)

## Set once a battle is finished so out-of-band kills (e.g. parry counters)
## can safely re-check the win condition without double-ending the battle.
var battle_finished : bool = false

var skip_turn = false # Please please please, Change the functionality or entirely remove this down the line.
var players: Array[Battler] = []
var enemies: Array[Battler] = []
var turn_order: Array[Battler] = []
var current_turn: int = 0
var is_first_turn: bool = true

var current_character:Battler
var current_target:Battler
var in_target_selection:bool = false
var in_menu_selection:bool = false

# Stepped navigation for target selection
var last_target_navigation_time: float = 0.0
var target_navigation_cooldown: float = 0.25  # Time between navigations in seconds
var target_navigation_threshold: float = 0.6  # Joystick threshold to trigger navigation
var target_joystick_active_direction: int = 0  # Track which direction joystick is active in

# Target type tracking (enemy vs ally)
var current_target_type: String = "enemy"  # "enemy" or "ally"

# ActionButtons is now in BattleHUD, not BattleManager
# We'll access it through the HUD
# For referencing and setting variables in the battle settings.
@onready var battle_settings = GlobalBattleSettings

var current_battler
@onready var hud: BattleHud = $BattleHUD

# Toggles For Battles
@export_group("Toggle Buttons")
@export var item_toggle: bool = true
@export var run_toggle: bool = true
@export var mouse_input_toggle: bool = true

# Battle Speed Control
@export_group("Battle Speed Control", "speed")
@export var speed_multiplier: float = 1.0  ## Multiplier for animation and action speeds. Hold Space to increase.
@export var speed_key: String = "Confirm"  ## Key to hold for battle speed increase
@export var speed_increase_amount: float = 3.0  ## How much to multiply speed (3.0 = 3x speed)
@export var speed_is_toggle: bool = false  ## If true, press once to toggle fast forward. If false, hold to fast forward.
var is_speed_active: bool = false

# Turn Safety & Timeout
@export_group("Turn Safety", "turn")
@export var turn_timeout_seconds: float = 10.0  ## Max time a turn can take before force-advancing. Prevents soft locks.
var current_turn_timeout_timer: float = 0.0

# Formation positioning with proper spacing
@export_group("Formation Spacing", "formation")
@export_range(1.0, 8.0, 0.5) var formation_spacing: float = 3.0  ## Space between enemies in formation

var animation_dictionary: Dictionary = {
	"run": "run",
	"walk": "walk",
	"turn_left": "turn_left", 
	"turn_right": "turn_right",
	"attack": "attack",
	"idle": "idle1",
	"defend": "defend"
}
## Dictionary of animation STATE NAMES (keys used by state_machine.travel())
## Maps action types to their corresponding state machine states
## NOTE: These are STATE NAMES, not animation names. The states themselves define which animation to play.

# Rotation and Battle Settings
@export_group("Battle Settings", "battle")
@export var invert_rotation_axis: bool = true
@export var remove_defeated_enemies: bool = true
@export var instant_turning: bool = false
## Invert rotation axis for characters with unusual pre-existing rotations.
## Remove defeated enemies entirely from the battle scene.
## Instant turning skips turn animations for immediate rotation.

# Troop System
@export_group("Troop System", "troop")
@export var active_troop: Troops = null
@export var enemy_markers: Node3D = null  # Reference to parent node containing Marker3D nodes for formation positions
@export var use_procedural_formation: bool = true
## Active troop to spawn. If set, will override manual enemy placement.
## Reference to the parent node containing Marker3D children for custom formations.
## If true, positions will be calculated procedurally based on formation type.

# Helper function to get animation name from dictionary
func get_animation(animation_type: String) -> String:
	if animation_dictionary.has(animation_type):
		return animation_dictionary[animation_type]
	else:
		return "idle1"  # Always fallback to idle1 state node

# Helper function to calculate enemy positions based on formation
func get_formation_position(index: int, total: int, formation: Troops.Formation, marker: Marker3D = null) -> Vector3:
	var base_pos = marker.global_position if marker else Vector3.ZERO
	var spacing: float = formation_spacing
	
	match formation:
		Troops.Formation.FRONT_ROW:
			# Center formation with one in middle, others on sides
			if total == 1:
				return base_pos
			
			# Calculate positions: center at 0, then alternate left/right
			var center_index = int(total / 2.0)
			var offset = index - center_index
			return base_pos + Vector3(offset * spacing, 0, 0)
			
		Troops.Formation.TRIANGLE:
			var row = int(sqrt(index))
			var col = index - row * row
			return base_pos + Vector3(col * spacing - row * spacing / 2.0, 0, row * spacing)
		Troops.Formation.CIRCLE_PLAYER:
			var angle = (TAU * index) / float(total)
			var radius = 4.0
			return base_pos + Vector3(cos(angle) * radius, 0, sin(angle) * radius)
		_:  # CUSTOM_MARKERS and default
			return base_pos

# Spawn enemies from troop data
func spawn_troop(troop: Troops, parent_node: Node3D = self) -> void:
	if not troop or not troop.enemy_group or troop.enemy_group.enemy_scenes.is_empty():
		push_error("Invalid troop or no enemy group/scenes defined!")
		return
	
	# Wait for node to be in tree before getting transform
	if not parent_node.is_inside_tree():
		await parent_node.tree_entered
	
	# Try to find FRONTROW marker for base positioning
	var front_row_marker: Marker3D = null
	for node in get_tree().get_nodes_in_group("FRONTROW"):
		if node is Marker3D:
			front_row_marker = node
			break
	
	var loaded_scenes = troop.get_enemy_scenes()
	var marker_index = 0
	
	for i in range(loaded_scenes.size()):
		var enemy_scene = loaded_scenes[i]
		if not enemy_scene:
			push_warning("Failed to load enemy scene at index ", i)
			continue
		
		var enemy = enemy_scene.instantiate()
		if not enemy is Battler:
			push_warning("Enemy scene is not a Battler at index ", i, " in group: ", troop.enemy_group.group_name)
			enemy.queue_free()
			continue
		
		# Calculate position based on formation
		var spawn_position: Vector3
		
		if troop.formation == Troops.Formation.CUSTOM_MARKERS:
			# Use Marker3D positions if available
			if enemy_markers and marker_index < enemy_markers.get_child_count():
				spawn_position = enemy_markers.get_child(marker_index).global_position
				marker_index += 1
			else:
				spawn_position = get_formation_position(i, loaded_scenes.size(), Troops.Formation.FRONT_ROW, front_row_marker)
		else:
			spawn_position = get_formation_position(i, loaded_scenes.size(), troop.formation, front_row_marker)
		
		# Add enemy to scene
		parent_node.add_child(enemy)
		enemy.global_position = spawn_position
		
		# Rotate 180 degrees on Y axis to face toward players
		enemy.rotation.y = PI
		
		# Add to enemies array, group, and turn order
		enemy.add_to_group("enemies")
		enemies.append(enemy)
		turn_order.append(enemy)
		
		# Set battle idle state
		enemy.battle_idle()
		hud.on_start_combat(enemy)
		


# Spawn additional enemies during battle (for troop-to-troop battles that continue)
func spawn_reinforcements(troop: Troops, parent_node: Node3D = self) -> void:
	if not troop or not troop.enemy_group or troop.enemy_group.enemy_scenes.is_empty():
		push_error("Invalid troop or no enemy group/scenes defined!")
		return
	
	# Try to find FRONTROW marker for base positioning
	var front_row_marker: Marker3D = null
	for node in get_tree().get_nodes_in_group("FRONTROW"):
		if node is Marker3D:
			front_row_marker = node
			break
	
	var loaded_scenes = troop.get_enemy_scenes()
	var current_enemy_count = enemies.size()
	
	for i in range(loaded_scenes.size()):
		var enemy_scene = loaded_scenes[i]
		if not enemy_scene:
			push_warning("Failed to load enemy scene at index ", i)
			continue
		
		var enemy = enemy_scene.instantiate()
		if not enemy is Battler:
			push_warning("Enemy scene is not a Battler at index ", i, " in group: ", troop.enemy_group.group_name)
			enemy.queue_free()
			continue
		
		# Calculate position based on formation
		var spawn_position = get_formation_position(current_enemy_count + i, current_enemy_count + loaded_scenes.size(), troop.formation, front_row_marker)
		
		# Set enemy position
		enemy.global_position = spawn_position
		
		# Rotate 180 degrees on Y axis to face toward players
		enemy.rotation.y = PI
		
		# Add to scene
		parent_node.add_child(enemy)
		
		# Add to enemies group
		enemy.add_to_group("enemies")
		
		# Add to enemies array
		enemies.append(enemy)
		
		# Add to turn order
		turn_order.append(enemy)
		
		# Apply troop-wide damage reduction if applicable
		if troop.damage_reduction != 1.0:
			enemy.damage_multiplier = troop.damage_reduction
		
		# Set battle idle state
		enemy.battle_idle()
		hud.on_start_combat(enemy)
		


# Helper function to clean up defeated enemies
func cleanup_defeated_enemies():
	if not remove_defeated_enemies:
		return
		
	# Remove defeated enemies from arrays and scene
	var enemies_to_remove = []
	for enemy in enemies:
		if enemy.is_defeated():
			enemies_to_remove.append(enemy)
	
	for enemy in enemies_to_remove:
		# Remove from turn order
		if turn_order.has(enemy):
			turn_order.erase(enemy)
		# Remove from enemies array
		enemies.erase(enemy)
		# Remove from scene
		enemy.queue_free()

var is_animating: bool = false
var card_integration: CardIntegration
var battle_camera: BattleCamera
var effect_manager: EffectManager
var real_time_defense_manager: RealTimeDefenseManager

func _ready():
	add_to_group("battle_manager")
	SignalBus.select_target.connect(target_selected)
	
	# Instantiate dynamic combat camera controller
	battle_camera = BattleCamera.new()
	battle_camera.name = "BattleCameraController"
	add_child(battle_camera)
	
	# Initialize effect manager
	effect_manager = EffectManager.new()
	effect_manager.name = "EffectManager"
	add_child(effect_manager)
	
	# Initialize real-time defense manager
	real_time_defense_manager = RealTimeDefenseManager.new()
	real_time_defense_manager.name = "RealTimeDefenseManager"
	add_child(real_time_defense_manager)
	
	# Connect screen flash from HUD after a short delay to ensure HUD is ready
	call_deferred("_connect_effect_screen_flash")
	
	# Initialize card integration
	initialize_card_integration()
	
	# Initialize battle
	initialize_battle()

func _connect_effect_screen_flash() -> void:
	# Connect screen flash from HUD
	if effect_manager and hud:
		var screen_flash = hud.get_node_or_null("Control/ScreenFlashOverlay")
		if screen_flash:
			effect_manager.setup_screen_flash(screen_flash)

func initialize_card_integration():
	# Create card integration node
	card_integration = CardIntegration.new()
	add_child(card_integration)
	
	# Don't initialize immediately - wait for battle to be set up first
	# This will be called in initialize_battle() instead

func initialize_cards_for_players():
	if not card_integration:
		return
	
	# Initialize card combat for each player
	for player in players:
		if player is Battler:
			card_integration.initialize_for_player(player)

## Open-hand cursor while the mouse is over a valid target during targeting -
## the same per-frame raycast check the treasure chest uses.
func _process(_delta: float) -> void:
	var over_target := false
	if in_target_selection and mouse_input_toggle and battle_camera:
		var battler := _raycast_battler_at(get_viewport().get_mouse_position())
		over_target = battler != null and battler.is_selectable and battler.is_valid_target
	CursorManager.set_hover(self, over_target)


func _input(event: InputEvent) -> void:
	if !in_target_selection or valid_targets.is_empty():
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_mouse_click_target_selection()
		get_viewport().set_input_as_handled()
	# Handle speed key
	if speed_is_toggle:
		# Toggle mode - press once to toggle on/off
		if event.is_action_pressed(speed_key):
			is_speed_active = !is_speed_active
			speed_multiplier = speed_increase_amount if is_speed_active else 1.0
	else:
		# Hold mode - hold key to speed up
		if event.is_action_pressed(speed_key):
			is_speed_active = true
			speed_multiplier = speed_increase_amount
		elif event.is_action_released(speed_key):
			is_speed_active = false
			speed_multiplier = 1.0
	
	# Cancel / Back (Esc, Backspace, right-click, gamepad B) is handled by the HUD's
	# single Back handler, which calls cancel_target_selection() here
	# Confirm is currently bound to Enter key
	if event.is_action_pressed("Confirm") and in_target_selection:
		await confirm_target_selection()

func initialize_battle():
	# Get all nodes and convert to Battler arrays
	players = []
	enemies = []
	
	for node in get_tree().get_nodes_in_group("players"):
		if node is Battler:
			players.append(node as Battler)
	
	for node in get_tree().get_nodes_in_group("enemies"):
		if node is Battler:
			enemies.append(node as Battler)
	
	# Assign enumerated display labels for queue identification
	for i in range(players.size()):
		var p = players[i]
		if p.character_name.is_empty() or p.character_name == "Player":
			p.character_name = "Ally %d" % (i + 1)
		elif not str(i + 1) in p.character_name:
			p.character_name = p.character_name + " %d" % (i + 1)
	
	for i in range(enemies.size()):
		var e = enemies[i]
		if e.character_name.is_empty() or e.character_name == "Enemy":
			e.character_name = "Enemy %d" % (i + 1)
		elif not str(i + 1) in e.character_name:
			e.character_name = e.character_name + " %d" % (i + 1)
	
	for player in players:
		# Register player with impact frame system for freeze effects
		if effect_manager:
			effect_manager.register_impact_node(player)
		hud.on_add_character(player)
		player.battle_idle()

		# Play spawn effect for allies
		_play_spawn_effect(player)
	
	# Ensure players are at the start of the turn order
	turn_order = players + enemies
	
	for enemy in enemies:
		# Register enemy with impact frame system for freeze effects
		if effect_manager:
			effect_manager.register_impact_node(enemy)
		hud.on_start_combat(enemy)
		enemy.battle_idle()
	
	# Initialize card integration now that battle is set up
	initialize_cards_for_players()
	
	# Initialize HUD connections
	if not hud:
		push_error("BattleHUD node not found. Please make sure it's added to the scene.")
		return
	hud.action_selected.connect(_on_action_selected)
	hud.menu_opened.connect(_do_menu_selection)
	
	# Check for ActionButtons and set toggle states
	var action_buttons = hud.get_node_or_null("Control/ActionButtons")
	if action_buttons:
		var items_button = action_buttons.get_node_or_null("Items")
		if items_button:
			items_button.disabled = not item_toggle
		var run_button = action_buttons.get_node_or_null("Run")
		if run_button:
			run_button.disabled = not run_toggle
	
	# Spawn troop if active_troop is set — await so enemies are ready before first turn
	if active_troop:
		await spawn_troop(active_troop, self)
		# Re-gather enemies after troop spawn
		enemies = []
		for node in get_tree().get_nodes_in_group("enemies"):
			if node is Battler:
				enemies.append(node as Battler)
		# Assign enumeration to newly spawned enemies
		for i in range(enemies.size()):
			var e = enemies[i]
			if e.character_name.is_empty() or e.character_name == "Enemy":
				e.character_name = "Enemy %d" % (i + 1)
			elif not str(i + 1) in e.character_name:
				e.character_name = e.character_name + " %d" % (i + 1)
		# Rebuild turn_order with spawned enemies
		turn_order = players + enemies
		for enemy in enemies:
			hud.on_start_combat(enemy)
			enemy.battle_idle()

	_notify_battlers(BattleEvents.COMBAT_START)
	start_next_turn()


## Sends a battle event ([BattleEvents]) to every battler on the field.
func _notify_battlers(event: StringName) -> void:
	for battler in players + enemies:
		if is_instance_valid(battler):
			battler.notify_battle_event(event, {"battle_manager": self})


## Sends a battle event to every living battler on the team opposing
## [param battler] (each gets its own copy of [param context]).
func notify_opponents_of(battler: Battler, event: StringName, context: Dictionary = {}) -> void:
	var opponents: Array = enemies if battler.team == Battler.TEAM.ALLY else players
	for opponent in opponents.duplicate():
		if is_instance_valid(opponent) and opponent != battler and opponent.current_health > 0:
			var ctx := context.duplicate()
			ctx["battle_manager"] = self
			opponent.notify_battle_event(event, ctx)


func count_allies():
	# The party size is however many ally battlers actually took the field
	# (drives escape difficulty penalties below).
	battle_settings.ally_party = maxi(1, players.size())

# See _ready() -> SignalBus.select_target.connect() ... Emitted from Battler
func target_selected(target: Battler) -> void:
	if !in_target_selection or !target.is_selectable:
		return
	
	# Check if there's a pending card from card combat
	var pending_card = get_meta("pending_card") if has_meta("pending_card") else null
	
	# AOE card: clicking any of its targets confirms all of them
	if pending_card and _is_aoe_targeting():
		confirm_target_selection()
		return
	
	if pending_card:
		set_meta("pending_card", null)
		in_target_selection = false
		mouse_input_toggle = false
		
		# Clean up target highlights
		for battler in valid_targets:
			if battler is Battler:
				battler.is_valid_target = false
				battler.is_selectable = false
				battler.deselect_as_target()
		valid_targets.clear()
		
		# The card's execution request frames the target (see play_card)
		
		# Targeting UI (incl. the contextual Back) is hidden when play_card() sets
		# CARD_EXECUTION_STATE
		
		var card_battle_manager = get_tree().get_first_node_in_group("card_battle_manager")
		if card_battle_manager:
			_execute_card_async(card_battle_manager, pending_card, target)
		return
		
	# Clear ALL targets' selection states first - only ONE highlight allowed
	for battler in valid_targets:
		if battler is Battler:
			battler.deselect_as_target()
	
	# Clear controller target reference
	current_controller_target = null
	
	# Save this as the last selected target for future reference
	last_selected_target = target
	
	# Update keyboard index to match mouse selection
	if target in valid_targets:
		keyboard_target_index = valid_targets.find(target)
	
	current_target = target
	_use_action_on_target()

## The core turn loop. Called at the end of every turn and at battle start.
## Checks win/loss conditions, skips defeated battlers, then delegates to
## [method player_turn] or [method enemy_turn].
## To run code every turn, add it here after the battle-over check.
func start_next_turn():
	# Check if battle is over before proceeding
	if is_battle_over():
		if all_defeated(players):
			end_battle(BattleEndCondition.DEFEAT)
		elif all_defeated(enemies):
			end_battle(BattleEndCondition.WIN)
		else:
			#Fallthrough
			end_battle()
		return
		
	# Ensure we have valid characters in turn order
	if turn_order.is_empty():
		end_battle()
		return

	# If it's the very first turn of the battle, do a cinematic intro with default camera
	if is_first_turn:
		is_first_turn = false
		if battle_camera:
			battle_camera.request_shot(&"turn", BattleCamera.ShotPriority.TURN, BattleCamera.CameraMode.DEFAULT)
		# Pause for a dramatic moment
		await get_tree().create_timer(1.5 / speed_multiplier).timeout

	# Reset turn-based flags
	is_turn_transitioning = false

	# A reactive counter can defeat the acting enemy before its original attack
	# coroutine reaches end_turn(). Battler.take_damage() removes that enemy from
	# turn_order immediately, so current_turn may temporarily equal the old
	# array size. Normalize the index before accessing it; this also protects
	# against any other asynchronous removal that changes the queue mid-turn.
	if turn_order.is_empty():
		end_battle()
		return
	current_turn = current_turn % turn_order.size()
	current_character = turn_order[current_turn]
	current_battler = current_character
	# Nothing from the last turn (targeting, a card) may keep the camera
	if battle_camera:
		battle_camera.release_all_shots_except([&"turn"])
	
	# Every battler's states hear that a turn starts (per-turn limits...)
	for battler in turn_order:
		for state in battler.active_states.values():
			if state is State:
				state.on_any_turn_start(battler)
	
	# A state that skips turns (Chilled, Stunned, ...) skips this one. Decided
	# before durations tick: this skipped turn is what uses the state up
	var skips_turn := false
	for state in current_character.active_states.values():
		if state is State and state.skip_turn:
			skips_turn = true
			break

	# Process states at the start of the turn (for Burning damage, etc.)
	var acting: Battler = current_character
	if current_battler and current_battler.has_method("process_states"):
		current_battler.process_states()

	# Its states' damage defeated it: the defeat already moved the battle on
	# (next turn or battle end). If it didn't, skip this battler's turn here
	if not is_instance_valid(acting) or acting.is_defeated():
		if current_character == acting:
			turn_order.erase(acting)
			if turn_order.is_empty():
				end_battle()
				return
			current_turn = current_turn % turn_order.size()
			start_next_turn()
		return
	
	if current_battler:
		current_battler.notify_battle_event(BattleEvents.TURN_START, {"battle_manager": self})
	
	if skips_turn:
		end_turn()
		return
	
	if current_character.is_defeated():
		turn_order.erase(current_character)
		current_turn = current_turn % turn_order.size()
		start_next_turn()
		return
	
	if hud and hud.has_method("update_turn_queue"):
		hud.update_turn_queue(turn_order, current_turn)
	elif hud and hud.turn_queue_ui:
		hud.turn_queue_ui.update_queue(turn_order, current_turn)
	
	if current_character in players:
		# Reset original position flag at start of turn
		if current_character.has_method("reset_original_position_flag"):
			current_character.reset_original_position_flag()
		# Save original position before any movement in player turn
		if current_character.has_method("save_original_position"):
			current_character.save_original_position()
		player_turn(current_character)
		if battle_camera:
			battle_camera.request_shot(&"turn", BattleCamera.ShotPriority.TURN, BattleCamera.CameraMode.OVER_THE_SHOULDER, current_character)
		# Start card combat turn for player
		if card_integration:
			var card_battle_manager = get_tree().get_first_node_in_group("card_battle_manager")
			if card_battle_manager:
				card_battle_manager.start_player_turn()
		# Player turn is driven by input — don't await, return here.
		update_hud()
		return
	else:
		if hud:
			if hud.has_method("set_ui_state"):
				hud.set_ui_state(3) # CARD_EXECUTION_STATE
		# MUST await so the enemy's entire action resolves before update_hud/next turn
		await enemy_turn(current_character)
	
	update_hud()

func update_hud():
	if not hud:
		return
	hud.update_character_info()
	# Guard against out-of-bounds access if turn_order changed mid-turn
	if turn_order.is_empty() or current_turn >= turn_order.size():
		if hud and hud.has_method("set_ui_state"):
			hud.set_ui_state(3) # CARD_EXECUTION_STATE
		return
	# Don't show action buttons for players (they use cards now)
	# Only show for items/run if needed
	if turn_order[current_turn] in players and not is_animating:
		hud.show_action_buttons(turn_order[current_turn])
	else:
		if hud and hud.has_method("set_ui_state"):
			hud.set_ui_state(3) # CARD_EXECUTION_STATE

var queued_item:Item
func _on_action_selected(action: String, usable:Item = null):
	match action:
		"run":
			escape_battle()
			return
		"item":
			if usable is Item:
				queued_item = usable
				_do_item_target_selection()
			return

var current_controller_target: Battler = null
var valid_targets: Array = []  # Array of Battler objects
var current_default_selector: Battler = null  # Track who has the default selection
var last_selected_target: Battler = null  # Remember last target for next selection
var keyboard_target_index: int = 0  # Track keyboard navigation position

@onready var spawn_effect: PackedScene = preload("res://assets/effects/ground/spawn_digital_rise.tscn")
@onready var healing_effect: PackedScene = preload("res://assets/effects/auras/aura_healing.tscn")

## Play spawn effect for an ally
func _play_spawn_effect(battler: Battler) -> void:
	if not spawn_effect:
		return
	
	var spawn_instance = spawn_effect.instantiate()
	get_tree().current_scene.add_child(spawn_instance)
	spawn_instance.global_position = battler.global_position
	
	# The VFXInstance has autoplay and one_shot enabled, so it handles its own timing
	# Wait for the effect to finish, then cleanup
	if spawn_instance.has_signal("finished"):
		spawn_instance.finished.connect(func():
			if is_instance_valid(spawn_instance):
				spawn_instance.queue_free()
		)
	else:
			# Fallback timer if no finished signal
			await get_tree().create_timer(2.0).timeout
			if is_instance_valid(spawn_instance):
				spawn_instance.queue_free()

## Play healing effect for a battler
func _play_healing_effect(battler: Battler) -> void:
	if not healing_effect:
		return
	
	var healing_instance = healing_effect.instantiate()
	battler.add_child(healing_instance)
	
	# Play open animation
	if healing_instance.has_node("AnimationPlayer"):
		var anim_player = healing_instance.get_node("AnimationPlayer")
		if anim_player:
			anim_player.play("open")
	
	# Auto-cleanup after effect finishes using the finished signal
	if healing_instance.has_signal("finished"):
		healing_instance.finished.connect(func():
			if is_instance_valid(healing_instance):
				if healing_instance.has_node("AnimationPlayer"):
					var anim_player = healing_instance.get_node("AnimationPlayer")
					if anim_player:
						anim_player.play("close")
						await anim_player.animation_finished
				healing_instance.queue_free()
		)
	else:
			# Fallback timer if no finished signal
		await get_tree().create_timer(1.0).timeout
		if is_instance_valid(healing_instance):
			if healing_instance.has_node("AnimationPlayer"):
				var anim_player = healing_instance.get_node("AnimationPlayer")
				if anim_player:
					anim_player.play("close")
			await get_tree().create_timer(0.2).timeout
			if is_instance_valid(healing_instance):
				healing_instance.queue_free()

## Populates [member valid_targets] based on the queued item's target type and highlights the default.
## For multi-target items, skips manual selection and targets all valid targets immediately.
## Cancels back to the action menu if the item can't be used or no valid targets exist.
func _do_item_target_selection() -> void:
	in_target_selection = true
	current_target = null
	valid_targets.clear()
	
	# First, clear all targeting states
	for battler in get_tree().get_nodes_in_group("players") + get_tree().get_nodes_in_group("enemies"):
		if battler is Battler:
			battler.clear_all_selections()
			battler.is_valid_target = false
			battler.is_selectable = false
	
	# Get fresh data from scene to avoid array corruption issues
	var current_enemies: Array = []
	var current_players: Array = []
	
	for node in get_tree().get_nodes_in_group("enemies"):
		if node is Battler:
			current_enemies.append(node as Battler)
	
	for node in get_tree().get_nodes_in_group("players"):
		if node is Battler:
			current_players.append(node as Battler)
	
	# Set valid targets based on item type
	if queued_item:
		# Simple targeting: items target enemies for damage, allies for healing
		# Item.hp_delta: negative = damage, positive = healing
		if queued_item.hp_delta < 0:
			valid_targets = current_enemies if current_character in current_players else current_players
		elif queued_item.hp_delta > 0:
			valid_targets = current_players if current_character in current_players else current_enemies
		else:
			valid_targets = [current_character]  # Default to self for other items

	# Check if we have any valid targets
	if valid_targets.is_empty():
		_cancel_action_target_selection()
		return
	
	# Enable only valid targets
	for target in valid_targets:
		if target is Battler:
			target.is_valid_target = true
			target.is_selectable = true

	# Set initial controller target - prioritize last selected target
	if valid_targets.size() > 0:
		var initial_target = valid_targets[0]
		
		# If we have a last selected target and it's still valid, use it
		if last_selected_target and last_selected_target in valid_targets:
			initial_target = last_selected_target
			keyboard_target_index = valid_targets.find(last_selected_target)
		else:
			keyboard_target_index = 0
		
		# Clear all targets first, then set ONLY the default target
		for battler in valid_targets:
			if battler is Battler:
				battler.deselect_as_target()
		
		current_controller_target = initial_target
		current_default_selector = current_controller_target
		current_controller_target.set_as_default_target()
	
	# Enable mouse input for item targeting (lets Battler._input_event fire on click)
	mouse_input_toggle = true
	
	# Switch cursor to targeting mode
	if hud and hud.has_method("set_targeting_mode"):
		hud.set_targeting_mode(true)
	
	SignalBus.allow_select_target.emit(true)

# Helper function for multiple target selection
func _auto_select_multiple_targets() -> void:
	for target in valid_targets:
		if target is Battler:
			target.is_valid_target = true
			target.is_selectable = true
			target.is_targeted = true
	if valid_targets.size() > 0 and valid_targets[0] is Battler:
		current_target = valid_targets[0]
		_use_action_on_target()

# Mouse clicks are handled in _input (not _unhandled_input) because the
# BattleHUD's full-screen Control node consumes mouse events during GUI
# processing, which runs AFTER _input but BEFORE _unhandled_input.
# Enhanced controller/keyboard input handling during targeting
func _unhandled_input(event: InputEvent) -> void:
	# Only process targeting mode inputs
	if !in_target_selection or valid_targets.is_empty():
		return
	
	# Only process key press events, not key release events
	if event is InputEventKey and not event.pressed:
		return
	
	var handled = false
	var current_time = Time.get_ticks_msec() / 1000.0
	
	# Handle targeting-specific inputs only
	# D-pad navigation (instant) - only left/right, not up/down
	if event.is_action_pressed("ui_right") or event.is_action_pressed("ui_left"):
		_cycle_controller_target(1 if event.is_action_pressed("ui_right") else -1)
		handled = true
	# Explicitly reject up/down navigation to prevent WASD W/S from cycling
	elif event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down"):
		handled = true  # Consume the input but don't cycle
	# RB/LB button navigation (instant)
	elif event.is_action_pressed("cycle_target_forward") or event.is_action_pressed("cycle_target_backward"):
		_cycle_controller_target(1 if event.is_action_pressed("cycle_target_forward") else -1)
		handled = true
	# Joystick navigation (stepped with cooldown) - only left/right axis
	elif event is InputEventJoypadMotion:
		var axis_value = event.axis_value
		if event.axis == 0:  # Left/right axis only
			# Determine direction
			var new_direction = 0
			if axis_value > target_navigation_threshold:
				new_direction = 1
			elif axis_value < -target_navigation_threshold:
				new_direction = -1

			# If direction changed, reset cooldown and navigate immediately
			if new_direction != 0 and new_direction != target_joystick_active_direction:
				target_joystick_active_direction = new_direction
				last_target_navigation_time = current_time
				_cycle_controller_target(new_direction)
				handled = true
			# If same direction, check cooldown
			elif new_direction != 0 and current_time - last_target_navigation_time > target_navigation_cooldown:
				last_target_navigation_time = current_time
				_cycle_controller_target(new_direction)
				handled = true
			# Reset if joystick centered
			elif abs(axis_value) < 0.2:
				target_joystick_active_direction = 0
	elif event.is_action_pressed("ui_accept"):
		confirm_target_selection()
		handled = true
	elif event.is_action_pressed("ui_cancel"):
		# Same path as the HUD's Back button
		if hud and hud.has_method("_on_global_back_pressed"):
			hud._on_global_back_pressed()
		else:
			_cancel_action_target_selection()
		handled = true
	
	# Only consume input if we actually handled it
	if handled:
		get_viewport().set_input_as_handled()

# Camera raycasting for mouse target selection
## The battler under [param root_mouse_pos] (root/HUD space) that the ray can
## hit; battlers that aren't valid targets are excluded so they never block.
## Shared by mouse click targeting and the hover check in _process.
func _raycast_battler_at(root_mouse_pos: Vector2) -> Battler:
	var cam: Camera3D = battle_camera.get_camera() if battle_camera else null
	if not cam:
		return null
	# project_ray_origin/normal already convert from root HUD space → SubViewport space
	var ray_origin = battle_camera.project_ray_origin(root_mouse_pos)
	var ray_direction = battle_camera.project_ray_normal(root_mouse_pos)

	# Create ray parameters
	var ray_params = PhysicsRayQueryParameters3D.new()
	ray_params.from = ray_origin
	ray_params.to = ray_origin + ray_direction * 1000
	ray_params.collision_mask = 0xFFFFFFFF  # All layers — must hit enemies AND allies

	# Exclude battlers that are NOT valid targets from raycast
	# This prevents blocking while allowing both enemy and ally selection
	var exclude_bodies: Array[RID] = []
	var all_battlers = get_tree().get_nodes_in_group("players") + get_tree().get_nodes_in_group("enemies")
	for battler in all_battlers:
		if battler is Battler and is_instance_valid(battler):
			# Only exclude if this battler is NOT a valid target
			if battler not in valid_targets:
				# Add the battler and all its collision bodies to exclude list
				_find_and_exclude_collision_bodies(battler, exclude_bodies)

	ray_params.exclude = exclude_bodies

	# Resolve the 3D physics space state (critical when inside a SubViewport)
	var space_state: PhysicsDirectSpaceState3D = null
	if cam.get_world_3d():
		space_state = cam.get_world_3d().direct_space_state
	elif cam.get_viewport() and cam.get_viewport().find_world_3d():
		space_state = cam.get_viewport().find_world_3d().direct_space_state
	elif get_world_3d():
		space_state = get_world_3d().direct_space_state

	if not space_state:
		push_warning("[MouseTarget] Could not obtain PhysicsDirectSpaceState3D for raycasting!")
		return null

	var result = space_state.intersect_ray(ray_params)

	if not result.has("collider"):
		return null
	# The Battler node: the collider itself or one of its ancestors
	var node: Node = result["collider"]
	while node and not node is Battler:
		node = node.get_parent()
	return node as Battler


func _handle_mouse_click_target_selection() -> void:
	if not battle_camera:
		push_warning("[MouseTarget] battle_camera is null — assign it in the Inspector!")
		return

	var is_aoe := _is_aoe_targeting()

	var battler: Battler = _raycast_battler_at(get_viewport().get_mouse_position())
	if battler:
		if battler and battler is Battler:
			# Check if this is a valid target
			if battler.is_selectable and battler.is_valid_target:
				# AOE card: a click on any of its targets confirms all of them -
				# no single target is ever selected or focused
				if is_aoe and has_meta("pending_card") and get_meta("pending_card"):
					confirm_target_selection()
					return
				# If this battler is already the currently selected target, execute action/card
				if current_controller_target == battler or battler.is_keyboard_selected or battler.is_default_target:
					current_target = battler
					var pending_card = get_meta("pending_card") if has_meta("pending_card") else null
					if pending_card:
						var card_battle_manager = get_tree().get_first_node_in_group("card_battle_manager")
						if card_battle_manager:
							_execute_card_async(card_battle_manager, pending_card, current_target)
						set_meta("pending_card", null)
						exit_targeting_mode()
					else:
						_use_action_on_target()
					return

				# Otherwise: first click selects and focuses the target
				# Clear ALL targets' selection states first - only ONE highlight allowed
				for t in valid_targets:
					if t is Battler:
						t.deselect_as_target()

				# Update index if the clicked target is in valid_targets
				var idx = valid_targets.find(battler)
				if idx != -1:
					keyboard_target_index = idx

				current_controller_target = battler
				current_default_selector = battler
				current_target = battler
				battler.set_as_keyboard_target()

				# Move camera to focus on the newly selected target
				if battle_camera:
					battle_camera.request_shot(&"targeting", BattleCamera.ShotPriority.TARGETING, BattleCamera.CameraMode.TARGET_FOCUS, battler)

## Recursively find and exclude all collision bodies in a node tree
func _find_and_exclude_collision_bodies(node: Node, exclude_list: Array[RID]) -> void:
	if not node or not is_instance_valid(node):
		return

	# If this is a physics body, add its RID to exclude list
	if node is PhysicsBody3D:
		exclude_list.append(node.get_rid())

	# If this is a collision shape, add its parent physics body to exclude list
	if node is CollisionShape3D or node is CollisionPolygon3D:
		var parent = node.get_parent()
		if parent and parent is PhysicsBody3D:
			exclude_list.append(parent.get_rid())

	# Recursively check children
	for child in node.get_children():
		_find_and_exclude_collision_bodies(child, exclude_list)

## True while picking an AOE card's targets (they're all picked together).
func _is_aoe_targeting() -> bool:
	return in_target_selection and bool(get_meta("is_aoe_mode", false))


func _cycle_controller_target(direction: int) -> void:
	# AOE: all targets are already picked; nothing to cycle
	if _is_aoe_targeting():
		return
	
	# Clear ALL targets' selection states first - only ONE highlight allowed
	for battler in valid_targets:
		if battler is Battler:
			battler.deselect_as_target()

	# Determine if we're targeting enemies or allies based on the first valid target
	var targeting_enemies = false
	if valid_targets.size() > 0 and valid_targets[0] is Battler:
		targeting_enemies = valid_targets[0] in enemies

	# Use the authoritative array for order (enemies or players)
	var ordered_battlers = enemies if targeting_enemies else players

	# Invert direction for enemies since they face the center while allies face away
	var actual_direction = direction
	if targeting_enemies:
		actual_direction = -direction

	# Find current target's index in the ordered array
	var current_index = -1
	if current_controller_target and current_controller_target in ordered_battlers:
		current_index = ordered_battlers.find(current_controller_target)
	else:
		# If no current target or it's not in the array, start from first valid target
		for i in range(ordered_battlers.size()):
			if ordered_battlers[i] in valid_targets:
				current_index = i
				break

	# If still no valid target found, return
	if current_index == -1:
		return

	# Cycle through the ordered array, skipping invalid targets
	var new_index = current_index
	var attempts = 0
	var max_attempts = ordered_battlers.size()

	while attempts < max_attempts:
		new_index += actual_direction

		# Wrap around
		if new_index >= ordered_battlers.size():
			new_index = 0
		elif new_index < 0:
			new_index = ordered_battlers.size() - 1

		# Check if this target is valid
		if ordered_battlers[new_index] in valid_targets:
			# Found a valid target
			break

		attempts += 1

	# If we couldn't find a valid target after full cycle, return
	if attempts >= max_attempts:
		return

	# Set new keyboard target
	var new_target = ordered_battlers[new_index]
	if new_target is Battler:
		current_controller_target = new_target
		current_default_selector = current_controller_target
		current_controller_target.set_as_keyboard_target()

		# Update keyboard_target_index to match the valid_targets array for mouse selection
		keyboard_target_index = valid_targets.find(new_target)

		# Move camera to show the newly highlighted target
		if battle_camera:
			battle_camera.request_shot(&"targeting", BattleCamera.ShotPriority.TARGETING, BattleCamera.CameraMode.TARGET_FOCUS, current_controller_target)

## Execute AOE projectile card - calculates center position and passes targets via context
## Plays an AOE card as one cast on every target: like any card it goes
## through [method CardBattleManager.play_card] (AP cost, events, discard), and
## the cast's [AoeContext] makes it resolve on all of them.
func _execute_aoe_card(pending_card: CardConfig, aoe_targets: Array) -> void:
	var context := AoeContext.from_targets(aoe_targets)
	var card_battle_manager = get_tree().get_first_node_in_group("card_battle_manager")
	if hud and hud.has_method("hide_aoe_confirmation_mode"):
		hud.hide_aoe_confirmation_mode()
	if card_battle_manager and not context.targets.is_empty():
		await _execute_card_async(card_battle_manager, pending_card, context.targets[0], context)

## Cancels the current target selection: battle-side cleanup here, then the HUD
## decides where the UI goes (back to the menu targeting started from).
func cancel_target_selection() -> void:
	_cancel_action_target_selection()

func _cancel_action_target_selection() -> void:
	exit_targeting_mode()
	# A card released to play but cancelled during targeting goes back to its
	# fan slot (otherwise it stays floating where it was dropped)
	var card_ui_node = get_tree().get_first_node_in_group("card_ui")
	if card_ui_node and card_ui_node.has_method("return_pending_card_to_hand"):
		card_ui_node.return_pending_card_to_hand()
	current_target = null
	current_controller_target = null
	current_default_selector = null
	keyboard_target_index = 0
	valid_targets.clear()
	
	# Clear queued item
	queued_item = null
	
	# Clear all targeting states for all battlers
	for battler in get_tree().get_nodes_in_group("players") + get_tree().get_nodes_in_group("enemies"):
		if battler is Battler:
			battler.clear_all_selections()
			# Reset to default selectable state
			battler.is_valid_target = true
			battler.is_selectable = true
	
	SignalBus.allow_select_target.emit(false)
	# UI: back to the menu the targeting came from (cards / items / base)
	if hud and hud.has_method("on_targeting_cancelled"):
		hud.on_targeting_cancelled()
	else:
		hud.show_action_buttons(current_character)

func _do_menu_selection() -> void:
	in_menu_selection = true

## Executes the queued action on [member current_target] then calls [method end_turn].
## Awaits animation completion for "attack" and "skill" so the next turn does not start
## until the current action visually resolves. Items resolve immediately without awaiting.
func _use_action_on_target() -> void:
	if !current_target:
		_cancel_action_target_selection()
		return
	
	# Card combat pending_card takes priority over queued_item
	var pending_card = get_meta("pending_card") if has_meta("pending_card") else null
	if pending_card:
		set_meta("pending_card", null)
		in_target_selection = false
		mouse_input_toggle = false
		for battler in valid_targets:
			if battler is Battler:
				battler.is_valid_target = false
				battler.is_selectable = false
				battler.deselect_as_target()
		valid_targets.clear()
		if hud and hud.has_method("set_ui_state"):
			hud.set_ui_state(3) # CARD_EXECUTION_STATE (also hides the contextual Back)
		var card_battle_manager = get_tree().get_first_node_in_group("card_battle_manager")
		if card_battle_manager:
			_execute_card_async(card_battle_manager, pending_card, current_target)
		return
	
	if !queued_item:
		_cancel_action_target_selection()
		return
	
	# exit_targeting_mode() clears current_target, so keep it for the item use
	var item_target: Battler = current_target
	exit_targeting_mode()
	in_menu_selection = false
	is_animating = true
	if hud and hud.has_method("set_ui_state"):
		hud.set_ui_state(3) # CARD_EXECUTION_STATE
	
	current_character.battle_item(queued_item, item_target)
	
	queued_item = null
	SignalBus.allow_select_target.emit(false)
	end_turn()

## [param use_stat_formula]: false for bonus damage that is already final
## (weapon procs, ...): it skips the attack/defense formula but still goes
## through hit chance, damage multipliers, Marked, shields and the rest. Such
## damage is not an attack, so it never triggers on-hit effects.
## [param crit_multiplier]: above 1 the hit is a crit (rolled by the caller,
## e.g. a card effect); it scales the damage and shows as a crit.
func damage_calculation(attacker, target, damage, attack_config: EnemyAttackConfig = null, damage_type: String = "physical", element: String = "none", use_stat_formula: bool = true, crit_multiplier: float = 1.0) -> void:
	# Safety check - if damage is 0, don't process
	if damage <= 0:
		return
	
	# Damage type / element: the parameters, else the enemy attack's config
	var final_damage_type = damage_type
	var final_element = element
	if attack_config:
		if final_damage_type == "physical" and not attack_config.damage_type.is_empty():
			final_damage_type = attack_config.damage_type
		if final_element == "none" and not attack_config.element.is_empty():
			final_element = attack_config.element

	var is_critical := crit_multiplier > 1.0
	var hit := {"attacker": attacker, "target": target, "damage_type": final_damage_type,
			"element": final_element, "is_attack": use_stat_formula, "is_critical": is_critical}

	# The attacker's states set the chance it lands (several multiply)
	var hit_chance := 100.0
	for state in attacker.active_states.values():
		if state is State:
			hit_chance = state.modify_hit_chance(hit_chance, attacker, hit)
	if randf_range(0.0, 100.0) > hit_chance:
		return  # Miss - no damage applied

	if use_stat_formula:
		damage = Formulas.damage(attacker, target, damage, final_damage_type)
	else:
		damage = maxi(1, roundi(damage))
	if is_critical:
		damage = roundi(damage * crit_multiplier)

	# The attacker's states shape the damage it deals (Electrocuted, Berserk...),
	# the target's the damage it takes (Marked...)
	for state in attacker.active_states.values():
		if state is State:
			damage = state.modify_damage_dealt(damage, attacker, hit)

	# Passive damage-dealt multipliers (weapon, vestiges, ...)
	damage = roundi(damage * attacker.get_multiplier(&"damage_dealt"))

	# The target's states shape the damage it takes (Marked, Electrocuted...).
	# Blocking a hit and on-hit effects (Protected, Bleed, Taunt, counters)
	# happen in take_damage
	for state in target.active_states.values():
		if state is State:
			damage = state.modify_damage_taken(damage, target, hit)

	# Only apply if damage is still positive after calculation
	if damage > 0:
		# Trigger game feel effects based on damage
		if effect_manager:
			var is_big_damage = damage > (target.max_health * 0.1)
			
			if is_critical:
				effect_manager.trigger_critical_hit()
			elif is_big_damage:
				effect_manager.trigger_big_damage()
			else:
				effect_manager.trigger_normal_hit()
		
		# AWAIT damage so counters complete before continuing
		await target.take_damage(damage, attacker, final_damage_type, final_element, use_stat_formula, is_critical)
		hud.update_health_bars()
		update_hud()

func heal_calculation(_user, target, amount):
	var _healing = target.take_healing(amount)
	hud.update_health_bars()

func enemy_turn(character:Battler) -> void:
	# SET THESE BEFORE AI CHOOSES ACTION
	current_character = character
	current_battler = character
	
	# Reset original position flag at start of turn
	if character.has_method("reset_original_position_flag"):
		character.reset_original_position_flag()
	# Save original position before any movement in enemy turn
	if character.has_method("save_original_position"):
		character.save_original_position()

	# No ally is "active" during an enemy turn - clear any leftover highlight.
	if hud:
		hud.update_party_status()
	
	# Get all players (allies) as targets for enemies
	var available_targets: Array = []
	for node in get_tree().get_nodes_in_group("players"):
		if node is Battler and !node.is_defeated():
			available_targets.append(node)
	
	if available_targets.is_empty():
		end_turn()
		return
	
	var all_enemies = get_tree().get_nodes_in_group("enemies")
	
	# Clear current_target before choosing new one
	current_target = null
	# AWAIT the AI action to complete before ending turn
	await AIManager.choose_action(character, available_targets, all_enemies, self)
	update_hud()
	end_turn()

## Finalises the current turn: processes the active battler's states and SP regen,
## cleans up defeated enemies, resets per-turn flags, advances [member current_turn],
## then calls [method start_next_turn] after a short speed-scaled delay.
## If [member skip_turn] is true (e.g. after a failed escape), state processing is skipped
## and the turn advances immediately.
var is_turn_transitioning: bool = false
var battler_attacking:bool = false
func end_turn():
	if is_turn_transitioning:
		return
	is_turn_transitioning = true
	battler_attacking = false  # RC-D: always clear — ai_manager sets this but never resets it

	if current_battler:
		current_battler.notify_battle_event(BattleEvents.TURN_END, {"battle_manager": self})
	
	if skip_turn:
		skip_turn = false
		current_turn = (current_turn + 1) % max(turn_order.size(), 1)
		is_animating = false
		start_next_turn()
	else:
		# State processing now happens at turn start in start_next_turn()
		# not here at turn end

		# ADVANCE the turn index FIRST, before cleanup removes entries
		# This ensures we always move forward in the queue
		if not turn_order.is_empty():
			current_turn = (current_turn + 1) % turn_order.size()
		
		# Remove defeated battlers from turn_order and arrays.
		# Must happen AFTER advancing, so cleanup adjusts correctly.
		_cleanup_defeated_from_turn_order()
		
		# Clear targeting states
		for battler in get_tree().get_nodes_in_group("players") + get_tree().get_nodes_in_group("enemies"):
			if battler is Battler:
				battler.clear_all_selections()
				battler.is_valid_target = false
				battler.is_selectable = false
		
		# Guard: if turn_order is now empty, end battle
		if turn_order.is_empty():
			end_battle()
			return
		
		# Re-clamp current_turn in case cleanup shrank the array
		current_turn = current_turn % turn_order.size()
		is_animating = false
		
		# Add small delay that respects speed multiplier
		await get_tree().create_timer(0.2 / speed_multiplier).timeout
		start_next_turn()

## Remove any defeated battlers from turn_order, players, and enemies arrays.
## Called AFTER current_turn has already been incremented in end_turn.
## So we only need to shift the index back for entries strictly BEFORE current_turn.
func _cleanup_defeated_from_turn_order() -> void:
	var to_remove: Array[Battler] = []
	for battler in turn_order:
		if not is_instance_valid(battler) or battler.is_defeated():
			to_remove.append(battler)
	
	for battler in to_remove:
		var idx = turn_order.find(battler)
		# Only shift current_turn back if the removed entry was strictly before it.
		# If it's at or after current_turn, the index stays correct.
		if idx >= 0 and idx < current_turn:
			current_turn -= 1
		turn_order.erase(battler)
		players.erase(battler)
		enemies.erase(battler)

## Force turn to advance immediately (safety mechanism for stuck turns)
func force_turn_advance() -> void:
	battler_attacking = false
	end_turn()

func player_turn(character):
	count_allies()
	hud.set_activebattler(character)
	hud.show_action_buttons(character)  # Make sure HUD shows here
	is_animating = false  # Allow player input

func is_battle_over():
	return all_defeated(players) or all_defeated(enemies)

func all_defeated(characters: Array):
	# (A freed battler counts as defeated)
	for character in characters:
		if is_instance_valid(character) and not character.is_defeated():
			return false
	return true

func escape_battle():
	var base_escape_chance = 70
	
	# Reduce chance by 10% for each additional ally
	var ally_penalty = (battle_settings.ally_party - 1) * 10
	
	# Calculate final threshold (base - penalties + difficulty mod)
	var escape_threshold = base_escape_chance - ally_penalty
	
	# Generate random number 1-100
	var roll = randi_range(1, 100)
	
	# Check if escape successful
	if roll <= escape_threshold:
		end_battle(BattleEndCondition.ESCAPE) # Use your existing escape scene transition
		return true
	else:
		skip_turn = true
		end_turn() # Enemy gets a turn after failed escape
		return false

func end_battle(state: BattleEndCondition = BattleEndCondition.WIN):
	# Guard against re-entry: out-of-band kills (parry counters, status effects)
	# may detect the battle is over more than once before the flow advances.
	if battle_finished:
		return
	battle_finished = true
	
	_notify_battlers(BattleEvents.COMBAT_END)
	# ESCAPE always ends the battle abruptly. WIN, Will end the battle and return to normal, DEFEAT will end the battle with game over.
	match state:
		BattleEndCondition.ESCAPE:
			# Show battle results for escape
			show_battle_results()
			
			# Remove defeated enemies with tween (scale instead of modulate)
			for enemy in enemies:
				var tween = create_tween()
				tween.set_parallel(true)
				tween.tween_property(enemy, "position:y", enemy.position.y + 2.0, 1.0)  # Float up
				tween.tween_property(enemy, "scale", Vector3.ONE * 0.01, 1.0)  # Shrink to almost nothing (exactly zero makes the basis singular)
				tween.tween_callback(func(): enemy.queue_free())
			
			await get_tree().create_timer(1.5).timeout
			_finish_battle(state)

		BattleEndCondition.CUTSCENE:
			_finish_battle(state)
			
		BattleEndCondition.WIN:
			# Show battle results screen
			show_battle_results()
			
			# Remove defeated enemies with tween (scale instead of modulate)
			for enemy in enemies:
				var tween = create_tween()
				tween.set_parallel(true)
				tween.tween_property(enemy, "position:y", enemy.position.y + 2.0, 1.0)  # Float up
				tween.tween_property(enemy, "scale", Vector3.ONE * 0.01, 1.0)  # Shrink to almost nothing (exactly zero makes the basis singular)
				tween.tween_callback(func(): enemy.queue_free())
			
			await get_tree().create_timer(1.5).timeout
			_finish_battle(state)

		BattleEndCondition.DEFEAT:
			if hud and hud.has_method("set_ui_state"):
				hud.set_ui_state(3) # CARD_EXECUTION_STATE
			await _play_defeat_sequence()

## Shared exit point for every end condition. Emits [signal battle_ended] so a
## level wrapper can continue the run (next battle / run over / replay).
func _finish_battle(state: BattleEndCondition) -> void:
	if not is_node_alive(): return
	if battle_ended.get_connections().size() > 0:
		battle_ended.emit(state)
		return


## Brief defeat moment: play the defeat sound, then hand control to the level flow.
func _play_defeat_sequence() -> void:
	var defeat_sound : AudioStream = load("res://assets/sounds/defeatsound1.wav")
	if defeat_sound:
		var defeat_player := AudioStreamPlayer.new()
		defeat_player.stream = defeat_sound
		add_child(defeat_player)
		defeat_player.play()
	await get_tree().create_timer(2.0).timeout
	if not is_node_alive(): return
	_finish_battle(BattleEndCondition.DEFEAT)

func update_button_states():
	# ActionButtons are now in BattleHUD, we can access them through HUD
	var action_buttons = hud.get_node_or_null("Control/ActionButtons")
	if action_buttons:
		var items_button = action_buttons.get_node_or_null("Items")
		if items_button:
			items_button.disabled = not item_toggle
		var run_button = action_buttons.get_node_or_null("Run")
		if run_button:
			run_button.disabled = not run_toggle

func exit_targeting_mode():
	in_target_selection = false
	current_target = null
	current_controller_target = null
	current_default_selector = null
	keyboard_target_index = 0
	
	# Disable all valid targets
	for battler in valid_targets:
		if battler is Battler:
			battler.is_valid_target = false
			battler.is_selectable = false
			battler.deselect_as_target()
	
	valid_targets.clear()
	
	# Clear pending card if exists (prevents targeting loop on cancel)
	if has_meta("pending_card"):
		set_meta("pending_card", null)
	
	# Clear AOE mode metadata
	if has_meta("is_aoe_mode"):
		set_meta("is_aoe_mode", false)
	if has_meta("target_type"):
		set_meta("target_type", null)
	
	# Disable mouse input when done targeting
	mouse_input_toggle = false
	
	# Update HUD: hide cancel target button, show cards and action buttons
	if hud and hud.has_method("set_targeting_mode"):
		hud.set_targeting_mode(false)
	
	# Back to whatever is below targeting (a card executing, else the turn shot)
	if battle_camera:
		battle_camera.release_shot(&"targeting")

## Confirms the current target selection. Shared by the Confirm/ui_accept input
## actions and the on-screen contextual confirm button in the battle HUD.
func confirm_target_selection() -> void:
	if not in_target_selection:
		return
	var pending_card = get_meta("pending_card") if has_meta("pending_card") else null

	# AOE mode: confirm on all targets at once, no single target selection needed
	if pending_card and has_meta("is_aoe_mode") and get_meta("is_aoe_mode"):
		# Not awaited: targeting ends now, so it can't be confirmed twice
		_execute_aoe_card(pending_card, valid_targets.duplicate())
		set_meta("pending_card", null)
		exit_targeting_mode()
		return

	var target: Battler = current_target if current_target else current_controller_target
	if not target and current_default_selector in valid_targets:
		target = current_default_selector
	if target:
		current_target = target

	if pending_card:
		# Non-AOE: requires a single target to be selected
		if not target:
			return
		var card_battle_manager = get_tree().get_first_node_in_group("card_battle_manager")
		if card_battle_manager:
			_execute_card_async(card_battle_manager, pending_card, current_target)
		set_meta("pending_card", null)
		exit_targeting_mode()
	elif queued_item:
		_use_action_on_target()

func _execute_card_async(card_battle_manager: CardBattleManager, card: CardConfig, target: Battler, aoe: AoeContext = null):
	# Helper function to execute card asynchronously
	await card_battle_manager.play_card(card, target, aoe)

## Display and populate battle results screen
## Shows victory/defeat results and waits for player input to continue
func show_battle_results() -> void:
	if not hud:
		return
	
	# Find the battle results scene (node is named "Results" in HUD)
	var battle_results = hud.find_child("Results", true, false)
	if battle_results:
		# Populate battle results with player stats before showing
		populate_battle_results(battle_results)
		
		# Make visible and fade in
		battle_results.visible = true
		if battle_results is CanvasItem:
			battle_results.modulate.a = 0.0
			
			var tween = create_tween()
			tween.tween_property(battle_results, "modulate:a", 1.0, 0.5)
			await tween.finished
		
		# Wait for player input to continue
		
		# Safety check: ensure we're still in tree before awaiting
		while is_node_alive() and not Input.is_action_just_pressed("ui_accept"):
			await get_tree().process_frame
		
		if not is_node_alive():
			return
		
		# Fade out when done
		if battle_results is CanvasItem:
			var fade_out = create_tween()
			fade_out.tween_property(battle_results, "modulate:a", 0.0, 0.3)
		battle_results.visible = false

## Helper to check if node is still alive
func is_node_alive() -> bool:
	return is_instance_valid(self) and is_inside_tree()

## Populate battle results with player stats and rewards
func populate_battle_results(_results_node: Node) -> void:
	pass
	# Update results node with battle information
	
	# You can add more specific population logic here
	# For example:
	# - Show defeated enemies
	# - Show experience gained per player
	# - Show items obtained
	# This depends on your BattleResults scene structure
