# レビュー用: 画面の流れと入力を、本物の入力の配り方(root.push_input)で通す。既存のテストは各画面の _input を
# じかに呼ぶので、画面どうしの受け取りの順・ボタンとの重なりは見ていない。print の RV 行が証拠。
extends "res://tests/suite.gd"

const FRAME := 1.0 / 60.0

var _main: Node
var _root: Window


func _boot() -> Node:
	if _main != null and is_instance_valid(_main):
		_main.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.json"))
	_root = Engine.get_main_loop().root
	_main = load("res://ui/main.tscn").instantiate()
	_root.add_child(_main)
	return _main


func _close() -> void:
	_main.free()
	_main = null


# 生きている全部の画面を 1 フレーム進める。
func _tick_all(n: int = 1, delta: float = FRAME) -> void:
	for i in n:
		for c: Node in _main.stage.get_children():
			if not c.is_queued_for_deletion() and c.has_method("_process"):
				c._process(delta)


func _live_names() -> Array:
	var out: Array = []
	for c: Node in _main.stage.get_children():
		if not c.is_queued_for_deletion() and c != _main.view:
			out.append(c.get_script().resource_path.get_file().get_basename())
	return out


func _key(code: Key, pressed: bool = true) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = pressed
	return e


func _mouse(x: float, y: float, pressed: bool, button: MouseButton = MOUSE_BUTTON_LEFT) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = pressed
	e.position = _main.stage.global_position + Vector2(x, y)
	e.global_position = e.position
	return e


# 本物の配り方で入力を 1 つ渡す。座標は、もうビューポートの中の値なので、そのまま渡す(true)。
# 窓なしのテストはフレームの終わりが来ないので、queue_free された画面をここで本当に消す(本物では次のフレームには居ない)。
func _push(e: InputEvent) -> void:
	_flush()
	_root.push_input(e, true)
	_flush()


func _flush() -> void:
	for c: Node in _main.stage.get_children():
		if c.is_queued_for_deletion():
			c.free()


func _click(x: float, y: float) -> void:
	_push(_mouse(x, y, true))
	_push(_mouse(x, y, false))


func _log_types(view: Node) -> Array:
	return view.event_log.map(func(row: Array) -> String: return row[1]).filter(func(t: String) -> bool: return t != "attack_start" and t != "pattern_start")


# ---- タイトルのスペースが、対戦の「弾く」にも入らないか ----

func test_review_title_space_does_not_leak_into_duel() -> bool:
	_boot()
	_tick_all(30)
	_push(_key(KEY_SPACE))
	eq(_main.screen_name, "duel", "スペースで いつもの3連戦")
	_tick_all(3)
	print("RV タイトルのスペース: 対戦の出来事 = %s  lock=%d" % [_log_types(_main.view), _main.view.duel.lock])
	eq(_main.view.duel.lock, 0, "始めたスペースが空振りになっていない")
	_close()
	return true


# ---- Esc: 一時停止 → 続ける が、同じ 1 回の押しで往復しないか ----

func test_review_esc_round_trip() -> bool:
	_boot()
	_main.start_run(Duel.Mode.FIXED)
	_tick_all(10)
	_push(_key(KEY_ESCAPE))
	eq(_main.screen_name, "pause", "Esc で一時停止")
	ok(_main.view.paused, "止まっている")
	_tick_all(2)
	_push(_key(KEY_ESCAPE))
	eq(_main.screen_name, "duel", "もう一度 Esc で続ける")
	ok(_main.view.resume_left > 0.9, "1 秒の待ち")
	# 待ちの間にもう一度 Esc → また一時停止(行き止まりにならない)
	_tick_all(10)
	_push(_key(KEY_ESCAPE))
	eq(_main.screen_name, "pause", "待ちの間の Esc で、また一時停止")
	eq(_live_names(), ["pause"], "一時停止の画面は 1 つだけ")
	_tick_all(2)
	_push(_key(KEY_ESCAPE))
	ok(_main.view.resume_left > 0.9, "待ちは最初から数え直す")
	_close()
	return true


# ---- 押した直後(同じフレーム)に一時停止になった入力が、再開の後に出てこないか ----

