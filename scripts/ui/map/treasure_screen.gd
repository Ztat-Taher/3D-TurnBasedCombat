class_name TreasureScreen
extends Control
## Treasure chest UI, opened as its own scene from the run map
## Awards a random vestige to the player

signal level_changed(next_level_path : String)

const MAP_LEVEL_PATH : String = "res://scenes/menus/map_menu/map_menu_3d.tscn"

const CARD := "MainContainer/HBox/RightColumn/VestigeCard"
const CONTENT := CARD + "/CardContent"

@onready var vestige_card: PanelContainer = get_node(CARD)
@onready var header_label: Label = get_node(CONTENT + "/HeaderLabel")
@onready var vestige_name_label: Label = get_node(CONTENT + "/VestigeName")
@onready var vestige_description_label: Label = get_node(CONTENT + "/VestigeDescription")
@onready var tags_row: HBoxContainer = get_node(CONTENT + "/Tags")
@onready var rarity_tag: PanelContainer = get_node(CONTENT + "/Tags/RarityTag")
@onready var rarity_label: Label = get_node(CONTENT + "/Tags/RarityTag/RarityLabel")
@onready var scope_label: Label = get_node(CONTENT + "/Tags/ScopeTag/ScopeLabel")
@onready var party_selection_container: VBoxContainer = get_node(CONTENT + "/PartySelectionContainer")
@onready var party_buttons: HFlowContainer = get_node(CONTENT + "/PartySelectionContainer/PartyButtons")
@onready var take_button: Button = get_node(CONTENT + "/Actions/TakeButton")
@onready var skip_button: Button = get_node(CONTENT + "/Actions/SkipButton")
@onready var click_prompt: VBoxContainer = $ClickPrompt
@onready var prompt_label: Label = $ClickPrompt/PromptLabel
@onready var progress_pips: HBoxContainer = $ClickPrompt/ProgressPips
@onready var chest: Node3D = $SubViewportContainer/SubViewport/Chest
@onready var camera_3d: Camera3D = $SubViewportContainer/SubViewport/Camera3D
@onready var main_container: Control = $MainContainer
@onready var screen_flash: ColorRect = $ScreenFlash
@onready var rarity_banner: Label = $RarityBanner
@onready var contextual_bar: ContextualButtonBar = $ContextualButtons

var awarded_vestige: Vestige = null
var selected_party_member: AllyPartyMember = null
var panel_reveal_tween: Tween
var camera_tween: Tween
var ui_reveal_tween: Tween
var prompt_pulse_tween: Tween
var party_button_group := ButtonGroup.new()
var camera_shake_tween: Tween
## Camera pose authored in the scene; framing always starts from here
var camera_home: Transform3D
## Fraction of the half-screen height the chest and revealed item may use (1 = edge)
const FRAME_LIMIT := 0.8
var cursor_manager: CursorManager
var is_hovering_chest: bool = false

func _process(_delta):
	# Check for chest hover to update cursor
	if chest and not chest.is_opening:
		_check_chest_hover()


func _ready() -> void:
	# Get cursor manager reference
	cursor_manager = get_tree().get_first_node_in_group("cursor_manager")
	if not cursor_manager:
		cursor_manager = get_tree().get_first_node_in_group("CursorManager")

	_generate_random_vestige()
	_setup_party_selection()
	_setup_chest()
	if chest:
		chest.chest_opened.connect(_on_chest_opened)
		chest.vestige_revealed.connect(_on_vestige_revealed)
		chest.clicks_progress.connect(_on_clicks_progress)
		# Set the vestige icon texture on the 3D mesh
		if awarded_vestige and awarded_vestige.icon:
			chest.set_vestige_icon(awarded_vestige.icon)

func _input(event):
	# Handle chest clicks at screen level
	if chest and not chest.is_opening:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			print("TreasureScreen: Left mouse button pressed detected")
			_check_chest_click(event)

