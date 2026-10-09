class_name MeshKit
extends RefCounted
## Builds flat-shaded, vertex-coloured low-poly meshes out of simple parts.
## Everything on the island (fields, trees, sheep, houses) is drawn by this,
## so a whole tile becomes one mesh and one draw call.

var st := SurfaceTool.new()
## Applied to every point added; set it, add a part, reset it.
var xform := Transform3D.IDENTITY
var rng := RandomNumberGenerator.new()
## How much each face's colour wanders, for a painted look.
var jitter := 0.05
var count := 0


func _init(seed_value: int = 1) -> void:
	rng.seed = seed_value
	st.begin(Mesh.PRIMITIVE_TRIANGLES)


func commit() -> ArrayMesh:
	if count == 0:
		return null
	return st.commit()


func _shade(color: Color) -> Color:
	if jitter <= 0.0:
		return color
	var k := 1.0 + rng.randf_range(-jitter, jitter)
	return Color(color.r * k, color.g * k, color.b * k, color.a)


## One face. Points go counter-clockwise seen from the side it faces.
func tri(a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	a = xform * a
	b = xform * b
	c = xform * c
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-12:
		return
	n = n.normalized()
	color = _shade(color)
	st.set_color(color)
	st.set_normal(n)
	st.add_vertex(a)
	st.set_color(color)
	st.set_normal(n)
	st.add_vertex(c)
	st.set_color(color)
	st.set_normal(n)
	st.add_vertex(b)
	count += 1


func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
	tri(a, b, c, color)
	tri(a, c, d, color)


## A polygon floor plan (in `ngon` order) pulled up from y0 to y1.
func extrude(ring: Array, y0: float, y1: float, top: Color, side: Color, bottom := false) -> void:
	var n := ring.size()
	var centre := Vector3.ZERO
	for p in ring:
		centre += Vector3(p.x, 0, p.y)
	centre /= n
	for i in n:
		var p: Vector2 = ring[i]
		var q: Vector2 = ring[(i + 1) % n]
		tri(Vector3(centre.x, y1, centre.z), Vector3(p.x, y1, p.y), Vector3(q.x, y1, q.y), top)
		quad(Vector3(p.x, y0, p.y), Vector3(q.x, y0, q.y), Vector3(q.x, y1, q.y), Vector3(p.x, y1, p.y), side)
		if bottom:
			tri(Vector3(centre.x, y0, centre.z), Vector3(q.x, y0, q.y), Vector3(p.x, y0, p.y), side)


static func ngon(sides: int, radius: float, offset := 0.0, centre := Vector2.ZERO) -> Array:
	var out: Array = []
	for i in sides:
		var a := TAU * i / sides + offset
		out.append(centre + Vector2(cos(a), -sin(a)) * radius)
	return out


func box(centre: Vector3, size: Vector3, color: Color, top := Color(0, 0, 0, 0)) -> void:
	var h := size / 2.0
	var ring := [Vector2(-h.x, h.z), Vector2(h.x, h.z), Vector2(h.x, -h.z), Vector2(-h.x, -h.z)]
	for i in ring.size():
		ring[i] += Vector2(centre.x, centre.z)
	extrude(ring, centre.y - h.y, centre.y + h.y, top if top.a > 0 else color, color, true)


## A cylinder or cone frustum standing on `base`.
func frustum(base: Vector3, r0: float, r1: float, height: float, sides: int, color: Color, top := Color(0, 0, 0, 0), spin := 0.0) -> void:
	var cap := top if top.a > 0 else color
	var a := ngon(sides, 1.0, spin)
	var tip := base + Vector3(0, height, 0)
	for i in sides:
		var p: Vector2 = a[i]
		var q: Vector2 = a[(i + 1) % sides]
		var p0 := base + Vector3(p.x * r0, 0, p.y * r0)
		var q0 := base + Vector3(q.x * r0, 0, q.y * r0)
		var p1 := tip + Vector3(p.x * r1, 0, p.y * r1)
		var q1 := tip + Vector3(q.x * r1, 0, q.y * r1)
		if r1 > 0.0001:
			quad(p0, q0, q1, p1, color)
			tri(tip, p1, q1, cap)
		else:
			tri(p0, q0, tip, color)
		tri(base, q0, p0, color)


func cone(base: Vector3, radius: float, height: float, sides: int, color: Color, spin := 0.0) -> void:
	frustum(base, radius, 0.0, height, sides, color, Color(0, 0, 0, 0), spin)


## A lumpy low-poly ball: crowns of trees, bushes, boulders, sheep.
func blob(centre: Vector3, radii: Vector3, color: Color, lumpy := 0.18, rings := 4, sides := 6, flat_bottom := false) -> void:
	var grid: Array = []
	for r in rings + 1:
		var row: Array = []
		var phi := PI * r / rings
		for s in sides:
			var theta := TAU * s / sides + (0.5 if r % 2 == 1 else 0.0) * TAU / sides
			var k := 1.0 if r == 0 or r == rings else 1.0 + rng.randf_range(-lumpy, lumpy)
			var y := cos(phi)
			if flat_bottom and y < -0.2:
				y = -0.2
			var p := Vector3(sin(phi) * cos(theta) * k, y, sin(phi) * sin(theta) * k)
			row.append(centre + p * radii)
		grid.append(row)
	for r in rings:
		for s in sides:
			var a: Vector3 = grid[r][s]
			var b: Vector3 = grid[r][(s + 1) % sides]
			var c: Vector3 = grid[r + 1][(s + 1) % sides]
			var d: Vector3 = grid[r + 1][s]
			if r == 0:
				tri(a, c, d, color)
			elif r == rings - 1:
				tri(a, b, d, color)
			else:
				quad(a, b, c, d, color)


## A boulder: a squat blob, a bit sunk into the ground.
func rock(base: Vector3, size: float, color: Color) -> void:
	var r := Vector3(size * rng.randf_range(0.9, 1.3), size * rng.randf_range(0.55, 0.85), size * rng.randf_range(0.8, 1.1))
	var save := xform
	xform = xform * Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3.ZERO)
	blob(base + Vector3(0, r.y * 0.45, 0), r, color, 0.28, 3, 5, true)
	xform = save


