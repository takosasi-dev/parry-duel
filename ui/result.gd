# 結果(画面設計書 S4)。受けた数・時間・最高との差・共有する文字を出す。練習では記録・差・共有を出さない。
# 記録を書くのは main(save)。ここは渡された info を見せるだけ。
extends Control

const B := preload("res://core/balance.gd")
const Rank := preload("res://core/rank.gd")
const S := preload("res://core/strings.gd")
const Kit := preload("res://ui/kit.gd")
const Fx := preload("res://ui/fx.gd")
const Title := preload("res://ui/title.gd")

const WAIT_SEC := 0.3  # 「もう1回」が押せるようになるまで
const SHARE_RECT := Rect2(40, 728, 640, 0)  # 高さは字の大きさで決まる
const SHARE_PAD := Vector2(20, 14)
const SHARE_GAP := 6  # 行の間
const SHARE_SIZES := [22, 20, 18, 16, 14, 12]
const HITS_POS := Vector2(360, 276)

var _main: Node
var _info: Dictionary
var _box: Control
var _again: Button
var _copied: Label
var _fx: Fx
var _marks: Array = []  # 上に並べる敵の印
var _won := false
var _bright := false  # 新しい記録
var _sparked := false
var _t := 0.0


func setup(main: Node, info: Dictionary) -> void:
	_main = main
	_info = info


# 最高との差の 1 行(§3.3)。{ text, bright }。bright = 新しい記録。
static func diff_line(result: Dictionary, record: Dictionary) -> Dictionary:
	var prev: Variant = record["prev_best"]
	if not (prev is Dictionary):
		return {"text": S.FIRST_RECORD, "bright": true}
	var dh := int(result["hits"]) - int(prev["hits"])
	var dt := int(result["ticks"]) - int(prev["ticks"])
	if dh < 0:
		return {"text": S.diff_fewer_hits(-dh), "bright": true}
	if dh > 0:
		return {"text": S.diff_more_hits(dh), "bright": false}
	# 差が 0.1 秒に満たない時は「0.0秒」と出さない
	if dt < 0:
		return {"text": S.diff_faster(Rank.seconds_text(-dt)) if Rank.tenths(-dt) > 0 else S.NEW_RECORD, "bright": true}
	if dt > 0 and Rank.tenths(dt) > 0:
		return {"text": S.diff_slower(Rank.seconds_text(dt)), "bright": false}
	return {"text": S.SAME_AS_BEST, "bright": false}


# 共有する文字の全部の行が、幅 width に折り返さずに入る字の大きさ。
static func share_font_size(text: String, width: float) -> int:
	for sz: int in SHARE_SIZES:
		var widest := 0.0
		for line: String in text.split("\n"):
			widest = maxf(widest, Kit.font(500).get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x)
		if widest <= width:
			return sz
	return SHARE_SIZES[-1]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_box = Title.box(self)
	_box.draw.connect(_draw_marks)
	_fx = Fx.new()  # 字の後ろに置く
	_fx.shake_enabled = false
	_box.add_child(_fx)
	var r: Dictionary = _info["result"]
	var practice: bool = _info["practice"]
	var boss: int = r["boss"]
	var hits: int = r["hits"]
	var share: String = _info["share_text"]
	_won = r["won"]
	var oy := 110.0 if practice else 0.0  # 練習は物が少ないので、下へ寄せる

	var head := S.RESULT_WIN
	if practice:
		head = S.practice_win(boss) if _won else S.PRACTICE_LOSE
		_marks = [boss]
	else:
		_marks = range(1, B.BOSS_COUNT + 1)
	Title.put(_box, head, 32, 700, Kit.C_TEXT, Rect2(20, 142 + oy, 680, 50))
	Title.fit(Title.put(_box, S.hits_or_unhurt(hits), 96, 900, Kit.C_PLAYER if hits == 0 else Kit.C_TEXT, Rect2(20, 204 + oy, 680, 144)))
	Title.put(_box, S.seconds(Rank.seconds_text(int(r["ticks"]))), 48, 700, Kit.C_TEXT, Rect2(20, 350 + oy, 680, 72))
	if not practice and _won:
		var diff := diff_line(r, _info["record"])
		_bright = diff["bright"]
		Title.fit(Title.put(_box, diff["text"], 26, 700 if _bright else 500, Kit.C_SPARK if _bright else Kit.C_DIM, Rect2(20, 428, 680, 42)))
	Title.put(_box, S.justs(int(r["justs"])), 26, 500, Kit.C_DIM, Rect2(60, 482 + oy, 280, 42), HORIZONTAL_ALIGNMENT_RIGHT)
	Title.put(_box, S.retries(int(r["retries"])), 26, 500, Kit.C_DIM, Rect2(380, 482 + oy, 280, 42), HORIZONTAL_ALIGNMENT_LEFT)

	_again = Kit.button("btn_again", S.BTN_AGAIN, 40, "primary")
	_again.disabled = true
	_again.pressed.connect(_go_again)
	_box.add_child(Kit.place(_again, 80, 566 + oy, 560, 120))
	var title := Kit.button("btn_title", S.BTN_TITLE, 32)
	title.pressed.connect(func() -> void: _main.go_title())

	var bottom := 566.0 + oy + 120.0 + 30.0
	if practice or share == "":
		_box.add_child(Kit.place(title, 80, bottom, 560, 96))
		bottom += 96.0
	else:
		var box := _share_box(share)
		bottom = box.position.y + box.size.y
		_copied = Title.put(_box, S.COPIED, 20, 500, Kit.C_DIM, Rect2(40, bottom + 4, 640, 32))
		_copied.visible = false
		var copy := Kit.button("btn_copy", S.BTN_COPY, 32)
		copy.pressed.connect(_copy)
		_box.add_child(Kit.place(copy, 80, bottom + 44, 270, 96))
		_box.add_child(Kit.place(title, 370, bottom + 44, 270, 96))
		bottom += 140.0
	var record: Dictionary = _info["record"]
	var saved: Variant = record["saved"]
	if saved is bool and not saved:
		Title.put(_box, S.SAVE_FAILED, 22, 700, Kit.C_RED, Rect2(40, bottom + 14, 640, 36))


