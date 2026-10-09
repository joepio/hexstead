extends Node
## Hexstead: build on a random island. The TV shows the board in 3D; each
## player's cards and choices live on their phone (the GameNight app opens the
## phone page by itself). AI seats, and players whose phone is away, are
## played by bots so the table never stalls.

## Seconds a player without a phone gets before the bot takes their turn.
const AWAY_GRACE := 15.0
## Seconds after a win before a new island rises.
const NEXT_ISLAND := 12.0
## Files the phone page needs, copied out of the game so GameNight can serve them.
const PHONE_FILES := ["index.html", "phone.js", "phone.css",
	"art/timber.png", "art/clay.png", "art/wool.png", "art/grain.png", "art/ore.png",
	"art/road.png", "art/hamlet.png", "art/town.png", "art/festival.png",
	"fonts/Alegreya.ttf", "fonts/AlegreyaSC-Bold.ttf"]
const BOT_NAMES := ["Bramble", "Cobble", "Thistle", "Juniper", "Marigold"]

var state: Rules
var roster: Array = []
var island: Island
var hud: Hud
var session := ""
var phase := "idle"
var phones := {}  # player id -> open phone screens
var bot_clock := 0.0
var away_clock := 0.0
var over_clock := 0.0
var sent_events := -1
var seed_value := 0
var bot_step := 0.9
## Screenshot mode: `-- --shot out.png [--moves N] [--seed N] [--yaw D]`.
var shot := ""
var shot_moves := 0
var shot_bolt := false
var _shown_event := {}


func _ready() -> void:
	island = Island.new()
	add_child(island)
	hud = Hud.new()
	add_child(hud)
	var args := OS.get_cmdline_user_args()
	var env_step := OS.get_environment("HEXSTEAD_BOT_STEP")
	if env_step != "":
		bot_step = float(env_step)
	for i in args.size():
		match args[i]:
			"--shot": shot = args[i + 1]
			"--moves": shot_moves = int(args[i + 1])
			"--seed": seed_value = int(args[i + 1])
			"--yaw": island.still = float(args[i + 1])
			"--phone": phones["p1"] = 1
			"--bolt": shot_bolt = true
	if GameNight.launched_by_daemon:
		GameNight.daemon_connected.connect(_declare_phone_page)
		GameNight.prepared.connect(_on_prepared)
		GameNight.started.connect(func(_s): phase = "running")
		GameNight.resumed.connect(func(_s): phase = "running")
		GameNight.paused.connect(func(_s): phase = "paused")
		GameNight.disposed.connect(_on_disposed)
		GameNight.companion_message.connect(_on_phone_message)
		GameNight.companion_presence.connect(_on_phone_presence)
	else:
		roster = _roster_from([], [])
		if shot != "":
			# A screenshot with a phone player shows the TV's hints.
			roster[0] = {id = "p1", name = "Joep", color = Rules.COLORS[0], bot = false}
		_new_game()
		phase = "running"
	if shot != "":
		_take_shot()


func _new_game() -> void:
	var s := seed_value if seed_value != 0 else int(Time.get_unix_time_from_system()) % 2147483646 + 1
	if seed_value != 0:
		seed_value += 1
	state = Rules.create(roster, s)
	bot_clock = 0.0
	away_clock = 0.0
	over_clock = 0.0
	island.build(state, s, shot == "")
	hud.bind(state, self)
	_broadcast()


func _roster_from(seats: Array, players: Array) -> Array:
	var out: Array = []
	for seat in seats:
		var o: Dictionary = seat.get("occupant", {})
		var kind := str(o.get("kind", "empty"))
		if kind == "empty":
			continue
		var entry := {id = str(o.get("player_id", "")), bot = kind == "ai", name = "Bot %d" % (int(seat.get("index", 0)) + 1)}
		for player in players:
			if str(player.get("id", "")) == entry.id:
				entry.name = player.get("name", entry.name)
				if player.has("color"):
					entry.color = player.color
		out.append(entry)
	# Hexstead needs company: fill up to three with bots (four when watching).
	var want := 3 if GameNight.launched_by_daemon else 4
	var k := 0
	while out.size() < want:
		out.append({bot = true, name = BOT_NAMES[k % BOT_NAMES.size()]})
		k += 1
	# Player colours must differ on the board even when profiles agree.
	var used := {}
	for p in out:
		if not p.has("color") or used.has(p.color):
			for c in Rules.COLORS:
				if not used.has(c):
					p.color = c
					break
		used[p.color] = true
	return out


# --- Phones ---------------------------------------------------------------

