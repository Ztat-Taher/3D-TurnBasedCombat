class_name AudioConfig
extends Resource
## Audio effect configuration for card sounds
## Controls how audio is played for different card phases

@export var audio_stream: String = ""                 ## Path to audio file
@export var volume: float = 1.0                      ## Volume level (0.0-1.0)
@export var pitch: float = 1.0                       ## Pitch multiplier
@export var bus: String = "Master"                   ## Audio bus for effects processing
@export var loop: bool = false                      ## Whether audio should loop
@export var random_pitch_variation: float = 0.0      ## Random pitch variation for variety
@export var random_volume_variation: float = 0.0     ## Random volume variation for variety
@export var delay: float = 0.0                       ## Delay before playing (seconds)
@export var fade_in_duration: float = 0.0            ## Fade in time
@export var fade_out_duration: float = 0.0           ## Fade out time
@export var max_distance: float = 100.0              ## Max 3D distance for attenuation
@export var attenuation: float = 1.0                 ## Attenuation factor
@export var doppler: float = 0.0                     ## Doppler effect strength

## Play this audio configuration
func play_audio(parent_node: Node, position: Vector3 = Vector3.ZERO) -> Node:
	if audio_stream.is_empty():
		push_warning("AudioConfig: No audio stream specified")
		return null
	
	var audio_path = audio_stream
	if not ResourceLoader.exists(audio_path):
		push_warning("AudioConfig: Audio file does not exist: %s" % audio_path)
		return null
	
	var audio_resource = load(audio_path)
	if not audio_resource:
		push_warning("AudioConfig: Failed to load audio: %s" % audio_path)
		return null
	
	# Determine if we need 2D or 3D audio
	var is_3d = position != Vector3.ZERO and max_distance > 0
	
	if is_3d:
		var audio_player_3d = AudioStreamPlayer3D.new()
		_configure_3d_audio(audio_player_3d, position)
		_configure_common_audio(audio_player_3d, audio_resource)
		parent_node.add_child(audio_player_3d)
		
		if delay > 0:
			var timer = Timer.new()
			timer.wait_time = delay
			timer.one_shot = true
			timer.timeout.connect(func():
				_play_audio_with_effects(audio_player_3d)
				timer.queue_free()
			)
			parent_node.add_child(timer)
			timer.start()
		else:
			_play_audio_with_effects(audio_player_3d)
		
		return audio_player_3d
	else:
		var audio_player_2d = AudioStreamPlayer2D.new()
		_configure_2d_audio(audio_player_2d)
		_configure_common_audio(audio_player_2d, audio_resource)
		parent_node.add_child(audio_player_2d)
		
		if delay > 0:
			var timer = Timer.new()
			timer.wait_time = delay
			timer.one_shot = true
			timer.timeout.connect(func():
				_play_audio_with_effects(audio_player_2d)
				timer.queue_free()
			)
			parent_node.add_child(timer)
			timer.start()
		else:
			_play_audio_with_effects(audio_player_2d)
		
		return audio_player_2d

## Configure 3D audio player
func _configure_3d_audio(audio_player: AudioStreamPlayer3D, position: Vector3):
	audio_player.global_position = position
	audio_player.max_distance = max_distance
	audio_player.attenuation = attenuation
	if doppler > 0.0:
		audio_player.doppler_tracking = 1 # ENABLED
	else:
		audio_player.doppler_tracking = 0 # DISABLED
	audio_player.unit_db = _volume_to_db(volume)
	audio_player.pitch_scale = _apply_random_pitch(pitch)

## Configure 2D audio player
func _configure_2d_audio(audio_player: AudioStreamPlayer2D):
	audio_player.volume_db = _volume_to_db(volume)
	audio_player.pitch_scale = _apply_random_pitch(pitch)

## Configure common audio properties
func _configure_common_audio(audio_player: Node, audio_resource: Resource):
	if audio_player is AudioStreamPlayer:
		audio_player.stream = audio_resource
		audio_player.bus = bus
		audio_player.autoplay = false
		
		if loop:
			audio_player.loop = true

