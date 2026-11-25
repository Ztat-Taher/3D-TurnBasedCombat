class_name WeaponListItem
extends PanelContainer
## Display-only row for one owned weapon. The equipped weapon is highlighted;
## weapons this member can't use are dimmed. (Equipping from the party screen
## isn't supported yet, so this deliberately isn't a button.)

@onready var weapon_icon : TextureRect = $HBox/Icon
@onready var name_label : Label = $HBox/VBox/NameLabel
@onready var level_label : Label = $HBox/VBox/LevelLabel
func setup(weapon : Weapon, member : AllyPartyMember) -> void:
	var equipped := member.equipped_weapon == weapon
	name_label.text = weapon.item_name
	level_label.text = "Lv. %d · %s%s" % [weapon.weapon_level,
		WeaponInfoSection.weapon_type_name(weapon.equip_kind()), " · Equipped" if equipped else ""]
	weapon_icon.texture = weapon.icon
	weapon_icon.visible = weapon.icon != null
	theme_type_variation = &"PartyListItemEquipped" if equipped else &"PartyListItem"
	if not member.can_equip_weapon(weapon):
		modulate = Color(1, 1, 1, 0.5)
		tooltip_text = "%s can't use this weapon type." % member.get_display_name()
