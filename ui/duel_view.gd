# 対戦画面(画面設計書 S2)。入力を Duel に渡し、たまった時間ぶん step() を呼び、events で演出と音を始め、snapshot を描く。
# 頭の位置は core/attack.gd の式だけで出す(INV-5)。判定の決まりは持たない(INV-1)。
extends Node2D

signal boss_beaten  # 敵 1・敵 2 を倒した(割れる動きの後)
signal finished  # 終わった(3 体を倒した・練習が終わった)。結果は duel.result()
signal retry_requested
signal title_requested
signal pause_requested

const B := preload("res://core/balance.gd")
const Attack := preload("res://core/attack.gd")
const Duel := preload("res://core/duel.gd")
const S := preload("res://core/strings.gd")
const Kit := preload("res://ui/kit.gd")
const Fx := preload("res://ui/fx.gd")
const Rank := preload("res://core/rank.gd")

const HIDDEN_DELTA := 0.25  # これより長い 1 フレームは「裏にいた」と見て一時停止にする(E-10)
const PAUSE_RECT := Rect2(24, 24, 88, 88)
const LOG_MAX := 24

var duel: Duel
var paused := false
var resume_left := 0.0  # 再開の待ちの残り(秒)
var debug: Node = null  # デバッグ用の窓口(無ければ null)
var event_log: Array = []  # 直近の出来事 [通し番号, type, tick]
var steps_last_frame := 0

var _acc := 0.0
var _time := 0.0
var _fx: Fx
var _seq := 0
var _tilt := 0.0
var _whiff_t := 0.0
var _dodge_t := 0.0
var _free_t := 0.0
var _bump_t := 0.0
var _bump_x := 0.0
var _since_counter := 99.0
var _hp_pop_t := 0.0
var _end_t := -1.0  # 終わり・敵を倒した時からの秒
var _end_sent := false
var _boss_gone := false
var _after_freeze: Array = []  # 止めが明けた時に始める演出
var _freeze_t := 0.0  # 止め(12 tick)の残りの秒。敵を倒した時は sim が止まるので、実時間で数える
var _lose_box: Control
var _pause_btn: Button
var _show_diff := true  # 押したずれを出す(設定)
var _trig := {}  # パッドの引き金(軸)を押し込んでいるか。押し込んだ時だけ 1 回に数える


func _ready() -> void:
	_fx = Fx.new()
	add_child(_fx)
	_pause_btn = Kit.button("btn_pause", "", 28, "quiet")
	Kit.place(_pause_btn, PAUSE_RECT.position.x, PAUSE_RECT.position.y, PAUSE_RECT.size.x, PAUSE_RECT.size.y)
	_pause_btn.pressed.connect(func() -> void: pause_requested.emit())
	add_child(_pause_btn)
	_lose_box = Control.new()
	_lose_box.visible = false
	var retry := Kit.button("btn_retry", S.BTN_RETRY, 40, "primary")
	retry.pressed.connect(func() -> void: retry_requested.emit())
	_lose_box.add_child(Kit.place(retry, 80, 600, 560, 120))
	var title := Kit.button("btn_lose_title", S.BTN_TITLE, 34)
	title.pressed.connect(func() -> void: title_requested.emit())
	_lose_box.add_child(Kit.place(title, 80, 760, 560, 96))
	add_child(_lose_box)


# 対戦を始める。settings は保存の settings(shake・reduce_flash・offset_ticks)。
func start(d: Duel, settings: Dictionary) -> void:
	duel = d
	apply_settings(settings)
	paused = false
	resume_left = 0.0
	_acc = 0.0
	_tilt = 0.0
	_end_t = -1.0
	_end_sent = false
	_boss_gone = false
	_after_freeze.clear()
	_freeze_t = 0.0
	_whiff_t = 0.0
	_dodge_t = 0.0
	_free_t = 0.0
	_lose_box.visible = false
	_pause_btn.visible = true
	_fx.clear()
	queue_redraw()


func apply_settings(settings: Dictionary) -> void:
	_show_diff = settings.get("show_diff", true) == true
	_fx.shake_enabled = settings["shake"]
	_fx.reduce_flash = settings["reduce_flash"]
	if duel != null:
		duel.set_offset(settings["offset_ticks"])


