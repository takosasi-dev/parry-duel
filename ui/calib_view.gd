# タイミング合わせの画面(画面設計書 S6)。core/calib.gd を進め、押したずれと、合う「判定のずれ」を出す。
# 攻撃の頭は対戦と同じ式(core/attack.gd)で動かし、場を 0.78 倍に縮めて上に寄せて描く。
extends Control

const B := preload("res://core/balance.gd")
const Attack := preload("res://core/attack.gd")
const Calib := preload("res://core/calib.gd")
const Rank := preload("res://core/rank.gd")
const S := preload("res://core/strings.gd")
const Kit := preload("res://ui/kit.gd")
const Fx := preload("res://ui/fx.gd")

const FIELD_SCALE := 0.78
const FIELD_POS := Vector2(360.0 * (1.0 - FIELD_SCALE), 236.0 - 300.0 * FIELD_SCALE)
const FIELD_BOTTOM := 830.0  # これより上の右半分を押すと「弾く」

var calib: Calib
var _main: Node
var _acc := 0.0
var _time := 0.0
var _field: Node2D
var _fx: Fx
var _use: Button
var _again: Button
var _suggest: Variant = null


func setup(main: Node, _info: Dictionary) -> void:
	_main = main


func _ready() -> void:
	size = Vector2(B.SCREEN_W, B.SCREEN_H)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_field = Node2D.new()
	_field.position = FIELD_POS
	_field.scale = Vector2(FIELD_SCALE, FIELD_SCALE)
	_field.draw.connect(_draw_field)
	add_child(_field)
	_fx = Fx.new()
	_fx.shake_enabled = false
	_field.add_child(_fx)

	_use = Kit.button("btn_use", S.BTN_USE, 32, "primary")
	_use.pressed.connect(_on_use)
	add_child(Kit.place(_use, 40, 960, 310, 96))
	_again = Kit.button("btn_remeasure", S.BTN_REMEASURE, 32)
	_again.pressed.connect(_restart)
	add_child(Kit.place(_again, 370, 960, 310, 96))
	var minus := Kit.button("btn_minus", "−", 44)
	minus.pressed.connect(func() -> void: _nudge(-1))
	add_child(Kit.place(minus, 40, 1068, 110, 88))
	var plus := Kit.button("btn_plus", "+", 44)
	plus.pressed.connect(func() -> void: _nudge(1))
	add_child(Kit.place(plus, 330, 1068, 110, 88))
	var zero := Kit.button("btn_zero", S.BTN_ZERO, 30)
	zero.pressed.connect(func() -> void: _set_offset(0))
	add_child(Kit.place(zero, 460, 1068, 220, 88))
	var back := Kit.button("btn_back", S.BTN_BACK, 32, "quiet")
	back.pressed.connect(func() -> void: _main.close_calib())
	add_child(Kit.place(back, 220, 1172, 280, 88))
	_restart()


func _restart() -> void:
	calib = Calib.new()
	_acc = 0.0
	_suggest = null
	_use.visible = false
	_again.visible = false
	_fx.clear()
	queue_redraw()


func _offset() -> int:
	return int(_main.save.settings()["offset_ticks"])


func _set_offset(v: int) -> void:
	_main.save.set_setting("offset_ticks", v)
	_main.settings_changed()
	queue_redraw()


func _nudge(d: int) -> void:
	_set_offset(_offset() + d)


func _on_use() -> void:
	if _suggest != null:
		_set_offset(int(_suggest))
	_main.close_calib()


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	var hit := false
	if event is InputEventKey:
		hit = event.pressed and not event.echo and (event.physical_keycode == KEY_SPACE or event.physical_keycode == KEY_X)
		if event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
			_main.close_calib()
			get_viewport().set_input_as_handled()
			return
	elif event is InputEventScreenTouch:
		hit = event.pressed and _in_field(event.position)
	elif event is InputEventMouseButton:
		hit = event.pressed and event.button_index == MOUSE_BUTTON_LEFT and event.device != InputEvent.DEVICE_ID_EMULATION and _in_field(event.position)
	if hit and not calib.done:
		calib.press()
		if _main.debug != null:
			_main.debug.mark_input()


