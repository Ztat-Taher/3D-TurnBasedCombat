class_name VFXConfig
extends Resource
## Visual effect configuration for modular card VFX
## Controls how visual effects are spawned and behave

enum VFXSpawnPoint {
	ACTOR,              # Spawn at actor position
	TARGET,             # Spawn at target position
	PROJECTILE,         # Spawn on projectile
	GROUND,             # Spawn at ground level
	AIR,                # Spawn in air above target
	CUSTOM              # Custom spawn point
}

@export var vfx_scene: String = ""                   ## Path to VFX scene
@export var vfx_spawn_point: VFXSpawnPoint = VFXSpawnPoint.TARGET
@export var vfx_duration: float = 1.0                ## How long the VFX plays
@export var vfx_scale: Vector3 = Vector3(1, 1, 1)   ## Scale of the VFX
@export var vfx_color: Color = Color(1, 1, 1, 1)    ## Color modulation
@export var attach_to_target: bool = false           ## Whether VFX follows target
@export var offset: Vector3 = Vector3.ZERO           ## Offset from spawn point
@export var rotation: Vector3 = Vector3.ZERO         ## Rotation offset
@export var random_offset_range: float = 0.0         ## Random position variation
@export var random_rotation_range: float = 0.0       ## Random rotation variation
@export var fade_in_duration: float = 0.1            ## Fade in time
@export var fade_out_duration: float = 0.2           ## Fade out time
@export var loop: bool = false                      ## Whether VFX should loop
@export var emission_rate: float = 1.0               ## Emission rate for particle systems
@export var burst: bool = false                      ## Whether to burst particles immediately

## Spawn the VFX at the specified location
func spawn_vfx(spawn_position: Vector3, target_node: Node = null) -> Node:
	if vfx_scene.is_empty():
		push_warning("VFXConfig: No scene specified for VFX")
		return null
	
	var vfx_scene_path = vfx_scene
	if not ResourceLoader.exists(vfx_scene_path):
		push_warning("VFXConfig: Scene does not exist: %s" % vfx_scene_path)
		return null
	
	var vfx_scene_resource = load(vfx_scene_path)
	if not vfx_scene_resource:
		push_warning("VFXConfig: Failed to load scene: %s" % vfx_scene_path)
		return null
	
	var vfx_instance = vfx_scene_resource.instantiate()
	if not vfx_instance:
		push_warning("VFXConfig: Failed to instantiate VFX scene")
		return null
	
	# Apply configuration
	_apply_vfx_configuration(vfx_instance, spawn_position, target_node)
	
	return vfx_instance

## Apply configuration to VFX instance
func _apply_vfx_configuration(vfx_instance: Node, spawn_position: Vector3, target_node: Node):
	# Set position with offset and random variation
	var final_position = spawn_position + offset
	if random_offset_range > 0:
		final_position += Vector3(
			randf_range(-random_offset_range, random_offset_range),
			randf_range(-random_offset_range, random_offset_range),
			randf_range(-random_offset_range, random_offset_range)
		)
	
	vfx_instance.global_position = final_position
	
	# Apply rotation
	vfx_instance.rotation_degrees = rotation
	if random_rotation_range > 0:
		vfx_instance.rotation_degrees += Vector3(
			randf_range(-random_rotation_range, random_rotation_range),
			randf_range(-random_rotation_range, random_rotation_range),
			randf_range(-random_rotation_range, random_rotation_range)
		)
	
	# Apply scale
	if vfx_instance.has_method("set_scale"):
		vfx_instance.set_scale(vfx_scale)
	elif vfx_instance is Node3D:
		vfx_instance.scale = vfx_scale
	
	# Apply color modulation
	if vfx_instance.has_method("set_modulate"):
		vfx_instance.set_modulate(vfx_color)
	elif vfx_instance is MeshInstance3D:
		if vfx_instance.get_surface_override_material(0):
			vfx_instance.get_surface_override_material(0).albedo_color = vfx_color
	
	# Attach to target if configured
	if attach_to_target and target_node:
		target_node.add_child(vfx_instance)
		vfx_instance.global_position = final_position # Reset position after reparenting
	
	# Handle particle systems
	if vfx_instance.has_method("set_emitting"):
		vfx_instance.set_emitting(true)
	
	if vfx_instance is GPUParticles3D:
		vfx_instance.emitting = true
		if emission_rate > 0:
			vfx_instance.amount = int(emission_rate)
		if burst:
			vfx_instance.restart()
	
	# Handle duration (auto-destroy)
	if vfx_duration > 0 and not loop:
		_schedule_vfx_destruction(vfx_instance, vfx_duration)

