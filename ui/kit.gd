# 画面の共通部品(色・太さ違いの字体・ラベル・ボタン・形を描く道具)。画面設計書 §11 の色はここに置く。
# 文言は持たない。各画面は文言を core/strings.gd から渡す。
extends RefCounted

const FONT_PATH := "res://assets/fonts/NotoSansJP-Subset.ttf"

const C_BG := Color("0E1116")
const C_BG_HI := Color("161B24")
const C_TEXT := Color("E6E6E6")
const C_DIM := Color("8B95A5")
const C_LINE := Color("E6E6E6")
const C_WHITE := Color("FFFFFF")
const C_RED := Color("FF4D4D")
const C_PLAYER := Color("7CE38B")
const C_PLAYER_LOCK := Color("3D5A45")
const C_SPARK := Color("FFE066")
const C_BOSS := [Color("8FA3B8"), Color("C9A66B"), Color("D46A6A")]

const HEAD_R_WHITE := 22.0
const HEAD_R_RED := 24.0
const RING_R := 26.0

static var _fonts := {}


static func font(weight: int = 400) -> Font:
	if not _fonts.has(weight):
		var fv := FontVariation.new()
		fv.base_font = load(FONT_PATH)
		fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
		_fonts[weight] = fv
	return _fonts[weight]


static func boss_color(boss: int) -> Color:
	return C_BOSS[clampi(boss - 1, 0, C_BOSS.size() - 1)]


static func label(text: String, size: int, weight: int = 400, color: Color = C_TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", font(weight))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func _box(bg: Color, border: Color, width: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(width)
	s.set_corner_radius_all(6)
	s.content_margin_left = 24
	s.content_margin_right = 24
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	s.anti_aliasing = true
	return s


# ボタン。node_name はデバッグ用の窓口と自動の確認が押す時の目印なので、必ず付ける。
# kind: "primary" = 主の入口、"normal" = ふつう、"quiet" = 目立たせない、"on" = 選ばれている切り替え
static func button(node_name: String, text: String, size: int = 36, kind: String = "normal") -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", font(700))
	b.add_theme_font_size_override("font_size", size)
	var edge := C_TEXT
	var fill := Color(1, 1, 1, 0.05)
	var ink := C_TEXT
	match kind:
		"primary":
			fill = Color(C_PLAYER, 0.16)
			edge = C_PLAYER
		"quiet":
			edge = Color(C_DIM, 0.7)
			ink = C_DIM
			fill = Color(1, 1, 1, 0.02)
		"on":
			fill = C_TEXT
			ink = C_BG
	b.add_theme_stylebox_override("normal", _box(fill, Color(edge, 0.85), 2))
	b.add_theme_stylebox_override("hover", _box(fill.lightened(0.08) if kind != "on" else fill, edge, 3))
	b.add_theme_stylebox_override("pressed", _box(Color(edge, 0.35) if kind != "on" else fill, edge, 3))
	b.add_theme_stylebox_override("disabled", _box(Color(1, 1, 1, 0.015), Color(C_DIM, 0.25), 2))
	b.add_theme_stylebox_override("focus", _box(Color(0, 0, 0, 0), C_SPARK, 4))
	for c: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, ink)
	b.add_theme_color_override("font_disabled_color", Color(C_DIM, 0.45))
	b.pressed.connect(func() -> void: Sfx.play("soft"))
	return b


# 置く場所と大きさを決める(論理の画面 720×1280 の中の px)。
static func place(c: Control, x: float, y: float, w: float, h: float) -> Control:
	c.position = Vector2(x, y)
	c.size = Vector2(w, h)
	if c is Button:
		c.custom_minimum_size = Vector2(w, h)
	return c


