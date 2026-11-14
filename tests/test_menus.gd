# メニューの 5 画面(タイトル・合間・結果・設定・一時停止)。本体(ui/main.tscn)を作って、ボタンを押してたどる。
# ランナーは同期なので、待ち時間は画面の _process(秒) をじかに呼んで進める。queue_free された古い画面は残るので、生きている物だけを探す。
extends "res://tests/suite.gd"

const Rank := preload("res://core/rank.gd")
const S := preload("res://core/strings.gd")
const ShareText := preload("res://core/share_text.gd")
const SaveStore := preload("res://save/save_store.gd")
const Kit := preload("res://ui/kit.gd")
const Title := preload("res://ui/title.gd")
const Result := preload("res://ui/result.gd")

const SCREEN_FILES := ["title", "interval", "result", "settings", "pause"]
const ENTRIES := ["btn_fixed", "btn_daily", "btn_practice_1", "btn_practice_2", "btn_practice_3"]

var _last: Node = null


# 保存を消して、本体を作る。タイトルが開く。
func _boot() -> Node:
	if _last != null and is_instance_valid(_last):
		_last.free()  # 前のテストが途中で止まった時の残り
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.json"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save_ext.json"))
	var main: Node = load("res://ui/main.tscn").instantiate()
	Engine.get_main_loop().root.add_child(main)
	_last = main
	return main


# 生きている画面を、上から順に。
func _live(main: Node) -> Array:
	var out: Array = main.stage.get_children().filter(func(c: Node) -> bool: return not c.is_queued_for_deletion())
	out.reverse()
	return out


func _btn(main: Node, node_name: String) -> Button:
	for c: Node in _live(main):
		var b := c.find_child(node_name, true, false)
		if b is Button:
			return b
	return null


func _press(main: Node, node_name: String) -> void:
	var b := _btn(main, node_name)
	ok(b != null, "%s がある" % node_name)
	if b != null:
		b.pressed.emit()


func _all(node: Node, type: Variant, out: Array = []) -> Array:
	for c: Node in node.get_children():
		if c is CanvasItem and not c.visible:
			continue
		if is_instance_of(c, type):
			out.append(c)
		_all(c, type, out)
	return out


# 画面に見えている Label の文言。
func _texts(screen: Node) -> Array:
	return _all(screen, Label).map(func(l: Label) -> String: return l.text)


func _label(screen: Node, text: String) -> Label:
	for l: Label in _all(screen, Label):
		if l.text == text:
			return l
	return null


# 合間・結果を、決めた info で開く。
func _show(main: Node, key: String, info: Dictionary) -> Control:
	main._clear_screens()
	main.view.visible = false
	main.screen_name = key
	main._screen = main._open(key, info)
	return main._screen


func _key(code: int, echo: bool = false) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code as Key
	e.pressed = true
	e.echo = echo
	return e


func _result_info(hits: int, ticks: int, record: Dictionary, mode: int = Duel.Mode.FIXED, won: bool = true, boss: int = 3) -> Dictionary:
	var r := {"won": won, "mode": mode, "boss": boss, "hits": hits, "ticks": ticks, "justs": 21, "parries": 60, "retries": 1}
	var practice := mode == Duel.Mode.PRACTICE
	return {"result": r, "mode": mode, "practice": practice, "date": "2026-11-12", "record": record,
		"share_text": "" if practice else ShareText.build("2026-11-12", mode, record["first_today"], r)}


func _record(prev: Variant, new_best: bool, saved: bool = true) -> Dictionary:
	return {"prev_best": prev, "new_best": new_best, "first_today": false, "saved": saved}


# ---- タイトル ----

func test_title_entries_lead_to_duel_and_settings() -> bool:
	var main := _boot()
	eq(main.screen_name, "title", "タイトルが開く")
	_press(main, "btn_fixed")
	eq(main.screen_name, "duel", "いつもの3連戦で対戦へ")
	eq(main.run["mode"], Duel.Mode.FIXED, "いつもの3連戦")
	main.go_title()
	_press(main, "btn_daily")
	eq(main.screen_name, "duel", "今日の3連戦で対戦へ")
	eq(main.run["mode"], Duel.Mode.DAILY, "今日の3連戦")
	main.go_title()
	_press(main, "btn_practice_1")
	eq(main.screen_name, "duel", "練習で対戦へ")
	eq(main.run["mode"], Duel.Mode.PRACTICE, "練習")
	main.go_title()
	_press(main, "btn_settings")
	eq(main.screen_name, "settings", "設定へ")
	ok(main._settings != null and _texts(main._settings).has(S.SETTINGS), "設定の画面が出る")
	main.free()
	return true


