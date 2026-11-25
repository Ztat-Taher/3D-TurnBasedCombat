class_name ActionButtons
extends Control
## Battle command menu that orbits its owner, in the style of
## Clair Obscur: Expedition 33 / Persona.
##
## - The owner's chest is tracked in 3D through the battle camera every frame,
##   so the menu stays pinned to the character as it and the camera move.
## - The buttons sit on an arc around that point. The arc is a small 3D plane
##   (measured in screen pixels) that is yawed toward the viewer and drawn with
##   its own perspective: nearer buttons are bigger, and every button is
##   foreshortened along its length.
## - Each button is rotated so its inner edge points back at the owner, like spokes.
##
## Everything is drawn by the full-resolution HUD, so the PSX low-res 3D look is
## untouched and the UI stays sharp. A "sharp bilinear" shader keeps the rotated
## pixel art crisp instead of jagged.
##
## Hover/press/appear juice keeps working because it animates the inner
## TextureButton, while this script only drives the *Wrapper controls.

enum MenuSide { AUTO, RIGHT, LEFT }

@export_group("Anchor")
## Height above the owner's origin that the arc is centered on (roughly chest height)
@export var anchor_height: float = 1.1
## Extra screen offset of the arc center from the owner (x is mirrored on the left side)
@export var screen_offset: Vector2 = Vector2(10.0, -10.0)
## Which side of the owner the menu opens on. AUTO picks the side with more room
@export var side: MenuSide = MenuSide.AUTO

@export_group("Arc")
## Distance in pixels from the arc center to each button's inner edge
@export var radius: float = 130.0
## Direction of the middle of the arc. 0 = straight out sideways, + = tilted up
@export_range(-90.0, 90.0) var arc_center_deg: float = 4.0
## Angle between neighbouring buttons on the arc
@export_range(0.0, 45.0) var arc_step_deg: float = 19.0
## 1 = buttons point straight at the owner, 0 = buttons stay level
@export_range(0.0, 1.0) var face_owner_strength: float = 1.0

@export_group("Perspective")
## Swings the arc plane so the outer edge comes toward the viewer
@export_range(-80.0, 80.0) var arc_yaw_deg: float = 32.0
## Virtual camera distance in pixels. Smaller = stronger perspective
@export var focal_length: float = 520.0
## Squash each button along its length to match the yawed plane
@export var foreshorten: bool = true
@export var base_scale: float = 0.85
@export var min_scale: float = 0.6
@export var max_scale: float = 1.3

@export_group("Motion")
## How quickly buttons catch up to their target pose (higher = snappier)
@export var follow_speed: float = 16.0
## Keep the whole menu at least this far inside the screen edges
@export var screen_margin: float = 16.0

@export_group("Rendering")
## Crisp antialiased pixel art while rotated (see ui_sharp_pixel.gdshader)
@export var sharp_pixel_filter: bool = true

const SHARP_PIXEL_SHADER := preload("res://assets/shaders/ui_sharp_pixel.gdshader")

var buttons: Array[Control] = []
var wrappers: Array[Control] = []
var owner_battler: Node3D = null

@onready var container_juice: ContainerJuice = get_node_or_null("ContainerJuice")

var _side_sign: float = 1.0
var _snap_next_frame: bool = true
var _sharp_material: ShaderMaterial


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in get_children():
		if child is Control and child.name.ends_with("Wrapper"):
			for button_child in child.get_children():
				if button_child is TextureButton:
					wrappers.append(child)
					buttons.append(button_child)
					break

	if sharp_pixel_filter:
		_sharp_material = ShaderMaterial.new()
		_sharp_material.shader = SHARP_PIXEL_SHADER
		for wrapper in wrappers:
			_apply_sharp_filter(wrapper)

	visibility_changed.connect(func(): _snap_next_frame = true)


## Sets which battler the menu orbits. Call when the active character changes.
func set_owner_battler(battler: Node3D) -> void:
	if battler != owner_battler:
		_snap_next_frame = true
	owner_battler = battler
	_update_layout(0.0)


func _process(delta: float) -> void:
	if visible:
		_update_layout(delta)


# --- Layout ------------------------------------------------------------------

