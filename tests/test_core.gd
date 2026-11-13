# 判定・避ける・硬直・よろけ・反撃・段階・教える型のテスト(AC-3〜AC-17 と E-1〜E-8)。
# 型 1 個だけの対戦を作り、境い目を 1 tick ずつ確かめる。最初の型は tick 120 に始まる。
extends "res://tests/suite.gd"

const Attack := preload("res://core/attack.gd")
const Judge := preload("res://core/judge.gd")

const START := 120  # INTRO が明けて最初の型が始まる tick
const T := START + 156  # 白・windup 60・travel 96 を at 0 に置いた時の当たる tick


func _white() -> Array:
	return [atk("white", "L", 60, 96)]


func _red() -> Array:
	return [atk("red", "T", 60, 96)]


func test_ac3_contact_tick_plain() -> bool:
	var d := duel_of([atk("white", "L", 120, 180)])
	var e := first_of(collect_to(d, START + 1), "attack_start")
	eq(e.get("tick"), START, "型の始まりの tick に攻撃が出る")
	eq(e["attack"]["contact"], START + 300, "windup 120・travel1 180 の当たる tick")
	return true


func test_ac3_contact_tick_hold() -> bool:
	var d := duel_of([atk("white", "R", 96, 72, 0, 72, 72)])
	var e := first_of(collect_to(d, START + 1), "attack_start")
	eq(e["attack"]["contact"], START + 312, "ため(96・72・72・72)の当たる tick")
	eq(Attack.contact_tick(atk("white", "R", 96, 72, 30, 72, 72), 500), 812, "contact_tick は始まる tick から数える")
	return true


func test_ac4_just_window() -> bool:
	for diff in range(-B.JUST_WINDOW, B.JUST_WINDOW + 1):
		var d := duel_of(_white())
		run_to(d, T + diff)
		d.press_parry()
		d.step()
		var e := first_of(d.events(), "parry")
		ok(e.get("just") == true, "T%+d は ぴったり" % diff)
		eq(d.stagger, 2, "T%+d の よろけ" % diff)
		eq(d.justs, 1, "T%+d の ぴったりの数" % diff)
	return true


func test_ac4_parry_window() -> bool:
	for diff: int in [-12, -11, -9, -7, -6, 6, 7, 9, 11, 12]:
		var d := duel_of(_white())
		run_to(d, T + diff)
		d.press_parry()
		d.step()
		var e := first_of(d.events(), "parry")
		ok(e.get("just") == false, "T%+d は 弾き" % diff)
		eq(d.stagger, 1, "T%+d の よろけ" % diff)
		eq(e.get("diff"), diff, "T%+d の差" % diff)
	return true


func test_ac4_outside_is_whiff() -> bool:
	for diff: int in [-13, 13]:
		var d := duel_of(_white())
		eq(press_at(d, T + diff, "parry")[0], "parry_whiff", "T%+d は空振り" % diff)
		eq(d.stagger, 0, "空振りで よろけ は増えない")
		eq(d.lock, B.WHIFF_LOCK - 1, "空振りの硬直")
	return true


func test_ac5_whiff_lock_drops_input() -> bool:
	for what: String in ["parry", "dodge"]:
		var d := duel_of(_white())
		press_at(d, 10, "parry")
		eq(press_at(d, 10 + B.WHIFF_LOCK - 1, what), [], "空振りの 53 tick 後の %s は捨てられる" % what)
		var d2 := duel_of(_white())
		press_at(d2, 10, "parry")
		eq(press_at(d2, 10 + B.WHIFF_LOCK, what).size(), 1, "空振りの 54 tick 後の %s は使われる" % what)
	return true


func test_ac6_white_hits_at_t13() -> bool:
	var d := duel_of(_white())
	var before := collect_to(d, T + 13)
	ok(first_of(before, "hurt").is_empty(), "T + 12 までは当たらない")
	eq(d.player_hp, 5, "T + 12 までの体力")
	d.step()
	eq(types(d.events()), ["hurt"], "T + 13 に当たる")
	eq(d.player_hp, 4, "体力が 1 減る")
	eq(d.hits, 1, "受けた数")
	return true


