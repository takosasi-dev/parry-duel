# レビュー用: 同梱の 30 個の型を、連打する相手・避けてばかりの相手・下手な相手に戦わせる。
# 終わらない対戦・詰み・「連打で抜ける」が出ないかを数字で出す(print の RV 行が証拠)。
extends "res://tests/suite.gd"

const Rng := preload("res://core/rng.gd")
const PatternStore := preload("res://core/pattern_store.gd")
const Attack := preload("res://core/attack.gd")

const MAX_STEPS := 120 * 60 * 20  # 20 分ぶん


# press.call(d, step) が "p"・"d"・"" を返す相手で、負けたらやり直しながら回す。
# { won, steps, hits, retries, boss, phase, parries, justs }
func _run(press: Callable, seed_value: int = 1, max_retries: int = 30, offset: int = 0) -> Dictionary:
	var d := Duel.new(seed_value, Duel.Mode.FIXED, 1)
	d.set_offset(offset)
	var steps := 0
	var retries := 0
	while steps < MAX_STEPS:
		if d.over:
			if d.won or retries >= max_retries:
				break
			retries += 1
			d = Duel.new(seed_value, Duel.Mode.FIXED, d.boss, d.retry_carry())
			d.set_offset(offset)
		if d.state == Duel.State.WAIT_NEXT:
			d.next_boss()
		var what: String = press.call(d, steps)
		if what == "p":
			d.press_parry()
		elif what == "d":
			d.press_dodge()
		d.step()
		steps += 1
	return {"won": d.won, "over": d.over, "steps": steps, "hits": d.hits, "retries": retries, "boss": d.boss, "phase": d.phase,
		"parries": d.parries, "justs": d.justs, "teach": d.teach_done.duplicate()}


func test_review_masher_parry() -> bool:
	# 弾くを一定の間隔で押し続けるだけの相手。空振りの硬直(D-5)が連打を止めているか
	for period: int in [1, 2, 4, 8, 12, 18, 24, 25, 30, 36, 37, 40, 48, 60]:
		var r := _run(func(_d: Duel, s: int) -> String: return "p" if s % period == 0 else "", 1, 0)
		print("RV masher period=%d  won=%s boss=%d phase=%d hits=%d parries=%d justs=%d steps=%d teach=%s" % [
			period, r["won"], r["boss"], r["phase"], r["hits"], r["parries"], r["justs"], r["steps"], r["teach"]])
	return true


func test_review_masher_with_retries() -> bool:
	# やり直しを続ければ、連打だけで 3 体を倒せるか
	for period: int in [1, 36, 37]:
		var r := _run(func(_d: Duel, s: int) -> String: return "p" if s % period == 0 else "", 1, 200)
		print("RV masher+retry period=%d  won=%s boss=%d phase=%d hits=%d retries=%d steps=%d(%.0f 秒) teach=%s" % [
			period, r["won"], r["boss"], r["phase"], r["hits"], r["retries"], r["steps"], r["steps"] / 120.0, r["teach"]])
	return true


func test_review_rhythm_presser_phases() -> bool:
	# 一定の間隔で弾くを押すだけの相手を、押し始めの位相を変えて回す。敵 1 を倒せた位相の数を数える(やり直しなし)
	# 負けた数が 0 で敵 2 を倒せていない行は、敵 2 か敵 3 の教える型(体力が減らない)から出られずに 20 分たった物
	for period: int in [1, 2, 3, 4, 6, 9, 12, 18, 24, 30, 35, 36, 37, 38, 39, 40, 42, 48, 54, 60, 72]:
		var beat1 := 0
		var beat2 := 0
		var lost := 0
		var fewest := 999
		for phase in period:
			var r := _run(func(_d: Duel, s: int) -> String: return "p" if s % period == phase else "", 1, 0)
			if r["boss"] >= 2:
				beat1 += 1
			if r["boss"] >= 3:
				beat2 += 1
				fewest = mini(fewest, r["hits"])
			if r["over"] and not r["won"]:
				lost += 1
		print("RV rhythm period=%d  位相 %d 通りのうち 敵 1 を倒した=%d 敵 2 も倒した=%d(その時の受けた数の最少=%s) 負けた=%d" % [
			period, period, beat1, beat2, str(fewest) if fewest < 999 else "-", lost])
	return true


func test_review_random_masher() -> bool:
	# でたらめな間隔(1〜max tick)で弾くを押し続ける相手。20 通りの種で、どこまで進むか(やり直しなし)
	for max_gap: int in [6, 20, 40, 80]:
		var beat1 := 0
		var total_parries := 0
		for s in 20:
			var rng := Rng.new(s * 31 + 7)
			var next_press := [0]
			var press := func(_d: Duel, step: int) -> String:
				if step >= next_press[0]:
					next_press[0] = step + 1 + rng.next_int(max_gap)
					return "p"
				return ""
			var r := _run(press, 1, 0)
			beat1 += 1 if r["boss"] >= 2 else 0
			total_parries += r["parries"]
		print("RV random masher gap=1..%d  20 回のうち 敵 1 を倒した=%d  弾いた数の平均=%.1f" % [max_gap, beat1, total_parries / 20.0])
	return true


