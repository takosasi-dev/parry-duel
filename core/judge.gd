# 弾く・避ける・当たるの判定(仕様書 §9.5)。判定の決まりはここにしか無い。
# tick の整数の比べだけで行う(INV-4)。小数は使わない。
extends RefCounted

const B := preload("res://core/balance.gd")

enum Grade { MISS, PARRY, JUST }
enum Due { NONE, AVOID, FADE, HIT, PUSH }


# 判定のずれを足した、当たる tick(T')。
static func judged_tick(contact: int, offset: int) -> int:
	return contact + offset


# 弾く を使う tick を t として、相手にする攻撃の番号を返す。無ければ -1。
# 窓の中で |t − T'| が小さい方、同じなら T' が早い方(E-3)。赤も選ばれる(弾けない相手として)。
# 判定のずれは、攻撃が始まった時の値(attack の offset)を使う。飛んでいる間に設定が変わっても、その攻撃の T' は動かない。
# window は弾くの窓(やさしい設定では広い)。
static func parry_target(attacks: Array, t: int, window: int = B.PARRY_WINDOW) -> int:
	var best := -1
	var best_diff := 0
	var best_tick := 0
	for i in attacks.size():
		var jt := judged_tick(attacks[i]["contact"], attacks[i]["offset"])
		var diff := absi(t - jt)
		if diff > window:
			continue
		if best == -1 or diff < best_diff or (diff == best_diff and jt < best_tick):
			best = i
			best_diff = diff
			best_tick = jt
	return best


# 当たる tick との差(符号つき)から、空振り・弾き・ぴったりを決める。
static func grade(diff: int, window: int = B.PARRY_WINDOW, just: int = B.JUST_WINDOW) -> Grade:
	var d := absi(diff)
	if d <= just:
		return Grade.JUST
	if d <= window:
		return Grade.PARRY
	return Grade.MISS


# 空振りした tick t に、当たる tick(T')が一番近い白との差(符号つき。負 = 早い)。reach より遠ければ null。
# 表示(早すぎ・遅すぎ)と押す癖のためだけに使い、判定には使わない。
static func nearest_white(attacks: Array, t: int, reach: int) -> Variant:
	var best: Variant = null
	for a: Dictionary in attacks:
		if a["kind"] != "white":
			continue
		var diff := t - judged_tick(a["contact"], a["offset"])
		if absi(diff) <= reach and (best == null or absi(diff) < absi(int(best))):
			best = diff
	return best


static func stagger_gain(g: Grade) -> int:
	if g == Grade.JUST:
		return B.STAGGER_GAIN_JUST
	if g == Grade.PARRY:
		return B.STAGGER_GAIN_PARRY
	return 0


# この tick に、まだ決着していない攻撃に何が起きるか。
#   T' の tick:      避けている → AVOID / 当たらない時間の中 → FADE(E-7)/ 赤 → HIT / 白 → PUSH(押し込みに入る)
#   白の T' + 13:    当たらない時間の中 → FADE / それ以外 → HIT(押し込みの間の 避ける は効かない)
# pushed は「T' を過ぎて押し込みに入った白」の印。push は押し込みの長さ(弾くの窓 + 1)。
static func due(attack: Dictionary, tick: int, dodge_ticks: int, hurt_ticks: int, push: int = B.PUSH_TICKS) -> Due:
	var jt := judged_tick(attack["contact"], attack["offset"])
	if not attack["pushed"]:
		if tick < jt:
			return Due.NONE
		if dodge_ticks > 0:
			return Due.AVOID
		if hurt_ticks > 0:
			return Due.FADE
		if attack["kind"] == "red":
			return Due.HIT
		return Due.PUSH
	if tick >= jt + push:
		if hurt_ticks > 0:
			return Due.FADE
		return Due.HIT
	return Due.NONE
