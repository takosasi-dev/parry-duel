# v0.3.0 の終わらない連戦のテスト: 3 体の繰り返し・周ごとの速さ・体力の持ち越し・記録・画面。
extends "res://tests/suite.gd"

const SaveStore := preload("res://save/save_store.gd")
const ShareText := preload("res://core/share_text.gd")
const S := preload("res://core/strings.gd")
const Rank := preload("res://core/rank.gd")

const PATH := "user://v3_save.json"

var _last: Node = null


# 今の敵を、反撃まで進めて倒す(よろけを満たして反撃を 3 回)。
static func _beat(d: Duel) -> void:
	var bot := Bot.new()
	var guard := 0
	var start_kills := d.kills
	while d.kills == start_kills and not d.over and guard < 60000:
		bot.act(d)
		d.step()
		guard += 1


func test_speed_steps_up_each_lap_and_stops_at_cap() -> bool:
	eq(Duel.endless_speed(100, 0), 100, "1 周目")
	eq(Duel.endless_speed(100, 2), 100, "1 周目の 3 体目")
	eq(Duel.endless_speed(100, 3), 100 + B.ENDLESS_STEP, "2 周目")
	eq(Duel.endless_speed(100, 300), B.ENDLESS_MAX, "上限で止まる")
	eq(Duel.endless_speed(B.EASY_SPEED, 300), B.EASY_SPEED * B.ENDLESS_MAX / 100, "やさしい設定は、やさしい速さに掛ける")
	return true


func test_bosses_cycle_and_hp_carries_over() -> bool:
	var d := Duel.new(B.FIXED_SEED, Duel.Mode.ENDLESS, 1)
	ok(not d.teach_done.has(false), "教える型は出さない")
	var seen: Array = []
	for i in 4:
		seen.append(d.boss)
		_beat(d)
		eq(d.state, Duel.State.WAIT_NEXT, "%d 体目を倒すと、次を待つ(終わらない)" % (i + 1))
		ok(not d.over, "終わらない")
		d.player_hp = 2  # 減った体力が持ち越されて、1 だけ戻る事を見る
		d.next_boss()
		eq(d.player_hp, 2 + B.ENDLESS_HEAL, "体力は持ち越して %d 戻る" % B.ENDLESS_HEAL)
	eq(seen, [1, 2, 3, 1], "敵 1・2・3 を繰り返す")
	eq(d.kills, 4, "倒した数")
	eq(d.speed, 100 + B.ENDLESS_STEP, "2 周目は速い")
	eq(d.result()["kills"], 4, "結果にも倒した数")
	return true


func test_second_lap_changes_pattern_order() -> bool:
	var first: Array = []
	var second: Array = []
	var d := Duel.new(B.FIXED_SEED, Duel.Mode.ENDLESS, 1)
	for lap in 2:
		var ids: Array = []
		for i in 3:
			var guard := 0
			var bot := Bot.new()
			var start_kills := d.kills
			while d.kills == start_kills and not d.over and guard < 60000:
				bot.act(d)
				d.step()
				for e: Dictionary in d.events():
					if e["type"] == "pattern_start" and d.boss == 1:
						ids.append(e["id"])
				guard += 1
			d.next_boss()
		if lap == 0:
			first = ids
		else:
			second = ids
	ok(first != second, "2 周目は型の順が変わる(%s / %s)" % [first, second])
	return true


func test_death_ends_the_run() -> bool:
	var d := Duel.new(B.FIXED_SEED, Duel.Mode.ENDLESS, 1)
	var guard := 0
	while not d.over and guard < 60000:  # 何も押さない
		d.step()
		guard += 1
	ok(d.over and not d.won, "負けで終わる")
	eq(d.kills, 0, "倒した数 0")
	return true


