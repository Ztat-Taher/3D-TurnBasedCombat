class_name ContainerJuice
extends Node

## Reusable UI juice component for containers (VBoxContainer, HBoxContainer, BoxContainer, etc.)
## Animates the appearance and disappearance of direct sibling Control nodes.

enum SlideDirection {
	FROM_LEFT,
	FROM_RIGHT,
	FROM_TOP,
	FROM_BOTTOM,
	CUSTOM
}

# Signals
signal appear_started
signal appear_finished
signal disappear_started
signal disappear_finished

# Appearance Settings
@export_group("Appear Animation")
@export var appear_slide_direction: SlideDirection = SlideDirection.FROM_LEFT
@export var appear_slide_distance: float = 60.0
@export var appear_custom_offset: Vector2 = Vector2(-60.0, 0.0)
@export var appear_duration: float = 0.25
@export var appear_stagger_delay: float = 0.04
@export var appear_fade: bool = true
@export var appear_bounce: bool = false
@export var appear_bounce_scale: float = 1.15
@export var appear_trans_type: Tween.TransitionType = Tween.TRANS_BACK
@export var appear_ease_type: Tween.EaseType = Tween.EASE_OUT

# Disappearance Settings
@export_group("Disappear Animation")
@export var disappear_slide_direction: SlideDirection = SlideDirection.FROM_RIGHT
@export var disappear_slide_distance: float = 60.0
@export var disappear_custom_offset: Vector2 = Vector2(60.0, 0.0)
@export var disappear_duration: float = 0.18
@export var disappear_stagger_delay: float = 0.03
@export var disappear_reverse_order: bool = true
@export var disappear_fade: bool = true
@export var disappear_scale_down: bool = false
@export var disappear_target_scale: float = 0.8
@export var disappear_trans_type: Tween.TransitionType = Tween.TRANS_QUAD
@export var disappear_ease_type: Tween.EaseType = Tween.EASE_IN

# General Settings
@export_group("General")
@export var auto_appear_on_ready: bool = false
@export var start_hidden: bool = true
@export var ignore_non_visible_nodes: bool = false

var current_tween: Tween
var _sibling_tweens: Dictionary = {} # Control -> Tween
var _sibling_base_scales: Dictionary = {} # Control -> Vector2
var _sibling_baseline_positions: Dictionary = {} # Control -> Vector2 (true baseline position at scene load)
var _sibling_offsets: Dictionary = {} # Control -> Vector2
var _sibling_hidden_states: Dictionary = {} # Control -> bool (tracks if button is logically hidden)
var _parent_is_container: bool = false  # Check if parent is a Container node

func _ready() -> void:
	# Check if parent is a container
	var parent = get_parent()
	_parent_is_container = parent is Container
	
	# Always cache baseline positions (including container-managed positions)
	_cache_baseline_positions()
	
	_cache_siblings()
	if start_hidden:
		set_hidden_state()
	if auto_appear_on_ready:
		appear()

## Cache baseline positions at scene load time (before any animations)
func _cache_baseline_positions() -> void:
	for sibling in get_target_siblings():
		if not _sibling_baseline_positions.has(sibling):
			# For wrapper pattern, cache position relative to wrapper
			_sibling_baseline_positions[sibling] = sibling.position

## Helper to ensure baseline position is cached for a sibling
func _ensure_baseline_cached(sibling: Control) -> void:
	if not _sibling_baseline_positions.has(sibling):
		_sibling_baseline_positions[sibling] = sibling.position

## Force recaching of siblings (for dynamic content)
func recache_siblings() -> void:
	_cache_baseline_positions()
	_cache_siblings()

## Force container to recalculate layout
func _recalculate_container_layout() -> void:
	if _parent_is_container:
		var parent = get_parent()
		if parent is Container:
			parent.queue_sort()

## Cache original scale of sibling controls
func _cache_siblings() -> void:
	for sibling in get_target_siblings():
		if not _sibling_base_scales.has(sibling):
			var s = sibling.scale
			if s.length_squared() < 0.1:
				s = Vector2.ONE
			_sibling_base_scales[sibling] = s
		if not _sibling_offsets.has(sibling):
			_sibling_offsets[sibling] = Vector2.ZERO
		if not _sibling_hidden_states.has(sibling):
			_sibling_hidden_states[sibling] = not sibling.visible or sibling.modulate.a < 0.9