# 共有する文字の枠。選べるが、書き換えられない。
func _share_box(share: String) -> TextEdit:
	var sz := share_font_size(share, SHARE_RECT.size.x - SHARE_PAD.x * 2.0 - 8.0)
	var lines := share.split("\n").size()
	var te := TextEdit.new()
	te.name = "share_box"
	te.text = share
	te.editable = false
	te.context_menu_enabled = false
	te.virtual_keyboard_enabled = false
	te.wrap_mode = TextEdit.LINE_WRAPPING_NONE
	var flat := StyleBoxFlat.new()
	flat.bg_color = Kit.C_BG_HI
	flat.set_corner_radius_all(6)
	flat.content_margin_left = SHARE_PAD.x
	flat.content_margin_right = SHARE_PAD.x
	flat.content_margin_top = SHARE_PAD.y
	flat.content_margin_bottom = SHARE_PAD.y
	for n: String in ["normal", "read_only", "focus"]:
		te.add_theme_stylebox_override(n, flat)
	te.add_theme_font_override("font", Kit.font(500))
	te.add_theme_font_size_override("font_size", sz)
	te.add_theme_constant_override("line_spacing", SHARE_GAP)
	for c: String in ["font_color", "font_readonly_color"]:
		te.add_theme_color_override(c, Kit.C_TEXT)
	te.add_theme_color_override("selection_color", Color(Kit.C_PLAYER, 0.35))
	var h := lines * (Kit.font(500).get_height(sz) + SHARE_GAP) + SHARE_PAD.y * 2.0 + 4.0
	_box.add_child(Kit.place(te, SHARE_RECT.position.x, SHARE_RECT.position.y, SHARE_RECT.size.x, h))
	return te


func _go_again() -> void:
	if _t >= WAIT_SEC:
		_main.again()


# コピーを試す。ブラウザが断っても分からないので、枠から写せることを伝える(E-18)。
func _copy() -> void:
	DisplayServer.clipboard_set(_info["share_text"])
	_copied.visible = true


func _input(event: InputEvent) -> void:
	if _main.screen_name == "result" and Title.is_go_key(event):
		get_viewport().set_input_as_handled()
		_go_again()


func _process(delta: float) -> void:
	_t += delta
	Title.enter(_box, _t / Title.ENTER_SEC)
	_again.disabled = _t < WAIT_SEC
	if _bright and not _sparked and _t >= Title.ENTER_SEC:
		_sparked = true
		_fx.sparks(HITS_POS, 14, 320.0, Kit.C_SPARK, 250.0)
	_fx.advance(delta)
	if _t < 1.0:
		_box.queue_redraw()


# 上に、倒した敵の印を並べる(練習は その敵だけ。負けた時は斬り跡なし)。
func _draw_marks() -> void:
	var y := 96.0 + (110.0 if _info["practice"] else 0.0)
	for i in _marks.size():
		var boss: int = _marks[i]
		var slash := clampf((_t - 0.1 - 0.08 * i) / 0.14, 0.001, 1.0) if _won else 0.0
		Title.mark(_box, boss, Vector2(360.0 + (i - (_marks.size() - 1) / 2.0) * 68.0, y), 22.0, Kit.boss_color(boss), slash)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Kit.C_BG)
