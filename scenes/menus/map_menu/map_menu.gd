extends Control
## Run map — Slay the Spire style path selection.
##
## Loaded as a "level" through the LevelLoader (so it gets the loading screen,
## the pause menu, and GameState syncing for free). After winning a battle the
## player returns here to choose the next step. Selecting a node emits
## 'level_changed', which the LevelManager turns into loading that battle.

signal level_changed(next_level_path : String)

## The run map data to display.
@export var run_map : RunMap

const MAP_MARGIN := 110.0
const NODE_BUTTON_SIZE := Vector2(160.0, 48.0)
const LINE_COLOR := Color(0.55, 0.55, 0.6, 0.5)
const LINE_COLOR_TRAVELED := Color(0.95, 0.8, 0.35, 0.9)
const COMPLETED_COLOR := Color(0.4, 0.85, 0.5, 0.9)
const LOCKED_COLOR := Color(1.0, 1.0, 1.0, 0.3)

var _node_buttons : Dictionary = {}
var _connections_layer : Control

func _ready() -> void:
	if run_map == null:
		# No resource assigned in the inspector: use the built-in default map.
		run_map = RunMap.create_default()
	# Lines are drawn on a layer child (the root's own drawing would be hidden
	# beneath the opaque Background child).
	_connections_layer = Control.new()
	_connections_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_connections_layer)
	move_child(_connections_layer, 1) # Above the background, below everything else.
	_connections_layer.draw.connect(_on_connections_draw)
	_rebuild_map()
	resized.connect(_refresh_layout)

func _rebuild_map() -> void:
	for button in _node_buttons.values():
		button.queue_free()
	_node_buttons.clear()
	if run_map == null:
		push_error("MapMenu: no RunMap resource assigned.")
		return
	var completed := GameState.get_completed_nodes()
	var available := run_map.get_available_node_ids(completed)
	for node in run_map.nodes:
		var map_node := node as RunMapNode
		if map_node == null:
			continue
		var button := Button.new()
		button.text = map_node.display_name
		button.custom_minimum_size = NODE_BUTTON_SIZE
		button.pressed.connect(_on_node_pressed.bind(map_node))
		if map_node.id in completed:
			button.text = "%s ✓" % map_node.display_name
			button.disabled = true
			button.modulate = COMPLETED_COLOR
		elif map_node.id in available:
			button.modulate = Color.WHITE
		else:
			button.disabled = true
			button.modulate = LOCKED_COLOR
		add_child(button)
		_node_buttons[map_node.id] = button
	# Grab focus on the first available node for keyboard/gamepad navigation.
	for node in run_map.nodes:
		var map_node := node as RunMapNode
		if map_node and map_node.id in available:
			_node_buttons[map_node.id].grab_focus()
			break
	_refresh_layout()

func _refresh_layout() -> void:
	if run_map == null:
		return
	for node_id in _node_buttons:
		var map_node := run_map.get_node_by_id(node_id)
		if map_node == null:
			continue
		var button : Button = _node_buttons[node_id]
		button.position = _node_pixel_position(map_node) - NODE_BUTTON_SIZE / 2.0
	if _connections_layer:
		_connections_layer.queue_redraw()

func _node_pixel_position(map_node : RunMapNode) -> Vector2:
	var area_size := (size - Vector2(MAP_MARGIN, MAP_MARGIN) * 2.0).max(Vector2.ZERO)
	return Vector2(MAP_MARGIN, MAP_MARGIN) + Vector2(map_node.map_position.x * area_size.x, map_node.map_position.y * area_size.y)

func _on_connections_draw() -> void:
	if run_map == null:
		return
	var completed := GameState.get_completed_nodes()
	for node in run_map.nodes:
		var map_node := node as RunMapNode
		if map_node == null:
			continue
		var traveled : bool = map_node.id in completed
		for next_id in map_node.next_node_ids:
			var next_node := run_map.get_node_by_id(next_id)
			if next_node == null:
				continue
			var color := LINE_COLOR_TRAVELED if traveled else LINE_COLOR
			_connections_layer.draw_line(_node_pixel_position(map_node), _node_pixel_position(next_node), color, 4.0, true)

func _on_node_pressed(map_node : RunMapNode) -> void:
	GameState.set_current_node_id(map_node.id)
	level_changed.emit(map_node.level_path)
