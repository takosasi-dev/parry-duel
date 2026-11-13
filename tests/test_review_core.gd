# レビュー用: 判定と対戦の決まりの、既存のテストが触っていない境い目(同じ tick の重なり・止めと入力・判定のずれが負・
# やり直しと次の敵をまたぐ値・型の順)。print の RV 行が証拠。
extends "res://tests/suite.gd"

const Judge := preload("res://core/judge.gd")
const Sequencer := preload("res://core/sequencer.gd")
const PatternStore := preload("res://core/pattern_store.gd")
const Calib := preload("res://core/calib.gd")

const T0 := 120 + 36 + 42  # 型が tick 120 に始まり、windup 36・travel 42 の攻撃が線に届く tick


func _white(at: int = 0) -> Dictionary:
	return atk("white", "L", 36, 42, at)


func _red(at: int = 0) -> Dictionary:
	return atk("red", "T", 36, 42, at)


# ---- 判定のずれが −12・+12 の時の境い目(AC-4〜AC-9 を、ずれを足して) ----

func test_review_offset_window_edges() -> bool:
	for offset: int in [-12, -1, 12]:
		var j := T0 + offset
		for c: Array in [[-13, "parry_whiff"], [-12, "plain"], [-6, "plain"], [-5, "just"], [0, "just"], [5, "just"], [6, "plain"], [12, "plain"]]:
			var d := duel_of([_white()])
			d.set_offset(offset)
			run_to(d, j + int(c[0]))
			d.press_parry()
			d.step()
			var e := first_of(d.events(), "parry")
			var got := "parry_whiff"
			if not e.is_empty():
				got = "just" if e["just"] else "plain"
			eq(got, c[1], "offset %d で T'%+d に弾く" % [offset, c[0]])
		# 何も押さないと T' + 13 に当たる(AC-6)
		var d2 := duel_of([_white()])
		d2.set_offset(offset)
		var hit := first_of(collect_to(d2, j + 40), "hurt")
		eq(hit.get("tick", -1), j + 13, "offset %d で白が当たる tick" % offset)
		# 赤: T'−29〜T' の避けるは効き、T'−30 と T'+1 は当たる(AC-7)
		for c2: Array in [[-30, true], [-29, false], [0, false], [1, true]]:
			var d3 := duel_of([_red()])
			d3.set_offset(offset)
			var ev := collect_to(d3, j + int(c2[0]))
			d3.press_dodge()
			ev.append_array(collect_to(d3, j + 40))
			eq(not first_of(ev, "hurt").is_empty(), c2[1], "offset %d で赤を T'%+d に避ける → 当たるか" % [offset, c2[0]])
			if c2[1]:
				eq(first_of(ev, "hurt")["tick"], j, "offset %d で赤が当たる tick" % offset)
	return true


# ---- E-7 の帰結: 当たった後の 60 tick に線へ届く白は消える。見えている白を遅めに弾こうとすると空振りになる ----

func test_review_white_fades_inside_hurt_time_and_late_parry_whiffs() -> bool:
	# 白 A(T0)を受ける → T0+13 に当たる。白 B は T0+50 に線へ届く(当たらない時間の中)
	var d := duel_of([_white(0), atk("white", "R", 36, 42, 50)])
	var ev := collect_to(d, T0 + 50)
	eq(first_of(ev, "hurt").get("tick", -1), T0 + 13, "A が当たる")
	eq(d.lock, 0, "B の窓の前に硬直は明けている(T0+37)")
	# B の窓は T0+38〜T0+62 のはず。T0+53(B の T から +3、ぴったりの幅)に弾く
	d.step()  # tick T0+50: B が線に届く
	print("RV E-7: B が線に届いた tick の出来事 = %s  残っている攻撃 = %d" % [types(d.events()), d.snapshot()["attacks"].size()])
	var got := press_at(d, T0 + 53, "parry")
	print("RV E-7: 当たった後の 60 tick の中で、B を T+3 に弾く → %s  lock=%d" % [got, d.lock])
	eq(got, ["parry_whiff"], "(今の動き)当たらない時間の中の白は T' で消えるので、T+3 の弾くは空振りになる")
	eq(d.lock, B.WHIFF_LOCK - 1, "空振りの硬直が付く")
	return true


# ---- 止め(freeze)と入力(E-8) ----

