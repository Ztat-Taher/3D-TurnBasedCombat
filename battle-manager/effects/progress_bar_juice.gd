extends Node
class_name ProgressBarJuice

## Reusable progress bar animation component for game feel
## Adds dual-layer trailing, damage/healing feedback, critical health effects, and text juice to progress bars

# References
@export var main_bar: TextureProgressBar = null
@export var trailing_bar: TextureProgressBar = null  # Damage bar
@export var associated_label: Label = null

# Dual-layer Settings
@export var trail_duration: float = 0.6
@export var trail_ease: Tween.EaseType = Tween.EASE_OUT

# Damage Feedback Settings
@export var enable_damage_feedback: bool = true
@export var damage_flash_color: Color = Color(2.0, 0.2, 0.2, 1.0)
@export var damage_flash_duration: float = 0.06
@export var damage_flash_recovery: float = 0.18
@export var damage_scale_pulse: Vector2 = Vector2(1.08, 1.15)
@export var damage_scale_duration: float = 0.1
@export var damage_scale_recovery: float = 0.15

# Healing Feedback Settings (per-instance configurable)
@export var enable_healing_feedback: bool = false
@export var healing_flash_color: Color = Color(0.2, 2.0, 0.2, 1.0)
@export var healing_flash_duration: float = 0.08
@export var healing_flash_recovery: float = 0.2
@export var healing_scale_growth: Vector2 = Vector2(1.05, 1.1)
@export var healing_scale_duration: float = 0.12
@export var healing_scale_recovery: float = 0.18

# Critical Low Health Settings
@export var enable_critical_health: bool = true
@export var critical_threshold: float = 0.3  # 30% of max health
@export var critical_pulse_color: Color = Color(2.0, 0.5, 0.5, 1.0)
@export var critical_pulse_interval: float = 0.8
@export var critical_pulse_duration: float = 0.3

# Text Juice Settings (configurable)
@export var enable_text_juice: bool = true
@export var enable_text_shake: bool = true
@export var enable_text_pop: bool = true
@export var text_shake_intensity: float = 3.0
@export var text_pop_scale: float = 1.3
@export var text_pop_duration: float = 0.08

# Entrance Settings (available method, container can also animate)
@export var entrance_scale: Vector2 = Vector2(0.7, 0.7)
@export var entrance_duration: float = 0.4
@export var entrance_trans: Tween.TransitionType = Tween.TRANS_BACK

# General Settings
@export var use_easing: bool = true

# Internal state
var previous_value: float = 0.0
var max_value: float = 100.0
var original_bar_modulate: Color
var original_label_position: Vector2
var original_label_scale: Vector2
var critical_health_timer: Timer = null
var is_critical: bool = false

func _ready() -> void:
	# Auto-setup with parent if it has TextureProgressBar children
	var parent = get_parent()
	if parent:
		_auto_setup_from_parent()

func _auto_setup_from_parent() -> void:
	var parent = get_parent()
	if not parent:
		return
	
	# Look for TextureProgressBar children
	var progress_bars: Array[TextureProgressBar] = []
	for child in parent.get_children():
		if child is TextureProgressBar:
			progress_bars.append(child)
	
	# If we have progress bars, set them up
	if progress_bars.size() >= 1:
		main_bar = progress_bars[0]
		if progress_bars.size() >= 2:
			trailing_bar = progress_bars[1]
	
	# Look for Label sibling
	for child in parent.get_children():
		if child is Label:
			associated_label = child
			break
	
	# If we found a main bar, setup with it
	if main_bar:
		setup(main_bar, trailing_bar, associated_label)

