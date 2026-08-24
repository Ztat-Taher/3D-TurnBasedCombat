class_name TurnQueueCard
extends Control

@onready var name_label: Label = $MainVBox/NameLabel
@onready var portrait_background: TextureRect = $MainVBox/PortraitBackground
@onready var background_shader: ColorRect = $BackgroundShader

var is_player: bool = false
var is_current: bool = false

var normal_size: Vector2 = Vector2(60, 70)
var active_size: Vector2 = Vector2(80, 90)

var card_shader: Shader = null

func setup(battler: Battler, is_current_turn: bool = false) -> void:
	print("TurnQueueCard setup() called - battler: ", battler.character_name if battler else "null", " is_current_turn: ", is_current_turn)
	
	if not battler:
		print("ERROR: battler is null!")
		return
	
	# Wait for scene to be ready if nodes aren't available yet
	if not name_label:
		print("Waiting for ready...")
		await ready
		print("Ready completed")
	
	print("name_label: ", name_label)
	print("background_shader: ", background_shader)
	
	# Create unique shader material for this card
	if background_shader:
		if not card_shader:
			card_shader = load("res://assets/shaders/ui_background_shader.gdshader")
		var unique_material = ShaderMaterial.new()
		unique_material.shader = card_shader
		background_shader.material = unique_material
		print("Created unique shader material for card")
	
	is_player = battler.is_in_group("players")
	is_current = is_current_turn
	
	print("is_player: ", is_player, " is_current: ", is_current)
	
	# Set basic info
	if name_label:
		name_label.text = battler.character_name
		print("Set name_label text to: ", battler.character_name)
	else:
		print("ERROR: name_label is null!")
	
	# Apply styling
	print("Calling apply_style...")
	apply_style()

func apply_style() -> void:
	print("TurnQueueCard apply_style() called - is_player: ", is_player, " is_current: ", is_current)
	
	# Update background shader color based on team and active state
	if background_shader:
		print("background_shader exists: ", background_shader)
		if background_shader.material:
			print("background_shader.material exists: ", background_shader.material)
			var target_color: Color
			if is_current:
				if is_player:
					target_color = Color(0.2, 0.4, 0.8, 0.95)  # Bright blue for active ally
					print("Setting active ally color: blue")
				else:
					target_color = Color(0.8, 0.2, 0.3, 0.95)  # Bright red for active enemy
					print("Setting active enemy color: red")
			else:
				target_color = Color(0.3, 0.3, 0.35, 0.85)  # Gray for inactive
				print("Setting inactive color: gray")
			
			# Set the shader uniform
			background_shader.material.set_shader_parameter("base_color", target_color)
			print("Shader parameter set to: ", target_color)
		else:
			print("ERROR: background_shader.material is null!")
	else:
		print("ERROR: background_shader is null!")
	
	# Update size based on active state
	if is_current:
		custom_minimum_size = active_size
		var t := create_tween()
		t.tween_property(self, "custom_minimum_size", active_size, 0.2).set_ease(Tween.EASE_OUT)
		print("Setting active size: ", active_size)
	else:
		custom_minimum_size = normal_size
		var t := create_tween()
		t.tween_property(self, "custom_minimum_size", normal_size, 0.2).set_ease(Tween.EASE_OUT)
		print("Setting normal size: ", normal_size)

func set_current_turn(is_current_turn: bool) -> void:
	is_current = is_current_turn
	apply_style()

func set_portrait_texture(texture: Texture2D) -> void:
	if portrait_background:
		portrait_background.texture = texture