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
# Defualt animation should check for weapon's later down the road, And adapt to using them with unique animations.
@export var default_animation = "Locomotion-Library/idle2" # Unused, But i reccomend gettomg the stats and animation from the database.
# Added by repo owner, Fame. To test compatibility with returning after a battle.
@export var game_map = "res://replace/regular_map/backtogame.tscn"
@onready var hud: BattleHud = $BattleHUD

# Toggles For Battles
@export_group("Toggle Buttons")
@export var item_toggle: bool = true
@export var run_toggle: bool = true
@export var mouse_input_toggle: bool = true

# Movement Animation System
@export_group("Movement Animation System", "movement")
@export var enable_movement_to_target: bool = true
@export var movement_distance_threshold: float = 2.0
@export var movement_speed: float = 4.0
@export var walking_forward_animation: String = "run"

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
@export var movement_timeout_seconds: float = 5.0  ## Max time a battler can be stuck advancing before auto-return.
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
		print("Warning: Animation type '", animation_type, "' not found in dictionary. Available keys: ", animation_dictionary.keys())
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
	
	print("Spawning troop: ", troop.troop_name)
	
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
		
		# Connect damage signal
		if not enemy.anim_damage.is_connected(_on_anim_damage):
			enemy.anim_damage.connect(_on_anim_damage)
		
		# Set battle idle state
		enemy.battle_idle()
		hud.on_start_combat(enemy)
		
		print("Spawned enemy: ", enemy.character_name, " at position ", spawn_position)

# Spawn additional enemies during battle (for troop-to-troop battles that continue)
func spawn_reinforcements(troop: Troops, parent_node: Node3D = self) -> void:
	if not troop or not troop.enemy_group or troop.enemy_group.enemy_scenes.is_empty():
		push_error("Invalid troop or no enemy group/scenes defined!")
		return
	
	print("Spawning reinforcements: ", troop.troop_name)
	
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
		
		# Connect damage signal
		if not enemy.anim_damage.is_connected(_on_anim_damage):
			enemy.anim_damage.connect(_on_anim_damage)
		
		# Set battle idle state
		enemy.battle_idle()
		hud.on_start_combat(enemy)
		
		print("Spawned reinforcement: ", enemy.character_name, " at position ", spawn_position)

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
		print("Cleaning up defeated enemy: ", enemy.character_name)
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

func _ready():
	add_to_group("battle_manager")
	SignalBus.select_target.connect(target_selected)
	
	print("BattleManager _ready() called")
	print("HUD found: ", hud != null)
	
	# Instantiate dynamic combat camera controller
	battle_camera = BattleCamera.new()
	battle_camera.name = "BattleCameraController"
	add_child(battle_camera)
	
	# Initialize card integration
	initialize_card_integration()
	
	# Initialize battle
	initialize_battle()

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

func _input(event: InputEvent) -> void:
	# Handle speed key
	if speed_is_toggle:
		# Toggle mode - press once to toggle on/off
		if event.is_action_pressed(speed_key):
			is_speed_active = !is_speed_active
			speed_multiplier = speed_increase_amount if is_speed_active else 1.0
			print("Battle speed ", "increased" if is_speed_active else "returned to normal", ": ", speed_multiplier, "x")
	else:
		# Hold mode - hold key to speed up
		if event.is_action_pressed(speed_key):
			is_speed_active = true
			speed_multiplier = speed_increase_amount
			print("Battle speed increased to: ", speed_multiplier, "x")
		elif event.is_action_released(speed_key):
			is_speed_active = false
			speed_multiplier = 1.0
			print("Battle speed returned to normal")
	
	# Cancel is currently bound to Escape key
	if event.is_action_pressed("Cancel"):
		print("Pressed cancel")
		if in_target_selection:
			print("Cancelling Target Selection")
			_cancel_action_target_selection()
		elif in_menu_selection:
			print("Cancelling Menu Selection")
			_cancel_menu_selection()
	# Confirm is currently bound to Enter key
	elif event.is_action_pressed("Confirm") and in_target_selection and current_target:
		if queued_item:
			_use_action_on_target()
		else:
			printerr("MANAGER: No item queued!")
			print("Item: ", queued_item)

