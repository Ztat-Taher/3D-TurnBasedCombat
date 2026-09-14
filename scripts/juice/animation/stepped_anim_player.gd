extends AnimationMixer
class_name SteppedAnimMixer

## Target framerate for the animations (Spider-Verse style)
@export var target_fps: float = 12.0
## Name of the root state machine in your AnimationTree
@export var root_sm_name: String = "Main"

var _accumulator: float = 0.0
var just_stepped: bool = false
var _last_animation: StringName = &""

var _top_playback: AnimationNodeStateMachinePlayback
var _sub_playbacks: Dictionary = {}

func _ready():
	callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_accumulator = 0.0

func _process(delta):
	just_stepped = false

	var current_animation = _get_current_animation()
	var animation_changed = current_animation != _last_animation and current_animation != &""
	_last_animation = current_animation

	_accumulator += delta
	var step_duration = 1.0 / target_fps

	if animation_changed:
		advance(step_duration)
		_accumulator = 0.0
		just_stepped = true
		return

	while _accumulator >= step_duration:
		advance(step_duration)
		_accumulator -= step_duration
		just_stepped = true

func _get_current_animation() -> StringName:
	# Lazy-init top playback — tree may not be ready during _ready()
	if not _top_playback:
		_top_playback = get("parameters/%s/playback" % root_sm_name)
		if not _top_playback:
			return &""

	var top_node: StringName = _top_playback.get_current_node()
	if top_node == &"":
		return &""

	var sub_playback: AnimationNodeStateMachinePlayback
	if _sub_playbacks.has(top_node):
		sub_playback = _sub_playbacks[top_node]
	else:
		sub_playback = get("parameters/%s/%s/playback" % [root_sm_name, top_node])
		_sub_playbacks[top_node] = sub_playback

	if sub_playback:
		var sub_node: StringName = sub_playback.get_current_node()
		if sub_node != &"":
			return StringName(top_node + "/" + sub_node)

	return top_node
