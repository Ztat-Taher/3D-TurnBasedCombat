class_name ScreenEffectConfig
extends Resource
## Screen effect configuration for visual feedback
## Controls screen flash, time slow, and other screen-space effects

enum EffectType {
	NONE,               # No effect
	FLASH,              # Screen flash
	TIME_SLOW,          # Time slow motion
	CHROMATIC,          # Chromatic aberration
	VIGNETTE,           # Vignette effect
	GRAIN,              # Film grain
	BLUR,               # Motion blur
	CUSTOM              # Custom effect
}

@export var effect_type: EffectType = EffectType.NONE
@export var effect_duration: float = 0.5             ## How long the effect lasts
@export var effect_intensity: float = 1.0            ## Intensity of the effect
@export var effect_color: Color = Color(1, 1, 1, 1)  ## Color for flash effects
@export var fade_in: float = 0.1                     ## Fade in duration
@export var fade_out: float = 0.2                     ## Fade out duration
@export var time_scale: float = 0.5                  ## Time scale for time slow effects
@export var affect_physics: bool = true              ## Whether time slow affects physics

## Apply screen effect using the EffectManager
func apply_screen_effect(effect_manager: EffectManager):
	if not effect_manager:
		push_warning("ScreenEffectConfig: No EffectManager provided")
		return
	
	match effect_type:
		EffectType.FLASH:
			_apply_flash(effect_manager)
		EffectType.TIME_SLOW:
			_apply_time_slow(effect_manager)
		EffectType.CHROMATIC:
			_apply_chromatic(effect_manager)
		EffectType.VIGNETTE:
			_apply_vignette(effect_manager)
		EffectType.GRAIN:
			_apply_grain(effect_manager)
		EffectType.BLUR:
			_apply_blur(effect_manager)
		EffectType.CUSTOM:
			# Would need custom implementation
			pass
		_:
			pass

## Apply screen flash effect
func _apply_flash(effect_manager: EffectManager):
	if effect_manager.has_method("get_screen_flash"):
		var screen_flash = effect_manager.get_screen_flash()
		if screen_flash and screen_flash.has_method("damage_flash"):
			screen_flash.damage_flash(effect_duration, effect_intensity)

## Apply time slow effect
func _apply_time_slow(effect_manager: EffectManager):
	if effect_manager.has_method("get_time_slow"):
		var time_slow = effect_manager.get_time_slow()
		if time_slow and time_slow.has_method("custom_slow"):
			time_slow.custom_slow(effect_duration, time_scale)

## Apply chromatic aberration effect
func _apply_chromatic(effect_manager: EffectManager):
	# Would need implementation with screen shaders
	pass

## Apply vignette effect
func _apply_vignette(effect_manager: EffectManager):
	# Would need implementation with screen shaders
	pass

## Apply grain effect
func _apply_grain(effect_manager: EffectManager):
	# Would need implementation with screen shaders
	pass

## Apply blur effect
func _apply_blur(effect_manager: EffectManager):
	# Would need implementation with screen shaders
	pass

## Create preset screen effects
static func create_damage_flash() -> ScreenEffectConfig:
	var config = ScreenEffectConfig.new()
	config.effect_type = EffectType.FLASH
	config.effect_duration = 0.3
	config.effect_intensity = 0.8
	config.effect_color = Color(1, 0, 0, 0.5)
	config.fade_in = 0.05
	config.fade_out = 0.2
	return config

static func create_critical_flash() -> ScreenEffectConfig:
	var config = ScreenEffectConfig.new()
	config.effect_type = EffectType.FLASH
	config.effect_duration = 0.4
	config.effect_intensity = 1.0
	config.effect_color = Color(1, 1, 0, 0.7)
	config.fade_in = 0.1
	config.fade_out = 0.3
	return config

static func create_heal_flash() -> ScreenEffectConfig:
	var config = ScreenEffectConfig.new()
	config.effect_type = EffectType.FLASH
	config.effect_duration = 0.5
	config.effect_intensity = 0.6
	config.effect_color = Color(0, 1, 0, 0.4)
	config.fade_in = 0.2
	config.fade_out = 0.3
	return config

static func create_time_slow() -> ScreenEffectConfig:
	var config = ScreenEffectConfig.new()
	config.effect_type = EffectType.TIME_SLOW
	config.effect_duration = 0.5
	config.effect_intensity = 1.0
	config.time_scale = 0.2
	config.affect_physics = true
	return config

## Validate configuration
func validate() -> Array[String]:
	var issues: Array[String] = []
	
	if effect_type == EffectType.NONE:
		issues.append("No effect type specified")
	
	if effect_duration <= 0:
		issues.append("Invalid effect duration")
	
	if effect_intensity <= 0:
		issues.append("Invalid effect intensity")
	
	return issues