# 次の敵へ(合間の画面の「次の敵へ」から呼ぶ)。
func next_boss() -> void:
	duel.next_boss()
	_end_t = -1.0
	_end_sent = false
	_boss_gone = false
	_after_freeze.clear()
	_freeze_t = 0.0
	_tilt = 0.0
	_acc = 0.0
	_fx.clear()


# 一時停止にする。止まる直前の押しは、再開の後に使わない。
func pause() -> void:
	paused = true
	if duel != null:
		duel.clear_input()


# 一時停止から続ける。120 tick ぶんの実時間を待ってから進める(E-9)。
func resume() -> void:
	paused = false
	if duel != null:
		duel.clear_input()
	resume_left = float(B.RESUME_WAIT_TICKS) / B.TICK_HZ
	_acc = 0.0


# 負けて「この敵からやり直す」が出ている。
func lost() -> bool:
	return _lose_box.visible


func is_playing() -> bool:
	return duel != null and not duel.over and duel.state != Duel.State.WAIT_NEXT and not _lose_box.visible


func _accepts_input() -> bool:
	return is_playing() and not paused and resume_left <= 0.0 and visible


func _input(event: InputEvent) -> void:
	if duel == null or not visible:
		return
	if event is InputEventKey:
		if not event.pressed or event.echo:
			return
		match event.physical_keycode:
			KEY_SPACE, KEY_X:
				_press(true)
			KEY_Z:
				_press(false)
			KEY_SHIFT:
				if event.location != KEY_LOCATION_RIGHT:
					_press(false)
			KEY_ESCAPE:
				if is_playing() and not paused:
					pause_requested.emit()
					get_viewport().set_input_as_handled()
			KEY_R:
				if _lose_box.visible:
					retry_requested.emit()
	elif event is InputEventJoypadButton:
		if not event.pressed or _lose_box.visible:
			return  # 負けた後の 2 つのボタンは、main がメニューと同じに選ばせる
		match event.button_index:
			JOY_BUTTON_A, JOY_BUTTON_RIGHT_SHOULDER, JOY_BUTTON_X:
				_press(true)
			JOY_BUTTON_B, JOY_BUTTON_LEFT_SHOULDER:
				_press(false)
			JOY_BUTTON_START:
				if is_playing() and not paused:
					pause_requested.emit()
					get_viewport().set_input_as_handled()
	elif event is InputEventJoypadMotion:
		# 引き金: 右 = 弾く、左 = 避ける。半分を越えた時に 1 回
		if event.axis == JOY_AXIS_TRIGGER_RIGHT or event.axis == JOY_AXIS_TRIGGER_LEFT:
			var down: bool = event.axis_value > 0.5
			if down and not _trig.get(event.axis, false):
				_press(event.axis == JOY_AXIS_TRIGGER_RIGHT)
			_trig[event.axis] = down
	elif event is InputEventScreenTouch:
		if event.pressed:
			_pointer(event.position)
	elif event is InputEventMouseButton:
		# タッチは模擬のマウスとしても届く(device が −1)。二重に数えないよう、そちらは捨てる
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT and event.device != InputEvent.DEVICE_ID_EMULATION:
			_pointer(event.position)


# 画面を押した。x が 360 以上なら弾く、360 未満なら避ける(余りの所も近い側の半分。E-20)。
func _pointer(screen_pos: Vector2) -> void:
	var local := get_global_transform().affine_inverse() * screen_pos
	if PAUSE_RECT.has_point(local):
		return
	_press(local.x >= B.SCREEN_W / 2.0)


func _press(parry: bool) -> void:
	if not _accepts_input():
		return
	if parry:
		duel.press_parry()
	else:
		duel.press_dodge()
	if debug != null:
		debug.mark_input()


