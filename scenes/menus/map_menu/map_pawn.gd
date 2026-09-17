extends MeshInstance3D
class_name MapPawn

## 3D pawn that hops between nodes on the map
## Uses tween system for smooth arc-based movement animations

signal movement_started(from_node: String, to_node: String)
signal movement_finished()
signal hop_completed()

var current_node_id: String = ""
var target_node_id: String = ""
var is_moving: bool = false

## Animation parameters
@export var hop_height: float = 1.0
@export var hop_duration: float = 0.5
@export var hop_ease: Tween.EaseType = Tween.EASE_OUT
@export var hop_trans: Tween.TransitionType = Tween.TRANS_CUBIC

var movement_tween: Tween
var base_position: Vector3 = Vector3.ZERO
var target_position: Vector3 = Vector3.ZERO

func _ready() -> void:
	base_position = position
	# Set default material if none exists
	if not mesh:
		create_default_mesh()
	if not material_override:
		create_default_material()

func create_default_mesh() -> void:
	var box = BoxMesh.new()
	box.size = Vector3(0.5, 0.5, 0.5)
	mesh = box

func create_default_material() -> void:
	var material = StandardMaterial3D.new()
	material.albedo_color = Color.WHITE
	material_override = material

func hop_to_position(target_pos: Vector3, from_node_id: String = "", to_node_id: String = "") -> void:
	if is_moving:
		return
	
	is_moving = true
	current_node_id = from_node_id
	target_node_id = to_node_id
	base_position = position
	target_position = target_pos
	
	movement_started.emit(from_node_id, to_node_id)
	
	# Kill any existing tween
	if movement_tween and movement_tween.is_valid():
		movement_tween.kill()
	
	# Create new tween for hop animation
	movement_tween = create_tween()
	movement_tween.set_ease(hop_ease)
	movement_tween.set_trans(hop_trans)
	
	# Animate the entire movement with arc using a single method
	movement_tween.tween_method(_animate_arc, 0.0, 1.0, hop_duration)
	
	# Add rotation for visual interest
	movement_tween.tween_property(self, "rotation:y", rotation.y + PI, hop_duration)
	
	# Callback when movement completes
	movement_tween.tween_callback(_on_movement_complete)

func _animate_arc(progress: float) -> void:
	# Calculate arc height using sine wave (0 -> 1 -> 0)
	var arc_offset = sin(progress * PI) * hop_height
	
	# Interpolate horizontal position (X and Z)
	var x = lerp(base_position.x, target_position.x, progress)
	var z = lerp(base_position.z, target_position.z, progress)
	var y = lerp(base_position.y, target_position.y, progress) + arc_offset
	
	position = Vector3(x, y, z)

func _on_movement_complete() -> void:
	is_moving = false
	base_position = target_position
	hop_completed.emit()
	movement_finished.emit()

func set_position_instant(new_position: Vector3) -> void:
	if movement_tween and movement_tween.is_valid():
		movement_tween.kill()
	
	position = new_position
	base_position = new_position
	is_moving = false

func get_current_position() -> Vector3:
	return position

func is_at_target() -> bool:
	return not is_moving and position.distance_to(target_position) < 0.01
