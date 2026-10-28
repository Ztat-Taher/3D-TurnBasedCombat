@tool
class_name DioramaRig3D
extends Node3D
## Procedural 360-degree Layered Diorama Arena Rig.
## Constructs an array of concentric 360-degree dome panorama layers,
## an arena floor with collision, and midground 2.5D radial billboards.
## Works alongside the scene's WorldEnvironment skybox without overriding it.
## Full live real-time editor preview — updates instantly whenever the resource is edited.

const DIORAMA_RING_SHADER = preload("res://assets/shaders/diorama_ring_layer.gdshader")
const DIORAMA_LIT_SHADER  = preload("res://assets/shaders/diorama_lit_spatial.gdshader")

@export var arena_resource: DioramaArena25D:
	set(value):
		if arena_resource and arena_resource.is_connected("changed", _on_resource_changed):
			arena_resource.disconnect("changed", _on_resource_changed)
		arena_resource = value
		if arena_resource:
			if not arena_resource.is_connected("changed", _on_resource_changed):
				arena_resource.connect("changed", _on_resource_changed)
			# Also connect to each ring's changed signal right away
			_connect_ring_signals()
		if is_inside_tree():
			rebuild_diorama()

@export var rebuild_trigger: bool = false:
	set(value):
		if value:
			rebuild_trigger = false
			rebuild_diorama()

var _rings_container: Node3D
var _floor_node: Node3D
var _elements_container: Node3D

func _ready() -> void:
	if arena_resource:
		if not arena_resource.is_connected("changed", _on_resource_changed):
			arena_resource.connect("changed", _on_resource_changed)
		_connect_ring_signals()
	rebuild_diorama()

func _connect_ring_signals() -> void:
	if not arena_resource:
		return
	for ring in arena_resource.panorama_rings:
		if ring and not ring.is_connected("changed", _on_resource_changed):
			ring.connect("changed", _on_resource_changed)

func _on_resource_changed() -> void:
	if is_inside_tree():
		rebuild_diorama()

## Rebuilds all concentric dome rings, the floor, and midground elements.
func rebuild_diorama() -> void:
	for child in get_children():
		child.queue_free()

	if not arena_resource:
		return

	_build_panorama_rings()
	_build_floor()
	_build_midground_elements()

## -----------------------------------------------------------------------
## Builds concentric 360° dome panoramic layers
## -----------------------------------------------------------------------
func _build_panorama_rings() -> void:
	if arena_resource.panorama_rings.is_empty():
		return

	_rings_container = Node3D.new()
	_rings_container.name = "PanoramaRings"
	add_child(_rings_container)
	_rings_container.owner = self if Engine.is_editor_hint() else null

	for ring: DioramaRingLayer25D in arena_resource.panorama_rings:
		if not ring or not ring.texture:
			continue

		# Connect changed signal for live updating individual ring parameters
		if not ring.is_connected("changed", _on_resource_changed):
			ring.connect("changed", _on_resource_changed)

		var ring_mesh_inst := MeshInstance3D.new()
		ring_mesh_inst.name = ring.name

		# Build the dome mesh with parametric shape and piecewise equator-anchored UVs
		ring_mesh_inst.mesh = DioramaRingMesh.create_dome_mesh(
			ring.radius,
			ring.height,
			ring.top_flatten,
			ring.bottom_flatten,
			ring.uv_top,
			ring.uv_equator,
			ring.uv_bottom,
			ring.lat_segments,
			ring.lon_segments
		)
		ring_mesh_inst.position.y = ring.vertical_offset

		var mat := ShaderMaterial.new()
		mat.shader = DIORAMA_RING_SHADER
		mat.render_priority = ring.render_priority

		# Texture & tiling
		mat.set_shader_parameter("albedo_texture",     ring.texture)
		mat.set_shader_parameter("horizontal_repeats", ring.horizontal_repeats)
		mat.set_shader_parameter("rotation_offset_uv", ring.rotation_offset_uv)

		# Surface detail maps
		mat.set_shader_parameter("use_normal_map", ring.normal_texture != null)
		if ring.normal_texture:
			mat.set_shader_parameter("normal_texture", ring.normal_texture)
			mat.set_shader_parameter("normal_scale", ring.normal_scale)

		mat.set_shader_parameter("use_specular_map", ring.specular_texture != null)
		if ring.specular_texture:
			mat.set_shader_parameter("specular_texture", ring.specular_texture)
			mat.set_shader_parameter("specular_strength", ring.specular_strength)

		mat.set_shader_parameter("use_ambient_map", ring.ambient_texture != null)
		if ring.ambient_texture:
			mat.set_shader_parameter("ambient_texture", ring.ambient_texture)
			mat.set_shader_parameter("ambient_strength", ring.ambient_strength)

		mat.set_shader_parameter("use_displacement_map", ring.displacement_texture != null)
		if ring.displacement_texture:
			mat.set_shader_parameter("displacement_texture", ring.displacement_texture)
			mat.set_shader_parameter("displacement_scale", ring.displacement_scale)
			mat.set_shader_parameter("displacement_min_layers", float(ring.displacement_min_layers))
			mat.set_shader_parameter("displacement_max_layers", float(ring.displacement_max_layers))

		# Camera-reactive parallax (seam-safe angular space)
		mat.set_shader_parameter("camera_yaw_parallax",   ring.camera_yaw_parallax)
		mat.set_shader_parameter("camera_pitch_parallax", ring.camera_pitch_parallax)
		mat.set_shader_parameter("camera_zoom_scale",     ring.zoom_scale)
		mat.set_shader_parameter("fov_warp",              ring.fov_warp)

		# Vibrance
		mat.set_shader_parameter("emission_energy",  ring.emission_energy)
		mat.set_shader_parameter("color_saturation", ring.color_saturation)
		mat.set_shader_parameter("modulate_color",   ring.modulate)

		# Edge blending
		mat.set_shader_parameter("top_fade_margin",    ring.top_fade_margin)
		mat.set_shader_parameter("bottom_fade_margin", ring.bottom_fade_margin)

		# Chromatic aberration
		mat.set_shader_parameter("chromatic_aberration", ring.chromatic_blur)

		ring_mesh_inst.material_override = mat
		_rings_container.add_child(ring_mesh_inst)
		ring_mesh_inst.owner = self if Engine.is_editor_hint() else null