func initialize_battle():
	print("=== INITIALIZE BATTLE START ===")
	
	# Get all nodes and convert to Battler arrays
	players = []
	enemies = []
	
	for node in get_tree().get_nodes_in_group("players"):
		if node is Battler:
			players.append(node as Battler)
	
	for node in get_tree().get_nodes_in_group("enemies"):
		if node is Battler:
			enemies.append(node as Battler)
	
	print("Players found: ", players.size())
	print("Enemies found: ", enemies.size())
	
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
		hud.on_add_character(player)
		player.battle_idle()
		if not player.anim_damage.is_connected(_on_anim_damage):
			player.anim_damage.connect(_on_anim_damage)
	
	# Ensure players are at the start of the turn order
	turn_order = players + enemies
	print("Current turn order: ", turn_order.map(func(b): return b.character_name))
	
	for enemy in enemies:
		hud.on_start_combat(enemy)
		enemy.battle_idle()
		if not enemy.anim_damage.is_connected(_on_anim_damage):
			enemy.anim_damage.connect(_on_anim_damage)
	
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
	print("ActionButtons found: ", action_buttons != null)
	if action_buttons:
		var items_button = action_buttons.get_node_or_null("Items")
		if items_button:
			items_button.disabled = not item_toggle
		var run_button = action_buttons.get_node_or_null("Run")
		if run_button:
			run_button.disabled = not run_toggle
	
	# Spawn troop if active_troop is set — await so enemies are ready before first turn
	if active_troop:
		print("Active troop detected: ", active_troop.troop_name)
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
			if not enemy.anim_damage.is_connected(_on_anim_damage):
				enemy.anim_damage.connect(_on_anim_damage)
	
	print("=== INITIALIZE BATTLE END ===")
	start_next_turn()


func count_allies():
	# For now, Should be one.
	battle_settings.ally_party = 1

