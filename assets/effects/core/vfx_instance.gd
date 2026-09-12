@tool
extends Node3D
class_name VFXInstance
## Universal base engine for all visual effects in the project.
## Controls playback, emission, child particle emitters, shader tinting,
## animations, and delay handling with zero scene-specific script requirements.

signal finished
signal stopped

@export var autoplay: bool = false
@export var one_shot: bool = false

@export_range(0.0, 8.0, 0.01) var speed_scale: float = 1.0:
	set(v):
		speed_scale = v
		_update_speed_scale(v)

@export var emitting: bool = true:
	set(v):
		if emitting == v:
			return
		emitting = v
		if emitting:
			play()
		else:
			stop()

@export_tool_button("Play", "Play") var play_button = func(): 
	play()

@export_tool_button("Stop", "Stop") var stop_button = func(): 
	stop()

var _anim_player: AnimationPlayer

var anim: AnimationPlayer:
	get():
		if _anim_player and is_instance_valid(_anim_player):
			return _anim_player
		if has_node("AnimationPlayer"):
			_anim_player = get_node("AnimationPlayer") as AnimationPlayer
			return _anim_player
		return null

var particles: Array[GPUParticles3D]:
	get():
		var result: Array[GPUParticles3D] = []
		_collect_particles(self, result)
		return result

var materials: Array[ShaderMaterial]:
	get():
		var result: Array[ShaderMaterial] = []
		_collect_materials(self, result)
		return result

func _ready() -> void:
	if autoplay:
		play()
	elif not emitting and not Engine.is_editor_hint():
		_stop_particles()

func _enter_tree() -> void:
	if autoplay and Engine.is_editor_hint():
		play()

## Primary method to activate / trigger the VFX
func play() -> void:
	emitting = true
	_start_particles()
	
	if anim:
		if anim.has_animation("open"):
			anim.play("open")
		elif anim.has_animation("main"):
			anim.play("main")
			anim.seek(0.0)
			await anim.animation_finished
			finished.emit()
			if not one_shot and emitting:
				anim.advance(0.0)
				play()

## Primary method to stop / fade out the VFX
func stop() -> void:
	emitting = false
	_stop_particles()
	
	if anim:
		if anim.has_animation("close"):
			anim.play("close")
		elif anim.has_animation("stop"):
			anim.play("stop")
		else:
			anim.stop()
	stopped.emit()

## Backwards-compatibility aliases
func start(node: GPUParticles3D = null) -> void:
	if node:
		node.restart()
		node.emitting = true
	else:
		play()

func open() -> void:
	play()

func close() -> void:
	stop()

## Standardized color modulation for all VFX shaders & particle systems
func set_vfx_color(color: Color) -> void:
	_set_shader_param("primary_color", color)
	_set_shader_param("initial_color", color)
	_set_shader_param("u_m2_rgb", color)
	_set_shader_param("u_m1_rgb", color)

func _update_speed_scale(v: float) -> void:
	if anim:
		anim.speed_scale = v
	for p in particles:
		p.speed_scale = v
	_set_shader_param("speed_scale", v)

func _start_particles() -> void:
	for p in particles:
		if p.has_meta("delay") and not Engine.is_editor_hint():
			var delay_time: float = float(p.get_meta("delay"))
			get_tree().create_timer(delay_time).timeout.connect(func():
				if is_instance_valid(p) and emitting:
					p.emitting = true
					p.restart()
			)
		else:
			p.emitting = true
			p.restart()

func _stop_particles() -> void:
	for p in particles:
		p.emitting = false

func _collect_particles(node: Node, result: Array[GPUParticles3D]) -> void:
	for c in node.get_children():
		if c is GPUParticles3D:
			result.append(c)
		_collect_particles(c, result)

func _collect_materials(node: Node, result: Array[ShaderMaterial]) -> void:
	for c in node.get_children():
		if c is GPUParticles3D or c is MeshInstance3D:
			if c.material_override is ShaderMaterial:
				result.append(c.material_override)
		_collect_materials(c, result)

func _set_shader_param(key: String, value: Variant) -> void:
	for m in materials:
		m.set_shader_parameter(key, value)
