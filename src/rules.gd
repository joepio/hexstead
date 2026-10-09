class_name Rules
extends RefCounted
## Hexstead rules: a random island of hex fields, dice that make the fields
## produce, and hamlets, towns, roads and festivals to buy with what they
## produce. No nodes, so the tests run it headless.
##
## Ids and seat numbers are 1-based, as the phone page expects them:
## `tiles[id - 1]`, `verts[id - 1]`, `edges[id - 1]`, `players[i - 1]`.

const RESOURCES := ["timber", "clay", "wool", "grain", "ore"]
const LABEL := {timber = "Timber", clay = "Clay", wool = "Wool", grain = "Grain", ore = "Ore"}
const COST := {
	road = {timber = 1, clay = 1},
	hamlet = {timber = 1, clay = 1, wool = 1, grain = 1},
	town = {grain = 2, ore = 3},
	festival = {wool = 1, grain = 1, ore = 1},
}
const LIMIT := {road = 15, hamlet = 5, town = 4, festival = 2}
const GOAL := 8
## A storm makes anyone holding more than this lose half their hand.
const HAND_LIMIT := 9
const COLORS := ["#e8553e", "#3d8fe0", "#f2c230", "#8a5cd6", "#3fbf7f", "#f08acb"]

const DIRS := [Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1)]
const FIELDS := ["timber", "timber", "timber", "timber", "clay", "clay", "clay", "wool", "wool",
	"wool", "wool", "grain", "grain", "grain", "grain", "ore", "ore", "ore"]
const NUMBERS := [2, 3, 3, 4, 4, 5, 5, 6, 6, 8, 8, 9, 9, 10, 10, 11, 11, 12]

var rng: RandomNumberGenerator
var tiles: Array = []
var verts: Array = []
var edges: Array = []
var players: Array = []
var storm := 0
var setup: Array = []
var setup_step := 0
var turn := 1
var phase := "setup_hamlet"
var round_no := 1
var market := "timber"
var dice: Array = []
var last_hamlet := 0
var winner := 0
var messages: Array = []
## Counts every change, so the game knows when to resend views.
var events := 0
## What happened last, for the TV to animate: {kind, player, id, ...}.
var last_event: Dictionary = {}


## How many of 36 rolls hit each number.
static func pips(n: int) -> int:
	return 0 if n == 0 else 6 - absi(7 - n)


static func hex_distance(a: Vector2i, b: Vector2i) -> int:
	var d := a - b
	return maxi(absi(d.x), maxi(absi(d.y), absi(d.x + d.y)))


func roll(a: int, b: int) -> int:
	return rng.randi_range(a, b)


func _shuffle(list: Array) -> Array:
	var out := list.duplicate()
	for i in range(out.size() - 1, 0, -1):
		var j := roll(0, i)
		var tmp = out[i]
		out[i] = out[j]
		out[j] = tmp
	return out


## Grow a random connected island of 19 hexes. Every round gets a new
## coastline, so no two boards play alike.
func _island() -> Array:
	var cells: Array = []
	var seen := {Vector2i.ZERO: true}
	var frontier: Array = []
	var add := func(c: Vector2i) -> void:
		cells.append(c)
		for d in DIRS:
			var n: Vector2i = c + d
			# Keep the island compact enough to read from the couch.
			if not seen.has(n) and hex_distance(n, Vector2i.ZERO) <= 3:
				seen[n] = true
				frontier.append(n)
	add.call(Vector2i.ZERO)
	while cells.size() < 19:
		# Prefer cells with more land around them, so the island stays solid.
		var best := -1
		var best_score := -1
		for i in frontier.size():
			var around := 0
			for other in cells:
				if hex_distance(other, frontier[i]) == 1:
					around += 1
			var score := around * 10 + roll(0, 14)
			if score > best_score:
				best = i
				best_score = score
		var c: Vector2i = frontier[best]
		frontier.remove_at(best)
		add.call(c)
	return cells


