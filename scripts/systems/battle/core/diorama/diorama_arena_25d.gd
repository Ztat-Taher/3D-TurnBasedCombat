class_name DioramaArena25D
extends Resource
## Data-driven resource defining a 360-degree diorama arena backdrop, floor, and concentric rings.

@export_group("Arena Info")
@export var arena_name: String = "Haligtree Arena":
	set(v):
		arena_name = v
		emit_changed()

@export_group("Floor Geometry & Material")
@export var floor_radius: float = 12.0:
	set(v):
		floor_radius = v
		emit_changed()
@export var floor_mesh: Mesh:
	set(v):
		floor_mesh = v
		emit_changed()
@export var floor_albedo: Texture2D:
	set(v):
		floor_albedo = v
		emit_changed()
@export var floor_normal: Texture2D:
	set(v):
		floor_normal = v
		emit_changed()
@export var floor_roughness: float = 0.8:
	set(v):
		floor_roughness = v
		emit_changed()
@export var floor_uv_scale: Vector2 = Vector2(4.0, 4.0):
	set(v):
		floor_uv_scale = v
		emit_changed()

@export_group("360 Concentric Panorama Rings")
## Array of concentric cylindrical layers building depth from far horizon into the arena
@export var panorama_rings: Array[DioramaRingLayer25D] = []:
	set(v):
		panorama_rings = v
		emit_changed()

@export_group("Midground Elements & Billboards")
@export var elements: Array[DioramaElement25D] = []:
	set(v):
		elements = v
		emit_changed()

@export_group("Atmosphere & Lighting Cues")
@export var directional_light_rotation_degrees: Vector3 = Vector3(-40.0, 35.0, 0.0):
	set(v):
		directional_light_rotation_degrees = v
		emit_changed()
@export var directional_light_color: Color = Color(1.0, 0.96, 0.88):
	set(v):
		directional_light_color = v
		emit_changed()
@export var directional_light_energy: float = 1.4:
	set(v):
		directional_light_energy = v
		emit_changed()
@export var ambient_color: Color = Color(0.42, 0.48, 0.58):
	set(v):
		ambient_color = v
		emit_changed()
@export var fog_enabled: bool = false:
	set(v):
		fog_enabled = v
		emit_changed()
@export var fog_color: Color = Color(0.65, 0.72, 0.80):
	set(v):
		fog_color = v
		emit_changed()
@export var fog_density: float = 0.002:
	set(v):
		fog_density = v
		emit_changed()
