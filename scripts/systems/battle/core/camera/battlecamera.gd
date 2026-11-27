class_name BattleCamera
extends Node
## Battle camera rig: the single owner of the gameplay Camera3D.
##
## Nothing else writes the camera. Every frame [method _process] composes:
##
##   shot        - base transform + FOV. A shot is live: it's rebuilt every
##                 frame from where its subjects are now (see "Shots"), and
##                 a shot change blends from the previous one into it.
##   + pull-back - dolly along the shot's backward axis (dodge/jump zoom-out)
##   + tracking  - aim blended toward a node or group's midpoint
##   + tilt      - local rotation offset (degrees)
##   + FOV       - override blended over the shot FOV, then divided by zoom
##   + shake     - h_offset/v_offset, which shift the view without moving
##                 the camera
##
## Each layer has its own tween and rests at a neutral value, so layers
## overlap freely. A shot change mid-shake or mid-dodge can't make the camera
## jump, drift or end up offset. Gameplay code (cards, battlers, effects,
## CameraEffectConfig) calls the methods below and never touches the Camera3D.
##
## All rig timing (shot moves, layers, shake) follows the battle manager's
## speed_multiplier live, so speeding up mid-move speeds up that move too.
##
## Which shot is on screen is decided by requests, not call order. Each
## system keeps one request under its own key at a priority (ShotPriority);
## the highest priority wins, the newest wins a tie. When a system is done it
## releases its key and the camera falls back to the next request down, e.g.
## leaving targeting returns to the turn's shot without anyone having to know
## what that was. With no requests the camera rests on the default shot.
##   request_shot(&"turn", ShotPriority.TURN, CameraMode.OVER_THE_SHOULDER, battler)
##   release_shot(&"targeting")

enum CameraMode {
	DEFAULT,
	OVER_THE_SHOULDER,
	ENEMY_OVERVIEW,
	TARGET_FOCUS
}

## Shot request priorities (higher wins)
enum ShotPriority {
	TURN = 0,        ## Whose turn it is (player over-the-shoulder, enemy turn beats)
	TARGETING = 10,  ## Choosing a target
	EXECUTION = 20,  ## A card or action resolving
	CINEMATIC = 30,  ## Scripted moments that override everything
}

enum ShakeStyle {
	RANDOM,       ## Jitter in a random direction every frame
	DIRECTIONAL,  ## Back-and-forth along one screen direction
	ROTATIONAL,   ## Circular wobble
}

@export var ots_camera_scene: PackedScene = preload("res://scenes/battle/cameras/perspective/over_the_shoulder_camera.tscn")
@export var overview_camera_scene: PackedScene = preload("res://scenes/battle/cameras/overview/enemy_overview_camera.tscn")
@export var focus_camera_scene: PackedScene = preload("res://scenes/battle/cameras/focus/target_focus_camera.tscn")

@export var transition_duration: float = 0.45
## How quickly a shot follows its subjects as they move (1/s; 0 = rigidly).
## Smoothing keeps quick moves (a dodge, a hit reaction) from jolting the view.
@export var follow_smoothing: float = 6.0
## Follow subjects up and down too. Off by default so jumps and hit bounces
## don't bob the camera.
@export var follow_vertical: bool = false
@export var fov_padding: float = 1.3 ## Distance multiplier around a single subject
@export var wide_fov_padding: float = 2.0 ## Distance multiplier for group shots (overview)

var camera: Camera3D
var current_mode: CameraMode = CameraMode.DEFAULT
var default_fov: float

var _default_transform: Transform3D

# ── Shot (base layer) ──
## Base transform/FOV this frame (blend of the previous shot into the live one)
var _shot_transform: Transform3D
var _shot_fov: float = 75.0
var _has_shot: bool = false
var _shot_tween: Tween ## Tweens _blend 0 -> 1