## Build the board: tiles, the corners where hamlets go (vertices) and the
## sides where roads go (edges).
func _board() -> void:
	var cells := _island()
	var lake := roll(0, cells.size() - 1)
	var fields := _shuffle(FIELDS)
	var placed := {}
	# 6s and 8s never touch, so no corner is a jackpot.
	for _try in 200:
		var numbers := _shuffle(NUMBERS)
		placed = {}
		var k := 0
		for i in cells.size():
			if i != lake:
				placed[i] = numbers[k]
				k += 1
		var ok := true
		for i in cells.size():
			for j in range(i + 1, cells.size()):
				if placed.has(i) and placed.has(j) and pips(placed[i]) == 5 and pips(placed[j]) == 5 \
						and hex_distance(cells[i], cells[j]) == 1:
					ok = false
		if ok:
			break
	tiles = []
	verts = []
	edges = []
	var k := 0
	for i in cells.size():
		var c: Vector2i = cells[i]
		var tile := {
			id = i + 1, q = c.x, r = c.y,
			x = sqrt(3.0) * (c.x + c.y / 2.0), y = 1.5 * c.y,
			verts = [], res = "", num = 0,
		}
		if i != lake:
			tile.res = fields[k]
			tile.num = placed[i]
			k += 1
		tiles.append(tile)
	var vert_at := {}
	var edge_at := {}
	for tile in tiles:
		var ring: Array = []
		for c in 6:
			var a := deg_to_rad(60.0 * c - 30.0)
			var x: float = tile.x + cos(a)
			var y: float = tile.y + sin(a)
			var key := "%d,%d" % [roundi(x * 100), roundi(y * 100)]
			if not vert_at.has(key):
				var v := {id = verts.size() + 1, x = x, y = y, tiles = [], adj = [], edges = [], owner = 0, kind = ""}
				verts.append(v)
				vert_at[key] = v
			var v: Dictionary = vert_at[key]
			ring.append(v)
			tile.verts.append(v.id)
			v.tiles.append(tile.id)
		for c in 6:
			var a: Dictionary = ring[c]
			var b: Dictionary = ring[(c + 1) % 6]
			var lo := mini(a.id, b.id)
			var hi := maxi(a.id, b.id)
			var key := "%d-%d" % [lo, hi]
			if not edge_at.has(key):
				var e := {id = edges.size() + 1, a = lo, b = hi, owner = 0}
				edges.append(e)
				edge_at[key] = e
				a.adj.append(b.id)
				b.adj.append(a.id)
				a.edges.append(e.id)
				b.edges.append(e.id)
	storm = lake + 1


## A new game for these players (`{id, name, color, bot}`), in seat order.
static func create(roster: Array, seed_value: int) -> Rules:
	var s := Rules.new()
	s.rng = RandomNumberGenerator.new()
	s.rng.seed = seed_value
	s._board()
	for i in roster.size():
		var p: Dictionary = roster[i]
		var hand := {}
		for res in RESOURCES:
			hand[res] = 0
		s.players.append({
			index = i + 1,
			id = str(p.get("id", "")),
			name = p.get("name", "Player %d" % (i + 1)),
			color = p.get("color", COLORS[i % COLORS.size()]),
			bot = p.get("bot", false) == true,
			hand = hand,
			built = {road = 0, hamlet = 0, town = 0, festival = 0},
		})
	# Setup: everyone places a hamlet and a road, then again in reverse.
	for i in s.players.size():
		s.setup.append(i + 1)
	for i in range(s.players.size(), 0, -1):
		s.setup.append(i)
	s.setup_step = 1
	s.turn = s.setup[0]
	s.phase = "setup_hamlet"
	s.market = RESOURCES[s.roll(0, RESOURCES.size() - 1)]
	s.say("A new island rises. Place your first hamlets.")
	return s


