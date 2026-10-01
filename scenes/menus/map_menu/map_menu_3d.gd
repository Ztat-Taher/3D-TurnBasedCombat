extends Node3D
## 3D Map Menu - Projects 2D UI onto 3D plane with 3D pawn
##
## The 2D map UI (nodes, paths) is rendered to a SubViewport
## and projected onto a 3D plane mesh. The pawn is a 3D object
## in the same scene space.

signal level_changed(next_level_path : String)

@export var run_map : RunMap
@export var clear_game_state_on_load : bool = false  # Debug option to reset progress

## Scene references
var _camera : Camera3D
var _map_plane : MeshInstance3D
var _map_viewport : SubViewport
var _map_ui : Control
var _pawn : MeshInstance3D
var _world_viewport : SubViewport

## 2D UI references (inside viewport)
var _path_drawer : MapPathDrawer
var _node_icon_layer : Control
var _node_icons : Dictionary = {}

## 3D positioning
@export var map_3d_width := 3.62
@export var map_3d_height := 2.0
@export var map_margin_3d := 0.0

## Camera follow
@export var camera_follow_speed := 2.0
@export var camera_follow_enabled := true
@export var camera_z_offset := 0.5  # Camera stays this far behind pawn on Z axis

## Current state
var _current_node_id : String = ""
var _stop_node_scene : PackedScene = load("res://scenes/menus/map_menu/stop_node.tscn")
var _pawn_scene : PackedScene = load("res://scenes/menus/map_menu/pawns/pawn_player.tscn")
var _initial_load : bool = true

## Decorative follower pawns - one per extra party member (visual only).
var _party_pawns : Array[MeshInstance3D] = []

## Formation offsets (XZ, world units) for follower pawns relative to the leader.
const PARTY_OFFSETS : Array[Vector2] = [
	Vector2(0.14, -0.14),
	Vector2(-0.14, -0.14),
	Vector2(0.0, -0.30),
]

func _ready() -> void:
	if run_map == null:
		run_map = RunMap.create_default()
	
	# Clear game state if debug flag is set
	if clear_game_state_on_load:
		GameState.reset()
		print("Game state cleared for debug")
	
	# Get references (3D world is wrapped in ViewportContainer for PSX post-processing)
	var world_path := "ViewportContainer/WorldViewport"
	_camera = get_node(world_path + "/Camera3D")
	_map_plane = get_node(world_path + "/MapPlane")
	_map_viewport = get_node(world_path + "/MapUIViewport")
	_map_ui = get_node(world_path + "/MapUIViewport/MapUI")
	_pawn = get_node(world_path + "/PlayerPawn")
	_world_viewport = get_node(world_path)
	
	# Print coordinate reference points
	_print_coordinate_reference()
	
	# Setup 2D UI layers inside viewport
	_setup_2d_ui_layers()
	
	# Setup pawn (it's already in the scene, just connect signals)
	_setup_3d_pawn()
	
	# Setup plane mesh with viewport texture
	_setup_map_plane()
	
	# Initialize current node
	_current_node_id = GameState.get_current_node_id()
	if _current_node_id.is_empty() and run_map and not run_map.starting_node_ids.is_empty():
		_current_node_id = run_map.starting_node_ids[0]
	
	_rebuild_map()

func _print_coordinate_reference() -> void:
	print("=== MAP COORDINATE REFERENCE ===")
	print("Map 3D dimensions: ", map_3d_width, " x ", map_3d_height)
	print("Map 3D margin: ", map_margin_3d)
	print()
	
	# Calculate the actual bounds
	var min_x = -(map_3d_width - map_margin_3d * 2.0) / 2.0
	var max_x = (map_3d_width - map_margin_3d * 2.0) / 2.0
	var min_z = -(map_3d_height - map_margin_3d * 2.0) / 2.0
	var max_z = (map_3d_height - map_margin_3d * 2.0) / 2.0
	
	print("World coordinate bounds:")
	print("  Top-Left:    (", min_x, ", 0, ", min_z, ") -> Normalized: (0.0, 0.0)")
	print("  Top-Right:   (", max_x, ", 0, ", min_z, ") -> Normalized: (1.0, 0.0)")
	print("  Bottom-Left: (", min_x, ", 0, ", max_z, ") -> Normalized: (0.0, 1.0)")
	print("  Bottom-Right:(", max_x, ", 0, ", max_z, ") -> Normalized: (1.0, 1.0)")
	print("  Center:      (0, 0, 0) -> Normalized: (0.5, 0.5)")
	print()
	print("Move pawn to these 5 points and report back the actual world positions!")
	print("=====================================")

