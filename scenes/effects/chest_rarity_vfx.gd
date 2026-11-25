class_name ChestRarityVFX
extends Node3D
## Rarity-colored chest opening effects, styled to match the low-poly PS2 look:
## faceted geometry, hard edges, posterized brightness, choppy (stepped) motion and
## square "pixel" particles.
##   fit_to_chest(...) - sizes and places everything from the measured chest body
##   charge(step)      - rarity light leaks out and pixels puff off the chest while it shakes
##   burst()           - lid opens: beam shoots up, shockwave ring, sparks, light flash,
##                       then glints keep rising from the rim
##   rays              - spinning spikes that follow the item, always drawn behind it
##
## Nothing is sized for a specific chest model: every size is a proportion of the
## chest the VFX is fitted to (rim height and opening size), scaled by rarity tier.

const BEAM_SHADER := preload("res://assets/effects/shaders/rarity_beam.gdshader")
const RING_SHADER := preload("res://assets/effects/shaders/rarity_ring.gdshader")
const RAYS_SHADER := preload("res://assets/effects/shaders/rarity_rays.gdshader")

## Per-tier settings. Index = tier (see Vestige.get_rarity_tier).
##   beam_radius: fraction of the chest opening's half-width
##   beam_height: multiple of the chest's footprint size
##   ring_size:   multiple of the chest's footprint size (full diameter)
##   rays_length: spike length in item-local units (the rays live on the item)
const TIERS := [
	{"beam_radius": 0.7, "beam_height": 2.8, "beam_intensity": 0.55, "ring_size": 2.7, "sparks": 12, "light": 1.5, "rays": 0.45, "rays_length": 0.13, "rays_count": 6},
	{"beam_radius": 0.85, "beam_height": 3.9, "beam_intensity": 0.8, "ring_size": 3.6, "sparks": 20, "light": 2.5, "rays": 0.6, "rays_length": 0.16, "rays_count": 8},
	{"beam_radius": 1.0, "beam_height": 5.5, "beam_intensity": 1.05, "ring_size": 4.5, "sparks": 32, "light": 3.5, "rays": 0.8, "rays_length": 0.2, "rays_count": 10},
	{"beam_radius": 1.2, "beam_height": 7.3, "beam_intensity": 1.35, "ring_size": 6.0, "sparks": 48, "light": 5.0, "rays": 1.0, "rays_length": 0.25, "rays_count": 12},
]

## Size of one square spark/mote, in world units
@export var pixel_particle_size: float = 0.022
## Beam brightness after the burst settles, relative to the tier's value
@export_range(0.0, 1.0) var idle_beam_level: float = 0.6

var color: Color = Color.WHITE
var tier: int = 0

## Chest measurements (set by fit_to_chest, in this node's parent space)
var rim_height: float = 0.15
var opening_size: Vector2 = Vector2(0.44, 0.28)
var opening_center: Vector3 = Vector3.ZERO

var beam: MeshInstance3D
var ring: MeshInstance3D
var rays: MeshInstance3D
var light: OmniLight3D
var sparks: GPUParticles3D
var motes: GPUParticles3D
var puff: GPUParticles3D
var glints: GPUParticles3D

var _beam_mat: ShaderMaterial
var _ring_mat: ShaderMaterial
var _rays_mat: ShaderMaterial
var _tween: Tween
var _charge_tween: Tween


func _ready() -> void:
	_build()
	_apply()
	reset()


## Sets the rarity look. Call before charge()/burst()
func set_rarity(new_color: Color, new_tier: int) -> void:
	color = new_color
	tier = clampi(new_tier, 0, TIERS.size() - 1)
	_apply()


## Fits every effect to a chest: `rim` = top of the body (where the lid sits),
## `opening` = body footprint (x, z), `center` = body center on the ground plane
func fit_to_chest(rim: float, opening: Vector2, center: Vector3) -> void:
	rim_height = rim
	opening_size = opening
	opening_center = Vector3(center.x, 0.0, center.z)
	_apply()


## Reparents the spinning rays onto the revealed item so they follow and grow with it
func attach_rays_to(target: Node3D) -> void:
	if not rays or not target:
		return
	if rays.get_parent():
		rays.get_parent().remove_child(rays)
	target.add_child(rays)
	rays.position = Vector3.ZERO