func setup(bar: TextureProgressBar, damage_bar: TextureProgressBar = null, label: Label = null) -> void:
	main_bar = bar
	trailing_bar = damage_bar
	associated_label = label
	
	if main_bar:
		previous_value = main_bar.value
		max_value = main_bar.max_value
		original_bar_modulate = main_bar.modulate
		
		# Ensure pivot is centered for nice scaling
		if main_bar.pivot_offset == Vector2.ZERO and main_bar.size != Vector2.ZERO:
			main_bar.pivot_offset = main_bar.size / 2.0
	
	if trailing_bar:
		trailing_bar.value = main_bar.value
		trailing_bar.max_value = main_bar.max_value
		
		# Ensure pivot is centered for nice scaling
		if trailing_bar.pivot_offset == Vector2.ZERO and trailing_bar.size != Vector2.ZERO:
			trailing_bar.pivot_offset = trailing_bar.size / 2.0
	
	if associated_label:
		original_label_position = associated_label.position
		original_label_scale = associated_label.scale
	
	# Setup critical health timer
	_setup_critical_timer()

func _setup_critical_timer() -> void:
	if critical_health_timer:
		critical_health_timer.queue_free()
	
	critical_health_timer = Timer.new()
	critical_health_timer.wait_time = critical_pulse_interval
	critical_health_timer.autostart = false
	critical_health_timer.one_shot = false
	add_child(critical_health_timer)
	critical_health_timer.timeout.connect(_on_critical_pulse)

func update_value(new_value: float, new_max: float) -> void:
	if not main_bar:
		return
	
	var old_value = previous_value
	previous_value = new_value
	max_value = new_max
	
	# Update main bar instantly
	main_bar.max_value = max_value
	main_bar.value = new_value
	
	# Update trailing bar with animation
	if trailing_bar:
		trailing_bar.max_value = max_value
		var trail_tween := create_tween()
		trail_tween.tween_property(trailing_bar, "value", new_value, trail_duration)
		if use_easing:
			trail_tween.set_ease(trail_ease)
	
	# Check for damage (value decreased)
	if new_value < old_value and enable_damage_feedback:
		_animate_damage_feedback()
	
	# Check for healing (value increased)
	elif new_value > old_value and enable_healing_feedback:
		_animate_healing_feedback()
	
	# Update critical health state
	_update_critical_health(new_value)
	
	# Update label text if provided
	if associated_label:
		associated_label.text = "%d / %d" % [int(new_value), int(max_value)]

func _animate_damage_feedback() -> void:
	if not main_bar:
		return
	
	var tween = create_tween()
	tween.set_parallel(true)
	
	# Red flash
	if use_easing:
		tween.set_ease(Tween.EASE_OUT)
	
	tween.tween_property(main_bar, "modulate", damage_flash_color, damage_flash_duration)
	tween.tween_property(main_bar, "modulate", original_bar_modulate, damage_flash_recovery)
	
	# Scale pulse
	var scale_tween = create_tween()
	scale_tween.tween_property(main_bar, "scale", damage_scale_pulse, damage_scale_duration).set_ease(Tween.EASE_OUT)
	scale_tween.tween_property(main_bar, "scale", Vector2.ONE, damage_scale_recovery).set_ease(Tween.EASE_IN)
	
	# Text juice
	if enable_text_juice and associated_label:
		_animate_text_damage()

func _animate_healing_feedback() -> void:
	if not main_bar:
		return
	
	var tween = create_tween()
	tween.set_parallel(true)
	
	# Green flash
	if use_easing:
		tween.set_ease(Tween.EASE_OUT)
	
	tween.tween_property(main_bar, "modulate", healing_flash_color, healing_flash_duration)
	tween.tween_property(main_bar, "modulate", original_bar_modulate, healing_flash_recovery)
	
	# Scale growth
	var scale_tween = create_tween()
	scale_tween.tween_property(main_bar, "scale", healing_scale_growth, healing_scale_duration).set_ease(Tween.EASE_OUT)
	scale_tween.tween_property(main_bar, "scale", Vector2.ONE, healing_scale_recovery).set_ease(Tween.EASE_IN)
	
	# Text juice
	if enable_text_juice and associated_label:
		_animate_text_healing()

