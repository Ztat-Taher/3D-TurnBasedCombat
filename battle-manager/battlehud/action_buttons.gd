class_name ActionButtons
extends BoxContainer

var buttons: Array[Control] = []

@onready var container_juice: ContainerJuice = get_node_or_null("ContainerJuice")

func _ready() -> void:
	# Collect all button children (now inside wrapper controls)
	for child in get_children():
		if child is Control and child.name.ends_with("Wrapper"):
			# Find the button inside the wrapper
			for button_child in child.get_children():
				if button_child is TextureButton:
					buttons.append(button_child)
					break

# Make tween accessible for parent scripts
func get_tween() -> Tween:
	return container_juice.current_tween if container_juice else null

func set_buttons_hidden() -> void:
	if container_juice:
		container_juice.set_hidden_state()

func animate_buttons_in() -> void:
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
