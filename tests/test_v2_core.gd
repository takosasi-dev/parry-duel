# v0.2.0 の対戦の決まりのテスト: 速さ(型の時間の伸び縮み)・広い窓・型の練習・押したずれ・押す癖。
# 型 1 個だけの対戦を作って確かめる。最初の型は tick 120 に始まる。
extends "res://tests/suite.gd"

const PatternStore := preload("res://core/pattern_store.gd")
const Rank := preload("res://core/rank.gd")

const START := 120
const T := START + 156  # 白・windup 60・travel 96 の当たる tick(速さ 100)


func _white() -> Array:
	return [atk("white", "L", 60, 96)]


func _duel(attacks: Array, opts: Dictionary, length: int = 600, mode: int = Duel.Mode.FIXED) -> Duel:
	return Duel.new(1, mode, 1, null, bosses_of([pattern("p", attacks, length)]), opts)


func test_scale_ticks_rounds() -> bool:
	eq(PatternStore.scale_ticks(96, 80), 120, "96 tick を 80% の速さで")
	eq(PatternStore.scale_ticks(60, 75), 80, "60 tick を 75% の速さで")
	eq(PatternStore.scale_ticks(0, 80), 0, "0 は 0 のまま")
	eq(PatternStore.scale_ticks(100, 130), 77, "速くすると短くなる(四捨五入)")
	var p := pattern("p", [atk("white", "L", 60, 96, 10, 0, 0)], 300)
	ok(PatternStore.scaled(p, 100) == p, "100 なら同じ物")
	var s := PatternStore.scaled(p, 80)
	eq(s["length"], 375, "長さも伸びる")
	eq(s["attacks"][0]["windup"], 75, "windup も伸びる")
	eq(p["attacks"][0]["windup"], 60, "元のデータは変えない")
	return true


func test_slower_speed_moves_contact() -> bool:
	var d := _duel(_white(), {"speed": 80})
	var e := first_of(collect_to(d, START + 1), "attack_start")
	eq(e["attack"]["contact"], START + 75 + 120, "80% の速さの当たる tick")
	return true


func test_easy_window_parries_wider_and_pushes_longer() -> bool:
	var d := _duel(_white(), {"window": B.EASY_PARRY_WINDOW, "just": B.EASY_JUST_WINDOW})
	eq(d.push_ticks, B.EASY_PARRY_WINDOW + 1, "押し込みは窓 + 1")
	var types_late := press_at(d, T + B.EASY_PARRY_WINDOW, "parry")
	ok("parry" in types_late, "窓の端(遅い側)で弾ける: %s" % [types_late])
	var d2 := _duel(_white(), {"window": B.EASY_PARRY_WINDOW, "just": B.EASY_JUST_WINDOW})
	run_to(d2, T - B.EASY_JUST_WINDOW)
	d2.press_parry()
	d2.step()
	eq(first_of(d2.events(), "parry").get("just"), true, "広いぴったりの端")
	var d3 := _duel(_white(), {})
	ok("parry_whiff" in press_at(d3, T - 15, "parry"), "ふつうの窓では 15 tick 早いと空振り")
	return true


func test_easy_flag_is_in_result() -> bool:
	eq(_duel(_white(), {"easy": true}).result()["easy"], true, "やさしいの印")
	eq(_duel(_white(), {}).result()["easy"], false, "ふつう")
	return true


func test_diffs_record_parries_and_near_whiffs() -> bool:
	var d := _duel([atk("white", "L", 60, 96), atk("white", "R", 60, 96, 150)], {}, 600)
	press_at(d, T - 3, "parry")
	eq(d.diffs, [-3], "弾いた差")
	var t2 := T + 150
	var ev := press_at(d, t2 - 20, "parry")  # 窓(12)の外、近い(36 以内)。遅い側は窓を過ぎると当たって消えるので、早い側だけ起きる
	ok("parry_whiff" in ev, "窓の外は空振り")
	eq(first_of(d.events(), "parry_whiff").get("near"), -20, "近くの白との差")
	eq(d.diffs, [-3, -20], "空振りの差も足す")
	eq(d.result()["diffs"], [-3, -20], "結果にも出る")
	eq(d.retry_carry()["diffs"], [-3, -20], "やり直しにも渡す")
	return true


func test_whiff_far_from_any_white_has_no_near() -> bool:
	var d := _duel(_white(), {})
	press_at(d, START + 10, "parry")
	eq(first_of(d.events(), "parry_whiff").get("near"), null, "遠い時は near が null")
	eq(d.diffs, [], "遠い空振りは足さない")
	return true