func _to_stagger() -> Duel:
	# 白 4 つを ぴったり で弾いて、よろけ 8 にする
	var d := duel_of([_white(0), _white(60), _white(120), _white(180)], 400)
	for k in 4:
		press_at(d, T0 + k * 60, "parry")
	return d


func test_review_freeze_keeps_time_and_locks() -> bool:
	var d := _to_stagger()
	eq(d.state, Duel.State.STAGGER, "よろけ")
	var t := d.tick
	d.press_parry()
	d.step()  # 反撃
	eq(d.freeze_ticks, B.COUNTER_FREEZE, "止め 12")
	var after := d.tick
	for i in B.COUNTER_FREEZE:
		d.step()
		eq(d.events(), [], "止めの間は出来事が無い")
	eq(d.tick, after, "止めの間は tick が進まない(時間に数えない)")
	eq(d.state_until - d.state_from, B.RECOVER_TICKS, "構え直しは 240 tick")
	print("RV freeze: 反撃の tick=%d、止めの後の tick=%d、次の型は tick %d" % [t, d.tick, d.state_until])
	return true


func test_review_mash_through_counter_whiffs_after_freeze() -> bool:
	# よろけた敵に連打する人: 反撃の後、止めの間の押しが 1 つ覚えられ、明けた tick に空振りになる(E-8 の帰結)
	var d := _to_stagger()
	d.press_parry()
	d.step()
	d.press_parry()  # 止めの間の押し
	for i in B.COUNTER_FREEZE:
		d.step()
	d.step()
	print("RV E-8: 止めが明けた tick の出来事 = %s  lock=%d  state=%d" % [types(d.events()), d.lock, d.state])
	eq(types(d.events()), ["parry_whiff"], "止めの間の押しは、明けた tick に空振りになる")
	ok(d.lock < B.RECOVER_TICKS, "硬直は構え直し(240)の間に明ける")
	return true


func test_review_dodge_and_parry_both_kept_through_freeze() -> bool:
	var d := _to_stagger()
	d.press_parry()
	d.step()
	d.press_dodge()
	d.press_parry()
	for i in B.COUNTER_FREEZE:
		d.step()
	d.step()
	eq(types(d.events()), ["parry_whiff"], "両方を覚えていても、明けた tick は弾くだけ(E-1)")
	return true


# ---- よろけに入る tick と、型の終わり・次の型の始まりが重なる ----

func test_review_stagger_on_pattern_end_tick() -> bool:
	# length をちょうど最後の弾きの tick にする: 型の終わり(GAP へ)と よろけ が同じ tick
	var last := T0 + 180
	var d := Duel.new(1, Duel.Mode.FIXED, 1, null, bosses_of([pattern("p", [_white(0), _white(60), _white(120), _white(180)], last - 120)]))
	for k in 3:
		press_at(d, T0 + k * 60, "parry")
	var got := press_at(d, last, "parry")
	print("RV よろけと型の終わりが同じ tick: %s  state=%d" % [got, d.state])
	eq(d.state, Duel.State.STAGGER, "よろけが勝つ")
	eq(d.snapshot()["attacks"].size(), 0, "攻撃は消える")
	# その後、何も押さないと 180 tick で立ち直り、72 tick 後に次の型
	var ev := collect_to(d, last + 400)
	eq(first_of(ev, "boss_recover").get("tick", -1), last + B.STAGGER_TICKS, "立ち直りの tick")
	eq(first_of(ev, "pattern_start").get("tick", -1), last + B.STAGGER_TICKS + B.GAP_TICKS, "次の型の tick")
	eq(d.stagger, B.STAGGER_AFTER_RECOVER, "よろけ 4")
	return true


func test_review_stagger_on_next_pattern_start_tick() -> bool:
	# 前の型の最後の白が GAP の終わり(次の型が始まる tick)に窓に入っている場合。length を短くして作る
	# 型 = 白 1 つ(at 0、線に T0)。length 6 → GAP は tick 126〜198 → 次の型は tick 198 = T0 に始まる
	var d := Duel.new(1, Duel.Mode.FIXED, 1, null, bosses_of([pattern("p", [_white(0)], 6)]))
	d.stagger = 6
	var got := press_at(d, T0, "parry")
	print("RV よろけと次の型の始まりが同じ tick: %s  state=%d attacks=%d" % [got, d.state, d.snapshot()["attacks"].size()])
	ok(got.has("stagger"), "よろけになる")
	ok(not got.has("pattern_start"), "同じ tick に次の型は始まらない")
	eq(d.snapshot()["attacks"].size(), 0, "攻撃は残らない")
	return true


