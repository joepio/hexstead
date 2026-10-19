class_name Art
extends RefCounted
## The island's look: palette, field tiles, the beach and every prop on them.
## All of it is built from code with MeshKit, so a new island every round
## costs nothing to ship.

## World units per board unit (a field's corner radius).
const S := 2.0
## Height of every field's surface. Corners and roads sit here.
const GROUND := 0.5
## Fields stop this far below their corners so seams show between them.
const BEVEL := 0.035
const CLIFF_BOTTOM := -1.6

const C := {
	grass = Color("7fb346"), grass_light = Color("9ccb55"), grass_dark = Color("5f9338"),
	forest_floor = Color("527f34"), moss = Color("6a9a3c"),
	pine = Color("2f5f31"), pine_light = Color("3f7a3a"), pine_dark = Color("234a28"),
	leaf = Color("4f8a3a"), leaf_light = Color("74a845"), trunk = Color("6b4a2f"),
	grain = Color("e2b04a"), grain_light = Color("f0c95c"), grain_dark = Color("c9933a"), hay = Color("e6c46a"),
	clay = Color("c97b4c"), clay_light = Color("d99561"), clay_dark = Color("9c5233"), brick = Color("b4553a"),
	meadow = Color("a2cf5c"), meadow_dark = Color("86bb4c"), wool = Color("f6f1e7"), sheep_face = Color("3b302b"),
	rock = Color("8f8ba3"), rock_light = Color("aba7bd"), rock_dark = Color("6d6982"), snow = Color("f4f2fa"),
	sand = Color("e7d29b"), sand_wet = Color("c9b37c"), sand_deep = Color("b9a774"),
	earth = Color("7a5a3c"), earth_dark = Color("5e4530"), stone = Color("8a8276"), stone_dark = Color("6c665d"),
	wood = Color("8c6844"), wood_dark = Color("5e4430"), plaster = Color("f1e4c6"), plaster_shade = Color("dccca6"),
	flower_white = Color("fbf7ee"), flower_yellow = Color("f6d34f"), flower_pink = Color("ef8fb0"), flower_blue = Color("8fb4ef"),
	reed = Color("6f8f3a"), lily = Color("4f9a45"), mushroom = Color("d8483a"),
}

## Board point (x, y) to world position on the ground.
static func world(x: float, y: float, h := GROUND) -> Vector3:
	return Vector3(x * S, h, y * S)


## Corners of a pointy-top hex around `centre`, in MeshKit's ring order.
static func hex_ring(centre: Vector2, radius: float) -> Array:
	return MeshKit.ngon(6, radius, deg_to_rad(30.0), centre)


## Signed distance from `p` to a pointy-top hex of corner radius `r` at origin.
static func hex_sdf(p: Vector2, r: float) -> float:
	var q := Vector2(absf(p.x), absf(p.y))
	var inner := r * sqrt(3.0) / 2.0
	# Edge normals of a pointy-top hex: (1, 0) and (1/2, sqrt(3)/2).
	return maxf(q.x, q.x * 0.5 + q.y * sqrt(3.0) / 2.0) - inner


static var noise: FastNoiseLite = _make_noise()


static func _make_noise() -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 0.35
	n.fractal_octaves = 2
	return n


## Calls `point.call(p: Vector2 world xz) -> float height` and
## `paint.call(p, h, normal) -> Color` over a finely cut hex, so fields get
## gentle bumps and painted patches.
static func hex_surface(kit: MeshKit, centre: Vector2, radius: float, rows: int, point: Callable, paint: Callable) -> void:
	var corners := hex_ring(centre, radius)
	for k in 6:
		var a: Vector2 = corners[k]
		var b: Vector2 = corners[(k + 1) % 6]
		var grid := {}
		for i in rows + 1:
			for j in i + 1:
				var p := centre + (a - centre) * (float(i) / rows) + (b - a) * (float(j) / rows)
				grid[Vector2i(i, j)] = Vector3(p.x, point.call(p), p.y)
		for i in rows:
			for j in i + 1:
				_up(kit, grid[Vector2i(i, j)], grid[Vector2i(i + 1, j)], grid[Vector2i(i + 1, j + 1)], paint)
				if j < i:
					_up(kit, grid[Vector2i(i, j)], grid[Vector2i(i + 1, j + 1)], grid[Vector2i(i, j + 1)], paint)


static func _up(kit: MeshKit, a: Vector3, b: Vector3, c: Vector3, paint: Callable) -> void:
	var n := (b - a).cross(c - a)
	if n.y < 0:
		var t := b
		b = c
		c = t
		n = -n
	var mid := (a + b + c) / 3.0
	kit.tri(a, b, c, paint.call(Vector2(mid.x, mid.z), mid.y, n.normalized()))


# --- Fields -----------------------------------------------------------------