## The live shot: placed at offset _live_relative from a frame whose origin is
## the subjects' (smoothed) anchor point and whose basis comes from the
## battle axis, so it follows the subjects without depending on their facing
var _live_subjects: Array = []
var _live_basis: Basis = Basis()
var _live_relative: Transform3D = Transform3D()
var _live_fov: float = 75.0
var _live_anchor: Vector3 = Vector3.ZERO
var _anchor_height: float = 0.0
var _blend_from: Transform3D
var _blend_from_fov: float = 75.0
var _blend: float = 1.0

## Battle axis: horizontal unit vector from the player side to the enemy side
var _axis: Vector3 = Vector3.BACK
var _axis_ready: bool = false

# ── Additive layers (neutral values) ──
var _pullback: float = 0.0
var _pullback_tween: Tween

var _track_nodes: Array = []
var _track_offset: Vector3 = Vector3.ZERO
var _track_speed: float = 0.0 ## 0 = follow exactly; else smoothing rate (1/s)
var _track_point: Vector3
var _track_weight: float = 0.0
var _track_tween: Tween

var _tilt_degrees: Vector3 = Vector3.ZERO
var _tilt_tween: Tween

var _zoom: float = 1.0
var _zoom_tween: Tween

var _fov_override: float = 75.0
var _fov_override_weight: float = 0.0
var _fov_tween: Tween

var _shake_time_left: float = 0.0
var _shake_duration: float = 0.0
var _shake_intensity: float = 0.0
var _shake_style: ShakeStyle = ShakeStyle.RANDOM
var _shake_frequency: float = 15.0
var _shake_decay: float = 1.0
var _shake_direction: Vector2 = Vector2.RIGHT

## Shot requests: key -> {priority, mode, subject, order}
var _requests: Dictionary = {}
var _request_order: int = 0
## Key and order of the request currently on screen (order changes when a
## key is re-requested, so re-requests re-apply)
var _applied_key: StringName = &""
var _applied_order: int = -1

## Shot prefab data (local transform + FOV), read once per scene. The prefab
## camera instance is freed right away rather than kept as an orphan node.
var _prefab_cache: Dictionary = {}


func _ready() -> void:
	# Place the camera before anything else this frame reads it (HUD projections,
	# mouse raycasts), so they never see last frame's position
	process_priority = -100
	call_deferred("_setup_camera")


func _setup_camera() -> void:
	if not camera or not is_instance_valid(camera):
		camera = _find_camera()
	if camera:
		_default_transform = camera.global_transform
		default_fov = camera.fov
		_shot_transform = _default_transform
		_shot_fov = default_fov
		_live_subjects = []
		_live_basis = Basis()
		_live_anchor = Vector3.ZERO
		_live_relative = _default_transform
		_live_fov = default_fov
		_blend = 1.0
		_has_shot = true
		# Requests made before the camera was found (e.g. the battle intro)
		_applied_order = -1
		_applied_key = &"__none__"
		_refresh_shot()


# ═════════════════════════════════════════════════════════════════════════════
# Composition
# ═════════════════════════════════════════════════════════════════════════════

func _process(delta: float) -> void:
	if not _has_shot or not is_instance_valid(camera):
		return
	var speed := get_speed()
	for t: Tween in [_shot_tween, _pullback_tween, _track_tween, _tilt_tween, _zoom_tween, _fov_tween]:
		if t and t.is_valid():
			t.set_speed_scale(speed)
	delta *= speed
	_update_live_shot(delta)
	var xform := _shot_transform
	xform.basis = xform.basis.orthonormalized()

	# Pull-back
	xform.origin += xform.basis.z * _pullback

	# Tracking: blend the aim toward the tracked point
	if _track_weight > 0.0:
		var goal: Variant = _get_track_goal()
		if goal != null:
			if _track_speed <= 0.0:
				_track_point = goal
			else:
				_track_point = _track_point.lerp(goal, 1.0 - exp(-_track_speed * delta))
		var to_point := _track_point - xform.origin
		if to_point.length_squared() > 0.0001:
			var up := Vector3.UP if absf(to_point.normalized().dot(Vector3.UP)) < 0.99 else xform.basis.z
			var look := Basis.looking_at(to_point, up)
			xform.basis = Basis(Quaternion(xform.basis).slerp(Quaternion(look), _track_weight))

	# Tilt (local)
	if _tilt_degrees != Vector3.ZERO:
		xform.basis = xform.basis * Basis.from_euler(_tilt_degrees * (PI / 180.0))

	camera.global_transform = xform

	var fov := lerpf(_shot_fov, _fov_override, _fov_override_weight)
	camera.fov = clampf(fov / maxf(_zoom, 0.01), 1.0, 179.0)

	_apply_shake(delta)


