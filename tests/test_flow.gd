# 同梱の型 30 個を使った通しのテスト(AC-2・AC-18〜AC-22)。自動で押す相手(bot)に戦わせる。
# 終わらない対戦は「失敗」にする(step の上限つき)。
extends "res://tests/suite.gd"

const PatternStore := preload("res://core/pattern_store.gd")
const Sequencer := preload("res://core/sequencer.gd")
const Rng := preload("res://core/rng.gd")

const MAX_STEPS := 120000  # 1,000 秒ぶん。ここまでに終わらなければ詰み


func _full(seed_value: int = 1) -> Duel:
	return Duel.new(seed_value, Duel.Mode.FIXED, 1)


func test_ac18_shipped_patterns_pass_all_checks() -> bool:
	var data := PatternStore.load_file(PatternStore.PATH)
	eq(data["errors"], [], "形の検査 (a)")
	ok(data["ok"], "読める")
	eq(PatternStore.check_all(data["bosses"]), [], "検査 (b)〜(f)")
	var n := 0
	for boss: Dictionary in data["bosses"]:
		for phase: Dictionary in boss["phases"]:
			n += phase["patterns"].size()
	eq(n, 30, "型は 30 個")
	return true


func test_ac19_bot_wins_unhurt() -> bool:
	var d := _full()
	var bot := Bot.new()
	ok(bot.run(d, MAX_STEPS), "上限までに終わる")
	ok(d.won, "3 体を倒す")
	eq(d.hits, 0, "受けた数 0")
	eq(int(bot.counts.get("parry_whiff", 0)), 0, "空振りが無い")
	eq(int(bot.counts.get("counter", 0)), 9, "反撃は 9 回")
	var sec := d.time_ticks() / float(B.TICK_HZ)
	print("      bot(全部 ぴったり)の時間: %.1f 秒、弾いた数 %d" % [sec, d.parries])
	return true


func test_ac20_bot_shifted_still_unhurt() -> bool:
	for shift: int in [-2, -1, 1, 2]:
		var d := _full()
		var bot := Bot.new()
		bot.shift = shift
		ok(bot.run(d, MAX_STEPS) and d.won, "ずれ %+d で 3 体を倒す" % shift)
		eq(d.hits, 0, "ずれ %+d の受けた数" % shift)
		eq(int(bot.counts.get("parry_whiff", 0)), 0, "ずれ %+d で空振りが無い(全部 弾き 以上)" % shift)
	return true


func test_plain_parry_bot_also_wins() -> bool:
	# ぴったり を 1 回も取れない人(いつも 8 tick 遅い)でも、詰まずに倒せる
	var d := _full()
	var bot := Bot.new()
	bot.shift = 8
	ok(bot.run(d, MAX_STEPS) and d.won, "8 tick 遅い相手も 3 体を倒す")
	eq(d.justs, 0, "ぴったり は 0")
	eq(d.hits, 0, "受けた数 0")
	print("      bot(全部 弾き)の時間: %.1f 秒、弾いた数 %d" % [d.time_ticks() / float(B.TICK_HZ), d.parries])
	return true


func test_every_phase_can_reach_stagger() -> bool:
	# どの段階にも、教える型のほかに白がある(無いと よろけ が溜まらず詰む)
	var data: Array = PatternStore.shared()["bosses"]
	for boss: Dictionary in data:
		for pi in boss["phases"].size():
			var whites := 0
			for p: Dictionary in boss["phases"][pi]["patterns"]:
				if not p["teach"]:
					whites += p["attacks"].filter(func(a: Dictionary) -> bool: return a["kind"] == "white").size()
			ok(whites > 0, "%s 段階 %d に、教える型のほかの白が無い" % [boss["id"], pi + 1])
	return true


func test_ac21_idle_stays_in_teach() -> bool:
	var d := _full()
	var bot := Bot.new()
	bot.parry_whites = false
	bot.dodge_reds = false
	bot.run(d, 600)
	eq(d.tick, 600, "600 tick 進む")
	eq(d.boss, 1, "敵 1 のまま")
	ok(d.snapshot()["teaching"], "教える型にいる")
	eq(d.player_hp, 5, "体力 5 のまま")
	eq(d.hits, 0, "受けた数 0")
	ok(int(bot.counts.get("hurt_free", 0)) >= 1, "当たっても減らない")
	return true


func test_ac21_teach_only_loses_to_boss1() -> bool:
	var d := _full()
	var bot := Bot.new()
	bot.only_teach = true
	ok(bot.run(d, MAX_STEPS), "上限までに終わる")
	ok(not d.won, "負ける")
	eq(d.boss, 1, "敵 1 で")
	eq(d.hits, 5, "受けた数 5")
	return true


func test_ac22_order_does_not_depend_on_speed() -> bool:
	var fast := Bot.new()
	var slow := Bot.new()
	slow.shift = 8  # 弾き(+1)しか取れないので、同じ段階に長くいる
	var d1 := _full(777)
	var d2 := _full(777)
	ok(fast.run(d1, MAX_STEPS) and slow.run(d2, MAX_STEPS), "どちらも終わる")
	var by_phase := func(list: Array) -> Dictionary:
		var out := {}
		for p: Array in list:
			var key := "%d-%d" % [p[0], p[1]]
			if not out.has(key):
				out[key] = []
			out[key].append([p[2], p[3]])
		return out
	var a: Dictionary = by_phase.call(fast.patterns)
	var b: Dictionary = by_phase.call(slow.patterns)
	eq(a.size(), 9, "9 つの段階を通る")
	var longer := 0
	for key: String in a:
		var n: int = mini(a[key].size(), b[key].size())
		eq(a[key].slice(0, n), b[key].slice(0, n), "段階 %s の型の順と腕の入れ替え" % key)
		longer += int(b[key].size() > a[key].size())
	ok(longer > 0, "遅い方が、同じ段階で多くの型を見ている(比べる意味がある)")
	return true


