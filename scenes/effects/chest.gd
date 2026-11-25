extends Node3D

enum ChestType {
	WOOD,
	STONE,
	GOLD
}

@export var chest_type: ChestType = ChestType.WOOD
@export var clicks_required: int = 5
@export var chest_collision_layer: int = 2  # Collision layer for raycasting

@export_group("Shake")
## Duration of a single shake at speed 1.0 (seconds)
@export var shake_base_duration: float = 0.25
## Speed added to the shake per click (1.0 = normal speed)
@export var shake_speed_per_click: float = 0.35
## Intensity added to the shake per click (1.0 = normal tilt)
@export var shake_intensity_per_click: float = 0.12
@export var max_shake_speed: float = 4.0
@export var max_shake_intensity: float = 2.0
## Small vertical hop during the shake, scaled by intensity
@export var shake_hop_height: float = 0.015
## Random sideways (Z) tilt added per shake, scaled by intensity
@export var shake_side_wobble: float = 0.04

signal chest_opened
signal vestige_revealed
signal clicks_progress(current: int, required: int)

@onready var chest_animation_player: AnimationPlayer = $AnimationPlayer
@onready var rarity_vfx: ChestRarityVFX = get_node_or_null("RarityVFX")

var chest_model: Node3D
var chest_top: Node3D
var vestige_icon_mesh: ExtrudedPixelMesh
var vestige_icon_tween: Tween
var vestige_idle_tween: Tween
## Where the icon spawns: VestigeIconMesh's position as placed in chest.tscn
var vestige_icon_origin: Vector3 = Vector3.ZERO
var shake_tween: Tween
var camera_3d: Camera3D

var current_clicks: int = 0
var is_opening: bool = false
var current_shake_speed: float = 1.0
var current_shake_intensity: float = 1.0

@export_group("Fitting")
## Where the item spawns relative to the measured rim (negative = inside the chest)
@export var icon_rim_offset: float = -0.05

## Measured from the loaded model's body (lid excluded), in this node's space.
## Everything that has to line up with the chest is placed from these.
var chest_rim_height: float = 0.15
var chest_opening: Vector2 = Vector2(0.44, 0.28)
var chest_center: Vector3 = Vector3.ZERO

## Rarity look for the opening VFX (set via set_rarity)
var rarity_color: Color = Color.WHITE
var rarity_tier: int = 0
var _charge_step: int = 0

const CHEST_SCENES = {
	ChestType.WOOD: preload("res://assets/models/chests/wood_chest.glb"),
	ChestType.STONE: preload("res://assets/models/chests/stone_chest.glb"),
	ChestType.GOLD: preload("res://assets/models/chests/gold_chest.glb")
}

## Icon scale when it first appears, and the scale it grows to during the reveal
const VESTIGE_ICON_SPAWN_SCALE := 0.05
const VESTIGE_ICON_FULL_SCALE := 1.25
## How far above its spawn point the item rises: peak, then where it settles, plus its idle bob
const VESTIGE_RISE_PEAK := 0.49
const VESTIGE_RISE_SETTLE := 0.42
const VESTIGE_IDLE_BOB := 0.04

## Lid rotation when closed (matches the start of the "open" animation)
const LID_CLOSED_ROTATION := Vector3(0.0, PI / 2.0, 0.0)

## Shake keyframes, ported from the old "Idle" animation.
## Each entry: [time as fraction of the shake duration, X tilt, Z tilt]
const SHAKE_KEYS: Array = [
	[0.1333, 0.0454, 0.0],
	[0.2667, 0.0750, 0.0],
	[0.4000, 0.0489, 0.0],
	[0.6667, -0.1065, 0.0035],
	[1.0000, 0.0, 0.0],
]

func _ready():
	_find_vestige_icon()
	load_chest_model()
	_setup_input()


