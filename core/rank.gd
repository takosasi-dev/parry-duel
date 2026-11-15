# 記録の比べ方と、時間・ずれの表示用の数(仕様書 §9.10・§9.1)。
# 受けた数が少ない方が上。同じなら時間が短い方が上。
extends RefCounted

const B := preload("res://core/balance.gd")


# a が b より上か。a・b は { hits, ticks }。
static func better(a: Dictionary, b: Dictionary) -> bool:
	var ah := int(a["hits"])
	var bh := int(b["hits"])
	return ah < bh or (ah == bh and int(a["ticks"]) < int(b["ticks"]))


# 終わらない連戦の記録の比べ方(v0.3.0)。a・b は { kills, hits, ticks }。倒した数が多い方、同じなら受けた数が少ない方、同じなら時間が短い方。
static func better_endless(a: Dictionary, b: Dictionary) -> bool:
	var ak := int(a["kills"])
	var bk := int(b["kills"])
	if ak != bk:
		return ak > bk
	return better(a, b)


# 秒の 10 倍(切り捨て)。18,504 tick → 1542。
@warning_ignore("integer_division")
static func tenths(ticks: int) -> int:
	return ticks * 10 / B.TICK_HZ


# 秒で小数 1 桁の文字。18,504 tick → "154.2"。
@warning_ignore("integer_division")
static func seconds_text(ticks: int) -> String:
	var t := tenths(ticks)
	return "%d.%d" % [t / 10, t % 10]


# tick を ms に直す(四捨五入)。表示専用。
static func ms(ticks: int) -> int:
	return roundi(ticks * 1000.0 / B.TICK_HZ)


# 押す癖(v0.2.0)。diffs は押したずれ(tick、負 = 早い)、offset はその回の判定のずれ(tick)。
# { n, mean_ms, suggest }。suggest は、平均のずれが 0 に近づく判定のずれ(tick)。数が足りない・ずれが小さい・今と同じなら null。
static func tendency(diffs: Array, offset: int) -> Dictionary:
	var n := diffs.size()
	if n < B.TENDENCY_MIN:
		return {"n": n, "mean_ms": 0, "suggest": null}
	var sum := 0
	for d: Variant in diffs:
		sum += int(d)
	var mean_ticks := roundi(float(sum) / n)
	var suggest: Variant = null
	if absi(mean_ticks) >= B.TENDENCY_MIN_TICKS:
		var want := clampi(offset + mean_ticks, B.OFFSET_MIN, B.OFFSET_MAX)
		if want != offset:
			suggest = want
	return {"n": n, "mean_ms": roundi(sum * 1000.0 / (n * B.TICK_HZ)), "suggest": suggest}