func _in_field(screen_pos: Vector2) -> bool:
	var local := get_global_transform().affine_inverse() * screen_pos
	return local.x >= B.SCREEN_W / 2.0 and local.y < FIELD_BOTTOM


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_time += delta
	_acc += delta * B.TICK_HZ
	var n := int(_acc)
	_acc -= n
	for i in mini(n, B.MAX_STEPS_PER_FRAME):
		calib.step()
		for e: Dictionary in calib.events():
			_on_event(e)
	_fx.advance(delta)
	_field.queue_redraw()
	queue_redraw()


func _on_event(e: Dictionary) -> void:
	var c: Vector2 = B.CONTACT["T"]
	match e["type"]:
		"calib_hit":
			var d: int = e["diff"]
			var near := absi(d) <= B.JUST_WINDOW
			_fx.bounce_head(c, B.ORIGIN["T"], "white")
			_fx.sparks(c, 16 if near else 8, 200.0 if near else 150.0, Kit.C_SPARK, 150.0 if near else 96.0)
			_fx.flash(c, 90.0, 120.0, Kit.C_WHITE, 0.3)
			_fx.popup(c + Vector2(0, -70), S.signed_ms(Rank.ms(d)), 40, Kit.C_SPARK if near else Kit.C_TEXT, 500.0)
			Sfx.play("just" if near else "parry")
		"calib_miss":
			Sfx.play("whiff")
		"calib_done":
			_suggest = calib.result()
			_use.visible = _suggest != null
			_again.visible = true
			Sfx.play("soft")


func _draw_field() -> void:
	var s := calib.snapshot()
	var lit := {}
	for a: Dictionary in s["attacks"]:
		var pr := Attack.progress(a, a["start"], s["tick"])
		lit["T"] = maxf(lit.get("T", 0.0), 0.2 * float(pr["p"]) if pr["phase"] == "windup" else 0.35 + 0.65 * float(pr["along"]))
	for i in 14:
		_field.draw_line((B.ORIGIN["T"] as Vector2).lerp(B.CONTACT["T"], (i + 0.25) / 14.0), (B.ORIGIN["T"] as Vector2).lerp(B.CONTACT["T"], (i + 0.6) / 14.0), Color(Kit.C_LINE, 0.12), 2.0, true)
	Kit.draw_parry_line(_field, B.LINE_X0, B.LINE_X1, B.LINE_Y, {"T": B.CONTACT["T"]}, lit)
	for a: Dictionary in s["attacks"]:
		var pr := Attack.progress(a, a["start"], s["tick"])
		var pos := Attack.head_pos(a, a["start"], s["tick"])
		if pr["phase"] == "windup":
			var p: float = pr["p"]
			Kit.draw_head(_field, pos, "white", 0.3 + 0.7 * p, 0.7 + 0.3 * p, minf((int(s["tick"]) - int(a["start"])) / 8.0, 1.0))
		elif pr["phase"] == "contact":
			Kit.draw_head(_field, pos + Vector2(sin(_time * 95.0) * 2.5, 0), "white", 1.0, 1.08)
		else:
			Kit.draw_head(_field, pos, "white")


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Kit.C_BG)
	Kit.text(self, Vector2(360, 96), S.CALIB, 44, Kit.C_TEXT, 900)
	Kit.text(self, Vector2(360, 150), S.CALIB_GUIDE, 26, Kit.C_DIM, 500)
	var s := calib.snapshot()
	Kit.text(self, Vector2(60, 892), S.calib_count(s["count"], B.CALIB_COUNT), 34, Kit.C_TEXT, 700, HORIZONTAL_ALIGNMENT_LEFT, 200.0)
	if s["last_diff"] != null:
		Kit.text(self, Vector2(660, 892), S.calib_now(Rank.ms(int(s["last_diff"]))), 30, Kit.C_TEXT, 500, HORIZONTAL_ALIGNMENT_RIGHT, 400.0)
	if s["done"]:
		if _suggest == null:
			Kit.text(self, Vector2(360, 940), S.CALIB_FAILED, 30, Kit.C_RED, 700)
		else:
			Kit.text(self, Vector2(360, 940), S.calib_result(Rank.ms(int(_suggest))), 34, Kit.C_SPARK, 700)
	Kit.text(self, Vector2(240, 1108), S.OFFSET, 20, Kit.C_DIM, 500, HORIZONTAL_ALIGNMENT_CENTER, 180.0)
	Kit.text(self, Vector2(240, 1142), S.signed_ms(Rank.ms(_offset())), 30, Kit.C_TEXT, 700, HORIZONTAL_ALIGNMENT_CENTER, 180.0)
