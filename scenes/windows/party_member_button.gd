class_name PartyMemberButton
extends Button
## Portrait + name tile in the party screen's member row. Toggle button:
## the selected member stays pressed (shared ButtonGroup), and focusing the
## tile with the keyboard/controller selects it too.

signal member_selected(member : AllyPartyMember)

const FALLBACK_PORTRAIT : String = "res://Placeholder.svg"

var member : AllyPartyMember

@onready var portrait : TextureRect = $VBox/Portrait
@onready var name_label : Label = $VBox/NameLabel


func _ready() -> void:
	pressed.connect(_emit_selected)
	focus_entered.connect(_emit_selected)


func setup(p_member : AllyPartyMember) -> void:
	member = p_member
	name_label.text = p_member.get_display_name()
	tooltip_text = "%s — Lv %d — HP %s" % [p_member.get_display_name(), p_member.level, p_member.get_hp_text()]
	var tex := p_member.get_portrait()
	if tex == null and ResourceLoader.exists(FALLBACK_PORTRAIT):
		tex = load(FALLBACK_PORTRAIT) as Texture2D
	portrait.texture = tex


func _emit_selected() -> void:
	if member != null:
		member_selected.emit(member)
