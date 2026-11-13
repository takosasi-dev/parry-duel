# 記録の比べ方・タイミング合わせ・日付・共有する文字・型の検査の落とし方・core の決まり(AC-23〜AC-25・AC-30・AC-31)。
extends "res://tests/suite.gd"

const Rank := preload("res://core/rank.gd")
const Calib := preload("res://core/calib.gd")
const DayIndex := preload("res://core/day_index.gd")
const ShareText := preload("res://core/share_text.gd")
const PatternStore := preload("res://core/pattern_store.gd")
const S := preload("res://core/strings.gd")


func test_ac23_rank_order() -> bool:
	ok(Rank.better({"hits": 2, "ticks": 9000}, {"hits": 3, "ticks": 8000}), "(2, 9000) は (3, 8000) より上")
	ok(not Rank.better({"hits": 3, "ticks": 8000}, {"hits": 2, "ticks": 9000}), "逆は下")
	ok(Rank.better({"hits": 2, "ticks": 8000}, {"hits": 2, "ticks": 9000}), "(2, 8000) は (2, 9000) より上")
	ok(not Rank.better({"hits": 2, "ticks": 9000}, {"hits": 2, "ticks": 9000}), "同じ物は上でない")
	return true


func test_time_text() -> bool:
	eq(Rank.seconds_text(18504), "154.2", "18,504 tick")
	eq(Rank.seconds_text(0), "0.0", "0 tick")
	eq(Rank.seconds_text(119), "0.9", "切り捨て")
	eq(Rank.seconds_text(120), "1.0", "1 秒")
	eq(Rank.ms(12), 100, "12 tick は 100 ms")
	eq(Rank.ms(5), 42, "5 tick は 約 42 ms")
	eq(Rank.ms(-2), -17, "負のずれ")
	return true


func test_ac24_calib_median() -> bool:
	eq(Calib.suggest([5, 7, 6, 6, 8, 4]), 6, "+5・+7・+6・+6・+8・+4 → +6")
	eq(Calib.suggest([1, 2, 3, 4]), 2, "偶数個なら小さい方の中央")
	eq(Calib.suggest([3, 9, 1, 7, 5]), 5, "奇数個の中央値")
	eq(Calib.suggest([5, 7, 6]), null, "有効な差が 3 個なら測れなかった")
	eq(Calib.suggest([30, 30, 30, 30]), 12, "上は 12 に切り詰める")
	eq(Calib.suggest([-30, -30, -30, -30]), -12, "下は −12 に切り詰める")
	return true


# 押すずれを渡して、タイミング合わせを最後まで回す。diffs[k] が null の回は押さない。
func _run_calib(diffs: Array) -> Calib:
	var c := Calib.new()
	var guard := 0
	while not c.done and guard < 5000:
		for k in diffs.size():
			if diffs[k] != null and c.tick == Calib.LEAD + k * B.CALIB_INTERVAL + B.CALIB_WINDUP + B.CALIB_TRAVEL + int(diffs[k]):
				c.press()
		c.step()
		guard += 1
	return c


func test_calib_run_skips_first_two() -> bool:
	var c := _run_calib([30, -30, 5, 7, 6, 6, 8, 4])
	ok(c.done, "8 回で終わる")
	eq(c.result(), 6, "最初の 2 回を除いた中央値")
	eq(c.snapshot()["count"], 8, "8 / 8")
	return true


func test_calib_run_too_few() -> bool:
	eq(_run_calib([0, 0, 3, null, null, 3, null, 3]).result(), null, "有効な押しが 3 回なら測れなかった")
	eq(_run_calib([null, null, 3, 3, 3, 3, null, null]).result(), 3, "4 回あれば測れる")
	return true


func test_calib_drops_far_presses() -> bool:
	var c := Calib.new()
	var contact: int = Calib.LEAD + B.CALIB_WINDUP + B.CALIB_TRAVEL
	while c.tick < contact - 37:
		c.step()
	c.press()
	c.step()
	eq(c.events()[0]["type"], "calib_miss", "37 tick 早い押しは捨てる")
	while c.tick < contact - 36:
		c.step()
	c.press()
	c.step()
	eq(c.events()[0]["type"], "calib_hit", "36 tick 早い押しは数える")
	eq(c.diffs[0], -36, "差は 押した tick − 当たる tick")
	c.press()
	c.step()
	eq(c.events()[0]["type"], "calib_miss", "同じ攻撃への 2 回目は数えない")
	return true


