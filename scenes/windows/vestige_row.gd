class_name VestigeRow
extends HBoxContainer
## One vestige in the party screen's vestiges list: icon, name (+ stacks) and
## description.

@onready var icon_rect : TextureRect = %Icon
@onready var name_label : Label = %NameLabel
@onready var description_label : Label = %DescriptionLabel


func setup(vestige : Vestige, stacks : int) -> void:
	if not is_node_ready():
		await ready
	icon_rect.texture = vestige.icon
	name_label.text = vestige.vestige_name + (" ×%d" % stacks if stacks > 1 else "")
	description_label.text = vestige.description
	tooltip_text = "%s\n%s" % [name_label.text, vestige.description]