func _check_chest_click(event):
	print("TreasureScreen: _check_chest_click called")
	var result = _raycast_to_chest()

	if result:
		print("TreasureScreen: Raycast hit something at: ", result.position)
		print("TreasureScreen: Hit collider: ", result.collider)
		print("TreasureScreen: Is chest? ", result.collider == chest)
	else:
		print("TreasureScreen: Raycast hit nothing")

	if result and result.collider == chest:
		print("TreasureScreen: Click registered on chest!")
		chest.on_chest_clicked()
		if contextual_bar:
			contextual_bar.flash_button(&"Confirm")
		get_viewport().set_input_as_handled()
	else:
		print("TreasureScreen: Click did not hit chest")

func _check_chest_hover():
	var result = _raycast_to_chest()
	var is_now_hovering = result and result.collider == chest

	if is_now_hovering != is_hovering_chest:
		is_hovering_chest = is_now_hovering
		if cursor_manager:
			cursor_manager.set_hovering(self, is_hovering_chest)

func _raycast_to_chest():
	var container: SubViewportContainer = $SubViewportContainer
	var sub_viewport: SubViewport = $SubViewportContainer/SubViewport
	if not container or not sub_viewport or not camera_3d:
		return null
	if container.size.x <= 0.0 or container.size.y <= 0.0:
		return null

	# Mouse position relative to the container (in canvas units, so it respects the
	# project's canvas_items stretch mode), then mapped onto the SubViewport's pixels.
	# Using the root window size here breaks whenever the window isn't 1280x720.
	var local_mouse_pos := container.get_local_mouse_position()
	var sub_mouse_pos := local_mouse_pos * Vector2(sub_viewport.size) / container.size

	# Project ray from camera using SubViewport coordinates
	var ray_origin = camera_3d.project_ray_origin(sub_mouse_pos)
	var ray_direction = camera_3d.project_ray_normal(sub_mouse_pos)

	# Create ray query
	var ray_params = PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_direction * 100.0)
	ray_params.collide_with_bodies = true
	ray_params.collide_with_areas = false
	ray_params.collision_mask = 2  # Chest collision layer

	# Query the world the camera (and chest) actually live in
	var world_3d := camera_3d.get_world_3d()
	if not world_3d:
		return null

	return world_3d.direct_space_state.intersect_ray(ray_params)


func _generate_random_vestige() -> void:
	# Load vestige library
	var library_path = "res://database/vestiges/vestige_library.tres"
	if not ResourceLoader.exists(library_path):
		_show_error("Vestige library not found")
		return

	var library = load(library_path)
	if library == null:
		_show_error("Failed to load vestige library")
		return

	# Rarity-weighted roll among the vestiges the run can still gain
	var selected: Vestige = (library as VestigeLibrary).roll(Vestige.DropSource.TREASURE,
		func(v: Vestige) -> bool: return GameState.can_gain_vestige(v))
	if selected == null:
		_show_no_vestiges_available()
		return

	awarded_vestige = selected
	# Don't display yet - wait for chest to open


func _display_vestige(vestige: Vestige) -> void:
	vestige_name_label.text = vestige.vestige_name
	vestige_description_label.text = vestige.description

	var rarity_color: Color = Vestige.get_rarity_color(vestige.rarity)
	rarity_label.text = vestige.get_rarity_name().capitalize()
	rarity_label.add_theme_color_override("font_color", rarity_color)
	_set_border_color(rarity_tag, rarity_color)
	# Tint the card border with the rarity color too
	_set_border_color(vestige_card, rarity_color.lerp(Color.WHITE, 0.35))

	scope_label.text = "Party-wide" if vestige.scope == Vestige.Scope.GLOBAL else "One ally"
	tags_row.visible = true

	# Update party selection based on vestige scope
	_update_party_selection_visibility()


## Gives a panel its own copy of its stylebox with a new border color
func _set_border_color(panel: PanelContainer, color: Color) -> void:
	var style := panel.get_theme_stylebox("panel")
	if style is StyleBoxFlat:
		style = style.duplicate()
		style.border_color = color
		panel.add_theme_stylebox_override("panel", style)


