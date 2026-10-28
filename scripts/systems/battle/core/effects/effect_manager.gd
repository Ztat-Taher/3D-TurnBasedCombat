extends Node
class_name EffectManager

# Central effect coordinator for game feel
# Manages all effect systems and ensures they don't conflict

signal effect_triggered(effect_name: String)
signal all_effects_finished

var screen_flash: ScreenFlash
var time_slow: TimeSlow
var impact_frame: ImpactFrame
var camera_shake_tween: Tween

var active_effects: Array[String] = []
var effect_queue: Array[Dictionary] = []
var is_processing_queue: bool = false
var max_concurrent_effects: int = 3

# Effect priorities (higher = more important)
enum EffectPriority {
	LOW = 0,
	MEDIUM = 1,
	HIGH = 2,
	CRITICAL = 3
}

func _ready() -> void:
	# Initialize effect systems
	# Don't create ScreenFlash - it should be in the HUD
	# We'll get a reference to it via setup_screen_flash()
	
	time_slow = TimeSlow.new()
	add_child(time_slow)
	
	impact_frame = ImpactFrame.new()
	add_child(impact_frame)
	
	# Connect signals to track active effects
	time_slow.time_slow_started.connect(_on_effect_started.bind("time_slow"))
	time_slow.time_slow_finished.connect(_on_effect_finished.bind("time_slow"))
	
	impact_frame.impact_frame_started.connect(_on_effect_started.bind("impact_frame"))
	impact_frame.impact_frame_finished.connect(_on_effect_finished.bind("impact_frame"))

func setup_screen_flash(flash: ScreenFlash) -> void:
	screen_flash = flash
	if screen_flash:
		screen_flash.flash_started.connect(_on_effect_started.bind("screen_flash"))
		screen_flash.flash_finished.connect(_on_effect_finished.bind("screen_flash"))

# Apply camera shake to the battle camera
func apply_camera_shake(duration: float, intensity: float) -> void:
	var battle_manager = get_tree().get_first_node_in_group("battle_manager")
	if not battle_manager or not battle_manager.battle_camera:
		return

	var camera = battle_manager.battle_camera.get_camera()
	if not camera:
		return

	# Cancel existing shake
	if camera_shake_tween and camera_shake_tween.is_valid():
		camera_shake_tween.kill()

	var original_position = camera.global_position
	camera_shake_tween = camera.create_tween()
	camera_shake_tween.set_parallel(true)

	var shake_timer = 0.0
	var update_func = func(delta):
		shake_timer += delta
		if shake_timer >= duration:
			camera.global_position = original_position
			return

		var decay = 1.0 - (shake_timer / duration)
		var current_intensity = intensity * decay

		var shake_offset = Vector3(
			randf_range(-current_intensity, current_intensity),
			randf_range(-current_intensity, current_intensity),
			randf_range(-current_intensity, current_intensity)
		)

		camera.global_position = original_position + shake_offset

	camera_shake_tween.tween_method(update_func, 0.0, duration, duration)
	camera_shake_tween.tween_callback(func():
		camera.global_position = original_position
	)

# Combined effect presets for common combat events

# Normal hit
func trigger_normal_hit() -> void:
	if screen_flash:
		screen_flash.damage_flash(0.08, 0.6)  # Reduced duration and intensity for subtlety
	if impact_frame:
		impact_frame.normal_hit_freeze(0.05)
	apply_camera_shake(0.1, 0.15)  # Light shake for normal hits

# Critical hit
func trigger_critical_hit() -> void:
	if screen_flash:
		screen_flash.critical_flash(0.1, 0.7)  # Reduced duration for subtlety
	if time_slow:
		time_slow.critical_slow(0.15, 0.2)
	if impact_frame:
		impact_frame.critical_freeze(0.1)
	apply_camera_shake(0.2, 0.3)  # Stronger shake for critical hits

# Perfect parry
func trigger_perfect_parry() -> void:
	if screen_flash:
		screen_flash.block_flash(0.1, 0.5)  # Reduced duration for subtlety
	if time_slow:
		time_slow.perfect_parry_slow(0.15, 0.2)
	if impact_frame:
		impact_frame.perfect_parry_freeze(0.15)
	apply_camera_shake(0.15, 0.25)  # Medium shake for perfect parry

# AOE attack
func trigger_aoe_attack() -> void:
	if screen_flash:
		screen_flash.aoe_flash(0.12, 0.5)  # Reduced duration for subtlety
	if impact_frame:
		impact_frame.aoe_freeze(0.1)
	apply_camera_shake(0.2, 0.25)  # Medium shake for AOE