func test_ac7_red_dodge_inside() -> bool:
	for lead: int in [29, 20, 10, 1, 0]:
		var d := duel_of(_red())
		press_at(d, T - lead, "dodge")
		var events := collect_to(d, T + 2)
		ok(first_of(events, "hurt").is_empty(), "T − %d に避けると当たらない" % lead)
		ok(lead == 0 or not first_of(events, "dodge_avoid").is_empty(), "T − %d は dodge_avoid" % lead)
		eq(d.player_hp, 5, "T − %d の体力" % lead)
	return true


func test_ac7_red_dodge_outside() -> bool:
	var d := duel_of(_red())
	press_at(d, T - 30, "dodge")
	eq(first_of(collect_to(d, T + 1), "hurt").get("tick"), T, "T − 30 に避けても T に当たる")
	var d2 := duel_of(_red())
	run_to(d2, T)
	d2.step()
	eq(types(d2.events()), ["hurt"], "赤は T に当たる")
	press_at(d2, T + 1, "dodge")
	eq(d2.player_hp, 4, "T + 1 に避けても遅い")
	return true


func test_ac8_parry_red() -> bool:
	var d := duel_of(_red())
	eq(press_at(d, T - 3, "parry"), ["parry_red"], "赤の窓の中で弾くと parry_red")
	eq(d.lock, B.WHIFF_LOCK - 1, "硬直 54")
	eq(d.snapshot()["attacks"].size(), 1, "赤は残る(E-4)")
	eq(first_of(collect_to(d, T + 1), "hurt").get("tick"), T, "T に当たる")
	eq(d.player_hp, 4, "体力が 1 減る")
	return true


func test_ac9_dodge_lock() -> bool:
	for what: String in ["parry", "dodge"]:
		var d := duel_of(_white())
		press_at(d, 10, "dodge")
		eq(press_at(d, 10 + 53, what), [], "避けるの 53 tick 後の %s は捨てられる" % what)
		var d2 := duel_of(_white())
		press_at(d2, 10, "dodge")
		eq(press_at(d2, 10 + 54, what).size(), 1, "避けるの 54 tick 後の %s は使われる" % what)
	return true


func test_ac10_dodge_white() -> bool:
	var d := duel_of(_white())
	press_at(d, T - 10, "dodge")
	var events := collect_to(d, T + 20)
	ok(not first_of(events, "dodge_avoid").is_empty(), "白も避けられる")
	eq(d.player_hp, 5, "体力は変わらない")
	eq(d.stagger, 0, "よろけは変わらない")
	eq(d.parries, 0, "弾いた数に入らない")
	return true


func test_ac11_offset() -> bool:
	var d := duel_of(_white())
	d.set_offset(6)
	press_at(d, T + 6, "parry")
	ok(first_of(d.events(), "parry").get("just") == true, "ずれ +6 で T + 6 は ぴったり")
	var d2 := duel_of(_white())
	d2.set_offset(6)
	eq(press_at(d2, T + 19, "parry")[0], "parry_whiff", "ずれ +6 で T + 19 は空振り")
	var d3 := duel_of(_white())
	d3.set_offset(6)
	eq(first_of(collect_to(d3, T + 30), "hurt").get("tick"), T + 6 + 13, "ずれ +6 で当たる tick も 6 遅れる")
	return true


func test_offset_is_clamped() -> bool:
	var d := duel_of(_white())
	d.set_offset(40)
	eq(d.offset, 12, "上は 12")
	d.set_offset(-99)
	eq(d.offset, -12, "下は −12")
	return true