# 正多角形の頂点。rot は最初の頂点の向き(ラジアン。0 = 右、−π/2 = 上)。
static func ngon(center: Vector2, radius: float, sides: int, rot: float = -PI / 2.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in sides:
		pts.append(center + Vector2.from_angle(rot + TAU * i / sides) * radius)
	return pts


# 敵の形(1 = 六角形、2 = ひし形、3 = 逆三角)。r は六角形の半径で、ほかの 2 つは少し大きい(画面設計書 §11 の 110・120・120)。
static func boss_shape(boss: int, center: Vector2, r: float) -> PackedVector2Array:
	match boss:
		1:
			return ngon(center, r, 6)
		2:
			return ngon(center, r * 12.0 / 11.0, 4)
	return ngon(center, r * 12.0 / 11.0, 3, PI / 2.0)


# 閉じた線。
static func outline(ci: CanvasItem, pts: PackedVector2Array, color: Color, width: float) -> void:
	var loop := pts.duplicate()
	loop.append(pts[0])
	ci.draw_polyline(loop, color, width, true)


# 中心から外へ薄くなる光(頂点色の扇)。シェーダーは使わない。
static func glow(ci: CanvasItem, center: Vector2, radius: float, color: Color, alpha: float, sides: int = 28) -> void:
	if alpha <= 0.003:
		return
	var inner := Color(color, alpha)
	var outer := Color(color, 0.0)
	var ring := ngon(center, radius, sides)
	for i in sides:
		ci.draw_polygon(PackedVector2Array([center, ring[i], ring[(i + 1) % sides]]), PackedColorArray([inner, outer, outer]))


# 攻撃の頭。白 = 丸、赤 = 先が下向きの三角(色を見なくても形で分かる。INV-11)。
# bright は 0〜1(予兆で明るくなる)、scale は大きさの倍率。
static func draw_head(ci: CanvasItem, pos: Vector2, kind: String, bright: float = 1.0, scale: float = 1.0, alpha: float = 1.0) -> void:
	if kind == "red":
		var r := HEAD_R_RED * scale
		glow(ci, pos, r * 2.6, C_RED, 0.30 * bright * alpha, 20)
		var tri := ngon(pos, r * 1.15, 3, PI / 2.0)
		ci.draw_colored_polygon(tri, Color(C_RED.darkened(0.55 * (1.0 - bright)), alpha))
		outline(ci, tri, Color(C_BG, alpha), 3.0)
		outline(ci, ngon(pos, r * 1.15 + 5.0, 3, PI / 2.0), Color(C_RED, 0.9 * alpha * bright), 2.0)
		var inner := ngon(pos + Vector2(0, -1), r * 0.42, 3, PI / 2.0)
		ci.draw_colored_polygon(inner, Color(C_BG, 0.85 * alpha))
	else:
		var r2 := HEAD_R_WHITE * scale
		glow(ci, pos, r2 * 2.8, C_WHITE, 0.26 * bright * alpha, 24)
		ci.draw_circle(pos, r2, Color(C_WHITE.darkened(0.5 * (1.0 - bright)), alpha), true, -1.0, true)
		ci.draw_arc(pos, r2 + 5.0, 0.0, TAU, 40, Color(C_WHITE, 0.55 * alpha * bright), 2.0, true)


# 弾く線と、当たり点の輪 3 個。lit は { "L": 0〜1, ... }(頭が向かっている腕の輪を明るくする)。
static func draw_parry_line(ci: CanvasItem, x0: float, x1: float, y: float, contacts: Dictionary, lit: Dictionary) -> void:
	for i in 5:
		var w := 26.0 - i * 5.0
		ci.draw_line(Vector2(x0, y), Vector2(x1, y), Color(C_LINE, 0.022), w + 4.0, true)
	ci.draw_line(Vector2(x0, y), Vector2(x1, y), C_LINE, 4.0, true)
	ci.draw_circle(Vector2(x0, y), 2.0, C_LINE, true, -1.0, true)
	ci.draw_circle(Vector2(x1, y), 2.0, C_LINE, true, -1.0, true)
	for arm: String in contacts:
		var c: Vector2 = contacts[arm]
		var on: float = lit.get(arm, 0.0)
		ci.draw_circle(c, RING_R, C_BG, true, -1.0, true)
		if on > 0.0:
			glow(ci, c, RING_R * 2.4, C_WHITE, 0.22 * on, 24)
		ci.draw_arc(c, RING_R, 0.0, TAU, 44, C_LINE.lerp(C_WHITE, on).darkened(0.45 * (1.0 - on)), 3.0 + on, true)
		ci.draw_circle(c, 4.0 + 2.0 * on, C_LINE.darkened(0.3 * (1.0 - on)), true, -1.0, true)


# 文字を描く(中央ぞろえ)。pos は文字の下の線の中央。
static func text(ci: CanvasItem, pos: Vector2, s: String, size: int, color: Color, weight: int = 700, align: int = HORIZONTAL_ALIGNMENT_CENTER, width: float = 720.0) -> void:
	var x := pos.x - width / 2.0
	if align == HORIZONTAL_ALIGNMENT_LEFT:
		x = pos.x
	elif align == HORIZONTAL_ALIGNMENT_RIGHT:
		x = pos.x - width
	ci.draw_string(font(weight), Vector2(x, pos.y), s, align, width, size, color)
