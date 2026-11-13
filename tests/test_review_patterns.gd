# レビュー用: 型のデータ(data/patterns.json)の、検査 (a)〜(f) が見ていない所を数字で出す。
# 頭の重なり・白と赤の間・判定のずれ ±12 での見え方・目安(§9.7 の表)との違い。print の RV 行が証拠。
extends "res://tests/suite.gd"

const PatternStore := preload("res://core/pattern_store.gd")
const Attack := preload("res://core/attack.gd")
const Sequencer := preload("res://core/sequencer.gd")
const Kit := preload("res://ui/kit.gd")


func _each(fn: Callable) -> void:
	var bosses: Array = PatternStore.shared()["bosses"]
	for bi in bosses.size():
		for pi in bosses[bi]["phases"].size():
			for p: Dictionary in bosses[bi]["phases"][pi]["patterns"]:
				fn.call(p, bi + 1, pi + 1)


# 頭が見えている間の位置。linger は、白が線に届いた後に当たり点へ残る tick(押し込み 13 + 判定のずれ)
func _head_at(a: Dictionary, tick: int, linger: int) -> Variant:
	var start: int = a["at"]
	var t_hit := Attack.contact_tick(a, start)
	var gone := t_hit + (linger if a["kind"] == "white" else 0)
	if tick < start or tick > gone:
		return null
	return Attack.head_pos(a, start, tick)


func test_review_heads_do_not_overlap_on_screen() -> bool:
	# 2 つの頭の中心が、半径の和(白 22・赤 24×1.15)より近づく tick があるか。入れ替えた型も見る。
	# 何も押さない時(白は押し込みの終わりまで残る)と、判定のずれ +12 の時(さらに 12 tick 残る)
	var worst := {}
	_each(func(p: Dictionary, _b: int, _ph: int) -> void: _overlaps(p, worst))
	for key: String in worst:
		print("RV 頭の重なり: %s  いちばん近い = %s px(tick %d、半径の和 %s)" % [key, worst[key][0], worst[key][1], worst[key][2]])
	print("RV 頭の重なり: %d 組" % worst.size())
	# この調べ方が重なりを見つけられることの確かめ: わざと重なる型(同じ腕に 10 tick 差・となりの腕に同じ tick)
	var control := {}
	_overlaps(pattern("same_arm", [atk("white", "L", 36, 42, 0), atk("white", "L", 36, 42, 10)], 300), control)
	_overlaps(pattern("far_arms", [atk("white", "L", 36, 42, 0), atk("white", "R", 36, 42, 0)], 300), control)
	_overlaps(pattern("next_arms_same_tick", [atk("white", "L", 36, 42, 0), atk("red", "T", 36, 42, 0)], 300), control)
	print("RV 頭の重なり(確かめ用の型): %s" % [control.keys()])
	ok(control.keys().any(func(k: String) -> bool: return k.begins_with("same_arm")), "同じ腕に 10 tick 差の型は、重なりとして見つかる")
	ok(not control.keys().any(func(k: String) -> bool: return k.begins_with("far_arms")), "L と R(当たり点が 120 px 離れる)は重ならない")
	return true


# 型 1 個(と、腕を入れ替えた物)の、重なる頭の組を out に足す。
func _overlaps(p: Dictionary, out: Dictionary) -> void:
	for variant: Dictionary in [p, Sequencer.swap_arms(p)]:
		for linger: int in [B.PUSH_TICKS, B.PUSH_TICKS + B.OFFSET_MAX]:
			var attacks: Array = variant["attacks"]
			for i in attacks.size():
				for j in range(i + 1, attacks.size()):
					var r_sum: float = _radius(attacks[i]) + _radius(attacks[j])
					for tick in range(0, int(variant["length"]) + 40):
						var pa: Variant = _head_at(attacks[i], tick, linger)
						var pb: Variant = _head_at(attacks[j], tick, linger)
						if pa == null or pb == null:
							continue
						var dist: float = (pa as Vector2).distance_to(pb)
						if dist < r_sum:
							var key := "%s%s linger=%d %s%d×%s%d" % [p["id"], "(入れ替え)" if variant != p else "", linger, attacks[i]["arm"], i, attacks[j]["arm"], j]
							if not out.has(key) or dist < out[key][0]:
								out[key] = [snappedf(dist, 0.1), tick, r_sum]


func _radius(a: Dictionary) -> float:
	return Kit.HEAD_R_RED * 1.15 if a["kind"] == "red" else Kit.HEAD_R_WHITE


func test_review_gaps_table() -> bool:
	# 型ごとの、当たる tick の差と種類の並び。白→赤・赤→白の差の最小、同じ腕の「前の当たり → 次の始まり」の最小
	var least := {}  # 種類の並び → 差の最小(ラムダの中から書けるよう辞書で持つ)
	var who := {}
	_each(func(p: Dictionary, _b: int, _ph: int) -> void:
		var cs := PatternStore.contacts(p)
		for i in range(1, cs.size()):
			var gap: int = cs[i]["tick"] - cs[i - 1]["tick"]
			var kind: String = "%s→%s" % [cs[i - 1]["kind"], cs[i]["kind"]]
			if gap < int(least.get(kind, 9999)):
				least[kind] = gap
				who[kind] = p["id"])
	var min_rw := int(least.get("red→white", 9999))
	print("RV 当たる tick の差の最小: %s  その型: %s" % [least, who])
	# 赤を避けた硬直(54)が明けてから、次の白の窓が閉じるまでの余り。赤を T' ちょうどで避けた時がいちばん厳しい
	eq(min_rw - B.DODGE_LOCK + B.PARRY_WINDOW >= B.PARRY_WINDOW, true, "赤を T' で避けても、次の白の窓の後ろ半分(T〜T+12)は全部使える")
	print("RV 赤を T' ちょうどで避けた時、次の白を弾ける tick = T%+d 〜 T+12(差の最小 %d − 硬直 54)" % [B.DODGE_LOCK - min_rw, min_rw])
	return true