func tile(id: int) -> Dictionary:
	return tiles[id - 1]


func vert(id: int) -> Dictionary:
	return verts[id - 1]


func edge(id: int) -> Dictionary:
	return edges[id - 1]


func player(i: int) -> Dictionary:
	return players[i - 1]


func say(text: String) -> void:
	messages.push_front(text)
	while messages.size() > 6:
		messages.pop_back()
	events += 1


static func vp(p: Dictionary) -> int:
	return p.built.hamlet + 2 * p.built.town + p.built.festival


static func cards(p: Dictionary) -> int:
	var n := 0
	for res in RESOURCES:
		n += p.hand[res]
	return n


static func can_afford(p: Dictionary, kind: String) -> bool:
	for res in COST[kind]:
		if p.hand[res] < COST[kind][res]:
			return false
	return true


static func _pay(p: Dictionary, kind: String) -> void:
	for res in COST[kind]:
		p.hand[res] -= COST[kind][res]


func _free_corner(v: Dictionary) -> bool:
	if v.owner:
		return false
	for other in v.adj:
		if vert(other).owner:
			return false
	return true


## Corners where player `i` may put a hamlet now.
func hamlet_spots(i: int) -> Array:
	var out: Array = []
	for v in verts:
		if _free_corner(v):
			var reached := phase == "setup_hamlet"
			if not reached:
				for e in v.edges:
					if edge(e).owner == i:
						reached = true
			if reached:
				out.append(v.id)
	return out


## Sides where player `i` may put a road now.
func road_spots(i: int) -> Array:
	var out: Array = []
	for e in edges:
		if e.owner:
			continue
		var ok := false
		if phase == "setup_road":
			ok = e.a == last_hamlet or e.b == last_hamlet
		else:
			for end_id in [e.a, e.b]:
				var v := vert(end_id)
				if v.owner == i:
					ok = true
				elif not v.owner:
					for other in v.edges:
						if other != e.id and edge(other).owner == i:
							ok = true
		if ok:
			out.append(e.id)
	return out


func town_spots(i: int) -> Array:
	var out: Array = []
	for v in verts:
		if v.owner == i and v.kind == "hamlet":
			out.append(v.id)
	return out


func storm_spots() -> Array:
	var out: Array = []
	for t in tiles:
		if t.id != storm:
			out.append(t.id)
	return out


func _check_win(i: int) -> void:
	var p := player(i)
	if vp(p) >= GOAL:
		winner = i
		phase = "over"
		last_event = {kind = "win", player = i}
		say("%s wins with %d points!" % [p.name, vp(p)])


func _next_setup() -> void:
	setup_step += 1
	if setup_step > setup.size():
		turn = 1
		phase = "roll"
		say("%s rolls first." % player(1).name)
	else:
		turn = setup[setup_step - 1]
		phase = "setup_hamlet"


## Pays out a roll. Returns {tile id: [[player, count], ...]} so the TV can
## fly cards from each field to its builders.
func _produce(sum: int) -> Dictionary:
	var got := {}
	for t in tiles:
		if t.num == sum and t.id != storm:
			for vid in t.verts:
				var v := vert(vid)
				if v.owner:
					var n := 2 if v.kind == "town" else 1
					player(v.owner).hand[t.res] += n
					if not got.has(t.id):
						got[t.id] = []
					got[t.id].append([v.owner, n, vid])
	return got


func _lose_random(p: Dictionary, n: int) -> Array:
	var lost: Array = []
	for _k in n:
		var pool: Array = []
		for res in RESOURCES:
			for _c in p.hand[res]:
				pool.append(res)
		if pool.is_empty():
			break
		var res: String = pool[roll(0, pool.size() - 1)]
		p.hand[res] -= 1
		lost.append(res)
	return lost


