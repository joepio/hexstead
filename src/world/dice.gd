class_name Dice
extends Control
## Two dice thrown across the middle of the TV, then the total, big.
##
## The throw is simulated by hand rather than by the physics engine: the whole
## tumble is worked out the moment the dice are rolled, so we know which face
## each die will land on before anyone sees it. The pips are then turned so
## that face shows the number the rules rolled. To the table it is a real,
## bouncing throw that happens to land on the right number.

signal shown(total: int)
signal done

const FACE_AXES := [Vector3.UP, Vector3.DOWN, Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD]
## Pips on each axis above: opposite faces add up to seven.
const FACE_VALUES := [1, 6, 2, 5, 3, 4]
const STEP := 1.0 / 120.0
const GRAVITY := 34.0
const HALF := 0.5
## The tray the dice bounce around in, in die widths.
const TRAY := Vector2(3.4, 1.9)

var viewport: SubViewport
var camera: Camera3D
var dice: Array = []        # [{body: Node3D, pips: Node3D}]
var tracks: Array = []      # per die: Array of Transform3D, one per STEP
var clock := -1.0
var total := 0
var label: Label
var _shown := false
var _hold := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	modulate.a = 0.0
	visible = false
	var holder := SubViewportContainer.new()
	holder.stretch = true
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(holder)
	viewport = SubViewport.new()
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	holder.add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)

	camera = Camera3D.new()
	camera.fov = 34.0
	camera.position = Vector3(0, 9.0, 5.4)
	world.add_child(camera)
	camera.look_at(Vector3(0, 0, -1.0), Vector3.UP)

	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 0.96, 0.9)
	env.ambient_light_energy = 0.55
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-62, -35, 0)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.shadow_blur = 2.0
	world.add_child(sun)

	# An invisible table that still catches the dice's shadows.
	var table := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(20, 14)
	table.mesh = plane
	var shadow_mat := StandardMaterial3D.new()
	shadow_mat.shadow_to_opacity = true
	shadow_mat.albedo_color = Color(0.05, 0.08, 0.1, 0.75)
	shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	plane.material = shadow_mat
	table.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(table)

	for k in 2:
		var body := Node3D.new()
		var pips := Node3D.new()
		body.add_child(pips)
		var cube := MeshInstance3D.new()
		cube.mesh = _die_mesh()
		cube.material_override = _ivory()
		pips.add_child(cube)
		_add_pips(pips)
		world.add_child(body)
		dice.append({body = body, pips = pips})

	label = Label.new()
	label.add_theme_font_size_override("font_size", 300)
	label.add_theme_color_override("font_color", Color("fbf6ea"))
	label.add_theme_color_override("font_outline_color", Color("3a2a1c"))
	label.add_theme_constant_override("outline_size", 34)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
	label.add_theme_constant_override("shadow_offset_y", 10)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# Above the dice, so both stay readable.
	label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	label.offset_top = -40
	label.offset_bottom = 300
	label.modulate.a = 0.0
	add_child(label)


func _ivory() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.35
	m.specular = 0.6
	return m


## A cube with its edges and corners cut off, so it catches the light like a
## real die.
func _die_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c := 0.11
	var e := HALF - c
	var col := Color("fbf3df")
	var face := func(n: Vector3) -> Array:
		var u := Vector3(n.y, n.z, n.x)
		var v := n.cross(u)
		return [n * HALF + (u + v) * e, n * HALF + (u - v) * e, n * HALF + (-u - v) * e, n * HALF + (-u + v) * e]
	var tri := func(a: Vector3, b: Vector3, d: Vector3) -> void:
		var n := (b - a).cross(d - a)
		if n.dot(a + b + d) < 0.0:
			var t := b
			b = d
			d = t
			n = -n
		n = n.normalized()
		for p in [a, d, b]:
			st.set_color(col)
			st.set_normal(n)
			st.add_vertex(p)
	# Faces.
	for n in FACE_AXES:
		var q: Array = face.call(n)
		tri.call(q[0], q[1], q[2])
		tri.call(q[0], q[2], q[3])
	# Edges and corners: every point of the chamfered cube is a face corner,
	# so each edge strip joins the two nearest corners of two faces.
	var corners := {}
	for n in FACE_AXES:
		for p in face.call(n):
			corners[_key(p)] = p
	var pts: Array = corners.values()
	for i in pts.size():
		for j in range(i + 1, pts.size()):
			for k in range(j + 1, pts.size()):
				var a: Vector3 = pts[i]
				var b: Vector3 = pts[j]
				var d: Vector3 = pts[k]
				# Corner triangles: three points one chamfer apart, on three faces.
				if _same_corner(a, b, d):
					tri.call(a, b, d)
	for n1 in FACE_AXES:
		for n2 in FACE_AXES:
			if n1.dot(n2) != 0.0 or _key(n1) > _key(n2):
				continue
			var q1: Array = []
			var q2: Array = []
			for p in face.call(n1):
				if p.dot(n2) > 0.0:
					q1.append(p)
			for p in face.call(n2):
				if p.dot(n1) > 0.0:
					q2.append(p)
			# Pair each point on face 1 with its neighbour on face 2.
			var a: Vector3 = q1[0]
			var b: Vector3 = q1[1]
			var a2: Vector3 = q2[0] if q2[0].distance_to(a) < q2[1].distance_to(a) else q2[1]
			var b2: Vector3 = q2[1] if a2 == q2[0] else q2[0]
			tri.call(a, b, b2)
			tri.call(a, b2, a2)
	return st.commit()


