class_name PartyStatusCard
extends Control

@onready var name_label: Label = $MainVBox/BarsContainer/NameLabel
@onready var active_tag: Label = $MainVBox/ActiveTag # unique_id=786705469
@onready var hp_bar: TextureProgressBar = $MainVBox/BarsContainer/HPContainer/HPBar
@onready var hp_damage_bar: TextureProgressBar = $MainVBox/BarsContainer/HPContainer/HPDamageBar
@onready var hp_num_label: Label = $MainVBox/BarsContainer/HPContainer/HPNumLabel # unique_id=540534169
@onready var ap_bar: TextureProgressBar = $MainVBox/BarsContainer/APContainer/HPBar
@onready var ap_damage_bar: TextureProgressBar = $MainVBox/BarsContainer/APContainer/APDamageBar
@onready var ap_num_label: Label = $MainVBox/BarsContainer/APContainer/APNumLabel
@onready var level_label: Label = $MainVBox/PortraitContainer/Level/LevelLabel
@onready var portrait_background: TextureRect = $MainVBox/PortraitContainer/PortraitBackground
@onready var background_shader: ColorRect = $BackgroundShader
@onready var card_focus: NinePatchRect = $CardFocus # unique_id=686705471

var is_active: bool = false
var is_hovered: bool = false
var card_shader: Shader = null

func setup(ally: Battler) -> void:
	if not ally:
		return
	
	# Ensure nodes are ready before accessing them
	if not name_label:
		await ready
	
	# Create unique shader material for this card
	if background_shader:
		if not card_shader:
			card_shader = load("res://assets/shaders/ui_background_shader.gdshader")
		var unique_material = ShaderMaterial.new()
		unique_material.shader = card_shader
		background_shader.material = unique_material
	
	if name_label:
		name_label.text = ally.character_name
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
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(self, "modulate:a", 1.0, 0.4).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "scale", Vector2(1.0, 1.0), 0.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	
	apply_style()

func set_active(is_active_battler: bool) -> void:
	is_active = is_active_battler
	if active_tag:
		active_tag.visible = is_active
	
	# Active transition juice
	if is_active_battler:
		# Scale up
		var scale_tween := create_tween()
		scale_tween.tween_property(self, "scale", Vector2(1.05, 1.05), 0.15).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		scale_tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.2).set_ease(Tween.EASE_IN)
		
		# Glow effect
		var glow_tween := create_tween()
		glow_tween.tween_property(self, "modulate", Color(1.2, 1.3, 1.5, 1.0), 0.1)
		glow_tween.tween_property(self, "modulate", Color.WHITE, 0.15)
	else:
		# Subtle shrink
		var scale_tween := create_tween()
		scale_tween.tween_property(self, "scale", Vector2(0.95, 0.95), 0.1).set_ease(Tween.EASE_OUT)
		scale_tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.15).set_ease(Tween.EASE_IN)
	
	apply_style()

func update_hp(current_health: int, max_health: int) -> void:
	if hp_bar:
		var previous_value = hp_bar.value
		hp_bar.max_value = max_health
		
		# Dual-layer effect: main bar instantly updates, damage bar smoothly catches up
		hp_bar.value = float(current_health)
		
		if hp_damage_bar:
			hp_damage_bar.max_value = max_health
			var damage_tween := create_tween()
			damage_tween.tween_property(hp_damage_bar, "value", float(current_health), 0.6).set_ease(Tween.EASE_OUT)
		
		# Damage feedback
		if float(current_health) < previous_value:
			# Red flash
			var flash := create_tween()
			flash.tween_property(hp_bar, "modulate", Color(2.0, 0.2, 0.2, 1.0), 0.06)
			flash.tween_property(hp_bar, "modulate", Color.WHITE, 0.18)
			
			# Scale pulse
			var scale_tween := create_tween()
			scale_tween.tween_property(hp_bar, "scale", Vector2(1.08, 1.15), 0.1).set_ease(Tween.EASE_OUT)
			scale_tween.tween_property(hp_bar, "scale", Vector2(1.0, 1.0), 0.15).set_ease(Tween.EASE_IN)
			
			# Text shake and pop
			if hp_num_label:
				var original_pos = hp_num_label.position
				var shake_tween := create_tween()
				shake_tween.tween_property(hp_num_label, "position:x", original_pos.x + 3.0, 0.05)
				shake_tween.tween_property(hp_num_label, "position:x", original_pos.x - 3.0, 0.05)
				shake_tween.tween_property(hp_num_label, "position:x", original_pos.x, 0.05)
				
				var pop_tween := create_tween()
				pop_tween.tween_property(hp_num_label, "scale", Vector2(1.3, 1.3), 0.08).set_ease(Tween.EASE_OUT)
				pop_tween.tween_property(hp_num_label, "scale", Vector2(1.0, 1.0), 0.12).set_ease(Tween.EASE_IN)
	
	if hp_num_label:
		hp_num_label.text = "%d/%d" % [current_health, max_health]