# See _ready() -> SignalBus.select_target.connect() ... Emitted from Battler
func target_selected(target: Battler) -> void:
	print("=== BATTLE MANAGER TARGET SELECTED ===")
	print("Received target: ", target.character_name)
	print("In target selection: ", in_target_selection)
	print("Target is selectable: ", target.is_selectable)
	print("Has pending card: ", has_meta("pending_card"))
	print("Valid targets count: ", valid_targets.size())
	
	if !in_target_selection or !target.is_selectable:
		print("Target selection rejected - not in selection or not selectable")
		print("  - in_target_selection: ", in_target_selection)
		print("  - target.is_selectable: ", target.is_selectable)
		return
	
	# Check if there's a pending card from card combat
	var pending_card = get_meta("pending_card")
	
	# Check if this is AOE mode (no individual targeting)
	var is_aoe_mode = get_meta("is_aoe_mode") if has_meta("is_aoe_mode") else false
	if is_aoe_mode:
		print("AOE mode - individual selection not allowed")
		return
	
	if pending_card:
		print("Card combat targeting: playing card ", pending_card.name, " on ", target.character_name)
		print("Target type: ", current_target_type)
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
		
		# Switch camera to target focus for ally targeting
		if current_target_type == "ally" and battle_camera:
			battle_camera.set_target_focus(target)
		
		# Hide targeting UI and ensure action buttons and cards remain hidden during action execution
		if hud:
			if hud.target_back_button:
				hud.target_back_button.visible = false
			hud.hide_action_buttons()
			if hud.card_ui:
				hud.card_ui.visible = false
		
		var card_battle_manager = get_tree().get_first_node_in_group("card_battle_manager")
		if card_battle_manager:
			_execute_card_async(card_battle_manager, pending_card, target)
		else:
			print("ERROR: CardBattleManager not found!")
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
	print("Set current_target to: ", current_target.character_name)
	print("About to call _use_action_on_target")
	print("=== VISUAL CONFIRMATION ===")
	print("Target with cyan highlight should be: ", target.character_name)
	print("Target that will be attacked: ", current_target.character_name)
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
		print("No characters in turn order, ending battle")
		end_battle()
		return

	# If it's the very first turn of the battle, do a cinematic intro with default camera
	if is_first_turn:
		is_first_turn = false
		if battle_camera:
			battle_camera.set_default_camera()
		# Pause for a dramatic moment
		await get_tree().create_timer(1.5 / speed_multiplier).timeout

	# Reset turn-based flags
	current_turn_timeout_timer = 0.0
	is_turn_transitioning = false

	current_character = turn_order[current_turn]
	current_battler = current_character
	
	# Reset counter usage for all battlers at turn start
	for battler in turn_order:
		if battler.active_states.has("Counter"):
			var counter_state = battler.active_states["Counter"] as CounterState
			if counter_state:
				counter_state.reset_turn_usage()
	
	if current_character.is_defeated():
		turn_order.erase(current_character)
		current_turn = current_turn % turn_order.size()
		start_next_turn()
		return
	
	if hud and hud.has_method("update_turn_queue"):
		hud.update_turn_queue(turn_order, current_turn)
	
	if current_character in players:
		print("Player's turn")
		player_turn(current_character)
		if battle_camera:
			battle_camera.set_over_the_shoulder(current_character)
		# Start card combat turn for player
		if card_integration:
			var card_battle_manager = get_tree().get_first_node_in_group("card_battle_manager")
			if card_battle_manager:
				card_battle_manager.start_player_turn()
		# Player turn is driven by input — don't await, return here.
		update_hud()
		return
	else:
		print("Enemy's turn")
		if hud:
			hud.hide_action_buttons()
			if hud.card_ui:
				hud.card_ui.visible = false
		# MUST await so the enemy's entire action resolves before update_hud/next turn
		await enemy_turn(current_character)
	
	update_hud()

func update_hud():
	if not hud:
		return
	hud.update_character_info()
	# Guard against out-of-bounds access if turn_order changed mid-turn
	if turn_order.is_empty() or current_turn >= turn_order.size():
		hud.hide_action_buttons()
		return
	# Don't show action buttons for players (they use cards now)
	# Only show for items/run if needed
	if turn_order[current_turn] in players and not is_animating:
		hud.show_action_buttons(turn_order[current_turn])
	else:
		hud.hide_action_buttons()

var queued_item:Item
func _on_action_selected(action: String, usable:Item = null):
	print("=== ACTION SELECTED ===")
	print("Action: ", action)
	print("Usable: ", usable)
	print("Current character: ", current_character.character_name)
	
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

## Populates [member valid_targets] based on the queued item's target type and highlights the default.
## For multi-target items, skips manual selection and targets all valid targets immediately.
## Cancels back to the action menu if the item can't be used or no valid targets exist.
func _do_item_target_selection() -> void:
	print("\n=== Starting Target Selection ===")
	print("DEBUG: enemies array before target selection: ", enemies)
	print("DEBUG: players array before target selection: ", players)
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
		print("=== ITEM TARGETING ===")
		print("Item name: ", queued_item.item_name)
		print("Current character in players: ", current_character in current_players)
		
		# Simple targeting: items target enemies for damage, allies for healing
		if queued_item.damage_amount > 0:
			valid_targets = current_enemies if current_character in current_players else current_players
		elif queued_item.heal_amount > 0:
			valid_targets = current_players if current_character in current_players else current_enemies
		else:
			valid_targets = [current_character]  # Default to self for other items

	# Check if we have any valid targets
	if valid_targets.is_empty():
		print("No valid targets found for this item!")
		_cancel_action_target_selection()
		return
	
	# Enable only valid targets
	print("Valid targets found: ", valid_targets.size())
	for target in valid_targets:
		if target is Battler:
			target.is_valid_target = true
			target.is_selectable = true
			print("Enabled target: ", target.character_name)
			print("  - Is valid target: ", target.is_valid_target)
			print("  - Is selectable: ", target.is_selectable)

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
		
		print("Default target set to: ", current_controller_target.character_name)
	
	SignalBus.allow_select_target.emit(true)
	print("=== Target Selection Complete ===\n")

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

