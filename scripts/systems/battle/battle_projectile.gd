class_name BattleProjectile
extends Node3D
## Drives a projectile VFX scene from its spawn point toward a target.
## Attach this as a child of the projectile scene root (or make the root extend it).
## Emits [signal arrived] when the projectile reaches the target; the parent scene
## is then freed by the caller that launched the projectile.

signal arrived

## Travel speed in metres per second.
var speed: float = 12.0
## Speed curve for varying velocity over time (slow start, fast travel)
var speed_curve: Curve = null
## Peak arc height in metres (0 = straight line).
var arc_height: float = 0.0
## Arc curve for dynamic curvature over time
var arc_curve: Curve = null
## How much the curve affects the path (0=straight, 1=full curve)
var curve_influence: float = 0.5

## Damage/effect data for this projectile
var damage_data: Dictionary = {}

var _origin: Vector3
var _target_pos: Vector3
var _total_dist: float = 0.0
var _traveled: float = 0.0
var _traveling: bool = false
var _previous_pos: Vector3

const ARRIVAL_THRESHOLD := 0.18

## Call this immediately after adding the projectile to the scene tree.
## [param from] and [param to] are global positions.
func launch(from: Vector3, to: Vector3, p_speed: float = speed, p_arc: float = arc_height) -> void:
	speed = p_speed
	arc_height = p_arc
	_origin = from
	_target_pos = to
	_total_dist = from.distance_to(to)
	_traveled = 0.0
	global_position = from
	_previous_pos = from
	_traveling = true
	# Orient the visual toward the target on the horizontal plane
	# VFX faces +Y locally (due to -90° Y transform), so we rotate +90° Y to align +Y with direction
	if _total_dist > 0.01:
		var flat_dir = Vector3(_target_pos.x - from.x, 0.0, _target_pos.z - from.z).normalized()
		if flat_dir.length_squared() > 0.01:
			# look_at aligns -Z with target, then rotate +90° Y to align +Y with direction
			look_at(global_position + flat_dir, Vector3.UP)
			rotate_y(PI / 2)

func _process(delta: float) -> void:
	if not _traveling:
		return

	var t := clampf(_traveled / _total_dist, 0.0, 1.0)

	# Get speed multiplier from curve (slow start, fast travel)
	var speed_mult := 1.0
	if speed_curve:
		speed_mult = speed_curve.sample(t)

	var step := speed * speed_mult * delta
	_traveled += step

	# Recalculate t with new traveled distance
	t = clampf(_traveled / _total_dist, 0.0, 1.0)

	# Lerp base position along the straight line
	var base_pos := _origin.lerp(_target_pos, t)

	# Apply dynamic arc height from curve
	var current_arc_height := arc_height
	if arc_curve:
		current_arc_height = arc_height * arc_curve.sample(t)
	
	# Mix between straight line and curved path based on curve_influence
	var curved_height := current_arc_height * sin(t * PI)
	if curve_influence > 0.0:
		base_pos.y += curved_height * curve_influence
	else:
		base_pos.y += curved_height

	# Store previous position BEFORE updating
	_previous_pos = global_position
	global_position = base_pos

	# Orient projectile toward its velocity direction (missile-like)
	var velocity = (global_position - _previous_pos).normalized()
	if velocity.length_squared() > 0.01:
		look_at(global_position + velocity, Vector3.UP)
		rotate_y(PI / 2)
		# Explicitly rotate child VFX to ensure it inherits the orientation
		for child in get_children():
			if child is Node3D:
				child.look_at(global_position + velocity, Vector3.UP)
				child.rotate_y(PI / 2)

	if t >= 1.0 or global_position.distance_to(_target_pos) <= ARRIVAL_THRESHOLD:
		global_position = _target_pos
		_traveling = false
		arrived.emit()
