extends AnimationMixer
class_name SteppedAnimMixer

## Target framerate for the animations (Spider-Verse style)
@export var target_fps: float = 12.0
## Name of the root state machine in your AnimationTree
@export var root_sm_name: String = "BaseSM"

## Most zero-time advances used to settle one change (e.g. a nested
## state machine's Start -> clip hop needs a second one).
const MAX_SETTLE_PASSES := 3

var _accumulator: float = 0.0
var just_stepped: bool = false
var _last_animation: StringName = &""
var _snap_requested: bool = false

var _top_playback: AnimationNodeStateMachinePlayback
var _sub_playbacks: Dictionary = {}
var _lookup_failed: bool = false

func _ready():
	callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_accumulator = 0.0

## Show a just-requested animation change on the next frame instead of at the
## next 12fps step. Call it after travel()/start()/a OneShot request.
func request_snap() -> void:
	_snap_requested = true

func _process(delta):
	just_stepped = false

	var current_animation = _get_current_animation()
	var animation_changed = current_animation != _last_animation and current_animation != &""

	if animation_changed or _snap_requested:
		_snap_requested = false
		# Apply pending requests and settle any chained hops without moving time,
		# so the new animation shows from its first frame and then holds for a
		# full step like every other frame.
		for i in MAX_SETTLE_PASSES:
			advance(0.0)
			var settled := _get_current_animation()
			if settled == current_animation:
				break
			current_animation = settled
		_last_animation = current_animation
		_accumulator = 0.0
		just_stepped = true
		return

	_accumulator += delta
	var step_duration = 1.0 / target_fps

	while _accumulator >= step_duration:
		advance(step_duration)
		_accumulator -= step_duration
		just_stepped = true

	# A step can itself switch state (an at-end transition); count that as the
	# new baseline rather than a change to snap to.
	if just_stepped:
		_last_animation = _get_current_animation()

func _get_current_animation() -> StringName:
	# Lazy-init top playback — tree may not be ready during _ready()
	if not _top_playback:
		if _lookup_failed:
			return &""
		_top_playback = get("parameters/%s/playback" % root_sm_name)
		if not _top_playback:
			_lookup_failed = true
			push_warning("[SteppedAnimMixer] '%s' has no state machine named '%s' - animation-change snapping is off" % [get_parent().name if get_parent() else name, root_sm_name])
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
