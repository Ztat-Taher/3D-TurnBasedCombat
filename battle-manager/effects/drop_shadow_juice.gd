extends Node
class_name DropShadowJuice

## Reusable UI Juice component that creates and manages an interactive dynamic drop shadow.
## Supports rectangular Control nodes (using StyleBox) or textured Control nodes (TextureRect/TextureButton using Texture).
## Reacts to hover, pickup / drag, movement velocity tilt, and custom animations.

@export_group("Target")
@export var target_control: Control = null
@export var enabled: bool = true:
	set(val):
		enabled = val
		if shadow_node and is_instance_valid(shadow_node):
			shadow_node.visible = _should_be_visible()

@export_group("Texture Shadow")
@export var match_texture: bool = false
@export var custom_shadow_texture: Texture2D = null

@export_group("Shadow Appearance")
@export var shadow_color: Color = Color(0.0, 0.0, 0.0, 0.45)
@export var corner_radius: int = 8
@export var shadow_offset_idle: Vector2 = Vector2(0.0, 8.0)
@export var shadow_offset_hover: Vector2 = Vector2(0.0, 18.0)
@export var shadow_offset_drag: Vector2 = Vector2(0.0, 36.0)

@export_group("Shadow Scale & Blur")
@export var shadow_scale_idle: Vector2 = Vector2(0.96, 0.96)
@export var shadow_scale_hover: Vector2 = Vector2(1.04, 1.04)
@export var shadow_scale_drag: Vector2 = Vector2(1.12, 1.12)
@export var shadow_alpha_idle: float = 0.25
@export var shadow_alpha_hover: float = 0.45
@export var shadow_alpha_drag: float = 0.65

## When true the shadow is hidden until set_dragging(true) is called.
## Hover state will NOT show the shadow.
@export var show_only_on_drag: bool = false

@export_group("Animation")
@export var transition_duration: float = 0.2
@export var follow_smoothness: float = 20.0
@export var velocity_tilt_factor: float = 0.03

# Internal shadow display node (Panel for flat/rect, TextureRect for texture matching)
var shadow_node: Control = null
var current_tween: Tween = null
var is_dragging: bool = false
var is_hovered: bool = false

var last_target_pos: Vector2 = Vector2.ZERO
var current_velocity: Vector2 = Vector2.ZERO
var _signals_connected: bool = false
var _ready_done: bool = false

func _ready() -> void:
	if not target_control:
		var parent = get_parent()
		if parent is Control:
			setup(parent)
	elif target_control:
		setup(target_control)

func setup(control: Control) -> void:
	target_control = control
	_connect_target_signals()
	_create_shadow_node()
	# Initial state is applied in _init_shadow_position() once node enters tree

func _connect_target_signals() -> void:
	if _signals_connected or not target_control:
		return
	
	if target_control.has_signal("mouse_entered"):
		target_control.mouse_entered.connect(_on_target_mouse_entered)
	if target_control.has_signal("mouse_exited"):
		target_control.mouse_exited.connect(_on_target_mouse_exited)
	if target_control.has_signal("focus_entered"):
		target_control.focus_entered.connect(_on_target_mouse_entered)
	if target_control.has_signal("focus_exited"):
		target_control.focus_exited.connect(_on_target_mouse_exited)
	
	_signals_connected = true

func _on_target_mouse_entered() -> void:
	if not is_dragging:
		set_hovered(true)

func _on_target_mouse_exited() -> void:
	if not is_dragging:
		set_hovered(false)

func _detect_texture() -> Texture2D:
	if custom_shadow_texture:
		return custom_shadow_texture
	if target_control is TextureButton:
		return (target_control as TextureButton).texture_normal
	if target_control is TextureRect:
		return (target_control as TextureRect).texture
	if target_control is NinePatchRect:
		return (target_control as NinePatchRect).texture
	return null