# 白 5 つ(30 tick おき)。4 つを ぴったり で弾くと よろけ 8。5 つ目はまだ飛んでいる。
func _five() -> Array:
	var out: Array = []
	for i in 5:
		out.append(atk("white", "LRT"[i % 3], 36, 42, i * 30))
	return out


func _stagger(d: Duel) -> int:
	for i in 4:
		press_at(d, START + 78 + i * 30, "parry")
	return START + 78 + 3 * 30  # よろけに入った tick


func test_ac12_stagger_clears_attacks() -> bool:
	var d := duel_of(_five())
	for i in 3:
		press_at(d, START + 78 + i * 30, "parry")
	run_to(d, START + 78 + 90)
	eq(d.snapshot()["attacks"].size(), 2, "よろける前は 2 つ飛んでいる")
	press_at(d, START + 78 + 90, "parry")
	eq(d.stagger, 8, "よろけ 8")
	eq(d.state, Duel.State.STAGGER, "STAGGER に入る")
	eq(d.snapshot()["attacks"].size(), 0, "決着していない攻撃が全部消える")
	ok(types(d.events()).has("stagger"), "stagger の出来事")
	return true


func test_ac13_counter() -> bool:
	var d := duel_of(_five())
	var t := _stagger(d)
	eq(press_at(d, t + 5, "parry"), ["counter", "boss_phase"], "よろけの間の弾くは反撃")
	eq(d.boss_hp, 2, "敵の体力が 1 減る")
	eq(d.freeze_ticks, B.COUNTER_FREEZE, "止め 12 tick")
	eq(d.phase, 2, "段階が 1 進む")
	eq(d.stagger, 0, "よろけが 0")
	var tick_before := d.tick
	for i in B.COUNTER_FREEZE:
		d.step()
	eq(d.tick, tick_before, "止めの間は tick が進まない")
	d.step()
	eq(d.tick, tick_before + 1, "止めが明けると進む")
	eq(d.state, Duel.State.RECOVER, "構え直し")
	return true


func test_ac13_new_phase_starts_after_recover() -> bool:
	var d := duel_of(_five())
	var t := _stagger(d)
	press_at(d, t + 5, "parry")
	var e := first_of(collect_to(d, t + 5 + B.RECOVER_TICKS + 2), "pattern_start")
	eq(e.get("tick"), t + 5 + B.RECOVER_TICKS, "RECOVER 240 の後に新しい段階の型が出る")
	return true


func test_ac14_boss_recovers() -> bool:
	var d := duel_of(_five())
	var t := _stagger(d)
	var events := collect_to(d, t + B.STAGGER_TICKS + 1)
	eq(first_of(events, "boss_recover").get("tick"), t + B.STAGGER_TICKS, "180 tick 後に立ち直る")
	eq(d.stagger, B.STAGGER_AFTER_RECOVER, "よろけが 4")
	eq(d.phase, 1, "同じ段階が続く")
	eq(d.boss_hp, 3, "敵の体力はそのまま")
	eq(d.state, Duel.State.GAP, "GAP から続ける")
	return true


func test_ac14_last_tick_still_counters() -> bool:
	var d := duel_of(_five())
	var t := _stagger(d)
	eq(press_at(d, t + B.STAGGER_TICKS, "parry")[0], "counter", "180 tick 目の弾くは反撃になる")
	return true


# 敵 1 体を、何も考えずに倒す(白を ぴったり で弾き、よろけたら反撃)。
func _beat_boss(d: Duel) -> void:
	var bot := Bot.new()
	bot.auto_next = false
	var boss := d.boss
	var guard := 0
	while not d.over and d.state != Duel.State.WAIT_NEXT and d.boss == boss and guard < 60000:
		bot.act(d)
		d.step()
		guard += 1