func _key(p: Vector3) -> String:
	return "%.3f,%.3f,%.3f" % [p.x, p.y, p.z]


func _same_corner(a: Vector3, b: Vector3, d: Vector3) -> bool:
	var s := Vector3(signf(a.x), signf(a.y), signf(a.z))
	for p in [b, d]:
		if Vector3(signf(p.x), signf(p.y), signf(p.z)) != s:
			return false
	return a.distance_to(b) < 0.2 and a.distance_to(d) < 0.2 and b.distance_to(d) < 0.2


func _add_pips(parent: Node3D) -> void:
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color("2b2018")
	dark.roughness = 0.6
	var red := StandardMaterial3D.new()
	red.albedo_color = Color("b3261b")
	red.roughness = 0.5
	var layout := {
		1: [Vector2.ZERO],
		2: [Vector2(-1, -1), Vector2(1, 1)],
		3: [Vector2(-1, -1), Vector2.ZERO, Vector2(1, 1)],
		4: [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)],
		5: [Vector2(-1, -1), Vector2(1, -1), Vector2.ZERO, Vector2(-1, 1), Vector2(1, 1)],
		6: [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 0), Vector2(1, 0), Vector2(-1, 1), Vector2(1, 1)],
	}
	for f in 6:
		var n: Vector3 = FACE_AXES[f]
		var value: int = FACE_VALUES[f]
		var u := Vector3(n.y, n.z, n.x)
		var v := n.cross(u)
		for p in layout[value]:
			var pip := MeshInstance3D.new()
			var disc := CylinderMesh.new()
			var r := 0.13 if value == 1 else 0.085
			disc.top_radius = r
			disc.bottom_radius = r
			disc.height = 0.04
			disc.radial_segments = 16
			disc.rings = 1
			pip.mesh = disc
			pip.material_override = red if value == 1 else dark
			pip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var pos: Vector3 = n * (HALF - 0.012) + (u * p.x + v * p.y) * 0.24
			# Cylinders stand on Y; turn this one to stand on the face normal.
			var basis := Basis(Quaternion(Vector3.UP, n)) if n != Vector3.DOWN else Basis(Vector3.RIGHT, PI)
			pip.transform = Transform3D(basis, pos)
			parent.add_child(pip)


# --- Throwing --------------------------------------------------------------

## Throw two dice that will show `values`. `shown` fires as they settle and
## the total appears, `done` when it has faded again.
func roll(values: Array, rng_seed: int = 0) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed if rng_seed != 0 else randi()
	total = int(values[0]) + int(values[1])
	tracks.clear()
	for k in 2:
		var track := _simulate(k, rng)
		tracks.append(track)
		var last: Transform3D = track[track.size() - 1]
		_turn_pips(dice[k].pips, last.basis, int(values[k]), rng)
	clock = 0.0
	_shown = false
	_hold = 0.0
	label.text = str(total)
	label.modulate.a = 0.0
	label.scale = Vector2.ONE
	modulate.a = 1.0
	visible = true
	_apply(0.0)


func busy() -> bool:
	return clock >= 0.0


func length() -> float:
	var n := 0
	for t in tracks:
		n = maxi(n, t.size())
	return n * STEP


func _process(delta: float) -> void:
	if clock < 0.0:
		return
	clock += delta
	var land := length()
	_apply(minf(clock, land))
	label.pivot_offset = label.size / 2.0
	if clock >= land and not _shown:
		_shown = true
		shown.emit(total)
	if _shown:
		var t := clock - land
		# The total pops in over the dice, stays, then everything fades.
		label.modulate.a = clampf(t / 0.12, 0.0, 1.0) * clampf((1.9 - t) / 0.35, 0.0, 1.0)
		var pop := 1.0 + 0.35 * maxf(0.0, 1.0 - t / 0.25)
		label.scale = Vector2.ONE * pop
		modulate.a = clampf((2.0 - t) / 0.35, 0.0, 1.0)
		if t >= 2.0:
			clock = -1.0
			visible = false
			done.emit()


## Put the dice where their tracks say they are at time `t`.
func _apply(t: float) -> void:
	for k in tracks.size():
		var track: Array = tracks[k]
		var f := t / STEP
		var i := clampi(int(f), 0, track.size() - 1)
		var j := mini(i + 1, track.size() - 1)
		var a: Transform3D = track[i]
		var b: Transform3D = track[j]
		dice[k].body.transform = a.interpolate_with(b, f - floorf(f))