# Enhanced controller input handling with better visual feedback
func _unhandled_input(event: InputEvent) -> void:
	# Only process targeting mode inputs
	if !in_target_selection or valid_targets.is_empty():
		return
	
	# Only process key press events, not key release events
	if event is InputEventKey and not event.pressed:
		return
	
	# Only process mouse press events, not mouse release events
	if event is InputEventMouseButton and not event.pressed:
		return
	
	# Handle mouse clicks via camera raycasting
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_mouse_click_target_selection()
		return
	
	var handled = false
	var current_time = Time.get_ticks_msec() / 1000.0
	
	# Handle targeting-specific inputs only
	# D-pad navigation (instant)
	if event.is_action_pressed("ui_right") or event.is_action_pressed("ui_left"):
		_cycle_controller_target(1 if event.is_action_pressed("ui_right") else -1)
		handled = true
	# RB/LB button navigation (instant)
	elif event.is_action_pressed("cycle_target_forward") or event.is_action_pressed("cycle_target_backward"):
		_cycle_controller_target(1 if event.is_action_pressed("cycle_target_forward") else -1)
		handled = true
	# Joystick navigation (stepped with cooldown)
	elif event is InputEventJoypadMotion:
		var axis_value = event.axis_value
		if event.axis == 0:  # Left/right axis
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
		if current_controller_target:
			current_target = current_controller_target
			# Check pending card first (card combat system)
			var pending_card = get_meta("pending_card") if has_meta("pending_card") else null
			if pending_card:
				if battle_camera:
					battle_camera.set_target_focus(current_target)
				var card_battle_manager = get_tree().get_first_node_in_group("card_battle_manager")
				if card_battle_manager:
					_execute_card_async(card_battle_manager, pending_card, current_target)
				set_meta("pending_card", null)
				exit_targeting_mode()
			else:
				_use_action_on_target()
		handled = true
	elif event.is_action_pressed("ui_cancel"):
		_cancel_action_target_selection()
		if in_target_selection:
			exit_targeting_mode()
		handled = true
	
	# Only consume input if we actually handled it
	if handled:
		get_viewport().set_input_as_handled()

# Camera raycasting for mouse target selection
func _handle_mouse_click_target_selection() -> void:
	if not battle_camera:
		return
	
	var viewport = get_viewport()
	var mouse_pos = viewport.get_mouse_position()
	
	# Raycast from camera through mouse position
	var ray_origin = battle_camera.project_ray_origin(mouse_pos)
	var ray_direction = battle_camera.project_ray_normal(mouse_pos)
	
	# Create ray parameters
	var ray_params = PhysicsRayQueryParameters3D.new()
	ray_params.from = ray_origin
	ray_params.to = ray_origin + ray_direction * 1000
	ray_params.collision_mask = 1  # Layer 1 for enemies
	
	# Perform raycast
	var space_state = get_world_3d().direct_space_state
	var result = space_state.intersect_ray(ray_params)
	
	if result.has("collider"):
		var collider = result["collider"]
		# Find the Battler parent node
		var battler = collider.get_parent()
		while battler and not battler is Battler:
			battler = battler.get_parent()
		
		if battler and battler is Battler:
			# Check if this is a valid target
			if battler.is_selectable and battler.is_valid_target:
				current_target = battler
				# Check pending card first (card combat system)
				var pending_card = get_meta("pending_card") if has_meta("pending_card") else null
				if pending_card:
					if battle_camera:
						battle_camera.set_target_focus(current_target)
					var card_battle_manager = get_tree().get_first_node_in_group("card_battle_manager")
					if card_battle_manager:
						_execute_card_async(card_battle_manager, pending_card, current_target)
					set_meta("pending_card", null)
					exit_targeting_mode()
				else:
					_use_action_on_target()

