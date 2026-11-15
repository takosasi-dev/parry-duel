# v0.3.0 の実績のテスト: 判定・保存(別のタブとの合わせ)・知らせ・一覧の画面。
extends "res://tests/suite.gd"

const Achievements := preload("res://core/achievements.gd")
const SaveStore := preload("res://save/save_store.gd")
const S := preload("res://core/strings.gd")
const Title := preload("res://ui/title.gd")

const PATH := "user://v3_ach.json"

var _last: Node = null


func _clean() -> void:
	for f: String in [PATH, "user://v3_ach_ext.json"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))


func _parry(just: bool) -> Dictionary:
	return {"type": "parry", "just": just, "attack": {"kind": "white"}, "combo": 1, "diff": 0}


func test_every_id_has_text_and_text_has_every_id() -> bool:
	var ids: Array = S.ACHIEVEMENTS.map(func(a: Array) -> String: return a[0])
	eq(ids, Achievements.IDS, "文言の並びと判定の id が同じ")
	for id: String in ids:
		ok(S.ach_name(id) != "" and S.ach_desc(id) != "", "%s の名前と取り方" % id)
	return true


func test_events() -> bool:
	var a := Achievements.new()
	var d := Duel.new(1, Duel.Mode.FIXED, 1)
	a.begin(d)
	var counts := {}
	eq(a.on_event(_parry(false), d, counts), ["first_parry"], "弾いた")
	var got: Array = []
	for i in B.ACH_JUST_STREAK:
		got = a.on_event(_parry(true), d, counts)
	ok("just_streak" in got and "first_just" in got, "ぴったり 10 連続: %s" % [got])
	a.on_event({"type": "parry_whiff"}, d, counts)
	ok(not ("just_streak" in a.on_event(_parry(true), d, counts)), "空振りで連続は切れる")
	ok("unhurt_boss" in a.on_event({"type": "boss_down", "boss": 1}, d, counts), "受けずに倒した")
	d.hits = 1
	ok(not ("unhurt_boss" in a.on_event({"type": "boss_down", "boss": 1}, d, counts)), "受けていれば無い")
	for i in B.ACH_RED_DODGES - 1:
		a.on_event({"type": "dodge_avoid", "attack": {"kind": "red"}}, d, counts)
	ok(not ("dodge_red" in a.on_event({"type": "dodge_avoid", "attack": {"kind": "white"}}, d, counts)), "白を避けても数えない")
	ok("dodge_red" in a.on_event({"type": "dodge_avoid", "attack": {"kind": "red"}}, d, counts), "赤を 20 回")
	eq(counts["red_dodges"], B.ACH_RED_DODGES, "数")
	var e := Duel.new(1, Duel.Mode.ENDLESS, 1)
	e.kills = 6
	ok("endless_lap2" in a.on_event({"type": "boss_down", "boss": 3}, e, counts), "連戦で 6 体")
	return true


func test_result() -> bool:
	var r := {"won": true, "mode": Duel.Mode.FIXED, "hits": 0, "retries": 0}
	eq(Achievements.on_result(r), ["win_fixed", "unhurt_run", "no_retry"], "無傷・やり直し無しで勝ち抜いた")
	r.merge({"mode": Duel.Mode.DAILY, "hits": 3, "retries": 1}, true)
	eq(Achievements.on_result(r), ["win_daily"], "今日の3連戦")
	r.merge({"mode": Duel.Mode.PRACTICE}, true)
	eq(Achievements.on_result(r), [], "練習は勝ち抜きに数えない")
	r.merge({"mode": Duel.Mode.FIXED, "won": false}, true)
	eq(Achievements.on_result(r), [], "負けは無い")
	return true


func test_unlock_saves_and_merges_with_other_tab() -> bool:
	_clean()
	var a := SaveStore.new(PATH)
	var b := SaveStore.new(PATH)
	eq(a.unlock(["first_parry", "first_parry", "nope"], "2026-11-14"), ["first_parry", "nope"], "新しい物だけ(重なりは 1 つ)")
	eq(a.unlock(["first_parry"], "2026-11-15"), [], "もう取った物は返さない")
	b.counts()["red_dodges"] = 7
	b.unlock(["first_just"], "2026-11-16")  # 古い写しのタブが書いた
	var c := SaveStore.new(PATH)
	eq(c.achievements().get("first_parry"), "2026-11-14", "別のタブの実績が残る")
	eq(c.achievements().get("first_just"), "2026-11-16", "こちらの実績も入る")
	eq(c.counts().get("red_dodges"), 7, "数も入る")
	_clean()
	return true


func _boot() -> Node:
	if _last != null and is_instance_valid(_last):
		_last.free()
	for f: String in ["user://save.json", "user://save_ext.json"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	var main: Node = load("res://ui/main.tscn").instantiate()
	Engine.get_main_loop().root.add_child(main)
	_last = main
	return main


func test_duel_event_unlocks_and_shows_toast() -> bool:
	var main := _boot()
	main.start_run(Duel.Mode.FIXED)
	main._on_duel_event(_parry(true))
	ok(main.save.achievements().has("first_parry") and main.save.achievements().has("first_just"), "対戦の出来事で取れる")
	eq(main.toast.queue.size() + (1 if main.toast.current != "" else 0), 2, "2 つ知らせる")
	main.toast._process(0.016)
	eq(main.toast.current, S.ach_name("first_parry"), "知らせの名前")
	main.free()
	return true


func test_auto_player_does_not_unlock() -> bool:
	var main := _boot()
	var dbg := preload("res://ui/debug.gd").new()
	dbg.main = main
	dbg.auto = true
	main.debug = dbg
	main.start_run(Duel.Mode.FIXED)
	main._on_duel_event(_parry(true))
	ok(main.save.achievements().is_empty(), "自動の相手(?auto=1)の回は取らない")
	main.debug = null
	dbg.free()
	main.free()
	return true


func test_achievements_screen() -> bool:
	var main := _boot()
	main.save.unlock(["first_parry", "win_fixed"], "2026-11-14")
	main.go_title()
	var b: Button = main._screen.find_child("btn_achievements", true, false)
	ok(b != null, "タイトルに「実績」")
	b.pressed.emit()
	eq(main.screen_name, "achievements", "一覧が開く")
	var labels: Array = main._screen.find_children("*", "Label", true, false)
	var texts: Array = labels.map(func(l: Label) -> String: return l.text)
	ok(S.ach_count(2, S.ACHIEVEMENTS.size()) in texts, "取った数: %s" % [texts.slice(0, 3)])
	ok("2026-11-14" in texts and S.ach_name("drill") in texts, "取った日と、まだの物の名前")
	for l: Label in labels:
		ok(Title.text_width(l) <= l.size.x + 0.5, "「%s」が枠に入る" % l.text)
	var back: Button = main._screen.find_child("btn_back", true, false)
	ok(back.get_rect().position.y >= 196.0 + 14 * 68.0, "戻るは一覧の下")
	back.pressed.emit()
	eq(main.screen_name, "title", "戻るでタイトルへ")
	main.free()
	return true
