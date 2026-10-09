class_name Island
extends Node3D
## The TV's 3D board: sea, sky and light, the island of fields with their
## number tokens, everyone's hamlets, towns and roads, and the storm.
## `build` raises a new island; `sync` brings pieces up to date with the
## rules, animating whatever changed.

const S := Art.S
const GROUND := Art.GROUND
const TOKEN_FONT := preload("res://assets/fonts/AlegreyaSC-Bold.ttf")
const PIECE_SCALE := 1.45
const WATER := preload("res://src/world/water.gdshader")

var camera: Camera3D
var sun: DirectionalLight3D
var land: Node3D
var tiles := {}            # tile id -> Node3D
var tokens := {}           # tile id -> Node3D
var verts := {}            # vertex id -> Node3D
var edges := {}            # edge id -> Node3D
var markers: Node3D
var storm: Node3D
var storm_tile := 0
var clouds: Array = []
var spinners: Array = []
var ground_mat: StandardMaterial3D
var lake_mat: ShaderMaterial
var marker_mat: StandardMaterial3D
var centre := Vector3.ZERO
var radius := 10.0
var sway := 0.0
var dof: CameraAttributesPractical
## Fixed camera angle for screenshots and tests; negative means sway.
var still := -1.0
var _piece_cache := {}


func _ready() -> void:
	ground_mat = StandardMaterial3D.new()
	ground_mat.vertex_color_use_as_albedo = true
	ground_mat.vertex_color_is_srgb = true
	ground_mat.roughness = 0.88
	ground_mat.specular = 0.25
	lake_mat = ShaderMaterial.new()
	lake_mat.shader = WATER
	lake_mat.set_shader_parameter("depth_scale", 0.35)
	lake_mat.set_shader_parameter("foam_width", 0.08)
	lake_mat.set_shader_parameter("wave_height", 0.0)
	lake_mat.set_shader_parameter("shallow", Color(0.36, 0.72, 0.74))
	lake_mat.set_shader_parameter("deep", Color(0.12, 0.42, 0.55))
	marker_mat = StandardMaterial3D.new()
	marker_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	marker_mat.albedo_color = Color(1, 0.97, 0.8, 0.85)
	marker_mat.emission_enabled = true
	marker_mat.emission = Color(1, 0.9, 0.55)
	_setup_world()


func _setup_world() -> void:
	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("6f9fd0")
	sky_mat.sky_horizon_color = Color("e9d6b8")
	sky_mat.ground_horizon_color = Color("bfc9c2")
	sky_mat.ground_bottom_color = Color("2b4f66")
	sky_mat.sun_angle_max = 20.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.6
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	env.ssao_enabled = true
	env.ssao_radius = 0.6
	env.ssao_intensity = 1.6
	env.ssao_power = 1.3
	env.glow_enabled = true
	env.glow_intensity = 0.2
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.fog_enabled = true
	env.fog_light_color = Color("c9dbe6")
	env.fog_density = 0.0012
	env.fog_sky_affect = 0.2
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.2
	env.adjustment_contrast = 1.08
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.light_color = Color("fff0d6")
	sun.light_energy = 1.7
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	sun.directional_shadow_max_distance = 90.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.rotation = Vector3(deg_to_rad(-36), deg_to_rad(-40), 0)
	add_child(sun)
	# A cool fill from the other side keeps shadows from going flat.
	var fill := DirectionalLight3D.new()
	fill.light_color = Color("9fc3ff")
	fill.light_energy = 0.25
	fill.rotation = Vector3(deg_to_rad(-30), deg_to_rad(150), 0)
	add_child(fill)

	var sea := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(400, 400)
	plane.subdivide_width = 160
	plane.subdivide_depth = 160
	sea.mesh = plane
	var sea_mat := ShaderMaterial.new()
	sea_mat.shader = WATER
	sea.material_override = sea_mat
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sea)
	var floor_node := MeshInstance3D.new()
	var floor_plane := PlaneMesh.new()
	floor_plane.size = Vector2(400, 400)
	floor_node.mesh = floor_plane
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color("8c8a62")
	floor_mat.roughness = 1.0
	floor_node.material_override = floor_mat
	floor_node.position.y = -1.7
	add_child(floor_node)

	for i in 0:
		var cloud := MeshInstance3D.new()
		cloud.mesh = Art.cloud(i + 1)
		cloud.material_override = ground_mat
		cloud.scale = Vector3.ONE * randf_range(2.2, 3.4)
		cloud.position = Vector3(randf_range(-30, 30), randf_range(11, 14), randf_range(-30, 20))
		cloud.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(cloud)
		clouds.append(cloud)

	camera = Camera3D.new()
	camera.fov = 30.0
	camera.far = 600.0
	# A touch of tilt-shift: the far shore softens like a model on a table.
	dof = CameraAttributesPractical.new()
	dof.dof_blur_far_enabled = true
	dof.dof_blur_amount = 0.06
	camera.attributes = dof
	add_child(camera)

	markers = Node3D.new()
	add_child(markers)