func test_title_shows_tagline_version_and_no_record() -> bool:
	var main := _boot()
	var t := _texts(main._screen)
	for want: String in [S.GAME_NAME, S.TAGLINE, S.VERSION, S.NOT_PLAYED, S.BTN_PRACTICE, S.boss_n(1), S.boss_n(3), main.today()["date"]]:
		ok(t.has(want), "「%s」が出る" % want)
	ok(not t.has(S.SAVE_BROKEN) and not t.has(S.DATA_BROKEN), "失敗の行は出ない")
	eq(_btn(main, "btn_fixed").text, S.BTN_FIXED, "入口の文言")
	eq(_btn(main, "btn_daily").text, S.BTN_DAILY, "入口の文言")
	main.free()
	return true


func test_title_shows_records() -> bool:
	var main := _boot()
	var day: int = main.today()["day"]
	main.save.record_win(Duel.Mode.FIXED, day, {"hits": 2, "ticks": 18504, "justs": 21, "retries": 0})
	main.save.record_win(Duel.Mode.DAILY, day, {"hits": 4, "ticks": 20000, "justs": 3, "retries": 1})
	main.save.record_win(Duel.Mode.DAILY, day, {"hits": 0, "ticks": 19000, "justs": 30, "retries": 0})
	main.go_title()
	var t := _texts(main._screen)
	ok(t.has(S.best_line(2, "154.2")), "いつもの最高が出る: %s" % [t])
	ok(t.has(S.daily_line(4, 0)), "1 回目と今日の最高が出る")
	ok(S.daily_line(4, 0).contains(S.UNHURT), "受けた数 0 は「無傷」")
	ok(not t.has(S.NOT_PLAYED), "「まだ遊んでいない」は消える")
	main.free()
	return true


func test_title_data_broken_blocks_entries() -> bool:
	var main := _boot()
	main.data_ok = false
	main.save.load_failed = true
	main.go_title()
	for n: String in ENTRIES:
		ok(_btn(main, n).disabled, "%s は押せない" % n)
		_btn(main, n).pressed.emit()
		eq(main.screen_name, "title", "%s を押しても進まない" % n)
	main._screen._input(_key(KEY_ENTER))
	eq(main.screen_name, "title", "Enter でも進まない")
	ok(not _btn(main, "btn_settings").disabled, "設定は押せる")
	var t := _texts(main._screen)
	ok(t.has(S.DATA_BROKEN), "「型のデータが壊れている」が出る(E-17)")
	ok(t.has(S.SAVE_BROKEN), "「保存を読めなかった…」が出る(E-15)")
	main.free()
	return true


func test_title_practice_only_reached_bosses() -> bool:
	var main := _boot()
	ok(not _btn(main, "btn_practice_1").disabled, "敵 1 は初めから押せる")
	ok(_btn(main, "btn_practice_2").disabled and _btn(main, "btn_practice_3").disabled, "着いていない敵は押せない")
	_btn(main, "btn_practice_3").pressed.emit()
	eq(main.screen_name, "title", "押しても始まらない")
	main.save.reach(2)
	main.go_title()
	ok(not _btn(main, "btn_practice_2").disabled, "敵 2 に着いたら押せる")
	ok(_btn(main, "btn_practice_3").disabled, "敵 3 はまだ")
	_press(main, "btn_practice_2")
	eq(main.screen_name, "duel", "練習が始まる")
	eq(main.view.duel.boss, 2, "敵 2 と戦う")
	eq(main.view.duel.mode, Duel.Mode.PRACTICE, "練習")
	main.free()
	return true


