extends Control
class_name CardButton
## Button representing a card in the player's hand with Balatro-style shader effect

signal card_played(card: CardData)
signal card_drag_started(card_button: CardButton)
signal card_drag_ended(card_button: CardButton, dropped_in_play_zone: bool)

var card_data: CardData
var is_hovered: bool = false
var is_selected: bool = false
var is_dragging: bool = false
var is_returning: bool = false
var is_out_of_hand: bool = false
## Set to true while the draw-from-pile fly-in animation is playing.
## Prevents _process from snapping card_3d_container back to resting position.
var is_draw_animating: bool = false

var base_position: Vector2 = Vector2.ZERO
var base_rotation: float = 0.0
var base_y_offset: float = 0.0
var base_z_index: int = 0

var drag_offset: Vector2 = Vector2.ZERO
var last_mouse_pos: Vector2 = Vector2.ZERO
var drag_velocity: Vector2 = Vector2.ZERO

var hand_bounds_provider: Callable = Callable()
var _original_parent: Node = null
var _original_index: int = -1
var _card_type_color: Color = Color.WHITE

var card_3d_container: SubViewportContainer
var card_viewport: SubViewport
var card_content: Control
var card_frame: TextureRect
var card_background: TextureRect
var name_banner: NinePatchRect
var card_name: Label
var cost_badge: TextureRect
var ap_cost: Label
var main_image: TextureRect
var type_icon: TextureRect
var stats_area: HBoxContainer
var attack_icon: TextureRect
var effect_icon: TextureRect

var description_popup: Control = null
var description_popup_scene: PackedScene = null
var hover_timer: float = 0.0
const HOVER_THRESHOLD: float = 0.5  # Seconds before showing description

var hover_tween: Tween
var return_tween: Tween
var card_shader_material: ShaderMaterial

# Pseudo 3D effect parameters
@export var fov: float = 90.0
@export var cull_back: bool = true
@export var max_tilt: float = 9.0
@export var tilt_sensitivity: float = 0.5
@export var tilt_inertia: float = 0.85

var current_y_rot: float = 0.0
var current_x_rot: float = 0.0

# Default textures from scene for fallback when card data doesn't provide assets
var _default_card_frame_texture: Texture2D
var _default_card_background_texture: Texture2D
var _default_name_banner_texture: Texture2D
var _default_cost_badge_texture: Texture2D
var _default_main_image_texture: Texture2D
var _default_type_icon_texture: Texture2D
var _default_attack_icon_texture: Texture2D
var _default_effect_icon_texture: Texture2D

func setup(card: CardData) -> void:
	card_data = card
	
	# Defer setup if nodes aren't ready yet
	if not card_name or not ap_cost:
		call_deferred("setup", card)
		return
	
	# Store default textures from scene for fallback
	_default_card_frame_texture = card_frame.texture if card_frame else null
	_default_card_background_texture = card_background.texture if card_background else null
	_default_name_banner_texture = name_banner.texture if name_banner else null
	_default_cost_badge_texture = cost_badge.texture if cost_badge else null
	_default_main_image_texture = main_image.texture if main_image else null
	_default_type_icon_texture = type_icon.texture if type_icon else null
	_default_attack_icon_texture = attack_icon.texture if attack_icon else null
	_default_effect_icon_texture = effect_icon.texture if effect_icon else null
	
	# Set modular card components (use fallback if card data doesn't provide texture)
	if card_name:
		card_name.text = card.name
	
	if ap_cost:
		ap_cost.text = str(card.cost)
	
	if card_frame:
		card_frame.texture = card.card_frame_texture if card.card_frame_texture else _default_card_frame_texture
	
	if card_background:
		# Set background sprite from card data, type-based fallback, or scene default
		if card.background_sprite:
			card_background.texture = card.background_sprite
		else:
			_set_type_based_background()
			if not card_background.texture:
				card_background.texture = _default_card_background_texture
	
	if name_banner:
		name_banner.texture = card.name_banner_texture if card.name_banner_texture else _default_name_banner_texture
	
	if cost_badge:
		cost_badge.texture = card.cost_badge_texture if card.cost_badge_texture else _default_cost_badge_texture
	
	if main_image:
		main_image.texture = card.main_image if card.main_image else _default_main_image_texture
	
	if type_icon:
		type_icon.texture = card.type_icon if card.type_icon else _default_type_icon_texture
	
	if attack_icon:
		attack_icon.texture = card.attack_icon if card.attack_icon else _default_attack_icon_texture
	
	if effect_icon:
		effect_icon.texture = card.effect_icon if card.effect_icon else _default_effect_icon_texture
	
	# Set up description popup if description exists
	if card.description and not card.description.is_empty():
		_setup_description_popup()

