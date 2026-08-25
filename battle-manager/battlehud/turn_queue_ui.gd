class_name TurnQueueUI
extends Control

@export var turn_queue_card_scene: PackedScene
@export var turn_queue_card_wrapper_scene: PackedScene

@onready var scroll_container: ScrollContainer = $ScrollContainer
@onready var queue_container: VBoxContainer = $ScrollContainer/QueueContainer
@onready var container_juice: ContainerJuice = $ScrollContainer/QueueContainer/ContainerJuice

var current_turn_order: Array = []
var current_turn_idx: int = 0
var _battler_to_wrapper: Dictionary = {} # Battler -> wrapper Control

func _ready() -> void:
	# Set default scenes if not assigned
	if not turn_queue_card_scene:
		turn_queue_card_scene = preload("res://battle-manager/battlehud/turn_queue_card.tscn")
	if not turn_queue_card_wrapper_scene:
		turn_queue_card_wrapper_scene = preload("res://battle-manager/battlehud/turn_queue_card_wrapper.tscn")

func update_queue(turn_order: Array, turn_idx: int) -> void:
	current_turn_order = turn_order
	current_turn_idx = turn_idx
	
	if not queue_container:
		print("TurnQueueUI: queue_container is null!")
		return
	
	if turn_order.is_empty():
		_clear_all_cards()
		return
	
	if not turn_queue_card_scene:
		push_error("Turn queue card scene not loaded!")
		return
	
	if not turn_queue_card_wrapper_scene:
		push_error("Turn queue card wrapper scene not loaded!")
		return
	
	var new_battlers: Array = []
	var current_battlers: Array = _battler_to_wrapper.keys()
	
	# Identify new battlers to add
	for battler in turn_order:
		if not is_instance_valid(battler) or battler.is_defeated():
			continue
		if not _battler_to_wrapper.has(battler):
			new_battlers.append(battler)
	
	# Identify old battlers to remove
	var old_battlers: Array = []
	for battler in current_battlers:
		if not is_instance_valid(battler):
			old_battlers.append(battler)
			continue
		if battler.is_defeated() or not turn_order.has(battler):
			old_battlers.append(battler)
	
	# Identify the single card that moved from front to back (reordering)
	var reordered_battler = null
	var active_battler = null
	var total = turn_order.size()
	if total > 0:
		# The battler that was at the front in the previous turn should now be at the back
		var prev_front_idx = (current_turn_idx - 1 + total) % total
		var prev_front_battler = turn_order[prev_front_idx]
		if prev_front_battler and _battler_to_wrapper.has(prev_front_battler):
			var wrapper = _battler_to_wrapper.get(prev_front_battler)
			var current_index = queue_container.get_children().find(wrapper)
			# If it was at position 0 and is now at the last position, it's reordering
			if current_index == 0 and prev_front_idx != 0:
				reordered_battler = prev_front_battler
		
		# Identify the current active battler (at position 0 in the new order)
		active_battler = turn_order[turn_idx]
	
	# Update card states and reorder FIRST (before animation)
	for i in range(total):
		var idx = (turn_idx + i) % total
		var battler = turn_order[idx]
		if not is_instance_valid(battler) or battler.is_defeated():
			continue
		
		var wrapper = _battler_to_wrapper.get(battler)
		if not wrapper or not is_instance_valid(wrapper):
			continue
		
		var is_current = (i == 0)
		
		# Update the card's state
		for child in wrapper.get_children():
			if child is TurnQueueCard:
				child.setup(battler, is_current)
		
		# Move wrapper to correct position
		var current_index = queue_container.get_children().find(wrapper)
		if current_index != i:
			queue_container.move_child(wrapper, i)
	
	# Force layout update after state changes
	await get_tree().process_frame
	queue_container.queue_sort()
	
	# Animate out old cards individually
	for battler in old_battlers:
		var wrapper = _battler_to_wrapper.get(battler)
		if wrapper and container_juice:
			for child in wrapper.get_children():
				if child is Control:
					container_juice.disappear_sibling(child)
	
	# Animate out the reordered card individually
	if reordered_battler and container_juice:
		var wrapper = _battler_to_wrapper.get(reordered_battler)
		if wrapper:
			for child in wrapper.get_children():
				if child is Control:
					container_juice.disappear_sibling(child)
	
	# Wait for disappear animations
	if not old_battlers.is_empty() or reordered_battler:
		await get_tree().create_timer(container_juice.disappear_duration).timeout
	
	# Remove old wrappers
	for battler in old_battlers:
		var wrapper = _battler_to_wrapper.get(battler)
		if wrapper and is_instance_valid(wrapper):
			_battler_to_wrapper.erase(battler)
			queue_container.remove_child(wrapper)
			wrapper.queue_free()
	
	# Add new cards
	for battler in new_battlers:
		# Create wrapper
		var wrapper = turn_queue_card_wrapper_scene.instantiate()
		_battler_to_wrapper[battler] = wrapper
		queue_container.add_child(wrapper)
		
		# Create card inside wrapper
		var card = turn_queue_card_scene.instantiate()
		if card is TurnQueueCard:
			wrapper.add_child(card)
		else:
			push_error("Instantiated node is not a TurnQueueCard!")
	
	# Re-apply states to new cards (since they were just created)
	for battler in new_battlers:
		var wrapper = _battler_to_wrapper.get(battler)
		if wrapper:
			for i in range(total):
				var idx = (turn_idx + i) % total
				if turn_order[idx] == battler:
					var is_current = (i == 0)
					for child in wrapper.get_children():
						if child is TurnQueueCard:
							child.setup(battler, is_current)
	
	# Animate in new cards individually
	for battler in new_battlers:
		var wrapper = _battler_to_wrapper.get(battler)
		if wrapper and container_juice:
			for child in wrapper.get_children():
				if child is Control:
					container_juice.appear_sibling(child)
	
	# Animate in the reordered card individually
	if reordered_battler and container_juice:
		var wrapper = _battler_to_wrapper.get(reordered_battler)
		if wrapper:
			for child in wrapper.get_children():
				if child is Control:
					container_juice.appear_sibling(child)
	
	# Animate in the active card individually (if not already animated)
	if active_battler and active_battler != reordered_battler and container_juice:
		var wrapper = _battler_to_wrapper.get(active_battler)
		if wrapper:
			for child in wrapper.get_children():
				if child is Control:
					container_juice.appear_sibling(child)

func _clear_all_cards() -> void:
	if container_juice:
		container_juice.kill()
	
	for battler in _battler_to_wrapper.keys():
		var wrapper = _battler_to_wrapper[battler]
		if wrapper and is_instance_valid(wrapper):
			queue_container.remove_child(wrapper)
			wrapper.queue_free()
	
	_battler_to_wrapper.clear()

func get_queue_container() -> VBoxContainer:
	return queue_container

func get_container_juice() -> ContainerJuice:
	return container_juice
