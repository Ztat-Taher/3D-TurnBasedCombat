class_name VestigeIconsContainer
extends HBoxContainer
## Shows the icons of every vestige a battler carries (its own and the
## party-wide ones) and, on hover, an info popup per vestige.

const POPUP_SCENE := preload("res://scenes/battle/hud/status_info_popup.tscn")
const RARITY_SHADER := preload("res://assets/shaders/vestige_icon_rarity.gdshader")
## Look of each rarity in [constant RARITY_SHADER] (its "effect" uniform).
const RARITY_EFFECTS := {
	Vestige.Rarity.COMMON: 0,
	Vestige.Rarity.UNCOMMON: 1,
	Vestige.Rarity.RARE: 2,
	Vestige.Rarity.BOSS: 3,
	Vestige.Rarity.EVENT: 4,
	Vestige.Rarity.SHOP: 5,
}

## One material per rarity, shared by every icon of that rarity.
static var _rarity_materials: Dictionary = {}

var vestige_icon_template: TextureRect = null
var battler: Battler = null
var active_vestige_popups: Array[Control] = []
var popup_container: VBoxContainer = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(_show_popups)
	mouse_exited.connect(_hide_popups)


func setup(battler_node: Battler, template: TextureRect) -> void:
	if battler and battler.vestiges.changed.is_connected(update_vestige_icons):
		battler.vestiges.changed.disconnect(update_vestige_icons)
	battler = battler_node
	vestige_icon_template = template
	if not battler:
		return
	if get_parent():
		popup_container = get_parent().get_node_or_null("PopUpContainer")
	battler.vestiges.changed.connect(update_vestige_icons)
	update_vestige_icons()


func update_vestige_icons() -> void:
	if not vestige_icon_template or not is_instance_valid(battler):
		return
	for child in get_children():
		if child != vestige_icon_template:
			child.queue_free()
	for vestige in battler.vestiges.get_vestiges():
		var icon := vestige_icon_template.duplicate() as TextureRect
		icon.visible = true
		icon.custom_minimum_size = Vector2(16, 16)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if vestige.icon:
			icon.texture = vestige.icon
		icon.material = _material_for(vestige.rarity)
		add_child(icon)


static func _material_for(rarity: Vestige.Rarity) -> ShaderMaterial:
	if not _rarity_materials.has(rarity):
		var material := ShaderMaterial.new()
		material.shader = RARITY_SHADER
		material.set_shader_parameter("effect", RARITY_EFFECTS.get(rarity, 0))
		material.set_shader_parameter("glow_color", Vestige.get_rarity_color(rarity))
		_rarity_materials[rarity] = material
	return _rarity_materials[rarity]


func _show_popups() -> void:
	_hide_popups()
	if not is_instance_valid(battler) or not popup_container:
		return
	var index := 0
	for vestige in battler.vestiges.get_vestiges():
		var popup := POPUP_SCENE.instantiate()
		popup_container.add_child(popup)
		var stacks := battler.vestiges.get_stacks(vestige)
		var title := vestige.vestige_name if stacks <= 1 else "%s x%d" % [vestige.vestige_name, stacks]
		popup.setup_info(self, title, vestige.description, vestige.icon, index)
		popup.set_bypass_timer(true)
		popup.show_popup()
		active_vestige_popups.append(popup)
		index += 1


func _hide_popups() -> void:
	for popup in active_vestige_popups:
		if is_instance_valid(popup):
			popup.queue_free()
	active_vestige_popups.clear()


func _exit_tree() -> void:
	_hide_popups()
	if is_instance_valid(battler) and battler.vestiges.changed.is_connected(update_vestige_icons):
		battler.vestiges.changed.disconnect(update_vestige_icons)
