# 保存のテスト(AC-26・NFR-9・E-12・E-15・E-16)。user:// にテスト用のファイルを作って、終わったら消す。
extends "res://tests/suite.gd"

const SaveStore := preload("res://save/save_store.gd")

const PATH := "user://test_save.json"


func _write(text: String) -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _clean() -> void:
	for f: String in [PATH, "user://test_save_ext.json"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))


func _is_default(s: SaveStore) -> void:
	eq(s.fixed_best(), null, "記録なし")
	eq(s.reached_boss(), 1, "着いた敵 1")
	eq(s.settings(), {"volume": 75, "shake": true, "reduce_flash": false, "offset_ticks": 0, "easy": false, "show_diff": true, "bgm_volume": 75}, "設定の既定値")


func test_no_file_is_default_without_warning() -> bool:
	_clean()
	var s := SaveStore.new(PATH)
	_is_default(s)
	ok(not s.load_failed, "初めての起動では、読めなかった扱いにしない")
	return true


func test_ac26_empty_file() -> bool:
	_write("")
	var s := SaveStore.new(PATH)
	_is_default(s)
	ok(s.load_failed, "空の保存は読めなかった扱い(E-15)")
	_clean()
	return true


func test_ac26_broken_json() -> bool:
	for text: String in ["{\"version\": 1, \"fixed\": {", "[1, 2, 3]", "null", "こんにちは"]:
		_write(text)
		var s := SaveStore.new(PATH)
		_is_default(s)
		ok(s.load_failed, "壊れた保存(%s)は読めなかった扱い" % text)
	_clean()
	return true


func test_ac26_unknown_version_keeps_settings() -> bool:
	_write(JSON.stringify({"version": 2, "fixed": {"hits": 0, "ticks": 100, "justs": 3, "retries": 0}, "reached_boss": 3,
		"daily": {"day": 5, "first": {"hits": 1, "ticks": 2}, "best": {"hits": 1, "ticks": 2}},
		"settings": {"volume": 25, "shake": false, "reduce_flash": true, "offset_ticks": -3}}))
	var s := SaveStore.new(PATH)
	eq(s.fixed_best(), null, "記録は初めから")
	eq(s.reached_boss(), 1, "着いた敵も初めから")
	eq(s.daily(5)["first"], null, "今日の記録も初めから")
	eq(s.settings(), {"volume": 25, "shake": false, "reduce_flash": true, "offset_ticks": -3, "easy": false, "show_diff": true, "bgm_volume": 75}, "設定は引き継ぐ")
	ok(not s.load_failed, "読めなかった扱いにはしない")
	_clean()
	return true


func test_ac26_offset_is_clamped() -> bool:
	_write(JSON.stringify({"version": 1, "settings": {"offset_ticks": 40}}))
	eq(SaveStore.new(PATH).settings()["offset_ticks"], 12, "ずれ 40 は 12")
	_write(JSON.stringify({"version": 1, "settings": {"offset_ticks": -40}}))
	eq(SaveStore.new(PATH).settings()["offset_ticks"], -12, "ずれ −40 は −12")
	_clean()
	return true


func test_wrong_types_fall_back() -> bool:
	_write(JSON.stringify({"version": 1, "fixed": "x", "daily": [1], "reached_boss": "3",
		"settings": {"volume": 33, "shake": "yes", "reduce_flash": 1, "offset_ticks": "5"}}))
	var s := SaveStore.new(PATH)
	_is_default(s)
	ok(not s.load_failed, "形は読めているので、読めなかった扱いにはしない")
	_write(JSON.stringify({"version": 1, "reached_boss": 99}))
	eq(SaveStore.new(PATH).reached_boss(), 3, "着いた敵は 1〜3 に切り詰める")
	_clean()
	return true


func test_round_trip() -> bool:
	_clean()
	var s := SaveStore.new(PATH)
	s.set_setting("volume", 50)
	s.set_setting("offset_ticks", 99)
	s.reach(2)
	s.reach(1)
	s.record_win(Duel.Mode.FIXED, 315, {"hits": 2, "ticks": 18504, "justs": 21, "retries": 0})
	var t := SaveStore.new(PATH)
	eq(t.settings()["volume"], 50, "音量が残る")
	eq(t.settings()["offset_ticks"], 12, "ずれは切り詰めて残る")
	eq(t.reached_boss(), 2, "着いた敵は戻らない")
	eq(t.fixed_best(), {"hits": 2, "ticks": 18504, "justs": 21, "retries": 0}, "最高が残る")
	ok(FileAccess.get_file_as_string(PATH).length() < 2048, "保存は 2 KB 以下")
	_clean()
	return true


func test_fixed_best_only_improves() -> bool:
	_clean()
	var s := SaveStore.new(PATH)
	var first := s.record_win(Duel.Mode.FIXED, 0, {"hits": 2, "ticks": 9000, "justs": 1, "retries": 0})
	ok(first["new_best"] and first["prev_best"] == null, "初めての記録")
	var worse := s.record_win(Duel.Mode.FIXED, 0, {"hits": 3, "ticks": 8000, "justs": 9, "retries": 0})
	ok(not worse["new_best"], "受けた数が多ければ、速くても下")
	eq(s.fixed_best()["hits"], 2, "最高は変わらない")
	var faster := s.record_win(Duel.Mode.FIXED, 0, {"hits": 2, "ticks": 8000, "justs": 0, "retries": 1})
	ok(faster["new_best"], "同じ受けた数なら、速い方が上")
	eq(faster["prev_best"]["ticks"], 9000, "前の最高を返す")
	eq(s.fixed_best(), {"hits": 2, "ticks": 8000, "justs": 0, "retries": 1}, "最高が入れ替わる")
	_clean()
	return true


