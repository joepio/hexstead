class_name Bot
extends RefCounted
## A simple, readable Hexstead player for AI seats and for players whose
## phone has gone away. One action per call, so the TV can show each step.


static func corner_value(s: Rules, vid: int) -> int:
	var value := 0
	var kinds := {}
	for tid in s.vert(vid).tiles:
		var t := s.tile(tid)
		if t.res != "":
			value += Rules.pips(t.num)
			if not kinds.has(t.res):
				kinds[t.res] = true
				value += 1
	return value


static func _best(list: Array, score: Callable) -> int:
	var top := 0
	var top_score := -INF
	for item in list:
		var value: float = score.call(item)
		if value > top_score:
			top = item
			top_score = value
	return top


## Roads that lead toward good open corners.
static func _road_value(s: Rules, eid: int) -> float:
	var e := s.edge(eid)
	var value := 0.0
	for end_id in [e.a, e.b]:
		var v := s.vert(end_id)
		if not v.owner:
			var free := true
			for other in v.adj:
				if s.vert(other).owner:
					free = false
			value = maxf(value, (3 if free else 0) + corner_value(s, end_id))
	return value + s.roll(0, 2)


static func _missing(p: Dictionary, kind: String) -> Array:
	var out: Array = []
	for res in Rules.COST[kind]:
		if p.hand[res] < Rules.COST[kind][res]:
			out.append(res)
	return out


## Swap a surplus for a card the next build needs.
static func _trade(s: Rules, i: int, kind: String) -> Dictionary:
	var p := s.player(i)
	var need := _missing(p, kind)
	if need.is_empty():
		return {}
	for res in Rules.RESOURCES:
		var keep: int = Rules.COST[kind].get(res, 0)
		if p.hand[res] - keep >= s.rate(res):
			return {a = "bank", give = res, get = need[0]}
	return {}


static func choose(s: Rules, i: int) -> Dictionary:
	var p := s.player(i)
	match s.phase:
		"setup_hamlet":
			return {a = "hamlet", id = _best(s.hamlet_spots(i), func(v): return corner_value(s, v) + s.roll(0, 1))}
		"setup_road":
			return {a = "road", id = _best(s.road_spots(i), func(e): return _road_value(s, e))}
		"roll":
			return {a = "roll"}
		"storm":
			return {a = "storm", id = _best(s.storm_spots(), func(tid):
				var t := s.tile(tid)
				var value := 0.0
				for vid in t.verts:
					var owner: int = s.vert(vid).owner
					if owner == i:
						value -= 10
					elif owner:
						value += Rules.pips(t.num) + Rules.cards(s.player(owner)) / 4.0
				return value)}
		"build":
			pass
		_:
			return {}
	var can := func(kind: String) -> bool:
		return Rules.can_afford(p, kind) and p.built[kind] < Rules.LIMIT[kind]
	var towns := s.town_spots(i)
	var hamlets := s.hamlet_spots(i)
	if can.call("town") and not towns.is_empty():
		return {a = "town", id = _best(towns, func(v): return corner_value(s, v))}
	if can.call("hamlet") and not hamlets.is_empty():
		return {a = "hamlet", id = _best(hamlets, func(v): return corner_value(s, v))}
	if can.call("festival") and Rules.vp(p) >= Rules.GOAL - 2:
		return {a = "festival"}
	var goal := "road"
	if not hamlets.is_empty() and p.built.hamlet < Rules.LIMIT.hamlet:
		goal = "hamlet"
	elif not towns.is_empty():
		goal = "town"
	var swap := _trade(s, i, goal)
	if not swap.is_empty():
		return swap
	if goal == "road" and can.call("road"):
		var roads := s.road_spots(i)
		if not roads.is_empty():
			return {a = "road", id = _best(roads, func(e): return _road_value(s, e))}
	if can.call("festival"):
		return {a = "festival"}
	return {a = "end"}