## Schedule VFX destruction after duration
func _schedule_vfx_destruction(vfx_instance: Node, duration: float):
	var timer = Timer.new()
	timer.wait_time = duration
	timer.one_shot = true
	timer.timeout.connect(func():
		if is_instance_valid(vfx_instance):
			if fade_out_duration > 0:
				_fade_out_vfx(vfx_instance)
			else:
				vfx_instance.queue_free()
	)
	vfx_instance.add_child(timer)
	timer.start()

## Fade out VFX before destruction
func _fade_out_vfx(vfx_instance: Node):
	var tween = vfx_instance.create_tween()
	tween.tween_property(vfx_instance, "modulate:a", 0.0, fade_out_duration)
	tween.tween_callback(func():
		if is_instance_valid(vfx_instance):
			vfx_instance.queue_free()
	)

## Get spawn position based on configuration
func get_spawn_position(actor: Node, target: Node, projectile: Node = null) -> Vector3:
	match vfx_spawn_point:
		VFXSpawnPoint.ACTOR:
			return actor.global_position if actor else Vector3.ZERO
		VFXSpawnPoint.TARGET:
			return target.global_position if target else Vector3.ZERO
		VFXSpawnPoint.PROJECTILE:
			return projectile.global_position if projectile else Vector3.ZERO
		VFXSpawnPoint.GROUND:
			var base_pos = target.global_position if target else Vector3.ZERO
			return Vector3(base_pos.x, 0, base_pos.z)
		VFXSpawnPoint.AIR:
			var base_pos = target.global_position if target else Vector3.ZERO
			return Vector3(base_pos.x, base_pos.y + 2.0, base_pos.z)
		VFXSpawnPoint.CUSTOM:
			# Would need custom implementation
			return target.global_position if target else Vector3.ZERO
		_:
			return Vector3.ZERO

## Validate configuration
func validate() -> Array[String]:
	var issues: Array[String] = []
	
	if vfx_scene.is_empty():
		issues.append("No VFX scene specified")
	
	if vfx_duration <= 0 and not loop:
		issues.append("Invalid VFX duration (must be > 0 or loop enabled)")
	
	return issues

## Create a simple VFX config for common effects
static func create_simple_fire_vfx() -> VFXConfig:
	var config = VFXConfig.new()
	config.vfx_scene = "res://vfx/fire_explosion.tres"
	config.vfx_spawn_point = VFXSpawnPoint.TARGET
	config.vfx_duration = 1.5
	config.vfx_scale = Vector3(1, 1, 1)
	config.vfx_color = Color(1, 0.5, 0, 1)
	config.attach_to_target = false
	config.fade_in_duration = 0.1
	config.fade_out_duration = 0.3
	config.burst = true
	return config

static func create_simple_heal_vfx() -> VFXConfig:
	var config = VFXConfig.new()
	config.vfx_scene = "res://vfx/healing_aura.tres"
	config.vfx_spawn_point = VFXSpawnPoint.TARGET
	config.vfx_duration = 2.0
	config.vfx_scale = Vector3(1, 1, 1)
	config.vfx_color = Color(0, 1, 0.5, 1)
	config.attach_to_target = true
	config.fade_in_duration = 0.2
	config.fade_out_duration = 0.5
	config.loop = true
	return config