## Builds one field: its painted top, bevel and earthen sides, and what grows
## on it. Returns {mesh, extras: [Node3D]} where extras animate.
static func field(res: String, centre_board: Vector2, seed_value: int, bottom := CLIFF_BOTTOM) -> Dictionary:
	var kit := MeshKit.new(seed_value)
	var c := centre_board * S
	var r := S
	var top_r := r * 0.985
	var base := _base_color(res)
	var ground := func(p: Vector2) -> float:
		var d := (p - c).length() / top_r
		var bump := noise.get_noise_2d(p.x * 3.0 + seed_value, p.y * 3.0) * 0.06
		if res == "":
			# The lake: a bowl.
			return GROUND - 0.25 * clampf(1.0 - d * 1.15, 0.0, 1.0) * 1.6 + bump * 0.3
		var edge := clampf((1.0 - d) * 4.0, 0.0, 1.0)
		return GROUND + bump * edge
	var paint := func(p: Vector2, h: float, n: Vector3) -> Color:
		var v := noise.get_noise_2d(p.x * 1.7 - seed_value * 3.1, p.y * 1.7)
		var col: Color = base[0].lerp(base[1], clampf(v * 1.6 + 0.5, 0.0, 1.0))
		if v < -0.35:
			col = col.lerp(base[2], 0.6)
		if res == "" and h < GROUND - 0.12:
			col = C.sand_wet
		return col
	hex_surface(kit, c, top_r, 6, ground, paint)
	# Bevel down to the field's true edge, then the earthen sides the cards show.
	var outer := hex_ring(c, r)
	var inner := hex_ring(c, top_r)
	# The rim is the field's own colour, a shade darker: a thin seam between
	# fields rather than a groove that reads as a ridge.
	var edge_col: Color = base[0].darkened(0.12)
	for k in 6:
		var a0: Vector2 = inner[k]
		var b0: Vector2 = inner[(k + 1) % 6]
		var a1: Vector2 = outer[k]
		var b1: Vector2 = outer[(k + 1) % 6]
		kit.quad(Vector3(a1.x, GROUND - BEVEL, a1.y), Vector3(b1.x, GROUND - BEVEL, b1.y),
			Vector3(b0.x, ground.call(b0), b0.y), Vector3(a0.x, ground.call(a0), a0.y), edge_col)
		var y1 := GROUND - BEVEL
		var y2 := GROUND - 0.42
		kit.quad(Vector3(a1.x, y2, a1.y), Vector3(b1.x, y2, b1.y), Vector3(b1.x, y1, b1.y), Vector3(a1.x, y1, a1.y), C.earth)
		kit.quad(Vector3(a1.x, bottom, a1.y), Vector3(b1.x, bottom, b1.y), Vector3(b1.x, y2, b1.y), Vector3(a1.x, y2, a1.y), C.stone)
	var extras: Array = []
	var place := Placer.new(c, seed_value)
	match res:
		"timber":
			_forest(kit, place)
		"grain":
			extras.append_array(_farm(kit, place))
		"clay":
			_clay_pit(kit, place)
		"wool":
			_pasture(kit, place)
		"ore":
			_mountain(kit, place)
		"":
			extras.append_array(_lake(kit, place))
	if res != "" and res != "ore":
		_flowers(kit, place, 10 if res != "timber" else 4)
	return {mesh = kit.commit(), extras = extras}


static func _base_color(res: String) -> Array:
	match res:
		"timber": return [C.forest_floor, C.moss, C.grass_dark]
		"grain": return [C.grain, C.grain_light, C.grain_dark]
		"clay": return [C.clay, C.clay_light, C.clay_dark]
		"wool": return [C.meadow, C.grass_light, C.meadow_dark]
		"ore": return [C.grass_dark, C.grass, C.rock_dark]
	return [C.grass, C.grass_light, C.grass_dark]


## Picks free spots on a field: away from its number token, its corners
## (where hamlets go) and its sides (where roads go), and from each other.
class Placer:
	var centre: Vector2
	var rng := RandomNumberGenerator.new()
	var taken: Array = []
	var corners: Array

	func _init(c: Vector2, seed_value: int) -> void:
		centre = c
		rng.seed = seed_value * 7919 + 13
		corners = Art.hex_ring(c, Art.S)

	## Where the number token sits.
	func token() -> Vector2:
		return centre + Vector2(0, Art.S * 0.42)

	func ok(p: Vector2, spacing: float, edge := 0.32, token_gap := 0.72) -> bool:
		if Art.hex_sdf(p - centre, Art.S) > -edge:
			return false
		for k in corners:
			if p.distance_to(k) < 0.62:
				return false
		if p.distance_to(token()) < token_gap:
			return false
		for t in taken:
			if p.distance_to(t[0]) < spacing + t[1]:
				return false
		return true

	## A free spot, or Vector2.INF after `tries` misses.
	func spot(spacing: float, tries := 40, edge := 0.32, token_gap := 0.72) -> Vector2:
		for _i in tries:
			var a := rng.randf() * TAU
			var d := sqrt(rng.randf()) * Art.S * 0.9
			var p := centre + Vector2(cos(a), sin(a)) * d
			if ok(p, spacing, edge, token_gap):
				taken.append([p, spacing])
				return p
		return Vector2.INF

	func h(p: Vector2) -> float:
		return Art.GROUND + Art.noise.get_noise_2d(p.x * 3.0, p.y * 3.0) * 0.02


static func _flowers(kit: MeshKit, place: Placer, n: int) -> void:
	var colors := [C.flower_white, C.flower_yellow, C.flower_pink, C.flower_white, C.flower_blue]
	for i in n:
		var p := place.spot(0.05, 12, 0.2, 0.5)
		if p == Vector2.INF:
			continue
		var col: Color = colors[place.rng.randi() % colors.size()]
		for k in 3:
			var o := Vector2(place.rng.randf_range(-0.12, 0.12), place.rng.randf_range(-0.12, 0.12))
			kit.blob(Vector3(p.x + o.x, GROUND + 0.04, p.y + o.y), Vector3(0.035, 0.03, 0.035), col, 0.1, 2, 4)
	# Grass tufts all over, which make fields read as fields up close.
	for i in n * 2:
		var p := place.spot(0.02, 8, 0.15, 0.48)
		if p == Vector2.INF:
			continue
		place.taken.pop_back()
		kit.cone(Vector3(p.x, GROUND - 0.01, p.y), 0.06, place.rng.randf_range(0.1, 0.18), 3, C.grass_dark, place.rng.randf() * TAU)


static func pine(kit: MeshKit, base: Vector3, size: float, rng: RandomNumberGenerator) -> void:
	kit.frustum(base, 0.07 * size, 0.05 * size, 0.3 * size, 5, C.trunk)
	var greens := [C.pine, C.pine_light, C.pine_dark]
	var y := base.y + 0.2 * size
	var w := 0.42 * size
	var spin := rng.randf() * TAU
	for layer in 3:
		var tone: Color = greens[(layer + rng.randi()) % 3]
		kit.cone(Vector3(base.x, y, base.z), w, 0.62 * size, 7, tone, spin + layer)
		y += 0.36 * size
		w *= 0.74