func set_fan_parameters(rot_deg: float, y_offset: float, z_idx: int) -> void:
	base_rotation = rot_deg
	base_y_offset = y_offset
	base_z_index = z_idx
	if not is_dragging and not is_returning:
		z_index = z_idx
		# Update popup z-index to match
		if description_popup:
			description_popup.z_index = z_index + 1
	
	if not is_hovered and not is_dragging:
		if card_3d_container:
			card_3d_container.rotation_degrees = base_rotation
			card_3d_container.position = Vector2(0.0, base_y_offset)

func _ready():
	pivot_offset = Vector2(60, 90)
	
	# Initialize node references
	card_3d_container = get_node_or_null("Card3DContainer")
	card_viewport = get_node_or_null("Card3DContainer/CardViewport")
	card_content = get_node_or_null("Card3DContainer/CardViewport/CardContent")
	card_frame = get_node_or_null("Card3DContainer/CardViewport/CardContent/CardFrame")
	card_background = get_node_or_null("Card3DContainer/CardViewport/CardContent/CardBackground")
	name_banner = get_node_or_null("Card3DContainer/CardViewport/CardContent/NameBanner")
	card_name = get_node_or_null("Card3DContainer/CardViewport/CardContent/NameBanner/CardName")
	cost_badge = get_node_or_null("Card3DContainer/CardViewport/CardContent/CostBadge")
	ap_cost = get_node_or_null("Card3DContainer/CardViewport/CardContent/CostBadge/APCost")
	main_image = get_node_or_null("Card3DContainer/CardViewport/CardContent/MainImage")
	type_icon = get_node_or_null("Card3DContainer/CardViewport/CardContent/TypeIcon")
	stats_area = get_node_or_null("Card3DContainer/CardViewport/CardContent/StatsArea")
	attack_icon = get_node_or_null("Card3DContainer/CardViewport/CardContent/StatsArea/AttackIcon")
	effect_icon = get_node_or_null("Card3DContainer/CardViewport/CardContent/StatsArea/EffectIcon")
	
	if card_3d_container:
		card_3d_container.pivot_offset = Vector2(60, 90)
	
	# Hit-detection rework: the root Control is IGNORE so its resting
	# fan-slot rect can never act as a stale detection area, and the visual
	# Card3DContainer (STOP) becomes the click/hit surface. Because the container is
	# what gets raised/rotated/scaled when highlighted, hit detection
	# naturally follows the highlighted card form.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if card_3d_container:
		card_3d_container.mouse_filter = Control.MOUSE_FILTER_STOP
		if not card_3d_container.gui_input.is_connected(_on_gui_input):
			card_3d_container.gui_input.connect(_on_gui_input)

	# Load description popup scene
	var popup_path = "res://battle-manager/card_combat/card_description_popup.tscn"
	if ResourceLoader.exists(popup_path):
		description_popup_scene = load(popup_path)

	_setup_shader()
	_pop_in()

func _setup_shader():
	# Set up the pseudo 3D shader material - MUST be unique per card to avoid shared state
	var shader = load("res://battle-manager/card_combat/card_pseudo_3d.gdshader")
	if shader and is_instance_valid(card_3d_container):
		# Create a NEW ShaderMaterial instance for each card to avoid shared state
		card_shader_material = ShaderMaterial.new()
		card_shader_material.shader = shader
		card_shader_material.set_shader_parameter("fov", fov)
		card_shader_material.set_shader_parameter("cull_back", cull_back)
		card_shader_material.set_shader_parameter("y_rot", 0.0)
		card_shader_material.set_shader_parameter("x_rot", 0.0)
		card_shader_material.set_shader_parameter("inset", 0.0)
		card_3d_container.material = card_shader_material
		print("Shader material set up for card: ", card_data.name if card_data else "unknown")
	else:
		print("Failed to set up shader - shader or card_3d_container invalid")



