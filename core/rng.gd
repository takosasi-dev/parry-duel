# 進行に関わる乱数(仕様書 §9.2・INV-3)。xorshift32 だけを持つ。SlingArc の core/rng.gd と同じ式。
# 端末や版で結果が変わらないよう、Godot の乱数関数は使わない。
extends RefCounted

const MASK := 0xFFFFFFFF

var state: int = 1


func _init(seed_value: int = 1) -> void:
	state = seed_value & MASK
	if state == 0:
		state = 1


func next() -> int:
	var x := state
	x = x ^ ((x << 13) & MASK)
	x = x ^ (x >> 17)
	x = x ^ ((x << 5) & MASK)
	state = x
	return x


# 0 以上 n 未満(§9.2 の range(n)。組み込みの range と名前が重なるので SlingArc の名前に合わせた)。n は 1 以上
func next_int(n: int) -> int:
	return next() % n