## Returns all direct sibling Controls that should be animated
func get_target_siblings() -> Array[Control]:
	var siblings: Array[Control] = []
	var parent = get_parent()
	if not parent:
		return siblings
		
	for child in parent.get_children():
		if child is Control and child != self:
			if ignore_non_visible_nodes and not child.visible:
				continue
			
			# Check if this is a wrapper Control (has one animated child)
			# If so, animate the child instead of the wrapper
			var animated_child = _get_animated_child(child)
			if animated_child:
				siblings.append(animated_child)
			else:
				siblings.append(child)
	return siblings

## Helper to get the actual child to animate (for wrapper Control pattern)
func _get_animated_child(wrapper: Control) -> Control:
	# If wrapper has exactly one Control child that's not container_juice, animate that
	var control_children: Array[Control] = []
	for child in wrapper.get_children():
		if child is Control:
			control_children.append(child)
	
	# If exactly one Control child and it's not the container_juice itself, use it
	if control_children.size() == 1 and control_children[0] != self:
		return control_children[0]
	
	# Also check for TurnQueueCard specifically (multiple children but main card)
	for child in wrapper.get_children():
		# Check if it's a TurnQueueCard by checking if it has the expected script or class
		if child.has_method("setup") and child.has_method("apply_style"):
			# This is likely a TurnQueueCard based on the methods it has
			return child
	
	# Fallback: use the first Control child that's not container_juice
	for child in wrapper.get_children():
		if child is Control and child != self:
			return child
	
	return null

## Calculate offset vector based on direction and distance
func _get_slide_offset(direction: SlideDirection, distance: float, custom: Vector2) -> Vector2:
	match direction:
		SlideDirection.FROM_LEFT:
			return Vector2(-distance, 0)
		SlideDirection.FROM_RIGHT:
			return Vector2(distance, 0)
		SlideDirection.FROM_TOP:
			return Vector2(0, -distance)
		SlideDirection.FROM_BOTTOM:
			return Vector2(0, distance)
		SlideDirection.CUSTOM:
			return custom
	return Vector2.ZERO

func _apply_sibling_offset(sibling: Control, offset: Vector2) -> void:
	if not sibling or not is_instance_valid(sibling):
		return
		
	_sibling_offsets[sibling] = offset
	
	# For containers, skip position animation entirely (interferes with layout)
	# For non-containers, use absolute position with baseline
	if not _parent_is_container:
		var baseline: Vector2 = _sibling_baseline_positions.get(sibling, sibling.position)
		sibling.position = baseline + offset
	# For containers with wrapper pattern, still animate position relative to wrapper
	elif _parent_is_container and sibling.get_parent() and sibling.get_parent() is Control and sibling.get_parent() != get_parent():
		# Button is inside a wrapper Control, animate relative to wrapper
		var baseline: Vector2 = _sibling_baseline_positions.get(sibling, sibling.position)
		sibling.position = baseline + offset

## Instantly snaps siblings into their hidden/pre-appear state
func set_hidden_state() -> void:
	_kill_current_tween()
	var offset = _get_slide_offset(appear_slide_direction, appear_slide_distance, appear_custom_offset)
	for sibling in get_target_siblings():
		_kill_sibling_tween(sibling)
		var base_scale: Vector2 = _sibling_base_scales.get(sibling, Vector2.ONE)
		_sibling_hidden_states[sibling] = true
		
		# Apply the appear offset from baseline
		_sibling_offsets[sibling] = offset
		_apply_sibling_offset(sibling, offset)
		
		if appear_fade:
			sibling.modulate.a = 0.0
		if appear_bounce:
			sibling.scale = base_scale * 0.7

## Instantly snaps siblings into their fully visible/reset state
func set_shown_state() -> void:
	_kill_current_tween()
	for sibling in get_target_siblings():
		_kill_sibling_tween(sibling)
		var base_scale: Vector2 = _sibling_base_scales.get(sibling, Vector2.ONE)
		_sibling_hidden_states[sibling] = false
		sibling.modulate.a = 1.0
		sibling.scale = base_scale
		
		# Reset to baseline position
		_sibling_offsets[sibling] = Vector2.ZERO
		if not _parent_is_container:
			var baseline_pos: Vector2 = _sibling_baseline_positions.get(sibling, sibling.position)
			sibling.position = baseline_pos
		elif _parent_is_container and sibling.get_parent() and sibling.get_parent() is Control and sibling.get_parent() != get_parent():
			# Button is inside wrapper, reset relative to wrapper
			var baseline_pos: Vector2 = _sibling_baseline_positions.get(sibling, sibling.position)
			sibling.position = baseline_pos

