class_name PipRowFitter
extends RefCounted

## Lays out a row of icon Controls inside an HBoxContainer so they fit the
## available width. When the row overflows, separation absorbs ~`space_ratio`
## of the overflow first (down to `min_separation`, which may be negative to
## allow slight overlap); icon size only shrinks for whatever remains.
## Base separation is captured from the container's theme before any override
## is applied.
##
## Options (Dictionary):
##   min_icon_size    - smallest allowed icon width (default 6.0)
##   min_separation   - smallest allowed separation; <0 means auto overlap
##                      allowance of 35% of the base icon width (default -1)
##   space_ratio      - fraction of overflow absorbed by separation (default 0.8)

const DEFAULT_MIN_ICON_SIZE := 6.0
const DEFAULT_SPACE_RATIO := 0.8
const META_BASE_SEPARATION := &"pip_row_base_separation"

static func get_icons(container: Node, template: Node = null) -> Array:
	var icons: Array = []
	for child in container.get_children():
		if child == template or child.is_queued_for_deletion():
			continue
		icons.append(child)
	return icons

static func relayout_row(container: Container, template: Node = null, preserve_height := false, available_width := -1.0, options := {}) -> void:
	if not is_instance_valid(container):
		return
	if not container.has_meta(META_BASE_SEPARATION):
		container.set_meta(META_BASE_SEPARATION, container.get_theme_constant(&"separation"))
	var base_separation: float = container.get_meta(META_BASE_SEPARATION)
	var icons := get_icons(container, template)
	if icons.is_empty():
		container.add_theme_constant_override(&"separation", int(floorf(base_separation)))
		return
	var width := available_width
	if width <= 0.0:
		width = container.size.x
	if width <= 0.0:
		return
	var base_size := _base_icon_size(icons[0])
	if base_size.x <= 0.0:
		return
	var min_icon_size: float = options.get("min_icon_size", DEFAULT_MIN_ICON_SIZE)
	var space_ratio: float = options.get("space_ratio", DEFAULT_SPACE_RATIO)
	var count := icons.size()
	var gaps := maxi(count - 1, 0)
	var icon_w := base_size.x
	var separation := base_separation
	var min_separation: float = options.get("min_separation", -1.0)
	if min_separation < 0.0:
		min_separation = -base_size.x * 0.35
	var overflow := count * base_size.x + gaps * base_separation - width
	if overflow > 0.0:
		if gaps > 0:
			separation = clampf(base_separation - space_ratio * overflow / gaps, min_separation, base_separation)
			icon_w = (width - gaps * separation) / count
		else:
			icon_w = width / count
		icon_w = clampf(icon_w, min_icon_size, base_size.x)
		if gaps > 0:
			separation = clampf((width - count * icon_w) / gaps, min_separation, base_separation)
	container.add_theme_constant_override(&"separation", int(floorf(separation)))
	var scale := icon_w / base_size.x
	for icon in icons:
		if not is_instance_valid(icon):
			continue
		var icon_size := Vector2(icon_w, base_size.y) if preserve_height else base_size * scale
		if icon is TextureRect:
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.custom_minimum_size = icon_size

static func _base_icon_size(icon: Node) -> Vector2:
	if icon is TextureRect and icon.texture:
		return icon.texture.get_size()
	var min_size: Vector2 = icon.get_combined_minimum_size()
	if min_size != Vector2.ZERO:
		return min_size
	return icon.custom_minimum_size