## Plays one shake of the chest body.
## intensity scales how far it tilts/hops, speed scales how fast it plays (2.0 = twice as fast).
## Calling it while a shake is running restarts it from the current pose, so rapid clicks chain smoothly.
func shake(intensity: float = 1.0, speed: float = 1.0) -> void:
	if not chest_model:
		return

	if shake_tween:
		shake_tween.kill()

	# During the opening build-up each shake leaks more rarity light
	if is_opening and rarity_vfx:
		_charge_step += 1
		rarity_vfx.charge(_charge_step)

	var duration := shake_base_duration / maxf(speed, 0.01)
	var side := 1.0 if randf() < 0.5 else -1.0
	var wobble := shake_side_wobble * intensity * side

	# Parallel tween with explicit delays, so rotation keys and the hop run on one timeline
	shake_tween = create_tween().set_parallel(true)

	# Rotation: walk through the keyframes
	var prev_time := 0.0
	for i in SHAKE_KEYS.size():
		var key: Array = SHAKE_KEYS[i]
		var is_last := i == SHAKE_KEYS.size() - 1
		var target := Vector3(
			key[1] * intensity,
			0.0,
			key[2] * intensity + (0.0 if is_last else wobble * sin(key[0] * PI))
		)
		shake_tween.tween_property(chest_model, "rotation", target, (key[0] - prev_time) * duration) \
			.set_delay(prev_time * duration) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		prev_time = key[0]

	# Hop: up for the first 40%, then drop back down with a little bounce
	if shake_hop_height > 0.0:
		var hop := shake_hop_height * intensity
		shake_tween.tween_property(chest_model, "position:y", hop, duration * 0.4) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		shake_tween.tween_property(chest_model, "position:y", 0.0, duration * 0.6) \
			.set_delay(duration * 0.4) \
			.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


## Instantly returns the chest body to its rest pose and stops any shake.
func stop_shake() -> void:
	if shake_tween:
		shake_tween.kill()
		shake_tween = null
	if chest_model:
		chest_model.rotation = Vector3.ZERO
		chest_model.position = Vector3.ZERO

func _setup_input():
	# Enable input processing for click detection
	set_process_input(true)

func _input(event):
	# This won't be called in SubViewport - input handled by parent screen
	pass

func _find_vestige_icon():
	# Look for vestige icon in the chest scene
	for child in get_children():
		if child is ExtrudedPixelMesh and child.name == "VestigeIconMesh":
			vestige_icon_mesh = child
			vestige_icon_origin = vestige_icon_mesh.position
			_hide_vestige_icon()
			print("Chest: Found vestige icon mesh")
			break
	if not vestige_icon_mesh:
		print("Chest: Warning - VestigeIconMesh not found in chest scene")

func _check_chest_click(event):
	print("Chest: _check_chest_click called")

	# Get the SubViewport this chest is in
	var sub_viewport = get_viewport()
	if not sub_viewport:
		print("Chest: No sub_viewport found")
		return
	print("Chest: SubViewport found, size: ", sub_viewport.size)

	# Get the main viewport (root)
	var root_viewport = get_tree().root
	if not root_viewport:
		print("Chest: No root_viewport found")
		return
	print("Chest: Root viewport found, size: ", root_viewport.size)

	# Get mouse position in root viewport coordinates
	var root_mouse_pos = root_viewport.get_mouse_position()
	print("Chest: Root mouse position: ", root_mouse_pos)

	# Calculate scale factor between root viewport and SubViewport
	var root_size = root_viewport.size
	var sub_size = sub_viewport.size
	var scale_factor = Vector2(root_size.x / sub_size.x, root_size.y / sub_size.y)
	print("Chest: Scale factor: ", scale_factor)

	# Convert root mouse position to SubViewport coordinates
	var sub_mouse_pos = root_mouse_pos / scale_factor
	print("Chest: SubViewport mouse position: ", sub_mouse_pos)

	# Find camera in SubViewport
	camera_3d = null
	for child in sub_viewport.get_children():
		if child is Camera3D:
			camera_3d = child
			break

	if not camera_3d:
		print("Chest: No camera found in SubViewport")
		return
	print("Chest: Camera found at position: ", camera_3d.global_position)

	# Project ray from camera using SubViewport coordinates
	var ray_origin = camera_3d.project_ray_origin(sub_mouse_pos)
	var ray_direction = camera_3d.project_ray_normal(sub_mouse_pos)
	print("Chest: Ray origin: ", ray_origin)
	print("Chest: Ray direction: ", ray_direction)

	# Create ray query
	var ray_params = PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_direction * 100.0)
	ray_params.collide_with_bodies = true
	ray_params.collide_with_areas = false
	ray_params.collision_mask = 2  # Chest collision layer

	# Perform raycast in SubViewport's physics world
	var result = sub_viewport.get_world_3d().direct_space_state.intersect_ray(ray_params)

	if result:
		print("Chest: Raycast hit something at: ", result.position)
		print("Chest: Hit collider: ", result.collider)
		print("Chest: Is self? ", result.collider == self)
	else:
		print("Chest: Raycast hit nothing")

	if result and result.collider == self:
		print("Chest: Click registered!")
		on_chest_clicked()
		get_viewport().set_input_as_handled()
	else:
		print("Chest: Click did not hit chest")