func _apply_shake(delta: float) -> void:
	if _shake_time_left <= 0.0:
		if camera.h_offset != 0.0 or camera.v_offset != 0.0:
			camera.h_offset = 0.0
			camera.v_offset = 0.0
		return
	_shake_time_left = maxf(_shake_time_left - delta, 0.0)
	var strength := _current_shake_strength()
	var elapsed := _shake_duration - _shake_time_left
	var offset := Vector2.ZERO
	match _shake_style:
		ShakeStyle.RANDOM:
			offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * strength
		ShakeStyle.DIRECTIONAL:
			offset = _shake_direction * sin(elapsed * _shake_frequency * TAU) * strength
		ShakeStyle.ROTATIONAL:
			var angle := elapsed * _shake_frequency * TAU
			offset = Vector2(cos(angle), sin(angle)) * strength
	camera.h_offset = offset.x
	camera.v_offset = offset.y


func _current_shake_strength() -> float:
	if _shake_time_left <= 0.0 or _shake_duration <= 0.0:
		return 0.0
	return _shake_intensity * pow(_shake_time_left / _shake_duration, _shake_decay)


## Midpoint of the tracked nodes plus the offset, or null when none are left
## (the aim then stays on the last known point, e.g. a projectile that hit).
func _get_track_goal() -> Variant:
	var sum := Vector3.ZERO
	var count := 0
	for node in _track_nodes:
		if is_instance_valid(node) and node is Node3D:
			sum += (node as Node3D).global_position
			count += 1
	if count == 0:
		return null
	return sum / count + _track_offset


## Battle speed (the battle manager's speed_multiplier; 1 without one).
func get_speed() -> float:
	var manager := get_parent()
	if manager and "speed_multiplier" in manager:
		return maxf(float(manager.speed_multiplier), 0.01)
	return 1.0



# ═════════════════════════════════════════════════════════════════════════════
# Shot requests
# ═════════════════════════════════════════════════════════════════════════════

## Puts (or replaces) [param key]'s request. [param subject] is the battler
## for OVER_THE_SHOULDER / TARGET_FOCUS, or an Array of battlers for
## ENEMY_OVERVIEW; DEFAULT needs none.
func request_shot(key: StringName, priority: ShotPriority, mode: CameraMode, subject: Variant = null) -> void:
	_request_order += 1
	_requests[key] = {"priority": priority, "mode": mode, "subject": subject, "order": _request_order}
	_refresh_shot()


func release_shot(key: StringName) -> void:
	if _requests.erase(key):
		_refresh_shot()


func release_all_shots_except(keep: Array[StringName] = []) -> void:
	var changed := false
	for key in _requests.keys():
		if key not in keep:
			_requests.erase(key)
			changed = true
	if changed:
		_refresh_shot()


func has_shot_request(key: StringName) -> bool:
	return _requests.has(key)


## Key of the request on screen (&"" = none, resting on the default shot).
func get_active_shot_key() -> StringName:
	return _applied_key


func _top_request_key() -> StringName:
	var best: StringName = &""
	for key: StringName in _requests:
		var r: Dictionary = _requests[key]
		if best == &"":
			best = key
			continue
		var b: Dictionary = _requests[best]
		if r.priority > b.priority or (r.priority == b.priority and r.order > b.order):
			best = key
	return best


