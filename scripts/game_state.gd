class_name GameState
extends Resource

const STATE_NAME : String = "GameState"
const FILE_PATH = "res://scripts/game_state.gd"

@export var level_states : Dictionary = {}
@export var current_level_path : String
@export var checkpoint_level_path : String
@export var total_games_played : int
@export var play_time : int
@export var total_time : int

# Run-map progress (Slay the Spire style path selection).
@export var current_node_id : String = ""
@export var completed_nodes : Array[String] = []

static func get_level_state(level_state_key : String) -> LevelState:
	if not has_game_state(): 
		return
	var game_state := get_or_create_state()
	if level_state_key.is_empty() : return
	if level_state_key in game_state.level_states:
		return game_state.level_states[level_state_key] 
	else:
		var new_level_state := LevelState.new()
		game_state.level_states[level_state_key] = new_level_state
		GlobalState.save()
		return new_level_state

static func has_game_state() -> bool:
	return GlobalState.has_state(STATE_NAME)

static func get_or_create_state() -> GameState:
	return GlobalState.get_or_create_state(STATE_NAME, FILE_PATH)

static func get_current_level_path() -> String:
	if not has_game_state(): 
		return ""
	var game_state := get_or_create_state()
	return game_state.current_level_path

static func get_checkpoint_level_path() -> String:
	if not has_game_state(): 
		return ""
	var game_state := get_or_create_state()
	return game_state.checkpoint_level_path

static func get_levels_reached() -> int:
	if not has_game_state(): 
		return 0
	var game_state := get_or_create_state()
	return game_state.level_states.size()

static func set_checkpoint_level_path(level_path : String) -> void:
	var game_state := get_or_create_state()
	game_state.checkpoint_level_path = level_path
	get_level_state(level_path)
	GlobalState.save()

static func set_current_level_path(level_path : String) -> void:
	var game_state := get_or_create_state()
	game_state.current_level_path = level_path
	GlobalState.save()

static func get_current_node_id() -> String:
	if not has_game_state(): 
		return ""
	var game_state := get_or_create_state()
	return game_state.current_node_id

static func set_current_node_id(node_id : String) -> void:
	var game_state := get_or_create_state()
	game_state.current_node_id = node_id
	GlobalState.save()

static func get_completed_nodes() -> Array:
	if not has_game_state(): 
		return []
	var game_state := get_or_create_state()
	return game_state.completed_nodes.duplicate()

static func is_node_completed(node_id : String) -> bool:
	if not has_game_state(): 
		return false
	var game_state := get_or_create_state()
	return node_id in game_state.completed_nodes

static func complete_current_node() -> void:
	var game_state := get_or_create_state()
	if game_state.current_node_id.is_empty():
		return
	if not game_state.current_node_id in game_state.completed_nodes:
		game_state.completed_nodes.append(game_state.current_node_id)
	game_state.current_node_id = ""
	GlobalState.save()

static func start_game() -> void:
	var game_state := get_or_create_state()
	game_state.total_games_played += 1
	GlobalState.save()

static func continue_game() -> void:
	var game_state := get_or_create_state()
	game_state.current_level_path = game_state.checkpoint_level_path
	GlobalState.save()

static func reset() -> void:
	var game_state := get_or_create_state()
	game_state.level_states = {}
	game_state.current_level_path = ""
	game_state.checkpoint_level_path = ""
	game_state.play_time = 0
	game_state.total_time = 0
	game_state.current_node_id = ""
	game_state.completed_nodes = []
	GlobalState.save()