func test_ac22_first_lap_is_definition_order() -> bool:
	var data: Array = PatternStore.shared()["bosses"]
	for bi in 3:
		for pi in 3:
			var patterns: Array = data[bi]["phases"][pi]["patterns"]
			var seq := Sequencer.new(12345, bi + 1, pi + 1, patterns, true)
			for p: Dictionary in patterns:
				if p["teach"]:
					continue
				var got := seq.next()
				eq(got["pattern"]["id"], p["id"], "1 周目は定義の順")
				ok(not got["swapped"], "1 周目は腕を入れ替えない")
	return true


func test_sequencer_repeats_teach_until_cleared() -> bool:
	var patterns: Array = PatternStore.shared()["bosses"][0]["phases"][0]["patterns"]
	var seq := Sequencer.new(1, 1, 1, patterns, false)
	eq(seq.next()["pattern"]["id"], "stone_1_teach", "最初は教える型")
	eq(seq.next()["pattern"]["id"], "stone_1_teach", "成功するまで同じ")
	seq.teach_cleared()
	eq(seq.next()["pattern"]["id"], "stone_1_a", "成功したら 2 個目")
	eq(seq.next()["pattern"]["id"], "stone_1_b", "3 個目")
	for i in 20:
		ok(not seq.next()["pattern"]["teach"], "2 周目からは教える型が出ない")
	return true


func test_sequencer_second_lap_is_seeded() -> bool:
	var patterns: Array = PatternStore.shared()["bosses"][0]["phases"][2]["patterns"]
	var run := func(seed_value: int) -> Array:
		var seq := Sequencer.new(seed_value, 1, 3, patterns, true)
		var out: Array = []
		for i in 40:
			var got := seq.next()
			out.append([got["pattern"]["id"], got["swapped"]])
		return out
	eq(run.call(5), run.call(5), "同じ種なら同じ順")
	ok(run.call(5) != run.call(6), "種が違えば順が変わる")
	var list: Array = run.call(5)
	var repeats := 0
	var swaps := 0
	for i in range(1, list.size()):
		repeats += int(list[i][0] == list[i - 1][0])
		swaps += int(list[i][1])
	eq(repeats, 0, "直前と同じ型が続かない")
	ok(swaps > 5 and swaps < 35, "腕の入れ替えは、ある時と無い時がある")
	return true


func test_phase_seeds_differ() -> bool:
	var seen := {}
	for boss in range(1, 4):
		for phase in range(1, 4):
			var s := Sequencer.phase_seed(1, boss, phase)
			ok(s > 0 and s <= 0xFFFFFFFF, "32 ビットの正の数")
			seen[s] = true
	eq(seen.size(), 9, "段階ごとに別の種")
	eq(Sequencer.phase_seed(1, 1, 1), 1 ^ ((0x9E3779B1 + 0x85EBCA6B) & 0xFFFFFFFF), "§9.8 の式")
	return true


func test_swap_arms_keeps_source() -> bool:
	var p: Dictionary = PatternStore.shared()["bosses"][0]["phases"][1]["patterns"][1]
	var before := str(p)
	var swapped := Sequencer.swap_arms(p)
	eq(str(p), before, "元のデータは変えない")
	eq(swapped["attacks"].map(func(a: Dictionary) -> String: return a["arm"]), ["T", "R", "L"], "L と R だけ入れ替わる")
	return true


func test_ac2_same_input_same_result_100_times() -> bool:
	# 入力の記録を 1 本作る。わざと乱れた相手(白を 0〜14 tick ずらし、時々押さない)
	var d := _full(4242)
	var bot := Bot.new()
	var noise := Rng.new(99)
	while not d.over and bot.steps < MAX_STEPS:
		if bot.steps % 97 == 0:
			bot.shift = noise.next_int(15) - 7
			bot.parry_whites = noise.next_int(6) != 0
		bot.act(d)
		d.step()
		bot.steps += 1
	ok(d.over, "記録を作る対戦が終わる")
	var want := d.result()
	print("      記録: %s、入力 %d 個、%d step" % [want, bot.record.size(), bot.steps])
	for i in 100:
		var again := _full(4242)
		Bot.replay(again, bot.record, bot.steps)
		if again.result() != want:
			errors.append("%d 回目の結果が違う: %s" % [i + 1, again.result()])
			break
	return true


func test_rng_matches_xorshift32() -> bool:
	var r := Rng.new(1)
	eq(r.next(), 270369, "種 1 の 1 個目")
	eq(r.next(), 67634689, "2 個目")
	eq(Rng.new(0).state, 1, "0 は 1 にする")
	var r2 := Rng.new(123)
	for i in 1000:
		var v := r2.next_int(7)
		ok(v >= 0 and v < 7, "next_int の範囲")
	return true


func test_phase3_has_a_run_that_must_be_parried() -> bool:
	# D-6「速い連続の攻撃は避けきれず、弾くしかない」: 各敵の段階 3 に、当たる tick が 30・30 と続く 3 連がある。
	# 避けるの硬直は 54 tick なので、1 つ目と 2 つ目を避けても、3 つ目は避けられない
	for boss: Dictionary in PatternStore.shared()["bosses"]:
		var found := false
		for p: Dictionary in boss["phases"][2]["patterns"]:
			var cs: Array = PatternStore.contacts(p)
			for i in range(2, cs.size()):
				found = found or (cs[i]["tick"] - cs[i - 2]["tick"] < B.DODGE_LOCK + 1 + B.MIN_CONTACT_GAP)
		ok(found, "%s の段階 3 に、避けきれない 3 連が無い" % boss["id"])
	return true