func _cycle_controller_target(direction: int) -> void:
	# Clear ALL targets' selection states first - only ONE highlight allowed
	for battler in valid_targets:
		if battler is Battler:
			battler.deselect_as_target()
	
	# Calculate new index with proper wrapping
	keyboard_target_index += direction
	if keyboard_target_index >= valid_targets.size():
		keyboard_target_index = 0
	elif keyboard_target_index < 0:
		keyboard_target_index = valid_targets.size() - 1
	
	# Set new keyboard target
	if valid_targets.size() > 0 and valid_targets[keyboard_target_index] is Battler:
		current_controller_target = valid_targets[keyboard_target_index]
		current_default_selector = current_controller_target
		current_controller_target.set_as_keyboard_target()
		
		# Move camera to show the newly highlighted enemy
		if battle_camera:
			battle_camera.set_target_focus(current_controller_target)
		
		print("Keyboard navigation: Selected ", current_controller_target.character_name)
		print("Current keyboard index: ", keyboard_target_index)
		print("Valid targets size: ", valid_targets.size())

func _cancel_action_target_selection() -> void:
	print("Cancelling target selection")
	exit_targeting_mode()
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
	
	if in_menu_selection:
		_do_menu_selection()
	else:
		hud.show_action_buttons(current_character)
	SignalBus.allow_select_target.emit(false)

func _cancel_menu_selection() -> void:
	in_menu_selection = false
	
	# Use the systematic menu close functions instead of direct manipulation
	if hud.item_select.visible:
		if hud.has_method("_close_items_menu"):
			hud._close_items_menu()
		else:
			hud.item_select.hide()
	var skill_select = hud.get("skill_select")
	if skill_select:
		skill_select.hide()
	if hud.card_ui:
		hud.card_ui.visible = true
	hud.show_action_buttons(current_character)

func _do_menu_selection() -> void:
	in_menu_selection = true

## Executes the queued action on [member current_target] then calls [method end_turn].
## Awaits animation completion for "attack" and "skill" so the next turn does not start
## until the current action visually resolves. Items resolve immediately without awaiting.
func _use_action_on_target() -> void:
	print("=== USING ACTION ON TARGET ===")
	print("Current target: ", current_target.character_name if current_target else "NULL")
	print("Queued item: ", queued_item.item_name if queued_item else "NULL")
	
	if !current_target:
		print("ERROR: No target selected!")
		_cancel_action_target_selection()
		return
	
	# Card combat pending_card takes priority over queued_item
	var pending_card = get_meta("pending_card") if has_meta("pending_card") else null
	if pending_card:
		print("Card pending - routing to card play on: ", current_target.character_name)
		set_meta("pending_card", null)
		in_target_selection = false
		mouse_input_toggle = false
		for battler in valid_targets:
			if battler is Battler:
				battler.is_valid_target = false
				battler.is_selectable = false
				battler.deselect_as_target()
		valid_targets.clear()
		if hud:
			if hud.target_back_button:
				hud.target_back_button.visible = false
			hud.hide_action_buttons()
			if hud.card_ui:
				hud.card_ui.visible = false
		var card_battle_manager = get_tree().get_first_node_in_group("card_battle_manager")
		if card_battle_manager:
			_execute_card_async(card_battle_manager, pending_card, current_target)
		return
	
	if !queued_item:
		print("ERROR: No item queued and no pending card!")
		_cancel_action_target_selection()
		return
	
	exit_targeting_mode()
	in_menu_selection = false
	is_animating = true
	hud.hide_action_buttons()
	
	print("Using item on target: ", current_target.character_name)
	current_character.battle_item(queued_item, current_target)
	
	queued_item = null
	SignalBus.allow_select_target.emit(false)
	end_turn()

func _on_anim_damage():
	# This function will be replaced by the card combat system
	# For now, keeping it for compatibility with existing animations
	print("Animation damage callback - will be handled by card system")
	pass

