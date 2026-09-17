class_name TurnQueueCard
extends Control

@onready var background: TextureRect = $Background
@onready var portrait_background: TextureRect = $Background/PortraitBackground
@onready var name_label: Label = $Background/PortraitBackground/NameLabel

var is_player: bool = false
var is_current: bool = false

var normal_size: Vector2 = Vector2(60, 70)
var active_size: Vector2 = Vector2(80, 70)

func setup(battler: Battler, is_current_turn: bool = false) -> void:
	if not battler:
		return
	
	# Wait for scene to be ready if nodes aren't available yet
	if not name_label:
		await ready
	
	is_player = battler.is_in_group("players")
	is_current = is_current_turn
	
	# Set basic info
	if name_label:
		name_label.text = battler.character_name
	
	# Apply styling immediately
	apply_style()

func apply_style() -> void:
	# Update modulate based on active state (no more team colors)
	var target_modulate = Color.WHITE
	if not is_current:
		target_modulate = Color(0.7, 0.7, 0.7, 0.8) # Dimmed and slightly translucent
	
	# Update size and modulate based on active state
	var target_size = active_size if is_current else normal_size
	var target_scale = Vector2(1.2, 1.2) if is_current else Vector2.ONE
	
	# Set pivot to left center for scaling
	pivot_offset = Vector2(0, target_size.y / 2.0)
	
	var t := create_tween()
	t.parallel()
	t.tween_property(self, "custom_minimum_size", target_size, 0.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	t.tween_property(self, "scale", target_scale, 0.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	
	# Animate color components together to avoid rainbow effect
	# We use a separate color for RGB to avoid overwriting alpha if possible, 
	# but animating the whole 'modulate' is safer for color consistency.
	# To avoid fighting with juice, we can check current alpha.
	var current_alpha = modulate.a
	var final_color = Color(target_modulate.r, target_modulate.g, target_modulate.b, target_modulate.a)
	
	# If we are appearing (alpha is low), don't force alpha to 1.0/0.8 yet
	if current_alpha < 0.1:
		final_color.a = current_alpha
	
	t.tween_property(self, "modulate", final_color, 0.2).set_ease(Tween.EASE_OUT)
	
	# If we are in a wrapper, update its min size too so the VBoxContainer reacts
	var parent = get_parent()
	if parent is Control and not parent is VBoxContainer:
		t.tween_property(parent, "custom_minimum_size", target_size, 0.2).set_ease(Tween.EASE_OUT)

func set_current_turn(is_current_turn: bool) -> void:
	is_current = is_current_turn
	apply_style()

func set_portrait_texture(texture: Texture2D) -> void:
	if portrait_background:
		portrait_background.texture = texture