func _create_shadow_node() -> void:
	if shadow_node and is_instance_valid(shadow_node):
		shadow_node.queue_free()
		shadow_node = null
	
	if not target_control:
		return
	
	var tex = _detect_texture() if match_texture else null
	if match_texture and tex:
		# Use TextureRect for exact PNG alpha contour shadow
		var tex_rect = TextureRect.new()
		tex_rect.name = "DropShadow_Texture"
		tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tex_rect.texture = tex
		tex_rect.modulate = shadow_color
		
		# Match stretch mode of TextureButton/TextureRect
		if target_control is TextureButton:
			tex_rect.stretch_mode = (target_control as TextureButton).stretch_mode
			if (target_control as TextureButton).ignore_texture_size:
				tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		elif target_control is TextureRect:
			tex_rect.stretch_mode = (target_control as TextureRect).stretch_mode
			tex_rect.expand_mode = (target_control as TextureRect).expand_mode
		
		shadow_node = tex_rect
	else:
		# Use Panel with soft StyleBox shadow
		var panel = Panel.new()
		panel.name = "DropShadow_Panel"
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		
		var stylebox = StyleBoxFlat.new()
		stylebox.bg_color = shadow_color
		stylebox.corner_radius_top_left = corner_radius
		stylebox.corner_radius_top_right = corner_radius
		stylebox.corner_radius_bottom_right = corner_radius
		stylebox.corner_radius_bottom_left = corner_radius
		stylebox.shadow_color = shadow_color
		stylebox.shadow_size = 14
		stylebox.shadow_offset = Vector2(0, 4)
		
		panel.add_theme_stylebox_override("panel", stylebox)
		shadow_node = panel
	
	shadow_node.z_as_relative = true
	shadow_node.z_index = -1
	# Hide until fully initialised to prevent frame-0 pop-in
	shadow_node.visible = false
	
	# For TextureButton targets: add shadow as FIRST CHILD of the button itself,
	# anchored to fill it. This avoids breaking parent layout and correctly tracks
	# the button's size/position automatically.
	if target_control is TextureButton:
		shadow_node.layout_mode = 1  # Anchors
		shadow_node.anchors_preset = 15  # Full rect
		shadow_node.anchor_right = 1.0
		shadow_node.anchor_bottom = 1.0
		shadow_node.grow_horizontal = 2
		shadow_node.grow_vertical = 2
		shadow_node.pivot_offset = target_control.size / 2.0
		target_control.add_child.call_deferred(shadow_node)
		target_control.move_child.call_deferred(shadow_node, 0)
	else:
		# Sibling approach for card panels / generic Controls
		shadow_node.size = target_control.size
		shadow_node.pivot_offset = target_control.pivot_offset if target_control.pivot_offset != Vector2.ZERO else target_control.size / 2.0
		var target_parent = target_control.get_parent()
		if target_parent:
			target_parent.add_child.call_deferred(shadow_node)
			target_parent.move_child.call_deferred(shadow_node, max(0, target_control.get_index() - 1))
		else:
			target_control.get_tree().root.add_child(shadow_node)
	
	# Init once node is in the tree
	shadow_node.tree_entered.connect(_init_shadow_position, CONNECT_ONE_SHOT)

func _init_shadow_position() -> void:
	if not target_control or not is_instance_valid(target_control) or not shadow_node or not is_instance_valid(shadow_node):
		return
	# For child-of-button mode: position/scale is handled by anchors in _process;
	# no global_position init needed — just set alpha and scale.
	if target_control is TextureButton:
		shadow_node.pivot_offset = shadow_node.size / 2.0
		shadow_node.scale = shadow_scale_idle
		shadow_node.modulate.a = shadow_alpha_idle if not show_only_on_drag else 0.0
	else:
		var global_scale = target_control.get_global_transform().get_scale()
		shadow_node.scale = global_scale * shadow_scale_idle
		shadow_node.modulate.a = shadow_alpha_idle if not show_only_on_drag else 0.0
		shadow_node.global_position = target_control.global_position + shadow_offset_idle
		shadow_node.rotation_degrees = target_control.rotation_degrees
		last_target_pos = target_control.global_position
	shadow_node.visible = _should_be_visible()
	_ready_done = true


func _should_be_visible() -> bool:
	if not enabled or not target_control:
		return false
	if not target_control.is_visible_in_tree():
		return false
	if show_only_on_drag and not is_dragging:
		return false
	return true

func _process(delta: float) -> void:
	if not enabled or not target_control or not is_instance_valid(target_control) or not shadow_node or not is_instance_valid(shadow_node):
		return
	if not _ready_done:
		return
	
	# Match visibility with target
	var should_be_visible = _should_be_visible()
	if shadow_node.visible != should_be_visible:
		shadow_node.visible = should_be_visible
	
	if not shadow_node.visible:
		return
	
	# TextureButton child-mode: shadow fills button via anchors, only need scale/alpha
	if target_control is TextureButton:
		if not (current_tween and current_tween.is_running()):
			var target_scale = shadow_scale_drag if is_dragging else (shadow_scale_hover if is_hovered else shadow_scale_idle)
			shadow_node.scale = shadow_node.scale.lerp(target_scale, follow_smoothness * delta)
			shadow_node.pivot_offset = shadow_node.size / 2.0
		return
	
	# Sibling mode: track target_control in global space
	# Keep shadow node size and pivot in sync
	if shadow_node.size != target_control.size:
		shadow_node.size = target_control.size
	var expected_pivot = target_control.pivot_offset if target_control.pivot_offset != Vector2.ZERO else target_control.size / 2.0
	if shadow_node.pivot_offset != expected_pivot:
		shadow_node.pivot_offset = expected_pivot
	
	var cur_target_pos = target_control.global_position
	var frame_vel = (cur_target_pos - last_target_pos) / max(delta, 0.001)
	current_velocity = current_velocity.lerp(frame_vel, 15.0 * delta)
	last_target_pos = cur_target_pos
	
	# Calculate target offset based on state & velocity
	var base_offset: Vector2 = shadow_offset_idle
	if is_dragging:
		var dynamic_drag_offset = shadow_offset_drag - (current_velocity * velocity_tilt_factor)
		base_offset = dynamic_drag_offset
	elif is_hovered:
		base_offset = shadow_offset_hover
	
	var target_global_pos = target_control.global_position + base_offset
	var global_scale = target_control.get_global_transform().get_scale()
	
	if is_dragging:
		shadow_node.global_position = shadow_node.global_position.lerp(target_global_pos, follow_smoothness * delta)
		shadow_node.rotation_degrees = lerp(shadow_node.rotation_degrees, target_control.rotation_degrees, follow_smoothness * delta)
		shadow_node.scale = global_scale * shadow_scale_drag
	elif not (current_tween and current_tween.is_running()):
		shadow_node.global_position = target_global_pos
		shadow_node.rotation_degrees = target_control.rotation_degrees
		shadow_node.scale = global_scale * (shadow_scale_hover if is_hovered else shadow_scale_idle)