func _setup_party_selection() -> void:
	if not party_selection_container:
		return

	var party = GameState.get_party()
	party_selection_container.visible = false

	for child in party_buttons.get_children():
		child.queue_free()

	if party.is_empty():
		return

	# One toggle button per ally. The ButtonGroup keeps exactly one selected,
	# and the theme's "pressed" style shows which one it is.
	for member in party:
		var button := Button.new()
		button.text = member.display_name
		button.toggle_mode = true
		# Allies that can't take another stack of this vestige can't be picked
		button.disabled = awarded_vestige != null and not GameState.can_gain_vestige(awarded_vestige, member)
		button.button_group = party_button_group
		button.custom_minimum_size = Vector2(96, 34)
		button.focus_mode = Control.FOCUS_ALL
		button.pressed.connect(_on_party_member_selected.bind(member))
		party_buttons.add_child(button)

	# Preselect the first ally that can take it
	selected_party_member = null
	for i in party.size():
		var button := party_buttons.get_child(i) as Button
		if not button.disabled:
			selected_party_member = party[i]
			button.button_pressed = true
			break


func _update_party_selection_visibility() -> void:
	if not party_selection_container:
		return
	
	# Only show party selection for per-character vestiges
	if awarded_vestige and awarded_vestige.scope == Vestige.Scope.PER_CHARACTER:
		var party = GameState.get_party()
		if party.size() > 1:
			party_selection_container.visible = true
		else:
			party_selection_container.visible = false
	else:
		# Global vestige - hide party selection
		party_selection_container.visible = false


func _on_party_member_selected(member: AllyPartyMember) -> void:
	selected_party_member = member


func _on_take_button_pressed() -> void:
	if awarded_vestige == null:
		_show_error("No vestige to award")
		return

	# Party-wide vestiges go to the party, per-character ones to the chosen ally
	var member := selected_party_member if awarded_vestige.scope == Vestige.Scope.PER_CHARACTER else null
	if not GameState.grant_vestige(awarded_vestige, member):
		_show_error("No party member can take this vestige")
		return
	
	# Return to map immediately
	level_changed.emit(MAP_LEVEL_PATH)


func _on_skip_button_pressed() -> void:
	level_changed.emit(MAP_LEVEL_PATH)


func _show_error(message: String) -> void:
	vestige_name_label.text = "Error"
	vestige_description_label.text = message
	tags_row.visible = false
	take_button.disabled = true


func _show_no_vestiges_available() -> void:
	header_label.text = "EMPTY CHEST"
	vestige_name_label.text = "Nothing Left"
	vestige_description_label.text = "You already own every vestige this chest could hold."
	tags_row.visible = false
	take_button.disabled = true


# trigger_chest_opening removed - using _setup_chest instead

## The lid just burst open: flash, shake and announce the rarity (bigger for rarer loot)
func _on_chest_opened() -> void:
	var color: Color = chest.rarity_color
	var tier: int = chest.rarity_tier

	_play_screen_flash(color, tier)
	_play_camera_shake(0.015 + 0.012 * tier, 0.25 + 0.1 * tier)
	if awarded_vestige:
		_play_rarity_banner(awarded_vestige.get_rarity_name().to_upper() + "!", color, tier)


func _play_screen_flash(color: Color, tier: int) -> void:
	if not screen_flash:
		return
	screen_flash.color = Color(color.r, color.g, color.b, 0.0)
	var peak := 0.18 + 0.07 * tier
	var flash := create_tween()
	flash.tween_property(screen_flash, "color:a", peak, 0.05)
	flash.tween_property(screen_flash, "color:a", 0.0, 0.35 + 0.1 * tier).set_ease(Tween.EASE_OUT)


## Jitters the camera's view offset (doesn't fight the camera's position tween)
func _play_camera_shake(strength: float, duration: float) -> void:
	if not camera_3d:
		return
	if camera_shake_tween:
		camera_shake_tween.kill()
	camera_shake_tween = create_tween()
	camera_shake_tween.tween_method(func(t: float):
		var falloff := (1.0 - t) * (1.0 - t)
		camera_3d.h_offset = randf_range(-1.0, 1.0) * strength * falloff
		camera_3d.v_offset = randf_range(-1.0, 1.0) * strength * falloff
	, 0.0, 1.0, duration)
	camera_shake_tween.tween_callback(func():
		camera_3d.h_offset = 0.0
		camera_3d.v_offset = 0.0)