func test_review_white_then_red_needs_parry_before_dodge() -> bool:
	# 白の後 30 tick 以内に赤が来る組: 赤を早めに避ける(白が押し込みに入った後、弾く前)と、白は避けられず、硬直 54 で弾けもしない
	var found: Array = []
	_each(func(p: Dictionary, _b: int, _ph: int) -> void:
		var cs := PatternStore.contacts(p)
		for i in range(1, cs.size()):
			var gap: int = cs[i]["tick"] - cs[i - 1]["tick"]
			if cs[i - 1]["kind"] == "white" and cs[i]["kind"] == "red" and gap <= B.DODGE_TICKS - 1 + B.PUSH_TICKS:
				found.append("%s(白 %d → 赤 %d、差 %d)" % [p["id"], cs[i - 1]["tick"], cs[i]["tick"], gap]))
	print("RV 白の押し込みと赤の避ける時間が重なる組: %s" % [found])
	# red_3_c で確かめる: 白(T=108)を弾かずに、赤(T=138)を 29 tick 前(= 白の T+1)に避ける
	var bosses: Array = PatternStore.shared()["bosses"]
	var p3: Dictionary = bosses[2]["phases"][2]["patterns"][2]
	eq(p3["id"], "red_3_c", "型の並び")
	var d := Duel.new(1, Duel.Mode.FIXED, 1, null, bosses_of([p3]))
	press_at(d, 120 + 109, "dodge")
	var ev := collect_to(d, 120 + 200)
	print("RV red_3_c: 白の T+1 に避ける → %s  hp=%d" % [types(ev).filter(func(t: String) -> bool: return t != "attack_start"), d.player_hp])
	return true


func test_review_guideline_table() -> bool:
	# §9.7 の「作る時の目安」と違う所(検査の対象ではない)
	var notes: Array = []
	_each(func(p: Dictionary, b: int, ph: int) -> void:
		if p["teach"]:
			return
		for a: Dictionary in p["attacks"]:
			var travel: int = a["travel1"] + a["travel2"]
			if a["hold"] > 0 and a["travel1"] != a["travel2"]:
				notes.append("%s: ための前後で速さが違う(travel1 %d・travel2 %d)" % [p["id"], a["travel1"], a["travel2"]])
			if b == 1 and ph == 1 and travel != 96:
				notes.append("%s: 敵 1 段階 1 は travel 96 の目安(実際 %d)" % [p["id"], travel])
			if b == 3 and ph == 1 and a["kind"] == "red" and (travel < 96 or travel > 144):
				notes.append("%s: 敵 3 段階 1 の赤は travel 96〜144 の目安(実際 %d)" % [p["id"], travel])
			if b == 3 and ph == 2 and a["kind"] == "white" and travel != 60:
				notes.append("%s: 敵 3 段階 2 の白は 60 の目安(実際 %d)" % [p["id"], travel])
			if b == 2 and ph == 1 and a["hold"] == 0:
				notes.append("%s: 敵 2 段階 1 は ため だけの目安" % p["id"]))
	for n: String in notes:
		print("RV 目安との違い: ", n)
	print("RV 目安との違い: %d 件" % notes.size())
	return true


func test_review_time_grid() -> bool:
	# 当たる tick と、型の長さ + 間(72)が、どれも 6 の倍数か(一定の間隔で押す相手が抜ける理由の裏づけ)
	var mods := {}
	var cycle_mods := {}
	_each(func(p: Dictionary, _b: int, _ph: int) -> void:
		for c: Dictionary in PatternStore.contacts(p):
			mods[int(c["tick"]) % 6] = int(mods.get(int(c["tick"]) % 6, 0)) + 1
		cycle_mods[(int(p["length"]) + B.GAP_TICKS) % 6] = int(cycle_mods.get((int(p["length"]) + B.GAP_TICKS) % 6, 0)) + 1)
	print("RV 当たる tick を 6 で割った余りの数 = %s  (型の長さ + 72)を 6 で割った余りの数 = %s" % [mods, cycle_mods])
	return true


func test_review_windup_pull_direction_per_arm() -> bool:
	# 予兆の「敵の中心の向きへ 20 px 引く」(§9.4)が、腕ごとに、進む向きに対してどちら向きか。
	# 引き終わり(予兆の最後の tick)から、動き出し(次の tick)へ、頭がどれだけ飛ぶかも出す
	for arm: String in ["L", "R", "T"]:
		var a := atk("white", arm, 48, 96)
		var pulled := Attack.head_pos(a, 0, 47)
		var moving := Attack.head_pos(a, 0, 48)
		var origin: Vector2 = B.ORIGIN[arm]
		var travel_dir := origin.direction_to(B.CONTACT[arm])
		var along := (pulled - origin).dot(travel_dir)
		print("RV 予兆の引き: 腕 %s  予兆の最後 = %s  動き出し = %s  進む向きの成分 = %+.1f px(+ は線の向き)" % [arm, pulled.snapped(Vector2(0.1, 0.1)), moving, along])
	return true
