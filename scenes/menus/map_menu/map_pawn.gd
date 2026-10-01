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

## Multi-hop pathing: the trip between two nodes is split into
## several smaller hops along a straight line.
@export var hop_segment_length: float = 0.4  ## World units between small hops
@export var hop_pause: float = 0.08          ## Brief settle between hops
@export var min_hop_segments: int = 2
@export var max_hop_segments: int = 8

var movement_tween: Tween
var rotation_tween: Tween
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
	
	base_position = position
	target_position = target_pos
	
	var distance := base_position.distance_to(target_position)
	if distance < 0.001:
		# Already there - just snap and report completion.
		current_node_id = from_node_id
		target_node_id = to_node_id
		movement_started.emit(from_node_id, to_node_id)
		_on_movement_complete()
		return
	
	is_moving = true
	current_node_id = from_node_id
	target_node_id = to_node_id
	
	movement_started.emit(from_node_id, to_node_id)
	
	# Kill any existing tween
	if movement_tween and movement_tween.is_valid():
		movement_tween.kill()
	
	# Split the straight path into multiple smaller hops.
	var segments := 1
	if hop_segment_length > 0.0:
		segments = int(round(distance / hop_segment_length))
	segments = clampi(segments, min_hop_segments, max_hop_segments)
	
	var waypoints: Array[Vector3] = []
	for i in range(1, segments + 1):
		waypoints.append(base_position.lerp(target_position, float(i) / float(segments)))
	
	# Face the direction of travel (when there is horizontal movement).
	var flat_delta := Vector3(target_position.x - base_position.x, 0.0, target_position.z - base_position.z)
	if flat_delta.length_squared() > 0.000001:
		var desired_yaw := atan2(flat_delta.x, flat_delta.z)
		# Separate tween so the turn runs alongside the first hop.
		if rotation_tween and rotation_tween.is_valid():
			rotation_tween.kill()
		rotation_tween = create_tween()
		rotation_tween.set_ease(hop_ease)
		rotation_tween.set_trans(hop_trans)
		rotation_tween.tween_property(self, "rotation:y", desired_yaw, hop_duration)
	
	# Sequential tween: one small arc hop per segment, brief settle between hops.
	movement_tween = create_tween()
	movement_tween.set_ease(hop_ease)
	movement_tween.set_trans(hop_trans)
	
	var segment_start := base_position
	for waypoint in waypoints:
		var seg_from := segment_start
		var seg_to: Vector3 = waypoint
		movement_tween.tween_method(_animate_arc_segment.bind(seg_from, seg_to), 0.0, 1.0, hop_duration)
		movement_tween.tween_interval(hop_pause)
		segment_start = seg_to
	
	# Callback when the whole movement completes
	movement_tween.tween_callback(_on_movement_complete)

## NOTE: bound args (seg_from/seg_to) arrive AFTER the tween value, so the
## signature must list progress first to match tween_method's call order.
func _animate_arc_segment(progress: float, seg_from: Vector3, seg_to: Vector3) -> void:
	# Calculate arc height using sine wave (0 -> 1 -> 0)
	var arc_offset = sin(progress * PI) * hop_height
	
	# Interpolate between this segment's endpoints
	var x = lerp(seg_from.x, seg_to.x, progress)
	var z = lerp(seg_from.z, seg_to.z, progress)
	var y = lerp(seg_from.y, seg_to.y, progress) + arc_offset
	
	position = Vector3(x, y, z)

func _on_movement_complete() -> void:
	is_moving = false
	base_position = target_position
	hop_completed.emit()
	movement_finished.emit()

func set_position_instant(new_position: Vector3) -> void:
	if movement_tween and movement_tween.is_valid():
		movement_tween.kill()
	if rotation_tween and rotation_tween.is_valid():
		rotation_tween.kill()
	
	position = new_position
	base_position = new_position
	is_moving = false

func get_current_position() -> Vector3:
	return position

func is_at_target() -> bool:
	return not is_moving and position.distance_to(target_position) < 0.01
