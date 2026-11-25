class_name OrbWeaponVisual
extends Node3D
## Visual for ORB weapons: one glowing orb per [OrbDefinition] orbiting the
## weapon owner. Driven by [OrbSystem] through [method setup_orbs],
## [method set_attuned_orb] and [method play_detonation].
##
## The scene is expected to contain orb holder nodes named `Orb0`, `Orb1`, ...
## (each with a `Mesh` MeshInstance3D child). [method setup_orbs] adopts those
## nodes — creating any that are missing — and repaints them from the weapon's
## orb definitions, so the same scene works for every ORB weapon and stays
## editable in the editor.
##
## Detonation: the orb leaves its orbit slot, arcs to the target on a
## quadratic bezier (OUT), holds briefly with a scale pulse (HOLD), then
## returns to its *current* orbit slot so it lands back in formation
## (RETURN). All motion is integrated in [_process] — no tweens.

@export var orbit_radius: float = 1.2
@export var orbit_height: float = 1.0
@export var orbit_speed: float = 1.6
@export var orb_scale: float = 0.18

## Detonation timing (seconds).
@export var detonate_out_time: float = 0.22
@export var detonate_hold_time: float = 0.09
@export var detonate_return_time: float = 0.3
## Height of the arc apex above the straight start->target line.
@export var detonate_arc_height: float = 2.4
## How far above the target's origin the orb strikes.
@export var target_height_offset: float = 1.0
## Sideways bow of the arc as a fraction of the start->target distance,
## making the path loop wider, not just higher.
@export var detonate_arc_bow: float = 0.3
## Return leg: exponential damping rate chasing the live orbit slot
## (higher = snappier), and how much the return path lifts with distance.
@export var detonate_return_damp: float = 9.0
@export var detonate_return_lift: float = 0.45

## Bounce amplitude for the Attuned orb vs the resting orbs.
@export var attuned_bounce: float = 0.3
@export var attuned_bounce_speed: float = 3.4
@export var idle_bounce: float = 0.12
@export var idle_bounce_speed: float = 2.2

var _orb_nodes: Array[Node3D] = []
var _materials: Array[StandardMaterial3D] = []
## Per-orb orbit data captured from the AUTHORED scene positions, so orbs
## keep whatever ring/height/phase the scene designer placed them on
## (including arrangements tilted by parent bones/attachments).
var _orb_radius: Array[float] = []
var _orb_base_y: Array[float] = []
var _orb_phase: Array[float] = []
var _defs: Array[OrbDefinition] = []
var _attuned: int = 0
var _time: float = 0.0
## index -> { phase, t } in LOCAL space (from/ctrl/to recomputed live so the
## moving orbit slot never distorts the curve).
var _detonations: Dictionary = {}


func _ready() -> void:
	# Orbs stay hidden/static until a weapon configures them — keeps an
	# unarmed ally from showing frozen orbs. The editor is unaffected
	# (this script does not run there).
	_sync_orb_visibility(0)
	set_process(false)


## Called by WeaponSystem with the weapon's orb roster.
func setup_orbs(defs: Array[OrbDefinition]) -> void:
	_defs = defs
	_detonations.clear()
	_orb_nodes.clear()
	_materials.clear()
	_orb_radius.clear()
	_orb_base_y.clear()
	_orb_phase.clear()
	for i in defs.size():
		var holder := _ensure_orb_holder(i)
		# Runtime-created holders spawn at the origin — seed them onto the
		# default orbit ring before capturing their authored slot.
		if not _is_authored(holder):
			holder.position = _default_slot(i, defs.size())
		_capture_orbit_slot(i, holder)
		var mesh_inst := _ensure_orb_mesh(holder)
		mesh_inst.scale = Vector3.ONE * orb_scale
		var mat := _ensure_orb_material(mesh_inst)
		mat.albedo_color = defs[i].color
		mat.emission = defs[i].color
		mat.emission_energy_multiplier = defs[i].emission_energy
		_orb_nodes.append(holder)
		_materials.append(mat)
		_set_trail(holder, false)
	_sync_orb_visibility(defs.size())
	set_attuned_orb(_attuned)
	set_process(true)


func set_attuned_orb(index: int) -> void:
	_attuned = index
	for i in _materials.size():
		var mat := _materials[i]
		var def := _defs[i] if i < _defs.size() else null
		var base_energy := def.emission_energy if def else 1.0
		# Attuned orb burns bright; the rest stay dim.
		mat.emission_energy_multiplier = base_energy * (2.2 if i == _attuned else 0.55)
		_orb_nodes[i].scale = Vector3.ONE * (1.25 if i == _attuned else 1.0)


# ---------------------------------------------------------------------------
# Orb node management (adopt scene-authored nodes, spawn missing ones)
# ---------------------------------------------------------------------------

