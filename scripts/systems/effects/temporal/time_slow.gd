extends Node
class_name TimeSlow

# Time slow (hit stop) system for game feel
# Temporarily slows down game time scale for impact moments

signal time_slow_started
signal time_slow_finished

var slow_tween: Tween
var is_slowing: bool = false
var original_time_scale: float = 1.0

# Slow presets
enum SlowType {
	CRITICAL,      # Slow for critical hits
	BIG_DAMAGE,    # Slow for big damage
	AOE,           # Slow for AOE attacks
	PERFECT_PARRY, # Slow for perfect parry
	CUSTOM         # Custom slow
}

func _ready() -> void:
	original_time_scale = Engine.time_scale

# Critical hit slow
func critical_slow(duration: float = 0.15, time_scale: float = 0.2) -> void:
	_start_slow(duration, time_scale)

# Big damage slow
func big_damage_slow(duration: float = 0.1, time_scale: float = 0.3) -> void:
	_start_slow(duration, time_scale)

# AOE slow
func aoe_slow(duration: float = 0.2, time_scale: float = 0.15) -> void:
	_start_slow(duration, time_scale)

# Perfect parry slow
func perfect_parry_slow(duration: float = 0.15, time_scale: float = 0.2) -> void:
	_start_slow(duration, time_scale)

# Custom slow with full control
func custom_slow(duration: float, time_scale: float) -> void:
	_start_slow(duration, time_scale)

func _start_slow(duration: float, target_time_scale: float) -> void:
	# Cancel any existing slow
	if slow_tween and slow_tween.is_valid():
		slow_tween.kill()
	
	is_slowing = true
	time_slow_started.emit()
	
	# Gradual slowdown
	slow_tween = create_tween()
	slow_tween.set_parallel(false)
	
	# Slow down
	var slowdown_duration: float = duration * 0.3
	slow_tween.tween_property(Engine, "time_scale", target_time_scale, slowdown_duration)
	
	# Hold at slow speed
	var hold_duration: float = duration * 0.4
	slow_tween.tween_interval(hold_duration)
	
	# Speed up back to normal
	var speedup_duration: float = duration * 0.3
	slow_tween.tween_property(Engine, "time_scale", original_time_scale, speedup_duration)
	
	slow_tween.tween_callback(_on_slow_finished)

func _on_slow_finished() -> void:
	is_slowing = false
	Engine.time_scale = original_time_scale
	time_slow_finished.emit()

func stop_slow() -> void:
	if slow_tween and slow_tween.is_valid():
		slow_tween.kill()
	is_slowing = false
	Engine.time_scale = original_time_scale
	time_slow_finished.emit()

# Instant slow (no gradual transition)
func instant_slow(duration: float, time_scale: float) -> void:
	if slow_tween and slow_tween.is_valid():
		slow_tween.kill()
	
	is_slowing = true
	time_slow_started.emit()
	
	Engine.time_scale = time_scale
	
	slow_tween = create_tween()
	slow_tween.tween_interval(duration)
	slow_tween.tween_callback(_restore_time_scale)

func _restore_time_scale() -> void:
	Engine.time_scale = original_time_scale
	is_slowing = false
	time_slow_finished.emit()

# Slow with custom curve
func slow_with_curve(duration: float, target_time_scale: float, curve: Tween.TransitionType) -> void:
	if slow_tween and slow_tween.is_valid():
		slow_tween.kill()
	
	is_slowing = true
	time_slow_started.emit()
	
	slow_tween = create_tween()
	slow_tween.set_trans(curve)
	
	var slowdown_duration: float = duration * 0.3
	slow_tween.tween_property(Engine, "time_scale", target_time_scale, slowdown_duration)
	
	var hold_duration: float = duration * 0.4
	slow_tween.tween_interval(hold_duration)
	
	var speedup_duration: float = duration * 0.3
	slow_tween.tween_property(Engine, "time_scale", original_time_scale, speedup_duration)
	
	slow_tween.tween_callback(_on_slow_finished)

# Set a new original time scale (for when game speed changes)
func set_original_time_scale(new_scale: float) -> void:
	original_time_scale = new_scale
	if not is_slowing:
		Engine.time_scale = original_time_scale