func test_review_press_just_before_pause_is_replayed_after_resume() -> bool:
	_boot()
	_main.start_run(Duel.Mode.FIXED)
	_tick_all(10)
	var tick: int = _main.view.duel.tick
	_push(_key(KEY_SPACE))  # このフレームの step の前に…
	_push(_key(KEY_ESCAPE))  # …一時停止
	ok(_main.view.paused, "一時停止")
	_tick_all(120)
	eq(_main.view.duel.tick, tick, "止まっている")
	_main.resume()
	_tick_all(61)
	var got := _log_types(_main.view)
	print("RV 一時停止の直前の押し: 再開の後の出来事 = %s  lock=%d" % [got, _main.view.duel.lock])
	ok(not got.has("parry_whiff"), "一時停止の直前の押しは、再開の後に使わない")
	eq(_main.view.duel.lock, 0, "硬直も残らない")
	_close()
	return true


func test_review_press_then_long_frame_is_replayed() -> bool:
	# 同じことが「長い 1 フレーム → 自動の一時停止」(E-10)でも起きるか
	_boot()
	_main.start_run(Duel.Mode.FIXED)
	_tick_all(10)
	_push(_key(KEY_Z))
	_main.view._process(0.4)  # 0.25 秒より長い 1 フレーム
	ok(_main.view.paused, "自動で一時停止")
	_main.resume()
	_tick_all(61)
	var got := _log_types(_main.view)
	print("RV 長いフレームの直前の押し: 再開の後の出来事 = %s" % [got])
	ok(not got.has("dodge"), "止まる前の押しは、再開の後に使わない")
	_close()
	return true


# ---- 一時停止ボタン・負けのボタン・マウスのほかのボタン ----

func test_review_pause_button_click_is_not_a_dodge() -> bool:
	_boot()
	_main.start_run(Duel.Mode.FIXED)
	_tick_all(10)
	_click(68, 68)
	eq(_main.screen_name, "pause", "一時停止ボタンを押すと一時停止")
	_main.resume()
	_tick_all(62)
	eq(_log_types(_main.view), [], "ボタンの上の押しは 避ける にならない")
	# 右ボタン・中ボタンは入力にしない
	_push(_mouse(500, 700, true, MOUSE_BUTTON_RIGHT))
	_push(_mouse(100, 700, true, MOUSE_BUTTON_MIDDLE))
	_tick_all(2)
	eq(_log_types(_main.view), [], "右ボタン・中ボタンは入力にしない")
	# ボタンのすぐ外(113, 68)は左半分 = 避ける
	_push(_mouse(113, 68, true))
	_tick_all(1)
	eq(_log_types(_main.view), ["dodge"], "ボタンのすぐ右は 避ける")
	_close()
	return true


func _lose(view: Node) -> void:
	view.duel.teach_done[0] = true
	view.duel._seq.teach_cleared()
	for i in 4000:
		if view._lose_box.visible:
			break
		view._process(FRAME)


func test_review_lose_box_buttons_by_real_click() -> bool:
	_boot()
	_main.start_run(Duel.Mode.FIXED)
	var view: Node = _main.view
	_lose(view)
	ok(view._lose_box.visible, "負けの 2 つのボタン")
	# 負けた後の Esc・スペース・タブが裏、では何も起きない
	_push(_key(KEY_ESCAPE))
	_push(_key(KEY_SPACE))
	_main.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	eq(_main.screen_name, "duel", "負けの画面のまま")
	ok(not view.paused, "一時停止にならない")
	_click(360, 660)  # この敵からやり直す
	_flush()
	ok(not view._lose_box.visible and not view.duel.over, "やり直しが始まる")
	eq(view.duel.retries, 1, "やり直し 1")
	var before: int = view._seq
	_tick_all(3)
	eq([view._seq, view.duel.lock], [before, 0], "ボタンを押した所(x=360)が 弾く にならない")
	eq(view._fx._items.size(), 0, "暗い幕が残らない")
	_lose(view)
	_click(360, 808)  # タイトルへ
	eq(_main.screen_name, "title", "タイトルへ")
	eq(_live_names(), ["title"], "タイトルだけ")
	eq(_main.save.fixed_best(), null, "記録は残らない")
	_close()
	return true


# ---- 一時停止からタイトルへ戻った後に、前の対戦が残らないか ----

