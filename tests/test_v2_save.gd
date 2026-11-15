# v0.2.0 の保存のテスト: やさしい設定の記録は別の帳面(ext)、新しい設定は ext、知らない項目は消さない、
# v0.1.2 のタブ(本の保存しか知らない)が後から書いても ext は残る。
extends "res://tests/suite.gd"

const SaveStore := preload("res://save/save_store.gd")

const PATH := "user://v2_save.json"
const EXT := "user://v2_save_ext.json"


func _clean() -> void:
	for f: String in [PATH, EXT]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))


func _write(file: String, text: String) -> void:
	var f := FileAccess.open(file, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _read(file: String) -> Dictionary:
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(file))
	return v if v is Dictionary else {}


func _win(hits: int, ticks: int, easy: bool) -> Dictionary:
	return {"hits": hits, "ticks": ticks, "justs": 1, "retries": 0, "easy": easy}


func test_easy_records_go_to_their_own_book() -> bool:
	_clean()
	var s := SaveStore.new(PATH)
	s.record_win(Duel.Mode.FIXED, 0, _win(1, 9000, true))
	eq(s.fixed_best(), null, "ふつうの記録は空のまま")
	eq(s.fixed_best(true)["hits"], 1, "やさしいの記録")
	s.record_win(Duel.Mode.DAILY, 40, _win(2, 9000, true))
	eq(s.daily(40)["first"], null, "ふつうの今日は空のまま")
	eq(s.daily(40, true)["first"]["hits"], 2, "やさしいの今日")
	var r := s.record_win(Duel.Mode.FIXED, 0, _win(3, 9000, false))
	eq(r["prev_best"], null, "ふつうの最高は、やさしいの記録と比べない")
	eq(int(_read(PATH)["fixed"]["hits"]), 3, "本の保存にはふつうの記録")
	eq(int(_read(EXT)["easy"]["fixed"]["hits"]), 1, "ext にやさしいの記録")
	var again := SaveStore.new(PATH)
	eq(again.fixed_best(true)["hits"], 1, "読み直しても残る")
	_clean()
	return true


func test_new_settings_live_in_ext() -> bool:
	_clean()
	var s := SaveStore.new(PATH)
	s.set_setting("easy", true)
	s.set_setting("show_diff", false)
	s.set_setting("volume", 50)
	ok(not _read(PATH)["settings"].has("easy"), "本の保存の設定に easy は無い")
	eq(_read(EXT)["settings"]["easy"], true, "ext に easy")
	eq(int(_read(PATH)["settings"]["volume"]), 50, "音量は本の保存")
	var again := SaveStore.new(PATH)
	eq(again.settings()["easy"], true, "読み直した easy")
	eq(again.settings()["show_diff"], false, "読み直した show_diff")
	_clean()
	return true


func test_old_tab_writing_main_save_keeps_ext() -> bool:
	_clean()
	var s := SaveStore.new(PATH)
	s.set_setting("easy", true)
	s.record_win(Duel.Mode.FIXED, 0, _win(0, 8000, true))
	# v0.1.2 のタブが、本の保存だけを自分の知っている形で書いた
	_write(PATH, '{"version":1,"fixed":{"hits":4,"ticks":20000,"justs":0,"retries":0},"daily":null,"reached_boss":2,"settings":{"volume":25,"shake":true,"reduce_flash":false,"offset_ticks":0}}')
	var again := SaveStore.new(PATH)
	eq(again.settings()["easy"], true, "easy は残る")
	eq(again.fixed_best(true)["hits"], 0, "やさしいの記録は残る")
	eq(again.fixed_best()["hits"], 4, "古いタブが書いたふつうの記録")
	eq(again.settings()["volume"], 25, "古いタブが書いた音量")
	_clean()
	return true


func test_unknown_fields_are_kept() -> bool:
	_clean()
	_write(PATH, '{"version":1,"fixed":null,"daily":null,"reached_boss":1,"later":{"x":1},"settings":{"volume":75,"shake":true,"reduce_flash":false,"offset_ticks":0,"later_setting":3}}')
	_write(EXT, '{"version":1,"settings":{"easy":false,"show_diff":true,"bgm_volume":50},"easy":{"fixed":null,"daily":null,"later_book":1},"later_thing":{"a":1}}')
	var s := SaveStore.new(PATH)
	s.set_setting("shake", false)
	var main := _read(PATH)
	var ext := _read(EXT)
	eq(main.get("later"), {"x": 1.0}, "本の保存の知らない項目")
	eq(main["settings"].get("later_setting"), 3.0, "本の保存の知らない設定")
	eq(ext["settings"].get("bgm_volume"), 50.0, "ext の知らない設定")
	eq(ext.get("later_thing"), {"a": 1.0}, "ext の知らない項目")
	eq(ext["easy"].get("later_book"), 1.0, "やさしいの帳面の知らない項目")
	_clean()
	return true


func test_other_tab_easy_record_survives_a_stale_write() -> bool:
	_clean()
	var old_tab := SaveStore.new(PATH)
	var new_tab := SaveStore.new(PATH)
	new_tab.record_win(Duel.Mode.FIXED, 0, _win(0, 7000, true))
	old_tab.set_setting("volume", 25)  # 古い写しのまま書く
	var after := SaveStore.new(PATH)
	eq(after.fixed_best(true)["hits"], 0, "別のタブのやさしいの記録が残る")
	eq(after.settings()["volume"], 25, "こちらの設定も入る")
	_clean()
	return true


func test_broken_ext_starts_from_defaults() -> bool:
	_clean()
	_write(EXT, "{")
	var s := SaveStore.new(PATH)
	ok(s.load_failed, "ext が読めない時も「読めなかった」")
	eq(s.settings()["easy"], false, "既定値")
	_clean()
	return true


func test_drill_is_not_recorded() -> bool:
	_clean()
	var s := SaveStore.new(PATH)
	var r := s.record_win(Duel.Mode.DRILL, 0, _win(0, 100, false))
	eq(r["new_best"], false, "型の練習は記録しない")
	ok(not FileAccess.file_exists(PATH), "書かない")
	_clean()
	return true
