class_name CardView
extends Control
## An illustrated card in the style of an old board game: parchment, a
## ribbon with its name, a diorama picture, cost badges and a caption.

const TITLE_FONT := preload("res://assets/fonts/AlegreyaSC-Bold.ttf")
const BODY_FONT := preload("res://assets/fonts/Alegreya.ttf")
const PAPER := Color("f4e8c8")
const PAPER_DARK := Color("e6d3a6")
const INK := Color("3a2a1c")
const FRAME := Color("2f4a3a")
const GOLD := Color("c9a24a")

var title := ""
var caption := ""
var art: Texture2D
## [[resource, count], ...] shown as badges under the picture.
var cost: Array = []
var accent := FRAME
var dim := false
var glow := 0.0:
	set(v):
		glow = v
		queue_redraw()


func _init(card_title := "", picture: Texture2D = null, card_cost: Array = [], card_caption := "") -> void:
	title = card_title
	art = picture
	cost = card_cost
	caption = card_caption
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var u := size.x / 200.0
	# Drop shadow, frame, paper.
	_round(Rect2(r.position + Vector2(4, 7) * u, r.size), 12 * u, Color(0, 0, 0, 0.28))
	if glow > 0.0:
		_round(r.grow(7 * u), 16 * u, Color(1.0, 0.88, 0.45, 0.65 * glow))
	_round(r, 12 * u, accent)
	_round(r.grow(-5 * u), 9 * u, PAPER)
	# A thin inner rule and corner flourishes.
	var inner := r.grow(-10 * u)
	_round_outline(inner, 6 * u, accent.lerp(PAPER, 0.35), 1.5 * u)
	for c in [inner.position, Vector2(inner.end.x, inner.position.y), inner.end, Vector2(inner.position.x, inner.end.y)]:
		draw_circle(c, 3 * u, accent.lerp(PAPER, 0.2))
	# Picture.
	var pic := Rect2(inner.position + Vector2(8, 34) * u, Vector2(inner.size.x - 16 * u, inner.size.x - 16 * u))
	_round(pic, 8 * u, PAPER_DARK.lerp(Color("cfe2e8"), 0.45))
	if art:
		var ar := art.get_size()
		var fit := minf(pic.size.x / ar.x, pic.size.y / ar.y) * 1.08
		var sz := ar * fit
		draw_texture_rect(art, Rect2(pic.get_center() - sz / 2.0 + Vector2(0, 2 * u), sz), false)
	# Ribbon with the title across the top.
	var rib := Rect2(r.position.x + 14 * u, inner.position.y + 4 * u, r.size.x - 28 * u, 28 * u)
	var notch := 8 * u
	var pts := PackedVector2Array([
		rib.position - Vector2(10 * u, -2 * u), rib.position + Vector2(rib.size.x + 10 * u, 2 * u),
		rib.position + Vector2(rib.size.x + 10 * u - notch, rib.size.y / 2.0 + 2 * u), rib.end + Vector2(10 * u, 2 * u),
		Vector2(rib.position.x - 10 * u, rib.end.y + 2 * u), rib.position + Vector2(-10 * u + notch, rib.size.y / 2.0 + 2 * u)])
	draw_colored_polygon(pts, accent.darkened(0.25))
	_round(rib, 4 * u, Color("fbf3dc"))
	_round_outline(rib, 4 * u, accent, 1.5 * u)
	var fs := int(19 * u)
	var tw := TITLE_FONT.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(TITLE_FONT, Vector2(rib.get_center().x - tw / 2.0, rib.position.y + rib.size.y * 0.5 + fs * 0.36), title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, INK)
	# Cost badges straddle the bottom of the picture.
	var y := pic.end.y + 2 * u
	if not cost.is_empty():
		var bw := 40 * u
		var gap := 3 * u
		var total := cost.size() * bw + (cost.size() - 1) * gap
		var x := r.get_center().x - total / 2.0
		for c in cost:
			var b := Rect2(x, y - 16 * u, bw, 28 * u)
			_round(b, 14 * u, Color("fbf3dc"))
			_round_outline(b, 14 * u, accent, 1.5 * u)
			var icon: Texture2D = Hud.art(c[0])
			if icon:
				draw_texture_rect(icon, Rect2(b.position + Vector2(1, 1) * u, Vector2(26, 26) * u), false)
			draw_string(TITLE_FONT, Vector2(b.position.x + 27 * u, b.position.y + 21 * u), str(c[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, int(17 * u), INK)
			x += bw + gap
		y += 16 * u
	if caption != "":
		var cs := int(14 * u)
		var lines := caption.split("\n")
		var ly := y + 16 * u
		for line in lines:
			var w := BODY_FONT.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, cs).x
			draw_string(BODY_FONT, Vector2(r.get_center().x - w / 2.0, ly), line, HORIZONTAL_ALIGNMENT_LEFT, -1, cs, INK.lerp(PAPER, 0.25))
			ly += cs * 1.15
	if dim:
		_round(r, 12 * u, Color(0.93, 0.89, 0.8, 0.5))


func _round(r: Rect2, radius: float, color: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(int(radius))
	sb.anti_aliasing = true
	draw_style_box(sb, r)


func _round_outline(r: Rect2, radius: float, color: Color, width: float) -> void:
	var sb := StyleBoxFlat.new()
	sb.draw_center = false
	sb.border_color = color
	sb.set_border_width_all(maxi(1, int(width)))
	sb.set_corner_radius_all(int(radius))
	sb.anti_aliasing = true
	draw_style_box(sb, r)
