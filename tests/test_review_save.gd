# レビュー用: 壊れた保存・型の違う値・古い版を読ませて、落ちないか、値が決まった範囲に収まるかを見る(§9.11・NFR-9)。
# 呼んだ先のスクリプトエラーは、このランナーでは失敗にならないので、出力の SCRIPT ERROR の行も合わせて見ること。
extends "res://tests/suite.gd"

const SaveStore := preload("res://save/save_store.gd")
const Title := preload("res://ui/title.gd")
const Rank := preload("res://core/rank.gd")
const S := preload("res://core/strings.gd")

const PATH := "user://review_save.json"

const CASES := [
	"", " ", "null", "true", "0", "[]", "[1,2]", "\"x\"", "{", "{}", "{\"version\":1}",
	"{\"version\":\"1\"}", "{\"version\":1.5}", "{\"version\":null}", "{\"version\":[1]}", "{\"version\":0}", "{\"version\":2,\"settings\":7}",
	"{\"version\":1,\"fixed\":7,\"daily\":7,\"reached_boss\":\"3\",\"settings\":[]}",
	"{\"version\":1,\"fixed\":{\"hits\":\"2\",\"ticks\":100}}",
	"{\"version\":1,\"fixed\":{\"hits\":2}}",
	"{\"version\":1,\"fixed\":{\"hits\":-4,\"ticks\":-9,\"justs\":\"a\",\"retries\":null}}",
	"{\"version\":1,\"fixed\":{\"hits\":1e30,\"ticks\":1e308}}",
	"{\"version\":1,\"fixed\":{\"hits\":2.9,\"ticks\":100.9}}",
	"{\"version\":1,\"daily\":{\"day\":\"315\"}}",
	"{\"version\":1,\"daily\":{\"day\":315}}",
	"{\"version\":1,\"daily\":{\"day\":315,\"first\":null,\"best\":{\"hits\":1,\"ticks\":9}}}",
	"{\"version\":1,\"daily\":{\"day\":315,\"first\":{\"hits\":1,\"ticks\":9},\"best\":\"x\"}}",
	"{\"version\":1,\"daily\":{\"day\":-5,\"first\":[],\"best\":{}}}",
	"{\"version\":1,\"daily\":[315]}",
	"{\"version\":1,\"reached_boss\":0}", "{\"version\":1,\"reached_boss\":99}", "{\"version\":1,\"reached_boss\":-1e20}", "{\"version\":1,\"reached_boss\":2.7}",
	"{\"version\":1,\"settings\":{\"volume\":60,\"shake\":1,\"reduce_flash\":\"true\",\"offset_ticks\":\"3\"}}",
	"{\"version\":1,\"settings\":{\"volume\":\"75\",\"shake\":null,\"offset_ticks\":40}}",
	"{\"version\":1,\"settings\":{\"volume\":75.0,\"offset_ticks\":-40.9}}",
	"{\"version\":1,\"settings\":{\"volume\":25.5,\"offset_ticks\":1e99}}",
	"{\"version\":1,\"settings\":{\"offset_ticks\":-1e99}}",
	"{\"version\":3,\"settings\":{\"volume\":0,\"shake\":false,\"reduce_flash\":true,\"offset_ticks\":-12},\"fixed\":{\"hits\":0,\"ticks\":1}}",
	"{\"version\":1,\"settings\":{\"volume\":100,\"extra\":{\"a\":[1,2,3]}},\"unknown\":true}",
]


func _write(text: String) -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _sane(s: SaveStore, text: String) -> void:
	var st := s.settings()
	var what := "「%s」" % text.left(60)
	ok(st["volume"] is int and st["volume"] in B.VOLUMES, what + " 音量が 5 段のどれか(%s)" % [st["volume"]])
	ok(st["shake"] is bool and st["reduce_flash"] is bool, what + " 揺れ・点滅が真偽")
	ok(st["offset_ticks"] is int and st["offset_ticks"] >= B.OFFSET_MIN and st["offset_ticks"] <= B.OFFSET_MAX, what + " ずれが −12〜12(%s)" % [st["offset_ticks"]])
	ok(s.reached_boss() is int and s.reached_boss() >= 1 and s.reached_boss() <= B.BOSS_COUNT, what + " 着いた敵が 1〜3(%s)" % [s.reached_boss()])
	var best: Variant = s.fixed_best()
	ok(best == null or (best is Dictionary and best["hits"] is int and best["ticks"] is int and best["hits"] >= 0 and best["ticks"] >= 0
		and best["justs"] is int and best["retries"] is int), what + " いつもの最高の形(%s)" % [best])
	var daily := s.daily(315)
	for k: String in ["first", "best"]:
		var r: Variant = daily[k]
		ok(r == null or (r is Dictionary and r["hits"] is int and r["ticks"] is int), what + " 今日の %s の形(%s)" % [k, r])
	# 画面が読む時と同じ使い方
	if best is Dictionary:
		S.best_line(int(best["hits"]), Rank.seconds_text(int(best["ticks"])))
	Title._daily_line(daily)
	Title._daily_line(s.daily(999))


