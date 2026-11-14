# v0.2.0 の画面のテスト: 型の練習の画面と対戦・やさしい設定・押す癖の 1 行・ゲームパッドでの操作。
extends "res://tests/suite.gd"

const Title := preload("res://ui/title.gd")
const S := preload("res://core/strings.gd")
const ShareText := preload("res://core/share_text.gd")

var _last: Node = null


func _boot() -> Node:
	if _last != null and is_instance_valid(_last):
		_last.free()
	for f: String in ["user://save.json", "user://save_ext.json"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	var main: Node = load("res://ui/main.tscn").instantiate()
	Engine.get_main_loop().root.add_child(main)
	_last = main
	return main


func _all(node: Node, type: Variant, out: Array = []) -> Array:
	for c: Node in node.get_children():
		if c is CanvasItem and not c.visible:
			continue
		if c.is_queued_for_deletion():
			continue
		if is_instance_of(c, type):
			out.append(c)
		_all(c, type, out)
	return out


func _btn(screen: Node, node_name: String) -> Button:
	for b: Button in _all(screen, Button):
		if b.name == node_name:
			return b
	return null


func _texts(screen: Node) -> Array:
	return _all(screen, Label).map(func(l: Label) -> String: return l.text)


func _pad(main: Node, button: JoyButton) -> void:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	e.pressed = true
	main.get_viewport().push_input(e)
	var up := InputEventJoypadButton.new()
	up.button_index = button
	up.pressed = false
	main.get_viewport().push_input(up)


func test_practice_screen_lists_patterns_of_reached_bosses() -> bool:
	var main := _boot()
	_btn(main._screen, "btn_drill").pressed.emit()
	eq(main.screen_name, "practice", "型の練習の画面が開く")
	var scr: Node = main._screen
	eq(_btn(scr, "btn_drill_boss_1").disabled, false, "敵 1 は選べる")
	eq(_btn(scr, "btn_drill_boss_2").disabled, true, "着いていない敵 2 は選べない")
	var names := _all(scr, Button).map(func(b: Button) -> String: return str(b.name)).filter(func(n: String) -> bool: return n.begins_with("btn_drill_stone"))
	eq(names.size(), 2 + 3 + 4, "敵 1 の型(教える型を除く): %s" % [names])
	ok(not names.has("btn_drill_stone_1_teach"), "教える型は出さない")
	main.save.reach(3)
	main.open_practice()
	scr = main._screen
	_btn(scr, "btn_drill_boss_3").pressed.emit()
	ok(_btn(scr, "btn_drill_red_3_d") != null, "敵 3 に替えると敵 3 の型")
	ok(_btn(scr, "btn_drill_stone_2_a") == null, "敵 1 の型は消える")
	main.free()
	return true


func test_practice_screen_layout() -> bool:
	var main := _boot()
	main.save.reach(3)
	main.open_practice()
	var buttons := _all(main._screen, Button)
	for b: Button in buttons:
		ok(b.size.y >= 88.0, "%s は高さ 88 以上" % b.name)
		var r := Rect2(b.global_position - main._screen.global_position - main._screen._box.position, b.size)  # 画面の中の位置(入る時の動きを除く)
		ok(r.position.x >= 0.0 and r.end.x <= 720.0 and r.end.y <= 1280.0, "%s は画面の中" % b.name)
		for other: Button in buttons:
			ok(other == b or not b.get_global_rect().intersects(other.get_global_rect()), "%s と %s が重ならない" % [b.name, other.name])
	for l: Label in _all(main._screen, Label):
		ok(Title.text_width(l) <= l.size.x + 0.5, "「%s」が枠に入る" % l.text)
	main.free()
	return true


func test_drill_starts_the_chosen_pattern_and_slow_is_slower() -> bool:
	var main := _boot()
	main.open_practice()
	_btn(main._screen, "btn_drill_slow").pressed.emit()
	_btn(main._screen, "btn_drill_stone_2_b").pressed.emit()
	eq(main.screen_name, "duel", "対戦が始まる")
	var d: Duel = main.view.duel
	eq(d.mode, Duel.Mode.DRILL, "型の練習")
	eq(d.drill_id, "stone_2_b", "選んだ型")
	eq(d.speed, B.SLOW_SPEED, "ゆっくり")
	eq(main.save.reached_boss(), 1, "着いた敵は進めない")
	main.go_title()
	main.open_practice()
	_btn(main._screen, "btn_drill_normal").pressed.emit()
	_btn(main._screen, "btn_drill_stone_1_a").pressed.emit()
	eq(main.view.duel.speed, B.SPEED_NORMAL, "ふつうに戻せる")
	main.free()
	return true


func test_easy_setting_changes_the_run_and_its_records() -> bool:
	var main := _boot()
	main.save.set_setting("easy", true)
	main.go_title()
	ok(S.EASY_ON in _texts(main._screen), "タイトルにやさしい設定の印")
	main.start_run(Duel.Mode.FIXED)
	var d: Duel = main.view.duel
	eq([d.speed, d.parry_window, d.just_window, d.easy], [B.EASY_SPEED, B.EASY_PARRY_WINDOW, B.EASY_JUST_WINDOW, true], "やさしい設定の速さと窓")
	var r := d.result()
	r.merge({"won": true, "hits": 2, "ticks": 9000}, true)
	main.save.record_win(Duel.Mode.FIXED, 0, r)
	eq(main.save.fixed_best(), null, "ふつうの記録は空のまま")
	eq(main.save.fixed_best(true)["hits"], 2, "やさしいの記録")
	ok(ShareText.build("2026-11-14", Duel.Mode.FIXED, false, r).contains(S.SHARE_FIXED + "・" + S.EASY), "共有する文字にやさしいの印")
	main.save.set_setting("easy", false)
	main.start_run(Duel.Mode.FIXED)
	eq(main.view.duel.speed, B.SPEED_NORMAL, "切ればふつうに戻る")
	main.free()
	return true


func test_retry_keeps_easy() -> bool:
	var main := _boot()
	main.save.set_setting("easy", true)
	main.start_run(Duel.Mode.FIXED)
	main.retry()
	eq(main.view.duel.easy, true, "やり直しもやさしい設定のまま")
	main.free()
	return true


func test_settings_has_new_switches() -> bool:
	var main := _boot()
	main.open_settings()
	var scr: Node = main._settings
	_btn(scr, "btn_diff_off").pressed.emit()
	eq(main.save.settings()["show_diff"], false, "押したずれを出さない")
	_btn(scr, "btn_easy_on").pressed.emit()
	eq(main.save.settings()["easy"], true, "やさしい 入")
	main.close_settings()
	main.start_run(Duel.Mode.FIXED)
	eq(main.view._show_diff, false, "対戦にも効く")
	main.free()
	return true


func test_result_shows_tendency_and_applies_offset() -> bool:
	var main := _boot()
	var r := {"won": true, "mode": Duel.Mode.FIXED, "boss": 3, "hits": 1, "ticks": 9000, "justs": 3, "parries": 20, "retries": 0,
		"easy": false, "diffs": [-4, -4, -4, -4, -4, -4, -4, -4, -3, -5], "offset": 0}
	var info := {"result": r, "mode": Duel.Mode.FIXED, "practice": false, "date": "2026-11-14",
		"record": {"prev_best": null, "new_best": true, "first_today": false, "saved": true}, "share_text": "x"}
	main._clear_screens()
	main.screen_name = "result"
	main._screen = main._open("result", info)
	ok(S.tendency(-33, 10) in _texts(main._screen), "押す癖の 1 行: %s" % [_texts(main._screen)])
	var apply := _btn(main._screen, "btn_apply_offset")
	ok(apply != null, "判定のずれを変えるボタン")
	if apply != null:
		apply.pressed.emit()
		eq(main.save.settings()["offset_ticks"], -4, "勧めた値になる")
		ok(apply.disabled, "押した後は押せない")
	for b: Button in _all(main._screen, Button):
		ok(b.get_global_rect().end.y <= 1280.0, "%s は画面の中" % b.name)
	main.free()
	return true


func test_result_without_enough_presses_has_no_tendency() -> bool:
	var main := _boot()
	var r := {"won": true, "mode": Duel.Mode.FIXED, "boss": 3, "hits": 1, "ticks": 9000, "justs": 3, "parries": 20, "retries": 0, "diffs": [-4], "offset": 0}
	main._clear_screens()
	main.screen_name = "result"
	main._screen = main._open("result", {"result": r, "mode": Duel.Mode.FIXED, "practice": false, "date": "2026-11-14",
		"record": {"prev_best": null, "new_best": true, "first_today": false, "saved": true}, "share_text": "x"})
	ok(_btn(main._screen, "btn_apply_offset") == null, "数が足りなければ出さない")
	main.free()
	return true


func test_pad_selects_then_presses_menu_buttons() -> bool:
	var main := _boot()
	_pad(main, JOY_BUTTON_A)
	eq(main.screen_name, "title", "最初の A は選ぶだけ")
	ok(main.pad, "パッドの扱いになる")
	var focus: Control = main.get_viewport().gui_get_focus_owner()
	eq(str(focus.name) if focus != null else "", "btn_fixed", "最初のボタンが選ばれる")
	_pad(main, JOY_BUTTON_A)
	eq(main.screen_name, "duel", "次の A で押す")
	# 対戦の最中は、ボタンを選ばない。A は弾く
	ok(main.get_viewport().gui_get_focus_owner() == null, "対戦の最中は何も選ばない")
	main.view.duel.clear_input()
	_pad(main, JOY_BUTTON_A)
	ok(main.view.duel._want_parry, "A で弾く")
	main.view.duel.clear_input()
	_pad(main, JOY_BUTTON_LEFT_SHOULDER)
	ok(main.view.duel._want_dodge, "LB で避ける")
	main.free()
	return true


func test_mouse_after_pad_clears_selection() -> bool:
	var main := _boot()
	_pad(main, JOY_BUTTON_A)
	ok(main.get_viewport().gui_get_focus_owner() != null, "パッドで選んだ")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(5, 5)
	main.get_viewport().push_input(click)
	ok(not main.pad, "マウスに戻る")
	ok(main.get_viewport().gui_get_focus_owner() == null, "選んだ印が消える")
	main.free()
	return true


func test_pad_b_goes_back_from_settings() -> bool:
	var main := _boot()
	main.open_settings()
	_pad(main, JOY_BUTTON_B)  # 選ぶだけ
	_pad(main, JOY_BUTTON_B)  # 戻る(設定の Esc の受け口へ)
	eq(main.screen_name, "title", "B で設定から戻る")
	main.free()
	return true
