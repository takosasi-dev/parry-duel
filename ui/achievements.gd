# 実績の一覧(v0.3.0)。取った物は名前を明るく、取った日を右に。まだの物は暗く、取り方だけを出す。
# タイトルの「実績」から開き、「戻る」・Esc でタイトルへ。
extends Control

const S := preload("res://core/strings.gd")
const Kit := preload("res://ui/kit.gd")
const Title := preload("res://ui/title.gd")

const LEFT := HORIZONTAL_ALIGNMENT_LEFT
const TOP := 196.0
const ROW := 68.0

var _main: Node
var _box: Control
var _t := 0.0


func setup(main: Node, _info: Dictionary) -> void:
	_main = main


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_box = Title.box(self)
	_box.draw.connect(_draw_rows)
	var got: Dictionary = _main.save.achievements()
	var total := S.ACHIEVEMENTS.size()
	var n := 0
	for a: Array in S.ACHIEVEMENTS:
		if got.has(a[0]):
			n += 1
	Title.put(_box, S.ACH_TITLE, 44, 900, Kit.C_TEXT, Rect2(60, 96, 400, 68), LEFT)
	Title.put(_box, S.ach_count(n, total), 30, 700, Kit.C_SPARK if n == total else Kit.C_DIM, Rect2(460, 96, 200, 68), HORIZONTAL_ALIGNMENT_RIGHT)
	for i in total:
		var a: Array = S.ACHIEVEMENTS[i]
		var y := TOP + i * ROW
		var have: bool = got.has(a[0])
		Title.fit(Title.put(_box, a[1], 24, 700, Kit.C_TEXT if have else Color(Kit.C_DIM, 0.8), Rect2(96, y + 4, 400, 32), LEFT))
		Title.fit(Title.put(_box, a[2], 18, 500, Kit.C_DIM if have else Color(Kit.C_DIM, 0.6), Rect2(96, y + 34, 440, 26), LEFT), 12)
		Title.put(_box, str(got[a[0]]) if have else S.ACH_LOCKED, 18, 500, Kit.C_DIM if have else Color(Kit.C_DIM, 0.5), Rect2(500, y + 6, 160, 30), HORIZONTAL_ALIGNMENT_RIGHT)
	var back := Kit.button("btn_back", S.BTN_BACK, 32, "quiet")
	back.pressed.connect(func() -> void: _main.go_title())
	_box.add_child(Kit.place(back, 220, 1172, 280, 88))


# 行の左の印(取った物は明るい菱形、まだの物は枠だけ)と、行の間の細い線。
func _draw_rows() -> void:
	var got: Dictionary = _main.save.achievements()
	for i in S.ACHIEVEMENTS.size():
		var y := TOP + i * ROW
		var c := Vector2(72, y + 32)
		var pts := Kit.ngon(c, 13.0, 4)
		if got.has(S.ACHIEVEMENTS[i][0]):
			_box.draw_colored_polygon(pts, Kit.C_SPARK)
		else:
			Kit.outline(_box, pts, Color(Kit.C_DIM, 0.5), 2.0)
		if i > 0:
			_box.draw_line(Vector2(60, y), Vector2(660, y), Color(Kit.C_DIM, 0.15), 1.0)


func _input(event: InputEvent) -> void:
	if _main.screen_name == "achievements" and Title.fresh_key(event) == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_main.go_title()


func _process(delta: float) -> void:
	_t += delta
	Title.enter(_box, _t / Title.ENTER_SEC)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Kit.C_BG)