## Default orbit slot used only for orbs the scene did not author.
func _default_slot(i: int, count: int) -> Vector3:
	var angle := TAU * float(i) / float(maxi(count, 1))
	return Vector3(cos(angle) * orbit_radius, orbit_height, sin(angle) * orbit_radius)


## True when [param holder] came from the scene file rather than being
## created by [_method _ensure_orb_holder] (runtime-created nodes have no owner).
func _is_authored(holder: Node3D) -> bool:
	return holder.owner != null


## Records the orb's authored local position as its orbit slot: radius and
## base height from the position, phase from its angle around the center.
func _capture_orbit_slot(i: int, holder: Node3D) -> void:
	var p := holder.position
	_orb_radius.append(Vector2(p.x, p.z).length())
	_orb_base_y.append(p.y)
	_orb_phase.append(atan2(p.z, p.x))


## Finds the orb's trail node (the TrailPrefab the designer attached under
## the orb's Mesh) — any descendant exposing an `enabled` property.
func _find_trail(holder: Node3D) -> Node:
	var found := holder.find_child("TrailPrefab", true, false)
	if found:
		return found
	for c in holder.find_children("*", "MeshInstance3D", true, false):
		if "enabled" in c:
			return c
	return null


func _set_trail(holder: Node3D, enabled: bool) -> void:
	var trail := _find_trail(holder)
	if trail and "enabled" in trail:
		trail.enabled = enabled


## Returns the holder node for orb [param index], adopting the scene-authored
## `OrbN` child when present or creating it otherwise.
func _ensure_orb_holder(index: int) -> Node3D:
	var wanted := "Orb%d" % index
	for c in get_children():
		if c is Node3D and c.name == wanted:
			return c
	var holder := Node3D.new()
	holder.name = wanted
	add_child(holder)
	return holder


func _ensure_orb_mesh(holder: Node3D) -> MeshInstance3D:
	var mesh_inst := holder.get_node_or_null("Mesh") as MeshInstance3D
	if mesh_inst == null:
		mesh_inst = MeshInstance3D.new()
		mesh_inst.name = "Mesh"
		var sphere := SphereMesh.new()
		sphere.radius = 1.0
		sphere.height = 2.0
		sphere.radial_segments = 16
		sphere.rings = 8
		mesh_inst.mesh = sphere
		holder.add_child(mesh_inst)
	return mesh_inst


func _ensure_orb_material(mesh_inst: MeshInstance3D) -> StandardMaterial3D:
	var mat := mesh_inst.material_override as StandardMaterial3D
	if mat == null:
		mat = StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.emission_enabled = true
		mesh_inst.material_override = mat
	return mat


## Shows the first [param count] orb holders and hides any extras (e.g. when
## a weapon has fewer orbs than the scene was authored with).
func _sync_orb_visibility(count: int) -> void:
	var i := 0
	for c in get_children():
		if c is Node3D and String(c.name).begins_with("Orb"):
			c.visible = i < count
			i += 1


# ---------------------------------------------------------------------------
# Detonation
# ---------------------------------------------------------------------------

## Launches the orb at [param index] on a curved path to [param target_pos]
## (global space). Fire-and-forget; [method _process] integrates the motion.
func play_detonation(index: int, target_pos: Vector3) -> void:
	if index < 0 or index >= _orb_nodes.size() or _detonations.has(index):
		return
	var orb := _orb_nodes[index]
	var from := orb.position
	var to := to_local(target_pos + Vector3.UP * target_height_offset)
	var ctrl := _arc_control(from, to, detonate_arc_height)
	_set_trail(orb, true)
	_detonations[index] = {
		"phase": 0,  # 0 = out, 1 = hold, 2 = return
		"t": 0.0,
		"from": from,
		"ctrl": ctrl,
		"to": to,
		"prev_slot": Vector3.ZERO,
	}


## Orbit slot position (local space) for orb [param i] at the current time.
## Built from the orb's AUTHORED slot (radius/height/phase captured in
## [method setup_orbs]) so scene-placed arrangements are preserved.
func _orbit_position(i: int) -> Vector3:
	var angle := _time * orbit_speed + _orb_phase[i]
	var is_attuned := i == _attuned
	var bob_amp := attuned_bounce if is_attuned else idle_bounce
	var bob_speed := attuned_bounce_speed if is_attuned else idle_bounce_speed
	var bob := sin(_time * bob_speed + float(i) * 1.7) * bob_amp
	return Vector3(
		cos(angle) * _orb_radius[i],
		_orb_base_y[i] + bob,
		sin(angle) * _orb_radius[i]
	)