func test_calib_timing_matches_spec() -> bool:
	var c := Calib.new()
	var starts: Array = []
	while not c.done:
		c.step()
		for e: Dictionary in c.events():
			if e["type"] == "attack_start":
				starts.append(e["attack"])
	eq(starts.size(), 8, "8 回")
	for k in range(1, 8):
		eq(starts[k]["start"] - starts[k - 1]["start"], 144, "144 tick ごと")
	eq(starts[0]["contact"] - starts[0]["start"], 144, "windup 48 + travel 96")
	eq([starts[0]["kind"], starts[0]["arm"]], ["white", "T"], "白・上")
	return true


func test_ac25_day_index() -> bool:
	eq(DayIndex.day_index(2026, 1, 1), 0, "2026-01-01")
	eq(DayIndex.day_index(2026, 11, 12), 315, "2026-11-12")
	eq(DayIndex.day_index(2027, 1, 1), 365, "2027-01-01")
	eq(DayIndex.day_index(2025, 12, 31), 0, "2025-12-31 は 0")
	eq(DayIndex.day_index(2028, 3, 1), 365 + 365 + 31 + 29, "うるう年をまたぐ")
	return true


func test_day_seed() -> bool:
	eq(DayIndex.day_seed(0), 2654435761, "通し日数 0 の種")
	eq(DayIndex.day_seed(315), (316 * 2654435761) & 0xFFFFFFFF, "§9.13 の式")
	var seen := {}
	for day in 400:
		var s := DayIndex.day_seed(day)
		ok(s > 0 and s <= 0xFFFFFFFF, "32 ビットの正の数")
		seen[s] = true
	eq(seen.size(), 400, "日ごとに違う")
	eq(DayIndex.date_string(2026, 1, 5), "2026-01-05", "日付の文字")
	return true


func test_ac30_share_daily_first() -> bool:
	var r := {"hits": 2, "ticks": 18504, "justs": 21, "retries": 0}
	eq(ShareText.build("2026-11-12", Duel.Mode.DAILY, true, r),
		"ParryDuel 2026-11-12(今日の3連戦・1回目)\n受けた数 2 / 154.2秒 / ぴったり 21 / やり直し 0\n" + S.SHARE_URL, "今日の 1 回目")
	return true


func test_ac30_share_daily_again_and_fixed() -> bool:
	var r := {"hits": 11, "ticks": 24000, "justs": 3, "retries": 2}
	eq(ShareText.build("2026-11-12", Duel.Mode.DAILY, false, r).split("\n")[0], "ParryDuel 2026-11-12(今日の3連戦)", "今日の 2 回目から")
	eq(ShareText.build("2027-01-01", Duel.Mode.FIXED, false, r),
		"ParryDuel 2027-01-01(いつもの3連戦)\n受けた数 11 / 200.0秒 / ぴったり 3 / やり直し 2\n" + S.SHARE_URL, "いつもの3連戦")
	return true


func test_ac30_share_unhurt() -> bool:
	var r := {"hits": 0, "ticks": 14400, "justs": 40, "retries": 0}
	eq(ShareText.build("2026-11-12", Duel.Mode.FIXED, false, r).split("\n")[1], "受けた数 0(無傷) / 120.0秒 / ぴったり 40 / やり直し 0", "無傷")
	ok(S.SHARE_URL.begins_with("https://") and S.SHARE_URL.ends_with("/parry-duel/"), "URL は 1 か所")
	return true


func test_strings_format() -> bool:
	eq(S.hits_or_unhurt(0), "無傷", "受けた数 0 は無傷")
	eq(S.hits_or_unhurt(2), "受けた数 2", "受けた数")
	eq(S.best_line(2, "154.2"), "最高 受けた数 2 / 154.2秒", "S1 の最高")
	eq(S.daily_line(4, 2), "1回目 受けた数 4 / 今日の最高 受けた数 2", "S1 の今日")
	eq(S.signed_ms(17), "+17 ms", "正")
	eq(S.signed_ms(-8), "−8 ms", "負")
	eq(S.signed_ms(0), "0 ms", "0")
	eq(S.diff_fewer_hits(1), "最高より 受けた数 −1(新しい記録)", "S4 の差")
	return true


# 同梱の型の写しを作り、1 か所だけ壊して検査に通す。
func _broken(edit: Callable) -> Array:
	var j := JSON.new()
	j.parse(FileAccess.get_file_as_string(PatternStore.PATH))
	var raw: Dictionary = j.data
	edit.call(raw["bosses"])
	var shape := PatternStore.check_shape(raw)
	if not shape.is_empty():
		return shape
	return PatternStore.check_all(PatternStore._normalize(raw))


func _p(bosses: Array, b: int, ph: int, i: int) -> Dictionary:
	return bosses[b]["phases"][ph]["patterns"][i]


