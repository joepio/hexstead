class_name Hud
extends CanvasLayer
## Everything on the TV that isn't the island: the settlers' scoreboard, the
## market card, whose turn it is with the dice, the build cards, the log, and
## cards flying from fields to whoever they pay.

const TITLE_FONT := preload("res://assets/fonts/AlegreyaSC-Bold.ttf")
const BODY_FONT := preload("res://assets/fonts/Alegreya.ttf")
const INK := Color("3a2a1c")
const PAPER := Color("f4e8c8")
const FRAME := Color("2f4a3a")
const BUILDS := [
	["road", "Road", "Joins your hamlets"],
	["hamlet", "Hamlet", "1 point"],
	["town", "Town", "Upgrades a hamlet\n2 points"],
	["festival", "Festival", "1 point, twice a game"],
]
const VERB := {
	setup_hamlet = "founds a hamlet", setup_road = "lays a road", roll = "rolls the dice",
	storm = "moves the storm", build = "builds and trades",
}

static var _art := {}

var state: Rules
var game: Node
var root: Control
var board: VBoxContainer
var rows: Array = []
var round_label: Label
var market_card: CardView
var build_cards := {}
var turn_name: Label
var turn_hint: Label
var turn_dot: Panel
var dice: DiceView
## The big throw in the middle of the TV.
var dice3d: Dice
var _pending_roll := {}

## The dice have landed and the total is up: time to show what it brings.
signal roll_landed(event: Dictionary)
var log_box: VBoxContainer
var shout: Label
var _shout_tween: Tween


static func art(name: String) -> Texture2D:
	if not _art.has(name):
		# The phone page needs these as plain files, so they aren't imported;
		# read the PNG ourselves.
		var img := Image.load_from_file("res://phone/art/%s.png" % name)
		if img:
			img.generate_mipmaps()
		_art[name] = ImageTexture.create_from_image(img) if img else null
	return _art[name]


func _ready() -> void:
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var theme := Theme.new()
	theme.default_font = BODY_FONT
	theme.default_font_size = 22
	theme.set_color("font_color", "Label", INK)
	root.theme = theme
	_build_board()
	_build_market()
	_build_cards()
	_build_turn()
	_build_log()
	dice3d = Dice.new()
	dice3d.set_anchors_preset(Control.PRESET_CENTER)
	dice3d.offset_left = -640
	dice3d.offset_right = 640
	dice3d.offset_top = -430
	dice3d.offset_bottom = 330
	root.add_child(dice3d)
	dice3d.label.add_theme_font_override("font", TITLE_FONT)
	dice3d.shown.connect(_on_dice_shown)
	shout = _label("", TITLE_FONT, 64, Color("fff6dc"))
	shout.add_theme_constant_override("outline_size", 14)
	shout.add_theme_color_override("font_outline_color", Color(0.18, 0.12, 0.06, 0.85))
	shout.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shout.set_anchors_preset(Control.PRESET_CENTER_TOP)
	shout.offset_left = -600
	shout.offset_right = 600
	shout.offset_top = 40
	shout.offset_bottom = 130
	shout.modulate.a = 0.0
	root.add_child(shout)


static func paper_box(radius := 14, border := FRAME) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PAPER
	sb.border_color = border
	sb.set_border_width_all(4)
	sb.set_corner_radius_all(radius)
	sb.shadow_color = Color(0, 0, 0, 0.3)
	sb.shadow_size = 10
	sb.shadow_offset = Vector2(3, 6)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 14
	sb.content_margin_bottom = 16
	sb.anti_aliasing = true
	return sb