static func round_tree(kit: MeshKit, base: Vector3, size: float, rng: RandomNumberGenerator) -> void:
	kit.frustum(base, 0.07 * size, 0.05 * size, 0.42 * size, 5, C.trunk)
	var tone: Color = C.leaf.lerp(C.leaf_light, rng.randf())
	kit.blob(base + Vector3(0, 0.62 * size, 0), Vector3(0.36, 0.32, 0.36) * size, tone, 0.2, 4, 7)
	kit.blob(base + Vector3(0.14 * size, 0.82 * size, 0.05 * size), Vector3(0.22, 0.2, 0.22) * size, tone.lightened(0.08), 0.2, 3, 6)


static func bush(kit: MeshKit, base: Vector3, size: float, rng: RandomNumberGenerator) -> void:
	var tone: Color = C.leaf.lerp(C.grass_dark, rng.randf())
	kit.blob(base + Vector3(0, 0.08 * size, 0), Vector3(0.2, 0.15, 0.2) * size, tone, 0.25, 3, 6, true)


static func _forest(kit: MeshKit, place: Placer) -> void:
	var tok := place.token()
	for i in 30:
		var p := place.spot(0.24, 30, 0.28, 0.75)
		if p == Vector2.INF:
			break
		# Keep the view to the token and the corners clear.
		if (p.y > tok.y - 0.25 and absf(p.x - tok.x) < 0.8):
			place.taken.pop_back()
			continue
		var near_corner := false
		for k in place.corners:
			if p.distance_to(k) < 0.85:
				near_corner = true
		if near_corner:
			place.taken.pop_back()
			continue
		var base := Vector3(p.x, GROUND - 0.02, p.y)
		var size := place.rng.randf_range(0.75, 1.2) * (0.8 if p.y > place.centre.y else 1.0)
		if place.rng.randf() < 0.8:
			pine(kit, base, size, place.rng)
		else:
			round_tree(kit, base, size * 0.9, place.rng)
	for i in 4:
		var p := place.spot(0.12, 20, 0.2, 0.5)
		if p != Vector2.INF:
			bush(kit, Vector3(p.x, GROUND, p.y), place.rng.randf_range(0.8, 1.3), place.rng)
	# A felled log and a ring of mushrooms.
	var p := place.spot(0.25, 20, 0.3, 0.55)
	if p != Vector2.INF:
		kit.xform = Transform3D(Basis(Vector3.UP, place.rng.randf() * TAU) * Basis(Vector3.FORWARD, PI / 2), Vector3(p.x, GROUND + 0.07, p.y))
		kit.frustum(Vector3(0, -0.25, 0), 0.07, 0.07, 0.5, 6, C.trunk, C.hay)
		kit.reset()
	p = place.spot(0.1, 20, 0.2, 0.5)
	if p != Vector2.INF:
		for k in 4:
			var o := Vector2(cos(k * 1.7), sin(k * 1.7)) * 0.09
			kit.frustum(Vector3(p.x + o.x, GROUND, p.y + o.y), 0.015, 0.015, 0.05, 4, C.plaster)
			kit.blob(Vector3(p.x + o.x, GROUND + 0.06, p.y + o.y), Vector3(0.04, 0.025, 0.04), C.mushroom, 0.1, 2, 6)


static func _farm(kit: MeshKit, place: Placer) -> Array:
	var c := place.centre
	var rng := place.rng
	# A windmill on the field's back half; its sails turn.
	var mill := c + Vector2(rng.randf_range(-0.6, 0.6), -0.85)
	place.taken.append([mill, 0.45])
	kit.frustum(Vector3(mill.x, GROUND - 0.02, mill.y), 0.26, 0.17, 0.75, 8, C.plaster, C.plaster)
	kit.cone(Vector3(mill.x, GROUND + 0.73, mill.y), 0.22, 0.28, 8, C.brick)
	kit.box(Vector3(mill.x, GROUND + 0.1, mill.y + 0.2), Vector3(0.11, 0.18, 0.08), C.wood_dark)
	kit.box(Vector3(mill.x + 0.0, GROUND + 0.45, mill.y + 0.17), Vector3(0.08, 0.09, 0.04), C.wood_dark)
	var sails := MeshKit.new(rng.randi())
	sails.box(Vector3(0, 0, 0.02), Vector3(0.07, 0.07, 0.08), C.wood_dark)
	for k in 4:
		sails.xform = Transform3D(Basis(Vector3.BACK, k * PI / 2), Vector3.ZERO)
		sails.box(Vector3(0, 0.32, 0.05), Vector3(0.03, 0.62, 0.02), C.wood_dark)
		sails.box(Vector3(0.07, 0.38, 0.055), Vector3(0.12, 0.48, 0.01), C.plaster_shade)
	var sail_node := MeshInstance3D.new()
	sail_node.mesh = sails.commit()
	sail_node.position = Vector3(mill.x, GROUND + 0.62, mill.y + 0.24)
	sail_node.set_meta("spin", Vector3(0, 0, -0.9))
	# Rows of wheat across the rest of the field.
	var angle := rng.randf_range(-0.4, 0.4)
	var along := Vector2(cos(angle), sin(angle))
	var across := Vector2(-along.y, along.x)
	for row in range(-9, 10):
		for step in range(-14, 15):
			var p := c + across * (row * 0.17) + along * (step * 0.12) + Vector2(rng.randf_range(-0.03, 0.03), rng.randf_range(-0.03, 0.03))
			if not place.ok(p, 0.0, 0.26, 0.6):
				continue
			var hgt := rng.randf_range(0.16, 0.24)
			var tone: Color = C.grain_light.lerp(C.hay, rng.randf())
			kit.cone(Vector3(p.x, GROUND - 0.01, p.y), 0.065, hgt, 4, tone, rng.randf() * TAU)
	# Hay bales.
	for i in 3:
		var p := place.spot(0.2, 20, 0.3, 0.6)
		if p == Vector2.INF:
			continue
		kit.xform = Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, PI / 2), Vector3(p.x, GROUND + 0.1, p.y))
		kit.frustum(Vector3(0, -0.11, 0), 0.11, 0.11, 0.22, 8, C.hay, C.grain_dark)
		kit.reset()
	return [sail_node]


