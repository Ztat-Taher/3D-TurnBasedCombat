@tool
extends Node3D
class_name ExtrudedPixelMesh
## Turns a 2D pixel-art texture into a thick 3D "item" mesh, Minecraft style:
## every opaque pixel becomes a little block, front/back faces show the pixel's color,
## and side walls are only added where a pixel borders transparency.
##
## Colors are baked into vertex colors (no UVs), so the side walls show the exact
## edge pixel's color with no texture bleeding.
## The mesh is centered on the opaque part of the image, so it spins in place.

enum Shading {
	## Unshaded, with fixed per-face brightness baked in (always readable, PSX friendly)
	BAKED,
	## Uses scene lighting
	LIT,
}

@export var texture: Texture2D = null:
	set(value):
		texture = value
		_queue_rebuild()

## World-space size of the longest side of the icon's opaque area
@export var target_size: float = 0.4:
	set(value):
		target_size = maxf(value, 0.001)
		_queue_rebuild()

## Thickness measured in pixels (Minecraft items are 1 pixel thick)
@export_range(0.25, 8.0, 0.25) var thickness_pixels: float = 1.0:
	set(value):
		thickness_pixels = value
		_queue_rebuild()

## Pixels with alpha below this are treated as empty
@export_range(0.0, 1.0, 0.01) var alpha_threshold: float = 0.5:
	set(value):
		alpha_threshold = value
		_queue_rebuild()

@export var shading: Shading = Shading.BAKED:
	set(value):
		shading = value
		_queue_rebuild()

@export_group("Baked Face Brightness")
@export_range(0.0, 1.0, 0.01) var front_brightness: float = 1.0:
	set(value):
		front_brightness = value
		_queue_rebuild()
@export_range(0.0, 1.0, 0.01) var back_brightness: float = 0.8:
	set(value):
		back_brightness = value
		_queue_rebuild()
@export_range(0.0, 1.0, 0.01) var top_brightness: float = 0.9:
	set(value):
		top_brightness = value
		_queue_rebuild()
@export_range(0.0, 1.0, 0.01) var side_brightness: float = 0.7:
	set(value):
		side_brightness = value
		_queue_rebuild()
@export_range(0.0, 1.0, 0.01) var bottom_brightness: float = 0.55:
	set(value):
		bottom_brightness = value
		_queue_rebuild()

var mesh_instance: MeshInstance3D
var pixel_size: float = 0.0  ## Computed world size of one pixel

var _rebuild_queued := false

# Mesh buffers, filled during a rebuild
var _verts := PackedVector3Array()
var _normals := PackedVector3Array()
var _colors := PackedColorArray()
var _indices := PackedInt32Array()


func _ready() -> void:
	_ensure_mesh_instance()
	_rebuild()


func set_texture(new_texture: Texture2D) -> void:
	texture = new_texture
	# Rebuild right away so callers can rely on the mesh existing after this call
	_rebuild()


func _ensure_mesh_instance() -> void:
	if mesh_instance and is_instance_valid(mesh_instance):
		return
	mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	add_child(mesh_instance)


func _queue_rebuild() -> void:
	if not is_inside_tree() or _rebuild_queued:
		return
	_rebuild_queued = true
	_rebuild.call_deferred()