func _label(text: String, font: Font, font_size: int, color := INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _build_board() -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", paper_box())
	panel.position = Vector2(32, 28)
	panel.custom_minimum_size = Vector2(430, 0)
	root.add_child(panel)
	board = VBoxContainer.new()
	board.add_theme_constant_override("separation", 6)
	panel.add_child(board)
	var head := HBoxContainer.new()
	board.add_child(head)
	var title := _label("Settlers", TITLE_FONT, 34)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	round_label = _label("Round 1", BODY_FONT, 22, INK.lerp(PAPER, 0.35))
	round_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(round_label)
	var rule := ColorRect.new()
	rule.color = FRAME.lerp(PAPER, 0.5)
	rule.custom_minimum_size = Vector2(0, 2)
	board.add_child(rule)


func _build_market() -> void:
	market_card = CardView.new("Market Day")
	market_card.accent = Color("7a4a2a")
	market_card.size = Vector2(210, 300)
	market_card.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	market_card.position = Vector2(-210 - 36, 28)
	root.add_child(market_card)


## A price list on the wall for everyone watching: what each build costs
## and what it's worth. Players buy on their phones.
func _build_cards() -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", paper_box())
	panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.offset_left = -36 - 380
	panel.offset_right = -36
	panel.offset_top = -24 - 300
	panel.offset_bottom = -24
	panel.custom_minimum_size = Vector2(380, 0)
	root.add_child(panel)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 2)
	panel.add_child(list)
	list.add_child(_label("Building costs", TITLE_FONT, 26))
	for b in BUILDS:
		var row := PanelContainer.new()
		var hi := StyleBoxFlat.new()
		hi.bg_color = Color(1.0, 0.85, 0.4, 0.0)
		hi.set_corner_radius_all(8)
		hi.content_margin_left = 4
		hi.content_margin_right = 4
		row.add_theme_stylebox_override("panel", hi)
		list.add_child(row)
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		row.add_child(line)
		var pic := TextureRect.new()
		pic.texture = art(b[0])
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.custom_minimum_size = Vector2(58, 58)
		line.add_child(pic)
		var name := VBoxContainer.new()
		name.add_theme_constant_override("separation", -6)
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(name)
		name.add_child(_label(b[1], TITLE_FONT, 22))
		name.add_child(_label(b[2].replace("\n", ", "), BODY_FONT, 16, INK.lerp(PAPER, 0.4)))
		var cost := HBoxContainer.new()
		cost.add_theme_constant_override("separation", 0)
		cost.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(cost)
		for res in Rules.RESOURCES:
			for k in Rules.COST[b[0]].get(res, 0):
				var icon := TextureRect.new()
				icon.texture = art(res)
				icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				icon.custom_minimum_size = Vector2(26, 30)
				cost.add_child(icon)
		build_cards[b[0]] = hi


func _build_turn() -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", paper_box(18))
	panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	panel.position = Vector2(494, -150)
	panel.custom_minimum_size = Vector2(640, 118)
	root.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	panel.add_child(row)
	turn_dot = Panel.new()
	turn_dot.custom_minimum_size = Vector2(40, 40)
	turn_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(turn_dot)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", -4)
	row.add_child(text)
	turn_name = _label("", TITLE_FONT, 36)
	text.add_child(turn_name)
	turn_hint = _label("", BODY_FONT, 22, INK.lerp(PAPER, 0.2))
	turn_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	turn_hint.custom_minimum_size = Vector2(470, 0)
	text.add_child(turn_hint)
	dice = DiceView.new()
	dice.custom_minimum_size = Vector2(150, 74)
	dice.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(dice)


func _build_log() -> void:
	var panel := PanelContainer.new()
	var sb := paper_box(12)
	sb.bg_color = Color(PAPER, 0.92)
	panel.add_theme_stylebox_override("panel", sb)
	panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	panel.position = Vector2(32, -230)
	panel.custom_minimum_size = Vector2(430, 0)
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(panel)
	log_box = VBoxContainer.new()
	log_box.add_theme_constant_override("separation", 2)
	panel.add_child(log_box)


