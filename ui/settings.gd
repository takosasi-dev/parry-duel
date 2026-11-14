# 設定(画面設計書 S5)。音量・画面の揺れ・点滅を弱める・押したずれ・やさしい・判定のずれ。変えた時点で保存する。
# タイトルからでも一時停止からでも開く。「戻る」は main が来た画面へ戻す。
extends Control

const B := preload("res://core/balance.gd")
const Rank := preload("res://core/rank.gd")
const S := preload("res://core/strings.gd")
const Kit := preload("res://ui/kit.gd")
const Title := preload("res://ui/title.gd")

const LEFT := HORIZONTAL_ALIGNMENT_LEFT

var _main: Node
var _box: Control
var _choices: Array = []  # [ボタン, 設定のキー, その値]。選ばれている物を "on" の見た目にする
var _offset: Label
var _minus: Button
var _plus: Button
var _t := 0.0


func setup(main: Node, _info: Dictionary) -> void:
	_main = main


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_box = Title.box(self)
	Title.put(_box, S.SETTINGS, 44, 900, Kit.C_TEXT, Rect2(60, 96, 600, 68), LEFT)

	Title.put(_box, S.VOLUME, 26, 500, Kit.C_TEXT, Rect2(60, 196, 300, 42), LEFT)
	for i in B.VOLUMES.size():
		var v: int = B.VOLUMES[i]
		_choice("btn_vol_%d" % v, S.volume(v), Rect2(60 + i * 122, 246, 112, 88), "volume", v)
	_switch(S.SHAKE, 368.0, "shake", "btn_shake")
	_switch(S.REDUCE_FLASH, 468.0, "reduce_flash", "btn_flash")
	_switch(S.SHOW_DIFF, 568.0, "show_diff", "btn_diff")
	_switch(S.EASY, 668.0, "easy", "btn_easy")
	Title.fit(Title.put(_box, S.EASY_HINT, 20, 500, Kit.C_DIM, Rect2(60, 758, 600, 32), LEFT))

	Title.put(_box, S.OFFSET, 26, 500, Kit.C_TEXT, Rect2(60, 812, 250, 88), LEFT)
	_minus = Kit.button("btn_offset_minus", "−", 40)
	_minus.pressed.connect(_nudge.bind(-1))
	_box.add_child(Kit.place(_minus, 320, 812, 92, 88))
	_offset = Title.put(_box, "", 30, 700, Kit.C_TEXT, Rect2(412, 812, 156, 88))
	_plus = Kit.button("btn_offset_plus", "+", 40)
	_plus.pressed.connect(_nudge.bind(1))
	_box.add_child(Kit.place(_plus, 568, 812, 92, 88))
	Title.put(_box, S.OFFSET_HINT, 20, 500, Kit.C_DIM, Rect2(60, 904, 600, 32), LEFT)
	var calib := Kit.button("btn_calib", S.BTN_CALIB, 30)
	calib.pressed.connect(func() -> void: _main.open_calib())
	_box.add_child(Kit.place(calib, 60, 946, 600, 88))

	# 「戻る」は、タイミング合わせの「戻る」と同じ場所(行き来しても動かない)
	var back := Kit.button("btn_back", S.BTN_BACK, 32, "quiet")
	back.pressed.connect(func() -> void: _main.close_settings())
	_box.add_child(Kit.place(back, 220, 1172, 280, 88))
	_sync()


func _choice(node_name: String, text: String, rect: Rect2, key: String, value: Variant) -> void:
	var b := Kit.button(node_name, text, 30)
	b.pressed.connect(_apply.bind(key, value))
	_box.add_child(Kit.place(b, rect.position.x, rect.position.y, rect.size.x, rect.size.y))
	_choices.append([b, key, value])


# 入・切の 1 行。
func _switch(text: String, y: float, key: String, node_name: String) -> void:
	Title.put(_box, text, 26, 500, Kit.C_TEXT, Rect2(60, y, 320, 88), LEFT)
	_choice(node_name + "_on", S.ON, Rect2(400, y, 124, 88), key, true)
	_choice(node_name + "_off", S.OFF, Rect2(536, y, 124, 88), key, false)


func _apply(key: String, value: Variant) -> void:
	_main.save.set_setting(key, value)
	_main.settings_changed()
	if key == "volume":
		Sfx.play("parry")
	_sync()


func _nudge(d: int) -> void:
	_apply("offset_ticks",int(_main.save.settings()["offset_ticks"]) + d)


# 今の設定を、見た目に写す。
func _sync() -> void:
	var st: Dictionary = _main.save.settings()
	for c: Array in _choices:
		var b: Button = c[0]
		var cur: Variant = st[c[1]]
		var on: bool = typeof(cur) == typeof(c[2]) and cur == c[2]
		if not b.has_meta("on") or b.get_meta("on") != on:
			b.set_meta("on", on)
			Title.restyle(b, "on" if on else "normal")
	_sync_offset()


func _sync_offset() -> void:
	var off := int(_main.save.settings()["offset_ticks"])
	_offset.text = S.signed_ms(Rank.ms(off))
	_minus.disabled = off <= B.OFFSET_MIN
	_plus.disabled = off >= B.OFFSET_MAX


func _input(event: InputEvent) -> void:
	if _main.screen_name == "settings" and Title.fresh_key(event) == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_main.close_settings()


func _process(delta: float) -> void:
	_t += delta
	Title.enter(_box, _t / Title.ENTER_SEC)
	_sync_offset()  # タイミング合わせから戻った時に、新しい値になる



func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Kit.C_BG)