func test_review_pause_to_title_leaves_nothing() -> bool:
	_boot()
	_main.start_run(Duel.Mode.DAILY)
	var view: Node = _main.view
	_tick_all(200)
	_push(_key(KEY_ESCAPE))
	_main.open_settings()
	_main.open_calib()
	eq(_live_names(), ["pause", "settings", "calib_view"], "一時停止 → 設定 → タイミング合わせ が重なる")
	_main.open_settings()
	_main.open_calib()
	eq(_live_names().size(), 3, "二重に開かない")
	_push(_key(KEY_ESCAPE))
	eq(_main.screen_name, "settings", "タイミング合わせの Esc は設定へ戻る")
	_tick_all(1)
	_push(_key(KEY_ESCAPE))
	eq(_main.screen_name, "pause", "設定の Esc は一時停止へ戻る")
	ok(view.paused, "まだ止まっている(設定の Esc で続けてしまわない)")
	_main.go_title()
	eq(_main.screen_name, "title", "タイトル")
	eq(_live_names(), ["title"], "タイトルだけが残る")
	ok(view.duel == null and not view.visible, "対戦は捨てられる")
	# タイトルで Esc・タブが裏 → 何も起きない
	_push(_key(KEY_ESCAPE))
	_main.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	eq(_main.screen_name, "title", "タイトルのまま")
	# 次の対戦は、最初から
	_main.start_run(Duel.Mode.FIXED)
	ok(not view.paused and view.resume_left == 0.0, "一時停止が残っていない")
	eq([view.duel.tick, view.duel.hits, view.duel.mode], [0, 0, Duel.Mode.FIXED], "新しい対戦")
	_tick_all(5)
	eq(view.duel.tick, 10, "すぐ進む")
	_close()
	return true


# ---- 敵を倒した後の 1.5 秒(割れる動き)の間の一時停止 ----

func _auto(view: Node, frames: int, until: Callable) -> void:
	var done := {}
	for f in frames:
		if until.call():
			return
		var d: Duel = view.duel
		if view.is_playing() and not view.paused:
			if d.state == Duel.State.STAGGER:
				view._input(_key(KEY_SPACE))
			for a: Dictionary in d.snapshot()["attacks"]:
				if done.has(a["id"]):
					continue
				if a["kind"] == "white" and d.tick >= a["contact"] - 2:
					done[a["id"]] = true
					view._input(_key(KEY_X))
				elif a["kind"] == "red" and d.tick >= a["contact"] - 12:
					done[a["id"]] = true
					view._input(_key(KEY_Z))
		view._process(FRAME)


func test_review_pause_during_boss_down_animation() -> bool:
	_boot()
	_main.start_run(Duel.Mode.FIXED)
	var view: Node = _main.view
	_auto(view, 6000, func() -> bool: return view.duel.state == Duel.State.WAIT_NEXT)
	eq(view.duel.state, Duel.State.WAIT_NEXT, "敵 1 を倒した")
	_tick_all(5)
	_push(_key(KEY_ESCAPE))
	print("RV 割れる動きの間の Esc: screen=%s paused=%s  一時停止ボタンは見えている=%s" % [_main.screen_name, view.paused, view._pause_btn.visible])
	_click(68, 68)
	print("RV 割れる動きの間に一時停止ボタン: screen=%s paused=%s" % [_main.screen_name, view.paused])
	if view.paused:
		_main.resume()
	for i in 400:
		if _main.screen_name == "interval":
			break
		view._process(FRAME)
	eq(_main.screen_name, "interval", "(続けると)合間へ進む。行き止まりにならない")
	_tick_all(3)
	# 合間: 500 ms の前のスペースは効かない。タブが裏でも何も起きない
	_push(_key(KEY_SPACE))
	eq(_main.screen_name, "interval", "入ってすぐのスペースは効かない")
	_main.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	ok(not view.paused, "合間でタブが裏に回っても、一時停止にしない")
	_tick_all(40)
	_push(_key(KEY_SPACE))
	eq(_main.screen_name, "duel", "500 ms の後のスペースで次の敵へ")
	eq(view.duel.boss, 2, "敵 2")
	_tick_all(3)
	eq(view.duel.lock, 0, "進めたスペースが空振りになっていない")
	ok(not view.paused, "止まっていない")
	_close()
	return true


# ---- 練習: 負け → 結果 → もう1回 ----