## -----------------------------------------------------------------------
## Floor geometry & collision
## -----------------------------------------------------------------------
func _build_floor() -> void:
	_floor_node = Node3D.new()
	_floor_node.name = "FloorContainer"
	add_child(_floor_node)
	_floor_node.owner = self if Engine.is_editor_hint() else null

	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = "ArenaFloor"

	if arena_resource.floor_mesh:
		mesh_inst.mesh = arena_resource.floor_mesh
	else:
		var default_floor := CylinderMesh.new()
		default_floor.top_radius    = arena_resource.floor_radius
		default_floor.bottom_radius = arena_resource.floor_radius
		default_floor.height        = 0.5
		default_floor.radial_segments = 36
		mesh_inst.mesh = default_floor
		mesh_inst.position.y = -0.25

	var floor_mat := StandardMaterial3D.new()
	if arena_resource.floor_albedo:
		floor_mat.albedo_texture = arena_resource.floor_albedo
		floor_mat.uv1_scale = Vector3(arena_resource.floor_uv_scale.x, arena_resource.floor_uv_scale.y, 1.0)
	else:
		floor_mat.albedo_color = Color(0.25, 0.28, 0.32)

	if arena_resource.floor_normal:
		floor_mat.normal_enabled = true
		floor_mat.normal_texture = arena_resource.floor_normal

	floor_mat.roughness = arena_resource.floor_roughness
	mesh_inst.material_override = floor_mat

	_floor_node.add_child(mesh_inst)
	mesh_inst.owner = self if Engine.is_editor_hint() else null

	var static_body := StaticBody3D.new()
	static_body.name = "FloorCollision"
	var col_shape := CollisionShape3D.new()
	var cyl_shape := CylinderShape3D.new()
	cyl_shape.radius = arena_resource.floor_radius
	cyl_shape.height = 0.5
	col_shape.shape    = cyl_shape
	col_shape.position.y = -0.25
	static_body.add_child(col_shape)
	_floor_node.add_child(static_body)
	static_body.owner = self if Engine.is_editor_hint() else null

## -----------------------------------------------------------------------
## Midground 2.5D element billboards
## -----------------------------------------------------------------------
func _build_midground_elements() -> void:
	_elements_container = Node3D.new()
	_elements_container.name = "MidgroundElements"
	add_child(_elements_container)
	_elements_container.owner = self if Engine.is_editor_hint() else null

	if arena_resource.elements.is_empty():
		return

	for elem: DioramaElement25D in arena_resource.elements:
		if not elem or not elem.albedo_texture:
			continue

		var elem_mesh_inst := MeshInstance3D.new()
		elem_mesh_inst.name = elem.name

		var quad := QuadMesh.new()
		quad.size = elem.size
		elem_mesh_inst.mesh = quad

		var rad := deg_to_rad(elem.angle_degrees)
		var x := sin(rad) * elem.distance_from_center
		var z := cos(rad) * elem.distance_from_center
		elem_mesh_inst.position = Vector3(x, elem.height_offset + elem.size.y * 0.5, z)

		if elem.face_center:
			elem_mesh_inst.look_at(Vector3(0.0, elem_mesh_inst.position.y, 0.0), Vector3.UP)
			elem_mesh_inst.rotate_y(PI)

		var mat := ShaderMaterial.new()
		mat.shader = DIORAMA_LIT_SHADER
		mat.set_shader_parameter("albedo_texture",        elem.albedo_texture)
		mat.set_shader_parameter("is_cutout",             true)
		mat.set_shader_parameter("alpha_scissor_threshold", elem.alpha_scissor_threshold)
		mat.set_shader_parameter("light_influence",       elem.light_influence)
		mat.set_shader_parameter("ambient_tint",          arena_resource.ambient_color)

		if elem.normal_texture:
			mat.set_shader_parameter("normal_texture",  elem.normal_texture)
			mat.set_shader_parameter("use_normal_map",  true)
			mat.set_shader_parameter("normal_scale",    elem.normal_scale)
		else:
			mat.set_shader_parameter("use_normal_map", false)

		elem_mesh_inst.material_override = mat
		_elements_container.add_child(elem_mesh_inst)
		elem_mesh_inst.owner = self if Engine.is_editor_hint() else null