## Pre-open pulse: stronger with each step, hints the rarity color
func charge(step: int) -> void:
	if _charge_tween:
		_charge_tween.kill()
	var p: Dictionary = TIERS[tier]
	var peak := float(p["light"]) * (0.25 + 0.2 * step)
	var rest := float(p["light"]) * (0.08 + 0.06 * step)
	light.visible = true
	if step > 0:
		puff.restart()
	_charge_tween = create_tween()
	_charge_tween.tween_property(light, "light_energy", peak, 0.06)
	_charge_tween.tween_property(light, "light_energy", rest, 0.35).set_ease(Tween.EASE_OUT)


## The lid opens: the beam shoots up, ring and sparks burst out, the light flashes
func burst() -> void:
	if _charge_tween:
		_charge_tween.kill()
	if _tween:
		_tween.kill()

	var p: Dictionary = TIERS[tier]
	var beam_intensity := float(p["beam_intensity"])
	var light_energy := float(p["light"])

	beam.visible = true
	ring.visible = true
	light.visible = true
	_beam_mat.set_shader_parameter("reveal", 0.0)
	_beam_mat.set_shader_parameter("intensity", beam_intensity * 2.0)
	_ring_mat.set_shader_parameter("progress", 0.0)
	beam.scale = Vector3(0.3, 1.0, 0.3)

	sparks.restart()
	motes.emitting = true
	glints.emitting = true

	_tween = create_tween().set_parallel(true)
	# Beam shoots up from the chest and pops wide, then settles
	_tween.tween_method(_set_beam_reveal, 0.0, 1.0, 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(beam, "scale", Vector3(1.35, 1.0, 1.35), 0.15).set_ease(Tween.EASE_OUT)
	_tween.tween_property(beam, "scale", Vector3.ONE, 0.5).set_delay(0.15).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_ELASTIC)
	_tween.tween_method(_set_beam_intensity, beam_intensity * 2.0, beam_intensity * idle_beam_level, 1.2) \
		.set_delay(0.2).set_ease(Tween.EASE_OUT)
	# Ground shockwave
	_tween.tween_method(_set_ring_progress, 0.0, 1.0, 0.7).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUART)
	# Light flash then settle to a steady glow
	_tween.tween_property(light, "light_energy", light_energy * 2.0, 0.06)
	_tween.tween_property(light, "light_energy", light_energy * 0.6, 1.0).set_delay(0.06).set_ease(Tween.EASE_OUT)
	# Rays fade in once the item starts to rise
	rays.visible = true
	_set_rays_intensity(0.0)
	_tween.tween_method(_set_rays_intensity, 0.0, float(p["rays"]), 0.6).set_delay(0.25)


## Hides everything and returns to the pre-charge state
func reset() -> void:
	if _tween:
		_tween.kill()
	if _charge_tween:
		_charge_tween.kill()
	if rays and rays.get_parent() != self:
		rays.get_parent().remove_child(rays)
		add_child(rays)
	beam.visible = false
	ring.visible = false
	rays.visible = false
	light.visible = false
	light.light_energy = 0.0
	motes.emitting = false
	glints.emitting = false
	_set_beam_reveal(0.0)
	_set_ring_progress(0.0)
	_set_rays_intensity(0.0)


# --- Building -------------------------------------------------------------------