func test_review_jittered_rhythm() -> bool:
	# 人の手に近づける: 間隔が lo〜hi tick でばらつく相手(20 通りの種、やり直しなし)
	# 下限が 36 未満だと、硬直(36)の最後の tick に入った押しが捨てられる(E-2)ので、下限 36 の組も見る
	for cfg: Array in [[36, 36], [36, 37], [36, 38], [36, 42], [37, 39], [35, 37], [34, 38], [33, 39], [30, 42], [24, 48], [12, 12], [12, 14], [10, 14], [8, 16], [15, 25], [5, 7], [4, 8]]:
		var beat1 := 0
		var beat2 := 0
		for s in 20:
			var rng := Rng.new(s * 131 + 5)
			var next_press := [s]
			var press := func(_d: Duel, step: int) -> String:
				if step >= next_press[0]:
					next_press[0] = step + int(cfg[0]) + rng.next_int(int(cfg[1]) - int(cfg[0]) + 1)
					return "p"
				return ""
			var r := _run(press, 1, 0)
			beat1 += 1 if r["boss"] >= 2 else 0
			beat2 += 1 if r["boss"] >= 3 else 0
		print("RV jitter 間隔 %d〜%d tick  20 回のうち 敵 1 を倒した=%d 敵 2 も倒した=%d" % [cfg[0], cfg[1], beat1, beat2])
	return true


func test_review_masher_dodge() -> bool:
	for period: int in [1, 54, 55, 60]:
		var r := _run(func(_d: Duel, s: int) -> String: return "d" if s % period == 0 else "", 1, 0)
		print("RV dodge-masher period=%d  over=%s won=%s boss=%d phase=%d hits=%d steps=%d teach=%s" % [
			period, r["over"], r["won"], r["boss"], r["phase"], r["hits"], r["steps"], r["teach"]])
	return true


func test_review_masher_both() -> bool:
	# 両方を毎 tick 押す(弾くが勝つ。E-1)/ 交互に押す
	var r := _run(func(_d: Duel, s: int) -> String: return "p" if s % 2 == 0 else "d", 1, 0)
	print("RV alternate p/d every tick  over=%s won=%s boss=%d phase=%d hits=%d parries=%d steps=%d" % [
		r["over"], r["won"], r["boss"], r["phase"], r["hits"], r["parries"], r["steps"]])
	return true


# 下手な相手: 白は T' + ずれ(−w〜+w の一様)で弾き、赤は T' − lead(0〜max_lead の一様)で避ける。
func _sloppy(seed_value: int, w: int, max_lead: int, offset: int = 0) -> Dictionary:
	var rng := Rng.new(seed_value * 7919 + 13)
	var plan := {}  # 攻撃の id → 押す tick
	var press := func(d: Duel, _s: int) -> String:
		if d.state == Duel.State.STAGGER:
			return "p"
		for a: Dictionary in d.snapshot()["attacks"]:
			if not plan.has(a["id"]):
				var jt: int = a["contact"] + d.offset
				plan[a["id"]] = jt + rng.next_int(2 * w + 1) - w if a["kind"] == "white" else jt - rng.next_int(max_lead + 1)
			if plan[a["id"]] == d.tick:
				return "p" if a["kind"] == "white" else "d"
		return ""
	return _run(press, 1, 30, offset)


func test_review_sloppy_players() -> bool:
	for cfg: Array in [[5, 29], [12, 29], [14, 29], [16, 29], [20, 29], [12, 35], [16, 40]]:
		var wins := 0
		var hits := 0
		var retries := 0
		var steps := 0
		var stuck := 0
		var n := 20
		for s in n:
			var r := _sloppy(s + 1, cfg[0], cfg[1])
			wins += 1 if r["won"] else 0
			hits += r["hits"]
			retries += r["retries"]
			steps += r["steps"]
			stuck += 1 if not r["over"] else 0
		print("RV sloppy w=±%d lead=0..%d  n=%d wins=%d stuck(20分で終わらない)=%d avg_hits=%.1f avg_retries=%.1f avg_time=%.0f 秒" % [
			cfg[0], cfg[1], n, wins, stuck, hits / float(n), retries / float(n), steps / float(n) / 120.0])
		if cfg[0] <= 12 and cfg[1] <= 29:
			eq(wins, n, "窓の中だけで押す相手は必ず勝つ(w=%d)" % cfg[0])
			eq(hits, 0, "窓の中だけで押す相手は無傷(w=%d)" % cfg[0])
	return true


