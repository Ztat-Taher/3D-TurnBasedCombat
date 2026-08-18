extends Node
class_name CameraShake

# Global camera shake system for game feel
# Provides multiple shake patterns for different combat events

signal shake_started
signal shake_finished

var camera: Camera3D
var shake_tween: Tween
var current_shake_intensity: float = 0.0
var current_shake_duration: float = 0.0
var current_shake_decay: float = 0.0
var shake_offset: Vector3 = Vector3.ZERO
var original_rotation: Vector3 = Vector3.ZERO
var is_shaking: bool = false
var noise: FastNoiseLite
var noise_seed: int = 0

# Shake parameters
var shake_noise_offset: float = 0.0

func _ready() -> void:
	noise = FastNoiseLite.new()
	noise.seed = randi()
	noise.frequency = 2.0
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX

func set_camera(cam: Camera3D) -> void:
	camera = cam
	if camera:
		original_rotation = camera.rotation

# Quick, high-intensity shake for hits
func impact_shake(intensity: float = 0.5, duration: float = 0.3) -> void:
	print("CameraShake: impact_shake - intensity: ", intensity, " duration: ", duration, " camera: ", camera, " camera valid: ", is_instance_valid(camera))
	if not camera:
		push_error("CameraShake: No camera set!")
		return
	_start_shake(intensity, duration, 3.0)

# Longer shake for big damage/explosions
func sustained_shake(intensity: float = 0.3, duration: float = 0.8) -> void:
	_start_shake(intensity, duration, 1.5)

# Directional shake based on damage source
func directional_shake(direction: Vector3, intensity: float = 0.4, duration: float = 0.4) -> void:
	_start_shake(intensity, duration, 2.0, direction.normalized())

# Rapid shake for critical hits
func critical_shake(intensity: float = 0.8, duration: float = 0.2) -> void:
	_start_shake(intensity, duration, 5.0)

# Custom shake with full control
func custom_shake(intensity: float, duration: float, decay: float = 2.0, direction: Vector3 = Vector3.ZERO) -> void:
	_start_shake(intensity, duration, decay, direction)

func _start_shake(intensity: float, duration: float, decay: float, direction: Vector3 = Vector3.ZERO) -> void:
	if not camera:
		push_warning("CameraShake: No camera set!")
		return
	
	# Cancel any existing shake
	if shake_tween and shake_tween.is_valid():
		shake_tween.kill()
	
	current_shake_intensity = intensity
	current_shake_duration = duration
	current_shake_decay = decay
	is_shaking = true
	shake_noise_offset = 0.0
	
	shake_started.emit()
	
	# Apply shake over duration
	shake_tween = create_tween()
	shake_tween.set_parallel(false)
	
	var steps: int = int(duration * 60.0)  # 60 updates per second
	var step_duration: float = duration / float(steps)
	
	for i in range(steps):
		var progress: float = float(i) / float(steps)
		var current_intensity: float = intensity * (1.0 - pow(progress, decay))
		
		if direction != Vector3.ZERO:
			# Directional shake
			var shake_vec: Vector3 = direction * current_intensity
			shake_offset = shake_vec + _get_noise_offset(current_intensity * 0.3)
		else:
			# Omni-directional shake
			shake_offset = _get_noise_offset(current_intensity)
		
		_apply_shake_offset()
		shake_tween.tween_interval(step_duration)
	
	# Reset to zero
	shake_offset = Vector3.ZERO
	_apply_shake_offset()
	
	shake_tween.tween_callback(_on_shake_finished)

func _get_noise_offset(intensity: float) -> Vector3:
	shake_noise_offset += 0.1
	var x: float = noise.get_noise_2d(shake_noise_offset, 0.0) * intensity
	var y: float = noise.get_noise_2d(0.0, shake_noise_offset) * intensity
	var z: float = noise.get_noise_2d(shake_noise_offset, shake_noise_offset) * intensity * 0.5
	return Vector3(x, y, z)

func _apply_shake_offset() -> void:
	if camera:
		# Apply shake rotation relative to original rotation
		camera.rotation.x = original_rotation.x + shake_offset.y * 0.05  # Pitch shake
		camera.rotation.y = original_rotation.y + shake_offset.x * 0.05  # Yaw shake
		print("CameraShake: Applied rotation - rotation.x: ", camera.rotation.x, " rotation.y: ", camera.rotation.y)

func _on_shake_finished() -> void:
	is_shaking = false
	current_shake_intensity = 0.0
	# Restore original rotation
	if camera:
		camera.rotation = original_rotation
	shake_finished.emit()

func stop_shake() -> void:
	if shake_tween and shake_tween.is_valid():
		shake_tween.kill()
	shake_offset = Vector3.ZERO
	# Restore original rotation
	if camera:
		camera.rotation = original_rotation
	_apply_shake_offset()
	is_shaking = false
	shake_finished.emit()