func test_review_broken_saves_load_sane() -> bool:
	var failed_flags: Array = []
	for text: String in CASES:
		_write(text)
		var s := SaveStore.new(PATH)
		_sane(s, text)
		failed_flags.append(1 if s.load_failed else 0)
		# 読んだ後に、勝ちを記録して書けるか(いつも・今日・別の日)
		var r1 := s.record_win(Duel.Mode.FIXED, 315, {"hits": 3, "ticks": 9000, "justs": 5, "retries": 1})
		var r2 := s.record_win(Duel.Mode.DAILY, 315, {"hits": 3, "ticks": 9000, "justs": 5, "retries": 1})
		var r3 := s.record_win(Duel.Mode.DAILY, 316, {"hits": 0, "ticks": 8000, "justs": 5, "retries": 0})
		ok(r1["saved"] and r2["saved"] and r3["saved"], "「%s」の後に書ける" % text.left(40))
		ok(r3["first_today"] and r3["prev_best"] == null, "「%s」: 別の日は 1 回目になる" % text.left(40))
		s.set_setting("offset_ticks", 99)
		s.reach(7)
		var again := SaveStore.new(PATH)
		ok(not again.load_failed, "「%s」: 書いた物をもう一度読める" % text.left(40))
		_sane(again, text + "(書き直した後)")
		eq(again.settings()["offset_ticks"], 12, "ずれ 99 は 12 に切り詰める")
		eq(again.reached_boss(), 3, "着いた敵 7 は 3 に切り詰める")
	print("RV 壊れた保存 %d 通り。「読めなかった」の旗(E-15)が立った数 = %d  旗の並び = %s" % [CASES.size(), failed_flags.count(1), failed_flags])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://review_save_ext.json"))
	return true


func test_review_version_and_flag_details() -> bool:
	# 版 1.5 は 1 として読まれるか。版が違う時に「読めなかった」の 1 行は出るか
	for c: Array in [["{\"version\":1.5,\"fixed\":{\"hits\":1,\"ticks\":9}}", "版 1.5"], ["{\"version\":2,\"fixed\":{\"hits\":1,\"ticks\":9}}", "版 2"],
			["{\"fixed\":{\"hits\":1,\"ticks\":9}}", "版なし"], ["[]", "配列"], ["{\"version\":1,\"fixed\":\"x\",\"daily\":3}", "記録の型が違う"]]:
		_write(c[0])
		var s := SaveStore.new(PATH)
		print("RV %s: 記録 = %s  読めなかったの旗 = %s" % [c[1], s.fixed_best(), s.load_failed])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://review_save_ext.json"))
	return true


func test_review_two_tabs_stale_write_drops_record() -> bool:
	# 同じブラウザで 2 つのタブを開いた時: 先に開いたタブ(a)は、起動時に読んだ中身を持ったまま。
	# 後のタブ(b)が最高を書いた後に、a が設定を 1 つ変えると、a の古い中身で丸ごと上書きされる
	_write("{}")
	var a := SaveStore.new(PATH)
	var b := SaveStore.new(PATH)
	b.record_win(Duel.Mode.FIXED, 10, {"hits": 0, "ticks": 9000, "justs": 30, "retries": 0})
	b.reach(3)
	eq(SaveStore.new(PATH).fixed_best() != null, true, "b が書いた最高は保存にある")
	a.set_setting("volume", 50)
	var after := SaveStore.new(PATH)
	print("RV 2 つのタブ: a が設定を変えた後の保存 = 最高 %s・着いた敵 %d・音量 %d" % [after.fixed_best(), after.reached_boss(), after.settings()["volume"]])
	eq(after.fixed_best(), {"hits": 0, "ticks": 9000, "justs": 30, "retries": 0}, "b の最高は残る(書く直前に読み直して合わせる)")
	eq(after.reached_boss(), 3, "着いた敵も残る")
	eq(after.settings()["volume"], 50, "a が変えた設定は入る")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://review_save_ext.json"))
	return true


func test_review_daily_rollover_and_tie() -> bool:
	_write("{}")
	var s := SaveStore.new(PATH)
	var a := s.record_win(Duel.Mode.DAILY, 10, {"hits": 2, "ticks": 9000, "justs": 1, "retries": 0})
	var b := s.record_win(Duel.Mode.DAILY, 10, {"hits": 2, "ticks": 9000, "justs": 1, "retries": 0})  # まったく同じ
	var c := s.record_win(Duel.Mode.DAILY, 10, {"hits": 1, "ticks": 9999, "justs": 1, "retries": 0})
	eq([a["first_today"], a["new_best"], b["first_today"], b["new_best"], c["new_best"]], [true, true, false, false, true], "1 回目・同じ・より上")
	eq(s.daily(10)["first"], {"hits": 2, "ticks": 9000}, "1 回目は書き換わらない")
	eq(s.daily(10)["best"], {"hits": 1, "ticks": 9999}, "最高は書き換わる")
	# きのう始めた回(day 9)が、今日の記録(day 10)の後に終わった時
	var d := s.record_win(Duel.Mode.DAILY, 9, {"hits": 0, "ticks": 5000, "justs": 1, "retries": 0})
	print("RV きのう始めた回が後から終わる: %s  保存の daily = %s" % [d, s.data["daily"]])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://review_save_ext.json"))
	return true