## A gable roof over a w x d floor, ridge along x.
func roof(centre: Vector3, w: float, d: float, h: float, color: Color, end_color: Color, over := 0.06) -> void:
	var x := w / 2.0 + over
	var z := d / 2.0 + over
	var y := centre.y
	var a := Vector3(-x, y, z) + Vector3(centre.x, 0, centre.z)
	var b := Vector3(x, y, z) + Vector3(centre.x, 0, centre.z)
	var c := Vector3(x, y, -z) + Vector3(centre.x, 0, centre.z)
	var d2 := Vector3(-x, y, -z) + Vector3(centre.x, 0, centre.z)
	var r0 := Vector3(centre.x - x, y + h, centre.z)
	var r1 := Vector3(centre.x + x, y + h, centre.z)
	quad(a, b, r1, r0, color)
	quad(c, d2, r0, r1, color)
	var e0 := Vector3(centre.x - w / 2.0, y, centre.z + d / 2.0)
	var e1 := Vector3(centre.x - w / 2.0, y, centre.z - d / 2.0)
	var e2 := Vector3(centre.x - w / 2.0, y + h * (d / 2.0) / z, centre.z)
	tri(e1, e0, e2, end_color)
	var f0 := Vector3(centre.x + w / 2.0, y, centre.z + d / 2.0)
	var f1 := Vector3(centre.x + w / 2.0, y, centre.z - d / 2.0)
	var f2 := Vector3(centre.x + w / 2.0, y + h * (d / 2.0) / z, centre.z)
	tri(f0, f1, f2, end_color)
	# Undersides, so the eaves don't show through from below.
	quad(r0, r1, b, a, color.darkened(0.4))
	quad(r1, r0, d2, c, color.darkened(0.4))


func at(origin: Vector3, yaw := 0.0, s := 1.0) -> void:
	xform = Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s), origin)


func reset() -> void:
	xform = Transform3D.IDENTITY