func _player_row(p: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.custom_minimum_size = Vector2(0, 50)
	var arrow := _label("▸", TITLE_FONT, 30, Color("b0482a"))
	arrow.custom_minimum_size = Vector2(16, 0)
	arrow.name = "Arrow"
	row.add_child(arrow)
	var crest := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(p.color)
	sb.border_color = Color(p.color).darkened(0.45)
	sb.set_border_width_all(3)
	sb.corner_radius_bottom_left = 16
	sb.corner_radius_bottom_right = 16
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	crest.add_theme_stylebox_override("panel", sb)
	crest.custom_minimum_size = Vector2(30, 36)
	crest.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(crest)
	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.add_theme_constant_override("separation", -8)
	row.add_child(names)
	names.add_child(_label(p.name, TITLE_FONT, 26))
	var status := _label("", BODY_FONT, 17, INK.lerp(PAPER, 0.4))
	status.name = "Status"
	names.add_child(status)
	var cards := _label("", BODY_FONT, 22, INK.lerp(PAPER, 0.25))
	cards.name = "Cards"
	cards.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(cards)
	var vp := _label("", TITLE_FONT, 36)
	vp.name = "Points"
	vp.custom_minimum_size = Vector2(46, 0)
	vp.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(vp)
	return row


func bind(s: Rules, g: Node) -> void:
	state = s
	game = g
	for r in rows:
		r.queue_free()
	rows.clear()
	for p in s.players:
		var row := _player_row(p)
		board.add_child(row)
		rows.append(row)
	refresh()


func on_event(event: Dictionary) -> void:
	if not state:
		return
	refresh()
	if event.is_empty():
		return
	match event.kind:
		"roll":
			_pending_roll = event
			dice3d.roll(event.dice)
		"hamlet", "town", "road", "festival":
			_flash(event.kind)
			if event.kind == "festival":
				say("%s throws a festival!" % state.player(event.player).name)
			for g in event.get("gift", []):
				_fly(g[1], event.id, event.player, 1)
		"storm":
			if event.res != "":
				say("%s steals from %s" % [state.player(event.player).name, state.player(event.victim).name])
		"win":
			say("%s wins!" % state.player(event.player).name, 6.0)
		"end":
			if state.turn == 1:
				say("Market day: %s at 2 for 1" % Rules.LABEL[state.market])


func _on_dice_shown(_total: int) -> void:
	var event := _pending_roll
	if event.is_empty():
		return
	dice.roll(event.dice)
	dice.tumble = 0.0
	if event.sum == 7:
		say("A storm is coming!")
	roll_landed.emit(event)
	# Cards follow the harvest from each hamlet to its owner's row.
	for tid in event.got:
		for gain in event.got[tid]:
			_fly(state.tile(tid).res, gain[2], gain[0], gain[1], Island.HARVEST_FLIGHT + 0.5)


## Whether the TV is still showing a throw; bots wait for it.
func busy() -> bool:
	return dice3d.busy()


func refresh() -> void:
	if not state:
		return
	round_label.text = "Round %d" % state.round_no
	for i in rows.size():
		var p: Dictionary = state.players[i]
		var row: Control = rows[i]
		var on_turn: bool = state.turn == p.index and state.phase != "over"
		row.get_node("Arrow").modulate.a = 1.0 if on_turn else 0.0
		row.get_node("Points").text = str(Rules.vp(p))
		row.get_node("Cards").text = "%d cards" % Rules.cards(p)
		var status := "bot"
		if not p.bot:
			status = "on phone" if game.has_phone(p) else "no phone yet"
		if state.winner == p.index:
			status = "wins!"
		if state.phase == "over" and not p.bot and game.wins(p) > 0:
			status += "  %d won" % game.wins(p)
		row.find_child("Status", true, false).text = status
	market_card.title = "Market Day"
	market_card.art = art(state.market)
	market_card.caption = "The bank takes\n%s at 2 for 1" % Rules.LABEL[state.market]
	market_card.queue_redraw()
	var p := state.player(state.turn)
	var me := state.player(state.turn)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(p.color)
	sb.border_color = Color(p.color).darkened(0.45)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(20)
	turn_dot.add_theme_stylebox_override("panel", sb)
	if state.phase == "over":
		turn_name.text = "%s wins!" % state.player(state.winner).name
	else:
		turn_name.text = "%s %s" % [me.name, VERB.get(state.phase, "")]
	if state.dice.is_empty() and state.phase != "build":
		dice.clear()
	var lines: Array = state.messages.slice(0, 4)
	for c in log_box.get_children():
		c.queue_free()
	for k in lines.size():
		var l := _label(lines[k], BODY_FONT, 21, INK.lerp(PAPER, 0.15 + k * 0.15))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(390, 0)
		log_box.add_child(l)


## The hint line under the turn: what's asked, or who is waiting for a phone.
func _process(_delta: float) -> void:
	if not state or not game:
		return
	if state.phase == "over":
		turn_hint.text = "A new island rises in %d…" % maxi(0, ceili(game.NEXT_ISLAND - game.over_clock))
		return
	var p := state.player(state.turn)
	if p.bot:
		turn_hint.text = "A bot plays this seat"
	elif game.has_phone(p):
		turn_hint.text = "Choosing on their phone"
	elif game.away_clock < game.AWAY_GRACE:
		turn_hint.text = "Open the GameNight app on your phone (%d)" % ceili(game.AWAY_GRACE - game.away_clock)
	else:
		turn_hint.text = "Phone away, a bot plays this turn"


func say(text: String, hold := 2.2) -> void:
	shout.text = text
	if _shout_tween:
		_shout_tween.kill()
	shout.scale = Vector2(0.8, 0.8)
	shout.pivot_offset = shout.size / 2.0
	_shout_tween = create_tween()
	_shout_tween.set_parallel()
	_shout_tween.tween_property(shout, "modulate:a", 1.0, 0.25)
	_shout_tween.tween_property(shout, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_shout_tween.chain().tween_interval(hold)
	_shout_tween.chain().tween_property(shout, "modulate:a", 0.0, 0.5)


## The price list row lights up when someone buys what's on it.
func _flash(kind: String) -> void:
	var hi: StyleBoxFlat = build_cards.get(kind)
	if not hi:
		return
	var tw := create_tween()
	tw.tween_property(hi, "bg_color:a", 0.75, 0.15)
	tw.tween_interval(0.8)
	tw.tween_property(hi, "bg_color:a", 0.0, 0.8)


## Little resource cards fly from where they were made to whoever gets them.
func _fly(res: String, vert_id: int, player_index: int, count: int, delay := 0.35) -> void:
	var island: Island = game.island
	if not island or not island.camera:
		return
	var from := island.camera.unproject_position(island.vert_pos(state, vert_id) + Vector3(0, 0.6, 0))
	var row: Control = rows[player_index - 1]
	var to := row.get_global_rect().get_center() + Vector2(110, 0)
	for k in count:
		var card := CardView.new(Rules.LABEL[res], art(res))
		card.size = Vector2(76, 106)
		card.pivot_offset = card.size / 2.0
		card.position = from - card.size / 2.0
		card.scale = Vector2(0.3, 0.3)
		root.add_child(card)
		var tw := create_tween()
		card.modulate.a = 0.0
		tw.tween_interval(delay + k * 0.15)
		tw.tween_property(card, "modulate:a", 1.0, 0.01)
		tw.tween_property(card, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(card, "position", from - card.size / 2.0 + Vector2(0, -50), 0.25)
		tw.tween_property(card, "position", to - card.size / 2.0, 0.7).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		tw.parallel().tween_property(card, "scale", Vector2(0.45, 0.45), 0.7)
		tw.parallel().tween_property(card, "rotation", randf_range(-0.4, 0.4), 0.7)
		tw.tween_property(card, "modulate:a", 0.0, 0.15)
		tw.tween_callback(card.queue_free)


## Two ivory dice that tumble before they land.
class DiceView:
	extends Control
	var faces: Array = []
	var tumble := 0.0

	func roll(values: Array) -> void:
		faces = values.duplicate()
		tumble = 0.7
		queue_redraw()

	func clear() -> void:
		faces = []
		queue_redraw()

	func _process(delta: float) -> void:
		if tumble > 0.0:
			tumble -= delta
			queue_redraw()

	func _draw() -> void:
		if faces.is_empty():
			return
		for k in 2:
			var value: int = faces[k] if tumble <= 0.0 else randi_range(1, 6)
			var c := Vector2(37 + k * 76, 37)
			var ang := 0.0 if tumble <= 0.0 else randf_range(-0.5, 0.5)
			draw_set_transform(c, ang + (k - 0.5) * 0.12, Vector2.ONE)
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color("fbf6ea")
			sb.border_color = Color("6b4a2f")
			sb.set_border_width_all(3)
			sb.set_corner_radius_all(12)
			sb.shadow_color = Color(0, 0, 0, 0.3)
			sb.shadow_size = 6
			sb.shadow_offset = Vector2(2, 4)
			sb.anti_aliasing = true
			draw_style_box(sb, Rect2(-32, -32, 64, 64))
			var red := value == 1
			for p in _pips(value):
				draw_circle(p * 16.0, 6.5 if not red else 9.0, Color("b3261b") if red else Color("2b2018"))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	func _pips(v: int) -> Array:
		match v:
			1: return [Vector2.ZERO]
			2: return [Vector2(-1, -1), Vector2(1, 1)]
			3: return [Vector2(-1, -1), Vector2.ZERO, Vector2(1, 1)]
			4: return [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]
			5: return [Vector2(-1, -1), Vector2(1, -1), Vector2.ZERO, Vector2(-1, 1), Vector2(1, 1)]
		return [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 0), Vector2(1, 0), Vector2(-1, 1), Vector2(1, 1)]