func test_title_keys() -> bool:
	var main := _boot()
	main._screen._input(_key(KEY_ENTER, true))
	eq(main.screen_name, "title", "押しっぱなしのくり返しでは始まらない")
	main._screen._input(_key(KEY_Z))
	eq(main.screen_name, "title", "ほかのキーでは始まらない")
	main._screen._input(_key(KEY_SPACE))
	eq(main.screen_name, "duel", "スペースで いつもの3連戦")
	eq(main.run["mode"], Duel.Mode.FIXED, "いつもの3連戦")
	main.go_title()
	_press(main, "btn_settings")
	main._screen._input(_key(KEY_ENTER))
	eq(main.screen_name, "settings", "設定が上にある間は、タイトルはキーを受けない")
	main.free()
	return true


# ---- 設定 ----

func test_settings_values_are_saved() -> bool:
	var main := _boot()
	_press(main, "btn_settings")
	ok(_btn(main, "btn_vol_75").get_meta("on"), "初めは 75 が選ばれている")
	for v: int in [0, 25, 50, 100]:
		_press(main, "btn_vol_%d" % v)
		eq(main.save.settings()["volume"], v, "音量")
		ok(_btn(main, "btn_vol_%d" % v).get_meta("on"), "選んだ音量が選ばれた見た目")
		eq(_btn(main, "btn_vol_%d" % v).get_theme_stylebox("normal").bg_color, Kit.C_TEXT, "塗りつぶしになる")
		ok(not _btn(main, "btn_vol_75").get_meta("on"), "ほかは外れる")
	_press(main, "btn_shake_off")
	eq(main.save.settings()["shake"], false, "揺れ 切")
	ok(_btn(main, "btn_shake_off").get_meta("on") and not _btn(main, "btn_shake_on").get_meta("on"), "切 が選ばれた見た目")
	_press(main, "btn_flash_on")
	eq(main.save.settings()["reduce_flash"], true, "点滅を弱める 入")
	_press(main, "btn_offset_plus")
	var disk: Dictionary = SaveStore.new().settings()
	eq(disk["volume"], 100, "保存に入る: 音量")
	eq(disk["shake"], false, "保存に入る: 揺れ")
	eq(disk["reduce_flash"], true, "保存に入る: 点滅")
	eq(disk["offset_ticks"], 1, "保存に入る: ずれ")
	_press(main, "btn_shake_on")
	_press(main, "btn_flash_off")
	eq(main.save.settings()["shake"], true, "揺れ 入")
	eq(main.save.settings()["reduce_flash"], false, "点滅を弱める 切")
	main.free()
	return true


func test_settings_offset_stops_at_12() -> bool:
	var main := _boot()
	_press(main, "btn_settings")
	ok(_texts(main._settings).has(S.signed_ms(0)), "初めは 0 ms")
	for i in 20:
		_press(main, "btn_offset_plus")
	eq(main.save.settings()["offset_ticks"], 12, "+12 で止まる")
	ok(_texts(main._settings).has(S.signed_ms(100)), "+100 ms と出る")
	ok(_btn(main, "btn_offset_plus").disabled, "これ以上は押せない")
	for i in 40:
		_press(main, "btn_offset_minus")
	eq(main.save.settings()["offset_ticks"], -12, "−12 で止まる")
	ok(_texts(main._settings).has(S.signed_ms(-100)), "−100 ms と出る")
	ok(_btn(main, "btn_offset_minus").disabled and not _btn(main, "btn_offset_plus").disabled, "下の端")
	main.free()
	return true


func test_settings_calib_and_back() -> bool:
	var main := _boot()
	_press(main, "btn_settings")
	_press(main, "btn_calib")
	eq(main.screen_name, "calib", "タイミング合わせへ")
	main._settings._input(_key(KEY_ESCAPE))
	eq(main.screen_name, "calib", "タイミング合わせが上にある間は、設定は Esc を受けない")
	_press(main, "btn_plus")
	_press(main, "btn_plus")
	_press(main, "btn_back")
	eq(main.screen_name, "settings", "戻る で設定に戻る")
	main._settings._process(0.016)
	ok(_texts(main._settings).has(S.signed_ms(Rank.ms(2))), "ずれの表示が新しい値になる: %s" % [_texts(main._settings)])
	_press(main, "btn_back")
	eq(main.screen_name, "title", "戻る でタイトルに戻る")
	_press(main, "btn_settings")
	main._settings._input(_key(KEY_ESCAPE))
	eq(main.screen_name, "title", "Esc でも戻る")
	main.free()
	return true


# ---- 一時停止 ----

