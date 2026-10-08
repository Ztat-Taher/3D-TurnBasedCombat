class_name NumberIndicator
extends Control

@export var number_item_scene: PackedScene = preload("res://scenes/battle/effects/number_indicator/number_item.tscn")

# Accumulation settings
@export var max_stack_size: int = 5
@export var stack_offset: Vector2 = Vector2(0, -15)
@export var stack_decay_time: float = 0.5

# Track active numbers by type
var active_numbers: Dictionary = {
	"damage": [],
	"heal": [],
	"xp": [],
	"shield": []
}

var stack_timers: Dictionary = {}

func show_damage(value: int, is_critical: bool = false, is_weakness: bool = false) -> void:
	print("[NumberIndicator] show_damage called: ", value)
	if value <= 0:
		print("[NumberIndicator] Value is 0, skipping")
		return
	
	var item = number_item_scene.instantiate() as NumberItem
	print("[NumberIndicator] NumberItem instantiated: ", item)
	item.number_type = NumberItem.NumberType.DAMAGE
	item.value = value
	item.is_critical = is_critical
	item.is_weakness = is_weakness
	
	add_number_item(item, "damage")

func show_heal(value: int) -> void:
	if value <= 0:
		return
	
	var item = number_item_scene.instantiate() as NumberItem
	item.number_type = NumberItem.NumberType.HEAL
	item.value = value
	
	add_number_item(item, "heal")

func show_xp(value: int) -> void:
	if value <= 0:
		return
	
	var item = number_item_scene.instantiate() as NumberItem
	item.number_type = NumberItem.NumberType.XP
	item.value = value
	
	add_number_item(item, "xp")

func show_shield_break() -> void:
	var item = number_item_scene.instantiate() as NumberItem
	item.number_type = NumberItem.NumberType.SHIELD
	item.value = 0
	
	add_number_item(item, "shield")

func add_number_item(item: NumberItem, type_key: String) -> void:
	# Add to viewport
	add_child(item)
	
	# Force size to match viewport
	item.size = size
	
	# Center the item
	item.position = Vector2(size.x / 2 - item.size.x / 2, size.y / 2 - item.size.y / 2)
	print("[NumberIndicator] Added item at position: ", item.position, " viewport size: ", size)
	
	# Handle stacking
	var stack = active_numbers[type_key]
	
	# If stack is full, remove oldest
	if stack.size() >= max_stack_size:
		var oldest = stack.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()
	
	# Add to stack
	stack.append(item)
	
	# Apply stack offset
	apply_stack_offsets(type_key)
	
	# Start decay timer to gradually reduce stack
	start_stack_decay(type_key)

func apply_stack_offsets(type_key: String) -> void:
	var stack = active_numbers[type_key]
	for i in range(stack.size()):
		var item = stack[i]
		if is_instance_valid(item):
			var offset = stack_offset * i
			item.set_stack_offset(offset)

func start_stack_decay(type_key: String) -> void:
	# Cancel existing timer for this type
	if stack_timers.has(type_key):
		if stack_timers[type_key]:
			stack_timers[type_key].queue_free()
	
	# Create new timer
	var timer = get_tree().create_timer(stack_decay_time)
	timer.timeout.connect(_on_stack_decay.bind(type_key))
	stack_timers[type_key] = timer

func _on_stack_decay(type_key: String) -> void:
	var stack = active_numbers[type_key]
	if stack.size() > 0:
		var oldest = stack.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()
		
		# Reapply offsets
		apply_stack_offsets(type_key)
		
		# Continue decay if more items
		if stack.size() > 0:
			start_stack_decay(type_key)
		else:
			stack_timers.erase(type_key)

func clear_type(type_key: String) -> void:
	var stack = active_numbers[type_key]
	for item in stack:
		if is_instance_valid(item):
			item.queue_free()
	stack.clear()
	
	if stack_timers.has(type_key):
		if stack_timers[type_key]:
			stack_timers[type_key].queue_free()
		stack_timers.erase(type_key)

func clear_all() -> void:
	for type_key in active_numbers:
		clear_type(type_key)