func test_ac15_wait_next_and_win() -> bool:
	var d := duel_of(_five())
	_beat_boss(d)
	eq(d.state, Duel.State.WAIT_NEXT, "敵の体力 0 で WAIT_NEXT")
	ok(types(d.events()).has("boss_down"), "boss_down の出来事")
	var tick := d.tick
	for i in 50:
		d.step()
	eq(d.tick, tick, "WAIT_NEXT の間は時間を数えない")
	d.player_hp = 2
	d.next_boss()
	eq(d.boss, 2, "次の敵")
	eq(d.player_hp, 5, "体力が 5 に戻る")
	eq(d.boss_hp, 3, "敵の体力 3")
	eq(d.state, Duel.State.INTRO, "INTRO から")
	_beat_boss(d)
	d.next_boss()
	_beat_boss(d)
	ok(d.over and d.won, "3 体目を倒すと終わり(勝ち)")
	eq(d.result()["boss"], 3, "着いた敵")
	return true


func test_ac16_lose_and_retry() -> bool:
	var d := duel_of(_five(), 240)
	var guard := 0
	while not d.over and guard < 20000:
		d.step()
		guard += 1
	ok(d.over and not d.won, "体力 0 で終わり(負け)")
	ok(types(d.events()).has("player_down"), "player_down の出来事")
	eq(d.player_hp, 0, "体力 0")
	eq(d.hits, 5, "受けた数 5")
	var r := d.result()
	var again := Duel.new(1, Duel.Mode.FIXED, d.boss, d.retry_carry(), bosses_of([pattern("p", _five(), 240)]))
	eq(again.hits, 5, "受けた数を引き継ぐ")
	eq(again.time_ticks(), int(r["ticks"]), "時間を引き継ぐ")
	eq(again.retries, 1, "やり直しの回数 +1")
	eq(again.player_hp, 5, "体力 5")
	eq(again.phase, 1, "段階 1 から")
	again.step()
	eq(again.time_ticks(), int(r["ticks"]) + 1, "引き継いだ時間に足していく")
	return true


func _teach_duel() -> Duel:
	return Duel.new(1, Duel.Mode.FIXED, 1, null, bosses_of([
		pattern("teach", [atk("white", "L", 60, 96)], 240, true), pattern("second", [atk("white", "R", 60, 96)], 240)]))


func test_ac17_teach_fail_is_free_and_repeats() -> bool:
	var d := _teach_duel()
	var events := collect_to(d, START + 240 + B.GAP_TICKS + 1)
	eq(first_of(events, "hurt_free").get("tick"), T + 13, "当たっても hurt_free")
	ok(first_of(events, "hurt").is_empty(), "hurt は出ない")
	eq(d.player_hp, 5, "体力が減らない")
	eq(d.hits, 0, "受けた数に数えない(E-6)")
	var starts := events.filter(func(e: Dictionary) -> bool: return e["type"] == "pattern_start")
	eq(starts.map(func(e: Dictionary) -> String: return e["id"]), ["teach", "teach"], "同じ型がまた出る")
	eq(starts[1]["tick"], START + 240 + B.GAP_TICKS, "間に GAP を挟む")
	return true


func test_ac17_teach_success_moves_on() -> bool:
	var d := _teach_duel()
	eq(press_at(d, T, "parry"), ["parry", "teach_clear"], "成功")
	eq(d.state, Duel.State.GAP, "型の残りを待たずに GAP")
	ok(d.teach_done[0], "教える型を成功した印")
	var e := first_of(collect_to(d, T + B.GAP_TICKS + 1), "pattern_start")
	eq(e.get("id"), "second", "2 個目の型へ進む")
	eq(e.get("tick"), T + B.GAP_TICKS, "成功した tick から GAP 72")
	return true


func test_ac17_teach_dodge_is_not_success() -> bool:
	var d := _teach_duel()
	press_at(d, T - 5, "dodge")
	collect_to(d, T + 20)
	ok(not d.teach_done[0], "白の教える型は、避けても成功にならない")
	return true


