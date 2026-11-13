# タイトル(画面設計書 S1)。入口のボタン・記録・版と、頭を線で弾く小さな動きを出す。
# メニュー 5 画面で使う小道具(字を置く・収める・ボタンの見た目の入れ替え・敵の印・入る時の動き・キー)も、
# ここの static に置く(kit.gd は統合担当の物なので。ほかの 4 画面はここを preload して使う)。
extends Control

const B := preload("res://core/balance.gd")
const Attack := preload("res://core/attack.gd")
const Duel := preload("res://core/duel.gd")
const Rank := preload("res://core/rank.gd")
const S := preload("res://core/strings.gd")
const Kit := preload("res://ui/kit.gd")
const Fx := preload("res://ui/fx.gd")

const ENTER_SEC := 0.3  # 画面に入る時の動きの長さ
const DEMO_SCALE := 0.8  # 対戦の場を縮めて、題の上に置く(頭は画面の上の外から入ってくる)
const DEMO_LINE_Y := 322.0  # 弾く線を置く高さ(画面の px)
const DEMO_PERIOD := 192  # 攻撃 1 回の周期(tick)
const DEMO_ATTACK := {"kind": "white", "arm": "L", "windup": 48, "travel1": 96, "hold": 0, "travel2": 0}

var _main: Node
var _data_ok := true
var _load_failed := false
var _box: Control
var _t := 0.0
var _demo: Node2D
var _fx: Fx
var _acc := 0.0
var _tick := 0  # 周期の中の tick
var _round := 0


# ---- 5 画面で使う小道具 ----

# 中身を載せる入れ物(入る時の動きは、これだけを動かす。背景は画面がじかに塗る)。
static func box(screen: Control) -> Control:
	var c := Control.new()
	c.size = screen.size
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.modulate.a = 0.0
	screen.add_child(c)
	return c


# 入る時の動き。k は 0〜1。
static func enter(c: Control, k: float) -> void:
	k = clampf(k, 0.0, 1.0)
	c.modulate.a = k
	c.position.y = 16.0 * (1.0 - k) * (1.0 - k)


# 字を置く。枠からはみ出さない(はみ出す分は切る。入るかどうかはテストが測る)。
static func put(parent: Node, text: String, size: int, weight: int, color: Color, rect: Rect2, align: int = HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Kit.label(text, size, weight, color)
	l.horizontal_alignment = align as HorizontalAlignment
	l.clip_text = true
	Kit.place(l, rect.position.x, rect.position.y, rect.size.x, rect.size.y)
	parent.add_child(l)
	return l


static func text_width(l: Label) -> float:
	return l.get_theme_font("font").get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, l.get_theme_font_size("font_size")).x


# 枠に入るまで字を小さくする。
static func fit(l: Label, min_size: int = 14) -> void:
	var sz := l.get_theme_font_size("font_size")
	while sz > min_size and text_width(l) > l.size.x:
		sz -= 2
		l.add_theme_font_size_override("font_size", sz)


# ボタンの見た目だけを入れ替える(名前とノードはそのまま)。
static func restyle(b: Button, kind: String) -> void:
	var t := Kit.button("_", "", 1, kind)
	for n: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(n, t.get_theme_stylebox(n))
	for c: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color"]:
		b.add_theme_color_override(c, t.get_theme_color(c))
	t.free()


# 敵の形(対戦画面と同じ: 六角形・ひし形・逆三角)。
static func boss_shape(boss: int, c: Vector2, r: float) -> PackedVector2Array:
	return Kit.boss_shape(boss, c, r)


# 敵の印。slash が 0 より大きければ、斜めの斬り跡を その割合まで引く。
static func mark(ci: CanvasItem, boss: int, c: Vector2, r: float, color: Color, slash: float = 0.0) -> void:
	var pts := boss_shape(boss, c, r)
	var w := maxf(r * 0.04, 2.0)
	ci.draw_colored_polygon(pts, Color(color, 0.1 * color.a))
	Kit.outline(ci, pts, color, w)
	if slash > 0.0:
		var d := Vector2(0.86, -0.5) * r * 1.55
		var to := c - d + d * 2.0 * minf(slash, 1.0)
		ci.draw_line(c - d, to, Kit.C_BG, w * 4.0, true)
		ci.draw_line(c - d, to, Kit.C_WHITE, w, true)