func _build() -> void:
	_beam_mat = ShaderMaterial.new()
	_beam_mat.shader = BEAM_SHADER
	beam = _make_mesh_instance("Beam", _beam_mat)
	beam.mesh = QuadMesh.new()
	# The shader turns the column toward the camera; keep it from being culled
	beam.extra_cull_margin = 1.0

	_ring_mat = ShaderMaterial.new()
	_ring_mat.shader = RING_SHADER
	ring = _make_mesh_instance("Ring", _ring_mat)
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE
	ring.mesh = plane

	# Rays start here and get reparented onto the item at the burst
	_rays_mat = ShaderMaterial.new()
	_rays_mat.shader = RAYS_SHADER
	rays = _make_mesh_instance("Rays", _rays_mat)
	# The shader moves the spikes in view space; keep them from being culled
	rays.extra_cull_margin = 1.0

	# Light that leaks out while charging and glows after opening
	light = OmniLight3D.new()
	light.name = "Light"
	light.omni_attenuation = 1.5
	light.shadow_enabled = false
	add_child(light)

	# One-shot burst of square sparks
	sparks = GPUParticles3D.new()
	sparks.name = "Sparks"
	sparks.one_shot = true
	sparks.explosiveness = 1.0
	sparks.lifetime = 1.2
	sparks.fixed_fps = 12  # choppy, low-framerate motion
	sparks.interpolate = false
	sparks.emitting = false
	sparks.process_material = _make_spark_process()
	sparks.draw_pass_1 = _make_pixel_quad(pixel_particle_size)
	add_child(sparks)

	# Square motes drifting up the beam's wall (not through its middle, where the item is)
	motes = GPUParticles3D.new()
	motes.name = "Motes"
	motes.lifetime = 2.2
	motes.amount = 12
	motes.fixed_fps = 12
	motes.interpolate = false
	motes.emitting = false
	motes.process_material = _make_mote_process()
	motes.draw_pass_1 = _make_pixel_quad(pixel_particle_size * 0.7)
	add_child(motes)

	# Build-up puff: a ring of pixels popping off the chest body on each shake
	puff = GPUParticles3D.new()
	puff.name = "Puff"
	puff.one_shot = true
	puff.explosiveness = 1.0
	puff.amount = 10
	puff.lifetime = 0.8
	puff.fixed_fps = 12
	puff.interpolate = false
	puff.emitting = false
	puff.process_material = _make_puff_process()
	puff.draw_pass_1 = _make_pixel_quad(pixel_particle_size * 0.8)
	add_child(puff)

	# After opening: diamond glints drifting up out of the rim
	glints = GPUParticles3D.new()
	glints.name = "Glints"
	glints.amount = 8
	glints.lifetime = 1.6
	glints.fixed_fps = 12
	glints.interpolate = false
	glints.emitting = false
	glints.process_material = _make_glint_process()
	glints.draw_pass_1 = _make_pixel_quad(pixel_particle_size * 1.4)
	add_child(glints)