## Animate all siblings (or currently hidden ones) sliding/fading in with cascading queue
func appear(only_hidden: bool = false) -> void:
	_kill_current_tween()
	_cache_siblings()
	
	var all_siblings = get_target_siblings()
	var siblings: Array[Control] = []
	
	for s in all_siblings:
		if only_hidden:
			# Check if sibling is logically hidden (not visible or faded out)
			var is_hidden = not s.visible or s.modulate.a < 0.9
			if is_hidden:
				siblings.append(s)
		else:
			siblings.append(s)
			
	if siblings.is_empty():
		return
		
	appear_started.emit()
	current_tween = create_tween()
	current_tween.set_parallel(true)
	
	var offset = _get_slide_offset(appear_slide_direction, appear_slide_distance, appear_custom_offset)
	
	for i in range(siblings.size()):
		var sibling = siblings[i]
		_kill_sibling_tween(sibling)
		var delay = i * appear_stagger_delay
		var base_scale: Vector2 = _sibling_base_scales.get(sibling, Vector2.ONE)
		
		# Mark as not hidden
		_sibling_hidden_states[sibling] = false
		
		# Ensure visible
		sibling.visible = true
		
		# Set initial state for this appearance
		if appear_fade:
			sibling.modulate.a = 0.0
			current_tween.tween_property(sibling, "modulate:a", 1.0, appear_duration).set_delay(delay)
		
		# Snap to the appear offset from baseline
		_sibling_offsets[sibling] = offset
		_apply_sibling_offset(sibling, offset)
		
		# Cascading animate visual offset back to (0, 0)
		var slide_t = current_tween.tween_method(
			func(current_offset: Vector2): _apply_sibling_offset(sibling, current_offset),
			offset,
			Vector2.ZERO,
			appear_duration
		)
		slide_t.set_delay(delay).set_trans(appear_trans_type).set_ease(appear_ease_type)
		
		# Animate scale bounce if enabled
		if appear_bounce:
			sibling.scale = base_scale * 0.7
			var bounce_up_duration = appear_duration * 0.4
			var bounce_down_duration = appear_duration * 0.6
			
			var bounce_t1 = current_tween.tween_property(sibling, "scale", base_scale * appear_bounce_scale, bounce_up_duration)
			bounce_t1.set_delay(delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			
			var bounce_t2 = current_tween.tween_property(sibling, "scale", base_scale, bounce_down_duration)
			bounce_t2.set_delay(delay + bounce_up_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	
	current_tween.finished.connect(func():
		for sibling in siblings:
			# Reset to baseline position
			_sibling_offsets[sibling] = Vector2.ZERO
			if not _parent_is_container:
				var baseline_pos: Vector2 = _sibling_baseline_positions.get(sibling, sibling.position)
				sibling.position = baseline_pos
			elif _parent_is_container and sibling.get_parent() and sibling.get_parent() is Control and sibling.get_parent() != get_parent():
				# Button is inside wrapper, reset relative to wrapper
				var baseline_pos: Vector2 = _sibling_baseline_positions.get(sibling, sibling.position)
				sibling.position = baseline_pos
			_sibling_hidden_states[sibling] = false
		appear_finished.emit()
	, CONNECT_ONE_SHOT)

## Animate all siblings (or currently shown ones) sliding/fading out with cascading queue
func disappear(only_visible: bool = false) -> void:
	_kill_current_tween()
	_cache_siblings()
	
	var all_siblings = get_target_siblings()
	var siblings: Array[Control] = []
	
	for s in all_siblings:
		if only_visible:
			# Check if sibling is logically visible (visible, not faded out, and not marked as hidden)
			var is_visible = s.visible and s.modulate.a > 0.1 and not _sibling_hidden_states.get(s, false)
			if is_visible:
				siblings.append(s)
		else:
			siblings.append(s)
			
	if siblings.is_empty():
		return
		
	disappear_started.emit()
	current_tween = create_tween()
	current_tween.set_parallel(true)
	
	var offset = _get_slide_offset(disappear_slide_direction, disappear_slide_distance, disappear_custom_offset)
	var count = siblings.size()
	
	for i in range(count):
		var sibling_index = (count - 1 - i) if disappear_reverse_order else i
		var sibling = siblings[sibling_index]
		_kill_sibling_tween(sibling)
		var delay = i * disappear_stagger_delay
		var base_scale: Vector2 = _sibling_base_scales.get(sibling, Vector2.ONE)
		
		# Mark as hidden immediately (before animation starts)
		_sibling_hidden_states[sibling] = true
		
		# Always reset offset to zero before disappearing for consistency
		_apply_sibling_offset(sibling, Vector2.ZERO)
		_sibling_offsets[sibling] = Vector2.ZERO
		
		# Fade out
		if disappear_fade:
			var fade_t = current_tween.tween_property(sibling, "modulate:a", 0.0, disappear_duration)
			fade_t.set_delay(delay)
		
		# Slide out
		var slide_t = current_tween.tween_method(
			func(current_offset: Vector2): _apply_sibling_offset(sibling, current_offset),
			Vector2.ZERO,
			offset,
			disappear_duration
		)
		slide_t.set_delay(delay).set_trans(disappear_trans_type).set_ease(disappear_ease_type)
		
		# Scale down if enabled
		if disappear_scale_down:
			var scale_t = current_tween.tween_property(sibling, "scale", base_scale * disappear_target_scale, disappear_duration)
			scale_t.set_delay(delay).set_trans(disappear_trans_type).set_ease(disappear_ease_type)
	
	current_tween.finished.connect(func():
		for sibling in siblings:
			# Reset to baseline position
			_sibling_offsets[sibling] = Vector2.ZERO
			if not _parent_is_container:
				var baseline_pos: Vector2 = _sibling_baseline_positions.get(sibling, sibling.position)
				sibling.position = baseline_pos
			elif _parent_is_container and sibling.get_parent() and sibling.get_parent() is Control and sibling.get_parent() != get_parent():
				# Button is inside wrapper, reset relative to wrapper
				var baseline_pos: Vector2 = _sibling_baseline_positions.get(sibling, sibling.position)
				sibling.position = baseline_pos
			_sibling_hidden_states[sibling] = true
		disappear_finished.emit()
	, CONNECT_ONE_SHOT)

## Animate a single sibling in
func appear_sibling(sibling: Control) -> Tween:
	if not sibling:
		return null
	_kill_sibling_tween(sibling)
	_ensure_baseline_cached(sibling)
	if not _sibling_base_scales.has(sibling):
		_sibling_base_scales[sibling] = sibling.scale
	if not _sibling_offsets.has(sibling):
		_sibling_offsets[sibling] = Vector2.ZERO
		
	var base_scale: Vector2 = _sibling_base_scales.get(sibling, Vector2.ONE)
	var start_offset: Vector2 = _get_slide_offset(appear_slide_direction, appear_slide_distance, appear_custom_offset)
	
	# Get wrapper for visibility control
	var wrapper = sibling.get_parent()
	
	# Mark as not hidden
	_sibling_hidden_states[sibling] = false
	
	# Apply the appear offset from baseline
	_sibling_offsets[sibling] = start_offset
	_apply_sibling_offset(sibling, start_offset)
	
	sibling.visible = true
	# Also show the wrapper
	if wrapper and wrapper != get_parent():
		wrapper.visible = true
	
	var tween = create_tween()
	tween.set_parallel(true)
	_sibling_tweens[sibling] = tween
	
	if appear_fade:
		sibling.modulate.a = 0.0
		tween.tween_property(sibling, "modulate:a", 1.0, appear_duration)
	
	var slide_t = tween.tween_method(
		func(offset: Vector2): _apply_sibling_offset(sibling, offset),
		start_offset,
		Vector2.ZERO,
		appear_duration
	)
	slide_t.set_trans(appear_trans_type).set_ease(appear_ease_type)
	
	if appear_bounce:
		sibling.scale = base_scale * 0.7
		var bounce_up_duration = appear_duration * 0.4
		var bounce_down_duration = appear_duration * 0.6
		tween.tween_property(sibling, "scale", base_scale * appear_bounce_scale, bounce_up_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(sibling, "scale", base_scale, bounce_down_duration).set_delay(bounce_up_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		
	tween.finished.connect(func():
		# Reset to baseline position
		_sibling_offsets[sibling] = Vector2.ZERO
		if not _parent_is_container:
			var end_baseline: Vector2 = _sibling_baseline_positions.get(sibling, sibling.position)
			sibling.position = end_baseline
		elif _parent_is_container and sibling.get_parent() and sibling.get_parent() is Control and sibling.get_parent() != get_parent():
			# Button is inside wrapper, reset relative to wrapper
			var end_baseline: Vector2 = _sibling_baseline_positions.get(sibling, sibling.position)
			sibling.position = end_baseline
		_sibling_hidden_states[sibling] = false
		_kill_sibling_tween(sibling)
	, CONNECT_ONE_SHOT)
	
	return tween

## Animate a single sibling out and set invisible on finish
func disappear_sibling(sibling: Control) -> Tween:
	if not sibling:
		return null
	_kill_sibling_tween(sibling)
	_ensure_baseline_cached(sibling)
	if not _sibling_base_scales.has(sibling):
		_sibling_base_scales[sibling] = sibling.scale
	if not _sibling_offsets.has(sibling):
		_sibling_offsets[sibling] = Vector2.ZERO
		
	var base_scale: Vector2 = _sibling_base_scales.get(sibling, Vector2.ONE)
	var target_offset: Vector2 = _get_slide_offset(disappear_slide_direction, disappear_slide_distance, disappear_custom_offset)
	
	# Get wrapper for visibility control
	var wrapper = sibling.get_parent()
	
	# Mark as hidden
	_sibling_hidden_states[sibling] = true
	
	# Start from baseline position
	_sibling_offsets[sibling] = Vector2.ZERO
	if not _parent_is_container:
		var start_baseline: Vector2 = _sibling_baseline_positions.get(sibling, sibling.position)
		sibling.position = start_baseline
	elif _parent_is_container and sibling.get_parent() and sibling.get_parent() is Control and sibling.get_parent() != get_parent():
		# Button is inside wrapper, reset relative to wrapper
		var start_baseline: Vector2 = _sibling_baseline_positions.get(sibling, sibling.position)
		sibling.position = start_baseline
	
	var tween = create_tween()
	tween.set_parallel(true)
	_sibling_tweens[sibling] = tween
	
	if disappear_fade:
		tween.tween_property(sibling, "modulate:a", 0.0, disappear_duration)
	
	var slide_t = tween.tween_method(
		func(offset: Vector2): _apply_sibling_offset(sibling, offset),
		Vector2.ZERO,
		target_offset,
		disappear_duration
	)
	slide_t.set_trans(disappear_trans_type).set_ease(disappear_ease_type)
	
	if disappear_scale_down:
		tween.tween_property(sibling, "scale", base_scale * disappear_target_scale, disappear_duration).set_trans(disappear_trans_type).set_ease(disappear_ease_type)
		
	tween.finished.connect(func():
		if is_instance_valid(sibling):
			sibling.visible = false
			# Also hide the wrapper to keep layout clean
			if wrapper and wrapper != get_parent():
				wrapper.visible = false
		# Reset to baseline position
		_sibling_offsets[sibling] = Vector2.ZERO
		if not _parent_is_container:
			var end_baseline: Vector2 = _sibling_baseline_positions.get(sibling, sibling.position)
			sibling.position = end_baseline
		elif _parent_is_container and sibling.get_parent() and sibling.get_parent() is Control and sibling.get_parent() != get_parent():
			# Button is inside wrapper, reset relative to wrapper
			var end_baseline: Vector2 = _sibling_baseline_positions.get(sibling, sibling.position)
			sibling.position = end_baseline
		_sibling_hidden_states[sibling] = true
		_kill_sibling_tween(sibling)
	, CONNECT_ONE_SHOT)
	
	return tween

func _kill_sibling_tween(sibling: Control) -> void:
	if _sibling_tweens.has(sibling):
		var t = _sibling_tweens[sibling]
		if t and t.is_valid():
			t.kill()
		_sibling_tweens.erase(sibling)

func _kill_current_tween() -> void:
	if current_tween and current_tween.is_valid():
		current_tween.kill()
	current_tween = null
	for s in _sibling_tweens.keys():
		var t = _sibling_tweens[s]
		if t and t.is_valid():
			t.kill()
	_sibling_tweens.clear()

## Public method to stop all animations and clear state
func kill() -> void:
	_kill_current_tween()
	_sibling_offsets.clear()
	_sibling_baseline_positions.clear()
