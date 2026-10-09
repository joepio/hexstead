extends SceneTree
## Headless rule checks: godot --headless --script tests/rules_test.gd

var failures := 0


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL: " + message)


func roster(n: int) -> Array:
	var out: Array = []
	for i in n:
		out.append({id = "p%d" % (i + 1), name = "P%d" % (i + 1), bot = true})
	return out


func _init() -> void:
	# Boards: 19 connected fields, one lake, no touching 6s and 8s.
	for seed_value in range(1, 61):
		var b := Rules.create(roster(3), seed_value)
		check(b.tiles.size() == 19, "19 tiles")
		var lakes := 0
		var nums := 0
		for t in b.tiles:
			if t.res == "":
				lakes += 1
				check(b.storm == t.id, "the storm starts on the lake")
			else:
				nums += 1
			check(t.verts.size() == 6, "every field has six corners")
		check(lakes == 1 and nums == 18, "one lake, 18 numbered fields")
		for t in b.tiles:
			for u in b.tiles:
				if t.id < u.id and Rules.pips(t.num) == 5 and Rules.pips(u.num) == 5:
					check(Rules.hex_distance(Vector2i(t.q, t.r), Vector2i(u.q, u.r)) > 1, "6s and 8s never touch (seed %d)" % seed_value)
		for e in b.edges:
			check(e.a != e.b, "edges join two corners")

	# Rules: turn order, refusals and the opening.
	var s := Rules.create(roster(3), 7)
	check(s.phase == "setup_hamlet" and s.turn == 1, "player 1 opens")
	check(s.act(2, {a = "hamlet", id = 1}) != "", "out of turn is refused")
	check(s.act(1, {a = "roll"}) != "", "no rolling during setup")
	var spot: int = s.hamlet_spots(1)[0]
	check(s.act(1, {a = "hamlet", id = spot}) == "", "first hamlet")
	check(s.act(1, {a = "road", id = -1}) != "", "bad road refused")
	for n in s.vert(spot).adj:
		check(not s.hamlet_spots(2).has(n), "neighbouring corners stay free")
	check(s.act(1, {a = "road", id = s.road_spots(1)[0]}) == "", "first road")
	check(s.turn == 2, "setup moves on")
	var order: Array = []
	while s.phase.begins_with("setup"):
		if s.phase == "setup_hamlet":
			order.append(s.turn)
		check(s.act(s.turn, Bot.choose(s, s.turn)) == "", "bot setup move")
	check(order == [2, 3, 3, 2, 1], "snake order, got %s" % [order])
	for p in s.players:
		check(p.built.hamlet == 2 and p.built.road == 2, "two hamlets and roads each")
		check(Rules.cards(p) >= 1, "second hamlet pays out")
	check(s.phase == "roll" and s.turn == 1, "player 1 rolls first")
	check(s.act(1, {a = "end"}) != "", "roll before ending")

	# Whole games: bots always finish, and every view encodes as JSON.
	var turns := 0
	for seed_value in range(1, 26):
		var g := Rules.create(roster(3 + seed_value % 2), seed_value * 31)
		var steps := 0
		while g.phase != "over" and steps < 20000:
			steps += 1
			var choice := Bot.choose(g, g.turn)
			var why := g.act(g.turn, choice)
			if why != "":
				check(false, "bot move refused: %s %s" % [why, choice])
				break
			if choice.a == "end":
				turns += 1
			for p in g.players:
				for res in Rules.RESOURCES:
					check(p.hand[res] >= 0, "no negative cards")
			if steps % 50 == 0:
				var text := JSON.stringify(g.view(g.turn))
				check(text.length() < 60000, "views stay small")
				check(JSON.parse_string(text) != null, "views are JSON")
		check(g.phase == "over", "game %d ended" % seed_value)
		check(Rules.vp(g.player(g.winner)) >= Rules.GOAL, "the winner reached the goal")
		for v in g.verts:
			if v.owner:
				for n in v.adj:
					check(not g.vert(n).owner, "hamlets keep their distance")
		check(g.act(g.turn, {a = "roll"}) != "", "nothing after the end")
	if failures:
		print("hexstead: %d checks failed" % failures)
		quit(1)
	else:
		print("hexstead: rules ok, 25 bot games finished, %d turns" % turns)
		quit(0)
