# 実績を取った時の知らせ(v0.3.0)。画面の上に、上から降りて 2.4 秒出て、上へ戻る。続けて取った時は順に出す。
# 押しは下へ通す(遊びを邪魔しない)。main が stage の一番上に置く(デバッグの帯よりは下)。
extends Control

const S := preload("res://core/strings.gd")
const Kit := preload("res://ui/kit.gd")

const SHOW_SEC := 2.4
const SLIDE_SEC := 0.25
const RECT := Rect2(110, 148, 500, 92)

var queue: Array = []  # まだ出していない実績の名前
var current := ""  # 今出している名前(テストとデバッグの窓口が読む)
var _t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(720, 1280)
	z_index = 90


func push(text: String) -> void:
	queue.append(text)


func _process(delta: float) -> void:
	if current == "":
		if queue.is_empty():
			return
		current = queue.pop_front()
		_t = 0.0
		Sfx.play("just", 7)
	_t += delta
	if _t >= SHOW_SEC:
		current = ""
	queue_redraw()


func _draw() -> void:
	if current == "":
		return
	var k := minf(minf(_t, SHOW_SEC - _t) / SLIDE_SEC, 1.0)
	var r := RECT
	r.position.y -= (1.0 - k) * (1.0 - k) * 120.0
	draw_rect(r, Color(Kit.C_BG, 0.94 * k))
	draw_rect(r, Color(Kit.C_SPARK, 0.9 * k), false, 3.0)
	Kit.text(self, r.position + Vector2(r.size.x / 2.0, 34), S.ACH_GOT, 20, Color(Kit.C_SPARK, k), 700, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	Kit.text(self, r.position + Vector2(r.size.x / 2.0, 72), current, 30, Color(Kit.C_TEXT, k), 900, HORIZONTAL_ALIGNMENT_CENTER, r.size.x - 24.0)