func _set_type_based_background():
	## Set background based on card type when no specific background is provided
	if not card_data or not card_background:
		return
	
	var card_type = card_data.card_type.to_lower()
	var type_background_path = ""
	
	# Map card types to background sprite paths
	match card_type:
		"attack":
			type_background_path = "res://assets/cards/backgrounds/attack_background.png"
		"heal":
			type_background_path = "res://assets/cards/backgrounds/heal_background.png"
		"defense":
			type_background_path = "res://assets/cards/backgrounds/defense_background.png"
		"special":
			type_background_path = "res://assets/cards/backgrounds/special_background.png"
		_:
			type_background_path = "res://assets/cards/backgrounds/default_background.png"
	
	# Load and set the background if the file exists
	if ResourceLoader.exists(type_background_path):
		card_background.texture = load(type_background_path)
	else:
		# Fallback to scene default or solid color
		if _default_card_background_texture:
			card_background.texture = _default_card_background_texture
		else:
			var fallback_color = _get_type_color(card_type)
			card_background.modulate = fallback_color

func _get_type_color(card_type: String) -> Color:
	## Get fallback color for card type
	match card_type:
		"attack":
			return Color(0.8, 0.3, 0.3)
		"heal":
			return Color(0.3, 0.8, 0.3)
		"defense":
			return Color(0.3, 0.5, 0.8)
		"special":
			return Color(0.8, 0.5, 0.2)
		_:
			return Color(0.5, 0.5, 0.5)

func _setup_description_popup():
	## Create and set up the description pop-up
	# Load scene if not already loaded (setup might be called before _ready)
	if not description_popup_scene:
		var popup_path = "res://battle-manager/card_combat/card_description_popup.tscn"
		if ResourceLoader.exists(popup_path):
			description_popup_scene = load(popup_path)
		else:
			return
	
	if not description_popup_scene:
		return
	
	# Defer setup if not in tree yet
	if not is_inside_tree():
		call_deferred("_setup_description_popup")
		return
	
	description_popup = description_popup_scene.instantiate()
	
	# Add as child of the card itself so it inherits position and z-index
	add_child(description_popup)
	
	# Set high z-index within the card's children to ensure it's on top
	description_popup.z_index = 100
	
	if description_popup.has_method("setup"):
		description_popup.setup(self, card_data.description)
	
	description_popup.visible = false

func _exit_tree():
	## Clean up description popup when card is destroyed
	if description_popup and is_instance_valid(description_popup):
		description_popup.queue_free()

func _pop_in():
	pass

func _get_cursor_manager() -> CursorManager:
	return get_tree().get_first_node_in_group("BattleHud").cursor_system if get_tree().get_first_node_in_group("BattleHud") else null

func _on_mouse_entered():
	if is_dragging:
		return
	is_hovered = true
	z_index = 100
	_animate_hover(true)
	
	# Update popup z-index to be significantly higher than any card
	if description_popup:
		description_popup.z_index = 1000
	
	var cm = _get_cursor_manager()
	if cm:
		cm.notify_hover_entered(self)

func _on_mouse_exited():
	if is_dragging:
		return
	is_hovered = false
	z_index = base_z_index
	_animate_hover(false)
	
	# Update popup z-index to match base card
	if description_popup:
		description_popup.z_index = z_index + 1
	
	var cm = _get_cursor_manager()
	if cm:
		cm.notify_hover_exited(self)

func set_controller_hover(hover: bool) -> void:
	if hover and not is_hovered:
		_on_mouse_entered()
	elif not hover and is_hovered:
		_on_mouse_exited()

func _animate_hover(hover: bool):
	if hover_tween and hover_tween.is_running():
		hover_tween.kill()
	
	# Animate z-index and card_3d_container
	hover_tween = create_tween()
	hover_tween.set_parallel(true)
	hover_tween.set_ease(Tween.EaseType.EASE_OUT)
	hover_tween.set_trans(Tween.TransitionType.TRANS_CUBIC)
	
	hover_tween.tween_property(self, "z_index", 100 if hover else base_z_index, 0.15)
	if card_3d_container:
		hover_tween.tween_property(card_3d_container, "position", Vector2(0.0, -45.0 + base_y_offset) if hover else Vector2(0.0, base_y_offset), 0.15)
		hover_tween.tween_property(card_3d_container, "scale", Vector2(1.2, 1.2) if hover else Vector2.ONE, 0.15)
		hover_tween.tween_property(card_3d_container, "rotation_degrees", 0.0 if hover else base_rotation, 0.15)
	
	# Update popup z-index with tween to use a very high value
	if description_popup:
		var target_z = 1000 if hover else base_z_index + 1
		hover_tween.tween_property(description_popup, "z_index", target_z, 0.15)