func _make_mesh_instance(node_name: String, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


## Rebuilds sizes/positions from the chest measurements and the rarity tier
func _apply() -> void:
	if not beam:
		return
	var p: Dictionary = TIERS[tier]
	var footprint := maxf(opening_size.x, opening_size.y)
	var opening_half := minf(opening_size.x, opening_size.y) * 0.5

	# Beam: low-sided prism rising from just inside the rim
	var radius := opening_half * float(p["beam_radius"])
	var height := footprint * float(p["beam_height"])
	var base := rim_height - opening_half * 0.3
	(beam.mesh as QuadMesh).size = Vector2(radius * 2.0, height)
	beam.position = opening_center + Vector3(0.0, base + height * 0.5, 0.0)
	_beam_mat.set_shader_parameter("beam_height", height)
	# Sit behind the item (on the axis) but in front of the chest's back wall
	_beam_mat.set_shader_parameter("push_back", opening_half * 0.6)
	_beam_mat.set_shader_parameter("beam_color", color)

	# Ground ring around the chest
	ring.position = opening_center + Vector3(0.0, 0.02, 0.0)
	ring.scale = Vector3.ONE * footprint * float(p["ring_size"])
	_ring_mat.set_shader_parameter("ring_color", color)

	# Rays: sized for the item (they live on it), not for the chest
	rays.mesh = _build_rays_mesh(int(p["rays_count"]), float(p["rays_length"]))
	_rays_mat.set_shader_parameter("ray_color", color)

	# Light sits inside the chest so it leaks out around the lid
	light.position = opening_center + Vector3(0.0, rim_height * 0.9, 0.0)
	light.omni_range = footprint * 7.0
	light.light_color = color

	# Sparks pop out of the opening; motes climb the beam's wall
	sparks.position = opening_center + Vector3(0.0, rim_height, 0.0)
	sparks.amount = int(p["sparks"])
	var spark_mat := sparks.process_material as ParticleProcessMaterial
	spark_mat.color = color
	spark_mat.emission_sphere_radius = opening_half * 0.6
	spark_mat.initial_velocity_min = footprint * 2.7
	spark_mat.initial_velocity_max = footprint * 5.0

	motes.position = opening_center + Vector3(0.0, base, 0.0)
	var mote_mat := motes.process_material as ParticleProcessMaterial
	mote_mat.color = color
	mote_mat.emission_ring_radius = radius * 0.9
	mote_mat.emission_ring_inner_radius = radius * 0.7
	mote_mat.emission_ring_height = 0.01

	puff.position = opening_center + Vector3(0.0, rim_height * 0.45, 0.0)
	var puff_mat := puff.process_material as ParticleProcessMaterial
	puff_mat.color = color.lerp(Color.WHITE, 0.3)
	puff_mat.emission_box_extents = Vector3(opening_size.x * 0.55, rim_height * 0.45, opening_size.y * 0.55)
	puff_mat.initial_velocity_min = footprint * 0.4
	puff_mat.initial_velocity_max = footprint * 1.0

	glints.position = opening_center + Vector3(0.0, rim_height, 0.0)
	glints.amount = 6 + tier * 3
	var glint_mat := glints.process_material as ParticleProcessMaterial
	glint_mat.color = color.lerp(Color.WHITE, 0.45)
	glint_mat.emission_box_extents = Vector3(opening_size.x * 0.35, 0.02, opening_size.y * 0.35)


## Star of flat triangle spikes in the XY plane. Vertex color red = heat
## (1 at the center, 0 at the tips), which the shader posterizes into bands.
## Spikes alternate long/short like classic loot rays.
func _build_rays_mesh(count: int, length: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half_width := PI / count * 0.5
	for i in count:
		var angle := TAU * i / count
		var spike_len := length * (1.0 if i % 2 == 0 else 0.6)
		var shoulder := spike_len * 0.25
		var tip := Vector2.from_angle(angle) * spike_len
		var left := Vector2.from_angle(angle - half_width) * shoulder
		var right := Vector2.from_angle(angle + half_width) * shoulder
		for tri in [[Vector2.ZERO, left, tip], [Vector2.ZERO, tip, right]]:
			for v: Vector2 in tri:
				var heat := 1.0 if v == Vector2.ZERO else (0.0 if v == tip else 0.6)
				st.set_color(Color(heat, heat, heat))
				st.add_vertex(Vector3(v.x, v.y, 0.0))
	return st.commit()


func _make_spark_process() -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.direction = Vector3.UP
	m.spread = 40.0
	m.gravity = Vector3(0, -4.0, 0)
	m.damping_min = 0.5
	m.damping_max = 1.5
	m.scale_min = 0.7
	m.scale_max = 1.3
	m.scale_curve = _make_step_curve_texture()
	return m


func _make_mote_process() -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	m.emission_ring_axis = Vector3.UP
	m.direction = Vector3.UP
	m.spread = 4.0
	m.initial_velocity_min = 0.25
	m.initial_velocity_max = 0.55
	m.gravity = Vector3.ZERO
	m.scale_min = 0.7
	m.scale_max = 1.2
	m.scale_curve = _make_step_curve_texture()
	return m


func _make_puff_process() -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.direction = Vector3.UP
	m.spread = 70.0
	m.gravity = Vector3(0, -1.5, 0)
	m.damping_min = 1.0
	m.damping_max = 2.0
	m.scale_min = 0.6
	m.scale_max = 1.1
	m.scale_curve = _make_step_curve_texture()
	return m


func _make_glint_process() -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.direction = Vector3.UP
	m.spread = 15.0
	m.initial_velocity_min = 0.1
	m.initial_velocity_max = 0.3
	m.gravity = Vector3.ZERO
	# Squares turned 45 degrees read as little diamonds/stars
	m.angle_min = 45.0
	m.angle_max = 45.0
	m.scale_min = 0.6
	m.scale_max = 1.2
	m.scale_curve = _make_step_curve_texture()
	return m


## Scale curve that shrinks in a few hard steps (no smooth fade)
func _make_step_curve_texture() -> CurveTexture:
	var curve := Curve.new()
	for step in [[0.0, 1.0], [0.45, 1.0], [0.46, 0.66], [0.7, 0.66], [0.71, 0.33], [0.9, 0.33], [0.91, 0.0]]:
		curve.add_point(Vector2(step[0], step[1]), 0.0, 0.0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	var tex := CurveTexture.new()
	tex.curve = curve
	return tex


## Solid square that faces the camera: an additive "pixel" tinted by the particle color
func _make_pixel_quad(size: float) -> QuadMesh:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.disable_fog = true

	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	quad.material = mat
	return quad


# --- Tween helpers -------------------------------------------------------------

func _set_beam_reveal(v: float) -> void:
	_beam_mat.set_shader_parameter("reveal", v)

func _set_beam_intensity(v: float) -> void:
	_beam_mat.set_shader_parameter("intensity", v)

func _set_ring_progress(v: float) -> void:
	_ring_mat.set_shader_parameter("progress", v)

func _set_rays_intensity(v: float) -> void:
	_rays_mat.set_shader_parameter("intensity", v)