## Apply one action by player `i`. Returns "" when it worked, else why not.
## Actions: {a="hamlet", id=vertex} in setup, {a="road", id=edge},
## {a="hamlet", id=vertex}, {a="town", id=vertex}, {a="festival"},
## {a="roll"}, {a="storm", id=tile}, {a="bank", give=res, get=res},
## {a="end"}.
func act(i: int, action: Dictionary) -> String:
	if phase == "over":
		return "The game is over."
	if i != turn:
		return "Wait for your turn."
	var p := player(i)
	var a := str(action.get("a", ""))
	var id := int(action.get("id", 0))
	if phase == "setup_hamlet":
		if a != "hamlet" or not hamlet_spots(i).has(id):
			return "Pick a free corner for your hamlet."
		var v := vert(id)
		v.owner = i
		v.kind = "hamlet"
		p.built.hamlet += 1
		last_hamlet = id
		phase = "setup_road"
		var gift: Array = []
		# The second hamlet starts you off with what it touches.
		if setup_step > players.size():
			for tid in v.tiles:
				var t := tile(tid)
				if t.res != "":
					p.hand[t.res] += 1
					gift.append([tid, t.res])
		last_event = {kind = "hamlet", player = i, id = id, gift = gift}
		say("%s founded a hamlet." % p.name)
		return ""
	elif phase == "setup_road":
		if a != "road" or not road_spots(i).has(id):
			return "Pick a side next to your new hamlet."
		edge(id).owner = i
		p.built.road += 1
		last_event = {kind = "road", player = i, id = id}
		_next_setup()
		events += 1
		return ""
	elif phase == "roll":
		if a != "roll":
			return "Roll the dice first."
		dice = [roll(1, 6), roll(1, 6)]
		var sum: int = dice[0] + dice[1]
		if sum == 7:
			var losses := {}
			for other in players:
				var n := cards(other)
				if n > HAND_LIMIT:
					losses[other.index] = _lose_random(other, n / 2)
					say("%s lost %d cards to the storm." % [other.name, n / 2])
			phase = "storm"
			last_event = {kind = "roll", player = i, dice = dice, sum = sum, got = {}, losses = losses}
			say("%s rolled 7. A storm is coming!" % p.name)
		else:
			var got := _produce(sum)
			last_event = {kind = "roll", player = i, dice = dice, sum = sum, got = got}
			say("%s rolled %d%s" % [p.name, sum, "." if not got.is_empty() else ". Nothing grows."])
			phase = "build"
		return ""
	elif phase == "storm":
		if a != "storm" or not storm_spots().has(id):
			return "Move the storm to another field."
		storm = id
		var victims: Array = []
		for vid in tile(id).verts:
			var owner: int = vert(vid).owner
			if owner and owner != i and cards(player(owner)) > 0 and not victims.has(owner):
				victims.append(owner)
		var taken := ""
		var victim_index := 0
		if not victims.is_empty():
			victim_index = victims[roll(0, victims.size() - 1)]
			var victim := player(victim_index)
			var lost := _lose_random(victim, 1)
			if not lost.is_empty():
				taken = lost[0]
				p.hand[taken] += 1
			say("%s took a card from %s." % [p.name, victim.name])
		else:
			say("The storm settles over an empty field.")
		last_event = {kind = "storm", player = i, id = id, victim = victim_index, res = taken}
		phase = "build"
		return ""
	# Build phase.
	if a in ["road", "hamlet", "town"]:
		if not can_afford(p, a):
			return "You need more cards for that."
		if p.built[a] >= LIMIT[a]:
			return "You have no %ss left." % a
		var spots := road_spots(i) if a == "road" else hamlet_spots(i) if a == "hamlet" else town_spots(i)
		if not spots.has(id):
			return "You can't build there."
		_pay(p, a)
		if a == "road":
			edge(id).owner = i
		else:
			var v := vert(id)
			v.owner = i
			v.kind = a
			if a == "town":
				p.built.hamlet -= 1
		p.built[a] += 1
		last_event = {kind = a, player = i, id = id}
		say("%s built a %s." % [p.name, a])
		_check_win(i)
		return ""
	elif a == "festival":
		if p.built.festival >= LIMIT.festival:
			return "You already held two festivals."
		if not can_afford(p, "festival"):
			return "A festival takes wool, grain and ore."
		_pay(p, "festival")
		p.built.festival += 1
		last_event = {kind = "festival", player = i}
		say("%s threw a festival!" % p.name)
		_check_win(i)
		return ""
	elif a == "bank":
		var give := str(action.get("give", ""))
		var get := str(action.get("get", ""))
		if not LABEL.has(give) or not LABEL.has(get) or give == get:
			return "Pick two different resources."
		var r := rate(give)
		if p.hand[give] < r:
			return "The bank wants %d %s." % [r, LABEL[give]]
		p.hand[give] -= r
		p.hand[get] += 1
		last_event = {kind = "bank", player = i, give = give, get = get, rate = r}
		say("%s traded %d %s for %s." % [p.name, r, LABEL[give], LABEL[get]])
		return ""
	elif a == "end":
		turn = turn % players.size() + 1
		if turn == 1:
			round_no += 1
			# The market wants something new each round.
			var options: Array = RESOURCES.filter(func(res): return res != market)
			market = options[roll(0, options.size() - 1)]
			say("Market day: the bank takes %s at 2 for 1." % LABEL[market])
		phase = "roll"
		dice = []
		last_event = {kind = "end", player = i}
		events += 1
		return ""
	return "Roll, build, trade or end your turn."