## Play audio with effects
func _play_audio_with_effects(audio_player: Node):
	# Apply fade in
	if fade_in_duration > 0:
		if audio_player.has_method("set_volume_db"):
			audio_player.set("volume_db", -80.0)
		var tween = audio_player.create_tween()
		tween.tween_property(audio_player, "volume_db", _volume_to_db(volume), fade_in_duration)
	
	if audio_player.has_method("play"):
		audio_player.play()
	
	# Handle fade out and cleanup
	if not loop:
		var duration = 1.0
		if audio_player.has_method("get_stream"):
			var stream = audio_player.get("stream")
			if stream and stream.has_method("get_length"):
				duration = stream.get_length()
		
		var total_duration = duration + fade_out_duration
		
		var cleanup_timer = Timer.new()
		cleanup_timer.wait_time = total_duration
		cleanup_timer.one_shot = true
		cleanup_timer.timeout.connect(func():
			if is_instance_valid(audio_player):
				if fade_out_duration > 0:
					var fade_tween = audio_player.create_tween()
					fade_tween.tween_property(audio_player, "volume_db", -80.0, fade_out_duration)
					fade_tween.tween_callback(func():
						if is_instance_valid(audio_player):
							audio_player.queue_free()
					)
				else:
					audio_player.queue_free()
			cleanup_timer.queue_free()
		)
		audio_player.add_child(cleanup_timer)
		cleanup_timer.start()

## Convert volume (0.0-1.0) to decibels
func _volume_to_db(vol: float) -> float:
	var adjusted_vol = vol
	if random_volume_variation > 0:
		adjusted_vol += randf_range(-random_volume_variation, random_volume_variation)
		adjusted_vol = clamp(adjusted_vol, 0.0, 1.0)
	
	return linear_to_db(adjusted_vol)

## Apply random pitch variation
func _apply_random_pitch(base_pitch: float) -> float:
	if random_pitch_variation > 0:
		var variation = randf_range(-random_pitch_variation, random_pitch_variation)
		return clamp(base_pitch + variation, 0.1, 4.0)
	return base_pitch

## Stop audio playback
func stop_audio(audio_player: Node):
	if audio_player and is_instance_valid(audio_player):
		if fade_out_duration > 0:
			var tween = audio_player.create_tween()
			tween.tween_property(audio_player, "volume_db", -80.0, fade_out_duration)
			tween.tween_callback(func():
				if is_instance_valid(audio_player):
					if audio_player.has_method("stop"):
						audio_player.stop()
					audio_player.queue_free()
			)
		else:
			if audio_player.has_method("stop"):
				audio_player.stop()
			audio_player.queue_free()

## Create preset audio configurations
static func create_cast_sound() -> AudioConfig:
	var config = AudioConfig.new()
	config.audio_stream = "res://audio/card_cast.wav"
	config.volume = 0.8
	config.pitch = 1.0
	config.bus = "SFX"
	config.loop = false
	config.random_pitch_variation = 0.1
	return config

static func create_hit_sound() -> AudioConfig:
	var config = AudioConfig.new()
	config.audio_stream = "res://audio/card_hit.wav"
	config.volume = 1.0
	config.pitch = 1.0
	config.bus = "SFX"
	config.loop = false
	config.random_pitch_variation = 0.15
	config.random_volume_variation = 0.2
	return config

static func create_impact_sound() -> AudioConfig:
	var config = AudioConfig.new()
	config.audio_stream = "res://audio/card_impact.wav"
	config.volume = 1.2
	config.pitch = 1.0
	config.bus = "SFX"
	config.loop = false
	config.random_pitch_variation = 0.05
	return config

static func create_heal_sound() -> AudioConfig:
	var config = AudioConfig.new()
	config.audio_stream = "res://audio/card_heal.wav"
	config.volume = 0.7
	config.pitch = 1.0
	config.bus = "SFX"
	config.loop = false
	config.fade_in_duration = 0.1
	config.fade_out_duration = 0.3
	return config

static func create_loop_sound() -> AudioConfig:
	var config = AudioConfig.new()
	config.audio_stream = "res://audio/card_loop.wav"
	config.volume = 0.5
	config.pitch = 1.0
	config.bus = "SFX"
	config.loop = true
	config.fade_in_duration = 0.2
	return config

## Validate configuration
func validate() -> Array[String]:
	var issues: Array[String] = []
	
	if audio_stream.is_empty():
		issues.append("No audio stream specified")
	
	if volume < 0 or volume > 2:
		issues.append("Volume must be between 0.0 and 2.0")
	
	if pitch <= 0 or pitch > 4:
		issues.append("Pitch must be between 0.0 and 4.0")
	
	if random_pitch_variation < 0 or random_pitch_variation > 1:
		issues.append("Random pitch variation must be between 0.0 and 1.0")
	
	if random_volume_variation < 0 or random_volume_variation > 1:
		issues.append("Random volume variation must be between 0.0 and 1.0")
	
	return issues
