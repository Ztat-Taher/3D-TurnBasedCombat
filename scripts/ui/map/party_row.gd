class_name PartyRow
extends HBoxContainer
## One party member's row inside the Rest screen (name / HP / Heal button).
##
## The layout and the Heal button's signal connection live in party_row.tscn;
## this script only binds a member, refreshes the labels and applies a heal.

signal healed

## The party member this row displays and heals.
var member : AllyPartyMember = null
## HP restored when this row's Heal button is pressed (999 = full heal).
var heal_amount : int = 999

@onready var name_label : Label = $NameLabel
@onready var hp_label : Label = $HpLabel


func setup(p_member : AllyPartyMember, p_heal_amount : int = 999) -> void:
	member = p_member
	heal_amount = p_heal_amount
	refresh()


func refresh() -> void:
	if member == null:
		return
	var display : String = member.display_name
	name_label.text = display if not display.is_empty() else member.id
	hp_label.text = member.get_hp_text()


func _on_heal_button_pressed() -> void:
	if member == null:
		return
	member.heal(heal_amount)
	refresh()
	GlobalState.save()
	healed.emit()