static func _clay_pit(kit: MeshKit, place: Placer) -> void:
	var rng := place.rng
	# Two dug terraces: darker steps sunk into the ground.
	for i in 2:
		var p := place.spot(0.5, 30, 0.55, 0.85)
		if p == Vector2.INF:
			continue
		var ring := MeshKit.ngon(7, rng.randf_range(0.36, 0.46), rng.randf(), p)
		kit.extrude(ring, GROUND - 0.2, GROUND + 0.015, C.clay_dark, C.clay_dark.darkened(0.15))
		var inner := MeshKit.ngon(7, 0.22, rng.randf(), p)
		kit.extrude(inner, GROUND - 0.2, GROUND - 0.07, C.clay_dark.darkened(0.12), C.clay_dark.darkened(0.25))
	# A kiln with a dark mouth.
	var k := place.spot(0.3, 30, 0.4, 0.7)
	if k != Vector2.INF:
		kit.frustum(Vector3(k.x, GROUND - 0.02, k.y), 0.26, 0.15, 0.42, 8, C.brick, C.earth_dark)
		kit.frustum(Vector3(k.x, GROUND + 0.4, k.y), 0.07, 0.06, 0.2, 6, C.brick.darkened(0.2))
		kit.box(Vector3(k.x, GROUND + 0.1, k.y + 0.22), Vector3(0.14, 0.16, 0.06), C.earth_dark.darkened(0.4))
	# Stacks of bricks.
	for i in 3:
		var p := place.spot(0.2, 30, 0.3, 0.6)
		if p == Vector2.INF:
			continue
		var yaw := rng.randf() * TAU
		kit.at(Vector3(p.x, GROUND, p.y), yaw)
		for layer in 3:
			for b in 3 - layer:
				var o := (b - (2 - layer) / 2.0) * 0.1
				kit.box(Vector3(o, 0.03 + layer * 0.055, 0), Vector3(0.09, 0.05, 0.16), C.brick.lerp(C.clay_light, rng.randf() * 0.3))
		kit.reset()
	# Mounds of dug clay.
	for i in 4:
		var p := place.spot(0.15, 20, 0.25, 0.55)
		if p != Vector2.INF:
			kit.blob(Vector3(p.x, GROUND, p.y), Vector3(0.2, 0.12, 0.17) * rng.randf_range(0.8, 1.3), C.clay_light, 0.2, 3, 6, true)
	for i in 3:
		var p := place.spot(0.12, 20, 0.2, 0.5)
		if p != Vector2.INF:
			kit.rock(Vector3(p.x, GROUND - 0.03, p.y), rng.randf_range(0.07, 0.12), C.stone)


static func sheep(kit: MeshKit, base: Vector3, yaw: float, rng: RandomNumberGenerator) -> void:
	kit.at(base, yaw, rng.randf_range(0.85, 1.1))
	for leg in [Vector2(-0.06, -0.035), Vector2(0.06, -0.035), Vector2(-0.06, 0.035), Vector2(0.06, 0.035)]:
		kit.box(Vector3(leg.x, 0.04, leg.y), Vector3(0.025, 0.08, 0.025), C.sheep_face)
	kit.blob(Vector3(0, 0.13, 0), Vector3(0.13, 0.085, 0.09), C.wool, 0.15, 3, 7)
	kit.blob(Vector3(-0.03, 0.18, 0), Vector3(0.08, 0.05, 0.07), C.wool, 0.15, 3, 6)
	kit.blob(Vector3(0.14, 0.16, 0), Vector3(0.045, 0.04, 0.035), C.sheep_face, 0.05, 3, 6)
	kit.box(Vector3(0.13, 0.19, 0.035), Vector3(0.02, 0.012, 0.03), C.sheep_face)
	kit.box(Vector3(0.13, 0.19, -0.035), Vector3(0.02, 0.012, 0.03), C.sheep_face)
	kit.reset()


static func _pasture(kit: MeshKit, place: Placer) -> void:
	var rng := place.rng
	# A fence along part of the field's edge.
	var start := rng.randi() % 6
	var corners := place.corners
	for side in 2:
		var a: Vector2 = corners[(start + side) % 6]
		var b: Vector2 = corners[(start + side + 1) % 6]
		var a2 := place.centre + (a - place.centre) * 0.78
		var b2 := place.centre + (b - place.centre) * 0.78
		var posts := 6
		for k in posts + 1:
			var t := float(k) / posts
			var p := a2.lerp(b2, t)
			if p.distance_to(a) < 0.62 * 1.2 or p.distance_to(b) < 0.62 * 1.2:
				continue
			kit.box(Vector3(p.x, GROUND + 0.09, p.y), Vector3(0.04, 0.2, 0.04), C.wood)
			if k < posts:
				var q := a2.lerp(b2, float(k + 1) / posts)
				if q.distance_to(a) < 0.62 * 1.2 or q.distance_to(b) < 0.62 * 1.2:
					continue
				var mid := (p + q) / 2.0
				var yaw := -atan2(q.y - p.y, q.x - p.x)
				kit.at(Vector3(mid.x, GROUND, mid.y), yaw)
				kit.box(Vector3(0, 0.15, 0), Vector3(p.distance_to(q), 0.03, 0.02), C.wood)
				kit.box(Vector3(0, 0.08, 0), Vector3(p.distance_to(q), 0.03, 0.02), C.wood)
				kit.reset()
	for i in 6:
		var p := place.spot(0.22, 30, 0.3, 0.6)
		if p != Vector2.INF:
			sheep(kit, Vector3(p.x, GROUND - 0.01, p.y), rng.randf() * TAU, rng)
	for i in 3:
		var p := place.spot(0.15, 20, 0.25, 0.55)
		if p != Vector2.INF:
			bush(kit, Vector3(p.x, GROUND, p.y), rng.randf_range(0.8, 1.2), rng)
	var p := place.spot(0.3, 20, 0.35, 0.6)
	if p != Vector2.INF:
		round_tree(kit, Vector3(p.x, GROUND - 0.02, p.y), 1.1, rng)