func test_check_a_shape() -> bool:
	eq(_broken(func(_b: Array) -> void: pass), [], "壊さなければ通る")
	ok(not _broken(func(b: Array) -> void: b.pop_back()).is_empty(), "敵が 2 体")
	ok(not _broken(func(b: Array) -> void: b[0]["phases"][2]["patterns"].pop_back()).is_empty(), "段階 3 の型が 3 個")
	ok(not _broken(func(b: Array) -> void: _p(b, 0, 0, 0).erase("teach")).is_empty(), "最初が教える型でない")
	ok(not _broken(func(b: Array) -> void: _p(b, 0, 1, 0)["teach"] = true).is_empty(), "教える型が余分にある")
	ok(not _broken(func(b: Array) -> void: _p(b, 0, 1, 0)["attacks"][0]["kind"] = "blue").is_empty(), "知らない kind")
	ok(not _broken(func(b: Array) -> void: _p(b, 0, 1, 0)["attacks"][0]["arm"] = "X").is_empty(), "知らない arm")
	ok(not _broken(func(b: Array) -> void: _p(b, 0, 1, 0)["attacks"][0]["windup"] = 48.5).is_empty(), "整数でない時間")
	ok(not _broken(func(b: Array) -> void: _p(b, 0, 1, 0)["attacks"][0]["at"] = -1).is_empty(), "負の時間")
	ok(not PatternStore.load_text("{").get("ok"), "JSON でない")
	ok(not PatternStore.load_text("[]").get("ok"), "辞書でない")
	return true


func test_check_b_times() -> bool:
	ok(not _broken(func(b: Array) -> void: _p(b, 0, 1, 0)["attacks"][0]["windup"] = 35).is_empty(), "windup 35")
	ok(not _broken(func(b: Array) -> void: _p(b, 0, 1, 0)["attacks"][1]["travel1"] = 41).is_empty(), "travel 41")
	ok(not _broken(func(b: Array) -> void: _p(b, 1, 1, 0)["attacks"][0]["hold"] = 35).is_empty(), "hold 35")
	ok(not _broken(func(b: Array) -> void: _p(b, 1, 1, 0)["attacks"][0]["hold"] = 97).is_empty(), "hold 97")
	ok(not _broken(func(b: Array) -> void: _p(b, 1, 1, 0)["attacks"][0]["travel2"] = 23).is_empty(), "ための後の travel 23")
	ok(not _broken(func(b: Array) -> void: _p(b, 0, 1, 0)["attacks"][0]["travel2"] = 30).is_empty(), "hold 0 なのに travel2")
	return true


func test_check_c_gaps() -> bool:
	ok(not _broken(func(b: Array) -> void: _p(b, 0, 1, 2)["attacks"][1]["at"] = 29).is_empty(), "当たる tick の差 29")
	ok(not _broken(func(b: Array) -> void: _p(b, 2, 1, 1)["attacks"][1]["at"] = 114).is_empty(), "赤の後 66 tick に次が来る")
	eq(_broken(func(b: Array) -> void: _p(b, 2, 1, 1)["attacks"][1]["at"] = 115), [], "赤の後 67 tick なら通る")
	return true


func test_check_d_length() -> bool:
	ok(not _broken(func(b: Array) -> void: _p(b, 0, 0, 1)["length"] = 299).is_empty(), "length が 最後 + 24 に足りない")
	return true


func test_check_e_kinds() -> bool:
	ok(not _broken(func(b: Array) -> void: _p(b, 0, 1, 0)["attacks"][0]["kind"] = "red").is_empty(), "敵 1 に赤")
	ok(not _broken(func(b: Array) -> void:
		var a: Dictionary = _p(b, 0, 0, 1)["attacks"][0]
		a["travel1"] = 48
		a["hold"] = 48
		a["travel2"] = 48).is_empty(), "敵 1 に ため")
	ok(not _broken(func(b: Array) -> void: _p(b, 1, 1, 0)["attacks"][2]["kind"] = "red").is_empty(), "敵 2 に赤")
	ok(not _broken(func(b: Array) -> void:
		var a: Dictionary = _p(b, 1, 1, 0)["attacks"][0]
		a["travel1"] = 96
		a["hold"] = 0
		a["travel2"] = 0
		a["at"] = 60).is_empty(), "敵 2 の型に ため が無い")
	ok(not _broken(func(b: Array) -> void: _p(b, 2, 0, 1)["attacks"][0]["kind"] = "white").is_empty(), "敵 3 の型に赤が無い")
	return true