func test_review_teach_clear_on_pattern_end_tick() -> bool:
	# 教える型の length を、弾く tick と同じにする: 教える型の成功と型の終わりが同じ tick
	var d := Duel.new(1, Duel.Mode.FIXED, 1, null, bosses_of([pattern("t", [_white(0)], T0 - 120, true), pattern("n", [_white(0)], 300)]))
	var got := press_at(d, T0, "parry")
	ok(got.has("teach_clear"), "成功する")
	var ev := collect_to(d, T0 + 200)
	var ps := first_of(ev, "pattern_start")
	eq(ps.get("id", ""), "n", "次は 2 個目の型")
	eq(ps.get("tick", -1), T0 + B.GAP_TICKS, "GAP は成功した tick から 72")
	return true


# ---- 同じ tick に、当たる物が 2 つ ----

func test_review_two_hits_same_tick_cost_one() -> bool:
	# 白(T0、押し込みの終わりは T0+13)と、赤(T0+13 に届く)。同じ tick に 2 つ当たる → 体力は 1 だけ減る
	var d := duel_of([_white(0), atk("red", "T", 36, 55, 0)])
	var ev := collect_to(d, T0 + 30)
	var hurts := ev.filter(func(e: Dictionary) -> bool: return e["type"] == "hurt")
	print("RV 同じ tick に 2 つ: hurt=%d attack_fade=%d hp=%d" % [hurts.size(), ev.filter(func(e: Dictionary) -> bool: return e["type"] == "attack_fade").size(), d.player_hp])
	eq(hurts.size(), 1, "当たるのは 1 つ")
	eq(d.player_hp, B.PLAYER_HP - 1, "体力 −1")
	return true


func test_review_stagger_parry_cancels_red_on_same_tick() -> bool:
	# よろけ 7 で、白(T0)を弾く tick に、赤もちょうど届く(T0)。弾くが先(手順 3)なので、赤は消えて当たらない。
	# ただし赤の方が「近い」と弾けない(parry_red)ので、白を 1 tick だけ近くする: 白 T0、赤 T0+1 で、T0 に押す
	var d := duel_of([_white(0), atk("red", "T", 36, 43, 0)])
	d.stagger = B.STAGGER_THRESHOLD - 1
	run_to(d, T0 + 1)  # tick T0 を何も押さずに過ぎる → 白は押し込みへ
	var got := press_at(d, T0 + 1, "parry")  # 白まで 1、赤まで 0 → 近いのは赤
	print("RV 白(差 1)と赤(差 0)が窓にある時の弾く: %s  hp=%d" % [got, d.player_hp])
	eq(got, ["parry_red", "hurt"], "(今の動き = §9.5 のとおり)近い方が赤なら弾けず、その tick に赤が当たる")
	var d2 := duel_of([_white(0), atk("red", "T", 36, 43, 0)])
	d2.stagger = B.STAGGER_THRESHOLD - 1
	var got2 := press_at(d2, T0, "parry")  # 白まで 0、赤まで 1 → 白
	collect_to(d2, T0 + 5)
	eq(got2, ["parry", "stagger"], "白の方が近ければ弾けて、よろけになる")
	eq(d2.player_hp, B.PLAYER_HP, "次の tick に届くはずだった赤は消えて、当たらない")
	return true


func test_review_dodge_on_contact_tick_of_white() -> bool:
	# 白が線に届く tick ちょうどに避ける → 避けられる。1 tick 後(押し込みの中)は避けられない
	var d := duel_of([_white()])
	var got := press_at(d, T0, "dodge")
	ok(got.has("dodge_avoid"), "T' ちょうどの避けるは効く")
	var d2 := duel_of([_white()])
	press_at(d2, T0 + 1, "dodge")
	var ev := collect_to(d2, T0 + 20)
	eq(first_of(ev, "hurt").get("tick", -1), T0 + 13, "T'+1 の避けるは効かず、T'+13 に当たる")
	return true


func test_review_hurt_lock_does_not_shorten_longer_lock() -> bool:
	# 避ける(硬直 54)を T0+1 に押して、白に T0+13 で当たる → 硬直は max(残り, 24)
	var d := duel_of([_white()])
	press_at(d, T0 + 1, "dodge")
	run_to(d, T0 + 14)
	eq(d.lock, B.DODGE_LOCK - 13, "避けるの硬直の残り(41)がそのまま")
	return true