func test_teach_red_needs_dodge() -> bool:
	var data := bosses_of([pattern("teach", [atk("red", "T", 60, 96)], 240, true), pattern("second", [atk("white", "R", 60, 96)], 240)])
	var d := Duel.new(1, Duel.Mode.FIXED, 1, null, data)
	press_at(d, T - 3, "parry")
	var events := collect_to(d, T + 1)
	ok(not first_of(events, "hurt_free").is_empty(), "赤を弾こうとすると当たるが、減らない")
	ok(not d.teach_done[0], "まだ成功でない")
	var d2 := Duel.new(1, Duel.Mode.FIXED, 1, null, data)
	press_at(d2, T - 10, "dodge")
	ok(types(collect_to(d2, T + 1)).has("teach_clear"), "避けると成功")
	return true


func test_retry_skips_cleared_teach() -> bool:
	var data := bosses_of([pattern("teach", [atk("white", "L", 60, 96)], 240, true), pattern("second", [atk("white", "R", 60, 96)], 240)])
	var d := Duel.new(1, Duel.Mode.FIXED, 1, {"teach_done": [true, false, false]}, data)
	eq(first_of(collect_to(d, START + 1), "pattern_start").get("id"), "second", "成功済みの教える型は飛ばす(E-13)")
	return true


func test_e1_parry_wins_over_dodge() -> bool:
	var d := duel_of(_white())
	run_to(d, T)
	d.press_dodge()
	d.press_parry()
	d.step()
	eq(types(d.events()), ["parry"], "同じ tick なら弾くだけを使う")
	eq(d.dodge_ticks, 0, "避けるは捨てられる")
	return true


func test_e3_nearest_then_earliest() -> bool:
	var attacks := [{"contact": 100, "kind": "white", "offset": 0}, {"contact": 110, "kind": "white", "offset": 0}]
	eq(Judge.parry_target(attacks, 103), 0, "差が小さい方")
	eq(Judge.parry_target(attacks, 108), 1, "差が小さい方(後ろ)")
	eq(Judge.parry_target(attacks, 105), 0, "同じなら当たる tick が早い方")
	eq(Judge.parry_target(attacks, 130), -1, "窓の外なら無し")
	attacks[0]["offset"] = 12
	eq(Judge.parry_target(attacks, 111), 1, "判定のずれは攻撃ごと(T' 112 と 110 なら 110 が近い)")
	return true


func test_e7_no_hit_during_hurt_ticks() -> bool:
	var d := duel_of([atk("white", "L", 60, 96), atk("white", "R", 60, 96, 30)])
	var events := collect_to(d, T + 30 + 20)
	eq(d.player_hp, 4, "2 つ目は当たらない")
	eq(first_of(events, "attack_fade").get("tick"), T + 30, "当たらない時間の中の攻撃は消える")
	eq(d.stagger, 0, "よろけは増えない")
	return true


func test_e8_input_kept_through_freeze() -> bool:
	var d := duel_of(_five())
	var t := _stagger(d)
	press_at(d, t + 1, "parry")
	d.press_parry()
	for i in B.COUNTER_FREEZE:
		d.step()
		eq(d.events(), [], "止めの間は何も起きない")
	d.step()
	eq(types(d.events()), ["parry_whiff"], "止めが明けた最初の tick に使う")
	return true


func test_push_in_cannot_be_dodged() -> bool:
	var d := duel_of(_white())
	press_at(d, T + 1, "dodge")
	eq(first_of(collect_to(d, T + 14), "hurt").get("tick"), T + 13, "押し込みの間に避けても、この白は当たる")
	return true


func test_push_in_can_still_be_parried() -> bool:
	var d := duel_of(_white())
	run_to(d, T + 12)
	ok(d.snapshot()["attacks"][0]["pushed"], "T を過ぎた白は押し込みの印がつく")
	d.press_parry()
	d.step()
	eq(types(d.events()), ["parry"], "T + 12 はまだ弾ける")
	return true