func _refresh_shot() -> void:
	var key := _top_request_key()
	var order: int = _requests[key].order if key != &"" else -1
	if key == _applied_key and order == _applied_order:
		return
	_applied_key = key
	_applied_order = order
	if key == &"":
		set_default_camera()
		return
	var r: Dictionary = _requests[key]
	match r.mode:
		CameraMode.OVER_THE_SHOULDER:
			if r.subject is Battler and is_instance_valid(r.subject):
				set_over_the_shoulder(r.subject)
			else:
				set_default_camera()
		CameraMode.TARGET_FOCUS:
			if r.subject is Battler and is_instance_valid(r.subject):
				set_target_focus(r.subject)
			else:
				set_default_camera()
		CameraMode.ENEMY_OVERVIEW:
			var group: Array = r.subject if r.subject is Array else []
			if group.any(func(b): return is_instance_valid(b)):
				set_enemy_overview(group)
			else:
				set_default_camera()
		_:
			set_default_camera()


# ═════════════════════════════════════════════════════════════════════════════
# Shots (applied by the request stack; gameplay code should request instead)
# ═════════════════════════════════════════════════════════════════════════════

## Every shot is placed relative to an anchor: the subjects' mean position
## (smoothed, height locked unless follow_vertical), turned to face along the
## battle axis. The offset from the anchor is fixed when the shot starts
## (prefab offset + distance fitted to the subjects' bounds), then the shot
## follows the anchor every frame - so a shot on a battler that runs, dodges or
## gets knocked back keeps framing it, and a battler turning to face its target
## never swings the camera.
##   over-the-shoulder / target focus: the battler's side of the axis (its
##     +Z faces the other side), anchored on the battler
##   enemy overview: the player side's frame, anchored on the enemies' center
##   default: the scene camera, fixed

func set_default_camera() -> void:
	current_mode = CameraMode.DEFAULT
	_start_shot([], Basis(), _default_transform, default_fov)


func set_over_the_shoulder(player_battler: Battler) -> void:
	current_mode = CameraMode.OVER_THE_SHOULDER
	if not player_battler or not is_instance_valid(player_battler):
		return
	var prefab := _get_prefab(ots_camera_scene)
	if prefab.is_empty():
		return
	_start_shot([player_battler], get_side_basis(player_battler), prefab.transform, prefab.fov)


func set_enemy_overview(enemies: Array) -> void:
	current_mode = CameraMode.ENEMY_OVERVIEW
	var valid_enemies := enemies.filter(func(e): return is_instance_valid(e) and e is Battler)
	if valid_enemies.is_empty():
		return
	var prefab := _get_prefab(overview_camera_scene)
	if prefab.is_empty():
		return
	# Seen from the players' side, looking along the axis at the enemies
	_start_shot(valid_enemies, _basis_facing(get_battle_axis()), prefab.transform, prefab.fov, true)


func set_target_focus(target_battler: Battler) -> void:
	current_mode = CameraMode.TARGET_FOCUS
	if not target_battler or not is_instance_valid(target_battler):
		return
	var prefab := _get_prefab(focus_camera_scene)
	if prefab.is_empty():
		return
	_start_shot([target_battler], get_side_basis(target_battler), prefab.transform, prefab.fov, false)


## Starts a live shot on [param subjects]: [param local] (the prefab offset) in
## a frame with [param frame_basis] at the subjects' anchor. [param fit] null =
## keep the prefab distance, true/false = fit the subjects (wide/tight padding).
func _start_shot(subjects: Array, frame_basis: Basis, local: Transform3D, fov: float, fit: Variant = null) -> void:
	if not _has_shot:
		return
	var anchor := _subjects_anchor(subjects) if not subjects.is_empty() else Vector3.ZERO
	var frame := Transform3D(frame_basis, anchor)
	var target := frame * local
	if fit != null:
		target = _fit_distance(target, subjects, fov, fit)
	_live_subjects = subjects
	_live_basis = frame_basis
	_live_relative = frame.affine_inverse() * target
	_live_fov = fov
	_live_anchor = anchor
	_anchor_height = anchor.y
	# Blend from wherever the base is right now (mid-blend included)
	_blend_from = _shot_transform
	_blend_from_fov = _shot_fov
	_blend = 0.0
	if _shot_tween and _shot_tween.is_valid():
		_shot_tween.kill()
	_shot_tween = create_tween().set_speed_scale(get_speed()) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_shot_tween.tween_property(self, "_blend", 1.0, transition_duration)