# ---- 判定のずれを、攻撃が飛んでいる間に変える(一時停止 → 設定)----

func test_review_offset_changed_mid_flight() -> bool:
	# ずれ +12 で、白が T0+5 まで来た所で止めて、ずれを −12 にする(設定で 24 tick ぶん動かす)
	var d := duel_of([_white()])
	d.set_offset(12)
	run_to(d, T0 + 5)
	d.set_offset(-12)  # 飛んでいる白は、始まった時のずれ(+12)のまま。T' = T0+12
	d.press_parry()
	d.step()
	var first := types(d.events())
	var ev := collect_to(d, T0 + 30)
	print("RV ずれを途中で +12 → −12: 直後の弾く = %s、その後 = %s  hp=%d" % [first, types(ev), d.player_hp])
	ok(first.has("parry"), "見えている白は、ずれを途中で動かしても弾ける(始まった時のずれで判定する)")
	eq(d.player_hp, B.PLAYER_HP, "当たらない")
	eq(d.offset, -12, "次に始まる攻撃からは新しいずれ")
	return true


# ---- やり直し・次の敵をまたぐ値 ----

func test_review_next_boss_keeps_and_resets() -> bool:
	var d := Duel.new(1, Duel.Mode.FIXED, 1, null, bosses_of([pattern("p", [_white(0), _white(60), _white(120), _white(180)], 400)]))
	d.set_offset(5)
	var bot := Bot.new()
	bot.auto_next = false
	bot.run(d, 100000)
	# bot.run は over まで回すので、WAIT_NEXT で止まるよう手で回す
	var guard := 0
	while d.state != Duel.State.WAIT_NEXT and guard < 100000:
		bot.act(d)
		d.step()
		guard += 1
	eq(d.state, Duel.State.WAIT_NEXT, "敵 1 を倒した")
	var tick := d.tick
	d.lock = 7
	d.hurt_ticks = 9
	d.dodge_ticks = 3
	d.player_hp = 2
	d.press_parry()
	for i in 50:
		d.step()
	eq(d.tick, tick, "WAIT_NEXT の間は時間を数えない")
	var parries := d.parries
	var justs := d.justs
	d.next_boss()
	eq([d.boss, d.phase, d.boss_hp, d.stagger, d.player_hp, d.lock, d.hurt_ticks, d.dodge_ticks, d.freeze_ticks], [2, 1, 3, 0, 5, 0, 0, 0, 0], "次の敵で戻る値")
	eq([d.offset, d.parries, d.justs, d.tick], [5, parries, justs, tick], "次の敵へ引き継ぐ値(判定のずれ・弾いた数・ぴったり・時間)")
	d.step()
	eq(types(d.events()), [], "WAIT_NEXT の間の押しは、次の敵に持ち越さない")
	eq(d.state_until, tick + B.INTRO_TICKS, "INTRO は 120 tick")
	return true


func test_review_retry_carry_values() -> bool:
	var d := Duel.new(77, Duel.Mode.DAILY, 2)
	d.set_offset(-7)
	d.hits = 9
	d.justs = 4
	d.parries = 11
	d.retries = 2
	d.combo = 5
	d.stagger = 6
	d.teach_done = [true, true, false]
	run_to(d, 500)
	var c := d.retry_carry()
	var n := Duel.new(d.seed_value, d.mode, d.boss, c)
	eq([n.hits, n.justs, n.parries, n.retries, n.time_ticks(), n.boss, n.phase, n.player_hp, n.stagger, n.boss_hp], [9, 4, 11, 3, 500, 2, 1, 5, 0, 3], "やり直しで引き継ぐ値・戻る値(E-13)")
	eq(n.teach_done, [true, true, false], "教える型の成功も引き継ぐ")
	eq(n.offset, 0, "判定のずれは Duel を作り直すと 0(ui が入れ直す必要がある)")
	eq(n.result()["ticks"], 500, "時間は足し算で引き継ぐ")
	# こわれた carry でも落ちない
	var bad := Duel.new(1, Duel.Mode.FIXED, 9, {"hits": "x", "teach_done": [1, 2]})
	eq(bad.boss, 3, "敵の番号は 1〜3 に切り詰める")
	return true


# ---- 型の出る順(INV-3)。教える型のくり返し・やり直し・立ち直りで、順と腕の入れ替えが変わらないか ----