func _process(delta: float) -> void:
	steps_last_frame = 0
	if duel == null or not visible:
		return
	_time += delta
	if paused:
		return
	if resume_left > 0.0:
		if delta > HIDDEN_DELTA:  # 待ちの間に裏へ回った。待ちを終わらせず、一時停止に戻す
			resume_left = 0.0
			pause_requested.emit()
			return
		resume_left = maxf(resume_left - delta, 0.0)
		_acc = 0.0
		queue_redraw()
		return
	if delta > HIDDEN_DELTA and is_playing():
		pause_requested.emit()
		return
	_acc += delta * B.TICK_HZ
	var n := int(_acc)
	_acc -= n
	n = mini(n, B.MAX_STEPS_PER_FRAME)  # 超えた分は捨てる(E-11)
	for i in n:
		duel.step()
		for e: Dictionary in duel.events():
			_on_event(e)
	steps_last_frame = n
	if _freeze_t > 0.0:
		_freeze_t -= delta
		if _freeze_t <= 0.0:
			_freeze_ended()
	_since_counter += delta
	_whiff_t = maxf(_whiff_t - delta, 0.0)
	_dodge_t = maxf(_dodge_t - delta, 0.0)
	_free_t = maxf(_free_t - delta, 0.0)
	_bump_t = maxf(_bump_t - delta, 0.0)
	_hp_pop_t = maxf(_hp_pop_t - delta, 0.0)
	var tilt_to := 0.24 if duel.state == Duel.State.STAGGER else 0.0
	_tilt = lerpf(_tilt, tilt_to, 1.0 - exp(-14.0 * delta))
	_fx.advance(delta)
	position = _fx.shake_offset()
	_watch_end(delta)
	queue_redraw()


# 終わり・敵を倒した後、動きを見せてから次の画面へ渡す。
func _watch_end(delta: float) -> void:
	if _end_t < 0.0:
		return
	_end_t += delta
	if _end_sent:
		return
	if duel.state == Duel.State.WAIT_NEXT and _end_t >= 1.5:
		_end_sent = true
		boss_beaten.emit()
	elif duel.over and duel.won and _end_t >= 1.8:
		_end_sent = true
		finished.emit()
	elif duel.over and not duel.won and _end_t >= 0.9:
		_end_sent = true
		if duel.mode == Duel.Mode.PRACTICE:
			finished.emit()
		else:
			_lose_box.visible = true
			_pause_btn.visible = false