func test_daily_first_and_best() -> bool:
	_clean()
	var s := SaveStore.new(PATH)
	eq(s.daily(315), {"day": 315, "first": null, "best": null}, "まだ遊んでいない")
	var a := s.record_win(Duel.Mode.DAILY, 315, {"hits": 4, "ticks": 20100, "justs": 5, "retries": 1})
	ok(a["first_today"], "今日の 1 回目")
	var b := s.record_win(Duel.Mode.DAILY, 315, {"hits": 2, "ticks": 18504, "justs": 21, "retries": 0})
	ok(not b["first_today"] and b["new_best"], "2 回目は 1 回目でなく、最高は入れ替わる")
	eq(s.daily(315), {"day": 315, "first": {"hits": 4, "ticks": 20100}, "best": {"hits": 2, "ticks": 18504}}, "1 回目は残り、最高だけ変わる")
	eq(s.fixed_best(), null, "いつもの記録とは別")
	eq(s.daily(316)["first"], null, "日付が変わると作り直す")
	var c := s.record_win(Duel.Mode.DAILY, 316, {"hits": 5, "ticks": 30000, "justs": 0, "retries": 2})
	ok(c["first_today"] and c["new_best"], "次の日の 1 回目")
	eq(SaveStore.new(PATH).daily(316)["best"], {"hits": 5, "ticks": 30000}, "次の日の物が保存される")
	_clean()
	return true


func test_practice_is_not_recorded() -> bool:
	_clean()
	var s := SaveStore.new(PATH)
	var r := s.record_win(Duel.Mode.PRACTICE, 315, {"hits": 0, "ticks": 100, "justs": 9, "retries": 0})
	ok(not r["new_best"], "練習は記録にならない")
	eq(s.fixed_best(), null, "いつもの記録に入らない")
	ok(not FileAccess.file_exists(PATH), "保存も書かない(E-14)")
	return true


func test_e16_write_failure_does_not_stop() -> bool:
	var s := SaveStore.new("user://no_such_dir/deep/save.json")
	var r := s.record_win(Duel.Mode.FIXED, 0, {"hits": 1, "ticks": 5, "justs": 0, "retries": 0})
	ok(not r["saved"], "書けなかったことを返す")
	ok(s.write_failed, "書けなかった印")
	eq(s.fixed_best()["hits"], 1, "動いている間の記録は持っている")
	return true


func test_other_tab_records_survive_a_stale_write() -> bool:
	# 同じブラウザの 2 つのタブ。後のタブが書いた記録を、先のタブの古い中身で消さない
	_clean()
	var old_tab := SaveStore.new(PATH)
	var new_tab := SaveStore.new(PATH)
	new_tab.record_win(Duel.Mode.FIXED, 10, {"hits": 1, "ticks": 9000, "justs": 3, "retries": 0})
	new_tab.record_win(Duel.Mode.DAILY, 10, {"hits": 2, "ticks": 8000, "justs": 3, "retries": 0})
	new_tab.reach(3)
	old_tab.set_setting("shake", false)
	var after := SaveStore.new(PATH)
	eq(after.fixed_best(), {"hits": 1, "ticks": 9000, "justs": 3, "retries": 0}, "いつもの最高が残る")
	eq(after.daily(10)["best"], {"hits": 2, "ticks": 8000}, "今日の最高が残る")
	eq(after.reached_boss(), 3, "着いた敵が残る")
	eq(after.settings()["shake"], false, "古いタブが変えた設定は入る")
	# 古いタブが、もっと良い記録を出した時は、良い方が残る。同じ日の 1 回目は、先に書かれていた方
	old_tab.record_win(Duel.Mode.FIXED, 10, {"hits": 0, "ticks": 9500, "justs": 9, "retries": 0})
	old_tab.record_win(Duel.Mode.DAILY, 10, {"hits": 5, "ticks": 7000, "justs": 0, "retries": 1})
	var last := SaveStore.new(PATH)
	eq(last.fixed_best()["hits"], 0, "良い方の最高")
	eq(last.daily(10)["first"], {"hits": 2, "ticks": 8000}, "1 回目は先に書かれていた方")
	eq(last.daily(10)["best"], {"hits": 2, "ticks": 8000}, "今日の最高は良い方")
	_clean()
	return true


func test_run_started_yesterday_does_not_replace_today() -> bool:
	_clean()
	var s := SaveStore.new(PATH)
	s.record_win(Duel.Mode.DAILY, 10, {"hits": 3, "ticks": 9000, "justs": 0, "retries": 0})
	var late := s.record_win(Duel.Mode.DAILY, 9, {"hits": 0, "ticks": 5000, "justs": 9, "retries": 0})
	ok(not late["new_best"] and not late["first_today"], "きのう始めた回は、今日の記録にならない")
	eq(s.daily(10)["best"], {"hits": 3, "ticks": 9000}, "今日の記録は残る")
	eq(SaveStore.new(PATH).daily(10)["first"], {"hits": 3, "ticks": 9000}, "保存も今日のまま")
	_clean()
	return true


func test_version_must_be_exactly_one() -> bool:
	_write(JSON.stringify({"version": 1.5, "reached_boss": 3, "settings": {"volume": 50}}))
	var s := SaveStore.new(PATH)
	eq(s.reached_boss(), 1, "版 1.5 は知らない版。記録は初めから")
	eq(s.settings()["volume"], 50, "設定は引き継ぐ")
	_clean()
	return true