func on_chest_clicked():
	print("Chest: on_chest_clicked called!")
	if is_opening:
		print("Chest: is_opening is true, ignoring click")
		return

	current_clicks += 1
	clicks_progress.emit(current_clicks, clicks_required)

	# Each click shakes faster and harder
	current_shake_speed = minf(current_shake_speed + shake_speed_per_click, max_shake_speed)
	current_shake_intensity = minf(current_shake_intensity + shake_intensity_per_click, max_shake_intensity)
	shake(current_shake_intensity, current_shake_speed)
	if rarity_vfx and not is_opening:
		rarity_vfx.charge(0)

	# Check if threshold reached
	if current_clicks >= clicks_required:
		print("Chest: Click threshold reached, starting opening sequence")
		start_opening_sequence()
	else:
		print("Chest: Click threshold not reached yet")

func load_chest_model():
	stop_shake()
	chest_top = null
	if chest_model:
		remove_child(chest_model)
		chest_model.queue_free()

	var chest_scene = CHEST_SCENES[chest_type]
	print("Chest: Loading chest type: ", chest_type, " from path: ", chest_scene.resource_path)
	chest_model = chest_scene.instantiate()
	chest_model.name = "chest"
	add_child(chest_model)
	move_child(chest_model, 0)

	chest_model.transform = Transform3D.IDENTITY

	_rename_chest_parts()
	if chest_top:
		chest_top.rotation = LID_CLOSED_ROTATION

	_measure_chest()
	_fit_to_chest()

	# Wait a frame for the model to be fully set up, then give an intro shake
	await get_tree().process_frame
	shake()

func _rename_chest_parts():
	for child in chest_model.get_children():
		if child.name.to_lower().contains("top") or child.name.to_lower().contains("lid"):
			child.name = "top"
			chest_top = child
		elif child is AnimationPlayer:
			child.queue_free()
	
	if not chest_top:
		for child in chest_model.get_children():
			if child is Node3D:
				for grandchild in child.get_children():
					if grandchild.name.to_lower().contains("top") or grandchild.name.to_lower().contains("lid"):
						grandchild.name = "top"
						chest_top = grandchild
					elif grandchild is AnimationPlayer:
						grandchild.queue_free()

## Measures the chest body (every mesh except the lid) so effects can fit any model
func _measure_chest() -> void:
	var body := AABB()
	var found := false
	var stack: Array[Node] = [chest_model]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node == chest_top:
			continue
		if node is MeshInstance3D and (node as MeshInstance3D).mesh:
			var box := _transform_to_self(node as Node3D) * (node as MeshInstance3D).get_aabb()
			body = box if not found else body.merge(box)
			found = true
		stack.append_array(node.get_children())
	if not found:
		return
	chest_rim_height = body.end.y
	chest_opening = Vector2(body.size.x, body.size.z)
	chest_center = body.get_center()


## Highest point the revealed item reaches, in world space (for camera framing)
func get_reveal_top() -> Vector3:
	var item_half := 0.0
	if vestige_icon_mesh:
		item_half = vestige_icon_mesh.target_size * VESTIGE_ICON_FULL_SCALE * 0.5
	var rise := maxf(VESTIGE_RISE_PEAK, VESTIGE_RISE_SETTLE + VESTIGE_IDLE_BOB)
	return to_global(vestige_icon_origin + Vector3(0.0, rise + item_half, 0.0))


## Node transform relative to this chest (works before/without global transforms)
func _transform_to_self(node: Node3D) -> Transform3D:
	var xform := Transform3D.IDENTITY
	var current: Node = node
	while current and current != self:
		if current is Node3D:
			xform = (current as Node3D).transform * xform
		current = current.get_parent()
	return xform


## Places the item spawn and the rarity VFX from the measurements
func _fit_to_chest() -> void:
	if rarity_vfx:
		rarity_vfx.fit_to_chest(chest_rim_height, chest_opening, chest_center)

	if vestige_icon_mesh:
		vestige_icon_origin = Vector3(chest_center.x, chest_rim_height + icon_rim_offset, chest_center.z)
		if not vestige_icon_mesh.visible:
			_hide_vestige_icon()


func set_chest_type(type: ChestType):
	chest_type = type
	load_chest_model()  # Plays its own intro shake once the model is in


## Colors and scales the opening VFX for a vestige rarity
func set_rarity(rarity: Vestige.Rarity) -> void:
	rarity_color = Vestige.get_rarity_color(rarity)
	rarity_tier = Vestige.get_rarity_tier(rarity)
	if rarity_vfx:
		rarity_vfx.set_rarity(rarity_color, rarity_tier)


