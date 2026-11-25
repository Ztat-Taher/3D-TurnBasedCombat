@tool
class_name StatRadarGraph
extends Control
## Pentagon (radar) chart of a member's stats. Each axis is scaled against its
## own reference value (see [method set_stats]) so a 100 HP / 10 ATK character
## doesn't collapse into a single HP spike.

## Axis order, clockwise from the top.
const STAT_KEYS : Array[String] = ["max_health", "attack", "defense", "agility", "max_ap"]
const STAT_LABELS : Array[String] = ["HP", "ATK", "DEF", "AGI", "AP"]
## Rings drawn behind the shape (fractions of the full radius).
const RINGS : Array[float] = [0.25, 0.5, 0.75, 1.0]
## Smallest share of the radius a non-zero stat is drawn at, so it stays visible.
const MIN_SHARE : float = 0.08

@export var fill_color : Color = Color(1.0, 0.85, 0.4, 0.55)
@export var outline_color : Color = Color(1.0, 0.85, 0.4, 1.0)
@export var web_color : Color = Color(1, 1, 1, 0.18)
@export var label_color : Color = Color(1, 1, 1, 0.9)
## Space kept around the pentagon for the axis labels.
@export var label_margin : float = 30.0

var _values : Dictionary = {}
var _references : Dictionary = {}


## [param values] and [param references] are keyed by [constant STAT_KEYS];
## an axis is full when its value reaches its reference.
func set_stats(values : Dictionary, references : Dictionary) -> void:
	_values = values
	_references = references
	queue_redraw()


func _get_minimum_size() -> Vector2:
	return Vector2(200, 200)


func _draw() -> void:
	var center := size * 0.5
	var radius := maxf(minf(size.x, size.y) * 0.5 - label_margin, 8.0)
	var count := STAT_KEYS.size()

	# Web: rings + spokes.
	for ring in RINGS:
		var ring_points := PackedVector2Array()
		for i in count + 1:
			ring_points.append(center + _axis(i % count, count) * radius * ring)
		draw_polyline(ring_points, web_color, 1.0, true)
	for i in count:
		draw_line(center, center + _axis(i, count) * radius, web_color, 1.0, true)

	# Shape.
	if not _values.is_empty():
		var points := PackedVector2Array()
		for i in count:
			points.append(center + _axis(i, count) * radius * _share(STAT_KEYS[i]))
		draw_colored_polygon(points, fill_color)
		var outline := points.duplicate()
		outline.append(points[0])
		draw_polyline(outline, outline_color, 2.0, true)

	# Labels last so the shape never covers them.
	var font := get_theme_font(&"font", &"Label")
	var font_size := get_theme_font_size(&"font_size", &"PartySmallLabel")
	for i in count:
		var text := STAT_LABELS[i]
		if not _values.is_empty():
			text += "\n%d" % int(_values.get(STAT_KEYS[i], 0))
		var anchor := center + _axis(i, count) * (radius + label_margin * 0.55)
		var box := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		var origin := anchor - box * 0.5 + Vector2(0, font.get_ascent(font_size))
		draw_multiline_string(font, origin, text, HORIZONTAL_ALIGNMENT_CENTER, box.x, font_size, -1, label_color)


func _share(key : String) -> float:
	var value := float(_values.get(key, 0))
	var reference := maxf(float(_references.get(key, value)), 1.0)
	if value <= 0.0:
		return 0.0
	return clampf(value / reference, MIN_SHARE, 1.0)


func _axis(index : int, count : int) -> Vector2:
	var angle := TAU / float(count) * float(index) - PI / 2.0
	return Vector2(cos(angle), sin(angle))