static func _mountain(kit: MeshKit, place: Placer) -> void:
	var rng := place.rng
	var c := place.centre + Vector2(rng.randf_range(-0.15, 0.15), -0.35)
	place.taken.append([c, 0.95])
	var peak_h := rng.randf_range(2.0, 2.4)
	var rings := [[1.25, 0.0], [0.95, 0.55], [0.62, 1.15], [0.32, 1.7]]
	var sides := 9
	var grid: Array = []
	for ring in rings:
		var row: Array = []
		for s in sides:
			var a := TAU * s / sides + rng.randf_range(-0.12, 0.12)
			var rr: float = ring[0] * rng.randf_range(0.85, 1.12)
			var y: float = ring[1] * peak_h / 1.9 + rng.randf_range(-0.08, 0.08)
			row.append(Vector3(c.x + cos(a) * rr, GROUND - 0.03 + y, c.y - sin(a) * rr * 0.9))
		grid.append(row)
	var tip := Vector3(c.x + rng.randf_range(-0.1, 0.1), GROUND + peak_h, c.y + rng.randf_range(-0.05, 0.05))
	var shade := func(a: Vector3, b: Vector3, d: Vector3) -> Color:
		var n := (b - a).cross(d - a).normalized()
		var y := (a.y + b.y + d.y) / 3.0
		if y > GROUND + peak_h * 0.68 and absf(n.y) > 0.35:
			return C.snow
		var col: Color = C.rock.lerp(C.rock_light, clampf(n.dot(Vector3(0.4, 0.5, 0.6).normalized()), 0.0, 1.0))
		if y < GROUND + 0.4:
			col = col.lerp(C.rock_dark, 0.35)
		return col
	for r in rings.size():
		for s in sides:
			var a: Vector3 = grid[r][s]
			var b: Vector3 = grid[r][(s + 1) % sides]
			if r == rings.size() - 1:
				kit.tri(a, b, tip, shade.call(a, b, tip))
			else:
				var d: Vector3 = grid[r + 1][s]
				var e: Vector3 = grid[r + 1][(s + 1) % sides]
				kit.tri(a, b, e, shade.call(a, b, e))
				kit.tri(a, e, d, shade.call(a, e, d))
	# Boulders, a few hardy pines and a mine entrance at the foot.
	for i in 6:
		var p := place.spot(0.16, 30, 0.25, 0.55)
		if p != Vector2.INF:
			kit.rock(Vector3(p.x, GROUND - 0.03, p.y), rng.randf_range(0.1, 0.2), C.rock.lerp(C.rock_dark, rng.randf() * 0.5))
	for i in 4:
		var p := place.spot(0.2, 30, 0.3, 0.6)
		if p != Vector2.INF:
			pine(kit, Vector3(p.x, GROUND - 0.02, p.y), rng.randf_range(0.6, 0.85), rng)
	var m := c + Vector2(0.55, 0.78)
	kit.at(Vector3(m.x, GROUND, m.y), -0.5)
	kit.box(Vector3(0, 0.14, 0.0), Vector3(0.3, 0.28, 0.06), C.sheep_face)
	kit.box(Vector3(-0.15, 0.15, 0.03), Vector3(0.04, 0.3, 0.05), C.wood)
	kit.box(Vector3(0.15, 0.15, 0.03), Vector3(0.04, 0.3, 0.05), C.wood)
	kit.box(Vector3(0, 0.31, 0.03), Vector3(0.38, 0.05, 0.06), C.wood)
	kit.box(Vector3(0.05, 0.02, 0.22), Vector3(0.05, 0.02, 0.4), C.wood_dark)
	kit.reset()


static func _lake(kit: MeshKit, place: Placer) -> Array:
	var rng := place.rng
	var c := place.centre
	for i in 14:
		var a := rng.randf() * TAU
		var d := rng.randf_range(1.0, 1.35)
		var p := c + Vector2(cos(a), sin(a)) * d
		if not place.ok(p, 0.0, 0.25, 0.0):
			continue
		for k in 3:
			var o := Vector2(rng.randf_range(-0.08, 0.08), rng.randf_range(-0.08, 0.08))
			kit.cone(Vector3(p.x + o.x, GROUND - 0.12, p.y + o.y), 0.025, rng.randf_range(0.25, 0.4), 3, C.reed)
	for i in 5:
		var a := rng.randf() * TAU
		var p := c + Vector2(cos(a), sin(a)) * rng.randf_range(0.3, 0.9)
		kit.extrude(MeshKit.ngon(7, rng.randf_range(0.07, 0.11), rng.randf(), p), GROUND - 0.08, GROUND - 0.075, C.lily, C.lily)
	for i in 6:
		var a := rng.randf() * TAU
		var p := c + Vector2(cos(a), sin(a)) * rng.randf_range(1.15, 1.45)
		if place.ok(p, 0.0, 0.2, 0.0):
			kit.rock(Vector3(p.x, GROUND - 0.06, p.y), rng.randf_range(0.08, 0.15), C.stone)
	# A little jetty.
	var a := rng.randf() * TAU
	var from := c + Vector2(cos(a), sin(a)) * 1.35
	var to := c + Vector2(cos(a), sin(a)) * 0.75
	var mid := (from + to) / 2.0
	kit.at(Vector3(mid.x, GROUND - 0.02, mid.y), -a)
	kit.box(Vector3(0, 0, 0), Vector3(0.6, 0.03, 0.2), C.wood)
	for k in [-0.25, 0.0, 0.25]:
		kit.box(Vector3(k, -0.1, 0.1), Vector3(0.03, 0.2, 0.03), C.wood_dark)
		kit.box(Vector3(k, -0.1, -0.1), Vector3(0.03, 0.2, 0.03), C.wood_dark)
	kit.reset()
	var water := MeshInstance3D.new()
	var hex := MeshKit.new(1)
	hex.jitter = 0.0
	hex.extrude(Art.hex_ring(Vector2.ZERO, S * 0.86), -0.01, 0.0, Color.WHITE, Color.WHITE)
	water.mesh = hex.commit()
	water.position = Vector3(c.x, GROUND - 0.1, c.y)
	water.set_meta("water", true)
	return [water]