## Turn the pips inside a die so that the face resting on top is `value`.
func _turn_pips(pips: Node3D, rest: Basis, value: int, rng: RandomNumberGenerator) -> void:
	# Which of the die's own sides ends up facing the sky.
	var up_axis := Vector3.UP
	var best := -2.0
	for axis in FACE_AXES:
		var d: float = (rest * axis).dot(Vector3.UP)
		if d > best:
			best = d
			up_axis = axis
	var want: Vector3 = FACE_AXES[FACE_VALUES.find(value)]
	# Any of the cube's 24 turns that carries `want` onto `up_axis`.
	var options: Array = []
	for b in _cube_turns():
		if (b * want).is_equal_approx(up_axis):
			options.append(b)
	pips.basis = options[rng.randi_range(0, options.size() - 1)]


static func _cube_turns() -> Array:
	var axes := [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD]
	var out: Array = []
	for x in axes:
		for y in axes:
			if absf(x.dot(y)) > 0.5:
				continue
			out.append(Basis(x, y, x.cross(y)))
	return out


## One die's whole throw, as a transform per step: thrown in from the side,
## bouncing off the table and the tray's invisible walls until it rests.
func _simulate(k: int, rng: RandomNumberGenerator) -> Array:
	var side := -1.0 if k == 0 else 1.0
	var pos := Vector3(side * (TRAY.x + 1.0), 2.2 + rng.randf() * 0.6, rng.randf_range(-0.6, 0.6) + (0.45 if k == 0 else -0.45))
	var vel := Vector3(-side * rng.randf_range(7.0, 9.0), rng.randf_range(1.0, 3.0), rng.randf_range(-1.5, 1.5))
	var rot := Basis(Quaternion.from_euler(Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)))
	var spin := Vector3(rng.randf_range(-18, 18), rng.randf_range(-10, 10), rng.randf_range(-18, 18))
	var inv_mass := 1.0
	var inv_inertia := 6.0  # a solid unit cube: I = m * s^2 / 6
	var track: Array = []
	var still := 0
	var corners: Array = []
	for x in [-HALF, HALF]:
		for y in [-HALF, HALF]:
			for z in [-HALF, HALF]:
				corners.append(Vector3(x, y, z))
	# Floor, then walls (only once the die is inside the tray).
	var planes := [[Vector3.UP, 0.0], [Vector3.LEFT, -TRAY.x], [Vector3.RIGHT, -TRAY.x], [Vector3.FORWARD, -TRAY.y], [Vector3.BACK, -TRAY.y]]
	for step in 900:
		vel.y -= GRAVITY * STEP
		pos += vel * STEP
		if spin.length() > 0.0:
			rot = Basis(spin.normalized(), spin.length() * STEP) * rot
			rot = rot.orthonormalized()
		var touching := false
		for plane in planes:
			var n: Vector3 = plane[0]
			var dist: float = plane[1]
			if n != Vector3.UP and absf(pos.x) > TRAY.x + 0.2 and n.x != 0.0:
				continue  # still flying in from outside
			var deepest := 0.0
			for c in corners:
				var r: Vector3 = rot * c
				var depth: float = dist - (pos + r).dot(n)
				if depth <= 0.0:
					continue
				deepest = maxf(deepest, depth)
				if n == Vector3.UP:
					touching = true
				var vp: Vector3 = vel + spin.cross(r)
				var vn := vp.dot(n)
				if vn >= 0.0:
					continue
				var rn := r.cross(n)
				var bounce := 0.35 if n == Vector3.UP else 0.5
				var j := -(1.0 + bounce) * vn / (inv_mass + inv_inertia * rn.length_squared())
				vel += n * j * inv_mass
				spin += rn * j * inv_inertia
				# Friction along the surface.
				vp = vel + spin.cross(r)
				var vt := vp - n * vp.dot(n)
				if vt.length() > 0.0001:
					var t := vt.normalized()
					var rt := r.cross(t)
					var jt := clampf(-vt.length() / (inv_mass + inv_inertia * rt.length_squared()), -0.5 * j, 0.5 * j)
					vel += t * jt * inv_mass
					spin += rt * jt * inv_inertia
			if deepest > 0.0:
				pos += n * deepest
		if touching:
			vel *= 0.992
			spin *= 0.985
		track.append(Transform3D(rot, pos))
		if touching and vel.length() < 0.15 and spin.length() < 0.4:
			still += 1
			if still > 20:
				break
		else:
			still = 0
	# Let it settle flat on its nearest face, so it never rests on an edge.
	var rest := track[track.size() - 1] as Transform3D
	var flat := _flatten(rest.basis)
	var settled := Transform3D(flat, Vector3(rest.origin.x, HALF, rest.origin.z))
	for i in 18:
		track.append(rest.interpolate_with(settled, (i + 1) / 18.0))
	return track


## The nearest orientation that has one face exactly up.
static func _flatten(b: Basis) -> Basis:
	var up_axis := Vector3.UP
	var best := -2.0
	for axis in FACE_AXES:
		var d: float = (b * axis).dot(Vector3.UP)
		if d > best:
			best = d
			up_axis = axis
	var now := (b * up_axis).normalized()
	return Basis(Quaternion(now, Vector3.UP)) * b