## Follows the subjects and blends the previous shot into the live one.
func _update_live_shot(delta: float) -> void:
	if not _live_subjects.is_empty():
		var goal := _subjects_anchor(_live_subjects, _live_anchor)
		if not follow_vertical:
			goal.y = _anchor_height
		if follow_smoothing <= 0.0:
			_live_anchor = goal
		else:
			_live_anchor = _live_anchor.lerp(goal, 1.0 - exp(-follow_smoothing * delta))
	var live := Transform3D(_live_basis, _live_anchor) * _live_relative
	if _blend >= 1.0:
		_shot_transform = live
		_shot_fov = _live_fov
	else:
		_shot_transform = _blend_from.interpolate_with(live, _blend)
		_shot_fov = lerpf(_blend_from_fov, _live_fov, _blend)


## Mean position of the subjects still around ([param fallback] if none are).
func _subjects_anchor(subjects: Array, fallback: Vector3 = Vector3.ZERO) -> Vector3:
	var sum := Vector3.ZERO
	var count := 0
	for node in subjects:
		if is_instance_valid(node) and node is Node3D:
			sum += (node as Node3D).global_position
			count += 1
	return sum / count if count > 0 else fallback


# ─────────────────────────────────────────────────────────────────────────────
# Battle axis
# ─────────────────────────────────────────────────────────────────────────────

## Horizontal unit vector from the player side toward the enemy side, worked
## out once (on first use, before anyone has moved) and then fixed:
##   1. a Node3D in the "battle_axis" group: its +Z (place one in an arena
##      to set the axis explicitly)
##   2. the direction the two sides face each other at the start (players'
##      +Z and the reverse of the enemies' +Z, averaged)
##   3. the line from the players' center to the enemies' center
##   4. world +Z
func get_battle_axis() -> Vector3:
	if not _axis_ready:
		refresh_battle_axis()
	return _axis


## Re-derives the battle axis (e.g. after rearranging an arena mid-battle).
func refresh_battle_axis() -> void:
	_axis_ready = true
	var marker := get_tree().get_first_node_in_group("battle_axis") as Node3D if is_inside_tree() else null
	if marker:
		var z := _flat(marker.global_transform.basis.z)
		if z != Vector3.ZERO:
			_axis = z
			return
	var players := _side_members(true)
	var enemies := _side_members(false)
	var facing := Vector3.ZERO
	for p in players:
		facing += _flat(p.global_transform.basis.z)
	for e in enemies:
		facing -= _flat(e.global_transform.basis.z)
	if facing.length() > 0.1:
		_axis = facing.normalized()
		return
	if not players.is_empty() and not enemies.is_empty():
		var line := _flat(_subjects_anchor(enemies) - _subjects_anchor(players))
		if line != Vector3.ZERO:
			_axis = line
			return
	_axis = Vector3.BACK


## Basis whose +Z faces the other side: along the axis for players, against
## it for enemies.
func get_side_basis(battler: Node) -> Basis:
	var axis := get_battle_axis()
	return _basis_facing(axis if _is_player_side(battler) else -axis)


## Basis with +Z pointing along [param forward] and Y up.
func _basis_facing(forward: Vector3) -> Basis:
	return Basis.looking_at(-forward, Vector3.UP)


func _is_player_side(battler: Node) -> bool:
	return battler in _side_members(true) or battler.is_in_group("players")