## Raise a fresh island for this game.
func build(s: Rules, seed_value: int, animate := true) -> void:
	if land:
		land.queue_free()
	land = Node3D.new()
	add_child(land)
	tiles.clear()
	tokens.clear()
	verts.clear()
	edges.clear()
	spinners.clear()
	_clear_markers()
	var cells: Array = []
	var lo := Vector3(INF, 0, INF)
	var hi := Vector3(-INF, 0, -INF)
	for t in s.tiles:
		cells.append(Vector2i(t.q, t.r))
		var node := Node3D.new()
		land.add_child(node)
		var built := Art.field(t.res, Vector2(t.x, t.y), seed_value * 31 + t.id)
		var mesh := MeshInstance3D.new()
		mesh.mesh = built.mesh
		mesh.material_override = ground_mat
		node.add_child(mesh)
		for extra in built.extras:
			node.add_child(extra)
			if extra.has_meta("water"):
				extra.material_override = lake_mat
				extra.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			else:
				extra.material_override = ground_mat
			if extra.has_meta("spin"):
				spinners.append(extra)
		if t.res != "":
			var token := _token(t.num)
			var spot := Vector2(t.x, t.y) * S + Vector2(0, S * 0.42)
			token.position = Vector3(spot.x, GROUND - 0.01, spot.y)
			node.add_child(token)
			tokens[t.id] = token
		tiles[t.id] = node
		var p := Vector3(t.x * S, 0, t.y * S)
		lo = Vector3(minf(lo.x, p.x), 0, minf(lo.z, p.z))
		hi = Vector3(maxf(hi.x, p.x), 0, maxf(hi.z, p.z))
	var shore := MeshInstance3D.new()
	shore.mesh = Art.shore(cells, seed_value)
	shore.material_override = ground_mat
	land.add_child(shore)
	centre = (lo + hi) / 2.0
	radius = maxf(hi.x - lo.x, hi.z - lo.z) / 2.0 + S * 1.4
	storm_tile = 0
	if storm:
		storm.queue_free()
		storm = null
	_place_storm(s.storm, false)
	if animate:
		_rise(shore)
	sync(s, false)


func _token(num: int) -> Node3D:
	var node := Node3D.new()
	var disc := MeshInstance3D.new()
	disc.mesh = Art.token_disc()
	disc.material_override = ground_mat
	node.add_child(disc)
	var hot := Rules.pips(num) == 5
	var ink := Color("b3261b") if hot else Color("3a2a1c")
	var label := Label3D.new()
	label.text = str(num)
	label.font = TOKEN_FONT
	label.font_size = 150
	label.pixel_size = 0.0032
	label.modulate = ink
	label.outline_size = 0
	label.rotation_degrees = Vector3(-90, 0, 0)
	label.position = Vector3(0, 0.1, -0.03)
	label.double_sided = false
	label.shaded = true
	node.add_child(label)
	var dots := Label3D.new()
	dots.text = "•".repeat(Rules.pips(num))
	dots.font = TOKEN_FONT
	dots.font_size = 96
	dots.pixel_size = 0.0028
	dots.modulate = ink
	dots.rotation_degrees = Vector3(-90, 0, 0)
	dots.position = Vector3(0, 0.1, 0.24)
	dots.shaded = true
	node.add_child(dots)
	return node