func test_drill_repeats_one_pattern_without_damage_or_stagger() -> bool:
	var a := pattern("a", [atk("white", "L", 60, 96)], 240)
	var b := pattern("b", [atk("red", "T", 60, 96)], 240)
	var data := bosses_of([a, b])
	var d := Duel.new(1, Duel.Mode.DRILL, 1, null, data, {"drill": "b"})
	eq(d.mode, Duel.Mode.DRILL, "型の練習")
	eq(d.drill_id, "b", "型の id")
	var seen := {}
	var events := collect_to(d, START + 240 * 6)
	for e: Dictionary in events:
		if e["type"] == "pattern_start":
			seen[e["id"]] = true
	eq(seen.keys(), ["b"], "同じ型だけが出る")
	ok(d.hits >= 3, "受けた数は数える(%d)" % d.hits)
	eq(d.player_hp, B.PLAYER_HP, "体力は減らない")
	ok(not d.over, "終わらない")
	ok(first_of(events, "hurt").is_empty(), "hurt は出さない")
	return true


func test_drill_parry_does_not_stagger_or_clear_teaching() -> bool:
	var t := pattern("t", [atk("white", "L", 60, 96)], 240, true)  # 教える型でも練習できる
	var d := Duel.new(1, Duel.Mode.DRILL, 1, null, bosses_of([t]), {"drill": "t"})
	var types_got := press_at(d, T, "parry")
	ok("parry" in types_got and not ("teach_clear" in types_got), "弾けて、教える型の成功にはならない: %s" % [types_got])
	eq(d.stagger, 0, "よろけは溜めない")
	return true


func test_drill_unknown_id_falls_back_to_practice() -> bool:
	var d := Duel.new(1, Duel.Mode.DRILL, 2, null, bosses_of([pattern("p", _white())]), {"drill": "none"})
	eq(d.mode, Duel.Mode.PRACTICE, "知らない型は、その敵の練習")
	eq(d.drill_id, "", "id は空")
	return true


func test_drill_finds_boss_and_phase_of_pattern() -> bool:
	var data: Array = PatternStore.shared()["bosses"]
	var id: String = data[2]["phases"][1]["patterns"][1]["id"]
	var d := Duel.new(1, Duel.Mode.DRILL, 1, null, null, {"drill": id})
	eq([d.boss, d.phase], [3, 2], "%s の敵と段階" % id)
	return true


func test_tendency() -> bool:
	eq(Rank.tendency([1, 2, 3], 0)["suggest"], null, "数が足りない")
	var early := [-4, -4, -4, -4, -4, -4, -4, -4]
	var t := Rank.tendency(early, 0)
	eq(t["n"], 8, "数")
	eq(t["mean_ms"], -33, "平均(ms、負 = 早い)")
	eq(t["suggest"], -4, "早いので、判定のずれを早い側へ")
	eq(Rank.tendency(early, -4)["suggest"], -8, "今のずれに足す")
	eq(Rank.tendency(early, -11)["suggest"], B.OFFSET_MIN, "範囲に収める")
	eq(Rank.tendency(early, B.OFFSET_MIN)["suggest"], null, "変えようがない時は null")
	eq(Rank.tendency([1, -1, 1, -1, 1, -1, 1, 1], 0)["suggest"], null, "ずれが小さい時は勧めない")
	return true


# 遅い速さと広い窓でも、同梱の型が全部、完璧に押す相手で無傷で倒せる(やさしい設定の組み合わせ)。
func test_easy_and_slow_are_beatable_by_perfect_bot() -> bool:
	for opts: Dictionary in [{"speed": B.EASY_SPEED, "window": B.EASY_PARRY_WINDOW, "just": B.EASY_JUST_WINDOW}, {"speed": B.SLOW_SPEED}]:
		for boss in range(1, B.BOSS_COUNT + 1):
			var d := Duel.new(1, Duel.Mode.PRACTICE, boss, null, null, opts)
			var bot := Bot.new()
			var guard := 0
			while not d.over and guard < 60000:
				bot.act(d)
				d.step()
				guard += 1
			ok(d.over and d.won and d.hits == 0, "敵 %d・%s: 終わり %s 勝ち %s 受けた数 %d" % [boss, opts, d.over, d.won, d.hits])
	return true