func _side_members(players: bool) -> Array:
	var manager := get_parent()
	var key := "players" if players else "enemies"
	var members: Array = []
	if manager and key in manager and manager.get(key) is Array:
		members = manager.get(key)
	if members.is_empty() and is_inside_tree():
		members = get_tree().get_nodes_in_group(key)
	return members.filter(func(b): return is_instance_valid(b) and b is Node3D)


func _flat(v: Vector3) -> Vector3:
	v.y = 0.0
	return v.normalized() if v.length_squared() > 0.000001 else Vector3.ZERO


## {transform, fov} of a shot prefab, or {} if the scene isn't a Camera3D.
func _get_prefab(scene: PackedScene) -> Dictionary:
	if scene == null:
		return {}
	if not _prefab_cache.has(scene):
		var instance := scene.instantiate()
		var data := {}
		if instance is Camera3D:
			data = {"transform": (instance as Camera3D).transform, "fov": (instance as Camera3D).fov}
		instance.free()
		_prefab_cache[scene] = data
	return _prefab_cache[scene]


## Moves [param shot] along its line to the subjects' center so they fit at
## [param fov] (the shot's own FOV, not the camera's current one).
func _fit_distance(shot: Transform3D, subjects: Array, fov: float, wide: bool) -> Transform3D:
	var bounds := _combined_bounds(subjects)
	if bounds.size == Vector3.ZERO:
		return shot
	var max_size := maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
	var distance := (max_size / 2.0) / tan(deg_to_rad(fov) / 2.0)
	distance *= wide_fov_padding if wide else fov_padding
	var center := bounds.get_center()
	var fitted := shot
	fitted.origin = center + (shot.origin - center).normalized() * distance
	return fitted


## World-space bounds of the subjects (battlers use get_combined_aabb()).
func _combined_bounds(subjects: Array) -> AABB:
	var bounds := AABB()
	var has_bounds := false
	for node in subjects:
		if not is_instance_valid(node) or not node is Node3D:
			continue
		var boxes: Array = []
		if node is Battler:
			boxes.append([node.get_combined_aabb(), (node as Node3D).global_transform])
		else:
			var visuals: Array = node.find_children("*", "VisualInstance3D", true, false)
			if node is VisualInstance3D:
				visuals.append(node)
			for vis in visuals:
				boxes.append([(vis as VisualInstance3D).get_aabb(), (vis as Node3D).global_transform])
		for entry in boxes:
			var local: AABB = entry[0]
			var xform: Transform3D = entry[1]
			var world: AABB = xform * local # all 8 corners: rotation and scale included
			bounds = world if not has_bounds else bounds.merge(world)
			has_bounds = true
	return bounds


# ═════════════════════════════════════════════════════════════════════════════
# Layers
# ═════════════════════════════════════════════════════════════════════════════

## Dolly back from the shot by [param distance] (negative = push in).
func set_pullback(distance: float, duration: float) -> void:
	_pullback_tween = _retween(_pullback_tween, "_pullback", distance, duration)


## Dodge/jump zoom-out (kept for battler.gd).
func adjust_camera_distance_for_evasion(distance_offset: float, duration: float) -> void:
	set_pullback(distance_offset, duration)


func reset_camera_distance() -> void:
	set_pullback(0.0, 0.15)


## Shakes the view for [param duration] seconds. [param intensity] is the peak
## offset in world units. [param decay] is the fade-out exponent (1 = linear,
## higher fades faster). A new shake doesn't cut short a stronger one that's
## still running.
func shake(duration: float, intensity: float, style: ShakeStyle = ShakeStyle.RANDOM,
		frequency: float = 15.0, decay: float = 1.0, direction: Vector2 = Vector2.RIGHT) -> void:
	if duration <= 0.0 or intensity <= 0.0:
		return
	if intensity < _current_shake_strength():
		return
	_shake_duration = duration
	_shake_time_left = duration
	_shake_intensity = intensity
	_shake_style = style
	_shake_frequency = frequency
	_shake_decay = maxf(decay, 0.01)
	_shake_direction = direction.normalized() if direction != Vector2.ZERO else Vector2.RIGHT


