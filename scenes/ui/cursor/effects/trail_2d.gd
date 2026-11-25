extends Line2D
## Cursor trail: a point per rendered frame at the cursor's position, kept for
## a fixed time instead of a fixed point count, so the trail is the same length
## at any frame rate and never lags behind the cursor (both update in _process).
## Color comes from the node's default_color and never changes.

## Seconds a point stays on the trail
@export var lifetime : float = 0.16

@onready var parent : Node2D = get_parent()
var offset : = Vector2.ZERO
## Time (seconds) each point was added; parallel to the Line2D points
var _times : PackedFloat64Array = []


func _ready() -> void:
	offset = position
	top_level = true
	# Run after the parent moved this frame, so the newest point is never stale
	process_priority = 100


func _process(_delta: float) -> void:
	global_position = Vector2.ZERO
	var now := Time.get_ticks_usec() / 1000000.0
	add_point(parent.global_position + offset, 0)
	_times.insert(0, now)
	while get_point_count() > 1 and now - _times[get_point_count() - 1] > lifetime:
		remove_point(get_point_count() - 1)
		_times.remove_at(_times.size() - 1)