# 押したばかりのキー(押しっぱなしのくり返しは入れない)。ほかは KEY_NONE。
static func fresh_key(event: InputEvent) -> int:
	if event is InputEventKey and event.pressed and not event.echo:
		return event.physical_keycode
	return KEY_NONE


static func is_go_key(event: InputEvent) -> bool:
	return fresh_key(event) in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]


# ---- タイトル ----

func setup(main: Node, info: Dictionary) -> void:
	_main = main
	_data_ok = info["data_ok"]
	_load_failed = info["load_failed"]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_box = box(self)
	_demo = Node2D.new()
	_demo.scale = Vector2(DEMO_SCALE, DEMO_SCALE)
	_demo.position = Vector2(360.0 * (1.0 - DEMO_SCALE), DEMO_LINE_Y - B.LINE_Y * DEMO_SCALE)
	_demo.modulate.a = 0.9
	_demo.draw.connect(_draw_demo)
	_box.add_child(_demo)
	_fx = Fx.new()
	_fx.shake_enabled = false
	_demo.add_child(_fx)

	put(_box, S.GAME_NAME, 72, 900, Kit.C_TEXT, Rect2(0, 362, 720, 104))
	put(_box, S.TAGLINE, 28, 500, Kit.C_TEXT, Rect2(0, 468, 720, 42))
	var y := 506.0
	if not _data_ok:
		put(_box, S.DATA_BROKEN, 20, 700, Kit.C_RED, Rect2(40, y, 640, 30))
		y += 28.0
	if _load_failed:
		put(_box, S.SAVE_BROKEN, 20, 500, Kit.C_SPARK, Rect2(40, y, 640, 30))

	var fixed := Kit.button("btn_fixed", S.BTN_FIXED, 40, "primary")
	fixed.disabled = not _data_ok
	fixed.pressed.connect(_start.bind(Duel.Mode.FIXED))
	_box.add_child(Kit.place(fixed, 80, 586, 560, 120))
	var best: Variant = _main.save.fixed_best()
	if best is Dictionary:
		put(_box, S.best_line(int(best["hits"]), Rank.seconds_text(int(best["ticks"]))), 22, 500, Kit.C_DIM, Rect2(80, 710, 560, 34))

	var today: Dictionary = _main.today()
	var daily := Kit.button("btn_daily", S.BTN_DAILY, 40)
	daily.disabled = not _data_ok
	daily.pressed.connect(_start.bind(Duel.Mode.DAILY))
	_box.add_child(Kit.place(daily, 80, 764, 560, 120))
	put(daily, str(today["date"]), 20, 500, Kit.C_DIM, Rect2(404, 0, 136, 120), HORIZONTAL_ALIGNMENT_RIGHT)
	put(_box, _daily_line(_main.save.daily(int(today["day"]))), 22, 500, Kit.C_DIM, Rect2(80, 888, 560, 34))

	put(_box, S.BTN_PRACTICE, 28, 700, Kit.C_TEXT, Rect2(80, 948, 96, 88), HORIZONTAL_ALIGNMENT_LEFT)
	var reached: int = _main.save.reached_boss()
	for n in range(1, B.BOSS_COUNT + 1):
		var b := Kit.button("btn_practice_%d" % n, "", 28)
		b.disabled = not _data_ok or n > reached
		b.pressed.connect(_practice.bind(n))
		_box.add_child(Kit.place(b, 184 + (n - 1) * 156, 948, 144, 88))
		var ink := Color(Kit.C_DIM, 0.45) if b.disabled else Kit.C_TEXT
		put(b, S.boss_n(n), 28, 700, ink, Rect2(58, 0, 78, 88))
		b.draw.connect(func() -> void: mark(b, n, Vector2(36, 44), 14.0, ink if b.disabled else Kit.boss_color(n)))

	var settings := Kit.button("btn_settings", S.BTN_SETTINGS, 30, "quiet")
	settings.pressed.connect(func() -> void: _main.open_settings())
	_box.add_child(Kit.place(settings, 220, 1078, 280, 88))
	put(_box, S.VERSION, 20, 500, Kit.C_DIM, Rect2(24, 1228, 200, 32), HORIZONTAL_ALIGNMENT_LEFT)