func shake_stop() -> void:
	_shake_time_left = 0.0


## Multiplies the zoom ([param amount] > 1 zooms in) over [param duration],
## holds it for [param hold] seconds, then returns if [param return_after].
func zoom(amount: float, duration: float, hold: float = 0.0, return_after: bool = true, delay: float = 0.0) -> void:
	_zoom_tween = _pulse(_zoom_tween, "_zoom", maxf(amount, 0.01), 1.0, duration, hold, return_after, delay)


## Blends the FOV to [param fov] over [param duration], holds it for
## [param hold] seconds, then blends back to the shot FOV if [param return_after].
func set_fov_override(fov: float, duration: float, hold: float = 0.0, return_after: bool = true) -> void:
	_fov_override = fov
	_fov_tween = _pulse(_fov_tween, "_fov_override_weight", 1.0, 0.0, duration, hold, return_after)


## Rotates the view by [param degrees] (local pitch/yaw/roll), holds it for
## [param hold] seconds, then rotates back if [param return_after].
func tilt(degrees: Vector3, duration: float, hold: float = 0.0, return_after: bool = true) -> void:
	_tilt_tween = _pulse(_tilt_tween, "_tilt_degrees", degrees, Vector3.ZERO, duration, hold, return_after)


## Aims the camera at [param nodes] (their midpoint plus [param offset]) for
## [param duration] seconds, blending in and out over [param blend_time].
## A [param speed] of 0 follows exactly; otherwise the aim point follows with
## that smoothing rate.
func track(nodes: Array, duration: float, offset: Vector3 = Vector3.ZERO, speed: float = 0.0, blend_time: float = 0.2) -> void:
	_track_nodes = nodes.filter(func(n): return is_instance_valid(n) and n is Node3D)
	if _track_nodes.is_empty():
		return
	_track_offset = offset
	_track_speed = speed
	if _track_weight <= 0.0:
		_track_point = _get_track_goal()
	var hold := maxf(duration - blend_time * 2.0, 0.0)
	_track_tween = _pulse(_track_tween, "_track_weight", 1.0, 0.0, blend_time, hold, true)


func stop_tracking(blend_time: float = 0.2) -> void:
	_track_tween = _retween(_track_tween, "_track_weight", 0.0, blend_time)


## Returns every layer (pull-back, tracking, tilt, zoom, FOV, shake) to
## neutral over [param duration], leaving the shot alone.
func clear_effects(duration: float = 0.2) -> void:
	shake_stop()
	set_pullback(0.0, duration)
	stop_tracking(duration)
	_tilt_tween = _retween(_tilt_tween, "_tilt_degrees", Vector3.ZERO, duration)
	_zoom_tween = _retween(_zoom_tween, "_zoom", 1.0, duration)
	_fov_tween = _retween(_fov_tween, "_fov_override_weight", 0.0, duration)


## Kills [param old] and tweens [param property] to [param value].
func _retween(old: Tween, property: String, value: Variant, duration: float) -> Tween:
	if old and old.is_valid():
		old.kill()
	if duration <= 0.0:
		set(property, value)
		return null
	var t := create_tween().set_speed_scale(get_speed()).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(self, property, value, duration)
	return t


## Tweens [param property] to [param peak], holds, and optionally back to
## [param rest].
func _pulse(old: Tween, property: String, peak: Variant, rest: Variant, duration: float,
		hold: float, return_after: bool, delay: float = 0.0) -> Tween:
	if old and old.is_valid():
		old.kill()
	var t := create_tween().set_speed_scale(get_speed()).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	if delay > 0.0:
		t.tween_interval(delay)
	t.tween_property(self, property, peak, maxf(duration, 0.001))
	if return_after:
		if hold > 0.0:
			t.tween_interval(hold)
		t.tween_property(self, property, rest, maxf(duration, 0.001))
	return t


