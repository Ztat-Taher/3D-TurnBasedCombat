class_name DioramaElement25D
extends Resource
## Represents a 2.5D element (pillar, ruin, tree, arch) placed radially in the 360 diorama.

@export var name: String = "Diorama Element"
@export var albedo_texture: Texture2D
@export var normal_texture: Texture2D
@export_range(0.0, 360.0, 0.1) var angle_degrees: float = 0.0
@export_range(5.0, 60.0, 0.5) var distance_from_center: float = 16.0
@export var height_offset: float = 0.0
@export var size: Vector2 = Vector2(6.0, 8.0)
@export var face_center: bool = true
@export_range(0.0, 2.0, 0.05) var normal_scale: float = 1.0
@export_range(0.0, 1.0, 0.05) var light_influence: float = 0.5
@export_range(0.0, 1.0, 0.01) var alpha_scissor_threshold: float = 0.5
