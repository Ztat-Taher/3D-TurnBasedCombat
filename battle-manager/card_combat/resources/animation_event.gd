class_name AnimationEvent
extends Resource
## Animation callback configuration for precise effect timing
## Controls when events trigger during animation playback

enum AnimationEventType {
	EFFECT_TRIGGER,      # Trigger card effect
	SOUND_PLAY,          # Play sound effect
	VFX_SPAWN,           # Spawn visual effect
	CAMERA_EFFECT,       # Apply camera effect
	SCREEN_EFFECT,       # Apply screen effect
	QTE_TRIGGER,         # Trigger QTE
	DAMAGE_FRAME,        # Apply damage
	PROJECTILE_SPAWN,    # Spawn projectile
	CUSTOM               # Custom event
}

@export var event_time: float = 0.5                 ## Time in animation when event triggers (0.0-1.0)
@export var event_type: AnimationEventType = AnimationEventType.EFFECT_TRIGGER
@export var event_data: Dictionary = {}              ## Event-specific data
@export var event_condition: EffectCondition         ## Optional condition for event trigger
@export var event_name: String = ""                  ## Event identifier for debugging
@export var repeat: bool = false                     ## Whether event can repeat
@export var repeat_interval: float = 0.0              ## Time between repeats
@export var max_repeats: int = 0                     ## Maximum number of repeats (0 = infinite)

## Check if this event should trigger at the given animation time
func should_trigger(animation_time: float, animation_duration: float) -> bool:
	var actual_time = event_time * animation_duration
	
	# Check if we're at the event time (with small tolerance)
	var tolerance = 0.05 # 50ms tolerance
	var time_diff = abs(animation_time - actual_time)
	
	return time_diff <= tolerance

## Check if condition is met for this event
func check_condition(actor: Node, target: Node) -> bool:
	if not event_condition:
		return true
	
	return event_condition.evaluate(actor, target)

## Execute this event
func execute(actor: Node, target: Node, context: Dictionary) -> Dictionary:
	var result = {
		"success": false,
		"event_type": AnimationEventType.keys()[event_type],
		"event_data": {},
		"message": ""
	}
	
	# Check condition first
	if not check_condition(actor, target):
		result["message"] = "Event condition not met"
		return result
	
	match event_type:
		AnimationEventType.EFFECT_TRIGGER:
			result = _execute_effect_trigger(actor, target, context)
		AnimationEventType.SOUND_PLAY:
			result = _execute_sound_play(actor, target, context)
		AnimationEventType.VFX_SPAWN:
			result = _execute_vfx_spawn(actor, target, context)
		AnimationEventType.CAMERA_EFFECT:
			result = _execute_camera_effect(actor, target, context)
		AnimationEventType.SCREEN_EFFECT:
			result = _execute_screen_effect(actor, target, context)
		AnimationEventType.QTE_TRIGGER:
			result = _execute_qte_trigger(actor, target, context)
		AnimationEventType.DAMAGE_FRAME:
			result = _execute_damage_frame(actor, target, context)
		AnimationEventType.PROJECTILE_SPAWN:
			result = _execute_projectile_spawn(actor, target, context)
		AnimationEventType.CUSTOM:
			result = _execute_custom_event(actor, target, context)
		_:
			result["message"] = "Unknown event type"
	
	return result

## Execute effect trigger event
func _execute_effect_trigger(actor: Node, target: Node, context: Dictionary) -> Dictionary:
	var result = {
		"success": false,
		"event_data": {},
		"message": ""
	}
	
	var card_config = context.get("card_config")
	if not card_config:
		result["message"] = "No card config in context"
		return result
	
	var effect_manager = context.get("effect_manager")
	if not effect_manager:
		result["message"] = "No effect manager in context"
		return result
	
	# Trigger the card's primary effect
	if card_config.primary_effect:
		var effect_result = card_config.primary_effect.apply_effect(actor, target, context.get("enemies", []), context.get("allies", []))
		result["success"] = effect_result["success"]
		result["event_data"] = effect_result
		result["message"] = "Effect triggered successfully"
	
	return result

## Execute sound play event
func _execute_sound_play(actor: Node, target: Node, context: Dictionary) -> Dictionary:
	var result = {
		"success": false,
		"event_data": {},
		"message": ""
	}
	
	var audio_config = event_data.get("audio_config")
	if not audio_config:
		result["message"] = "No audio config in event data"
		return result
	
	var parent_node = context.get("parent_node", actor)
	var position = event_data.get("position", actor.global_position if actor else Vector3.ZERO)
	
	var audio_player = audio_config.play_audio(parent_node, position)
	if audio_player:
		result["success"] = true
		result["event_data"]["audio_player"] = audio_player
		result["message"] = "Sound played successfully"
	else:
		result["message"] = "Failed to play sound"
	
	return result

## Execute VFX spawn event
func _execute_vfx_spawn(actor: Node, target: Node, context: Dictionary) -> Dictionary:
	var result = {
		"success": false,
		"event_data": {},
		"message": ""
	}
	
	var vfx_config = event_data.get("vfx_config")
	if not vfx_config:
		result["message"] = "No VFX config in event data"
		return result
	
	var spawn_position = event_data.get("spawn_position", target.global_position if target else Vector3.ZERO)
	var target_node = event_data.get("target_node", target)
	
	var vfx_instance = vfx_config.spawn_vfx(spawn_position, target_node)
	if vfx_instance:
		result["success"] = true
		result["event_data"]["vfx_instance"] = vfx_instance
		result["message"] = "VFX spawned successfully"
	else:
		result["message"] = "Failed to spawn VFX"
	
	return result