func _on_event(e: Dictionary) -> void:
	_seq += 1
	event_log.append([_seq, e["type"], e["tick"]])
	if event_log.size() > LOG_MAX:
		event_log.pop_front()
	match e["type"]:
		"attack_start":
			Sfx.play("warn_red" if e["attack"]["kind"] == "red" else "warn_white")
		"parry":
			var a: Dictionary = e["attack"]
			var c: Vector2 = B.CONTACT[a["arm"]]
			var semis := mini(int(e["combo"]) - 1, 12)
			_bump_t = 0.12
			_bump_x = signf(c.x - B.PLAYER_POS.x) * 16.0
			_fx.bounce_head(c, B.ORIGIN[a["arm"]], a["kind"])
			_fx.streak(c)
			if e["just"]:
				_fx.sparks(c, 16, 200.0, Kit.C_SPARK, 150.0)
				_fx.ring(c, Kit.RING_R, 96.0, 200.0, Kit.C_SPARK, 5.0)
				_fx.flash(c, 120.0, 160.0, Kit.C_SPARK, 0.5)
				_fx.popup(c + Vector2(0, -64), S.JUST, 34, Kit.C_SPARK, 400.0)
				_fx.shake(3.0, 80.0)
				Sfx.play("just", semis)
			else:
				_fx.sparks(c, 8, 150.0, Kit.C_SPARK, 96.0)
				_fx.flash(c, 70.0, 110.0, Kit.C_WHITE, 0.3)
				_fx.shake(2.0, 60.0)
				Sfx.play("parry", semis)
				if _show_diff:  # ぴったりでない時だけ、どちらへ外れたかを出す(v0.2.0)
					_fx.popup(c + Vector2(0, -64), S.press_diff(Rank.ms(int(e["diff"]))), 26, Kit.C_TEXT, 500.0)
		"parry_whiff":
			_whiff_t = 0.3
			if _show_diff and e.get("near") != null:  # 近くの白より早く押した
				_fx.popup(Vector2(360, B.LINE_Y - 70), S.TOO_EARLY, 30, Kit.C_TEXT, 500.0)
			# 反撃の直後の押し(止めの間に覚えた入力。E-8)は、空振りの音で水を差さない。硬直の見た目は出す
			if _since_counter > 0.5:
				Sfx.play("whiff")
		"parry_red":
			_whiff_t = 0.3
			_fx.cross(B.CONTACT[e["attack"]["arm"]])
			Sfx.play("clank")
		"dodge":
			_dodge_t = 0.25
			Sfx.play("dodge")
		"dodge_avoid":
			var av: Dictionary = e["attack"]
			_fx.pass_head(B.CONTACT[av["arm"]], (B.ORIGIN[av["arm"]] as Vector2).direction_to(B.CONTACT[av["arm"]]), av["kind"])
		"attack_fade":
			_fx.fade_head(B.CONTACT[e["attack"]["arm"]], e["attack"]["kind"])
		"hurt":
			_hp_pop_t = 0.3
			_fx.edge_red()
			_fx.shake(6.0, 120.0)
			_fx.sparks(B.PLAYER_POS, 6, 160.0, Kit.C_RED, 70.0, 0.0)
			_fx.flash(B.PLAYER_POS, 130.0, 200.0, Kit.C_RED, 0.45)
			_fx.fade_head(B.CONTACT[e["attack"]["arm"]], e["attack"]["kind"])
			Sfx.play("hurt")
		"hurt_free":
			_free_t = 0.15
			_fx.popup(B.PLAYER_POS + Vector2(196, 12), S.TEACH_FREE, 26, Kit.C_TEXT, 600.0, 18.0)
			Sfx.play("soft")
		"stagger":
			_fx.ring(B.BOSS_POS, 120.0, 230.0, 320.0, Kit.C_SPARK, 6.0)
			Sfx.play("stagger")
		"counter":
			_fx.slash(B.BOSS_POS, 1000.0 * B.COUNTER_FREEZE / B.TICK_HZ)
			_after_freeze.append("counter")
			_since_counter = 0.0
			_freeze_t = float(B.COUNTER_FREEZE) / B.TICK_HZ
			Sfx.play("counter")
		"boss_phase":
			_fx.popup(B.BOSS_POS + Vector2(0, 236), "%s %d" % [S.PHASE, int(e["phase"])], 34, Kit.boss_color(duel.boss).lightened(0.3), 1100.0, 0.0)
		"boss_recover":
			Sfx.play("soft", -5)
		"boss_down":
			_after_freeze.append("boss_down")
			_end_t = 0.0
		"player_down":
			_fx.darken(400.0)
			_end_t = 0.0
			Sfx.play("hurt", -7)


# 止め(12 tick)が明けた。反撃の一番派手な所をここで出す。
func _freeze_ended() -> void:
	for what: String in _after_freeze:
		if what == "counter":
			_fx.shake(10.0, 150.0)
			_fx.sparks(B.BOSS_POS, 22, 320.0, Kit.C_SPARK, 260.0, 0.0)
			_fx.flash(B.BOSS_POS, 300.0, 220.0, Kit.C_WHITE, 0.55)
		elif what == "boss_down":
			_boss_gone = true
			_fx.shake(10.0, 200.0)
			_fx.shatter(B.BOSS_POS, _boss_pieces(duel.boss), Kit.boss_color(duel.boss))
			_fx.ring(B.BOSS_POS, 60.0, 330.0, 420.0, Kit.boss_color(duel.boss).lightened(0.4), 6.0)
			Sfx.play("shatter")
	_after_freeze.clear()


# ---- 描く ----

static func _boss_shape(boss: int) -> PackedVector2Array:
	return Kit.boss_shape(boss, Vector2.ZERO, 110.0)


# 割れる時の 3 つのかけら(中心から扇に切る)。
static func _boss_pieces(boss: int) -> Array:
	var pts := _boss_shape(boss)
	var n := pts.size()
	var out: Array = []
	var counts: Array = {3: [1, 1, 1], 4: [2, 1, 1], 6: [2, 2, 2]}[n]  # かけらごとの辺の数
	var i0 := 0
	for count: int in counts:
		var piece := PackedVector2Array([Vector2.ZERO])
		for j in count + 1:
			piece.append(pts[(i0 + j) % n])
		i0 += count
		out.append(piece)
	return out