## GameNight serves the phone page from a real folder, so copy it out.
func _declare_phone_page() -> void:
	var root := "user://phone"
	DirAccess.make_dir_recursive_absolute(root + "/art")
	DirAccess.make_dir_recursive_absolute(root + "/fonts")
	for name in PHONE_FILES:
		var data := FileAccess.get_file_as_bytes("res://phone/" + name)
		if data.is_empty():
			continue
		var f := FileAccess.open(root + "/" + name, FileAccess.WRITE)
		if f:
			f.store_buffer(data)
	GameNight.declare_companion(ProjectSettings.globalize_path(root), "index.html")


func has_phone(p: Dictionary) -> bool:
	return p.id != "" and phones.get(p.id, 0) > 0


func _send_view(p: Dictionary, i: int) -> void:
	if has_phone(p) and GameNight.launched_by_daemon:
		GameNight.send_companion_message(state.view(i), p.id)


func _broadcast() -> void:
	if not state:
		return
	for p in state.players:
		_send_view(p, p.index)
	sent_events = state.events


func _on_phone_presence(player_id: String, connected: bool) -> void:
	phones[player_id] = maxi(0, phones.get(player_id, 0) + (1 if connected else -1))
	if connected and state:
		for p in state.players:
			if p.id == player_id:
				_send_view(p, p.index)


func _on_phone_message(player_id: String, data: Variant) -> void:
	if not state or typeof(data) != TYPE_DICTIONARY:
		return
	for p in state.players:
		if p.id == player_id:
			var why := act(p.index, data)
			if why != "":
				GameNight.send_companion_message({t = "error", text = why}, player_id)


# --- Session --------------------------------------------------------------

func _on_prepared(session_id: String, seats: Array, players: Array) -> void:
	session = session_id
	roster = _roster_from(seats, players)
	_new_game()
	phase = "ready"
	GameNight.notify_ready(session_id)


func _on_disposed(_s: String) -> void:
	session = ""
	phase = "idle"


func act(i: int, action: Dictionary) -> String:
	var before := state.phase
	var why := state.act(i, action)
	if why == "":
		away_clock = 0.0
		_show(state.last_event)
		_broadcast()
		if state.phase == "over" and before != "over" and session != "":
			GameNight.notify_finished(session)
	return why


## Animate what just happened on the TV.
func _show(event: Dictionary) -> void:
	if event.is_empty() or event == _shown_event:
		return
	_shown_event = event
	island.sync(state, shot == "")
	match event.kind:
		"roll":
			island.celebrate(event.got.keys())
			if event.sum == 7:
				island.lightning()
	hud.on_event(event)
	_update_targets()


## Show everyone where a phone player on turn may build.
func _update_targets() -> void:
	var p := state.player(state.turn)
	if p.bot or state.phase == "over":
		island.hide_targets()
		return
	var legal: Dictionary = state.view(state.turn).legal
	for kind in ["hamlet", "road", "storm"]:
		if legal.has(kind) and state.phase in ["setup_hamlet", "setup_road", "storm"]:
			island.show_targets(state, kind, legal[kind])
			return
	island.hide_targets()


func bot_turn(i: int) -> bool:
	var p := state.player(i)
	return p.bot or (not has_phone(p) and away_clock >= AWAY_GRACE)


func _process(delta: float) -> void:
	if not state or phase != "running" or shot != "":
		return
	if state.phase == "over":
		over_clock += delta
		if over_clock > NEXT_ISLAND:
			_new_game()
		return
	var p := state.player(state.turn)
	if not p.bot and not has_phone(p):
		away_clock += delta
	if bot_turn(state.turn):
		bot_clock += delta
		if bot_clock >= bot_step:
			bot_clock = 0.0
			var choice := Bot.choose(state, state.turn)
			if choice.is_empty() or act(state.turn, choice) != "":
				act(state.turn, {a = "end"})
	else:
		bot_clock = 0.0
	if state.events != sent_events:
		_broadcast()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if session != "" and phase == "running":
			GameNight.request_overlay()
		elif not GameNight.launched_by_daemon:
			get_tree().quit()


# --- Screenshots ----------------------------------------------------------

func _take_shot() -> void:
	# Play some moves instantly so the board has pieces on it.
	var moves := 0
	while moves < shot_moves and state.phase != "over":
		var i := state.turn
		var choice := Bot.choose(state, i)
		if choice.is_empty() or state.act(i, choice) != "":
			state.act(i, {a = "end"})
		moves += 1
		# Stop on the phone player's turn, so the hints show.
		if moves >= shot_moves and not state.player(state.turn).bot:
			break
	island.sync(state, false)
	_update_targets()
	hud.bind(state, self)
	hud.on_event(state.last_event)
	for _f in 90:
		await get_tree().process_frame
	if shot_bolt and island.storm:
		island.storm.get_node("Bolt").show()
		island.storm.get_node("Flash").light_energy = 4.0
		await get_tree().process_frame
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(shot)
	print("saved ", shot)
	get_tree().quit()