# ═════════════════════════════════════════════════════════════════════════════
# Camera lookup and screen-space helpers
# ═════════════════════════════════════════════════════════════════════════════

## Returns the resolved gameplay camera (re-resolves on demand).
func get_camera() -> Camera3D:
	if not camera or not is_instance_valid(camera):
		camera = _find_camera()
	return camera


## Resolves the gameplay Camera3D wherever it lives:
##  - the active camera of this controller's own viewport (legacy layout)
##  - a Camera3D child of the parent node (legacy layout)
##  - a camera in the "battle_camera" group (recommended for SubViewport layouts)
##  - any active camera found inside a SubViewport of the current scene
func _find_camera() -> Camera3D:
	if not is_inside_tree():
		return null
	var own_cam := get_viewport().get_camera_3d()
	if own_cam is Camera3D:
		return own_cam
	var parent := get_parent()
	if parent:
		var parent_camera = parent.get_node_or_null("Camera3D")
		if parent_camera is Camera3D:
			return parent_camera
	var grouped := get_tree().get_first_node_in_group("battle_camera")
	if grouped is Camera3D:
		return grouped
	for viewport in _find_sub_viewports(get_tree().current_scene):
		var sub_cam := viewport.get_camera_3d()
		if sub_cam:
			return sub_cam
	return null


func _find_sub_viewports(node: Node) -> Array[SubViewport]:
	var result: Array[SubViewport] = []
	if node == null:
		return result
	if node is SubViewport:
		result.append(node)
	for child in node.get_children():
		result.append_array(_find_sub_viewports(child))
	return result


## Ratio between the root HUD viewport's coordinate space and the gameplay
## SubViewport's render space (e.g. 2x when a 640x360 viewport fills a 1280x720
## window). Unprojected camera coordinates must be multiplied by this to land in
## root HUD space.
func get_viewport_scale() -> Vector2:
	var cam := get_camera()
	if not cam:
		return Vector2.ONE
	var vp := cam.get_viewport()
	if not vp:
		return Vector2.ONE
	var view_size := Vector2(vp.get_visible_rect().size)
	if view_size.x <= 0.0 or view_size.y <= 0.0:
		return Vector2.ONE
	var root_vp := get_viewport()
	if not root_vp:
		return Vector2.ONE
	var root_size := Vector2(root_vp.get_visible_rect().size)
	if root_size.x <= 0.0 or root_size.y <= 0.0:
		return Vector2.ONE
	return Vector2(root_size.x / view_size.x, root_size.y / view_size.y)


## Project a world-space position into root HUD screen coordinates.
func world_to_screen(world_pos: Vector3) -> Vector2:
	var cam := get_camera()
	if not cam:
		return Vector2.ZERO
	return cam.unproject_position(world_pos) * get_viewport_scale()


## Convert a root-HUD screen point to the gameplay camera's viewport space.
func screen_to_viewport(screen_point: Vector2) -> Vector2:
	return screen_point / get_viewport_scale()


## World-space ray origin for a root-HUD mouse position (used for mouse
## targeting while the camera lives inside a low-res SubViewport).
func project_ray_origin(screen_point: Vector2) -> Vector3:
	var cam := get_camera()
	if not cam:
		return Vector3.ZERO
	return cam.project_ray_origin(screen_to_viewport(screen_point))


## World-space ray direction for a root-HUD mouse position.
func project_ray_normal(screen_point: Vector2) -> Vector3:
	var cam := get_camera()
	if not cam:
		return Vector3.ZERO
	return cam.project_ray_normal(screen_to_viewport(screen_point))


## True if a world-space position is behind the gameplay camera.
func is_position_behind(world_pos: Vector3) -> bool:
	var cam := get_camera()
	if not cam:
		return false
	return cam.is_position_behind(world_pos)