func _process(delta: float) -> void:
	var mouse_pos = get_viewport().get_mouse_position()
	
	# Handle description popup hover timer
	if is_hovered and not is_dragging and description_popup:
		hover_timer += delta
		if hover_timer >= HOVER_THRESHOLD:
			if description_popup.has_method("set_hovering"):
				description_popup.set_hovering(true)
				# Update position when showing
				if description_popup.has_method("update_position"):
					description_popup.update_position()
				# Update z-index to match card
				description_popup.z_index = z_index
	else:
		hover_timer = 0.0
		if description_popup and description_popup.has_method("set_hovering"):
			description_popup.set_hovering(false)
	
	# Update popup position and z-index if visible and card is moving
	if description_popup and description_popup.visible:
		if description_popup.has_method("update_position"):
			description_popup.update_position()
		description_popup.z_index = z_index
	
	if is_dragging:
		# Dragging logic
		var cur_vel = (mouse_pos - last_mouse_pos) / max(delta, 0.001)
		drag_velocity = drag_velocity.lerp(cur_vel, 15.0 * delta)
		last_mouse_pos = mouse_pos
		
		# Move card_3d_container freely to mouse
		var target_face_global = mouse_pos - drag_offset
		if card_3d_container:
			card_3d_container.global_position = target_face_global
			card_3d_container.scale = Vector2(1.25, 1.25)
		
		is_out_of_hand = not _is_inside_hand_zone()
	elif is_hovered:
		# Hover state with pseudo 3D effect
		if card_shader_material:
			var card_center := global_position + (size * 0.5)
			var offset_from_center = (mouse_pos - card_center) / (size * 0.5)
			var target_tilt_y = clamp(offset_from_center.x * max_tilt, -max_tilt, max_tilt)
			var target_tilt_x = clamp(-offset_from_center.y * max_tilt, -max_tilt, max_tilt)
			
			# Apply inertia to tilt values
			current_y_rot = lerp(current_y_rot, target_tilt_y, (1.0 - tilt_inertia) * 15.0 * delta)
			current_x_rot = lerp(current_x_rot, target_tilt_x, (1.0 - tilt_inertia) * 15.0 * delta)
			
			card_shader_material.set_shader_parameter("y_rot", current_y_rot)
			card_shader_material.set_shader_parameter("x_rot", current_x_rot)
		
		if card_3d_container:
			card_3d_container.scale = lerp(card_3d_container.scale, Vector2(1.2, 1.2), 0.25)
	else:
		# Normal state - respect fanning parameters
		if card_shader_material:
			# Decay tilt values back to zero
			if abs(current_y_rot) > 0.1 or abs(current_x_rot) > 0.1:
				current_y_rot = lerp(current_y_rot, 0.0, (1.0 - tilt_inertia) * 15.0 * delta)
				current_x_rot = lerp(current_x_rot, 0.0, (1.0 - tilt_inertia) * 15.0 * delta)
				card_shader_material.set_shader_parameter("y_rot", current_y_rot)
				card_shader_material.set_shader_parameter("x_rot", current_x_rot)
			else:
				card_shader_material.set_shader_parameter("y_rot", 0.0)
				card_shader_material.set_shader_parameter("x_rot", 0.0)
		
		if card_3d_container and not is_draw_animating:
			card_3d_container.scale = lerp(card_3d_container.scale, Vector2.ONE, 0.25)
			card_3d_container.position = Vector2(0.0, base_y_offset)
			card_3d_container.rotation_degrees = base_rotation

func _on_gui_input(event: InputEvent):
	## Connected to CardFace.gui_input in card_button.tscn. The root Control
	## itself is mouse_filter = IGNORE so its resting fan slot no longer acts
	## as a stale detection area - the visual CardFace is the hit area.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_start_drag()
		else:
			if is_dragging:
				_end_drag()

