# 一時停止(画面設計書 S7)。対戦の上に重ねる。後ろの対戦が暗く透ける。
# 「続ける」の後の 1 秒の待ちは対戦画面が持つ。「タイトルへ」は今の回を記録に残さない(main.go_title を呼ぶだけ)。
extends Control

const S := preload("res://core/strings.gd")
const Kit := preload("res://ui/kit.gd")
const Title := preload("res://ui/title.gd")

const DIM := 0.85  # 後ろを暗くする濃さ

var _main: Node
var _box: Control
var _t := 0.0


func setup(main: Node, _info: Dictionary) -> void:
	_main = main


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	modulate.a = 0.0
	_box = Title.box(self)
	_box.draw.connect(_draw_bars)
	Title.put(_box, S.PAUSED, 52, 900, Kit.C_TEXT, Rect2(20, 400, 680, 80))
	var resume := Kit.button("btn_resume", S.BTN_RESUME, 40, "primary")
	resume.pressed.connect(func() -> void: _main.resume())
	_box.add_child(Kit.place(resume, 80, 548, 560, 120))
	var settings := Kit.button("btn_pause_settings", S.BTN_SETTINGS, 32)
	settings.pressed.connect(func() -> void: _main.open_settings())
	_box.add_child(Kit.place(settings, 80, 698, 560, 96))
	var title := Kit.button("btn_pause_title", S.BTN_TITLE, 32, "quiet")
	title.pressed.connect(func() -> void: _main.go_title())
	_box.add_child(Kit.place(title, 80, 814, 560, 96))


func _input(event: InputEvent) -> void:
	# 入ったフレームのキーは受けない(一時停止にした Esc で、すぐ続けてしまわないように)
	if _main.screen_name == "pause" and _t > 0.0 and Title.fresh_key(event) == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_main.resume()


func _process(delta: float) -> void:
	_t += delta
	modulate.a = clampf(_t / 0.2, 0.0, 1.0)  # 暗い幕ごと、すっと出る
	Title.enter(_box, _t / 0.2)
	_box.modulate.a = 1.0


# 止まっている印(縦の棒 2 本)。ボタンの後ろは塗りつぶす(透けた対戦の字と、ボタンの字が重ならないように)。
func _draw_bars() -> void:
	for c: Node in _box.get_children():
		if c is Button:
			_box.draw_rect(c.get_rect().grow(-2.0), Kit.C_BG)
	for x: float in [330.0, 372.0]:
		_box.draw_rect(Rect2(x, 300, 18, 68), Kit.C_TEXT)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(Kit.C_BG, DIM))
