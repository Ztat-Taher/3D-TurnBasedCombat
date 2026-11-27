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

## Same order as BattleCamera.ShakeStyle
enum ShakeStyle {
	RANDOM,             # Random shake direction
	DIRECTIONAL,        # Directional shake
	ROTATIONAL          # Rotational shake
}

@export var camera_shake_enabled: bool = false
@export var shake_intensity: float = 0.3              ## Shake intensity
@export var shake_duration: float = 0.2               ## Shake duration
@export var shake_style: ShakeStyle = ShakeStyle.RANDOM
@export var shake_frequency: float = 15.0              ## Shake frequency
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

## Plays these effects on the battle camera rig ([BattleCamera], which
## card_battle_manager and AnimationEvent pass in as the context "camera").
## Everything is a layer on top of the current shot, so effects return to
## exactly where the camera was and can't fight shot changes.
##   shake    - shake_decay is the fade-out exponent (1 = linear)
##   zoom     - zoom_amount multiplies the zoom (>1 in), held for nothing,
##              returned after zoom_duration if zoom_return
##   tracking - aims at the actor / target / both (midpoint) / projectile for
##              tracking_duration; tracking_speed smooths the aim (0 = exact)
##   tilt     - camera_tilt is a local rotation offset in degrees
##   fov      - blends to camera_fov and back
func apply_camera_effects(rig: Node, actor: Node, target: Node, projectile: Node = null):
	if not rig is BattleCamera:
		push_warning("CameraEffectConfig: expected the BattleCamera rig, got %s" % rig)
		return
	var cam := rig as BattleCamera

	if camera_shake_enabled:
		cam.shake(shake_duration, shake_intensity, shake_style as BattleCamera.ShakeStyle,
				shake_frequency, shake_decay)

	if camera_zoom_enabled:
		cam.zoom(zoom_amount, zoom_duration, 0.0, zoom_return, zoom_delay)

	if tracking_mode != TrackingMode.NONE:
		var nodes := _get_tracking_nodes(actor, target, projectile)
		if not nodes.is_empty():
			cam.track(nodes, tracking_duration, tracking_offset, tracking_speed)

	if camera_tilt != Vector3.ZERO:
		cam.tilt(camera_tilt, tilt_duration, 0.0, tilt_return)

	if camera_fov >= 0:
		cam.set_fov_override(camera_fov, fov_duration)

## Nodes to aim at for the tracking mode (BOTH = their midpoint)
func _get_tracking_nodes(actor: Node, target: Node, projectile: Node) -> Array:
	var nodes: Array = []
	match tracking_mode:
		TrackingMode.ACTOR:
			nodes = [actor]
		TrackingMode.TARGET, TrackingMode.CUSTOM:
			nodes = [target]
		TrackingMode.BOTH:
			nodes = [actor, target]
		TrackingMode.PROJECTILE:
			nodes = [projectile]
	return nodes.filter(func(n): return is_instance_valid(n))

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