func damage_calculation(attacker, target, damage) -> void:
	# Safety check - if damage is 0, don't process
	if damage <= 0:
		print("Damage is 0 or negative, skipping calculation")
		return
	
	# CHECK HIT CHANCE from attacker's states (Blind reduces accuracy)
	var hit_chance = 100.0
	for state_name in attacker.active_states:
		var state = attacker.active_states[state_name] as State
		if state and state.hit_chance < 100.0:
			hit_chance = state.hit_chance
			break
	
	# Roll for hit
	var roll = randf_range(0.0, 100.0)
	if roll > hit_chance:
		print("%s's attack misses! (rolled %.1f vs hit chance %.1f)" % [attacker.character_name, roll, hit_chance])
		# Display miss text
		if hud and hud.battle_text_display:
			hud.battle_text_display.show_miss(attacker, target, null)
		return  # Miss - no damage applied
	
	damage = Formulas.physical_damage(attacker, target, damage)
	print("%s attacks %s for %d damage! (hit: %.1f/%.1f)" % [attacker.character_name, target.character_name, damage, hit_chance, 100.0])
	
	# Check for reactive defense (Dodge / Parry / Perfect Parry Counter) if target is player ally
	var card_battle_manager = get_tree().get_first_node_in_group("card_battle_manager")
	if card_battle_manager and target in players:
		damage = await card_battle_manager.trigger_reactive_defense(attacker, damage, target)
		print("Damage after reactive defense: ", damage)
	
	# Only apply if damage is still positive after calculation
	if damage > 0:
		# AWAIT damage so counters complete before continuing
		await target.take_damage(damage, attacker)
		hud.update_health_bars()
		update_hud()
		
		# Display damage text with BattleAflictions
		if hud and hud.battle_text_display:
			hud.battle_text_display.show_damage(attacker, target, null, damage, false, false)
	else:
		print("Final damage after calculation is 0 or negative, not applying")

func heal_calculation(user, target, amount):
	var healing = target.take_healing(amount)
	print("%s heals %s for %d health!" % [user.character_name, target.character_name, healing])
	hud.update_health_bars()
	update_hud()
	
	# Display healing text with BattleAflictions
	if hud and hud.battle_text_display:
		hud.battle_text_display.show_healing(user, target, null, healing)

func enemy_turn(character:Battler) -> void:
	print("=== ENEMY TURN ===")
	print("Enemy character: ", character.character_name)
	
	# SET THESE BEFORE AI CHOOSES ACTION
	current_character = character
	current_battler = character
	
	# Get all players (allies) as targets for enemies
	var available_targets: Array = []
	for node in get_tree().get_nodes_in_group("players"):
		if node is Battler and !node.is_defeated():
			available_targets.append(node)
	
	if available_targets.is_empty():
		print("No available targets!")
		end_turn()
		return
	
	print("Available targets for enemy: ", available_targets.size())
	for target in available_targets:
		if target is Battler:
			print("  - ", target.character_name, " (HP: ", target.current_health, "/", target.max_health, ")")
	
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
		print("[Turn Guard] Turn transition already in progress, skipping duplicate call")
		return
	is_turn_transitioning = true
	
	if skip_turn:
		skip_turn = false
		current_turn = (current_turn + 1) % max(turn_order.size(), 1)
		is_animating = false
		start_next_turn()
	else:
		# Process states before SP regen
		if current_battler:
			current_battler.process_states()
		
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
	print("[FORCE ADVANCE] Forcing turn to end due to timeout")
	battler_attacking = false
	end_turn()

## Start the turn timeout timer to prevent soft locks
func _start_turn_timeout() -> void:
	current_turn_timeout_timer = turn_timeout_seconds
	print("[Turn Timeout] Started timeout (%.1fs) for %s" % [turn_timeout_seconds, current_character.character_name if current_character else "NULL"])
	
	await get_tree().create_timer(turn_timeout_seconds / speed_multiplier).timeout
	
	# Check if turn has exceeded timeout
	if current_character:
		print("[Turn Timeout] WARNING: Turn exceeded %.1fs!" % turn_timeout_seconds)
		force_turn_advance()