# Big damage
func trigger_big_damage() -> void:
	if screen_flash:
		screen_flash.damage_flash(0.1, 0.5)  # Reduced duration and intensity for subtlety
	if time_slow:
		time_slow.big_damage_slow(0.1, 0.2)
	if impact_frame:
		impact_frame.big_damage_freeze(0.08)
	apply_camera_shake(0.15, 0.25)  # Medium shake for big damage

# Block/parry
func trigger_block() -> void:
	if screen_flash:
		screen_flash.block_flash(0.08, 0.4)  # Reduced duration and intensity for subtlety
	if impact_frame:
		impact_frame.block_freeze(0.05)
	apply_camera_shake(0.08, 0.1)  # Light shake for block

# Dodge
func trigger_dodge() -> void:
	if screen_flash:
		screen_flash.dodge_flash(0.06, 0.3)  # Reduced duration and intensity for subtlety
	if impact_frame:
		impact_frame.dodge_freeze(0.05)
	apply_camera_shake(0.06, 0.08)  # Very light shake for dodge
	# Camera distance adjustment is handled directly in perform_dodge_dash()

# Hit stop - combines time slow and impact freeze for maximum impact
func trigger_hit_stop(duration: float = 0.1, time_scale: float = 0.1) -> void:
	if time_slow:
		time_slow.custom_slow(duration, time_scale)
	if impact_frame:
		impact_frame.custom_freeze(duration)

# Individual effect access
func get_screen_flash() -> ScreenFlash:
	return screen_flash

func get_time_slow() -> TimeSlow:
	return time_slow

func get_impact_frame() -> ImpactFrame:
	return impact_frame

# Node registration for impact frames
func register_impact_node(node: Node) -> void:
	impact_frame.register_node(node)

func unregister_impact_node(node: Node) -> void:
	impact_frame.unregister_node(node)

# Effect queue management
func queue_effect(effect_func: Callable, priority: EffectPriority = EffectPriority.MEDIUM) -> void:
	var effect_data: Dictionary = {
		"function": effect_func,
		"priority": priority,
		"timestamp": Time.get_ticks_msec()
	}
	
	effect_queue.append(effect_data)
	effect_queue.sort_custom(_sort_by_priority)
	
	if not is_processing_queue:
		_process_queue()

func _sort_by_priority(a: Dictionary, b: Dictionary) -> bool:
	return a["priority"] > b["priority"]

func _process_queue() -> void:
	is_processing_queue = true
	
	while effect_queue.size() > 0 and active_effects.size() < max_concurrent_effects:
		var effect_data: Dictionary = effect_queue.pop_front()
		var effect_func: Callable = effect_data["function"]
		
		effect_func.call()
	
	if active_effects.size() == 0 and effect_queue.size() == 0:
		is_processing_queue = false
		all_effects_finished.emit()

func _on_effect_started(effect_name: String) -> void:
	if not active_effects.has(effect_name):
		active_effects.append(effect_name)
	effect_triggered.emit(effect_name)

func _on_effect_finished(effect_name: String) -> void:
	active_effects.erase(effect_name)
	
	if active_effects.size() == 0:
		all_effects_finished.emit()
	
	if is_processing_queue:
		_process_queue()

# Stop all effects immediately
func stop_all_effects() -> void:
	screen_flash.stop_flash()
	time_slow.stop_slow()
	impact_frame.stop_freeze()
	if camera_shake_tween and camera_shake_tween.is_valid():
		camera_shake_tween.kill()
	active_effects.clear()
	effect_queue.clear()
	is_processing_queue = false

# Check if any effects are active
func has_active_effects() -> bool:
	return active_effects.size() > 0

# Get count of active effects
func get_active_effect_count() -> int:
	return active_effects.size()

# Disable/enable specific effect systems
func set_screen_flash_enabled(enabled: bool) -> void:
	screen_flash.process_mode = Node.PROCESS_MODE_INHERIT if enabled else Node.PROCESS_MODE_DISABLED

func set_time_slow_enabled(enabled: bool) -> void:
	time_slow.process_mode = Node.PROCESS_MODE_INHERIT if enabled else Node.PROCESS_MODE_DISABLED

func set_impact_frame_enabled(enabled: bool) -> void:
	impact_frame.process_mode = Node.PROCESS_MODE_INHERIT if enabled else Node.PROCESS_MODE_DISABLED

# Set maximum concurrent effects
func set_max_concurrent_effects(max_val: int) -> void:
	max_concurrent_effects = maxi(1, max_val)
