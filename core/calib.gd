# タイミング合わせの進行と計算(仕様書 §9.14)。白・上の攻撃を 144 tick ごとに 8 回出し、押したずれの中央値を出す。
# 体力は無い。判定のずれは足さない(素の差を測る)。攻撃 1 つにつき、最初の有効な押しだけを数える。
extends RefCounted

const B := preload("res://core/balance.gd")

const LEAD := B.CALIB_LEAD
const TAIL := B.CALIB_TAIL

var tick := 0
var done := false
var diffs: Array = []  # 攻撃ごとの差(tick)。押していなければ null
var last_diff: Variant = null  # 直前の有効な押しの差
var _attacks: Array = []
var _want := false
var _events: Array = []


func _init() -> void:
	for k in B.CALIB_COUNT:
		var start: int = LEAD + k * B.CALIB_INTERVAL
		_attacks.append({"id": k + 1, "start": start, "contact": start + B.CALIB_WINDUP + B.CALIB_TRAVEL, "kind": "white", "arm": "T",
			"windup": B.CALIB_WINDUP, "travel1": B.CALIB_TRAVEL, "hold": 0, "travel2": 0, "free": true, "pushed": false})
		diffs.append(null)


func press() -> void:
	_want = true


func events() -> Array:
	return _events


func step() -> void:
	_events = []
	if done:
		_want = false
		return
	if _want:
		_want = false
		_press_now()
	for a: Dictionary in _attacks:
		if a["start"] == tick:
			_events.append({"type": "attack_start", "attack": a, "tick": tick})
	if tick >= _attacks[B.CALIB_COUNT - 1]["contact"] + TAIL:
		done = true
		_events.append({"type": "calib_done", "tick": tick})
	tick += 1


func _press_now() -> void:
	var best := 0
	for k in B.CALIB_COUNT:
		if absi(tick - _attacks[k]["contact"]) < absi(tick - _attacks[best]["contact"]):
			best = k
	var d: int = tick - _attacks[best]["contact"]
	if absi(d) > B.CALIB_MAX_DIFF or diffs[best] != null:
		_events.append({"type": "calib_miss", "tick": tick})
		return
	diffs[best] = d
	last_diff = d
	_events.append({"type": "calib_hit", "attack": _attacks[best], "diff": d, "index": best, "tick": tick})


# 描画用。attacks は、まだ押されておらず、線を過ぎて間もない物まで。count は当たる tick を過ぎたか押した数。
func snapshot() -> Dictionary:
	var live: Array = []
	var count := 0
	for k in B.CALIB_COUNT:
		var a: Dictionary = _attacks[k]
		if diffs[k] != null or tick > a["contact"] + B.PUSH_TICKS:
			count += 1
		elif tick >= a["start"]:
			live.append(a)
	return {"tick": tick, "attacks": live, "count": count, "last_diff": last_diff, "done": done}


# 提案する判定のずれ(tick)。測れなかった時は null。
func result() -> Variant:
	var valid: Array = []
	for k in range(B.CALIB_SKIP, B.CALIB_COUNT):
		if diffs[k] != null:
			valid.append(diffs[k])
	return suggest(valid)


# 最初の 2 回を除いた差の配列から、中央値(偶数個なら小さい方の中央)を −12〜12 に切り詰めて返す。
# 有効な差が 4 個未満なら null。
static func suggest(valid: Array) -> Variant:
	if valid.size() < B.CALIB_MIN_VALID:
		return null
	var sorted := valid.duplicate()
	sorted.sort()
	@warning_ignore("integer_division")
	var mid: int = sorted[(sorted.size() - 1) / 2]
	return clampi(mid, B.OFFSET_MIN, B.OFFSET_MAX)