func _setup_2d_ui_layers() -> void:
	# Create PathLayer for dashed lines
	var path_layer = Control.new()
	path_layer.name = "PathLayer"
	path_layer.anchors_preset = Control.PRESET_FULL_RECT
	path_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	path_layer.set_script(load("res://scenes/menus/map_menu/map_path_drawer.gd"))
	_map_ui.add_child(path_layer)
	_path_drawer = path_layer
	
	# Create NodeIconLayer for stop nodes
	var node_layer = Control.new()
	node_layer.name = "NodeIconLayer"
	node_layer.anchors_preset = Control.PRESET_FULL_RECT
	node_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_ui.add_child(node_layer)
	_node_icon_layer = node_layer
	
	# Connect path drawer
	if _path_drawer:
		_path_drawer.set_run_map(run_map)

func _setup_3d_pawn() -> void:
	# Pawn is already in the scene, just connect signals
	if _pawn:
		_pawn.movement_finished.connect(_on_pawn_movement_finished)
		_pawn.visible = true

func _setup_map_plane() -> void:
	# Apply viewport texture to plane - get texture directly from viewport
	await get_tree().process_frame  # Wait for viewport to be ready
	var viewport_texture = _map_viewport.get_texture()
	
	var material = StandardMaterial3D.new()
	material.albedo_texture = viewport_texture
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST  # crisp, pixelated map
	
	_map_plane.material_override = material

func _rebuild_map() -> void:
	# Clear existing icons
	for icon in _node_icons.values():
		icon.queue_free()
	_node_icons.clear()
	
	if run_map == null:
		push_error("MapMenu3D: no RunMap resource assigned.")
		return
	
	var completed := GameState.get_completed_nodes()
	
	# Filter completed nodes to only include nodes that exist in current map
	var valid_completed : Array[String] = []
	for node_id in completed:
		if run_map.get_node_by_id(node_id):
			valid_completed.append(node_id)
	completed = valid_completed
	
	# Get available nodes
	var available : Array[String] = []
	
	# If no current node set (first load), use start node's next nodes
	if _current_node_id.is_empty() and not run_map.starting_node_ids.is_empty():
		var start_node = run_map.get_node_by_id(run_map.starting_node_ids[0])
		if start_node:
			available = start_node.next_node_ids.duplicate()
			_current_node_id = run_map.starting_node_ids[0]  # Set as current for availability calculation
	elif not _current_node_id.is_empty():
		var current_node := run_map.get_node_by_id(_current_node_id)
		if current_node:
			available = current_node.next_node_ids.duplicate()
	
	print("Current node: ", _current_node_id)
	print("Available nodes: ", available)
	
	# Create node icons (render all nodes except starting node)
	for node in run_map.nodes:
		var map_node := node as RunMapNode
		if map_node == null:
			continue
		
		# Skip starting node - it's just where the pawn starts, not a clickable node
		if map_node.id in run_map.starting_node_ids:
			continue
		
		var stop_node := _stop_node_scene.instantiate() as StopNode
		stop_node.setup(map_node)
		stop_node.name = "StopNode_" + map_node.id
		stop_node.node_selected.connect(_on_node_selected)
		stop_node.node_hovered.connect(_on_node_hovered)
		stop_node.node_exited.connect(_on_node_exited)
		
		var is_completed := map_node.id in completed
		var is_available := map_node.id in available
		
		stop_node.update_state(is_available, is_completed)
		
		_node_icon_layer.add_child(stop_node)
		_node_icons[map_node.id] = stop_node
	
	# Update path drawer
	if _path_drawer:
		_path_drawer.set_completed_nodes(completed)
		print("Completed nodes: ", completed)
	
	# Position nodes in 2D UI
	_refresh_2d_layout()
	
	# Position 3D pawn at current node (only on initial load, not after hops)
	if _initial_load and _current_node_id and _pawn:
		_position_pawn_3d(_current_node_id)
		_initial_load = false
	
	# Keep the follower pawn group in sync with the party size (visual only).
	_refresh_party_pawns()

