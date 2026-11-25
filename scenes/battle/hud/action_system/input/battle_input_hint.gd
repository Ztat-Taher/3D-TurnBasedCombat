extends "res://addons/maaacks_game_template/base/nodes/input_hint/input_hint.gd"
## Input hint that auto-resolves the shared InputIconMapper used by the
## options menu input settings, so battle prompts use the same icon system.
## The lookup is retried on every refresh, so a hint that becomes ready before
## the mapper exists (e.g. one created by a ContextualButtonBar) still gets icons.

func _ready() -> void:
	# super._ready() connects joypad_device_changed itself when the mapper is set
	if input_icon_mapper == null:
		input_icon_mapper = get_tree().get_first_node_in_group("input_icon_mapper") as InputIconMapper
	super._ready()


func _refresh() -> void:
	_resolve_icon_mapper()
	# The mapper only knows the joypad device after its own _ready
	if input_icon_mapper != null and not input_icon_mapper.is_node_ready():
		if not input_icon_mapper.ready.is_connected(_refresh):
			input_icon_mapper.ready.connect(_refresh, CONNECT_ONE_SHOT)
		return
	super._refresh()


func _resolve_icon_mapper() -> void:
	if input_icon_mapper != null or not is_inside_tree():
		return
	input_icon_mapper = get_tree().get_first_node_in_group("input_icon_mapper") as InputIconMapper
	if input_icon_mapper and not input_icon_mapper.joypad_device_changed.is_connected(_refresh):
		input_icon_mapper.joypad_device_changed.connect(_refresh)
