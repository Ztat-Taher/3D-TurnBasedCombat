extends LevelManager
## LevelManager extension that drives the Slay the Spire style run:
## the run map (map_level_path) is the hub between battles; winning a battle
## shows the level-complete screen, then returns to the map to choose the next
## step. Completing the final map node ends the run.

## Scene shown as the run map hub between battles.
@export_file("*.tscn") var map_level_path : String = "res://scenes/menus/map_menu/map_menu.tscn"
## Full-screen interstitial shown after winning a level, before the map.
## Meant to double as the future reward screen.
@export_file("*.tscn") var level_complete_scene_path : String = "res://scenes/windows/level_complete_screen.tscn"
## Run map data used to decide when the run is complete.
## Falls back to the built-in default map if unassigned.
@export var run_map : RunMap

func set_current_level_path(value : String) -> void:
	super.set_current_level_path(value)
	GameState.set_current_level_path(value)

func set_checkpoint_level_path(value : String) -> void:
	super.set_checkpoint_level_path(value)
	GameState.set_checkpoint_level_path(value)

func get_checkpoint_level_path() -> String:
	var state_level_path := GameState.get_checkpoint_level_path()
	if not state_level_path.is_empty():
		if ResourceLoader.exists(state_level_path):
			return state_level_path
		# The saved checkpoint no longer exists (e.g. levels were renamed or removed).
		# Clear it so the run restarts at the run map.
		GameState.set_current_level_path("")
		GameState.set_checkpoint_level_path("")
	return map_level_path

func get_run_map() -> RunMap:
	if run_map == null:
		run_map = RunMap.create_default()
	return run_map

func get_run_map_node(node_id : String) -> RunMapNode:
	if node_id.is_empty():
		return null
	return get_run_map().get_node_by_id(node_id)

func _on_level_won(next_level_path : String = "") -> void:
	# Winning a battle marks its map node as completed and sends the player
	# back to the run map (via the level-complete screen) to choose the next
	# step - unless the completed node was the end of the run.
	var completed_node := get_run_map_node(GameState.get_current_node_id())
	GameState.complete_current_node()
	if completed_node != null and completed_node.next_node_ids.is_empty():
		_load_win_screen_or_ending()
		return
	checkpoint_level_path = map_level_path
	_load_level_won_screen_or_checkpoint()

func _load_level_won_screen_or_checkpoint() -> void:
	if level_complete_scene_path.is_empty():
		_load_checkpoint_level()
		return
	var packed : PackedScene = load(level_complete_scene_path)
	if packed == null:
		push_error("LevelManager: could not load the level complete screen: %s" % level_complete_scene_path)
		_load_checkpoint_level()
		return
	var instance = packed.instantiate()
	# Wrap the screen in its own high canvas layer so it draws ABOVE the battle
	# HUD (which lives on CanvasLayer 1). Otherwise the in-battle results panel
	# stays on top of the level-complete screen and blocks it.
	var canvas_layer := CanvasLayer.new()
	canvas_layer.name = "LevelCompleteLayer"
	canvas_layer.layer = 50
	canvas_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().current_scene.add_child(canvas_layer)
	canvas_layer.add_child(instance)
	_try_connecting_signal_to_node(instance, &"continue_pressed", _load_checkpoint_level)
	_try_connecting_signal_to_node(instance, &"restart_pressed", _reload_level)
	_try_connecting_signal_to_node(instance, &"main_menu_pressed", _load_main_menu)
	instance.hidden.connect(_close_level_complete_screen.bind(instance, canvas_layer), CONNECT_ONE_SHOT)

func _close_level_complete_screen(instance : Node, canvas_layer : CanvasLayer) -> void:
	if is_instance_valid(canvas_layer):
		canvas_layer.queue_free()
	_close_scene(instance)