## Execute camera effect event
func _execute_camera_effect(actor: Node, target: Node, context: Dictionary) -> Dictionary:
	var result = {
		"success": false,
		"event_data": {},
		"message": ""
	}
	
	var camera_config = event_data.get("camera_config")
	if not camera_config:
		result["message"] = "No camera config in event data"
		return result
	
	var camera = context.get("camera")
	if not camera:
		result["message"] = "No camera in context"
		return result
	
	camera_config.apply_camera_effects(camera, actor, target, context.get("projectile"))
	result["success"] = true
	result["message"] = "Camera effect applied successfully"
	
	return result

## Execute screen effect event
func _execute_screen_effect(actor: Node, target: Node, context: Dictionary) -> Dictionary:
	var result = {
		"success": false,
		"event_data": {},
		"message": ""
	}
	
	var screen_config = event_data.get("screen_config")
	if not screen_config:
		result["message"] = "No screen config in event data"
		return result
	
	var effect_manager = context.get("effect_manager")
	if not effect_manager:
		result["message"] = "No effect manager in context"
		return result
	
	screen_config.apply_screen_effect(effect_manager)
	result["success"] = true
	result["message"] = "Screen effect applied successfully"
	
	return result

## Execute QTE trigger event
func _execute_qte_trigger(actor: Node, target: Node, context: Dictionary) -> Dictionary:
	var result = {
		"success": false,
		"event_data": {},
		"message": ""
	}
	
	var qte_manager = context.get("qte_manager")
	if not qte_manager:
		result["message"] = "No QTE manager in context"
		return result
	
	var card_config = context.get("card_config")
	if not card_config:
		result["message"] = "No card config in context"
		return result
	
	if qte_manager.has_method("start_card_qte"):
		var qte_started = qte_manager.start_card_qte(context.get("card_data"))
		result["success"] = qte_started
		result["message"] = "QTE trigger processed" if qte_started else "QTE not started"
	else:
		result["message"] = "QTE manager does not support card QTE"
	
	return result

## Execute damage frame event
func _execute_damage_frame(actor: Node, target: Node, context: Dictionary) -> Dictionary:
	var result = {
		"success": false,
		"event_data": {},
		"message": ""
	}
	
	var damage_amount = event_data.get("damage_amount", 0)
	if damage_amount <= 0:
		result["message"] = "No damage amount specified"
		return result
	
	if target and target.has_method("take_damage"):
		target.take_damage(damage_amount)
		result["success"] = true
		result["event_data"]["damage_dealt"] = damage_amount
		result["message"] = "Damage applied successfully"
	else:
		result["message"] = "Target does not support damage"
	
	return result

## Execute projectile spawn event
func _execute_projectile_spawn(actor: Node, target: Node, context: Dictionary) -> Dictionary:
	var result = {
		"success": false,
		"event_data": {},
		"message": ""
	}
	
	var projectile_scene = event_data.get("projectile_scene")
	if not projectile_scene:
		result["message"] = "No projectile scene specified"
		return result
	
	var spawn_position = event_data.get("spawn_position", actor.global_position if actor else Vector3.ZERO)
	var target_position = event_data.get("target_position", target.global_position if target else Vector3.ZERO)
	
	# Would need projectile system implementation
	result["message"] = "Projectile system not yet implemented"
	
	return result

## Execute custom event
func _execute_custom_event(actor: Node, target: Node, context: Dictionary) -> Dictionary:
	var result = {
		"success": false,
		"event_data": {},
		"message": ""
	}
	
	var custom_script = event_data.get("custom_script")
	if not custom_script:
		result["message"] = "No custom script specified"
		return result
	
	# Would need custom script execution implementation
	result["message"] = "Custom event execution not yet implemented"
	
	return result

## Get event description for debugging
func get_description() -> String:
	var description = "[%s] %s at %.2f%% of animation" % [event_name, AnimationEventType.keys()[event_type], event_time * 100]
	
	if not event_data.is_empty():
		description += " (Data: %s)" % str(event_data)
	
	if event_condition:
		description += " [Condition: %s]" % event_condition.get_description()
	
	return description

## Create preset animation events
static func create_hit_frame_event(damage_amount: int = 0) -> AnimationEvent:
	var event = AnimationEvent.new()
	event.event_time = 0.55 # Typical hit frame at 55% of animation
	event.event_type = AnimationEventType.DAMAGE_FRAME
	event.event_data = {"damage_amount": damage_amount}
	event.event_name = "HitFrame"
	return event

static func create_sound_event(audio_config: AudioConfig, time: float = 0.0) -> AnimationEvent:
	var event = AnimationEvent.new()
	event.event_time = time
	event.event_type = AnimationEventType.SOUND_PLAY
	event.event_data = {"audio_config": audio_config}
	event.event_name = "SoundPlay"
	return event

static func create_vfx_event(vfx_config: VFXConfig, time: float = 0.5) -> AnimationEvent:
	var event = AnimationEvent.new()
	event.event_time = time
	event.event_type = AnimationEventType.VFX_SPAWN
	event.event_data = {"vfx_config": vfx_config}
	event.event_name = "VFXSpawn"
	return event

static func create_qte_event(time: float = 0.3) -> AnimationEvent:
	var event = AnimationEvent.new()
	event.event_time = time
	event.event_type = AnimationEventType.QTE_TRIGGER
	event.event_name = "QTETrigger"
	return event

## Validate configuration
func validate() -> Array[String]:
	var issues: Array[String] = []
	
	if event_time < 0.0 or event_time > 1.0:
		issues.append("Event time must be between 0.0 and 1.0")
	
	if event_name.is_empty():
		issues.append("Event name should not be empty for debugging")
	
	if repeat and repeat_interval <= 0:
		issues.append("Repeat enabled but invalid repeat interval")
	
	if repeat and max_repeats < 0:
		issues.append("Repeat enabled but invalid max repeats")
	
	return issues