func player_turn(character):
	count_allies()
	hud.set_activebattler(character)
	hud.show_action_buttons(character)  # Make sure HUD shows here
	is_animating = false  # Allow player input

func is_battle_over():
	return all_defeated(players) or all_defeated(enemies)

func all_defeated(characters: Array):
	for character in characters:
		if not character.is_defeated():
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
		print("Escape successful! (Rolled %d, needed %d or less)" % [roll, escape_threshold])
		end_battle(BattleEndCondition.ESCAPE) # Use your existing escape scene transition
		return true
	else:
		print("Escape failed! (Rolled %d, needed %d or less)" % [roll, escape_threshold])
		skip_turn = true
		end_turn() # Enemy gets a turn after failed escape
		return false

func end_battle(state: BattleEndCondition = BattleEndCondition.WIN):
	# ESCAPE always ends the battle abruptly. WIN, Will end the battle and return to normal, DEFEAT will end the battle with game over.
	match state:
		BattleEndCondition.ESCAPE:
			print("Nobody Won - Battle Escaped.")
			
			# Show battle results for escape
			show_battle_results()
			
			for player in players:
				player.gain_experience(100)
			
			# Remove defeated enemies with tween (scale instead of modulate)
			for enemy in enemies:
				var tween = create_tween()
				tween.set_parallel(true)
				tween.tween_property(enemy, "position:y", enemy.position.y + 2.0, 1.0)  # Float up
				tween.tween_property(enemy, "scale", Vector3.ZERO, 1.0)  # Shrink to nothing
				tween.tween_callback(func(): enemy.queue_free())
			
			await get_tree().create_timer(1.5).timeout
			get_tree().change_scene_to_file(game_map)
			
		BattleEndCondition.CUTSCENE:
			print("cutscene will play.")
			pass
			
		BattleEndCondition.WIN:
			print("Victory! All enemies have been defeated.")
			
			# Show battle results screen
			show_battle_results()
			
			# Award experience to players
			for player in players:
				player.gain_experience(100)
			
			# Remove defeated enemies with tween (scale instead of modulate)
			for enemy in enemies:
				var tween = create_tween()
				tween.set_parallel(true)
				tween.tween_property(enemy, "position:y", enemy.position.y + 2.0, 1.0)  # Float up
				tween.tween_property(enemy, "scale", Vector3.ZERO, 1.0)  # Shrink to nothing
				tween.tween_callback(func(): enemy.queue_free())
			
			await get_tree().create_timer(1.5).timeout
			get_tree().change_scene_to_file(game_map)
			
		BattleEndCondition.DEFEAT:
			print("Game Over. All players have been defeated.")
			hud.hide_action_buttons()

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
	print("=== EXIT TARGETING MODE ===")
	in_target_selection = false
	current_target = null
	
	# Disable all valid targets
	for battler in valid_targets:
		if battler is Battler:
			battler.is_valid_target = false
			battler.is_selectable = false
			battler.deselect_as_target()
	
	valid_targets.clear()
	
	# Clear pending card if exists (prevents targeting loop on cancel)
	if has_meta("pending_card"):
		print("Clearing pending card on exit targeting mode")
		set_meta("pending_card", null)
	
	# Clear AOE mode metadata
	if has_meta("is_aoe_mode"):
		set_meta("is_aoe_mode", false)
	if has_meta("aoe_targets"):
		set_meta("aoe_targets", null)
	if has_meta("target_type"):
		set_meta("target_type", null)
	
	# Disable mouse input when done targeting
	mouse_input_toggle = false
	
	# Update HUD: hide cancel target button, show cards and action buttons
	if hud and hud.has_method("set_targeting_mode"):
		hud.set_targeting_mode(false)
	
	# Restore OTS camera on current character if player turn
	if battle_camera and current_character in players:
		battle_camera.set_over_the_shoulder(current_character)