func test_check_f_counts() -> bool:
	ok(not _broken(func(b: Array) -> void: _p(b, 0, 1, 0)["attacks"].resize(1)).is_empty(), "段階 2 に攻撃 1 つ")
	ok(not _broken(func(b: Array) -> void: _p(b, 0, 2, 0)["attacks"].resize(2)).is_empty(), "段階 3 に攻撃 2 つ")
	return true


func test_inv9_teach_patterns_are_fixed() -> bool:
	ok(not _broken(func(b: Array) -> void: _p(b, 0, 0, 0)["attacks"][0]["travel1"] = 170).is_empty(), "教える型の中身を変えた")
	ok(not _broken(func(b: Array) -> void: _p(b, 2, 0, 0)["length"] = 400).is_empty(), "教える型の長さを変えた")
	ok(not _broken(func(b: Array) -> void: _p(b, 1, 0, 0)["id"] = "swing_1_x").is_empty(), "教える型の id を変えた")
	return true


func test_nfr7_readable_length() -> bool:
	for boss: Dictionary in PatternStore.shared()["bosses"]:
		for phase: Dictionary in boss["phases"]:
			for p: Dictionary in phase["patterns"]:
				for a: Dictionary in p["attacks"]:
					ok(a["windup"] + a["travel1"] + a["hold"] + a["travel2"] >= 78, p["id"] + ": 予兆から当たるまで 78 tick 以上")
	return true


func test_patterns_same_arm_do_not_overlap() -> bool:
	# 同じ腕の次の攻撃は、前の攻撃が線に届いた後に始まる。同じ腕の頭が 2 つ飛んで見えない
	for boss: Dictionary in PatternStore.shared()["bosses"]:
		for phase: Dictionary in boss["phases"]:
			for p: Dictionary in phase["patterns"]:
				var busy := {}
				var sorted: Array = p["attacks"].duplicate()
				sorted.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x["at"] < y["at"])
				for a: Dictionary in sorted:
					ok(a["at"] >= int(busy.get(a["arm"], -999)), "%s: 腕 %s の攻撃が重なる" % [p["id"], a["arm"]])
					busy[a["arm"]] = a["at"] + a["windup"] + a["travel1"] + a["hold"] + a["travel2"]
	return true


func _core_files() -> Array:
	return Array(DirAccess.get_files_at("res://core")).filter(func(f: String) -> bool: return f.ends_with(".gd"))


func test_ac31_core_is_pure() -> bool:
	var files := _core_files()
	ok(files.size() >= 12, "core のファイルが揃っている")
	var banned := RegEx.new()
	banned.compile("\\b(sin|cos|randf|randi|randf_range|randi_range|randomize)\\s*\\(|\\bTime\\.|\\bInput\\.|\\bEngine\\.|\\bOS\\.")
	for f: String in files:
		var text := FileAccess.get_file_as_string("res://core/" + f)
		var first := text.split("\n")
		var extends_line := ""
		for line: String in first:
			if line.begins_with("extends"):
				extends_line = line.strip_edges()
				break
		eq(extends_line, "extends RefCounted", f + " は RefCounted")
		ok(text.begins_with("#"), f + " の冒頭に責務のコメント")
		for line: String in first:
			var code := line.split("#")[0]
			ok(banned.search(code) == null, "%s に使ってはいけない呼び出し: %s" % [f, line.strip_edges()])
	return true


func test_ac31_judge_has_no_float() -> bool:
	var text := FileAccess.get_file_as_string("res://core/judge.gd")
	var decimal := RegEx.new()
	decimal.compile("\\d\\.\\d|\\bfloat\\b|\\bfloor|\\bround|\\bceil|\\blerp|\\bVector2\\b|[^/]/[^/]")
	var quoted := RegEx.new()
	quoted.compile("\"[^\"]*\"")
	for line: String in text.split("\n"):
		var code := quoted.sub(line.split("#")[0], "", true)
		ok(decimal.search(code) == null, "judge.gd に小数の計算: " + line.strip_edges())
	return true


func test_nfr14_tuning_lives_in_balance() -> bool:
	# duel・judge・sequencer・calib に、2 桁以上の数をじかに書いていない(調整値は balance.gd)
	var number := RegEx.new()
	number.compile("(?<![\\w.\"])\\d{2,}(?![\\w\"])")
	for f: String in ["duel.gd", "judge.gd", "sequencer.gd"]:
		for line: String in FileAccess.get_file_as_string("res://core/" + f).split("\n"):
			var code := line.split("#")[0]
			ok(number.search(code) == null, "%s に数がじかに書いてある: %s" % [f, line.strip_edges()])
	return true