func _rebuild() -> void:
	_rebuild_queued = false
	_ensure_mesh_instance()

	if not texture:
		mesh_instance.mesh = null
		return

	var image := texture.get_image()
	if not image:
		push_warning("ExtrudedPixelMesh: could not read image from texture")
		mesh_instance.mesh = null
		return
	if image.is_compressed():
		image.decompress()
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)

	var w := image.get_width()
	var h := image.get_height()

	# Opaque mask + bounds of the opaque area (for centering and sizing)
	var mask := PackedByteArray()
	mask.resize(w * h)
	var min_x := w
	var min_y := h
	var max_x := -1
	var max_y := -1
	for y in h:
		for x in w:
			if image.get_pixel(x, y).a >= alpha_threshold:
				mask[y * w + x] = 1
				min_x = mini(min_x, x)
				min_y = mini(min_y, y)
				max_x = maxi(max_x, x)
				max_y = maxi(max_y, y)

	if max_x < 0:
		mesh_instance.mesh = null
		return

	var used_w := max_x - min_x + 1
	var used_h := max_y - min_y + 1
	pixel_size = target_size / float(maxi(used_w, used_h))
	var half_depth := pixel_size * thickness_pixels * 0.5
	# Center of the opaque area in pixel coordinates
	var cx := (min_x + max_x + 1) * 0.5
	var cy := (min_y + max_y + 1) * 0.5

	_verts.clear()
	_normals.clear()
	_colors.clear()
	_indices.clear()

	var baked := shading == Shading.BAKED

	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			if mask[y * w + x] == 0:
				continue

			var c := image.get_pixel(x, y)
			c.a = 1.0

			# Pixel bounds in local space (image Y goes down, world Y goes up)
			var x0 := (x - cx) * pixel_size
			var x1 := x0 + pixel_size
			var y1 := (cy - y) * pixel_size
			var y0 := y1 - pixel_size
			var zf := half_depth
			var zb := -half_depth

			# Front (+Z) and back (-Z)
			_add_quad(Vector3(x0, y0, zf), Vector3(x1, y0, zf), Vector3(x1, y1, zf), Vector3(x0, y1, zf),
				Vector3.BACK, _shade(c, front_brightness, baked))
			_add_quad(Vector3(x0, y0, zb), Vector3(x0, y1, zb), Vector3(x1, y1, zb), Vector3(x1, y0, zb),
				Vector3.FORWARD, _shade(c, back_brightness, baked))

			# Side walls only on edges that border transparency
			if not _is_solid(mask, w, h, x - 1, y):
				_add_quad(Vector3(x0, y0, zb), Vector3(x0, y0, zf), Vector3(x0, y1, zf), Vector3(x0, y1, zb),
					Vector3.LEFT, _shade(c, side_brightness, baked))
			if not _is_solid(mask, w, h, x + 1, y):
				_add_quad(Vector3(x1, y0, zb), Vector3(x1, y1, zb), Vector3(x1, y1, zf), Vector3(x1, y0, zf),
					Vector3.RIGHT, _shade(c, side_brightness, baked))
			if not _is_solid(mask, w, h, x, y - 1):  # pixel above in the image = +Y
				_add_quad(Vector3(x0, y1, zb), Vector3(x0, y1, zf), Vector3(x1, y1, zf), Vector3(x1, y1, zb),
					Vector3.UP, _shade(c, top_brightness, baked))
			if not _is_solid(mask, w, h, x, y + 1):  # pixel below in the image = -Y
				_add_quad(Vector3(x0, y0, zb), Vector3(x1, y0, zb), Vector3(x1, y0, zf), Vector3(x0, y0, zf),
					Vector3.DOWN, _shade(c, bottom_brightness, baked))

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _verts
	arrays[Mesh.ARRAY_NORMAL] = _normals
	arrays[Mesh.ARRAY_COLOR] = _colors
	arrays[Mesh.ARRAY_INDEX] = _indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _make_material())
	mesh_instance.mesh = mesh
	mesh_instance.transform = Transform3D.IDENTITY

	_verts.clear()
	_normals.clear()
	_colors.clear()
	_indices.clear()


func _make_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	if shading == Shading.BAKED:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	else:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		mat.roughness = 1.0
		mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return mat


func _shade(c: Color, brightness: float, baked: bool) -> Color:
	if not baked:
		return c
	return Color(c.r * brightness, c.g * brightness, c.b * brightness, 1.0)


func _is_solid(mask: PackedByteArray, w: int, h: int, x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= w or y >= h:
		return false
	return mask[y * w + x] == 1


## Adds a quad (4 corners in order around the face) facing `normal`.
## Winding is fixed up automatically so the face is front-facing for Godot (clockwise).
func _add_quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3, color: Color) -> void:
	var base := _verts.size()
	_verts.append_array([a, b, c, d])
	for i in 4:
		_normals.append(normal)
		_colors.append(color)

	# Counter-clockwise (seen from the normal side) gives a cross product along the normal;
	# Godot treats clockwise as front-facing, so flip in that case.
	if (b - a).cross(c - a).dot(normal) > 0.0:
		_indices.append_array([base, base + 2, base + 1, base, base + 3, base + 2])
	else:
		_indices.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