func _update_layout(delta: float) -> void:
	var owner_screen: Variant = _get_owner_screen_position()
	if owner_screen == null:
		return

	var vp_size := get_viewport_rect().size
	_update_side((owner_screen as Vector2).x, vp_size.x)
	var center: Vector2 = owner_screen + Vector2(screen_offset.x * _side_sign, screen_offset.y)

	var shown := _get_shown_wrappers()
	var count := shown.size()
	if count == 0:
		return

	var yaw := deg_to_rad(arc_yaw_deg)
	var targets: Array[Dictionary] = []
	var bounds := Rect2(center, Vector2.ZERO)

	for k in count:
		var wrapper := shown[k]
		# Point on the arc in "menu space": x outward, y up, z toward the viewer
		var angle := deg_to_rad(arc_center_deg + ((count - 1) * 0.5 - k) * arc_step_deg)
		var flat_x := cos(angle) * radius
		var y := sin(angle) * radius
		# Yaw the arc plane so the outer edge swings toward the viewer
		var x := flat_x * cos(yaw)
		var z := flat_x * sin(yaw)
		var depth_scale := focal_length / maxf(focal_length - z, 1.0)
		var anchor := center + Vector2(x * _side_sign, -y) * depth_scale

		# Inner edge points at the owner; text stays upright on either side
		var spoke := anchor - center
		var rot := atan2(spoke.y, spoke.x)
		if _side_sign < 0.0:
			rot -= PI
		rot = wrapf(rot, -PI, PI) * face_owner_strength

		var s := clampf(base_scale * depth_scale, min_scale, max_scale)
		var length_scale := s * (cos(yaw) if foreshorten else 1.0)
		targets.append({"wrapper": wrapper, "anchor": anchor, "rot": rot, "scale": Vector2(length_scale, s)})

		var far_end := anchor + Vector2.from_angle(rot) * wrapper.size.x * length_scale * _side_sign
		var half_h := Vector2(0.0, wrapper.size.y * s * 0.5)
		bounds = bounds.expand(anchor - half_h).expand(anchor + half_h).expand(far_end - half_h).expand(far_end + half_h)

	# Nudge the whole menu back inside the screen if it pokes out
	var push := Vector2(
		maxf(0.0, screen_margin - bounds.position.x) - maxf(0.0, bounds.end.x - (vp_size.x - screen_margin)),
		maxf(0.0, screen_margin - bounds.position.y) - maxf(0.0, bounds.end.y - (vp_size.y - screen_margin))
	)

	var t := 1.0 if (_snap_next_frame or delta <= 0.0) else 1.0 - exp(-follow_speed * delta)
	_snap_next_frame = false

	# The root sits on the arc center; wrappers are placed relative to it
	position = center + push

	for target in targets:
		var wrapper: Control = target["wrapper"]
		# Pivot on the edge closest to the owner so rotation swings around it
		var pivot := Vector2(0.0 if _side_sign > 0.0 else wrapper.size.x, wrapper.size.y * 0.5)
		wrapper.pivot_offset = pivot
		var goal_pos: Vector2 = (target["anchor"] as Vector2) - center - pivot
		wrapper.position = wrapper.position.lerp(goal_pos, t)
		wrapper.rotation = lerp_angle(wrapper.rotation, target["rot"], t)
		wrapper.scale = wrapper.scale.lerp(target["scale"], t)


## Owner's chest projected into HUD coordinates, or null if unavailable/behind the camera
func _get_owner_screen_position() -> Variant:
	if not owner_battler or not is_instance_valid(owner_battler) or not owner_battler.is_inside_tree():
		return null
	var bc := _get_battle_camera()
	if not bc:
		return null
	var world_pos := owner_battler.global_position + Vector3.UP * anchor_height
	if bc.is_position_behind(world_pos):
		return null
	return bc.world_to_screen(world_pos)


## Picks the side with more room, with hysteresis so it doesn't flicker
func _update_side(owner_x: float, screen_w: float) -> void:
	match side:
		MenuSide.RIGHT:
			_side_sign = 1.0
		MenuSide.LEFT:
			_side_sign = -1.0
		MenuSide.AUTO:
			if _side_sign > 0.0 and owner_x > screen_w * 0.62:
				_side_sign = -1.0
				_snap_next_frame = true
			elif _side_sign < 0.0 and owner_x < screen_w * 0.38:
				_side_sign = 1.0
				_snap_next_frame = true


## Wrappers whose button is logically shown (hidden ones collapse out of the arc)
func _get_shown_wrappers() -> Array[Control]:
	var shown: Array[Control] = []
	for i in wrappers.size():
		var button := buttons[i]
		if not wrappers[i].visible or not button.visible:
			continue
		if container_juice and container_juice.is_sibling_hidden(button):
			continue
		shown.append(wrappers[i])
	return shown


func _get_battle_camera() -> BattleCamera:
	var bm = get_tree().get_first_node_in_group("battle_manager")
	if not bm or not ("battle_camera" in bm):
		return null
	return bm.battle_camera as BattleCamera


func _apply_sharp_filter(node: Node) -> void:
	for child in node.get_children():
		if child is DropShadow:
			continue  # has its own shadow shader
		if child is TextureRect or child is TextureButton or child is Label:
			var item := child as CanvasItem
			if item.material == null:
				item.material = _sharp_material
				item.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		_apply_sharp_filter(child)


# --- Juice passthrough ----------------------------------------------------------

# Make tween accessible for parent scripts
func get_tween() -> Tween:
	return container_juice.current_tween if container_juice else null

func set_buttons_hidden() -> void:
	if container_juice:
		container_juice.set_hidden_state()

func animate_buttons_in() -> void:
	_snap_next_frame = true
	if container_juice:
		container_juice.appear(false)

func animate_buttons_out() -> void:
	if container_juice:
		container_juice.disappear(false)

func show_button(button_name: String) -> void:
	var button = get_button_by_name(button_name)
	if button and container_juice:
		container_juice.appear_sibling(button)

func hide_button(button_name: String) -> void:
	var button = get_button_by_name(button_name)
	if button and container_juice:
		container_juice.disappear_sibling(button)

func set_button_visible(button_name: String, should_show: bool) -> void:
	if should_show:
		show_button(button_name)
	else:
		hide_button(button_name)

func get_button_by_name(button_name: String) -> Control:
	for button in buttons:
		if button.name == button_name:
			return button
	return null

func is_button_visible(button_name: String) -> bool:
	var button = get_button_by_name(button_name)
	if button:
		return button.visible and button.modulate.a > 0.05
	return false

func refresh_buttons() -> void:
	# Animate out all buttons, then animate back in
	animate_buttons_out()
	if container_juice and container_juice.current_tween:
		await container_juice.current_tween.finished
	set_buttons_hidden()
	animate_buttons_in()
