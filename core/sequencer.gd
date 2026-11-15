# 1 つの段階の中で、型の出る順と腕の入れ替えを決める(仕様書 §9.8)。
# 種・敵・段階と「何個目か」だけで決まり、操作や時刻では変わらない(INV-3)。
extends RefCounted

const B := preload("res://core/balance.gd")
const Rng := preload("res://core/rng.gd")

var _patterns: Array
var _pool: Array = []  # 教える型を除いた物(2 周目から使う)
var _rng: Rng
var _index := 0  # 1 周目で次に出す番号
var _teach_ok: bool
var _last_id := ""


# boss と phase は 1 から。patterns はその段階の型(定義の順)。teach_ok が真なら教える型を飛ばす。
# mixed が真なら、定義の順の 1 周目を飛ばして、最初から混ぜて出す(終わらない連戦の 2 周目から。v0.3.0)。
func _init(seed_value: int, boss: int, phase: int, patterns: Array, teach_ok: bool, mixed: bool = false) -> void:
	_patterns = patterns
	_teach_ok = teach_ok
	if mixed:
		_index = patterns.size()
	_rng = Rng.new(phase_seed(seed_value, boss, phase))
	for p: Dictionary in patterns:
		if not p["teach"]:
			_pool.append(p)


static func phase_seed(seed_value: int, boss: int, phase: int) -> int:
	return (seed_value ^ ((boss * B.SEED_BOSS_MUL + phase * B.SEED_PHASE_MUL) & Rng.MASK)) & Rng.MASK


# 教える型を成功した。次からは 2 個目へ進む。
func teach_cleared() -> void:
	_teach_ok = true


# 次に出す型。{ pattern, swapped }。pattern は入れ替え済みの写しで、元のデータは変えない。
func next() -> Dictionary:
	while _index < _patterns.size():
		var p: Dictionary = _patterns[_index]
		if p["teach"] and not _teach_ok:
			_last_id = p["id"]
			return {"pattern": p, "swapped": false}  # 成功するまで同じ型
		_index += 1
		if not p["teach"]:
			_last_id = p["id"]
			return {"pattern": p, "swapped": false}  # 1 周目は入れ替えない(乱数も引かない)
	if _pool.is_empty():
		return {"pattern": _patterns[0], "swapped": false}
	var pick: Dictionary = _pool[_rng.next_int(_pool.size())]
	var tries := 0
	while pick["id"] == _last_id and tries < B.RESHUFFLE_TRIES:
		pick = _pool[_rng.next_int(_pool.size())]
		tries += 1
	_last_id = pick["id"]
	if _rng.next_int(2) == 1:
		return {"pattern": swap_arms(pick), "swapped": true}
	return {"pattern": pick, "swapped": false}


# L と R を入れ替えた写し(T はそのまま)。
static func swap_arms(pattern: Dictionary) -> Dictionary:
	var out := pattern.duplicate(true)
	for a: Dictionary in out["attacks"]:
		if a["arm"] == "L":
			a["arm"] = "R"
		elif a["arm"] == "R":
			a["arm"] = "L"
	return out