func test_review_practice_lose_then_again() -> bool:
	_boot()
	_main.save.reach(2)
	_main.start_practice(2)
	var view: Node = _main.view
	view.duel.teach_done[1] = true
	view.duel._seq.teach_cleared()
	for i in 4000:
		if _main.screen_name == "result":
			break
		_tick_all(1)
	eq(_main.screen_name, "result", "練習の負けは結果へ(負けのボタンは出ない)")
	ok(not view._lose_box.visible, "負けのボタンは出ていない")
	eq(_live_names(), ["result"], "結果だけ")
	_tick_all(30)
	_push(_key(KEY_ENTER))
	eq(_main.screen_name, "duel", "Enter で もう1回")
	eq([view.duel.mode, view.duel.boss, view.duel.hits, view.duel.retries, view.duel.player_hp], [Duel.Mode.PRACTICE, 2, 0, 0, 5], "同じ敵の練習が最初から")
	eq(_main.save.reached_boss(), 2, "着いた敵は変わらない")
	ok(not FileAccess.file_exists("user://save.json") or _main.save.fixed_best() == null, "記録は書かれない")
	_close()
	return true


# ---- 再開の待ちの間にタブが裏に回る ----

func test_review_tab_hidden_during_resume_wait() -> bool:
	_boot()
	_main.start_run(Duel.Mode.FIXED)
	var view: Node = _main.view
	_tick_all(30)
	_main.pause()
	_main.resume()
	_tick_all(20)
	var tick: int = view.duel.tick
	_main.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	print("RV 再開の待ちの間にタブが裏: screen=%s paused=%s" % [_main.screen_name, view.paused])
	ok(view.paused, "また一時停止になる")
	view._process(5.0)  # 戻ってきた最初の長いフレーム
	_tick_all(120)
	eq(view.duel.tick, tick, "戻っても進まない")
	# 待ちの間に、長い 1 フレームだけが来た時(通知が来ないブラウザ)
	_main.resume()
	_tick_all(10)
	view._process(5.0)
	print("RV 再開の待ちの間に 5 秒のフレームだけが来た: paused=%s resume_left=%s tick=%d(前 %d)" % [view.paused, view.resume_left, view.duel.tick, tick])
	_tick_all(2)
	print("RV その 2 フレーム後: paused=%s tick=%d" % [view.paused, view.duel.tick])
	_close()
	return true


# ---- 最初の操作まで音を鳴らさない(FR-29)が、本物の配り方で効いているか ----

func test_review_sfx_unlocks_on_first_input() -> bool:
	Sfx.unlocked = false
	_boot()
	_tick_all(30)
	ok(not Sfx.unlocked, "何も押すまでは鳴らさない")
	_push(_key(KEY_SPACE, false))  # 離しただけ
	ok(not Sfx.unlocked, "キーを離しただけでは開かない")
	_push(_mouse(360, 40, true))
	ok(Sfx.unlocked, "最初の押しで開く")
	_close()
	return true


# ---- 結果: 今日の3連戦の 1 回目・2 回目、日付をまたいだ時 ----

func test_review_daily_first_and_date_kept() -> bool:
	_boot()
	_main.start_run(Duel.Mode.DAILY)
	var view: Node = _main.view
	# 始めた日を、きのうにする(遊んでいる間に日付が変わった。E-19)
	var today: Dictionary = _main.today()
	_main.run["day"] = int(today["day"]) - 1
	_main.run["date"] = "2026-01-01"
	view.duel.boss = 3
	view.duel.phase = 3
	view.duel.boss_hp = 1
	view.duel.hits = 2
	view.duel.state = Duel.State.STAGGER
	view.duel.state_until = view.duel.tick + 100
	view._input(_key(KEY_SPACE))
	for i in 300:
		_tick_all(1)
		if _main.screen_name == "result":
			break
	eq(_main.screen_name, "result", "結果")
	var d: Dictionary = _main.save.data["daily"]
	eq(d["day"], int(today["day"]) - 1, "保存は始めた日の物(E-19)")
	var box: Node = _main._screen.find_child("share_box", true, false)
	ok(box != null and (box.text as String).begins_with("ParryDuel 2026-01-01(今日の3連戦・1回目)"), "共有する文字も始めた日・1回目")
	# タイトルに戻ると、今日はまだ遊んでいない
	_main.go_title()
	var labels: Array = _main._screen.find_children("*", "Label", true, false).map(func(l: Label) -> String: return l.text)
	ok(labels.has("まだ遊んでいない"), "今日の欄は「まだ遊んでいない」")
	_close()
	return true