## What a field gives, as a little thing that flies to a hamlet.
static func harvest_piece(res: String) -> ArrayMesh:
	var kit := MeshKit.new(7)
	match res:
		"timber":
			# Two logs, lying down.
			for z in [-0.12, 0.12]:
				kit.xform = Transform3D(Basis(Vector3.BACK, PI / 2), Vector3(0.28, 0.12, z))
				kit.frustum(Vector3.ZERO, 0.11, 0.11, 0.56, 7, C.trunk, C.hay)
			kit.xform = Transform3D(Basis(Vector3.BACK, PI / 2), Vector3(0.28, 0.32, 0))
			kit.frustum(Vector3.ZERO, 0.11, 0.11, 0.56, 7, C.wood, C.hay)
			kit.reset()
		"clay":
			kit.box(Vector3(0, 0.08, 0), Vector3(0.42, 0.16, 0.22), C.brick, C.clay_light)
			kit.box(Vector3(0.05, 0.24, 0.02), Vector3(0.42, 0.16, 0.22), C.brick, C.clay_light)
		"wool":
			kit.blob(Vector3(0, 0.18, 0), Vector3(0.24, 0.18, 0.2), C.wool, 0.25, 4, 7)
		"grain":
			kit.frustum(Vector3.ZERO, 0.08, 0.16, 0.42, 7, C.grain_dark, C.grain_light)
			kit.box(Vector3(0, 0.16, 0), Vector3(0.2, 0.05, 0.2), C.wood_dark)
		"ore":
			kit.rock(Vector3.ZERO, 0.26, C.rock_light)
	return kit.commit()


## A flat hexagonal band, for marking a whole field.
static func hex_band(outer_r: float, inner_r: float) -> ArrayMesh:
	var kit := MeshKit.new(1)
	kit.jitter = 0.0
	var outer := hex_ring(Vector2.ZERO, outer_r)
	var inner := hex_ring(Vector2.ZERO, inner_r)
	for k in 6:
		var a1: Vector2 = outer[k]
		var b1: Vector2 = outer[(k + 1) % 6]
		var a0: Vector2 = inner[k]
		var b0: Vector2 = inner[(k + 1) % 6]
		kit.quad(Vector3(a1.x, 0, a1.y), Vector3(b1.x, 0, b1.y), Vector3(b0.x, 0, b0.y), Vector3(a0.x, 0, a0.y), Color.WHITE)
	return kit.commit()


# --- Beach and sea --------------------------------------------------------

## The sand and shallows around the island: hexes next to land that slope
## from a beach under the cliffs into the sea.
static func shore(cells: Array, seed_value: int) -> ArrayMesh:
	var land := {}
	for cell in cells:
		land[cell] = true
	var ring := {}
	for cell in cells:
		for d in Rules.DIRS:
			for k in [1, 2]:
				var n: Vector2i = cell + d * k
				if not land.has(n):
					ring[n] = true
			var n2: Vector2i = cell + d + Rules.DIRS[(Rules.DIRS.find(d) + 1) % 6]
			if not land.has(n2):
				ring[n2] = true
	var centres: Array = []
	for cell in cells:
		centres.append(_cell_world(cell))
	var kit := MeshKit.new(seed_value)
	kit.jitter = 0.03
	var height := func(p: Vector2) -> float:
		var d := INF
		for c in centres:
			d = minf(d, hex_sdf(p - c, S))
		var wobble := noise.get_noise_2d(p.x * 0.9 + seed_value, p.y * 0.9) * 0.45
		d = maxf(0.0, d + wobble * 0.5)
		return 0.26 - d * 0.42 - d * d * 0.12
	var paint := func(_p: Vector2, h: float, _n: Vector3) -> Color:
		if h > 0.08:
			return C.sand
		if h > -0.04:
			return C.sand_wet
		return C.sand_deep.lerp(Color("5c9b8f"), clampf(-h * 0.8, 0.0, 1.0))
	for cell in ring:
		hex_surface(kit, _cell_world(cell), S, 4, height, paint)
	# Rocks along the beach.
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for cell in ring:
		if rng.randf() < 0.55:
			var c: Vector2 = _cell_world(cell) + Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1))
			var h: float = height.call(c)
			if h > -0.25:
				kit.rock(Vector3(c.x, h - 0.05, c.y), rng.randf_range(0.12, 0.3), C.stone.lerp(C.stone_dark, rng.randf()))
	return kit.commit()


static func _cell_world(cell: Vector2i) -> Vector2:
	return Vector2(sqrt(3.0) * (cell.x + cell.y / 2.0), 1.5 * cell.y) * S


