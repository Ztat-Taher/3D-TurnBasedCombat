class_name AttackIndicator3D
extends Node3D

enum AttackType { PARRIABLE_ONLY, DODGE_ONLY, JUMPABLE }

const COLOR_PARRIABLE = Color(1.0, 0.1, 0.1, 1.0)  # Red
const COLOR_DODGE = Color(1.0, 0.8, 0.0, 1.0)      # Gold
const COLOR_JUMPABLE = Color(0.0, 0.6, 1.0, 1.0)   # Blue

@onready var sprite_3d: Sprite3D = $Sprite3D

func _ready() -> void:
	visible = false

func show_indicator(type: AttackType) -> void:
	visible = true
	var mat := sprite_3d.material_override as ShaderMaterial
	
	if not mat:
		push_error("AttackIndicator3D: No ShaderMaterial found on Sprite3D")
		return
	
	match type:
		AttackType.PARRIABLE_ONLY:
			mat.set_shader_parameter("indicator_color", COLOR_PARRIABLE)
			mat.set_shader_parameter("indicator_type", 1)  # X
		AttackType.DODGE_ONLY:
			mat.set_shader_parameter("indicator_color", COLOR_DODGE)
			mat.set_shader_parameter("indicator_type", 0)  # Circle
		AttackType.JUMPABLE:
			mat.set_shader_parameter("indicator_color", COLOR_JUMPABLE)
			mat.set_shader_parameter("indicator_type", 2)  # Chevron
	
	# Pop-in animation using Tween
	scale = Vector3.ZERO
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", Vector3.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func hide_indicator() -> void:
	var tween = create_tween()
	tween.tween_property(self, "scale", Vector3.ZERO, 0.1).set_ease(Tween.EASE_IN)
	tween.tween_callback(func(): visible = false)
