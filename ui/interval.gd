# 合間(画面設計書 S3)。倒した敵と、ここまでの小計を見せる。「次の敵へ」で進む。
# ここにいる間、対戦の時間は進まない(対戦画面が止まっている)。
extends Control

const Rank := preload("res://core/rank.gd")
const S := preload("res://core/strings.gd")
const Kit := preload("res://ui/kit.gd")
const Title := preload("res://ui/title.gd")

const WAIT_SEC := 0.5  # 「次の敵へ」が押せるようになるまで
const MARK_POS := Vector2(360, 372)

var _main: Node
var _info: Dictionary
var _box: Control
var _next: Button
var _t := 0.0


func setup(main: Node, info: Dictionary) -> void:
	_main = main
	_info = info


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_box = Title.box(self)
	_box.draw.connect(_draw_mark)
	var boss: int = _info["boss"]
	var hits: int = _info["hits"]
	Title.put(_box, S.boss_beaten(boss), 56, 900, Kit.C_TEXT, Rect2(20, 520, 680, 84))
	Title.put(_box, S.so_far(hits, Rank.seconds_text(int(_info["ticks"]))), 30, 500, Kit.C_TEXT, Rect2(20, 628, 680, 46))
	Title.put(_box, S.justs(int(_info["justs"])), 26, 500, Kit.C_DIM, Rect2(20, 678, 680, 40))
	_next = Kit.button("btn_next", S.BTN_NEXT, 40, "primary")
	_next.disabled = true
	_next.pressed.connect(_go)
	_box.add_child(Kit.place(_next, 80, 856, 560, 120))


func _go() -> void:
	if _t >= WAIT_SEC:
		_main.next_boss()


func _input(event: InputEvent) -> void:
	if _main.screen_name == "interval" and Title.is_go_key(event):
		get_viewport().set_input_as_handled()
		_go()


func _process(delta: float) -> void:
	_t += delta
	Title.enter(_box, _t / Title.ENTER_SEC)
	_next.disabled = _t < WAIT_SEC
	if _t < 1.0:
		_box.queue_redraw()


# 倒した敵の形を、敵の色の線で。入ってすぐ、斬り跡が走る。
func _draw_mark() -> void:
	var boss: int = _info["boss"]
	Kit.glow(_box, MARK_POS, 230.0, Kit.boss_color(boss), 0.07)
	Title.mark(_box, boss, MARK_POS, 96.0, Kit.boss_color(boss), clampf((_t - 0.12) / 0.16, 0.001, 1.0))


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Kit.C_BG)
