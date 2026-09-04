extends Control
class_name CardButton
## Button representing a card in the player's hand with visual polish, pseudo-3D shader tilt, and drag-and-drop

signal card_played(card: CardData)
signal card_drag_started(card_button: CardButton)
signal card_drag_ended(card_button: CardButton, dropped_in_play_zone: bool)

var card_data: CardData
var is_hovered: bool = false
var is_selected: bool = false
var is_dragging: bool = false

var base_position: Vector2 = Vector2.ZERO
var base_rotation: float = 0.0
var base_y_offset: float = 0.0
var base_z_index: int = 0
var hover_offset: float = -30.0

var drag_offset: Vector2 = Vector2.ZERO
var last_mouse_pos: Vector2 = Vector2.ZERO
var drag_velocity: Vector2 = Vector2.ZERO

# Parent-reparenting for drag: store original parent and index
var _original_parent: Node = null
var _original_index: int = -1
var _card_type_color: Color = Color.WHITE

@onready var card_panel: Panel = get_node("CardPanel")
@onready var name_label: Label = get_node("CardPanel/Content/VBox/CardName")
@onready var cost_label: Label = get_node("CardPanel/Content/VBox/CostContainer/CostLabel")
@onready var cost_background: Panel = get_node("CardPanel/Content/VBox/CostContainer")
@onready var description_label: Label = get_node("CardPanel/Content/VBox/CardDescription")
@onready var glow: Panel = get_node("Glow")

var hover_tween: Tween
var return_tween: Tween
var card_shader_material: ShaderMaterial

func setup(card: CardData) -> void:
	card_data = card
	
	card_panel = get_node_or_null("CardPanel")
	name_label = get_node_or_null("CardPanel/Content/VBox/CardName")
	cost_label = get_node_or_null("CardPanel/Content/VBox/CostContainer/CostLabel")
	description_label = get_node_or_null("CardPanel/Content/VBox/CardDescription")
	glow = get_node_or_null("Glow")
	
	if name_label:
		name_label.text = card.name
	
	if cost_label:
		cost_label.text = str(card.cost)
	
	if description_label:
		var description = ""
		if card.attack > 0:
			description += "Damage: " + str(card.attack) + "\n"
		if card.health > 0:
			description += "Health: " + str(card.health) + "\n"
		if card.metadata.has("element"):
			var element = card.metadata["element"]
			description += "Element: " + element.capitalize() + "\n"
		if card.metadata.has("applies_state"):
			var state = card.metadata["applies_state"]
			var duration = card.metadata.get("state_duration", 0)
			description += "Applies: " + state.capitalize()
			if duration > 0:
				description += " (" + str(duration) + " turns)"
			description += "\n"
		if card.metadata.has("description"):
			description += card.metadata["description"]
		description_label.text = description
	
	_set_card_type_color()

func set_fan_parameters(rot_deg: float, y_offset: float, z_idx: int) -> void:
	base_rotation = rot_deg
	base_y_offset = y_offset
	base_z_index = z_idx
	if not is_dragging:
		z_index = z_idx
	
	if not is_hovered and not is_dragging:
		if card_panel:
			card_panel.rotation_degrees = base_rotation
			card_panel.position = Vector2(0.0, base_y_offset)
		if glow:
			glow.rotation_degrees = base_rotation
			glow.position = Vector2(0.0, -4.0 + base_y_offset)

func _ready():
	pivot_offset = Vector2(60, 180)
	if card_panel:
		card_panel.pivot_offset = Vector2(60, 180)
	if glow:
		glow.pivot_offset = Vector2(64, 184)
		glow.modulate.a = 0.0
		
	_setup_shader()
	_pop_in()

func _setup_shader():
	var shader = load("res://battle-manager/card_combat/card_pseudo_3d.gdshader")
	# Apply shader to the root Control (self) not card_panel.
	# Panel nodes have no TEXTURE in canvas_item shaders, causing transparency.
	if shader:
		card_shader_material = ShaderMaterial.new()
		card_shader_material.shader = shader
		card_shader_material.set_shader_parameter("border_scale", 1.0)
		card_shader_material.set_shader_parameter("shadow_offset", Vector2(0.0, 15.0))
		card_shader_material.set_shader_parameter("shadow_color", Color(0.0, 0.0, 0.0, 0.906))
		card_shader_material.set_shader_parameter("blur_amount", 1.2)
		card_shader_material.set_shader_parameter("shadow_scale", 1.05)
		card_shader_material.set_shader_parameter("fov", 90.0)
		card_shader_material.set_shader_parameter("cull_back", true)
		card_shader_material.set_shader_parameter("hovering", 0.0)
		# Do NOT set shader on card_panel - it has no TEXTURE, causing invisible cards
		# Instead keep card_panel plain and use modulate for card type color

func _set_card_type_color():
	if not card_data or not card_panel:
		return
	
	var card_type = card_data.metadata.get("card_type", "attack")
	var color: Color
	match card_type:
		"attack":
			color = Color(0.8, 0.3, 0.3)
		"heal":
			color = Color(0.3, 0.8, 0.3)
		"defense":
			color = Color(0.3, 0.5, 0.8)
		_:
			color = Color(0.7, 0.7, 0.7)
	
	# Store the color and apply to the StyleBoxFlat bg_color so shader doesn't interfere
	_card_type_color = color
	var stylebox = card_panel.get_theme_stylebox("panel") as StyleBoxFlat
	if stylebox:
		# Duplicate so we don't modify the shared resource
		var unique_style = stylebox.duplicate() as StyleBoxFlat
		unique_style.bg_color = color
		card_panel.add_theme_stylebox_override("panel", unique_style)

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
	
	var cm = _get_cursor_manager()
	if cm:
		cm.notify_hover_entered(self)