func set_hovered(hover: bool) -> void:
	is_hovered = hover
	if not is_dragging:
		_update_shadow_state(is_hovered, false, transition_duration)

func set_dragging(dragging: bool) -> void:
	is_dragging = dragging
	_update_shadow_state(is_hovered, is_dragging, transition_duration)

func _update_shadow_state(p_hover: bool, p_drag: bool, duration: float) -> void:
	if not shadow_node or not is_instance_valid(shadow_node) or not target_control:
		return
	
	if not enabled:
		shadow_node.visible = false
		return
	
	# When show_only_on_drag, fade out then hide unless dragging
	if show_only_on_drag and not p_drag:
		if current_tween and current_tween.is_running():
			current_tween.kill()
		if shadow_node.visible:
			current_tween = create_tween()
			current_tween.tween_property(shadow_node, "modulate:a", 0.0, duration)
			current_tween.finished.connect(func(): if shadow_node and is_instance_valid(shadow_node): shadow_node.visible = false, CONNECT_ONE_SHOT)
		return
	
	shadow_node.visible = true
	
	var target_scale_mult = shadow_scale_drag if p_drag else (shadow_scale_hover if p_hover else shadow_scale_idle)
	var target_alpha = shadow_alpha_drag if p_drag else (shadow_alpha_hover if p_hover else shadow_alpha_idle)
	var target_offset = shadow_offset_drag if p_drag else (shadow_offset_hover if p_hover else shadow_offset_idle)
	
	# TextureButton child-mode: only tween scale + alpha (position is anchor-controlled)
	if target_control is TextureButton:
		if current_tween and current_tween.is_running():
			current_tween.kill()
		if duration <= 0.0:
			shadow_node.scale = target_scale_mult
			shadow_node.modulate.a = target_alpha
			return
		current_tween = create_tween()
		current_tween.set_parallel(true)
		current_tween.set_ease(Tween.EaseType.EASE_OUT)
		current_tween.set_trans(Tween.TransitionType.TRANS_CUBIC)
		current_tween.tween_property(shadow_node, "scale", target_scale_mult, duration)
		current_tween.tween_property(shadow_node, "modulate:a", target_alpha, duration)
		return
	
	# Sibling mode: tween scale + alpha + global_position + rotation
	var effective_scale = target_control.get_global_transform().get_scale() * target_scale_mult
	
	if current_tween and current_tween.is_running():
		current_tween.kill()
	
	if duration <= 0.0:
		shadow_node.scale = effective_scale
		shadow_node.modulate.a = target_alpha
		shadow_node.global_position = target_control.global_position + target_offset
		shadow_node.rotation_degrees = target_control.rotation_degrees
		return
	
	current_tween = create_tween()
	current_tween.set_parallel(true)
	current_tween.set_ease(Tween.EaseType.EASE_OUT)
	current_tween.set_trans(Tween.TransitionType.TRANS_CUBIC)
	
	current_tween.tween_property(shadow_node, "scale", effective_scale, duration)
	current_tween.tween_property(shadow_node, "modulate:a", target_alpha, duration)
	current_tween.tween_property(shadow_node, "global_position", target_control.global_position + target_offset, duration)
	current_tween.tween_property(shadow_node, "rotation_degrees", target_control.rotation_degrees, duration)

func reset() -> void:
	is_dragging = false
	is_hovered = false
	_update_shadow_state(false, false, transition_duration)

func animate_to_state(p_hover: bool, p_drag: bool, duration: float = 0.25) -> void:
	is_hovered = p_hover
	is_dragging = p_drag
	_update_shadow_state(p_hover, p_drag, duration)

func _exit_tree() -> void:
	if shadow_node and is_instance_valid(shadow_node):
		shadow_node.queue_free()
