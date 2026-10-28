class_name DioramaRingLayer25D
extends Resource
## Defines an individual panoramic dome layer in the 360 diorama.
## The dome can be shaped from a full sphere to a cylinder by tweaking top/bottom flattening.

@export var name: String = "Panorama Ring"
@export var texture: Texture2D:
	set(v):
		texture = v
		emit_changed()

@export_group("Surface Detail Maps")
## Normal map texture for pseudo-3D surface relief and lighting response
@export var normal_texture: Texture2D:
	set(v):
		normal_texture = v
		emit_changed()

## Normal map bump depth/intensity
@export_range(0.0, 3.0, 0.05) var normal_scale: float = 1.0:
	set(v):
		normal_scale = v
		emit_changed()

## Specular / glossiness texture map
@export var specular_texture: Texture2D:
	set(v):
		specular_texture = v
		emit_changed()

## Specular reflection intensity
@export_range(0.0, 2.0, 0.05) var specular_strength: float = 0.5:
	set(v):
		specular_strength = v
		emit_changed()

## Ambient occlusion / ambient cavity shadow map
@export var ambient_texture: Texture2D:
	set(v):
		ambient_texture = v
		emit_changed()

## Ambient occlusion influence
@export_range(0.0, 2.0, 0.05) var ambient_strength: float = 1.0:
	set(v):
		ambient_strength = v
		emit_changed()

## Height / displacement texture for parallax occlusion / depth shift
@export var displacement_texture: Texture2D:
	set(v):
		displacement_texture = v
		emit_changed()

## Displacement depth scale (parallax occlusion depth factor)
@export_range(0.0, 0.1, 0.002) var displacement_scale: float = 0.025:
	set(v):
		displacement_scale = v
		emit_changed()

## Minimum raymarch steps when viewing surface head-on
@export_range(4, 32, 1) var displacement_min_layers: int = 8:
	set(v):
		displacement_min_layers = v
		emit_changed()

## Maximum raymarch steps when viewing surface at a steep grazing angle
@export_range(8, 64, 1) var displacement_max_layers: int = 24:
	set(v):
		displacement_max_layers = v
		emit_changed()

@export_group("Geometry & Placement")
## Distance from the arena center (equatorial radius of the dome)
@export var radius: float = 65.0:
	set(v):
		radius = v
		emit_changed()

## Total height of the dome from top cap to bottom cap center
@export var height: float = 80.0:
	set(v):
		height = v
		emit_changed()

## Vertical positioning of the dome center relative to arena floor (Y = 0)
@export var vertical_offset: float = 18.0:
	set(v):
		vertical_offset = v
		emit_changed()

@export_group("Dome Shape")
## Flattening of the top dome cap.
## 0.0 = full hemisphere (curved top like a sky dome pole)
## 1.0 = flattened down to the equator ring level (horizontal disk / cylinder top rim)
@export_range(0.0, 1.0, 0.01) var top_flatten: float = 0.0:
	set(v):
		top_flatten = v
		emit_changed()

## Flattening of the bottom dome cap.
## 0.0 = full hemisphere bottom pole (curved under)
## 1.0 = flattened up to the equator ring level (horizontal floor disk / cylinder bottom rim)
@export_range(0.0, 1.0, 0.01) var bottom_flatten: float = 1.0:
	set(v):
		bottom_flatten = v
		emit_changed()

## Where in the panorama texture the top pole maps to.
## Lower/raise to scroll/stretch the top cap independently without affecting the sides.
@export_range(0.0, 1.0, 0.005) var uv_top: float = 0.0:
	set(v):
		uv_top = v
		emit_changed()

## The texture UV.y anchor for the dome's equator (the horizontal sides/horizon line).
## Locking this ensures the sides of the ball perfectly match the panorama horizon (default 0.5).
@export_range(0.0, 1.0, 0.005) var uv_equator: float = 0.5:
	set(v):
		uv_equator = v
		emit_changed()

## Where in the panorama texture the bottom pole maps to.
## Lower/raise to scroll/stretch the bottom cap independently without affecting the sides.
@export_range(0.0, 1.0, 0.005) var uv_bottom: float = 1.0:
	set(v):
		uv_bottom = v
		emit_changed()

## Number of latitude rings in the dome mesh (more = smoother curvature)
@export_range(4, 32, 1) var lat_segments: int = 12:
	set(v):
		lat_segments = v
		emit_changed()

## Number of longitude segments around the circumference (more = smoother circle)
@export_range(16, 128, 1) var lon_segments: int = 64:
	set(v):
		lon_segments = v
		emit_changed()

@export_group("Tiling & Alignment")
## How many times the texture wraps horizontally around the 360 dome
@export_range(0.5, 8.0, 0.5) var horizontal_repeats: float = 1.0:
	set(v):
		horizontal_repeats = v
		emit_changed()

## Horizontal rotation offset (0.0–1.0 wraps around 360°) to align a feature to front
@export_range(0.0, 1.0, 0.005) var rotation_offset_uv: float = 0.0:
	set(v):
		rotation_offset_uv = v
		emit_changed()

@export_group("Perspective & Optical Camera Warping")
## Horizontal parallax shift as camera yaws — operates in seam-safe angular space
@export_range(0.0, 0.5, 0.005) var camera_yaw_parallax: float = 0.04:
	set(v):
		camera_yaw_parallax = v
		emit_changed()

## Vertical parallax shift as camera pitches up/down
@export_range(0.0, 0.3, 0.005) var camera_pitch_parallax: float = 0.02:
	set(v):
		camera_pitch_parallax = v
		emit_changed()

## Optical zoom factor (1.0 = no zoom, <1.0 = zoom out, >1.0 = zoom in)
@export_range(0.5, 2.0, 0.05) var zoom_scale: float = 1.0:
	set(v):
		zoom_scale = v
		emit_changed()

## Barrel/pincushion FOV warp to match camera lens distortion
@export_range(0.0, 0.5, 0.01) var fov_warp: float = 0.05:
	set(v):
		fov_warp = v
		emit_changed()

@export_group("Vibrance & Lighting")
## Emission energy multiplier — boost to keep panorama vivid like a skybox
@export_range(0.0, 4.0, 0.05) var emission_energy: float = 1.5:
	set(v):
		emission_energy = v
		emit_changed()

## Color saturation boost (1.0 = normal, >1.0 = extra vivid)
@export_range(0.0, 2.5, 0.05) var color_saturation: float = 1.25:
	set(v):
		color_saturation = v
		emit_changed()

@export var modulate: Color = Color(1.0, 1.0, 1.0, 1.0):
	set(v):
		modulate = v
		emit_changed()

@export_group("Edge Blending")
## Soft fade on the top pole/rim (UV.y = 0) to blend into skybox above
@export_range(0.0, 0.5, 0.01) var top_fade_margin: float = 0.1:
	set(v):
		top_fade_margin = v
		emit_changed()

## Soft fade on the bottom pole/rim (UV.y = 1) to blend into arena floor
@export_range(0.0, 0.5, 0.01) var bottom_fade_margin: float = 0.0:
	set(v):
		bottom_fade_margin = v
		emit_changed()

## Chromatic aberration (RGB split at edges for cinematic feel)
@export_range(0.0, 0.02, 0.001) var chromatic_blur: float = 0.0:
	set(v):
		chromatic_blur = v
		emit_changed()

@export_group("Rendering")
@export var render_priority: int = -5:
	set(v):
		render_priority = v
		emit_changed()