func confirm_aoe_execution():
	print("=== CONFIRM AOE EXECUTION ===")
	var pending_card = get_meta("pending_card")
	var aoe_targets = get_meta("aoe_targets")
	var target_type = get_meta("target_type")
	
	if not pending_card or aoe_targets.is_empty():
		print("ERROR: No pending card or AOE targets for execution")
		exit_targeting_mode()
		return
	
	print("Executing AOE card: ", pending_card.name)
	print("AOE targets: ", aoe_targets.size())
	print("Target type: ", target_type)
	
	# Clear AOE mode metadata
	set_meta("is_aoe_mode", false)
	set_meta("aoe_targets", null)
	set_meta("pending_card", null)
	
	# Hide targeting UI
	if hud and hud.has_method("hide_aoe_confirmation_mode"):
		hud.hide_aoe_confirmation_mode()
	hud.hide_action_buttons()
	if hud.card_ui:
		hud.card_ui.visible = false
	
	# Execute AOE card on all targets
	var card_battle_manager = get_tree().get_first_node_in_group("card_battle_manager")
	if card_battle_manager:
		_execute_aoe_card_async(card_battle_manager, pending_card, aoe_targets)
	else:
		print("ERROR: CardBattleManager not found for AOE execution")
		exit_targeting_mode()

func _execute_aoe_card_async(card_battle_manager: CardBattleManager, card: CardData, targets: Array[Battler]):
	print("=== EXECUTING AOE CARD ===")
	print("Card: ", card.name)
	print("Targets: ", targets.size())
	
	# Set animating state
	is_animating = true
	
	# Execute the card effect on each target
	for target in targets:
		if is_instance_valid(target):
			print("Executing on target: ", target.character_name)
			await card_battle_manager.execute_card_effect(card, target)
	
	# Execute card completion logic (spend AP, discard, etc.)
	# We need to manually handle this without calling play_card again
	card_battle_manager.is_executing_card = true
	
	# Spend AP
	if card_battle_manager.ap_system:
		card_battle_manager.ap_system.spend_ap(card.cost)
	
	# Remove from hand
	var deck = card_battle_manager._get_current_deck()
	if deck:
		deck.discard_card(card)
	
	card_battle_manager.is_executing_card = false
	
	# Restore camera
	if battle_camera and is_instance_valid(current_character):
		battle_camera.set_over_the_shoulder(current_character)
	
	# Reset animating state
	is_animating = false
	
	# Show action buttons again
	if hud:
		hud.show_action_buttons(current_character)
		if hud.card_ui:
			hud.card_ui.visible = true
	
	print("Targeting mode exited")

func _execute_card_async(card_battle_manager: CardBattleManager, card: CardData, target: Battler):
	# Helper function to execute card asynchronously
	await card_battle_manager.play_card(card, target)

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
		print("Battle Results shown - waiting for input...")
		
		# Safety check: ensure we're still in tree before awaiting
		while is_node_alive() and not Input.is_action_just_pressed("ui_accept"):
			await get_tree().process_frame
		
		if not is_node_alive():
			print("BattleManager no longer in tree, exiting results...")
			return
		
		print("Input received, continuing...")
		
		# Fade out when done
		if battle_results is CanvasItem:
			var fade_out = create_tween()
			fade_out.tween_property(battle_results, "modulate:a", 0.0, 0.3)
		battle_results.visible = false
	else:
		print("Results node not found in HUD")

## Helper to check if node is still alive
func is_node_alive() -> bool:
	return is_instance_valid(self) and is_inside_tree()

## Populate battle results with player stats and rewards
func populate_battle_results(_results_node: Node) -> void:
	# Update results node with battle information
	print("Populating battle results...")
	
	# You can add more specific population logic here
	# For example:
	# - Show defeated enemies
	# - Show experience gained per player
	# - Show items obtained
	# This depends on your BattleResults scene structure