# 今日の記録の 1 行。daily は { day, first, best }。
static func _daily_line(daily: Dictionary) -> String:
	var first: Variant = daily["first"]
	if not (first is Dictionary):
		return S.NOT_PLAYED
	var best: Variant = daily["best"]
	var top: Dictionary = best if best is Dictionary else first
	return S.daily_line(int(first["hits"]), int(top["hits"]))


func _start(mode: int) -> void:
	if _data_ok:
		_main.start_run(mode)


func _practice(boss: int) -> void:
	if _data_ok and boss <= int(_main.save.reached_boss()):
		_main.start_practice(boss)


func _input(event: InputEvent) -> void:
	if _main.screen_name == "title" and is_go_key(event):
		get_viewport().set_input_as_handled()
		_start(Duel.Mode.FIXED)


func _process(delta: float) -> void:
	_t += delta
	enter(_box, _t / ENTER_SEC)
	if _main.screen_name != "title":
		return  # 設定が上に重なっている間は止める
	_acc += delta * B.TICK_HZ
	var n := int(_acc)
	_acc -= n
	for i in mini(n, B.MAX_STEPS_PER_FRAME):
		_tick += 1
		if _tick == Attack.duration(DEMO_ATTACK):
			_demo_hit()
		elif _tick >= DEMO_PERIOD:
			_tick = 0
			_round += 1
	_fx.advance(delta)
	_demo.queue_redraw()


func _demo_arm() -> String:
	return "L" if _round % 2 == 0 else "R"


# 頭が線に届いた。弾いた時と同じ火花を、音なしで出す。
func _demo_hit() -> void:
	var c: Vector2 = B.CONTACT[_demo_arm()]
	_fx.reduce_flash = _main.save.settings()["reduce_flash"]
	_fx.bounce_head(c, B.ORIGIN[_demo_arm()], "white")
	_fx.sparks(c, 12, 180.0, Kit.C_SPARK, 130.0)
	_fx.flash(c, 80.0, 120.0, Kit.C_WHITE, 0.3)


func _draw_demo() -> void:
	var a := DEMO_ATTACK.duplicate()
	a["arm"] = _demo_arm()
	var flying := _tick < Attack.duration(a)
	var pr := Attack.progress(a, 0, _tick)
	var lit := {}
	if flying:
		lit[a["arm"]] = 0.2 * float(pr["p"]) if pr["phase"] == "windup" else 0.35 + 0.65 * float(pr["along"])
	for arm: String in ["L", "R"]:  # 頭の通り道を、うすい破線で
		var from: Vector2 = B.ORIGIN[arm]
		var to: Vector2 = B.CONTACT[arm]
		for i in 14:
			_demo.draw_line(from.lerp(to, (i + 0.25) / 14.0), from.lerp(to, (i + 0.6) / 14.0), Color(Kit.C_LINE, 0.1), 2.0, true)
	Kit.draw_parry_line(_demo, B.LINE_X0, B.LINE_X1, B.LINE_Y, {"L": B.CONTACT["L"], "R": B.CONTACT["R"]}, lit)
	if not flying:
		return
	var pos := Attack.head_pos(a, 0, _tick)
	if pr["phase"] == "windup":
		var p: float = pr["p"]
		Kit.draw_head(_demo, pos, "white", 0.3 + 0.7 * p, 0.7 + 0.3 * p, minf(_tick / 8.0, 1.0))
	else:
		Kit.draw_head(_demo, pos, "white")


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Kit.C_BG)