## Quadratic bezier control point: midpoint raised by [param height] and
## bowed sideways (perpendicular to the flat travel direction) by
## [member detonate_arc_bow] * distance, so the path loops around rather
## than arcing straight up.
func _arc_control(from: Vector3, to: Vector3, height: float) -> Vector3:
	var mid := from.lerp(to, 0.5)
	var flat_dir := Vector3(to.x - from.x, 0.0, to.z - from.z)
	var side := Vector3.UP.cross(flat_dir.normalized()) if flat_dir.length_squared() > 0.0001 else Vector3.RIGHT
	return mid + Vector3.UP * height + side * flat_dir.length() * detonate_arc_bow


func _quad_bezier(p0: Vector3, p1: Vector3, p2: Vector3, t: float) -> Vector3:
	var u := 1.0 - t
	return u * u * p0 + 2.0 * u * t * p1 + t * t * p2


func _process(delta: float) -> void:
	_time += delta
	var count := _orb_nodes.size()
	for i in count:
		var orb := _orb_nodes[i]
		if _detonations.has(i):
			_update_detonation(i, orb, delta)
			continue
		var slot := _orbit_position(i)
		orb.position = slot
		orb.rotation = Vector3.ZERO
		orb.rotate_y(-(_time * orbit_speed + _orb_phase[i]))


func _update_detonation(index: int, orb: Node3D, delta: float) -> void:
	var d: Dictionary = _detonations[index]
	d["t"] += delta
	var from: Vector3 = d["from"]
	var ctrl: Vector3 = d["ctrl"]
	var to: Vector3 = d["to"]
	var slot := _orbit_position(index)

	match int(d["phase"]):
		0:  # OUT — arc from orbit slot to the target (smoothstep-eased)
			var raw_t := clampf(float(d["t"]) / detonate_out_time, 0.0, 1.0)
			var t := raw_t * raw_t * (3.0 - 2.0 * raw_t)  # smoothstep
			var prev := orb.position
			var next := _quad_bezier(from, ctrl, to, t)
			orb.position = next
			_face_along(orb, next - prev)
			# Scale pulse as it arrives.
			orb.scale = Vector3.ONE * lerpf(1.0, 1.45, t) * (1.25 if index == _attuned else 1.0)
			if raw_t >= 1.0:
				d["phase"] = 1
				d["t"] = 0.0
		1:  # HOLD — parked on the target, pulsing
			orb.position = to
			var pulse := 1.0 + sin(float(d["t"]) * 40.0) * 0.12
			orb.scale = Vector3.ONE * 1.45 * pulse * (1.25 if index == _attuned else 1.0)
			if float(d["t"]) >= detonate_hold_time:
				d["phase"] = 2
				d["t"] = 0.0
				d["prev_slot"] = slot
		2:  # RETURN — damped homing back to the LIVE orbit slot. Chasing the
			# slot each frame (instead of a fixed bezier) means the moving
			# orbit never distorts the path — no flicker. Velocity
			# feedforward (aiming ahead of the slot by v/damp) cancels the
			# steady-state lag a plain exponential chase would have, so the
			# orb actually lands on the slot instead of trailing ~0.2 behind
			# and snapping on timeout.
			var slot_vel := Vector3.ZERO
			var prev_slot: Vector3 = d["prev_slot"]
			if delta > 0.0001:
				slot_vel = (slot - prev_slot) / delta
				slot_vel = slot_vel.limit_length(8.0)
			d["prev_slot"] = slot
			var dist := orb.position.distance_to(slot)
			var lift := minf(dist * detonate_return_lift, detonate_arc_height * 0.4)
			var desired := slot + slot_vel / detonate_return_damp + Vector3.UP * lift
			var k := 1.0 - exp(-detonate_return_damp * delta)
			var prev := orb.position
			orb.position = orb.position.lerp(desired, k)
			_face_along(orb, orb.position - prev)
			# Ease the scale back down as it closes in.
			var close_factor := clampf(dist / maxf(slot.length(), 0.5), 0.0, 1.0)
			orb.scale = Vector3.ONE * lerpf(1.0, 1.45, close_factor) * (1.25 if index == _attuned else 1.0)
			if dist < 0.06 or float(d["t"]) > detonate_return_time * 4.0:
				_detonations.erase(index)
				_set_trail(orb, false)
				orb.position = slot
				orb.scale = Vector3.ONE * (1.25 if index == _attuned else 1.0)


## Yaw the orb to face along a local-space direction (visual only).
func _face_along(orb: Node3D, local_dir: Vector3) -> void:
	if local_dir.length_squared() < 0.0001:
		return
	var global_dir := (global_transform * local_dir).normalized()
	if global_dir.length_squared() < 0.0001:
		return
	var target := orb.global_position + global_dir
	if orb.global_position.distance_squared_to(target) > 0.0001:
		orb.look_at(target, Vector3.UP)