func _on_mouse_exited():
	if is_dragging:
		return
	is_hovered = false
	z_index = base_z_index
	_animate_hover(false)
	
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
	
	var panel_target_y = (base_y_offset - 45.0) if hover else base_y_offset
	var target_rotation = 0.0 if hover else base_rotation
	var target_scale = Vector2(1.2, 1.2) if hover else Vector2.ONE
	
	hover_tween = create_tween()
	hover_tween.set_parallel(true)
	hover_tween.set_ease(Tween.EaseType.EASE_OUT)
	hover_tween.set_trans(Tween.TransitionType.TRANS_CUBIC)
	
	if card_panel:
		hover_tween.tween_property(card_panel, "position:x", 0.0, 0.15)
		hover_tween.tween_property(card_panel, "position:y", panel_target_y, 0.15)
		hover_tween.tween_property(card_panel, "rotation_degrees", target_rotation, 0.15)
		hover_tween.tween_property(card_panel, "scale", target_scale, 0.15)
	
	if card_shader_material:
		hover_tween.tween_property(card_shader_material, "shader_parameter/hovering", 1.0 if hover else 0.0, 0.15)

func _process(delta: float) -> void:
	var mouse_pos = get_viewport().get_mouse_position()
	
	if is_dragging:
		# Velocity for responsive tilt
		var cur_vel = (mouse_pos - last_mouse_pos) / max(delta, 0.001)
		drag_velocity = drag_velocity.lerp(cur_vel, 15.0 * delta)
		last_mouse_pos = mouse_pos
		
		# Move card_panel & glow freely to mouse without moving CardButton inside HBoxContainer
		var target_panel_global = mouse_pos - drag_offset
		if card_panel:
			card_panel.global_position = target_panel_global
		
		# Dynamic tilt based on velocity and center displacement
		var tilt_y = clamp(-drag_velocity.x * 0.02, -25.0, 25.0)
		var tilt_x = clamp(drag_velocity.y * 0.02, -20.0, 20.0)
		var rot_z = clamp(drag_velocity.x * 0.04, -18.0, 18.0)
		
		if card_panel:
			card_panel.rotation_degrees = rot_z
			card_panel.scale = Vector2(1.25, 1.25)
		
		if card_shader_material:
			card_shader_material.set_shader_parameter("y_rot", tilt_y)
			card_shader_material.set_shader_parameter("x_rot", tilt_x)
			card_shader_material.set_shader_parameter("mouse_screen_pos", mouse_pos)
			card_shader_material.set_shader_parameter("hovering", 1.0)
	elif is_hovered:
		if card_shader_material:
			var card_center = global_position + (size / 2.0)
			var offset_from_center = (mouse_pos - card_center) / (size / 2.0)
			var tilt_y = clamp(offset_from_center.x * 15.0, -20.0, 20.0)
			var tilt_x = clamp(-offset_from_center.y * 15.0, -20.0, 20.0)
			card_shader_material.set_shader_parameter("y_rot", tilt_y)
			card_shader_material.set_shader_parameter("x_rot", tilt_x)
			card_shader_material.set_shader_parameter("mouse_screen_pos", mouse_pos)
	else:
		if card_shader_material:
			var cur_y: float = card_shader_material.get_shader_parameter("y_rot") if card_shader_material.get_shader_parameter("y_rot") != null else 0.0
			var cur_x: float = card_shader_material.get_shader_parameter("x_rot") if card_shader_material.get_shader_parameter("x_rot") != null else 0.0
			if abs(cur_y) > 0.1 or abs(cur_x) > 0.1:
				card_shader_material.set_shader_parameter("y_rot", lerp(cur_y, 0.0, 15.0 * delta))
				card_shader_material.set_shader_parameter("x_rot", lerp(cur_x, 0.0, 15.0 * delta))

func _gui_input(event: InputEvent):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_start_drag()
		else:
			if is_dragging:
				_end_drag()

func _input(event: InputEvent):
	# Global release safety in case mouse left window or control bounds
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
	z_index = 200
	
	var mouse_pos = get_viewport().get_mouse_position()
	# Drag offset relative to card_panel's global position
	var panel_global = card_panel.global_position if card_panel else global_position
	drag_offset = mouse_pos - panel_global
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
	
	var mouse_pos = get_viewport().get_mouse_position()
	var vp_rect = get_viewport().get_visible_rect()
	
	# Drop zone: dragged upwards above hand area (upper 68% of screen)
	var play_drop_threshold_y = vp_rect.size.y - 230.0
	var is_in_play_zone = mouse_pos.y < play_drop_threshold_y
	
	var cm = _get_cursor_manager()
	if cm:
		cm.notify_hover_exited(self)
		cm.force_cursor_state(CursorDisplay.CursorState.DEFAULT)
	
	if is_in_play_zone:
		card_drag_ended.emit(self, true)
		card_played.emit(card_data)
	else:
		card_drag_ended.emit(self, false)