func test_pause_resume_settings_title() -> bool:
	var main := _boot()
	_press(main, "btn_fixed")
	main.pause()
	eq(main.screen_name, "pause", "一時停止")
	ok(_texts(main._pause).has(S.PAUSED), "「一時停止」が出る")
	ok(main.view.visible, "後ろに対戦が見えている")
	main._pause._input(_key(KEY_ESCAPE))
	eq(main.screen_name, "pause", "入ったフレームの Esc では続けない")
	_press(main, "btn_resume")
	eq(main.screen_name, "duel", "続ける")
	ok(not main.view.paused and main.view.resume_left > 0.0, "1 秒の待ちに入る")
	main.pause()
	_press(main, "btn_pause_settings")
	eq(main.screen_name, "settings", "一時停止から設定へ")
	main._pause._process(0.1)
	main._pause._input(_key(KEY_ESCAPE))
	eq(main.screen_name, "settings", "設定が上にある間は、一時停止は Esc を受けない")
	_press(main, "btn_back")
	eq(main.screen_name, "pause", "戻る で一時停止に戻る")
	main._pause._input(_key(KEY_ESCAPE))
	eq(main.screen_name, "duel", "Esc で続ける")
	main.pause()
	_press(main, "btn_pause_title")
	eq(main.screen_name, "title", "タイトルへ")
	eq(main.save.fixed_best(), null, "記録に残らない")
	ok(not main.view.visible, "対戦は消える")
	main.free()
	return true


# ---- 合間 ----

func test_interval_shows_subtotal() -> bool:
	var main := _boot()
	var t := _texts(_show(main, "interval", {"boss": 1, "hits": 0, "ticks": 6276, "justs": 9}))
	ok(t.has(S.boss_beaten(1)), "「敵 1 を倒した」が出る")
	ok(t.has(S.so_far(0, "52.3")), "ここまで: %s" % [t])
	ok(S.so_far(0, "52.3").contains(S.UNHURT), "受けた数 0 は「無傷」")
	ok(t.has(S.justs(9)), "ぴったりの数")
	t = _texts(_show(main, "interval", {"boss": 2, "hits": 3, "ticks": 12000, "justs": 0}))
	ok(t.has(S.boss_beaten(2)) and t.has(S.so_far(3, "100.0")), "敵 2・受けた数 3: %s" % [t])
	main.free()
	return true


func test_interval_next_after_500ms() -> bool:
	var main := _boot()
	_press(main, "btn_fixed")
	main.view.duel.state = Duel.State.WAIT_NEXT  # 敵 1 を倒した所にする
	main._on_boss_beaten()
	eq(main.screen_name, "interval", "合間が開く")
	var next := _btn(main, "btn_next")
	ok(next.disabled, "入ってすぐは押せない")
	next.pressed.emit()
	main._screen._input(_key(KEY_SPACE))
	eq(main.screen_name, "interval", "500 ms までは進まない(ボタンもキーも)")
	main._screen._process(0.4)
	ok(next.disabled, "400 ms でもまだ")
	main._screen._process(0.15)
	ok(not next.disabled, "500 ms を過ぎたら押せる")
	main._screen._input(_key(KEY_ENTER))
	eq(main.screen_name, "duel", "Enter で次の敵へ")
	eq(main.view.duel.boss, 2, "敵 2 になる")
	main.view.duel.state = Duel.State.WAIT_NEXT
	main._on_boss_beaten()
	main._screen._process(0.6)
	_press(main, "btn_next")
	eq(main.view.duel.boss, 3, "ボタンでも次の敵へ")
	main.free()
	return true


# ---- 結果 ----

func test_result_diff_line_six_cases() -> bool:
	var prev := {"hits": 3, "ticks": 20000}
	var cases := [
		[3, 20000, null, S.FIRST_RECORD, true],
		[2, 25000, prev, S.diff_fewer_hits(1), true],
		[3, 19592, prev, S.diff_faster("3.4"), true],
		[5, 15000, prev, S.diff_more_hits(2), false],
		[3, 20300, prev, S.diff_slower("2.5"), false],
		[3, 20000, prev, S.SAME_AS_BEST, false],
	]
	for c: Array in cases:
		var d := Result.diff_line({"hits": c[0], "ticks": c[1]}, {"prev_best": c[2]})
		eq(d["text"], c[3], "差の行")
		eq(d["bright"], c[4], "明るい色か: %s" % c[3])
		eq(d["bright"], c[2] == null or Rank.better({"hits": c[0], "ticks": c[1]}, prev), "明るい = 新しい記録: %s" % c[3])
	return true