func test_endless_record_and_rank() -> bool:
	ok(Rank.better_endless({"kills": 5, "hits": 9, "ticks": 9}, {"kills": 4, "hits": 0, "ticks": 0}), "倒した数が多い方が上")
	ok(Rank.better_endless({"kills": 5, "hits": 1, "ticks": 9}, {"kills": 5, "hits": 2, "ticks": 0}), "同じなら受けた数")
	for f: String in [PATH, "user://v3_save_ext.json"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	var s := SaveStore.new(PATH)
	var r1 := s.record_endless({"kills": 4, "hits": 6, "ticks": 30000, "easy": false})
	eq(r1["new_best"], true, "初めての記録")
	var r2 := s.record_endless({"kills": 3, "hits": 0, "ticks": 20000, "easy": false})
	eq(r2["new_best"], false, "倒した数が少なければ最高ではない")
	s.record_endless({"kills": 2, "hits": 0, "ticks": 20000, "easy": true})
	var again := SaveStore.new(PATH)
	eq(again.endless_best()["kills"], 4, "ふつうの最高")
	eq(again.endless_best(true)["kills"], 2, "やさしいの最高は別")
	var other := SaveStore.new(PATH)
	other.record_endless({"kills": 9, "hits": 1, "ticks": 1, "easy": false})
	again.set_setting("volume", 25)  # 古い写しのまま書いても、別のタブの最高は消えない
	eq(SaveStore.new(PATH).endless_best()["kills"], 9, "別のタブの最高が残る")
	for f: String in [PATH, "user://v3_save_ext.json"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	return true


func test_share_text_for_endless() -> bool:
	var t := ShareText.build("2026-11-14", Duel.Mode.ENDLESS, false, {"kills": 12, "hits": 7, "ticks": 37488, "justs": 80, "easy": false})
	var lines := t.split("\n")
	eq(lines.size(), 3, "3 行")
	ok(lines[0].contains(S.SHARE_ENDLESS), "入口の名前: %s" % lines[0])
	eq(lines[1], "12 体 / 受けた数 7 / 312.4秒 / ぴったり 80", "2 行目")
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


func _find(node: Node, node_name: String) -> Node:
	return node.find_child(node_name, true, false)


func test_title_entry_is_locked_until_boss_3() -> bool:
	var main := _boot()
	var b: Button = _find(main._screen, "btn_endless")
	ok(b != null and b.disabled, "敵 3 に着くまで押せない")
	main.start_endless()
	eq(main.screen_name, "title", "呼んでも始まらない")
	main.save.reach(3)
	main.go_title()
	b = _find(main._screen, "btn_endless")
	ok(b != null and not b.disabled, "敵 3 に着くと押せる")
	b.pressed.emit()
	eq(main.screen_name, "duel", "始まる")
	eq(main.view.duel.mode, Duel.Mode.ENDLESS, "終わらない連戦")
	main.free()
	return true


func test_interval_and_result_screens() -> bool:
	var main := _boot()
	main.save.reach(3)
	main.start_endless()
	var d: Duel = main.view.duel
	for i in 3:
		_beat(d)
		d.next_boss()
	_beat(d)
	main._on_boss_beaten()
	var texts: Array = []
	for l: Node in main._screen.find_children("*", "Label", true, false):
		texts.append((l as Label).text)
	ok(S.endless_beaten(4) in texts, "合間に倒した数: %s" % [texts])
	ok(S.endless_speed(100 + B.ENDLESS_STEP) in texts, "次の敵の速さ")
	main.next_boss()
	eq(main.view.duel.boss, 2, "5 体目は敵 2")
	# 負けて終わる
	main.view.duel.player_hp = 0
	main.view.duel.step()
	main._on_finished()
	eq(main.screen_name, "result", "結果へ")
	texts = []
	for l: Node in main._screen.find_children("*", "Label", true, false):
		texts.append((l as Label).text)
	ok(S.kills(4) in texts and S.ENDLESS in texts and S.FIRST_RECORD in texts, "結果に倒した数・見出し・初めての記録: %s" % [texts])
	eq(main.save.endless_best()["kills"], 4, "記録が残る")
	ok(_find(main._screen, "btn_copy") != null, "共有できる")
	eq(main._screen._slashed, 3, "4 体倒せば印は 3 つとも斜線")
	main.free()
	return true


func test_result_slashes_only_beaten_marks() -> bool:
	var main := _boot()
	main.save.reach(3)
	main.start_endless()
	_beat(main.view.duel)
	main._on_boss_beaten()
	main.next_boss()
	main.view.duel.player_hp = 0
	main.view.duel.step()
	main._on_finished()
	eq(main._screen._slashed, 1, "1 体だけなら斜線は 1 つ")
	main.free()
	return true