func update_ap(current_ap: int, max_ap: int) -> void:
	if ap_bar:
		var previous_value = ap_bar.value
		ap_bar.max_value = max_ap
		
		# Dual-layer effect: main bar instantly updates, damage bar smoothly catches up
		ap_bar.value = float(current_ap)
		
		if ap_damage_bar:
			ap_damage_bar.max_value = max_ap
			var damage_tween := create_tween()
			damage_tween.tween_property(ap_damage_bar, "value", float(current_ap), 0.5).set_ease(Tween.EASE_OUT)
		
		# Blue flash when AP changes
		if float(current_ap) != previous_value:
			var flash := create_tween()
			flash.tween_property(ap_bar, "modulate", Color(0.5, 1.5, 2.0, 1.0), 0.08)
			flash.tween_property(ap_bar, "modulate", Color.WHITE, 0.15)
			
			# AP number pop
			if ap_num_label:
				var pop_tween := create_tween()
				pop_tween.tween_property(ap_num_label, "scale", Vector2(1.25, 1.25), 0.1).set_ease(Tween.EASE_OUT)
				pop_tween.tween_property(ap_num_label, "scale", Vector2(1.0, 1.0), 0.15).set_ease(Tween.EASE_IN)
	
	if ap_num_label:
		ap_num_label.text = "%d/%d" % [current_ap, max_ap]

func update_level(level: int) -> void:
	if level_label:
		level_label.text = str(level)

func set_portrait_texture(texture: Texture2D) -> void:
	if portrait_background:
		portrait_background.texture = texture

func apply_style() -> void:
	# The root node is now a Control, not PanelContainer, so we style the BackgroundShader ColorRect instead
	# The animated shader background is handled by the BackgroundShader ColorRect in the scene
	
	# Update background shader color based on active state
	if background_shader:
		if is_active:
			background_shader.color = Color(0.1, 0.18, 0.32, 0.95)
		else:
			background_shader.color = Color(0.06, 0.09, 0.16, 0.85)
	
	# Apply HP bar styling (using texture progress bars now)
	apply_hp_bar_style()
	
	# Apply AP bar styling (using texture progress bars now)
	apply_ap_bar_style()

func apply_hp_bar_style() -> void:
	# HP bar uses texture progress bars, so minimal styling needed
	# The textures are already set in the scene file
	if hp_bar:
		var hp_bg = StyleBoxFlat.new()
		hp_bg.bg_color = Color(0.18, 0.08, 0.08, 0.8)
		hp_bg.corner_radius_top_left = 2
		hp_bg.corner_radius_top_right = 2
		hp_bg.corner_radius_bottom_right = 2
		hp_bg.corner_radius_bottom_left = 2
		hp_bar.add_theme_stylebox_override("background", hp_bg)

func apply_ap_bar_style() -> void:
	# AP bar uses texture progress bars, so minimal styling needed
	# The textures are already set in the scene file
	if ap_bar:
		var ap_bg = StyleBoxFlat.new()
		ap_bg.bg_color = Color(0.08, 0.12, 0.22, 0.8)
		ap_bg.corner_radius_top_left = 2
		ap_bg.corner_radius_top_right = 2
		ap_bg.corner_radius_bottom_right = 2
		ap_bg.corner_radius_bottom_left = 2
		ap_bar.add_theme_stylebox_override("background", ap_bg)

func _on_mouse_entered() -> void:
	is_hovered = true
	var hover_tween := create_tween()
	hover_tween.tween_property(self, "scale", Vector2(1.03, 1.03), 0.15).set_ease(Tween.EASE_OUT)
	if card_focus:
		card_focus.visible = true
		var focus_tween := create_tween()
		focus_tween.tween_property(card_focus, "modulate:a", 1.0, 0.1)

func _on_mouse_exited() -> void:
	is_hovered = false
	if not is_active:
		var hover_tween := create_tween()
		hover_tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.15).set_ease(Tween.EASE_OUT)
		if card_focus:
			var focus_tween := create_tween()
			focus_tween.tween_property(card_focus, "modulate:a", 0.0, 0.1)
			focus_tween.tween_callback(func(): card_focus.visible = false)