# --- Pieces ---------------------------------------------------------------

## A hamlet: a cottage with a roof in its owner's colour.
static func hamlet(color: Color, seed_value := 1) -> ArrayMesh:
	var kit := MeshKit.new(seed_value)
	kit.jitter = 0.025
	var roof_col := color
	kit.extrude(MeshKit.ngon(8, 0.36, 0.2), -0.05, 0.03, C.stone, C.stone_dark)
	kit.box(Vector3(0, 0.2, 0), Vector3(0.42, 0.34, 0.3), C.plaster, C.plaster)
	# Timber framing.
	for x in [-0.205, 0.205]:
		kit.box(Vector3(x, 0.2, 0.152), Vector3(0.035, 0.34, 0.01), C.wood_dark)
	kit.box(Vector3(0, 0.3, 0.152), Vector3(0.42, 0.03, 0.01), C.wood_dark)
	kit.box(Vector3(-0.08, 0.12, 0.152), Vector3(0.09, 0.17, 0.012), C.wood_dark)
	kit.box(Vector3(0.1, 0.18, 0.152), Vector3(0.08, 0.07, 0.012), Color("ffe7a3"))
	kit.roof(Vector3(0, 0.37, 0), 0.42, 0.3, 0.24, roof_col, C.plaster_shade)
	kit.box(Vector3(0.12, 0.55, -0.05), Vector3(0.06, 0.18, 0.06), C.stone_dark)
	return kit.commit()


## A town: a hall, a house and a tower with a pennant.
static func town(color: Color, seed_value := 1) -> ArrayMesh:
	var kit := MeshKit.new(seed_value)
	kit.jitter = 0.025
	kit.extrude(MeshKit.ngon(9, 0.5, 0.2), -0.05, 0.04, C.stone, C.stone_dark)
	# Hall.
	kit.box(Vector3(-0.08, 0.26, 0.06), Vector3(0.5, 0.44, 0.3), C.plaster)
	kit.box(Vector3(-0.08, 0.28, 0.212), Vector3(0.5, 0.03, 0.01), C.wood_dark)
	kit.box(Vector3(-0.2, 0.13, 0.212), Vector3(0.1, 0.2, 0.012), C.wood_dark)
	for x in [-0.02, 0.1]:
		kit.box(Vector3(x, 0.38, 0.212), Vector3(0.07, 0.08, 0.012), Color("ffe7a3"))
	kit.roof(Vector3(-0.08, 0.48, 0.06), 0.5, 0.3, 0.26, color, C.plaster_shade)
	# Tower.
	kit.frustum(Vector3(0.24, 0.0, -0.14), 0.13, 0.12, 0.78, 8, C.stone.lightened(0.1), C.stone)
	kit.frustum(Vector3(0.24, 0.78, -0.14), 0.15, 0.15, 0.04, 8, C.wood_dark)
	kit.cone(Vector3(0.24, 0.82, -0.14), 0.17, 0.3, 8, color)
	kit.box(Vector3(0.24, 1.2, -0.14), Vector3(0.015, 0.18, 0.015), C.wood_dark)
	kit.box(Vector3(0.3, 1.25, -0.14), Vector3(0.11, 0.07, 0.01), color.lightened(0.15))
	kit.box(Vector3(0.24, 0.5, -0.015), Vector3(0.06, 0.09, 0.012), Color("ffe7a3"))
	return kit.commit()


## A road along a side: a packed path with a kerb in its owner's colour.
static func road(color: Color, length: float, seed_value := 1) -> ArrayMesh:
	var kit := MeshKit.new(seed_value)
	kit.jitter = 0.03
	kit.box(Vector3(0, 0.03, 0), Vector3(length, 0.09, 0.3), color.darkened(0.15), color)
	var stones := int(length / 0.14)
	for i in stones:
		var x := -length / 2.0 + (i + 0.5) * length / stones
		kit.box(Vector3(x, 0.065, 0), Vector3(length / stones * 0.8, 0.02, 0.14), C.plaster_shade.lerp(C.stone, kit.rng.randf() * 0.5))
	return kit.commit()


## The wooden number token on a field.
static func token_disc() -> ArrayMesh:
	var kit := MeshKit.new(3)
	kit.jitter = 0.0
	kit.frustum(Vector3(0, 0, 0), 0.52, 0.52, 0.07, 18, C.wood_dark, C.wood_dark)
	kit.frustum(Vector3(0, 0.07, 0), 0.47, 0.47, 0.02, 18, Color("f4e7c6"), Color("f4e7c6"))
	return kit.commit()


## The storm cloud that sits over a field.
static func storm_cloud() -> ArrayMesh:
	var kit := MeshKit.new(5)
	kit.jitter = 0.03
	# Billows in a ring and a tall middle, with a flat dark base like a
	# thundercloud: light on top, slate underneath.
	var puffs: Array = [[Vector3(0, 0.35, 0), Vector3(0.75, 0.6, 0.62)], [Vector3(0.15, 0.75, -0.05), Vector3(0.5, 0.45, 0.45)]]
	for i in 8:
		var a := TAU * i / 8.0 + kit.rng.randf_range(-0.2, 0.2)
		var o := Vector3(cos(a) * 0.85, kit.rng.randf_range(0.1, 0.3), sin(a) * 0.6)
		puffs.append([o, Vector3(0.48, 0.42, 0.44) * kit.rng.randf_range(0.8, 1.15)])
	for p in puffs:
		kit.blob(p[0], p[1], Color.WHITE, 0.1, 5, 9, true)
	return _shade_by_height(kit.commit(), Color("3a4255"), Color("9aa3b8"), 0.0, 1.1)


