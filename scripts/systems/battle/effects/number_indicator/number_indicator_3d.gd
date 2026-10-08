class_name NumberIndicator3D
extends Node3D

@export var number_item_scene: PackedScene = preload("res://scenes/battle/effects/number_indicator/number_item.tscn")

var active_numbers: Array = []

func show_damage(value: int, is_critical: bool = false, is_weakness: bool = false) -> void:
	if value <= 0:
		return
	
	var item = number_item_scene.instantiate() as NumberItem
	item.number_type = NumberItem.NumberType.DAMAGE
	item.value = value
	item.is_critical = is_critical
	item.is_weakness = is_weakness
	
	spawn_number_item(item)

func show_heal(value: int) -> void:
	if value <= 0:
		return
	
	var item = number_item_scene.instantiate() as NumberItem
	item.number_type = NumberItem.NumberType.HEAL
	item.value = value
	
	spawn_number_item(item)

func show_xp(value: int) -> void:
	if value <= 0:
		return
	
	var item = number_item_scene.instantiate() as NumberItem
	item.number_type = NumberItem.NumberType.XP
	item.value = value
	
	spawn_number_item(item)

func show_shield_break() -> void:
	var item = number_item_scene.instantiate() as NumberItem
	item.number_type = NumberItem.NumberType.SHIELD
	item.value = 0
	
	spawn_number_item(item)

func spawn_number_item(item: NumberItem) -> void:
	# Create a Label3D for each number (simpler than SubViewport approach)
	var label = Label3D.new()
	label.text = item.get_display_text()
	var font = load("res://assets/fonts/tinyRPGFontKit01_v1_2/TinyRPG-BadgeFont.ttf")
	if font:
		label.font = font
	label.outline_size = 8
	label.outline_modulate = Color.BLACK
	label.pixel_size = 0.025  # Increased for better visibility
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = item.get_color()
	label.position = Vector3(0, 3.5, 0)  # Position above battler
	
	# Add animation
	label.position.y = 3.0
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", 4.5, 1.0)
	tween.tween_property(label, "modulate:a", 0.0, 1.0)
	tween.chain().tween_callback(func(): label.queue_free())
	
	add_child(label)
	
	# Free the item as it was only used as a data container
	item.free()
