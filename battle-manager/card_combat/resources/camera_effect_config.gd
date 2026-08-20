class_name CameraEffectConfig
extends Resource
## Camera effect configuration for cinematic card effects
## Controls camera shake, zoom, and tracking behavior

enum TrackingMode {
	NONE,               # No special tracking
	ACTOR,              # Track actor
	TARGET,             # Track target
	BOTH,               # Track both actor and target
	PROJECTILE,         # Track projectile
	CUSTOM              # Custom tracking
}

enum ShakeStyle {
	RANDOM,             # Random shake direction
	DIRECTIONAL,        # Directional shake
	ROTATIONAL          # Rotational shake
}

@export var camera_shake_enabled: bool = false
@export var shake_intensity: float = 0.5              ## Shake intensity
@export var shake_duration: float = 0.3               ## Shake duration
@export var shake_style: ShakeStyle = ShakeStyle.RANDOM
@export var shake_frequency: float = 20.0              ## Shake frequency
@export var shake_decay: float = 1.0                  ## Shake decay rate

@export var camera_zoom_enabled: bool = false
@export var zoom_amount: float = 1.0                 ## Zoom level (1.0 = no zoom, <1.0 = zoom out, >1.0 = zoom in)
@export var zoom_duration: float = 0.5                ## Zoom duration
@export var zoom_delay: float = 0.0                  ## Delay before zoom starts
@export var zoom_return: bool = true                  ## Whether to return to original zoom

@export var tracking_mode: TrackingMode = TrackingMode.NONE
@export var tracking_speed: float = 5.0               ## How fast camera tracks target
@export var tracking_offset: Vector3 = Vector3.ZERO   ## Offset from tracked target
@export var tracking_duration: float = 1.0            ## How long to track

@export var camera_tilt: Vector3 = Vector3.ZERO       ## Camera tilt/rotation
@export var tilt_duration: float = 0.5                ## Tilt animation duration
@export var tilt_return: bool = true                  ## Whether to return to original tilt

@export var camera_fov: float = -1.0                  ## FOV override (-1 = no change)
@export var fov_duration: float = 0.5                 ## FOV change duration

## Apply camera effects to the current camera
func apply_camera_effects(camera: Camera3D, actor: Node, target: Node, projectile: Node = null):
	if not camera:
		push_warning("CameraEffectConfig: No camera provided")
		return
	
	if camera_shake_enabled:
		_apply_shake(camera)
	
	if camera_zoom_enabled:
		_apply_zoom(camera)
	
	if tracking_mode != TrackingMode.NONE:
		_apply_tracking(camera, actor, target, projectile)
	
	if camera_tilt != Vector3.ZERO:
		_apply_tilt(camera)
	
	if camera_fov >= 0:
		_apply_fov(camera)

## Apply camera shake
func _apply_shake(camera: Camera3D):
	var shake_tween = camera.create_tween()
	
	var original_position = camera.global_position
	var shake_timer = 0.0
	
	var total_frames = int(shake_duration * 60) # Assuming 60 FPS
	for i in range(total_frames):
		var decay = 1.0 - (shake_timer / shake_duration) * shake_decay
		var current_intensity = shake_intensity * decay
		
		var shake_offset = Vector3.ZERO
		match shake_style:
			ShakeStyle.RANDOM:
				shake_offset = Vector3(
					randf_range(-current_intensity, current_intensity),
					randf_range(-current_intensity, current_intensity),
					randf_range(-current_intensity, current_intensity)
				)
			ShakeStyle.DIRECTIONAL:
				shake_offset = Vector3(current_intensity, 0, 0)
			ShakeStyle.ROTATIONAL:
				var angle = shake_timer * shake_frequency
				shake_offset = Vector3(
					cos(angle) * current_intensity,
					sin(angle) * current_intensity,
					0
				)
		
		camera.global_position = original_position + shake_offset
		shake_timer += 1.0 / 60.0 # Assume 60 FPS
		await camera.get_tree().process_frame
	
	camera.global_position = original_position

## Apply camera zoom
func _apply_zoom(camera: Camera3D):
	if not camera is Camera3D:
		return
	
	var original_fov = camera.fov
	var target_fov = original_fov / zoom_amount
	
	var zoom_tween = camera.create_tween()
	
	if zoom_delay > 0:
		zoom_tween.tween_interval(zoom_delay)
	
	zoom_tween.tween_property(camera, "fov", target_fov, zoom_duration)
	
	if zoom_return:
		zoom_tween.tween_property(camera, "fov", original_fov, zoom_duration)