func test_review_window_edge_players_with_offset() -> bool:
	# 判定のずれ −12・+12 で、窓の端(−12・+12)だけで押す相手、赤を T'−29・T' で避ける相手
	for offset: int in [-12, 0, 12]:
		for edge: int in [-12, 12]:
			# 避けるのは 0・17 tick 前。29 tick 前だと、30 tick 前に線へ届いた白(red_3_c)の押し込み中に避けることになり、
			# その白は避けられず(§9.5)、硬直 54 で弾けもしないので 1 回当たる(仕様どおりの動き。最初の実行で確認: hits=1)
			for lead: int in [0, 17]:
				var press := func(d: Duel, _s: int) -> String:
					if d.state == Duel.State.STAGGER:
						return "p"
					for a: Dictionary in d.snapshot()["attacks"]:
						var jt: int = a["contact"] + d.offset
						if a["kind"] == "white" and d.tick == jt + edge:
							return "p"
						if a["kind"] == "red" and d.tick == jt - lead:
							return "d"
					return ""
				var r := _run(press, 1, 0, offset)
				print("RV edge offset=%d parry@%+d dodge@-%d  won=%s boss=%d phase=%d hits=%d steps=%d" % [offset, edge, lead, r["won"], r["boss"], r["phase"], r["hits"], r["steps"]])
				ok(r["won"] and r["hits"] == 0, "offset %d・弾く %+d・避ける −%d で無傷のはず" % [offset, edge, lead])
	return true


# 型 1 個を、避けるだけで無傷で抜ける押し方(総当たり)。攻撃は T の順。free は次に押せる tick、cover は今の避けるが効く最後の tick。
# 見つかれば押す tick の配列、無ければ null。
func _dodge_plan(cs: Array, i: int, free: int, cover: int) -> Variant:
	if i >= cs.size():
		return []
	var t_hit: int = cs[i]
	if t_hit <= cover:
		return _dodge_plan(cs, i + 1, free, cover)
	for t in range(maxi(free, t_hit - (B.DODGE_TICKS - 1)), t_hit + 1):
		var rest: Variant = _dodge_plan(cs, i + 1, t + B.DODGE_LOCK, t + B.DODGE_TICKS - 1)
		if rest != null:
			return [t] + rest
	return null


func test_review_dodge_only_clearable() -> bool:
	# D-6「速い連続の攻撃は避けきれず、弾くしかない」が、同梱の型で成り立っているか。
	# 総当たりで見つけた押し方を、実際に Duel で 3 周ぶん流して、受けた数 0 を確かめる
	var clearable: Array = []
	var not_clearable: Array = []
	for boss: Dictionary in PatternStore.shared()["bosses"]:
		for phase: Dictionary in boss["phases"]:
			for p: Dictionary in phase["patterns"]:
				var cs: Array = PatternStore.contacts(p).map(func(c: Dictionary) -> int: return c["tick"])
				var plan: Variant = _dodge_plan(cs, 0, -9999, -9999)
				if plan == null:
					not_clearable.append(p["id"])
					continue
				clearable.append("%s%s" % [p["id"], plan])
				var plain := p.duplicate(true)
				plain["teach"] = false
				var d := Duel.new(1, Duel.Mode.FIXED, 1, null, bosses_of([plain]))
				var start := -1
				for s in (int(p["length"]) + B.GAP_TICKS) * 3 + B.INTRO_TICKS:
					if d.state == Duel.State.PATTERN and d.tick == d.state_from:
						start = d.tick
					if start >= 0 and (d.tick - start) in plan:
						d.press_dodge()
					d.step()
					if not d.events().is_empty() and d.events()[0]["type"] == "pattern_start":
						start = d.tick - 1
						if 0 in plan:
							pass
				eq(d.hits, 0, "%s: 避けるだけで 3 周を無傷" % p["id"])
				eq(d.parries, 0, "%s: 弾いていない" % p["id"])
	print("RV dodge-only で無傷で抜けられる型 %d 個(押す tick): %s" % [clearable.size(), ", ".join(clearable)])
	print("RV dodge-only では抜けられない型 %d 個: %s" % [not_clearable.size(), ", ".join(not_clearable)])
	return true


func test_review_perfect_dodger_never_ends() -> bool:
	# 全部を避ける相手(弾かない)。敵 1 の教える型は弾かないと抜けられないので、そこで止まる
	var press := func(d: Duel, _s: int) -> String:
		for a: Dictionary in d.snapshot()["attacks"]:
			if d.tick == a["contact"] + d.offset - 10:
				return "d"
		return ""
	var r := _run(press, 1, 0)
	print("RV 全部避ける相手  over=%s boss=%d phase=%d hits=%d steps=%d teach=%s" % [r["over"], r["boss"], r["phase"], r["hits"], r["steps"], r["teach"]])
	return true


func test_review_parry_only_on_boss3() -> bool:
	# 赤も弾こうとする相手(避けない)。敵 3 の教える型で止まるか、体力は減らないか
	var d := Duel.new(1, Duel.Mode.PRACTICE, 3)
	var steps := 0
	var free_hits := 0
	while steps < 120 * 120 and not d.over:
		for a: Dictionary in d.snapshot()["attacks"]:
			if d.tick == a["contact"]:
				d.press_parry()
		d.step()
		for e: Dictionary in d.events():
			if e["type"] == "hurt_free":
				free_hits += 1
		steps += 1
	print("RV 赤を弾こうとする相手(敵 3)  120 秒後 over=%s hp=%d hurt_free=%d teach_done=%s" % [d.over, d.player_hp, free_hits, d.teach_done[2]])
	eq(d.player_hp, B.PLAYER_HP, "教える型の間は体力が減らない")
	return true