func _animate_text_damage() -> void:
	if not associated_label:
		return
	
	if enable_text_shake:
		var original_pos = original_label_position
		var shake_tween = create_tween()
		shake_tween.tween_property(associated_label, "position:x", original_pos.x + text_shake_intensity, 0.05)
		shake_tween.tween_property(associated_label, "position:x", original_pos.x - text_shake_intensity, 0.05)
		shake_tween.tween_property(associated_label, "position:x", original_pos.x, 0.05)
	
	if enable_text_pop:
		var pop_tween = create_tween()
		pop_tween.tween_property(associated_label, "scale", original_label_scale * text_pop_scale, text_pop_duration).set_ease(Tween.EASE_OUT)
		pop_tween.tween_property(associated_label, "scale", original_label_scale, text_pop_duration * 1.5).set_ease(Tween.EASE_IN)

func _animate_text_healing() -> void:
	if not associated_label:
		return
	
	if enable_text_pop:
		var pop_tween = create_tween()
		pop_tween.tween_property(associated_label, "scale", original_label_scale * text_pop_scale, text_pop_duration).set_ease(Tween.EASE_OUT)
		pop_tween.tween_property(associated_label, "scale", original_label_scale, text_pop_duration * 1.5).set_ease(Tween.EASE_IN)

func _update_critical_health(current_value: float) -> void:
	if not enable_critical_health or max_value == 0:
		_stop_critical_health()
		return
	
	var health_percentage = current_value / max_value
	var should_be_critical = health_percentage <= critical_threshold
	
	if should_be_critical and not is_critical:
		_start_critical_health()
	elif not should_be_critical and is_critical:
		_stop_critical_health()

func _start_critical_health() -> void:
	is_critical = true
	if critical_health_timer and not critical_health_timer.is_stopped():
		return
	
	if critical_health_timer:
		critical_health_timer.start()
		_on_critical_pulse()  # Immediate pulse

func _stop_critical_health() -> void:
	is_critical = false
	if critical_health_timer:
		critical_health_timer.stop()
	
	if main_bar:
		main_bar.modulate = original_bar_modulate

func _on_critical_pulse() -> void:
	if not main_bar or not is_critical:
		return
	
	var tween = create_tween()
	tween.tween_property(main_bar, "modulate", critical_pulse_color, critical_pulse_duration * 0.5)
	tween.tween_property(main_bar, "modulate", original_bar_modulate, critical_pulse_duration * 0.5)

func animate_entrance() -> void:
	if not main_bar:
		return
	
	# Set initial state first
	main_bar.modulate.a = 0.0
	main_bar.scale = entrance_scale
	
	var tween = create_tween()
	tween.set_parallel(true)
	
	if use_easing:
		tween.set_ease(Tween.EASE_OUT)
	
	tween.tween_property(main_bar, "modulate:a", 1.0, entrance_duration)
	tween.tween_property(main_bar, "scale", Vector2.ONE, entrance_duration).set_trans(entrance_trans)

func animate_exit() -> void:
	if not main_bar:
		return
	
	var tween = create_tween()
	tween.set_parallel(true)
	
	if use_easing:
		tween.set_ease(Tween.EASE_IN)
	
	tween.tween_property(main_bar, "modulate:a", 0.0, entrance_duration * 0.8)
	tween.tween_property(main_bar, "scale", entrance_scale, entrance_duration * 0.8)

func animate_pop(intensity: float = 1.0) -> void:
	if not main_bar:
		return
	
	var tween = create_tween()
	var pop_scale = Vector2.ONE * (1.1 * intensity)
	tween.tween_property(main_bar, "scale", pop_scale, 0.1).set_ease(Tween.EASE_OUT)
	tween.tween_property(main_bar, "scale", Vector2.ONE, 0.15).set_ease(Tween.EASE_IN)

func set_critical_health_enabled(enabled: bool) -> void:
	enable_critical_health = enabled
	if not enabled:
		_stop_critical_health()

func reset_to_original() -> void:
	if main_bar:
		main_bar.scale = Vector2.ONE
		main_bar.modulate = original_bar_modulate
	
	if trailing_bar:
		trailing_bar.scale = Vector2.ONE
		trailing_bar.modulate = original_bar_modulate
	
	if associated_label:
		associated_label.position = original_label_position
		associated_label.scale = original_label_scale
	
	_stop_critical_health()

func _exit_tree() -> void:
	if critical_health_timer:
		critical_health_timer.queue_free()
