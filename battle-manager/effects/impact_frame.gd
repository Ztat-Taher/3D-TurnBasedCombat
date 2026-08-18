extends Node
class_name ImpactFrame

# Impact frame system for game feel
# Briefly freezes character animation at impact moment

signal impact_frame_started
signal impact_frame_finished

var frozen_nodes: Array[Node] = []
var freeze_timer: Timer
var is_frozen: bool = false

# Freeze presets
enum FreezeType {
	NORMAL,        # Short freeze for normal hits
	CRITICAL,      # Longer freeze for critical hits
	PERFECT_PARRY, # Long freeze for perfect parry
	QTE_SUCCESS,   # Freeze for QTE success moments
	CUSTOM         # Custom freeze duration
}

func _ready() -> void:
	freeze_timer = Timer.new()
	freeze_timer.one_shot = true
	freeze_timer.timeout.connect(_on_freeze_finished)
	add_child(freeze_timer)

# Normal hit freeze
func normal_hit_freeze(duration: float = 0.05) -> void:
	_start_freeze(duration)

# Critical hit freeze
func critical_freeze(duration: float = 0.1) -> void:
	_start_freeze(duration)

# Perfect parry freeze
func perfect_parry_freeze(duration: float = 0.15) -> void:
	_start_freeze(duration)

# QTE success freeze
func qte_success_freeze(duration: float = 0.12) -> void:
	_start_freeze(duration)

# Big damage freeze
func big_damage_freeze(duration: float = 0.08) -> void:
	_start_freeze(duration)

# AOE freeze
func aoe_freeze(duration: float = 0.1) -> void:
	_start_freeze(duration)

# Block/parry freeze
func block_freeze(duration: float = 0.05) -> void:
	_start_freeze(duration)

# Dodge freeze
func dodge_freeze(duration: float = 0.05) -> void:
	_start_freeze(duration)

# Custom freeze with full control
func custom_freeze(duration: float) -> void:
	_start_freeze(duration)

func _start_freeze(duration: float) -> void:
	if is_frozen:
		return
	
	is_frozen = true
	impact_frame_started.emit()
	
	# Freeze all registered nodes
	for node in frozen_nodes:
		if node.has_method("set_process_mode"):
			node.set_process_mode(Node.PROCESS_MODE_DISABLED)
		elif node is AnimationPlayer:
			node.pause()
		elif node is Sprite2D or node is Sprite3D:
			node.set_process(false)
	
	freeze_timer.wait_time = duration
	freeze_timer.start()

func _on_freeze_finished() -> void:
	_unfreeze()

func _unfreeze() -> void:
	if not is_frozen:
		return
	
	# Unfreeze all registered nodes
	for node in frozen_nodes:
		if node.has_method("set_process_mode"):
			node.set_process_mode(Node.PROCESS_MODE_INHERIT)
		elif node is AnimationPlayer:
			node.play()
		elif node is Sprite2D or node is Sprite3D:
			node.set_process(true)
	
	is_frozen = false
	impact_frame_finished.emit()

# Register a node to be frozen during impact frames
func register_node(node: Node) -> void:
	if not frozen_nodes.has(node):
		frozen_nodes.append(node)

# Unregister a node from impact frame freezing
func unregister_node(node: Node) -> void:
	frozen_nodes.erase(node)

# Freeze a specific node immediately
func freeze_node(node: Node, duration: float) -> void:
	if not is_frozen:
		_start_freeze(duration)
	
	# Add this node to the frozen list if not already
	if not frozen_nodes.has(node):
		register_node(node)

# Freeze multiple nodes at once
func freeze_nodes(nodes: Array[Node], duration: float) -> void:
	for node in nodes:
		register_node(node)
	
	if not is_frozen:
		_start_freeze(duration)

# Stop all freezing immediately
func stop_freeze() -> void:
	if freeze_timer:
		freeze_timer.stop()
	_unfreeze()

# Check if a specific node is frozen
func is_node_frozen(node: Node) -> bool:
	return is_frozen and frozen_nodes.has(node)

# Clear all registered nodes
func clear_registered_nodes() -> void:
	if is_frozen:
		stop_freeze()
	frozen_nodes.clear()