## Recolours a mesh from `low` at y0 to `high` at y1 (keeps flat normals).
static func _shade_by_height(mesh: ArrayMesh, low: Color, high: Color, y0: float, y1: float) -> ArrayMesh:
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colors := PackedColorArray()
	colors.resize(verts.size())
	for i in range(0, verts.size(), 3):
		var y := (verts[i].y + verts[i + 1].y + verts[i + 2].y) / 3.0
		var c := low.lerp(high, smoothstep(y0, y1, y))
		colors[i] = c
		colors[i + 1] = c
		colors[i + 2] = c
	arrays[Mesh.ARRAY_COLOR] = colors
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return out


## A zigzag lightning bolt from the cloud to the ground, `length` long.
static func bolt(length: float, seed_value: int) -> ArrayMesh:
	var kit := MeshKit.new(seed_value)
	kit.jitter = 0.0
	var p := Vector3.ZERO
	var steps := 6
	for i in steps:
		var q := Vector3(kit.rng.randf_range(-0.35, 0.35), -length * (i + 1) / steps, kit.rng.randf_range(-0.2, 0.2))
		var w := 0.12 * (1.0 - float(i) / steps) + 0.04
		for side in [Vector3(w, 0, 0), Vector3(0, 0, w)]:
			kit.quad(p - side, p + side, q + side, q - side, Color.WHITE)
			kit.quad(p + side, p - side, q - side, q + side, Color.WHITE)
		p = q
	return kit.commit()


## A fluffy white cloud drifting over the sea.
static func cloud(seed_value: int) -> ArrayMesh:
	var kit := MeshKit.new(seed_value)
	kit.jitter = 0.02
	for i in 5:
		var o := Vector3(kit.rng.randf_range(-0.9, 0.9), kit.rng.randf_range(0.0, 0.25), kit.rng.randf_range(-0.4, 0.4))
		kit.blob(o, Vector3(0.6, 0.38, 0.5) * kit.rng.randf_range(0.7, 1.2), Color("fdfcf8"), 0.15, 4, 8)
	return kit.commit()


## A festival: a maypole with ribbons, bunting and a couple of tents.
static func festival(seed_value := 1) -> ArrayMesh:
	var kit := MeshKit.new(seed_value)
	kit.jitter = 0.03
	var colors := [Color("e8553e"), Color("f2c230"), Color("3d8fe0"), Color("3fbf7f"), Color("f08acb")]
	kit.frustum(Vector3(0, 0, 0), 0.04, 0.03, 1.1, 6, C.plaster)
	kit.blob(Vector3(0, 1.12, 0), Vector3(0.07, 0.07, 0.07), C.flower_yellow, 0.1, 3, 6)
	kit.cone(Vector3(0, 0.98, 0), 0.12, 0.12, 6, C.leaf)
	for i in 6:
		var a := TAU * i / 6.0
		var end := Vector3(cos(a) * 0.55, 0.02, sin(a) * 0.55)
		var top := Vector3(0, 0.98, 0)
		var col: Color = colors[i % colors.size()]
		var side := Vector3(-sin(a), 0, cos(a)) * 0.025
		kit.quad(top - side, top + side, end + side, end - side, col)
		kit.quad(top + side, top - side, end - side, end + side, col)
	for t in [[Vector3(-0.62, 0, -0.35), colors[0]], [Vector3(0.6, 0, -0.42), colors[2]]]:
		kit.frustum(t[0], 0.26, 0.26, 0.16, 8, C.plaster)
		kit.cone(t[0] + Vector3(0, 0.16, 0), 0.3, 0.32, 8, t[1])
	for i in 7:
		kit.blob(Vector3(kit.rng.randf_range(-0.6, 0.6), 0.03, kit.rng.randf_range(0.2, 0.6)), Vector3(0.04, 0.03, 0.04), colors[i % colors.size()], 0.1, 2, 5)
	return kit.commit()


## A small grass plot that pieces stand on in card pictures.
static func plot(seed_value := 1) -> ArrayMesh:
	var kit := MeshKit.new(seed_value)
	var c := Vector2.ZERO
	var ground := func(p: Vector2) -> float:
		return GROUND + noise.get_noise_2d(p.x * 3.0, p.y * 3.0) * 0.03
	var paint := func(p: Vector2, _h: float, _n: Vector3) -> Color:
		return C.grass.lerp(C.grass_light, clampf(noise.get_noise_2d(p.x * 2.0, p.y * 2.0) + 0.5, 0, 1))
	hex_surface(kit, c, S * 0.955, 5, ground, paint)
	var outer := hex_ring(c, S)
	var inner := hex_ring(c, S * 0.955)
	for k in 6:
		var a0: Vector2 = inner[k]
		var b0: Vector2 = inner[(k + 1) % 6]
		var a1: Vector2 = outer[k]
		var b1: Vector2 = outer[(k + 1) % 6]
		kit.quad(Vector3(a1.x, GROUND - BEVEL, a1.y), Vector3(b1.x, GROUND - BEVEL, b1.y), Vector3(b0.x, GROUND, b0.y), Vector3(a0.x, GROUND, a0.y), C.grass_dark)
		kit.quad(Vector3(a1.x, GROUND - 0.42, a1.y), Vector3(b1.x, GROUND - 0.42, b1.y), Vector3(b1.x, GROUND - BEVEL, b1.y), Vector3(a1.x, GROUND - BEVEL, a1.y), C.earth)
		kit.quad(Vector3(a1.x, -0.5, a1.y), Vector3(b1.x, -0.5, b1.y), Vector3(b1.x, GROUND - 0.42, b1.y), Vector3(a1.x, GROUND - 0.42, a1.y), C.stone)
	var place := Placer.new(c, seed_value)
	place.taken.append([Vector2.ZERO, 1.0])
	_flowers(kit, place, 8)
	for i in 3:
		var p := place.spot(0.2, 20, 0.3, 0.0)
		if p != Vector2.INF:
			bush(kit, Vector3(p.x, GROUND, p.y), 1.0, place.rng)
	return kit.commit()