func _input(event: InputEvent) -> void:
	if is_dragging and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_end_drag()

func _start_drag():
	if is_dragging:
		return
	
	if hover_tween and hover_tween.is_running():
		hover_tween.kill()
	if return_tween and return_tween.is_running():
		return_tween.kill()
	
	is_dragging = true
	is_out_of_hand = false
	z_index = 200
	
	var mouse_pos = get_viewport().get_mouse_position()
	# Drag offset relative to card_3d_container's global position
	var face_global = card_3d_container.global_position if card_3d_container else global_position
	drag_offset = mouse_pos - face_global
	last_mouse_pos = mouse_pos
	drag_velocity = Vector2.ZERO
	
	# Cursor to PRESS
	var cm = _get_cursor_manager()
	if cm:
		cm.notify_hover_entered(self)
		if cm.cursor_display:
			cm.cursor_display.set_cursor_state(CursorDisplay.CursorState.PRESS)
	
	card_drag_started.emit(self)

func _end_drag():
	if not is_dragging:
		return
	
	is_dragging = false
	is_out_of_hand = false
	
	var cm = _get_cursor_manager()
	if cm:
		cm.notify_hover_exited(self)
		cm.force_cursor_state(CursorDisplay.CursorState.DEFAULT)
	
	# "Play" only when the card is released outside the hand container's
	# boundaries. Inside them, CardUI slots it back into the fan (reordering
	# it to the closest position to the release point). The actual play
	# attempt (incl. the AP check) lives in CardUI so a rejected card is
	# returned to the hand instead of vanishing mid-air.
	var dropped_in_play_zone := not _is_inside_hand_zone()
	card_drag_ended.emit(self, dropped_in_play_zone)

func _get_hand_zone_rect() -> Rect2:
	## Hand zone as reported by CardUI (the CardContainer boundaries plus a
	## small margin). Falls back to the legacy screen rule if no CardUI is
	## wired up.
	if hand_bounds_provider.is_valid():
		var rect: Variant = hand_bounds_provider.call()
		if rect is Rect2:
			return rect
	var vp_rect := get_viewport_rect()
	return Rect2(Vector2.ZERO, Vector2(vp_rect.size.x, vp_rect.size.y - 230.0))

func _compute_face_world_rect() -> Rect2:
	## Axis-aligned world rect that encloses the CardFace's current
	## transform (raised / rotated / scaled) - i.e. the card as drawn.
	if not card_3d_container:
		return get_global_rect()
	var t := card_3d_container.get_global_transform()
	var half := card_3d_container.size * 0.5
	var center := t * half
	var extent := t.basis_xform(half).abs()
	return Rect2(center - extent, extent * 2.0)

func _is_inside_hand_zone() -> bool:
	## True while any part of the card's visual form still overlaps the hand
	## zone. Matches the live table-tilt feedback in _process.
	return _compute_face_world_rect().intersects(_get_hand_zone_rect())

func is_point_over_visual(global_point: Vector2) -> bool:
	## Detection covers BOTH the resting fan position and the raised hover
	## position at the same time, so a card is hittable across the whole
	## zone it sweeps through (no dead gaps between neighbouring cards).
	if not card_3d_container:
		return get_global_rect().has_point(global_point)
	
	# Use the actual current global rect which includes the animated position
	var current_rect = card_3d_container.get_global_rect()
	
	# Add padding to account for the hover scale (1.2x)
	var padding = Vector2(current_rect.size * 0.1)
	
	# Add extra bottom padding when highlighted to cover the lift animation
	if is_hovered:
		padding.y += 40.0
	
	var expanded_rect = Rect2(
		current_rect.position - padding,
		current_rect.size + padding * 2
	)
	
	return expanded_rect.has_point(global_point)

# Returns true if the cursor is touching the card (Balatro-style detection)
func is_cursor_touching() -> bool:
	var mouse_pos: Vector2 = get_global_mouse_position()
	var start = card_3d_container.global_position if card_3d_container else global_position
	var end = start + (card_3d_container.size if card_3d_container else size)
	var starty = mouse_pos.x >= start.x and mouse_pos.y >= start.y
	var endy = mouse_pos.x <= end.x and mouse_pos.y <= end.y
	return starty and endy
