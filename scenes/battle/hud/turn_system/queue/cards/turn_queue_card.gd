class_name TurnQueueCard
extends Control

@onready var name_label: Label = $MainVBox/NameLabel
@onready var portrait_background: TextureRect = $MainVBox/PortraitBackground
@onready var background_shader: ColorRect = $BackgroundShader

var is_player: bool = false
var is_current: bool = false

var normal_size: Vector2 = Vector2(60, 70)
var active_size: Vector2 = Vector2(80, 70)  # Only width increases, height stays same

var card_shader: Shader = null

func setup(battler: Battler, is_current_turn: bool = false) -> void:
	if not battler:
		return
	
	# Wait for scene to be ready if nodes aren't available yet
	if not name_label:
		await ready
	
	# Create unique shader material for this card to avoid sharing
	if background_shader:
		if not card_shader:
			card_shader = load("res://assets/shaders/ui_background_shader.gdshader")
		
		# Create a unique material instance
		var unique_material = ShaderMaterial.new()
		unique_material.shader = card_shader
		background_shader.material = unique_material
	
	is_player = battler.is_in_group("players")
	is_current = is_current_turn
	
	# Set basic info
	if name_label:
		name_label.text = battler.character_name
	
	# Apply styling immediately
	apply_style()

func apply_style() -> void:
	# Update background shader color based on team and active state
	if background_shader and background_shader.material:
		var shader_material = background_shader.material as ShaderMaterial
		if shader_material:
			var target_color: Color
			if is_current:
				if is_player:
					target_color = Color(0.2, 0.5, 0.8, 0.95)  # Bright blue for active ally
				else:
					target_color = Color(0.8, 0.2, 0.3, 0.95)  # Bright red for active enemy
			else:
				# Non-active cards show team color but grayed out and translucent
				if is_player:
					target_color = Color(0.15, 0.2, 0.3, 0.6)  # Grayed blue, translucent
				else:
					target_color = Color(0.3, 0.15, 0.2, 0.6)  # Grayed red, translucent
			
			# Set the shader parameter directly
			shader_material.set_shader_parameter("base_color", target_color)
	
	# Update size and modulate based on active state
	var target_size = active_size if is_current else normal_size
	var target_modulate = Color.WHITE if is_current else Color(0.8, 0.8, 0.8, 0.85)
	
	custom_minimum_size = target_size
	
	var t := create_tween()
	t.parallel()
	t.tween_property(self, "custom_minimum_size", target_size, 0.2).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "size", target_size, 0.2).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "modulate", target_modulate, 0.2).set_ease(Tween.EASE_OUT)

func set_current_turn(is_current_turn: bool) -> void:
	is_current = is_current_turn
	apply_style()

func set_portrait_texture(texture: Texture2D) -> void:
	if portrait_background:
		portrait_background.texture = texture