func _refresh_2d_layout() -> void:
	var viewport_size = Vector2(_map_viewport.size)
	var margin = 64.0
	var area_size = (viewport_size - Vector2(margin, margin) * 2.0).max(Vector2.ZERO)
	
	for node_id in _node_icons:
		var map_node := run_map.get_node_by_id(node_id)
		if map_node == null:
			continue
		var stop_node : StopNode = _node_icons[node_id]
		var pixel_pos = Vector2(margin, margin) + Vector2(
			map_node.map_position.x * area_size.x,
			map_node.map_position.y * area_size.y
		)
		stop_node.position = pixel_pos - Vector2(32, 32)
		stop_node.size = Vector2(64, 64)
	
	if _path_drawer:
		_path_drawer.queue_redraw()

func _get_node_world_pos(map_node: RunMapNode) -> Vector3:
	var viewport_size = Vector2(_map_viewport.size)
	var margin = 64.0
	var area_size = (viewport_size - Vector2(margin, margin) * 2.0).max(Vector2.ZERO)
	
	# Pixel position of the node center inside the SubViewport
	var pixel_pos = Vector2(margin, margin) + Vector2(
		map_node.map_position.x * area_size.x,
		map_node.map_position.y * area_size.y
	)
	
	# Normalized UV on the plane mesh (0.0 to 1.0)
	var uv_x = pixel_pos.x / viewport_size.x
	var uv_y = pixel_pos.y / viewport_size.y
	
	# Map UV to 3D world coordinates on the MapPlane
	var plane_position = _map_plane.position
	var world_x = (uv_x - 0.5) * map_3d_width + plane_position.x
	var world_z = (uv_y - 0.5) * map_3d_height + plane_position.z
	
	return Vector3(world_x, 0.1, world_z)

func _position_pawn_3d(node_id : String) -> void:
	var map_node := run_map.get_node_by_id(node_id)
	if map_node == null or not _pawn:
		return
	
	var final_pos = _get_node_world_pos(map_node)
	print("Positioning pawn at: ", final_pos)
	_pawn.position = final_pos

## Rebuild the follower pawn group so its size matches the party roster.
## Only recreates pawns when the party size actually changed (visual only).
func _refresh_party_pawns() -> void:
	if _pawn == null or _pawn_scene == null:
		return
	
	var count := maxi(1, GameState.get_party().size())
	var expected_followers := count - 1
	
	if _party_pawns.size() != expected_followers:
		for existing in _party_pawns:
			if is_instance_valid(existing):
				existing.queue_free()
		_party_pawns.clear()
		
		for i in range(expected_followers):
			var follower := _pawn_scene.instantiate() as MeshInstance3D
			if follower == null:
				continue
			follower.name = "PartyPawn_%d" % (i + 1)
			_pawn.get_parent().add_child(follower)
			follower.transform = _pawn.transform
			_party_pawns.append(follower)
	
	_update_party_pawn_positions()

## Lock follower pawns to the leader's position so they hop along with it.
func _update_party_pawn_positions() -> void:
	if _pawn == null:
		return
	for i in _party_pawns.size():
		var follower := _party_pawns[i]
		if not is_instance_valid(follower):
			continue
		var offset := PARTY_OFFSETS[mini(i, PARTY_OFFSETS.size() - 1)]
		if i >= PARTY_OFFSETS.size():
			# Extra members beyond the standard formation share an offset with jitter.
			offset += Vector2(0.06 * float(i - PARTY_OFFSETS.size() + 1), 0.0)
		follower.position = _pawn.position + Vector3(offset.x, 0.0, offset.y)

func _on_node_selected(node_id : String, node_level_path : String) -> void:
	var map_node := run_map.get_node_by_id(node_id)
	if map_node == null:
		return
	
	var completed := GameState.get_completed_nodes()
	var current_node := run_map.get_node_by_id(_current_node_id)
	var available : Array[String] = []
	if current_node:
		available = current_node.next_node_ids.duplicate()
	
	if node_id not in available:
		return
	
	# Animate 3D pawn
	if _pawn:
		var target_node = run_map.get_node_by_id(node_id)
		var target_pos = _get_node_world_pos(target_node)
		
		_pawn.hop_to_position(target_pos, _current_node_id, node_id)
		await _pawn.movement_finished
	
	# Update game state
	GameState.set_current_node_id(node_id)
	GameState.complete_current_node()
	_current_node_id = node_id
	
	_rebuild_map()

	if not node_level_path.is_empty():
		level_changed.emit(node_level_path)

