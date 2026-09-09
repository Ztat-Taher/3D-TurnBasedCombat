class_name PartyStatusCard
extends Control

@onready var name_label: Label = $MainVBox/BarsContainer/NameLabel
@onready var active_tag: Label = $MainVBox/ActiveTag # unique_id=786705469
@onready var hp_bar: TextureProgressBar = $MainVBox/BarsContainer/HPContainer/HPBar
@onready var hp_damage_bar: TextureProgressBar = $MainVBox/BarsContainer/HPContainer/HPDamageBar
@onready var hp_num_label: Label = $MainVBox/BarsContainer/HPContainer/HPNumLabel # unique_id=540534169
@onready var ap_bar: TextureProgressBar = $MainVBox/BarsContainer/APContainer/APBar
@onready var ap_damage_bar: TextureProgressBar = $MainVBox/BarsContainer/APContainer/APDamageBar
@onready var ap_num_label: Label = $MainVBox/BarsContainer/APContainer/APNumLabel
@onready var level_label: Label = $MainVBox/PortraitContainer/Level/LevelLabel
@onready var portrait_background: TextureRect = $MainVBox/PortraitContainer/PortraitBackground
@onready var background_shader: ColorRect = $BackgroundShader

@onready var hp_juice: ProgressBarJuice = $MainVBox/BarsContainer/HPContainer/HPJuice
@onready var ap_juice: ProgressBarJuice = $MainVBox/BarsContainer/APContainer/APJuice

var is_active: bool = false
var card_shader: Shader = null

func setup(ally: Battler) -> void:
	if not ally:
		return
	
	# Ensure nodes are ready before accessing them
	if not name_label:
		await ready
	
	# Use the existing shader material from the scene if available
	if background_shader and background_shader.material:
		card_shader = background_shader.material.shader
	
	if name_label:
		name_label.text = ally.character_name
	
	# Setup juice components if they exist
	if hp_juice:
		hp_juice.setup(hp_bar, hp_damage_bar, hp_num_label)
		hp_juice.enable_healing_feedback = true
		hp_juice.enable_critical_health = true
	
	if ap_juice:
		ap_juice.setup(ap_bar, ap_damage_bar, ap_num_label)
		ap_juice.enable_healing_feedback = false
		ap_juice.enable_critical_health = false
	
	update_hp(ally.current_health, ally.max_health)
	update_ap(3, 3) # Default AP
	
	# Try to get level from ally, default to 3 if not available
	var level = 3
	if "level" in ally:
		level = ally.level
	elif ally.has_method("get_level"):
		level = ally.get_level()
	update_level(level)
	
	# Entrance animation
	modulate.a = 0.0
	scale = Vector2(0.7, 0.7)
	
	# Set pivot to bottom center for proper scaling
	pivot_offset = Vector2(size.x / 2, size.y)
	
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(self, "modulate:a", 1.0, 0.4).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "scale", Vector2(1.0, 1.0), 0.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	
	# Apply initial inactive state
	set_active(false)

func set_active(is_active_battler: bool) -> void:
	is_active = is_active_battler
	if active_tag:
		active_tag.visible = is_active
	
	# Update shader color and scale based on active state
	if background_shader and background_shader.material:
		var shader_material = background_shader.material as ShaderMaterial
		if shader_material:
			var target_color: Color
			var target_scale: Vector2
			var target_modulate: Color
			
			if is_active:
				# Active: brighter blue, larger scale from bottom center
				target_color = Color(0.15, 0.3, 0.5, 0.95)
				target_scale = Vector2(1.1, 1.1)
				target_modulate = Color.WHITE
			else:
				# Inactive: darker, smaller scale, slightly translucent
				target_color = Color(0.06, 0.09, 0.16, 0.85)
				target_scale = Vector2(1.0, 1.0)
				target_modulate = Color(0.8, 0.8, 0.8, 0.85)
			
			# Animate the transitions
			var tween = create_tween()
			tween.set_parallel(true)
			tween.tween_property(shader_material, "shader_parameter/base_color", target_color, 0.2).set_ease(Tween.EASE_OUT)
			tween.tween_property(self, "scale", target_scale, 0.2).set_ease(Tween.EASE_OUT)
			tween.tween_property(self, "modulate", target_modulate, 0.2).set_ease(Tween.EASE_OUT)

func update_hp(current_health: int, max_health: int) -> void:
	if hp_juice:
		hp_juice.update_value(float(current_health), float(max_health))
	elif hp_bar:
		hp_bar.max_value = max_health
		hp_bar.value = float(current_health)
		if hp_damage_bar:
			hp_damage_bar.max_value = max_health
			hp_damage_bar.value = float(current_health)
		if hp_num_label:
			hp_num_label.text = "%d/%d" % [current_health, max_health]

func update_ap(current_ap: int, max_ap: int) -> void:
	if ap_juice:
		ap_juice.update_value(float(current_ap), float(max_ap))
	elif ap_bar:
		ap_bar.max_value = max_ap
		ap_bar.value = float(current_ap)
		if ap_damage_bar:
			ap_damage_bar.max_value = max_ap
			ap_damage_bar.value = float(current_ap)
		if ap_num_label:
			ap_num_label.text = "%d/%d" % [current_ap, max_ap]

func update_level(level: int) -> void:
	if level_label:
		level_label.text = str(level)

func set_portrait_texture(texture: Texture2D) -> void:
	if portrait_background:
		portrait_background.texture = texture
