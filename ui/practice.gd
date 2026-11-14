# 型の練習の、型を選ぶ画面(v0.2.0)。敵をタブで選び、段階ごとの型(教える型は除く)を並べる。
# 型のボタンには、その型の攻撃(白い丸・赤い三角・ため)を小さく描く。押すと main.start_drill。
extends Control

const B := preload("res://core/balance.gd")
const PatternStore := preload("res://core/pattern_store.gd")
const S := preload("res://core/strings.gd")
const Kit := preload("res://ui/kit.gd")
const Title := preload("res://ui/title.gd")

const LEFT := HORIZONTAL_ALIGNMENT_LEFT
const ROW_Y := 484.0  # 段階 1 の行の上
const ROW_H := 120.0

var _main: Node
var _box: Control
var _rows: Control  # 段階の行(敵を替えたら作り直す)
var _boss := 1
var _tabs: Array = []
var _speed: Array = []  # [ふつう, ゆっくり]
var _t := 0.0


func setup(main: Node, _info: Dictionary) -> void:
	_main = main


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_box = Title.box(self)
	Title.put(_box, S.DRILL, 44, 900, Kit.C_TEXT, Rect2(60, 96, 600, 68), LEFT)
	Title.fit(Title.put(_box, S.DRILL_GUIDE, 22, 500, Kit.C_DIM, Rect2(60, 170, 600, 34), LEFT))

	Title.put(_box, S.SPEED, 26, 500, Kit.C_TEXT, Rect2(60, 226, 200, 88), LEFT)
	for i in 2:
		var b := Kit.button(["btn_drill_normal", "btn_drill_slow"][i], [S.SPEED_NORMAL, S.SPEED_SLOW][i], 30)
		b.pressed.connect(_set_slow.bind(i == 1))
		_box.add_child(Kit.place(b, 300 + i * 190, 226, 170, 88))
		_speed.append(b)

	var reached: int = _main.save.reached_boss()
	for n in range(1, B.BOSS_COUNT + 1):
		# 字はボタン自身の字にする(選んだタブは明るい地になるので、字の色もボタンの見た目と一緒に替わる)
		var t := Kit.button("btn_drill_boss_%d" % n, "   " + S.boss_n(n), 28)
		t.disabled = n > reached
		t.pressed.connect(_pick_boss.bind(n))
		_box.add_child(Kit.place(t, 60 + (n - 1) * 208, 348, 192, 88))
		t.draw.connect(func() -> void: Title.mark(t, n, Vector2(40, 44), 15.0, Color(Kit.C_DIM, 0.45) if t.disabled else Kit.boss_color(n)))
		_tabs.append(t)

	var back := Kit.button("btn_back", S.BTN_BACK, 32, "quiet")
	back.pressed.connect(func() -> void: _main.go_title())
	_box.add_child(Kit.place(back, 220, 1172, 280, 88))
	_sync_speed()
	_pick_boss(1)


func _set_slow(slow: bool) -> void:
	_main.drill_slow = slow
	_sync_speed()


func _sync_speed() -> void:
	for i in 2:
		Title.restyle(_speed[i], "on" if (i == 1) == bool(_main.drill_slow) else "normal")


func _pick_boss(n: int) -> void:
	_boss = n
	for i in _tabs.size():
		if not _tabs[i].disabled:
			Title.restyle(_tabs[i], "on" if i + 1 == n else "normal")
	if _rows != null:
		_rows.queue_free()
	_rows = Control.new()
	_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(_rows)
	var data: Dictionary = PatternStore.shared()
	if not data["ok"]:
		return
	var phases: Array = data["bosses"][n - 1]["phases"]
	for pi in phases.size():
		var y := ROW_Y + pi * ROW_H
		Title.put(_rows, S.phase_n(pi + 1), 26, 500, Kit.C_TEXT, Rect2(60, y, 140, 88), LEFT)
		var j := 0
		for p: Dictionary in phases[pi]["patterns"]:
			if p["teach"]:
				continue
			var b := Kit.button("btn_drill_" + str(p["id"]), "", 30)
			b.pressed.connect(func() -> void: _main.start_drill(p["id"]))
			_rows.add_child(Kit.place(b, 200 + j * 118, y, 106, 88))
			b.draw.connect(_draw_pattern.bind(b, p))
			j += 1
	if _main.pad:
		_main._apply_focus.call_deferred()


# 型のボタンの中身: 上に文字(A〜D)、下に攻撃を出る順に(白い丸・赤い三角、ための攻撃は輪つき)。
func _draw_pattern(b: Button, p: Dictionary) -> void:
	var letter := str(p["id"]).get_slice("_", str(p["id"]).get_slice_count("_") - 1).to_upper()
	Kit.text(b, Vector2(53, 42), letter, 30, Kit.C_TEXT, 700, HORIZONTAL_ALIGNMENT_CENTER, 106.0)
	var attacks: Array = p["attacks"]
	var n := attacks.size()
	for i in n:
		var a: Dictionary = attacks[i]
		var c := Vector2(53.0 + (i - (n - 1) / 2.0) * 20.0, 66.0)
		if a["kind"] == "red":
			b.draw_colored_polygon(Kit.ngon(c, 8.0, 3, PI / 2.0), Kit.C_RED)
		else:
			b.draw_circle(c, 6.0, Kit.C_WHITE, true, -1.0, true)
		if int(a["hold"]) > 0:
			b.draw_arc(c, 9.5, 0.0, TAU, 16, Color(Kit.C_WHITE, 0.8), 1.5, true)


func _input(event: InputEvent) -> void:
	if _main.screen_name == "practice" and Title.fresh_key(event) == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_main.go_title()


func _process(delta: float) -> void:
	_t += delta
	Title.enter(_box, _t / Title.ENTER_SEC)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Kit.C_BG)