## Called by AnimationPlayer's "open" right as the lid flies open
func _on_lid_burst() -> void:
	if rarity_vfx:
		rarity_vfx.burst()
		if vestige_icon_mesh:
			rarity_vfx.attach_rays_to(vestige_icon_mesh)
	chest_opened.emit()
	_play_vestige_reveal_animation()

func play_open_sequence():
	# Legacy function - now use start_opening_sequence
	start_opening_sequence()

func start_opening_sequence():
	if is_opening:
		return

	is_opening = true
	_charge_step = 0
	# "open" is the whole sequence: build-up shakes (each calls shake()),
	# the lid flying open, and _on_lid_burst() for the VFX + item reveal
	if chest_animation_player:
		chest_animation_player.play("open")

func reset_chest():
	current_clicks = 0
	is_opening = false
	current_shake_speed = 1.0
	current_shake_intensity = 1.0
	stop_shake()
	if chest_animation_player:
		chest_animation_player.stop()
	if chest_top:
		chest_top.rotation = LID_CLOSED_ROTATION
	_charge_step = 0
	if rarity_vfx:
		rarity_vfx.reset()
	if vestige_icon_tween:
		vestige_icon_tween.kill()
	if vestige_idle_tween:
		vestige_idle_tween.kill()
	_hide_vestige_icon()

func set_vestige_icon(texture: Texture2D):
	if vestige_icon_mesh:
		vestige_icon_mesh.set_texture(texture)
	else:
		print("Chest: Warning - vestige_icon_mesh is null, cannot set texture")

func _play_vestige_reveal_animation():
	if not vestige_icon_mesh:
		return

	vestige_icon_mesh.visible = true

	if vestige_icon_tween:
		vestige_icon_tween.kill()

	vestige_icon_tween = create_tween()
	vestige_icon_tween.set_parallel(true)

	# Start small at the spawn point inside the chest
	vestige_icon_mesh.position = vestige_icon_origin
	vestige_icon_mesh.scale = Vector3.ONE * VESTIGE_ICON_SPAWN_SCALE
	var base_y := vestige_icon_origin.y

	# Rise up out of the chest
	vestige_icon_tween.tween_property(vestige_icon_mesh, "position:y", base_y + 0.28, 1.0).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	vestige_icon_tween.tween_property(vestige_icon_mesh, "position:y", base_y + VESTIGE_RISE_PEAK, 0.5).set_delay(1.0)

	# Grow from small to full size as it rises (slight overshoot for a pop)
	vestige_icon_tween.tween_property(vestige_icon_mesh, "scale", Vector3.ONE * VESTIGE_ICON_FULL_SCALE, 0.9).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

	# Fast spin that slows down as it settles (rotation is in radians)
	vestige_icon_tween.tween_property(vestige_icon_mesh, "rotation:y", TAU * 2.0, 2.0).set_delay(0.5).as_relative() \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

	# Final float animation
	vestige_icon_tween.tween_property(vestige_icon_mesh, "position:y", base_y + VESTIGE_RISE_SETTLE, 1.5).set_delay(1.5).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)

	# Emit signal when reveal animation is mostly done
	vestige_icon_tween.tween_callback(func(): vestige_revealed.emit()).set_delay(1.0)

	# Then keep it slowly spinning and bobbing, like a dropped item
	vestige_icon_tween.tween_callback(_start_vestige_idle).set_delay(3.0)


func _hide_vestige_icon():
	if not vestige_icon_mesh:
		return
	vestige_icon_mesh.visible = false
	vestige_icon_mesh.position = vestige_icon_origin
	vestige_icon_mesh.rotation = Vector3.ZERO
	vestige_icon_mesh.scale = Vector3.ONE * VESTIGE_ICON_SPAWN_SCALE


func _start_vestige_idle():
	if not vestige_icon_mesh:
		return
	if vestige_idle_tween:
		vestige_idle_tween.kill()

	var base_y := vestige_icon_mesh.position.y
	vestige_idle_tween = create_tween().set_loops().set_parallel(true)
	vestige_idle_tween.tween_property(vestige_icon_mesh, "rotation:y", TAU, 4.0).as_relative()
	vestige_idle_tween.tween_property(vestige_icon_mesh, "position:y", base_y + VESTIGE_IDLE_BOB, 2.0) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	vestige_idle_tween.tween_property(vestige_icon_mesh, "position:y", base_y, 2.0).set_delay(2.0) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