func test_combo_counts_and_resets() -> bool:
	var d := duel_of(_five())
	press_at(d, START + 78, "parry")
	press_at(d, START + 108, "parry")
	eq(d.combo, 2, "続けて弾くと増える")
	eq(first_of(d.events(), "parry").get("combo"), 2, "出来事にも入る")
	collect_to(d, START + 138 + 14)
	eq(d.combo, 0, "当たると 0")
	return true


func test_hurt_sets_lock_and_grace() -> bool:
	var d := duel_of(_white())
	run_to(d, T + 13)
	d.step()
	eq(d.hurt_ticks, B.HURT_TICKS - 1, "当たらない時間 60")
	eq(d.lock, B.HURT_LOCK - 1, "当たった後の硬直 24")
	return true


func test_practice_ends_after_one_boss() -> bool:
	var d := Duel.new(1, Duel.Mode.PRACTICE, 2, null, bosses_of([pattern("p", _five())]))
	_beat_boss(d)
	ok(d.over and d.won, "練習は、選んだ敵を倒すと終わる")
	eq(d.result()["boss"], 2, "選んだ敵")
	return true


func test_events_do_not_share_state() -> bool:
	var d := duel_of(_white())
	press_at(d, 5, "parry")
	var first := d.events()
	d.step()
	eq(types(first), ["parry_whiff"], "前の tick の出来事は書き換わらない")
	eq(d.events(), [], "何も無い tick は空")
	return true


func test_head_moves_at_constant_speed() -> bool:
	var a := atk("white", "L", 60, 96)
	var prev := Attack.head_pos(a, 0, 60)
	eq(prev, B.ORIGIN["L"], "予兆が明けた tick は起点")
	var step_len := -1.0
	for t in range(61, 157):
		var p := Attack.head_pos(a, 0, t)
		var moved := prev.distance_to(p)
		if step_len < 0.0:
			step_len = moved
		ok(absf(moved - step_len) < 0.01, "tick %d の進みが等速でない" % t)
		prev = p
	eq(Attack.head_pos(a, 0, 156), B.CONTACT["L"], "当たる tick に当たり点")
	eq(Attack.head_pos(a, 0, 160), B.CONTACT["L"], "その後は当たり点に止まる")
	return true


func test_head_holds_at_midpoint() -> bool:
	var a := atk("white", "R", 96, 72, 0, 72, 72)
	var mid: Vector2 = B.ORIGIN["R"].lerp(B.CONTACT["R"], 0.5)
	for t: int in [96 + 72, 96 + 72 + 30, 96 + 72 + 71]:
		ok(Attack.head_pos(a, 0, t).distance_to(mid) < 0.01, "ための間(tick %d)は中間点" % t)
		eq(Attack.progress(a, 0, t)["phase"], "hold", "phase は hold")
	eq(Attack.progress(a, 0, 96 + 72 + 72)["phase"], "move", "ための後はまた動く")
	eq(Attack.head_pos(a, 0, 312), B.CONTACT["R"], "当たる tick に当たり点")
	return true


func test_windup_pulls_toward_boss() -> bool:
	var a := atk("white", "T", 60, 96)
	eq(Attack.head_pos(a, 0, 0), B.ORIGIN["T"], "予兆の始まりは起点")
	var p := Attack.head_pos(a, 0, 59)
	ok(p.distance_to(B.ORIGIN["T"]) > 19.0 and p.distance_to(B.ORIGIN["T"]) <= 20.0, "予兆の終わりに 20 px 引いている")
	ok(p.y < B.ORIGIN["T"].y, "上の腕は、弾く線から離れる向きへ引く")
	for arm: String in ["L", "R"]:
		var q := Attack.head_pos(atk("white", arm, 60, 96), 0, 59)
		ok(q.distance_to(B.BOSS_POS) < B.ORIGIN[arm].distance_to(B.BOSS_POS), "左右の腕は、敵の中心の向きへ引く")
		ok(q.y < B.ORIGIN[arm].y, "引く向きは、線から離れる側")
	return true
