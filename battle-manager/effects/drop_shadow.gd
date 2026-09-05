extends TextureRect
class_name DropShadow
## Reusable drop-shadow component for 2D UI elements.
##
## Attach this to a TextureRect placed as a CHILD of the element to shadow:
##   - it draws BEHIND its parent (z_index = -1), so it never covers the element.
##   - being a child, it inherits the parent's transforms & fade automatically
##     (hover scale, press bounce, ContainerJuice slide/fade, drag, fan layout...).
##   - for TextureButton parents the shadow texture and stretch mode are copied
##     from the button automatically.
##
## The linked shader (res://assets/shaders/drop_shadow.gdshader) is a reworked
## version of the "Simple Shadow Shader for 2D Sprites" from GodotShaders:
## straight-edge shadows have been given a blur pass and an animatable
## shadow_strength so shadows can appear/disappear (see set_strength()).

@export var shadow_offset: Vector2 = Vector2(0.0, 4.0)
@export var shadow_color: Color = Color(0, 0, 0, 0.4)
@export var shadow_strength: float = 1.0
@export var blur_amount: float = 1.5
## Keep the offset screen-aligned (straight down) even when the node rotates.
@export var disable_rotating: bool = false

const drop_shadow_shader := preload("res://assets/shaders/drop_shadow.gdshader")

var shadow_material: ShaderMaterial
var _strength_tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	z_index = -1
	_mirror_button_texture()
	_apply_material()

## If the parent is a TextureButton, mirror its icon so the shadow matches.
func _mirror_button_texture() -> void:
	var parent := get_parent()
	if parent is TextureButton:
		var button := parent as TextureButton

		if texture == null:
			texture = button.texture_normal

		match button.stretch_mode:
			TextureButton.STRETCH_SCALE:
				stretch_mode = TextureRect.STRETCH_SCALE
			TextureButton.STRETCH_TILE:
				stretch_mode = TextureRect.STRETCH_TILE
			TextureButton.STRETCH_KEEP:
				stretch_mode = TextureRect.STRETCH_KEEP
			TextureButton.STRETCH_KEEP_CENTERED:
				stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
			TextureButton.STRETCH_KEEP_ASPECT:
				stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
			TextureButton.STRETCH_KEEP_ASPECT_CENTERED:
				stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			TextureButton.STRETCH_KEEP_ASPECT_COVERED:
				stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED

func _apply_material() -> void:
	shadow_material = ShaderMaterial.new()
	shadow_material.shader = drop_shadow_shader
	shadow_material.set_shader_parameter("shadow_offset", shadow_offset)
	shadow_material.set_shader_parameter("shadow_color", shadow_color)
	shadow_material.set_shader_parameter("shadow_strength", shadow_strength)
	shadow_material.set_shader_parameter("blur_amount", blur_amount)
	shadow_material.set_shader_parameter("disable_rotating", disable_rotating)
	material = shadow_material


## Fade the shadow in/out. Pass duration <= 0 for an instant change.
func set_strength(new_strength: float, duration: float = 0.0) -> void:
	if _strength_tween and _strength_tween.is_valid():
		_strength_tween.kill()
	shadow_strength = new_strength
	if shadow_material == null:
		await ready
	if shadow_material == null:
		return
	if duration <= 0.0:
		shadow_material.set_shader_parameter("shadow_strength", new_strength)
		return
	_strength_tween = create_tween()
	_strength_tween.tween_method(
		func(v: float) -> void:
			if shadow_material:
				shadow_material.set_shader_parameter("shadow_strength", v),
			shadow_material.get_shader_parameter("shadow_strength") if shadow_material else 0.0,
			new_strength,
			duration
	)