func _order(d: Duel, press: Callable, steps: int) -> Dictionary:
	var out := {}  # "敵-段階" → [[id, swapped], ...]
	for s in steps:
		if d.over:
			break
		if d.state == Duel.State.WAIT_NEXT:
			d.next_boss()
		press.call(d)
		d.step()
		for e: Dictionary in d.events():
			if e["type"] == "pattern_start" and not e["teach"]:
				var key := "%d-%d" % [d.boss, d.phase]
				if not out.has(key):
					out[key] = []
				out[key].append([e["id"], e["swapped"]])
	return out


func _same_prefix(a: Dictionary, b: Dictionary, what: String) -> int:
	var compared := 0
	for key: String in a:
		if not b.has(key):
			continue
		var n := mini(a[key].size(), b[key].size())
		for i in n:
			if a[key][i] != b[key][i]:
				errors.append("%s: %s の %d 個目が違う(%s と %s)" % [what, key, i + 1, a[key][i], b[key][i]])
				return compared
			compared += 1
	return compared


func test_review_order_same_across_play_styles() -> bool:
	for seed_value: int in [1, 2654435761, 12345]:
		# a: ふつうの相手 / b: 教える型を 3 回わざと逃してから弾く・よろけても 1 回は見送る相手 / c: わざと当たりながら進む相手
		var a := _order(Duel.new(seed_value, Duel.Mode.DAILY, 1), func(d: Duel) -> void: Bot.new().act(d), 40000)
		var skips := [0]
		var b_press := func(d: Duel) -> void:
			if d.state == Duel.State.STAGGER:
				if d.stagger == B.STAGGER_THRESHOLD and d.tick == d.state_from + 100 and skips[0] % 4 == 3:
					d.press_parry()
				if d.tick == d.state_from + 179:
					skips[0] += 1
				return
			for at: Dictionary in d.snapshot()["attacks"]:
				if at["free"] and d.tick < 1500:
					continue  # 教える型をしばらく逃す
				if at["kind"] == "white" and d.tick == at["contact"] + 9:
					d.press_parry()
				elif at["kind"] == "red" and d.tick == at["contact"] - 3:
					d.press_dodge()
		var b := _order(Duel.new(seed_value, Duel.Mode.DAILY, 1), b_press, 120000)
		var c_press := func(d: Duel) -> void:
			if d.state == Duel.State.STAGGER:
				d.press_parry()
				return
			for at: Dictionary in d.snapshot()["attacks"]:
				if int(at["id"]) % 9 == 0 and not at["free"]:
					continue  # 9 つに 1 つは受ける
				if at["kind"] == "white" and d.tick == at["contact"] - 8:
					d.press_parry()
				elif at["kind"] == "red" and d.tick == at["contact"] - 20:
					d.press_dodge()
		var c := _order(Duel.new(seed_value, Duel.Mode.DAILY, 1), c_press, 60000)
		# 正: 種・敵・段階だけから作った Sequencer の順(教える型は飛ばす)。どの相手の順も、これの頭と同じはず
		var want := {}
		var bosses: Array = PatternStore.shared()["bosses"]
		for bi in 3:
			for pi in 3:
				var seq := Sequencer.new(seed_value, bi + 1, pi + 1, bosses[bi]["phases"][pi]["patterns"], true)
				var list: Array = []
				for i in 200:
					var got := seq.next()
					list.append([got["pattern"]["id"], got["swapped"]])
				want["%d-%d" % [bi + 1, pi + 1]] = list
		var n0 := _same_prefix(a, want, "種 %d: ふつうの相手" % seed_value)
		var n1 := _same_prefix(b, want, "種 %d: 見送る相手" % seed_value)
		var n2 := _same_prefix(c, want, "種 %d: 受ける相手" % seed_value)
		print("RV 型の順: 種 %d  正と比べた型の数 = %d・%d・%d  段階の数 = %d・%d・%d" % [seed_value, n0, n1, n2, a.size(), b.size(), c.size()])
		ok(n0 >= 18 and n1 >= 36 and n2 >= 30, "十分な数を比べた(%d・%d・%d)" % [n0, n1, n2])
	return true


