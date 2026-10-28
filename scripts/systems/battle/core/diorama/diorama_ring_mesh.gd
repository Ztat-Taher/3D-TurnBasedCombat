class_name DioramaRingMesh
extends Object
## Generates a parametric dome mesh for 360 panorama diorama rings.
##
## UV mapping baked into vertices:
##   UV.x = [0.0, 1.0] around the full 360° circumference
##   UV.y = [uv_top, uv_bottom] mapped from top pole → bottom pole
##          uv_top   = which row of the texture maps to the top pole   (default 0.0 = texture top)
##          uv_bottom= which row of the texture maps to the bottom pole (default 1.0 = texture bottom)
##          Example: uv_top=0.1, uv_bottom=0.7  → only 10%-70% of the panorama is shown
##          Example: uv_top=0.0, uv_bottom=0.5  → only the top half of the panorama
##          Example: uv_top=0.25, uv_bottom=0.75 → centered band only
##   UV2.y = equator proximity (1.0 at equator, 0.0 at poles) for pole fade in shader.
##
## Flattening controls shape WITHOUT cutting off texture content:
##   top_flatten    0.0 = curved hemisphere top (full dome peak)
##                  1.0 = flattened down to equator ring level (horizontal disk / cylinder top rim)
##   bottom_flatten 0.0 = curved hemisphere bottom (bowl under the arena)
##                  1.0 = flattened up to equator ring level (horizontal floor disk / cylinder bottom rim)
##
## Normals point INWARD so the camera sees the inside of the dome.