## Fields come up out of the sea one after another, from the middle out.
func _rise(shore: Node3D) -> void:
	shore.position.y = -2.5
	var tw := create_tween()
	tw.tween_property(shore, "position:y", 0.0, 1.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	for id in tiles:
		var node: Node3D = tiles[id]
		var d := Vector2(node.get_child(0).get_aabb().get_center().x - centre.x, node.get_child(0).get_aabb().get_center().z - centre.z).length()
		node.position.y = -4.0
		var t := create_tween()
		t.tween_interval(0.3 + d * 0.06 + randf() * 0.15)
		t.tween_property(node, "position:y", 0.0, 0.9).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func vert_pos(s: Rules, id: int) -> Vector3:
	var v := s.vert(id)
	return Vector3(v.x * S, GROUND - 0.02, v.y * S)


func tile_pos(s: Rules, id: int) -> Vector3:
	var t := s.tile(id)
	return Vector3(t.x * S, GROUND, t.y * S)


func _piece(kind: String, color: Color, length := 0.0) -> ArrayMesh:
	var key := "%s/%s/%.2f" % [kind, color.to_html(), length]
	if not _piece_cache.has(key):
		match kind:
			"hamlet": _piece_cache[key] = Art.hamlet(color)
			"town": _piece_cache[key] = Art.town(color)
			"road": _piece_cache[key] = Art.road(color, length)
	return _piece_cache[key]


## Add any pieces the rules have that the board doesn't show yet.
func sync(s: Rules, animate := true) -> void:
	for e in s.edges:
		if e.owner and not edges.has(e.id):
			var a := vert_pos(s, e.a)
			var b := vert_pos(s, e.b)
			var length := a.distance_to(b) * 0.64
			var node := MeshInstance3D.new()
			node.mesh = _piece("road", Color(s.player(e.owner).color), snappedf(length, 0.01))
			node.material_override = ground_mat
			node.position = (a + b) / 2.0
			node.rotation.y = -atan2(b.z - a.z, b.x - a.x)
			land.add_child(node)
			edges[e.id] = node
			if animate:
				_pop(node)
	for v in s.verts:
		if not v.owner:
			continue
		var have: Node3D = verts.get(v.id)
		if have and have.get_meta("kind") == v.kind:
			continue
		if have:
			have.queue_free()
		var node := MeshInstance3D.new()
		node.mesh = _piece(v.kind, Color(s.player(v.owner).color))
		node.material_override = ground_mat
		node.position = vert_pos(s, v.id)
		var rng := RandomNumberGenerator.new()
		rng.seed = v.id
		node.rotation.y = rng.randf_range(-0.35, 0.35)
		node.scale = Vector3.ONE * PIECE_SCALE
		node.set_meta("kind", v.kind)
		land.add_child(node)
		verts[v.id] = node
		if animate:
			_pop(node, true)
	if s.storm != storm_tile:
		_place_storm(s.storm, animate)


## A piece drops in and settles with a puff of dust.
func _pop(node: Node3D, drop := false) -> void:
	var target := node.position
	var full := node.scale
	node.scale = full * 0.2
	if drop:
		node.position.y += 1.6
	var tw := create_tween().set_parallel()
	tw.tween_property(node, "scale", full, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(node, "position:y", target.y, 0.4).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	_dust(target)


func _dust(at: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 18
	p.lifetime = 0.9
	p.explosiveness = 0.9
	p.direction = Vector3.UP
	p.spread = 80.0
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 1.4
	p.gravity = Vector3(0, -1.5, 0)
	p.scale_amount_min = 0.06
	p.scale_amount_max = 0.14
	var m := SphereMesh.new()
	m.radius = 0.5
	m.height = 1.0
	m.radial_segments = 6
	m.rings = 3
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("e9dcc0")
	mat.roughness = 1.0
	m.material = mat
	p.mesh = m
	p.position = at + Vector3(0, 0.15, 0)
	land.add_child(p)
	p.emitting = true
	get_tree().create_timer(1.5).timeout.connect(p.queue_free)


func _place_storm(tile_id: int, animate: bool) -> void:
	storm_tile = tile_id
	if not storm:
		storm = _make_storm()
		add_child(storm)
	var t: Node3D = tiles.get(tile_id)
	if not t:
		return
	var aabb: AABB = t.get_child(0).get_aabb()
	var target := Vector3(aabb.get_center().x, 3.4, aabb.get_center().z)
	if animate:
		var tw := create_tween()
		tw.tween_property(storm, "position", target + Vector3(0, 1.2, 0), 0.5).set_trans(Tween.TRANS_SINE)
		tw.tween_property(storm, "position", target, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		storm.position = target


func _make_storm() -> Node3D:
	var node := Node3D.new()
	var cloud := MeshInstance3D.new()
	cloud.mesh = Art.storm_cloud()
	cloud.material_override = ground_mat
	cloud.scale = Vector3.ONE * 1.5
	node.add_child(cloud)
	var rain := CPUParticles3D.new()
	rain.amount = 160
	rain.lifetime = 0.7
	rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	rain.emission_box_extents = Vector3(1.1, 0.1, 0.8)
	rain.direction = Vector3.DOWN
	rain.spread = 3.0
	rain.gravity = Vector3(0, -9, 0)
	rain.initial_velocity_min = 3.0
	rain.initial_velocity_max = 4.0
	var drop := BoxMesh.new()
	drop.size = Vector3(0.012, 0.22, 0.012)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.75, 0.85, 1.0, 0.55)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	drop.material = mat
	rain.mesh = drop
	rain.position = Vector3(0, -0.3, 0)
	node.add_child(rain)
	# Darken the field below: a light with negative energy.
	var gloom := OmniLight3D.new()
	gloom.light_energy = -2.2
	gloom.omni_range = 2.4
	gloom.position = Vector3(0, -2.4, 0)
	gloom.light_negative = true
	node.add_child(gloom)
	var flash := OmniLight3D.new()
	flash.name = "Flash"
	flash.light_color = Color("dfe8ff")
	flash.light_energy = 0.0
	flash.omni_range = 5.0
	flash.position = Vector3(0, -1.0, 0)
	node.add_child(flash)
	return node


## Fields that produced glow and their tokens hop.
func celebrate(tile_ids: Array) -> void:
	for id in tile_ids:
		var token: Node3D = tokens.get(id)
		if token:
			var base := token.position.y
			var tw := create_tween()
			tw.tween_property(token, "position:y", base + 0.5, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw.tween_property(token, "position:y", base, 0.5).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		var tile: Node3D = tiles.get(id)
		if tile:
			var aabb: AABB = tile.get_child(0).get_aabb()
			var glow := OmniLight3D.new()
			glow.light_color = Color("ffd77a")
			glow.light_energy = 0.0
			glow.omni_range = 3.2
			glow.position = Vector3(aabb.get_center().x, GROUND + 1.0, aabb.get_center().z)
			land.add_child(glow)
			var tw := create_tween()
			tw.tween_property(glow, "light_energy", 3.0, 0.25)
			tw.tween_property(glow, "light_energy", 0.0, 1.2)
			tw.tween_callback(glow.queue_free)


func lightning() -> void:
	if not storm:
		return
	var flash: OmniLight3D = storm.get_node("Flash")
	var tw := create_tween()
	for k in 2:
		tw.tween_property(flash, "light_energy", 8.0, 0.04)
		tw.tween_property(flash, "light_energy", 0.0, 0.12)


func _clear_markers() -> void:
	for m in markers.get_children():
		m.queue_free()


## Glowing hints for where the player on turn may build: corners, sides or
## fields (for the storm).
func show_targets(s: Rules, kind: String, ids: Array) -> void:
	_clear_markers()
	for id in ids:
		var m := MeshInstance3D.new()
		m.material_override = marker_mat
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		match kind:
			"hamlet", "town":
				var ring := TorusMesh.new()
				ring.inner_radius = 0.14
				ring.outer_radius = 0.22
				ring.rings = 16
				ring.ring_segments = 6
				m.mesh = ring
				m.position = vert_pos(s, id) + Vector3(0, 0.1, 0)
				if kind == "town":
					m.position.y += 0.75
			"road":
				var e := s.edge(id)
				var a := vert_pos(s, e.a)
				var b := vert_pos(s, e.b)
				var bar := BoxMesh.new()
				bar.size = Vector3(a.distance_to(b) * 0.5, 0.05, 0.1)
				m.mesh = bar
				m.position = (a + b) / 2.0 + Vector3(0, 0.1, 0)
				m.rotation.y = -atan2(b.z - a.z, b.x - a.x)
			"storm":
				var ring := TorusMesh.new()
				ring.inner_radius = 1.25
				ring.outer_radius = 1.35
				ring.rings = 6
				ring.ring_segments = 4
				m.mesh = ring
				m.position = tile_pos(s, id) + Vector3(0, 0.15, 0)
		markers.add_child(m)


func hide_targets() -> void:
	_clear_markers()


func _process(delta: float) -> void:
	sway += delta
	for n in spinners:
		if is_instance_valid(n):
			n.rotation += n.get_meta("spin") * delta
	for c in clouds:
		c.position.x += delta * 0.6
		if c.position.x > 40:
			c.position.x = -40
	if markers.get_child_count():
		var k := 0.6 + 0.4 * sin(sway * 5.0)
		marker_mat.albedo_color.a = k
	if storm:
		storm.rotation.y += delta * 0.2
		if randf() < delta * 0.25:
			lightning()
	_place_camera()


func _place_camera() -> void:
	var yaw := deg_to_rad(still if still >= 0.0 else sin(sway * 0.08) * 6.0)
	var pitch := deg_to_rad(52.0)
	var dist := radius / tan(deg_to_rad(camera.fov / 2.0)) * 0.86
	var dir := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	# Aim a little below the middle: the cards row covers the bottom of the TV.
	var look := centre + Vector3(0, 0, radius * 0.24)
	camera.position = look + dir * dist
	camera.look_at(look, Vector3.UP)
	dof.dof_blur_far_distance = dist + radius * 0.55
	dof.dof_blur_far_transition = radius * 0.8
