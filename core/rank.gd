# 記録の比べ方と、時間・ずれの表示用の数(仕様書 §9.10・§9.1)。
# 受けた数が少ない方が上。同じなら時間が短い方が上。
extends RefCounted

const B := preload("res://core/balance.gd")


# a が b より上か。a・b は { hits, ticks }。
static func better(a: Dictionary, b: Dictionary) -> bool:
	var ah := int(a["hits"])
	var bh := int(b["hits"])
	return ah < bh or (ah == bh and int(a["ticks"]) < int(b["ticks"]))


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