func _draw() -> void:
	if duel == null:
		return
	var s := duel.snapshot()
	var tick: int = s["tick"]
	var attacks: Array = s["attacks"]
	var boss: int = s["boss"]
	var col := Kit.boss_color(boss)
	var state: int = s["state"]

	# 敵の後ろの光と、頭の通り道
	var boss_pos := _boss_pos(s)
	Kit.glow(self, boss_pos, 380.0, col, 0.10, 36)
	if not _boss_gone:
		var spin := _time * 0.22
		for i in 3:
			draw_arc(boss_pos, 196.0, spin + TAU * i / 3.0, spin + TAU * i / 3.0 + 1.25, 24, Color(col, 0.16), 2.0, true)
			draw_arc(boss_pos, 240.0, -spin * 0.7 + TAU * i / 3.0, -spin * 0.7 + TAU * i / 3.0 + 0.7, 16, Color(col, 0.09), 2.0, true)
	# 弾く線より下を少し沈めて、自分の場所を分ける
	var floor_a := Color(0, 0, 0, 0.0)
	var floor_b := Color(0, 0, 0, 0.34)
	draw_polygon(PackedVector2Array([Vector2(0, B.LINE_Y), Vector2(B.SCREEN_W, B.LINE_Y), Vector2(B.SCREEN_W, B.SCREEN_H), Vector2(0, B.SCREEN_H)]),
		PackedColorArray([floor_a, floor_a, floor_b, floor_b]))
	var active := {}
	var lit := {}
	var charge := 0.0
	for a: Dictionary in attacks:
		var pr := Attack.progress(a, a["start"], tick)
		active[a["arm"]] = true
		if pr["phase"] == "windup":
			charge = maxf(charge, pr["p"])
			lit[a["arm"]] = maxf(lit.get(a["arm"], 0.0), 0.2 * float(pr["p"]))
		else:
			lit[a["arm"]] = maxf(lit.get(a["arm"], 0.0), 0.35 + 0.65 * float(pr["along"]))
	for arm: String in B.ORIGIN:
		_draw_lane(B.ORIGIN[arm], B.CONTACT[arm], 0.16 if active.has(arm) else 0.05)

	# 腕(敵から頭まで)
	if not _boss_gone:
		for a: Dictionary in attacks:
			var head := Attack.head_pos(a, a["start"], tick)
			var grow := minf((tick - int(a["start"])) / 8.0, 1.0)
			draw_line(boss_pos, boss_pos.lerp(head, grow), Color(col, 0.9), 4.0, true)

	# 敵
	if not _boss_gone:
		_draw_boss(boss_pos, boss, B.BOSS_HP - int(s["boss_hp"]), state == Duel.State.STAGGER, charge)

	# 教える型の 1 行(頭より後ろに描く)
	if s["teaching"] and (state == Duel.State.PATTERN or state == Duel.State.GAP):
		var line := S.TEACH_DODGE if boss == 3 else S.TEACH_PARRY
		draw_rect(Rect2(60, 842, 600, 56), Color(Kit.C_BG, 0.72))
		Kit.text(self, Vector2(360, 882), line, 30, Kit.C_TEXT, 700)

	# 弾く線
	Kit.draw_parry_line(self, B.LINE_X0, B.LINE_X1, B.LINE_Y, B.CONTACT, lit)

	# 頭
	for a: Dictionary in attacks:
		_draw_attack_head(a, tick)

	_draw_player(s)
	_draw_hud(s)

	if state == Duel.State.STAGGER:
		var pulse := 0.5 + 0.5 * sin(_time * 14.0)
		var c := Vector2(540, 720)
		draw_circle(c, 104.0, Color(Kit.C_BG, 0.55), true, -1.0, true)
		draw_arc(c, 104.0 + 10.0 * pulse, 0.0, TAU, 64, Color(Kit.C_SPARK, 0.95), 6.0, true)
		draw_arc(c, 128.0 + 16.0 * pulse, 0.0, TAU, 64, Color(Kit.C_SPARK, 0.35 * (1.0 - pulse)), 3.0, true)
		Kit.text(self, c + Vector2(0, 24), S.NOW, 64, Kit.C_SPARK, 900)
		Kit.text(self, c + Vector2(0, 156), S.COUNTER_HINT, 28, Kit.C_SPARK, 700)
	elif state == Duel.State.INTRO:
		var k := float(tick - int(s["state_from"])) / B.INTRO_TICKS
		var a2 := clampf(minf(k * 5.0, (1.0 - k) * 3.0), 0.0, 1.0)
		if duel.mode == Duel.Mode.DRILL:
			Kit.text(self, Vector2(360, 760), _drill_name(), 52, Color(Kit.C_TEXT, a2), 900)
		else:
			Kit.text(self, Vector2(360, 760), S.boss_of(boss, B.BOSS_COUNT), 72, Color(Kit.C_TEXT, a2), 900)

	if resume_left > 0.0:
		var total := float(B.RESUME_WAIT_TICKS) / B.TICK_HZ
		var c2 := Vector2(360, 640)
		draw_circle(c2, 78.0, Color(Kit.C_BG, 0.8), true, -1.0, true)
		draw_arc(c2, 60.0, 0.0, TAU, 64, Color(Kit.C_DIM, 0.35), 6.0, true)
		draw_arc(c2, 60.0, -PI / 2.0, -PI / 2.0 + TAU * (1.0 - resume_left / total), 64, Kit.C_TEXT, 8.0, true)


