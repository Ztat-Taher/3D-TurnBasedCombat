extends Node3D
class_name HitEffect
## Template scene for hit effects using Sprite3D
## Configured by HitEffectConfig resource

@onready var sprite: Sprite3D = $Sprite3D

var animation_timer: Timer
var current_frame: int = 0
var total_frames: int = 1

## Configure this hit effect from a HitEffectConfig resource
func configure(config: HitEffectConfig) -> void:
	if not config or not config.spritesheet_texture:
		push_error("HitEffect: Invalid config or missing texture")
		return
	
	# Configure the existing Sprite3D
	sprite.texture = config.spritesheet_texture
	sprite.hframes = config.hframes
	sprite.vframes = config.vframes
	sprite.modulate = config.color
	sprite.scale = config.scale
	
	# Apply randomization for variety
	_apply_randomization(config)
	
	# Start animation from frame 0
	sprite.frame = 0
	current_frame = 0
	total_frames = config.hframes * config.vframes
	
	# Animate using timer
	if total_frames > 1:
		animation_timer = Timer.new()
		animation_timer.wait_time = 1.0 / config.fps
		animation_timer.autostart = true
		animation_timer.timeout.connect(_on_animation_tick)
		add_child(animation_timer)
	
	# Schedule cleanup after duration
	if config.duration > 0:
		var cleanup_timer = Timer.new()
		cleanup_timer.wait_time = config.duration
		cleanup_timer.one_shot = true
		cleanup_timer.timeout.connect(queue_free)
		add_child(cleanup_timer)
		cleanup_timer.start()

## Apply random scale, rotation, and mirroring for visual variety
func _apply_randomization(config: HitEffectConfig) -> void:
	# Random scale
	if config.random_scale_max > config.random_scale_min:
		var random_scale = randf_range(config.random_scale_min, config.random_scale_max)
		sprite.scale *= random_scale
	
	# Random rotation
	if config.random_rotation_max > config.random_rotation_min:
		var random_rotation = randf_range(config.random_rotation_min, config.random_rotation_max)
		sprite.rotation_degrees.z = random_rotation
	
	# Random mirroring (flip horizontally)
	if config.random_mirror and randf() < 0.5:
		sprite.scale.x *= -1

func _on_animation_tick() -> void:
	if not is_instance_valid(sprite):
		if animation_timer:
			animation_timer.queue_free()
		return
	
	current_frame += 1
	if current_frame >= total_frames:
		# Animation complete
		if animation_timer:
			animation_timer.stop()
			animation_timer.queue_free()
	else:
		sprite.frame = current_frame