func _play_rarity_banner(text: String, color: Color, tier: int) -> void:
	if not rarity_banner:
		return
	rarity_banner.text = text
	rarity_banner.add_theme_color_override("font_color", color.lerp(Color.WHITE, 0.15))
	rarity_banner.add_theme_font_size_override("font_size", 40 + 8 * tier)
	rarity_banner.visible = true
	rarity_banner.pivot_offset = rarity_banner.size / 2.0
	rarity_banner.modulate.a = 0.0
	rarity_banner.scale = Vector2(2.2, 2.2)
	rarity_banner.rotation_degrees = -4.0

	var banner := create_tween().set_parallel(true)
	banner.tween_property(rarity_banner, "modulate:a", 1.0, 0.1)
	banner.tween_property(rarity_banner, "scale", Vector2.ONE, 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	banner.tween_property(rarity_banner, "rotation_degrees", 0.0, 0.3).set_ease(Tween.EASE_OUT)
	# Hold, then drift up and fade before the card slides in
	banner.tween_property(rarity_banner, "position:y", rarity_banner.position.y - 24.0, 0.4).set_delay(1.1).set_ease(Tween.EASE_IN)
	banner.tween_property(rarity_banner, "modulate:a", 0.0, 0.4).set_delay(1.1)
	banner.chain().tween_callback(func():
		rarity_banner.visible = false
		rarity_banner.position.y += 24.0)

func _on_vestige_revealed() -> void:
	# Animate camera to float right so chest is on left
	_animate_camera_right()
	# Then show UI on the right side
	await get_tree().create_timer(0.5).timeout
	_show_ui()

## Dollies the camera back along its view direction (keeping its angle) just enough
## that the chest's base and the revealed item's highest point stay on screen.
## Works for any chest size because the chest reports its own measurements.
func _frame_camera_on_chest() -> void:
	if not camera_3d or not chest:
		return
	if camera_home == Transform3D():
		camera_home = camera_3d.global_transform
	camera_3d.global_transform = camera_home

	var tan_half := tan(deg_to_rad(camera_3d.fov) * 0.5) * FRAME_LIMIT
	var to_view := camera_home.affine_inverse()
	var extra := 0.0
	for point in [chest.get_reveal_top(), chest.global_position]:
		var local: Vector3 = to_view * point
		var depth := -local.z
		var needed := absf(local.y) / tan_half
		extra = maxf(extra, needed - depth)
	if extra > 0.0:
		camera_3d.global_position = camera_home.origin + camera_home.basis.z * extra


func _animate_camera_right():
	if not camera_3d:
		return

	if camera_tween:
		camera_tween.kill()

	camera_tween = create_tween()

	# Move camera to the right to frame chest on left side
	# Use negative X to move right in camera's view space
	var current_pos = camera_3d.global_position
	var target_pos = current_pos + Vector3(-0.5, 0, 0)  # Move right by 2 units

	print("TreasureScreen: Camera animating from ", current_pos, " to ", target_pos)
	camera_tween.tween_property(camera_3d, "global_position", target_pos, 1.0).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)

func _show_ui():
	if not main_container:
		return

	if ui_reveal_tween:
		ui_reveal_tween.kill()

	if awarded_vestige:
		_display_vestige(awarded_vestige)
		take_button.disabled = false

	main_container.modulate = Color.WHITE
	main_container.visible = true
	# Let the containers lay the card out before animating from its resting spot
	vestige_card.modulate = Color.TRANSPARENT
	await get_tree().process_frame
	_play_panel_reveal_animation()
	_enable_card_navigation()


## Choice phase: the contextual button mirrors whichever card button is highlighted
## (keyboard/gamepad focus, or the mouse hovering it) and confirms it
func _enable_card_navigation() -> void:
	var card_buttons: Array[BaseButton] = [skip_button, take_button]
	for child in party_buttons.get_children():
		if child is BaseButton:
			card_buttons.append(child)
	for button in card_buttons:
		if not button.mouse_entered.is_connected(_focus_on_hover.bind(button)):
			button.mouse_entered.connect(_focus_on_hover.bind(button))
	if contextual_bar:
		# Confirm presses the highlighted card button; Cancel (connected in the scene) skips
		contextual_bar.follow_focus(vestige_card, &"Confirm")
		contextual_bar.show_button(&"Cancel")
	if not take_button.disabled:
		take_button.grab_focus()
	else:
		skip_button.grab_focus()