## Cards of `res` the bank wants for one card of your choice.
func rate(res: String) -> int:
	return 2 if res == market else 4


## What player `i` sees on their phone.
func view(i: int) -> Dictionary:
	var p := player(i)
	var legal := {}
	if turn == i:
		if phase == "setup_hamlet":
			legal.hamlet = hamlet_spots(i)
		elif phase == "setup_road":
			legal.road = road_spots(i)
		elif phase == "storm":
			legal.storm = storm_spots()
		elif phase == "build":
			for kind in ["road", "hamlet", "town"]:
				if can_afford(p, kind) and p.built[kind] < LIMIT[kind]:
					legal[kind] = road_spots(i) if kind == "road" else hamlet_spots(i) if kind == "hamlet" else town_spots(i)
			legal.festival = can_afford(p, "festival") and p.built.festival < LIMIT.festival
	var out_tiles: Array = []
	for t in tiles:
		var tv := {id = t.id, x = t.x, y = t.y}
		if t.res != "":
			tv.res = t.res
			tv.num = t.num
		out_tiles.append(tv)
	var out_verts: Array = []
	for v in verts:
		var vv := {id = v.id, x = v.x, y = v.y}
		if v.owner:
			vv.owner = v.owner
			vv.kind = v.kind
		out_verts.append(vv)
	var out_edges: Array = []
	for e in edges:
		var a := vert(e.a)
		var b := vert(e.b)
		var ev := {id = e.id, x1 = a.x, y1 = a.y, x2 = b.x, y2 = b.y}
		if e.owner:
			ev.owner = e.owner
		out_edges.append(ev)
	var out_players: Array = []
	for other in players:
		out_players.append({name = other.name, color = other.color, vp = vp(other), cards = cards(other)})
	var rates := {}
	for res in RESOURCES:
		rates[res] = rate(res)
	var out := {
		t = "view",
		you = {index = i, color = p.color, name = p.name, hand = p.hand, vp = vp(p), built = p.built, turn = turn == i},
		phase = phase, turn = turn, storm = storm, market = market, goal = GOAL,
		cost = COST, rates = rates, legal = legal, players = out_players,
		tiles = out_tiles, verts = out_verts, edges = out_edges, log = messages,
	}
	if not dice.is_empty():
		out.dice = dice
	if winner:
		out.winner = winner
	return out