## Create the dome mesh.
## @param radius        Equatorial radius of the dome.
## @param height        Total height from top cap to bottom cap level.
## @param top_flatten   0 = curved sphere top, 1 = flat disk lid.
## @param bottom_flatten 0 = curved sphere bottom, 1 = flat disk floor.
## @param uv_top        Texture UV.y value at the top pole (default 0.0).
## @param uv_equator    Texture UV.y anchor value at the equator/sides (default 0.5).
## @param uv_bottom     Texture UV.y value at the bottom pole (default 1.0).
## @param lat_segments  Latitude ring count (more = smoother cap curvature).
## @param lon_segments  Longitude segment count (more = smoother circumference).
static func create_dome_mesh(
		radius: float,
		height: float,
		top_flatten: float = 0.0,
		bottom_flatten: float = 1.0,
		uv_top: float = 0.0,
		uv_equator: float = 0.5,
		uv_bottom: float = 1.0,
		lat_segments: int = 12,
		lon_segments: int = 64
) -> ArrayMesh:
	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)

	top_flatten    = clampf(top_flatten,    0.0, 1.0)
	bottom_flatten = clampf(bottom_flatten, 0.0, 1.0)

	var half_h := height * 0.5

	# -------------------------------------------------------------------
	# Vertex grid: lat=0 → top cap, lat=lat_segments → bottom cap
	#
	# lat_angle sweeps PI/2 (top) → 0 (equator) → -PI/2 (bottom)
	#
	# ring_radius = cos(lat_angle) * radius  — unchanged by flatten.
	#   At the top pole: radius=0, then fans to full radius at equator.
	#   This means a flattened top becomes a horizontal disk that still
	#   renders the zenith part of the texture concentrically.
	#
	# Y position:
	#   top half:    lerp(sphere_y, +half_h, top_flatten)
	#   bottom half: lerp(sphere_y, -half_h, bottom_flatten)
	#
	# UV.y baked per-vertex = lerp(uv_top, uv_bottom, v_ratio)
	#   where v_ratio goes 0 (top pole) → 1 (bottom pole)
	#   This maps any sub-region of the panorama texture to the dome.
	#
	# UV2.y = cos(lat_angle) = equator proximity for pole-based fade.
	# -------------------------------------------------------------------

	var verts: Array = []

	for lat in range(lat_segments + 1):
		var v_ratio := float(lat) / float(lat_segments)

		# Sphere latitude angle: +PI/2 at top pole, -PI/2 at bottom pole
		var lat_angle := PI * 0.5 - v_ratio * PI

		# Horizontal ring radius — unchanged by flatten so all texture rows remain visible
		var ring_radius := cos(lat_angle) * radius

		# Y position: sphere base, then flatten toward equator (y = 0.0)
		var sphere_y := sin(lat_angle) * half_h
		var y: float
		if lat_angle >= 0.0:
			y = lerp(sphere_y, 0.0, top_flatten)
		else:
			y = lerp(sphere_y, 0.0, bottom_flatten)

		# Baked UV.y: Piecewise mapping anchored at the equator (v_ratio = 0.5)
		# Top hemisphere: maps [0.0 (top pole) .. 0.5 (equator)] -> [uv_top .. uv_equator]
		# Bottom hemisphere: maps [0.5 (equator) .. 1.0 (bottom pole)] -> [uv_equator .. uv_bottom]
		# This pins the sides of the panorama to the equator while letting top and bottom
		# scroll/stretch like ribbon ends independently without squishing or moving the sides.
		var baked_v: float
		if v_ratio <= 0.5:
			var t := v_ratio * 2.0  # 0.0 at top pole -> 1.0 at equator
			baked_v = lerpf(uv_top, uv_equator, t)
		else:
			var t := (v_ratio - 0.5) * 2.0  # 0.0 at equator -> 1.0 at bottom pole
			baked_v = lerpf(uv_equator, uv_bottom, t)

		# UV2.y: equator proximity for smooth pole fade in shader
		var equator_prox := cos(lat_angle)   # 1.0 at equator, 0.0 at poles

		var lat_verts := []
		for lon in range(lon_segments + 1):
			var u_ratio := float(lon) / float(lon_segments)
			var lon_angle := u_ratio * TAU

			var x := sin(lon_angle) * ring_radius
			var z := cos(lon_angle) * ring_radius

			# Inward-facing normal from sphere latitude
			var nx := -sin(lon_angle) * cos(lat_angle)
			var ny := -sin(lat_angle)
			var nz := -cos(lon_angle) * cos(lat_angle)

			# At poles the horizontal component vanishes — pure axial normal
			if ring_radius < 0.0001:
				nx = 0.0; nz = 0.0
				ny = -1.0 if lat_angle >= 0.0 else 1.0

			# Fully flat caps: axial normal for consistent lighting on the disk
			if lat_angle >= 0.0 and top_flatten > 0.99:
				nx = 0.0; ny = -1.0; nz = 0.0
			elif lat_angle < 0.0 and bottom_flatten > 0.99:
				nx = 0.0; ny = 1.0; nz = 0.0

			# Tangent pointing horizontally along longitude (+X direction relative to ring angle)
			var tx := cos(lon_angle)
			var ty := 0.0
			var tz := -sin(lon_angle)

			lat_verts.append({
				"pos":         Vector3(x, y, z),
				"normal":      Vector3(nx, ny, nz).normalized(),
				"tangent":     Plane(tx, ty, tz, 1.0),
				"uv":          Vector2(u_ratio, baked_v),
				"equator_prox": equator_prox,
			})
		verts.append(lat_verts)

	# -------------------------------------------------------------------
	# Emit vertices
	# -------------------------------------------------------------------
	for lat in range(lat_segments + 1):
		for lon in range(lon_segments + 1):
			var d: Dictionary = verts[lat][lon]
			surface_tool.set_normal(d["normal"])
			surface_tool.set_tangent(d["tangent"])
			surface_tool.set_uv(d["uv"])
			surface_tool.set_uv2(Vector2(d["uv"].x, d["equator_prox"]))
			surface_tool.add_vertex(d["pos"])

	# -------------------------------------------------------------------
	# Triangle indices (inward-facing winding)
	# -------------------------------------------------------------------
	var stride := lon_segments + 1
	for lat in range(lat_segments):
		for lon in range(lon_segments):
			var i0 := lat * stride + lon
			var i1 := i0 + 1
			var i2 := (lat + 1) * stride + lon
			var i3 := i2 + 1

			surface_tool.add_index(i0)
			surface_tool.add_index(i2)
			surface_tool.add_index(i1)

			surface_tool.add_index(i1)
			surface_tool.add_index(i2)
			surface_tool.add_index(i3)

	return surface_tool.commit()