func _focus_on_hover(button: BaseButton) -> void:
	if button.is_visible_in_tree() and not button.disabled:
		button.grab_focus()


## Open phase: the contextual button (Space / Enter / A, or clicking it) counts as a
## click on the chest
func _on_contextual_open() -> void:
	if chest and not chest.is_opening:
		chest.on_chest_clicked()


func _play_panel_reveal_animation():
	if not vestige_card:
		return

	if panel_reveal_tween:
		panel_reveal_tween.kill()

	# Scale from the card's center while sliding in slightly from the right
	vestige_card.pivot_offset = vestige_card.size / 2.0
	vestige_card.modulate = Color.TRANSPARENT
	vestige_card.scale = Vector2(0.85, 0.85)
	var rest_x := vestige_card.position.x
	vestige_card.position.x = rest_x + 40.0

	panel_reveal_tween = create_tween().set_parallel(true)
	panel_reveal_tween.tween_property(vestige_card, "modulate:a", 1.0, 0.25).set_ease(Tween.EASE_OUT)
	panel_reveal_tween.tween_property(vestige_card, "position:x", rest_x, 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	panel_reveal_tween.tween_property(vestige_card, "scale", Vector2.ONE, 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)


func _setup_chest():
	if not chest:
		return

	# Set chest type based on vestige rarity
	if awarded_vestige:
		match awarded_vestige.rarity:
			Vestige.Rarity.COMMON:
				chest.set_chest_type(chest.ChestType.WOOD)
			Vestige.Rarity.UNCOMMON:
				chest.set_chest_type(chest.ChestType.STONE)
			Vestige.Rarity.RARE, Vestige.Rarity.BOSS:
				chest.set_chest_type(chest.ChestType.GOLD)
			_:
				chest.set_chest_type(chest.ChestType.WOOD)
		chest.set_rarity(awarded_vestige.rarity)
	_frame_camera_on_chest()

	# The card stays hidden until the chest opens; only the click prompt shows
	if main_container:
		main_container.visible = false
	take_button.disabled = true
	if contextual_bar:
		# Confirm counts as a click on the chest until it opens
		contextual_bar.show_button(&"Confirm", "", &"", _on_contextual_open)
	_build_progress_pips(chest.clicks_required)
	_start_prompt_pulse()


func _on_clicks_progress(current: int, required: int):
	# Fill pips up to the current click count, with a pop on the newest one
	for i in progress_pips.get_child_count():
		var pip := progress_pips.get_child(i) as Panel
		_style_pip(pip, i < current)
		if i == current - 1:
			pip.pivot_offset = pip.size / 2.0
			pip.scale = Vector2(1.5, 1.5)
			create_tween().tween_property(pip, "scale", Vector2.ONE, 0.2) \
				.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

	if current >= required:
		_hide_click_prompt()
		if contextual_bar:
			contextual_bar.hide_button(&"Confirm")
	else:
		prompt_label.text = "Keep clicking!"


func _build_progress_pips(count: int) -> void:
	for child in progress_pips.get_children():
		child.queue_free()
	for i in count:
		var pip := Panel.new()
		pip.custom_minimum_size = Vector2(18, 18)
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_style_pip(pip, false)
		progress_pips.add_child(pip)


func _style_pip(pip: Panel, filled: bool) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.95, 0.95, 0.95) if filled else Color(0, 0, 0, 0.6)
	style.border_color = Color(0.95, 0.95, 0.95)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.corner_detail = 1
	pip.add_theme_stylebox_override("panel", style)


func _start_prompt_pulse() -> void:
	if prompt_pulse_tween:
		prompt_pulse_tween.kill()
	click_prompt.modulate = Color.WHITE
	prompt_pulse_tween = create_tween().set_loops()
	prompt_pulse_tween.tween_property(prompt_label, "modulate:a", 0.45, 0.8).set_trans(Tween.TRANS_SINE)
	prompt_pulse_tween.tween_property(prompt_label, "modulate:a", 1.0, 0.8).set_trans(Tween.TRANS_SINE)


func _hide_click_prompt() -> void:
	if prompt_pulse_tween:
		prompt_pulse_tween.kill()
	prompt_label.modulate.a = 1.0
	create_tween().tween_property(click_prompt, "modulate:a", 0.0, 0.4).set_delay(0.25)