func _on_node_hovered(node_id : String) -> void:
	pass

func _on_node_exited(node_id : String) -> void:
	pass

func _on_pawn_movement_finished() -> void:
	pass

func _process(delta: float) -> void:
	# Keep follower pawns locked to the leader (they mirror its arc while hopping).
	_update_party_pawn_positions()
	
	if not camera_follow_enabled or not _pawn or not _camera:
		return
	
	# Get current camera position
	var current_cam_pos = _camera.position
	
	# Target Z is pawn's position plus offset (camera stays behind pawn)
	var target_z = _pawn.position.z + camera_z_offset
	
	# Smoothly interpolate camera Z to follow pawn (creates lag effect)
	var new_z = lerp(current_cam_pos.z, target_z, camera_follow_speed * delta)
	
	# Keep X and Y fixed, only move Z
	_camera.position = Vector3(current_cam_pos.x, current_cam_pos.y, new_z)

func _input(event: InputEvent) -> void:
	# Forward keyboard/gamepad events directly to viewport
	if event is InputEventKey or event is InputEventJoypadButton:
		_map_viewport.push_input(event)
	# Forward mouse events through raycast conversion
	elif event is InputEventMouseMotion or event is InputEventMouseButton:
		_forward_mouse_to_viewport(event)

func _forward_mouse_to_viewport(event: InputEvent) -> void:
	# Raycast from camera to plane (convert to low-res WorldViewport space first)
	var world_pos := _window_to_world_coords(event.position)
	var ray_origin = _camera.project_ray_origin(world_pos)
	var ray_direction = _camera.project_ray_normal(world_pos)
	var plane = Plane(Vector3.UP, _map_plane.position.y)
	var intersection = plane.intersects_ray(ray_origin, ray_direction)
	
	if intersection:
		# Convert world position to viewport-local coordinates
		var local_pos = intersection - _map_plane.position
		var viewport_size = Vector2(_map_viewport.size)
		
		# Map plane dimensions to viewport size
		var uv_x = (local_pos.x / map_3d_width) + 0.5
		var uv_y = (local_pos.z / map_3d_height) + 0.5
		
		var viewport_pos = Vector2(uv_x * viewport_size.x, uv_y * viewport_size.y)
		
		# For mouse button clicks, find the button at this position and trigger it
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_trigger_button_at_position(viewport_pos)
		else:
			# For other events (hover, etc), forward to viewport
			var viewport_event = event.duplicate()
			viewport_event.position = viewport_pos
			_map_viewport.push_input(viewport_event)

## Converts window coordinates to the low-res WorldViewport space.
## The SubViewportContainer renders at 1/stretch_shrink resolution, so
## camera raycasts need mouse positions scaled into that viewport first.
func _window_to_world_coords(window_pos: Vector2) -> Vector2:
	if _world_viewport == null:
		return window_pos
	var win_size := Vector2(get_viewport().get_visible_rect().size)
	var world_size := Vector2(_world_viewport.get_visible_rect().size)
	if win_size.x <= 0.0 or win_size.y <= 0.0:
		return window_pos
	return window_pos * (world_size / win_size)

func _trigger_button_at_position(viewport_pos: Vector2) -> void:
	print("Trying to trigger button at viewport position: ", viewport_pos)
	
	# Check all stop nodes to see if the click is within their bounds
	for node_id in _node_icons:
		var stop_node : StopNode = _node_icons[node_id]
		var node_rect = Rect2(stop_node.position, stop_node.size)
		
		if node_rect.has_point(viewport_pos):
			print("Found button at position: ", node_id)
			if stop_node.is_available and not stop_node.is_locked:
				stop_node._on_button_pressed()
			else:
				print("Button not clickable - available: ", stop_node.is_available, " locked: ", stop_node.is_locked)
			return