func test_result_win_screen() -> bool:
	var main := _boot()
	_press(main, "btn_fixed")
	var info := _result_info(2, 18504, _record({"hits": 3, "ticks": 20000}, true))
	var screen := _show(main, "result", info)
	var t := _texts(screen)
	for want: String in [S.RESULT_WIN, S.hits(2), S.seconds("154.2"), S.diff_fewer_hits(1), S.justs(21), S.retries(1)]:
		ok(t.has(want), "「%s」が出る: %s" % [want, t])
	eq(_label(screen, S.diff_fewer_hits(1)).get_theme_color("font_color"), Kit.C_SPARK, "新しい記録は明るい色")
	ok(not t.has(S.COPIED) and not t.has(S.SAVE_FAILED), "コピーの後の行・保存の失敗の行は出ていない")
	var box: TextEdit = screen.find_child("share_box", true, false)
	ok(box != null, "共有する文字の枠がある")
	eq(box.text, info["share_text"], "枠の中身")
	eq(box.get_line_count(), 3, "3 行")
	ok(not box.editable, "書き換えられない")
	ok(box.selecting_enabled, "選べる")
	_press(main, "btn_copy")
	ok(_texts(screen).has(S.COPIED), "コピーの後に 1 行出る(E-18)")
	var again := _btn(main, "btn_again")
	ok(again.disabled, "入ってすぐは押せない")
	again.pressed.emit()
	screen._input(_key(KEY_ENTER))
	eq(main.screen_name, "result", "300 ms までは進まない")
	screen._process(0.35)
	ok(not again.disabled, "300 ms を過ぎたら押せる")
	screen._input(_key(KEY_SPACE))
	eq(main.screen_name, "duel", "スペースで もう1回")
	eq(main.run["mode"], Duel.Mode.FIXED, "同じ入口")

	screen = _show(main, "result", _result_info(0, 18504, _record({"hits": 0, "ticks": 18000}, false)))
	eq(_label(screen, S.UNHURT).get_theme_color("font_color"), Kit.C_PLAYER, "受けた数 0 は 緑の「無傷」")
	eq(_label(screen, S.diff_slower("4.2")).get_theme_color("font_color"), Kit.C_DIM, "最高でない時は弱い色")
	screen._process(0.35)
	_press(main, "btn_again")
	eq(main.screen_name, "duel", "ボタンでも もう1回")
	_show(main, "result", info)
	_press(main, "btn_title")
	eq(main.screen_name, "title", "タイトルへ")
	main.free()
	return true


func test_result_practice_has_no_record_or_share() -> bool:
	var main := _boot()
	var screen := _show(main, "result", _result_info(1, 6000, _record(null, false), Duel.Mode.PRACTICE, true, 2))
	var t := _texts(screen)
	ok(t.has(S.practice_win(2)), "題に「練習」と入る: %s" % [t])
	ok(t.has(S.hits(1)) and t.has(S.seconds("50.0")), "受けた数と時間は出る")
	ok(not t.has(S.FIRST_RECORD), "差の行は出ない")
	ok(screen.find_child("share_box", true, false) == null, "共有の枠は出ない(E-14)")
	ok(screen.find_child("btn_copy", true, false) == null, "コピーは出ない")
	ok(_btn(main, "btn_again") != null and _btn(main, "btn_title") != null, "もう1回・タイトルへ はある")
	t = _texts(_show(main, "result", _result_info(5, 3000, _record(null, false), Duel.Mode.PRACTICE, false, 3)))
	ok(t.has(S.PRACTICE_LOSE), "負けた時の題: %s" % [t])
	main.free()
	return true


func test_result_save_failed_line() -> bool:
	var main := _boot()
	var t := _texts(_show(main, "result", _result_info(2, 18504, _record(null, true, false))))
	ok(t.has(S.SAVE_FAILED), "「このブラウザでは記録を残せない」が出る(E-16)")
	ok(t.has(S.FIRST_RECORD), "初めての記録")
	main.free()
	return true