func _boss_pos(s: Dictionary) -> Vector2:
	var pos: Vector2 = B.BOSS_POS
	if s["state"] == Duel.State.INTRO:
		var k := clampf(float(int(s["tick"]) - int(s["state_from"])) / B.INTRO_TICKS, 0.0, 1.0)
		var e := 1.0 - pow(1.0 - k, 3.0)
		pos.y += -560.0 * (1.0 - e)
	elif s["state"] == Duel.State.RECOVER:
		# 反撃を受けてのけぞり、構え直す
		var k2 := clampf(float(int(s["tick"]) - int(s["state_from"])) / B.RECOVER_TICKS, 0.0, 1.0)
		pos += Vector2(26.0, -40.0) * pow(1.0 - k2, 2.0) * minf(k2 * 14.0, 1.0)
	return pos + Vector2(0, 5.0 * sin(_time * 1.7))


func _draw_lane(from: Vector2, to: Vector2, alpha: float) -> void:
	var n := 14
	for i in n:
		var a := from.lerp(to, (i + 0.25) / n)
		var b := from.lerp(to, (i + 0.6) / n)
		draw_line(a, b, Color(Kit.C_LINE, alpha), 2.0, true)


func _draw_boss(pos: Vector2, boss: int, cracks: int, staggered: bool, charge: float) -> void:
	var col := Kit.boss_color(boss)
	if staggered:
		col = col.lerp(Kit.C_WHITE, 0.45)
	var wobble := 0.04 * sin(_time * 22.0) if staggered else 0.0
	draw_set_transform(pos, _tilt + wobble, Vector2.ONE)
	var pts := _boss_shape(boss)
	var shades := PackedColorArray()
	for p: Vector2 in pts:
		shades.append(col.darkened(0.42 + 0.30 * clampf(p.y / 120.0, -1.0, 1.0)))
	draw_polygon(pts, shades)
	# 中の形。敵 2(振り子)は、ゆっくり左右に振れる
	var sway := 0.42 * sin(_time * 2.4) if boss == 2 and not staggered else 0.0
	var inner := PackedVector2Array()
	for p: Vector2 in pts:
		inner.append((p * 0.62).rotated(sway))
	draw_colored_polygon(inner, Color(Kit.C_BG, 0.5))
	Kit.outline(self, inner, Color(col, 0.55), 2.0)
	Kit.outline(self, pts, col.lightened(0.15), 5.0)
	# 芯。予兆の間は明るくなる
	var core := Kit.C_WHITE if staggered else (Kit.C_RED.lightened(0.5 * charge) if boss == 3 else col.lightened(0.3 + 0.5 * charge))
	Kit.glow(self, Vector2.ZERO, 54.0 + 26.0 * charge, core, 0.25 + 0.4 * charge, 20)
	draw_colored_polygon(Kit.ngon(Vector2.ZERO, 15.0 + 5.0 * charge, 4), core)
	# ひび(受けた反撃の数)
	for i in cracks:
		var ang := [-0.7, 2.5, 0.9][i % 3] as float
		var crack := PackedVector2Array([Vector2.from_angle(ang) * 10.0])
		for j in range(1, 6):
			var jig := [0.22, -0.3, 0.26, -0.18, 0.12][j - 1] as float
			crack.append(Vector2.from_angle(ang + jig * (1.0 if i % 2 == 0 else -1.0)) * (j * 21.0))
		draw_polyline(crack, Color(Kit.C_BG, 0.95), 6.0, true)
		draw_polyline(crack, Color(Kit.C_WHITE, 0.75), 2.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_attack_head(a: Dictionary, tick: int) -> void:
	var start: int = a["start"]
	var pr := Attack.progress(a, start, tick)
	var pos := Attack.head_pos(a, start, tick)
	var appear := minf((tick - start) / 8.0, 1.0)
	match pr["phase"]:
		"windup":
			var p: float = pr["p"]
			Kit.draw_head(self, pos, a["kind"], 0.3 + 0.7 * p, (0.7 + 0.3 * p) * appear, appear)
		"contact":
			# 押し込み。当たり点で小さく震える
			var jitter := Vector2(sin(_time * 95.0) * 2.5, cos(_time * 71.0) * 2.0)
			Kit.draw_head(self, pos + jitter, a["kind"], 1.0, 1.08)
		_:
			if pr["phase"] == "move":
				for k in range(4, 0, -1):
					var back := tick - k * 3
					if Attack.progress(a, start, back)["phase"] == "move":
						Kit.draw_head(self, Attack.head_pos(a, start, back), a["kind"], 0.6, 1.0 - 0.09 * k, 0.11 * (5 - k) / 4.0)
			Kit.draw_head(self, pos, a["kind"], 1.0, 1.0)
			if pr["phase"] == "hold":
				# ため。止まっている間、頭のまわりを輪が回る(いつ動き出すかは教えない)
				for i in 3:
					var a0 := _time * 4.0 + TAU * i / 3.0
					draw_arc(pos, Kit.HEAD_R_WHITE + 13.0, a0, a0 + 1.1, 10, Color(Kit.C_WHITE, 0.7), 3.0, true)


func _draw_player(s: Dictionary) -> void:
	var pos: Vector2 = B.PLAYER_POS
	var alpha := 1.0
	if _dodge_t > 0.0:
		pos.x -= 60.0 * sin(PI * (1.0 - _dodge_t / 0.25))
	if int(s["dodge_ticks"]) > 0 or _dodge_t > 0.0:
		alpha = 0.45
	if int(s["hurt_ticks"]) > 0:
		alpha = 0.5 if fmod(_time * 12.0, 1.0) < 0.6 else 0.25
	if _bump_t > 0.0:
		pos += Vector2(_bump_x, -14.0) * (_bump_t / 0.12)
	var col := Kit.C_PLAYER
	if int(s["lock"]) > 0 or _whiff_t > 0.0:
		col = Kit.C_PLAYER_LOCK
	if _free_t > 0.0:
		col = Kit.C_WHITE
	var tri := Kit.ngon(pos, 28.0, 3)
	if col == Kit.C_PLAYER:
		Kit.glow(self, pos, 70.0, col, 0.16 * alpha, 20)
	draw_colored_polygon(tri, Color(col, alpha))
	Kit.outline(self, tri, Color(col.lightened(0.35), alpha), 2.0)
	# 体力
	var hp: int = s["player_hp"]
	for i in B.PLAYER_HP:
		var c := Vector2(360 + (i - 2) * 36, 1168)
		if i < hp:
			draw_circle(c, 11.0, Kit.C_PLAYER, true, -1.0, true)
		else:
			var pop := _hp_pop_t / 0.3 if i == hp else 0.0
			draw_arc(c, 11.0 + 14.0 * pop, 0.0, TAU, 28, Color(Kit.C_RED if pop > 0.0 else Kit.C_DIM, 0.55 + 0.45 * pop), 2.0, true)
	Kit.text(self, Vector2(256, 1177), S.HP, 22, Kit.C_DIM, 500, HORIZONTAL_ALIGNMENT_RIGHT, 120.0)


func _draw_hud(s: Dictionary) -> void:
	# 一時停止の印
	if _pause_btn.visible:
		var c := PAUSE_RECT.get_center()
		draw_rect(Rect2(c.x - 13, c.y - 16, 9, 32), Kit.C_DIM)
		draw_rect(Rect2(c.x + 4, c.y - 16, 9, 32), Kit.C_DIM)
	var hits: int = s["hits"]
	Kit.text(self, Vector2(696, 66), S.hits_or_unhurt(hits), 28, Kit.C_PLAYER if hits == 0 else Kit.C_TEXT, 700, HORIZONTAL_ALIGNMENT_RIGHT, 300.0)
	if s["drill_id"] != "":
		# 型の練習: 型の名前と、弾いた数。段階とよろけは出さない(溜まらない)
		Kit.text(self, Vector2(134, 66), _drill_name(), 26, Kit.C_TEXT, 700, HORIZONTAL_ALIGNMENT_LEFT, 380.0)
		var sub := S.drill_stats(int(s["parries"]), int(s["justs"]))
		if int(s["speed"]) == B.SLOW_SPEED:
			sub += "  " + S.SPEED_SLOW
		if s["easy"]:
			sub += "  " + S.EASY
		Kit.text(self, Vector2(134, 122), sub, 22, Kit.C_DIM, 500, HORIZONTAL_ALIGNMENT_LEFT, 560.0)
		_draw_guide(s)
		return
	Kit.text(self, Vector2(134, 66), S.boss_of(s["boss"], B.BOSS_COUNT), 28, Kit.C_TEXT, 700, HORIZONTAL_ALIGNMENT_LEFT, 300.0)
	if s["easy"]:
		Kit.text(self, Vector2(246, 66), S.EASY, 22, Kit.C_SPARK, 700, HORIZONTAL_ALIGNMENT_LEFT, 200.0)
	# 段階(残っている体力の数だけ塗る)
	Kit.text(self, Vector2(134, 122), S.PHASE, 22, Kit.C_DIM, 500, HORIZONTAL_ALIGNMENT_LEFT, 100.0)
	var col := Kit.boss_color(s["boss"])
	for i in B.BOSS_HP:
		var d := Kit.ngon(Vector2(206 + i * 32, 114), 12.0, 4)
		if i < int(s["boss_hp"]):
			draw_colored_polygon(d, col)
		else:
			Kit.outline(self, d, Color(Kit.C_DIM, 0.6), 2.0)
	# よろけ(溜まった数だけ塗る)
	Kit.text(self, Vector2(328, 122), S.STAGGER, 22, Kit.C_DIM, 500, HORIZONTAL_ALIGNMENT_LEFT, 100.0)
	var full := int(s["stagger"]) >= B.STAGGER_THRESHOLD
	var pulse := 0.5 + 0.5 * sin(_time * 14.0)
	for i in B.STAGGER_THRESHOLD:
		var r := Rect2(412 + i * 35, 102, 28, 24)
		if i < int(s["stagger"]):
			draw_rect(r, Kit.C_SPARK.lerp(Kit.C_WHITE, 0.6 * pulse) if full else Kit.C_SPARK)
		else:
			draw_rect(r, Color(Kit.C_DIM, 0.5), false, 2.0)
	_draw_guide(s)


# 左右の半分の案内。いつも出す。最初の敵と教える型の間と、型の練習ははっきり、ほかはうすく
func _draw_guide(s: Dictionary) -> void:
	var k := 1.0 if int(s["boss"]) == 1 or s["teaching"] or s["drill_id"] != "" else 0.45
	draw_line(Vector2(360, 1200), Vector2(360, 1272), Color(Kit.C_DIM, 0.5 * k), 2.0)
	Kit.text(self, Vector2(180, 1232), S.DODGE, 28, Color(Kit.C_TEXT, k), 700)
	Kit.text(self, Vector2(180, 1262), S.KEYS_DODGE, 20, Color(Kit.C_DIM, k), 500)
	Kit.text(self, Vector2(540, 1232), S.PARRY, 28, Color(Kit.C_TEXT, k), 700)
	Kit.text(self, Vector2(540, 1262), S.KEYS_PARRY, 20, Color(Kit.C_DIM, k), 500)


# 型の練習の型の名前(「敵 2・段階 3・B」)。
func _drill_name() -> String:
	return S.drill_name(duel.boss, duel.phase, duel.drill_id.get_slice("_", duel.drill_id.get_slice_count("_") - 1).to_upper())