## Apply camera tracking
func _apply_tracking(camera: Node3D, actor: Node, target: Node, projectile: Node):
	var track_target = _get_tracking_target(actor, target, projectile)
	if not track_target:
		return
	
	var original_position = camera.global_position
	var tracking_timer = 0.0
	
	var total_frames = int(tracking_duration * 60) # Assuming 60 FPS
	for i in range(total_frames):
		var target_position = track_target.global_position + tracking_offset
		var direction = (target_position - camera.global_position).normalized()
		var distance = camera.global_position.distance_to(target_position)
		
		if distance > 0.1:
			var move_amount = min(distance, tracking_speed / 60.0)
			camera.global_position += direction * move_amount
		
		tracking_timer += 1.0 / 60.0 # Assume 60 FPS
		await camera.get_tree().process_frame
	
	# Return to original position if configured
	if tracking_mode == TrackingMode.NONE:
		var return_tween = camera.create_tween()
		return_tween.tween_property(camera, "global_position", original_position, 0.5)

## Get target to track based on tracking mode
func _get_tracking_target(actor: Node, target: Node, projectile: Node) -> Node:
	match tracking_mode:
		TrackingMode.ACTOR:
			return actor
		TrackingMode.TARGET:
			return target
		TrackingMode.BOTH:
			# Return midpoint between actor and target
			if actor and target:
				return null # Would need a temporary midpoint node
			return actor if actor else target
		TrackingMode.PROJECTILE:
			return projectile
		TrackingMode.CUSTOM:
			# Would need custom implementation
			return target
		_:
			return null

## Apply camera tilt
func _apply_tilt(camera: Node3D):
	var original_rotation = camera.rotation_degrees
	
	var tilt_tween = camera.create_tween()
	tilt_tween.tween_property(camera, "rotation_degrees", camera_tilt, tilt_duration)
	
	if tilt_return:
		tilt_tween.tween_property(camera, "rotation_degrees", original_rotation, tilt_duration)

## Apply FOV change
func _apply_fov(camera: Camera3D):
	if not camera is Camera3D:
		return
	
	var original_fov = camera.fov
	
	var fov_tween = camera.create_tween()
	fov_tween.tween_property(camera, "fov", camera_fov, fov_duration)
	fov_tween.tween_property(camera, "fov", original_fov, fov_duration)

## Create preset camera effects
static func create_impact_shake() -> CameraEffectConfig:
	var config = CameraEffectConfig.new()
	config.camera_shake_enabled = true
	config.shake_intensity = 0.8
	config.shake_duration = 0.4
	config.shake_style = ShakeStyle.RANDOM
	config.shake_frequency = 25.0
	config.shake_decay = 1.5
	return config

static func create_dramatic_zoom() -> CameraEffectConfig:
	var config = CameraEffectConfig.new()
	config.camera_zoom_enabled = true
	config.zoom_amount = 1.5
	config.zoom_duration = 0.3
	config.zoom_delay = 0.1
	config.zoom_return = true
	return config

static func create_tracking_shot() -> CameraEffectConfig:
	var config = CameraEffectConfig.new()
	config.tracking_mode = TrackingMode.PROJECTILE
	config.tracking_speed = 8.0
	config.tracking_duration = 2.0
	config.tracking_offset = Vector3(0, 1, 0)
	return config

static func create_screen_tilt() -> CameraEffectConfig:
	var config = CameraEffectConfig.new()
	config.camera_tilt = Vector3(0, 0, 15)
	config.tilt_duration = 0.3
	config.tilt_return = true
	return config

## Validate configuration
func validate() -> Array[String]:
	var issues: Array[String] = []
	
	if camera_shake_enabled and shake_duration <= 0:
		issues.append("Camera shake enabled but invalid duration")
	
	if camera_zoom_enabled and zoom_amount <= 0:
		issues.append("Camera zoom enabled but invalid zoom amount")
	
	if tracking_mode != TrackingMode.NONE and tracking_duration <= 0:
		issues.append("Tracking enabled but invalid duration")
	
	return issues