func test_share_text_fits_without_wrapping() -> bool:
	var worst := ShareText.build("2026-11-12", Duel.Mode.DAILY, true, {"hits": 0, "ticks": 119988, "justs": 999, "retries": 99})
	var inner: float = Result.SHARE_RECT.size.x - Result.SHARE_PAD.x * 2.0 - 8.0
	var sz := Result.share_font_size(worst, inner)
	ok(sz >= 16, "読める大きさ(%d)で入る" % sz)
	for line: String in worst.split("\n"):
		ok(Kit.font(500).get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x <= inner, "折り返さずに入る: %s" % line)
	return true


# ---- 5 画面まとめて ----

# 一番長くなる文言で 5 画面を開き、[名前, 画面] を返す。
func _worst_screens(main: Node) -> Array:
	var day: int = main.today()["day"]
	main.save.data["fixed"] = {"hits": 12, "ticks": 119988, "justs": 0, "retries": 0}
	main.save.data["daily"] = {"day": day, "first": {"hits": 12, "ticks": 119988}, "best": {"hits": 11, "ticks": 119988}}
	main.save.data["reached_boss"] = 2
	main.data_ok = false
	main.save.load_failed = true
	var out: Array = []
	main.go_title()
	out.append(["title", main._screen])
	main.data_ok = true
	main.open_settings()
	main.save.set_setting("offset_ticks", -12)
	main._settings._process(0.016)
	out.append(["settings", main._settings])
	out.append(["interval", _show(main, "interval", {"boss": 2, "hits": 12, "ticks": 119988, "justs": 999})])
	var info := _result_info(12, 119988, _record({"hits": 12, "ticks": 239976}, true, false), Duel.Mode.DAILY)
	info["result"]["justs"] = 999
	info["result"]["retries"] = 99
	out.append(["result", _show(main, "result", info)])
	main.start_run(Duel.Mode.FIXED)
	main.pause()
	out.append(["pause", main._pause])
	return out


func test_buttons_are_tall_and_do_not_overlap() -> bool:
	var main := _boot()
	var n := 0
	for pair: Array in _worst_screens(main):
		var buttons := _all(pair[1], Button)
		n += buttons.size()
		for b: Button in buttons:
			ok(b.size.y >= 88.0, "%s の %s は高さ 88 以上(%s)" % [pair[0], b.name, b.size.y])
			ok(b.position.x >= 0.0 and b.position.x + b.size.x <= 720.0, "%s の %s は画面の中" % [pair[0], b.name])
			for other: Button in buttons:
				ok(other == b or not b.get_rect().intersects(other.get_rect()), "%s の %s と %s が重ならない" % [pair[0], b.name, other.name])
	eq(n, 7 + 17 + 1 + 3 + 3, "ボタンは全部で 31 個(v0.2.0 でタイトルに型の練習、設定に 2 行)")
	main.free()
	return true


func test_labels_fit_with_longest_texts() -> bool:
	var main := _boot()
	var n := 0
	for pair: Array in _worst_screens(main):
		for l: Label in _all(pair[1], Label):
			n += 1
			ok(Title.text_width(l) <= l.size.x + 0.5, "%s の「%s」が枠に入る(%d > %d)" % [pair[0], l.text, Title.text_width(l), l.size.x])
	ok(n >= 30, "字を %d 個 測った" % n)
	main.free()
	return true


func test_no_japanese_literals_in_screens() -> bool:
	var re := RegEx.create_from_string("\"[^\"]*[\\x{3000}-\\x{30FF}\\x{4E00}-\\x{9FFF}\\x{FF00}-\\x{FFEF}][^\"]*\"")
	eq(re.search_all("a(\"あ\", \"x\", \"敵\")  b(\"カ\")").size(), 3, "この正規表現は日本語の文字列を見つける")
	for file: String in SCREEN_FILES:
		var src := FileAccess.get_file_as_string("res://ui/%s.gd" % file)
		ok(src.length() > 200, "%s.gd を読めた" % file)
		for line: String in src.split("\n"):
			var code := line.get_slice("#", 0)  # コメントを除く
			for m: RegExMatch in re.search_all(code):
				ok(false, "%s.gd に、じかに書いた文言がある: %s" % [file, m.get_string()])
	return true
