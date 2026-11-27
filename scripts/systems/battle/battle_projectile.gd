class_name BattleProjectile
extends Node3D
## Drives a projectile VFX scene from its spawn point toward a target.
## Attach this as a child of the projectile scene root (or make the root extend it).
## Emits [signal arrived] when the projectile reaches the target; the parent scene
## is then freed by the caller that launched the projectile.

signal arrived
## Emitted by the card battle manager once this projectile's impact has been
## fully resolved (damage applied). The node is freed right after.
signal resolved
## Emitted when the projectile reaches the depth of one of its pierce targets
## (see [method set_pierce_targets]); always before [signal arrived].
signal passed_target(target: Node3D)

## Travel speed in metres per second.
var speed: float = 12.0
## Speed curve for varying velocity over time (slow start, fast travel)
var speed_curve: Curve = null
## Peak arc height in metres (0 = straight line).
var arc_height: float = 0.0
## Shape of the arc over the flight (x = progress 0..1, y = fraction of
## arc_height). Should start and end at 0. Null = a sine hump.
var arc_curve: Curve = null
## Scales the arc: 0 = straight line, 1 = the full arc_height.
var curve_influence: float = 0.5
## Battle manager whose speed_multiplier (hold Space) scales the flight.
var battle_manager: Node = null

## Damage/effect data for this projectile
var damage_data: Dictionary = {}
## Seconds before the projectile is forced to arrive (safety net: a speed
## curve that samples 0, a zero speed or a bad target can never strand it).
var lifetime: float = 5.0

var _age: float = 0.0

var _origin: Vector3
var _target_pos: Vector3
var _total_dist: float = 0.0
var _traveled: float = 0.0
var _traveling: bool = false
var _previous_pos: Vector3
var _applied_speed: float = 1.0
## Pierce targets not yet passed: [{target, at}], "at" = path progress 0..1
var _pierce: Array = []

## Slowest a speed curve may make the projectile, as a fraction of speed, so a
## curve sampling 0 can't stall it mid-flight.
const MIN_SPEED_FRACTION := 0.05

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
	_age = 0.0
	global_position = from
	_previous_pos = from
	_traveling = true
	_pierce.clear()
	if _total_dist > 0.01:
		_face(_path_point(0.02) - _path_point(0.0))


## Makes the projectile pass through [param targets] (an AOE slash/wave):
## each is reported by [signal passed_target] once the projectile has come as
## far along [param axis] as that target stands (so a row of targets is struck
## together, and nearer rows first). [param axis] defaults to the flight
## direction. Call after [method launch].
func set_pierce_targets(targets: Array, axis: Vector3 = Vector3.ZERO) -> void:
	_pierce.clear()
	var flat := Vector3(_target_pos.x - _origin.x, 0.0, _target_pos.z - _origin.z)
	axis.y = 0.0
	axis = axis.normalized() if axis.length_squared() > 0.0001 else flat.normalized()
	var reach := flat.dot(axis)  # how far along the axis the whole flight goes
	for t in targets:
		if not (t is Node3D and is_instance_valid(t)):
			continue
		var at := 1.0
		if reach > 0.01:
			var offset: Vector3 = (t as Node3D).global_position - _origin
			offset.y = 0.0
			at = clampf(offset.dot(axis) / reach, 0.0, 1.0)
		_pierce.append({"target": t, "at": at})
	_pierce.sort_custom(func(a, b): return a.at < b.at)


## Position on the flight path at progress [param t] (0..1): the straight line
## from origin to target, raised by the arc.
func _path_point(t: float) -> Vector3:
	var p := _origin.lerp(_target_pos, t)
	var shape := arc_curve.sample(t) if arc_curve else sin(t * PI)
	p.y += arc_height * shape * clampf(curve_influence, 0.0, 1.0)
	return p


## Points the projectile's nose along [param direction], banking with the
## path (pitch included) and keeping its up side up. Projectile VFX scenes are
## authored with their nose on local +X.
func _face(direction: Vector3) -> void:
	if direction.length_squared() < 0.000001:
		return
	var nose := direction.normalized()
	var up_hint := Vector3.UP if absf(nose.dot(Vector3.UP)) < 0.999 else Vector3.FORWARD
	var side := nose.cross(up_hint).normalized()
	var up := side.cross(nose)
	global_basis = Basis(nose, up, side)


## Battle speed (1 = normal).
func get_speed() -> float:
	if battle_manager and "speed_multiplier" in battle_manager:
		return maxf(0.01, float(battle_manager.speed_multiplier))
	return 1.0


## Keeps the VFX children (particles, animations, trails) at battle speed.
func _sync_vfx_speed() -> void:
	var s := get_speed()
	if is_equal_approx(s, _applied_speed):
		return
	_applied_speed = s
	for child in get_children():
		if "speed_scale" in child:
			child.speed_scale = s
	for trail in find_children("*", "MeshInstance3D", true, false):
		if "speed_scale" in trail and "points" in trail:
			trail.speed_scale = s


func _process(delta: float) -> void:
	_sync_vfx_speed()
	if not _traveling:
		return

	delta *= get_speed()
	_age += delta
	if _total_dist < 0.01 or (lifetime > 0.0 and _age >= lifetime):
		_arrive()
		return

	var t := clampf(_traveled / _total_dist, 0.0, 1.0)

	# Get speed multiplier from curve (slow start, fast travel)
	var speed_mult := 1.0
	if speed_curve:
		speed_mult = maxf(MIN_SPEED_FRACTION, speed_curve.sample(t))

	var step := speed * speed_mult * delta
	_traveled += step

	# Recalculate t with new traveled distance
	t = clampf(_traveled / _total_dist, 0.0, 1.0)

	_previous_pos = global_position
	global_position = _path_point(t)

	# Face along the path's tangent (exact, not frame-to-frame), so the nose
	# follows the arc up and down as well as left and right
	_face(_path_point(minf(t + 0.02, 1.0)) - _path_point(maxf(t - 0.02, 0.0)))

	# Pierce targets the projectile has now reached
	while not _pierce.is_empty() and t >= float(_pierce[0].at):
		passed_target.emit(_pierce.pop_front().target)

	if t >= 1.0 or global_position.distance_to(_target_pos) <= ARRIVAL_THRESHOLD:
		_arrive()


func _arrive() -> void:
	global_position = _target_pos
	_traveling = false
	# Anything still unpassed (e.g. lifetime ran out) is hit now
	while not _pierce.is_empty():
		passed_target.emit(_pierce.pop_front().target)
	arrived.emit()
