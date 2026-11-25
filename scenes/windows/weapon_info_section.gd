class_name WeaponInfoSection
extends HBoxContainer
## Equipped weapon summary: icon, name, level and weapon type.

@onready var icon : TextureRect = $Icon
@onready var name_label : Label = $InfoVBox/NameLabel
@onready var level_label : Label = $InfoVBox/LevelLabel
@onready var type_label : Label = $InfoVBox/TypeLabel


func setup(member : AllyPartyMember) -> void:
	var equipped := member.equipped_weapon
	if equipped == null:
		name_label.text = "Unarmed"
		level_label.text = ""
		type_label.text = "Type: %s" % weapon_type_name(member.weapon_type)
		icon.texture = null
	else:
		name_label.text = equipped.item_name
		level_label.text = "Level %d" % equipped.weapon_level
		type_label.text = "Type: %s" % weapon_type_name(equipped.equip_kind())
		icon.texture = equipped.icon
	level_label.visible = not level_label.text.is_empty()
	icon.visible = icon.texture != null


## "BLADE" -> "Blade".
static func weapon_type_name(wtype : Weapon.WType) -> String:
	return str(Weapon.WType.keys()[wtype]).capitalize()
