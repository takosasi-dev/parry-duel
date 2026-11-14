# 対戦画面(ui/duel_view.gd)と画面の切り替え(ui/main.gd)を、窓なしで手で 1 フレームずつ進めて確かめる。
# 入力の受け方(FR-2・E-1・E-20)、一時停止と再開(FR-27・AC-29・E-9〜E-11)、敵を倒した後・負けた後の流れ。
extends "res://tests/suite.gd"

const FRAME := 1.0 / 60.0

var _main: Node


func _open(mode: int = Duel.Mode.FIXED, boss: int = 1) -> Node:
	var save_path := ProjectSettings.globalize_path("user://save.json")
	if FileAccess.file_exists("user://save.json"):
		DirAccess.remove_absolute(save_path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save_ext.json"))
	_main = load("res://ui/main.tscn").instantiate()
	Engine.get_main_loop().root.add_child(_main)
	if mode == Duel.Mode.PRACTICE:
		_main.save.reach(3)
		_main.start_practice(boss)
	else:
		_main.start_run(mode)
	return _main.view


func _close() -> void:
	_main.free()
	_main = null


func _frames(view: Node, n: int) -> void:
	for i in n:
		view._process(FRAME)


func _key(code: Key, echo: bool = false, location: KeyLocation = KEY_LOCATION_UNSPECIFIED) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = true
	e.echo = echo
	e.location = location
	return e


func _click(x: float, y: float, device: int = 0) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = _main.stage.global_position + Vector2(x, y)  # ゲームの座標 → ビューポートの座標
	e.device = device
	return e


func _touch(x: float, y: float, index: int = 0) -> InputEventScreenTouch:
	var e := InputEventScreenTouch.new()
	e.pressed = true
	e.index = index
	e.position = _main.stage.global_position + Vector2(x, y)
	return e


# 入力を 1 つ渡して 1 フレーム進め、そのフレームに起きた出来事の type を返す。
func _send(view: Node, events: Array) -> Array:
	var before: int = view.event_log.size()
	var last: int = view.event_log[before - 1][0] if before > 0 else 0
	for e: InputEvent in events:
		view._input(e)
	view._process(FRAME)
	var out: Array = []
	for row: Array in view.event_log:
		if row[0] > last and row[1] != "attack_start" and row[1] != "pattern_start":
			out.append(row[1])
	return out


# 空振りの硬直が明けるまで進める。
func _settle(view: Node) -> void:
	_frames(view, 30)


func test_keys_map_to_parry_and_dodge() -> bool:
	var view := _open()
	eq(_send(view, [_key(KEY_SPACE)]), ["parry_whiff"], "スペース = 弾く")
	_settle(view)
	eq(_send(view, [_key(KEY_X)]), ["parry_whiff"], "X = 弾く")
	_settle(view)
	eq(_send(view, [_key(KEY_Z)]), ["dodge"], "Z = 避ける")
	_settle(view)
	eq(_send(view, [_key(KEY_SHIFT, false, KEY_LOCATION_LEFT)]), ["dodge"], "左シフト = 避ける")
	_settle(view)
	eq(_send(view, [_key(KEY_SHIFT, false, KEY_LOCATION_RIGHT)]), [], "右シフトは何もしない")
	eq(_send(view, [_key(KEY_SPACE, true)]), [], "押しっぱなしのくり返しは見ない")
	eq(_send(view, [_key(KEY_A)]), [], "ほかのキーは何もしない")
	_close()
	return true


func test_pointer_halves() -> bool:
	var view := _open()
	eq(_send(view, [_click(360, 700)]), ["parry_whiff"], "x 360 は弾く")
	_settle(view)
	eq(_send(view, [_click(359, 700)]), ["dodge"], "x 359 は避ける")
	_settle(view)
	eq(_send(view, [_click(5000, 700)]), ["parry_whiff"], "右の余りは弾く(E-20)")
	_settle(view)
	eq(_send(view, [_click(-300, 700)]), ["dodge"], "左の余りは避ける(E-20)")
	_settle(view)
	eq(_send(view, [_click(60, 60)]), [], "一時停止ボタンの上は入力にしない")
	var right := _click(600, 700)
	right.button_index = MOUSE_BUTTON_RIGHT
	eq(_send(view, [right]), [], "右ボタンは使わない")
	_close()
	return true


func test_touch_is_not_counted_twice() -> bool:
	var view := _open()
	# タッチは、模擬のマウス(device −1)としても届く。数えるのはタッチだけ
	eq(_send(view, [_touch(600, 900), _click(600, 900, InputEvent.DEVICE_ID_EMULATION)]), ["parry_whiff"], "タップ 1 回は 1 回")
	_frames(view, 3)
	eq(view.duel.lock, B.WHIFF_LOCK - 8, "硬直は 1 回ぶん(2 回目で延びていない)")
	_close()
	return true


func test_two_thumbs_same_frame_parry_wins() -> bool:
	var view := _open()
	eq(_send(view, [_touch(100, 900, 0), _touch(600, 900, 1)]), ["parry_whiff"], "同じフレームの左右は、弾くだけを使う(E-1)")
	_settle(view)
	eq(_send(view, [_touch(100, 900, 0)]), ["dodge"], "別のフレームなら、それぞれ別の入力")
	_close()
	return true


func test_pause_stops_ticks_and_resume_waits() -> bool:
	var view := _open()
	_frames(view, 30)
	var tick: int = view.duel.tick
	eq(tick, 60, "30 フレームで 60 tick")
	view._input(_key(KEY_ESCAPE))
	ok(view.paused, "Esc で一時停止")
	eq(_main.screen_name, "pause", "一時停止の画面")
	_frames(view, 60)
	eq(view.duel.tick, tick, "一時停止の間は tick が進まない")
	eq(_send(view, [_key(KEY_SPACE)]), [], "一時停止の間の入力は捨てる")
	_main.resume()
	ok(not view.paused and view.resume_left > 0.99, "続けるの後、1 秒の待ち")
	_frames(view, 59)
	eq(view.duel.tick, tick, "待ちの間は tick が進まない(AC-29)")
	eq(_send(view, [_key(KEY_SPACE)]), [], "待ちの間の入力は捨てる(E-9)")
	_frames(view, 2)
	ok(view.duel.tick > tick, "1 秒たつと進む")
	eq(view.duel.lock, 0, "待ちの間の押しは残っていない")
	_close()
	return true


func test_long_frame_pauses() -> bool:
	var view := _open()
	_frames(view, 10)
	var tick: int = view.duel.tick
	view._process(2.0)
	ok(view.paused, "長い 1 フレーム(裏にいた)は一時停止にする(E-10)")
	eq(view.duel.tick, tick, "裏にいた間は進めない")
	_close()
	return true


func test_focus_out_pauses() -> bool:
	var view := _open()
	_frames(view, 10)
	_main.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	ok(view.paused, "ウィンドウが裏に回った通知で一時停止")
	_main.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	ok(view.paused, "戻っても自動では再開しない")
	_close()
	return true


func test_slow_frames_drop_ticks() -> bool:
	var view := _open()
	view._process(0.2)
	eq(view.duel.tick, B.MAX_STEPS_PER_FRAME, "1 フレームに進めるのは 8 tick まで(E-11)")
	view._process(0.1)
	eq(view.duel.tick, B.MAX_STEPS_PER_FRAME * 2, "超えた分は捨てる(ためない)")
	_close()
	return true


# 自動で押しながら進める。until が真になるか frames に届くまで。
func _auto(view: Node, frames: int, until: Callable) -> void:
	var done := {}
	for i in frames:
		if until.call():
			return
		var d: Duel = view.duel
		if d.state == Duel.State.STAGGER:
			view._input(_key(KEY_SPACE))
		else:
			for a: Dictionary in d.snapshot()["attacks"]:
				if done.has(a["id"]):
					continue
				if a["kind"] == "white" and d.tick >= a["contact"] - 1:
					done[a["id"]] = true
					view._input(_key(KEY_SPACE))
				elif a["kind"] == "red" and d.tick >= a["contact"] - 12:
					done[a["id"]] = true
					view._input(_key(KEY_Z))
		view._process(FRAME)


func test_boss_down_leads_to_interval_then_next() -> bool:
	var view := _open()
	_auto(view, 4000, func() -> bool: return _main.screen_name == "interval")
	eq(_main.screen_name, "interval", "敵 1 を倒すと合間へ")
	ok(view._boss_gone, "割れる動きが始まっている")
	ok(not view.visible, "対戦画面は隠れる")
	eq(view.duel.hits, 0, "キーの入力だけで無傷")
	var tick: int = view.duel.tick
	_frames(view, 30)
	eq(view.duel.tick, tick, "合間の間は時間を数えない")
	_main.next_boss()
	eq(_main.screen_name, "duel", "次の敵へ")
	eq(view.duel.boss, 2, "敵 2")
	eq(_main.save.reached_boss(), 2, "着いた敵を保存する")
	ok(view.visible and not view._boss_gone, "敵がまた見える")
	_close()
	return true


func test_practice_win_goes_to_result_without_record() -> bool:
	var view := _open(Duel.Mode.PRACTICE, 2)
	_auto(view, 4000, func() -> bool: return _main.screen_name == "result")
	eq(_main.screen_name, "result", "練習は、選んだ敵を倒すと結果へ")
	eq(_main.save.fixed_best(), null, "記録に残さない(E-14)")
	_close()
	return true


func test_lose_shows_retry_and_carries() -> bool:
	var view := _open()
	view.duel.teach_done[0] = true  # 教える型を飛ばして、すぐ当たるようにする
	view.duel._seq.teach_cleared()
	for i in 3000:
		if view._lose_box.visible:
			break
		view._process(FRAME)
	ok(view._lose_box.visible, "負けると 2 つのボタンが出る")
	ok(view.duel.over and not view.duel.won, "負け")
	var hits: int = view.duel.hits
	var ticks: int = view.duel.time_ticks()
	eq(hits, 5, "受けた数 5")
	view._input(_key(KEY_R))
	ok(not view._lose_box.visible, "R でやり直す")
	eq(view.duel.hits, hits, "受けた数を引き継ぐ")
	eq(view.duel.time_ticks(), ticks, "時間を引き継ぐ")
	eq(view.duel.retries, 1, "やり直しの回数 +1")
	eq(view.duel.player_hp, 5, "体力 5")
	eq(_main.save.fixed_best(), null, "負けた回は記録に残さない")
	_close()
	return true


func test_full_run_records_best() -> bool:
	var view := _open()
	for boss in 3:
		_auto(view, 6000, func() -> bool: return _main.screen_name != "duel")
		if _main.screen_name == "interval":
			_main.next_boss()
	eq(_main.screen_name, "result", "3 体を倒すと結果へ")
	var best: Variant = _main.save.fixed_best()
	ok(best is Dictionary, "いつもの3連戦の最高が残る")
	if best is Dictionary:
		eq(best["hits"], 0, "無傷")
		eq(best["ticks"], view.duel.time_ticks(), "時間")
	_close()
	return true


func test_settings_reach_the_duel() -> bool:
	var view := _open()
	_main.save.set_setting("offset_ticks", 7)
	_main.save.set_setting("shake", false)
	_main.settings_changed()
	eq(view.duel.offset, 7, "判定のずれが対戦に入る")
	ok(not view._fx.shake_enabled, "揺れを切ると fx に伝わる")
	view._fx.shake(10.0, 150.0)
	eq(view._fx.shake_offset(), Vector2.ZERO, "揺れを切ると画面の位置が動かない(NFR-12)")
	_close()
	return true


func test_auto_player_run_is_not_saved() -> bool:
	# デバッグ用の自動の相手(?auto=1)の回は、最高にも着いた敵にも残さない
	var view := _open()
	var debug: Node = load("res://ui/debug.gd").new()
	debug.main = _main
	_main.stage.add_child(debug)
	debug.auto = true
	_main.debug = debug
	for boss in 3:
		_auto(view, 6000, func() -> bool: return _main.screen_name != "duel")
		if _main.screen_name == "interval":
			_main.next_boss()
	eq(_main.screen_name, "result", "最後まで進む")
	eq(_main.save.fixed_best(), null, "最高に残さない")
	eq(_main.save.reached_boss(), 1, "着いた敵にも残さない")
	_close()
	return true


func test_long_frame_during_resume_wait_pauses_again() -> bool:
	var view := _open()
	_frames(view, 10)
	_main.pause()
	_main.resume()
	_frames(view, 10)
	var tick: int = view.duel.tick
	view._process(2.0)  # 待ちの間に裏へ回った
	ok(view.paused, "待ちを終わらせず、一時停止に戻る")
	eq(view.duel.tick, tick, "tick は進まない")
	_close()
	return true


func test_press_before_pause_is_dropped() -> bool:
	var view := _open()
	_frames(view, 10)
	view._input(_key(KEY_SPACE))
	view._input(_key(KEY_ESCAPE))
	ok(view.paused, "一時停止")
	_main.resume()
	_frames(view, 62)
	eq(view.duel.lock, 0, "止まる直前の押しは、再開の後に使わない")
	_close()
	return true