func test_review_retry_order_matches_first_try() -> bool:
	# やり直し(教える型を飛ばす)でも、同じ敵・同じ段階の 2 個目からの順と腕の入れ替えは同じ
	var first := _order(Duel.new(99, Duel.Mode.DAILY, 2), func(d: Duel) -> void: Bot.new().act(d), 30000)
	var retry := _order(Duel.new(99, Duel.Mode.DAILY, 2, {"hits": 5, "ticks": 100, "teach_done": [true, true, false]}), func(d: Duel) -> void: Bot.new().act(d), 30000)
	var n := _same_prefix(first, retry, "やり直し")
	print("RV やり直しの順: 比べた型の数 = %d  %s" % [n, str(first.get("2-1", [])).left(120)])
	ok(n >= 10, "十分な数を比べた")
	return true


func test_review_second_lap_never_repeats_and_uses_all() -> bool:
	# 2 周目から: 同じ id が続く回数と、出ない型が無いかを 3,000 個ぶん数える(4 回まで選び直す決まり)
	var bosses: Array = PatternStore.shared()["bosses"]
	var repeats := 0
	var total := 0
	for bi in 3:
		for pi in 3:
			var seq := Sequencer.new(1, bi + 1, pi + 1, bosses[bi]["phases"][pi]["patterns"], true)
			var seen := {}
			var last := ""
			var swaps := 0
			for i in 300:
				var got := seq.next()
				var id: String = got["pattern"]["id"]
				seen[id] = int(seen.get(id, 0)) + 1
				swaps += 1 if got["swapped"] else 0
				if i >= bosses[bi]["phases"][pi]["patterns"].size() and id == last:
					repeats += 1
				last = id
				total += 1
			var pool: int = bosses[bi]["phases"][pi]["patterns"].filter(func(p: Dictionary) -> bool: return not p["teach"]).size()
			eq(seen.size(), pool, "敵 %d 段階 %d: 教える型を除いた全部の型が出る" % [bi + 1, pi + 1])
			print("RV 2 周目: 敵 %d 段階 %d  出た数 = %s  入れ替え = %d/300" % [bi + 1, pi + 1, seen, swaps])
	print("RV 2 周目: 同じ型が続いた回数 = %d / %d" % [repeats, total])
	return true


# ---- タイミング合わせ ----

func test_review_calib_double_press_and_ties() -> bool:
	var c := Calib.new()
	var t1: int = Calib.LEAD + B.CALIB_WINDUP + B.CALIB_TRAVEL
	# 3 回目の攻撃に、−30(早すぎる誤タップ)と +2 の 2 回押す → 数えるのは最初の −30
	var t3 := t1 + 2 * B.CALIB_INTERVAL
	var log: Array = []
	while not c.done:
		if c.tick == t3 - 30 or c.tick == t3 + 2:
			c.press()
		c.step()
		for e: Dictionary in c.events():
			if e["type"] != "attack_start":
				log.append([e["type"], e.get("diff", null)])
	print("RV calib: 同じ攻撃に 2 回押す → %s  diffs=%s" % [log, c.diffs])
	eq(c.diffs[2], -30, "(今の動き)同じ攻撃への 2 回目の押しは捨てられ、最初の −30 が残る")
	# 36 と −36 は有効、37 は捨てる
	for d: int in [-37, -36, 36, 37]:
		var c2 := Calib.new()
		while not c2.done:
			if c2.tick == t3 + d:
				c2.press()
			c2.step()
		eq(c2.diffs[2] != null, absi(d) <= 36, "差 %d が有効か" % d)
	return true


func test_review_calib_ignores_current_offset() -> bool:
	# NFR-17「出た値を使った後にもう一度測ると、ずれの中央値が ±2 tick 以内」は、§9.14「offset を足さない」と両立しない:
	# いつも +6 tick 遅れて押す人は、1 回目も 2 回目も +6 が出る(calib は今の判定のずれを知らない)
	var results: Array = []
	for round in 2:
		var c := Calib.new()
		var t1: int = Calib.LEAD + B.CALIB_WINDUP + B.CALIB_TRAVEL
		while not c.done:
			for k in B.CALIB_COUNT:
				if c.tick == t1 + k * B.CALIB_INTERVAL + 6:
					c.press()
			c.step()
		results.append(c.result())
	print("RV calib: +6 遅れて押す人の 1 回目・2 回目の結果 = %s(NFR-17 は 2 回目が ±2 以内を求める)" % [results])
	eq(results, [6, 6], "(今の動き = §9.14 のとおり)2 回目も同じ値が出る")
	return true
