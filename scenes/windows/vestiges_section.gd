extends VBoxContainer
class_name VestigesSection
## Lists the selected member's own vestiges and the party-wide ones.

@onready var character_vestiges : VBoxContainer = $CharacterVestiges
@onready var party_vestiges : VBoxContainer = $PartyVestiges


func setup(member : AllyPartyMember) -> void:
	_fill(character_vestiges, member.vestiges, member.get_vestige_stack_count)
	_fill(party_vestiges, GameState.get_global_vestiges(),
		func(vestige_id : String) -> int: return GameState.get_global_vestige_stack_count(vestige_id))


## Rebuilds [param container] from [param vestiges]; [param stack_count] maps a
## vestige id to its stack count.
func _fill(container : VBoxContainer, vestiges : Array[Vestige], stack_count : Callable) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()
	for vestige in vestiges:
		if vestige == null:
			continue
		var stacks : int = stack_count.call(vestige.vestige_id)
		var stack_text := " ×%d" % stacks if stacks > 1 else ""
		container.add_child(_make_label("%s%s — %s" % [vestige.vestige_name, stack_text, vestige.description]))
	if container.get_child_count() == 0:
		container.add_child(_make_label("None"))


func _make_label(text : String) -> Label:
	var label := Label.new()
	label.theme_type_variation = &"PartyBodyLabel"
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label
