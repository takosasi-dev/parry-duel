# data/patterns.json の読み込みと検査(仕様書 §9.7)。検査 (a)〜(f) と、教える型の中身(INV-9)を見る。
# 読んだ数は int に直して返す(JSON の数は float で来る)。起動時は形 (a) だけを検査する。
extends RefCounted

const B := preload("res://core/balance.gd")
const Attack := preload("res://core/attack.gd")

const PATH := "res://data/patterns.json"
const BOSS_IDS := ["stone", "swing", "red"]
const TIME_KEYS := ["at", "windup", "travel1", "hold", "travel2"]
# 教える型(INV-9)。中身を変えない。
const TEACH := {
	"stone_1_teach": {"length": 420, "attack": {"at": 0, "kind": "white", "arm": "L", "windup": 120, "travel1": 180, "hold": 0, "travel2": 0}},
	"swing_1_teach": {"length": 432, "attack": {"at": 0, "kind": "white", "arm": "R", "windup": 96, "travel1": 72, "hold": 72, "travel2": 72}},
	"red_1_teach": {"length": 384, "attack": {"at": 0, "kind": "red", "arm": "T", "windup": 120, "travel1": 144, "hold": 0, "travel2": 0}},
}

static var _shared: Dictionary = {}


# 同梱の型を 1 回だけ読む。{ ok, bosses, errors }。形の検査 (a) に落ちたら ok = false(E-17)。
static func shared() -> Dictionary:
	if _shared.is_empty():
		_shared = load_file(PATH)
	return _shared


static func load_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "bosses": [], "errors": ["型のデータが無い: " + path]}
	return load_text(FileAccess.get_file_as_string(path))


static func load_text(text: String) -> Dictionary:
	var j := JSON.new()
	if j.parse(text) != OK:
		return {"ok": false, "bosses": [], "errors": ["JSON として読めない"]}
	var errors := check_shape(j.data)
	if not errors.is_empty():
		return {"ok": false, "bosses": [], "errors": errors}
	return {"ok": true, "bosses": _normalize(j.data), "errors": []}


static func _is_count(v: Variant) -> bool:
	return (v is float or v is int) and float(v) >= 0.0 and float(v) == floorf(float(v))


# (a) 形。問題を文字の配列で返す(空なら通った)。
static func check_shape(raw: Variant) -> Array:
	var errors: Array = []
	if not (raw is Dictionary) or not (raw.get("bosses") is Array):
		return ["bosses が無い"]
	var bosses: Array = raw["bosses"]
	if bosses.size() != B.BOSS_COUNT:
		return ["敵の数が %d でない" % B.BOSS_COUNT]
	for bi in bosses.size():
		var boss: Variant = bosses[bi]
		if not (boss is Dictionary) or not (boss.get("id") is String) or boss["id"] != BOSS_IDS[bi]:
			errors.append("敵 %d の id が %s でない" % [bi + 1, BOSS_IDS[bi]])
			continue
		if not (boss.get("phases") is Array) or boss["phases"].size() != B.BOSS_HP:
			errors.append("%s: 段階が %d でない" % [boss["id"], B.BOSS_HP])
			continue
		for pi in B.BOSS_HP:
			var phase: Variant = boss["phases"][pi]
			var where := "%s 段階 %d" % [boss["id"], pi + 1]
			if not (phase is Dictionary) or not (phase.get("patterns") is Array):
				errors.append(where + ": patterns が無い")
				continue
			var patterns: Array = phase["patterns"]
			if patterns.size() != B.PATTERNS_PER_PHASE[pi]:
				errors.append("%s: 型の数が %d でない" % [where, B.PATTERNS_PER_PHASE[pi]])
			for qi in patterns.size():
				errors.append_array(_check_pattern_shape(patterns[qi], where, pi == 0 and qi == 0))
	return errors


static func _check_pattern_shape(p: Variant, where: String, must_teach: bool) -> Array:
	var errors: Array = []
	if not (p is Dictionary) or not (p.get("id") is String):
		return [where + ": id の無い型がある"]
	var id: String = p["id"]
	var teach: bool = p.get("teach") is bool and p["teach"]
	if teach != must_teach:
		errors.append(id + (": 教える型でなければならない" if must_teach else ": 教える型は各敵の最初の 1 個だけ"))
	if not _is_count(p.get("length")):
		errors.append(id + ": length が 0 以上の整数でない")
	if not (p.get("attacks") is Array) or p["attacks"].is_empty():
		return errors + [id + ": attacks が無い"]
	for a: Variant in p["attacks"]:
		if not (a is Dictionary):
			errors.append(id + ": 攻撃が辞書でない")
			continue
		if not (a.get("kind") is String) or not (a["kind"] in ["white", "red"]):
			errors.append(id + ": kind が white・red でない")
		if not (a.get("arm") is String) or not (a["arm"] in ["L", "R", "T"]):
			errors.append(id + ": arm が L・R・T でない")
		for k: String in TIME_KEYS:
			if not _is_count(a.get(k)):
				errors.append("%s: %s が 0 以上の整数でない" % [id, k])
	return errors


static func _normalize(raw: Dictionary) -> Array:
	var bosses: Array = []
	for boss: Dictionary in raw["bosses"]:
		var phases: Array = []
		for phase: Dictionary in boss["phases"]:
			var patterns: Array = []
			for p: Dictionary in phase["patterns"]:
				var attacks: Array = []
				for a: Dictionary in p["attacks"]:
					var one := {"kind": a["kind"], "arm": a["arm"]}
					for k: String in TIME_KEYS:
						one[k] = int(a[k])
					attacks.append(one)
				patterns.append({"id": p["id"], "teach": p.get("teach") is bool and p["teach"], "length": int(p["length"]), "attacks": attacks})
			phases.append({"patterns": patterns})
		bosses.append({"id": boss["id"], "phases": phases})
	return bosses


# 型の時間を速さ(%)に合わせた写し(v0.2.0)。100 ならそのまま返す。整数の計算だけ(INV-4)で、四捨五入。
# 型を選んだ後に掛けるので、型の出る順(今日の3連戦の順)は速さで変わらない。
static func scaled(pattern: Dictionary, speed: int) -> Dictionary:
	if speed == B.SPEED_NORMAL:
		return pattern
	var out := pattern.duplicate(true)
	out["length"] = scale_ticks(int(out["length"]), speed)
	for a: Dictionary in out["attacks"]:
		for k: String in TIME_KEYS:
			a[k] = scale_ticks(int(a[k]), speed)
	return out


@warning_ignore("integer_division")
static func scale_ticks(ticks: int, speed: int) -> int:
	return (ticks * B.SPEED_NORMAL + speed / 2) / speed


# 型の中の当たる tick(型の始まりを 0 として)を、早い順に返す。
static func contacts(pattern: Dictionary) -> Array:
	var out: Array = []
	for a: Dictionary in pattern["attacks"]:
		out.append({"tick": Attack.contact_tick(a, a["at"]), "kind": a["kind"]})
	out.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x["tick"] < y["tick"])
	return out


# (b)〜(f) と、教える型の中身、同じ id の重なり。bosses は load_* が返した物。
static func check_all(bosses: Array) -> Array:
	var errors: Array = []
	var seen := {}
	for bi in bosses.size():
		for pi in bosses[bi]["phases"].size():
			for p: Dictionary in bosses[bi]["phases"][pi]["patterns"]:
				var id: String = p["id"]
				if seen.has(id):
					errors.append(id + ": 同じ id が 2 つある")
				seen[id] = true
				errors.append_array(_check_pattern(p, bi, pi))
	for id: String in TEACH:
		if not seen.has(id):
			errors.append(id + ": 教える型が無い")
	return errors


static func _check_pattern(p: Dictionary, bi: int, pi: int) -> Array:
	var errors: Array = []
	var id: String = p["id"]
	var attacks: Array = p["attacks"]
	var has_red := false
	var has_hold := false
	for a: Dictionary in attacks:
		# (b) 時間
		if a["windup"] < B.MIN_WINDUP:
			errors.append("%s: windup が %d 未満" % [id, B.MIN_WINDUP])
		if a["travel1"] + a["travel2"] < B.MIN_TRAVEL:
			errors.append("%s: travel1 + travel2 が %d 未満" % [id, B.MIN_TRAVEL])
		if a["hold"] != 0 and (a["hold"] < B.HOLD_MIN or a["hold"] > B.HOLD_MAX):
			errors.append("%s: hold が 0 でも %d〜%d でもない" % [id, B.HOLD_MIN, B.HOLD_MAX])
		if a["hold"] > 0 and (a["travel1"] < B.MIN_SPLIT_TRAVEL or a["travel2"] < B.MIN_SPLIT_TRAVEL):
			errors.append("%s: ための前後の travel が %d 未満" % [id, B.MIN_SPLIT_TRAVEL])
		if a["hold"] == 0 and a["travel2"] != 0:
			errors.append(id + ": hold が 0 なのに travel2 がある")
		if Attack.duration(a) < B.MIN_READ_TICKS:
			errors.append("%s: 予兆から当たるまでが %d tick 未満(NFR-7)" % [id, B.MIN_READ_TICKS])
		has_red = has_red or a["kind"] == "red"
		has_hold = has_hold or a["hold"] > 0
	# (c) 間
	var cs := contacts(p)
	for i in range(1, cs.size()):
		var gap: int = cs[i]["tick"] - cs[i - 1]["tick"]
		if gap < B.MIN_CONTACT_GAP:
			errors.append("%s: 当たる tick の差が %d 未満(%d)" % [id, B.MIN_CONTACT_GAP, gap])
		if cs[i - 1]["kind"] == "red" and gap <= B.RED_AFTER_GAP:
			errors.append("%s: 赤の後 %d tick 以内に次が来る(%d)" % [id, B.RED_AFTER_GAP, gap])
	# (d) 長さ
	if p["length"] < cs[cs.size() - 1]["tick"] + B.MIN_TAIL:
		errors.append("%s: length が 最後の当たる tick + %d に足りない" % [id, B.MIN_TAIL])
	# (e) 種類
	if bi == 0 and (has_red or has_hold):
		errors.append(id + ": 敵 1 に赤か ため がある")
	if bi == 1 and has_red:
		errors.append(id + ": 敵 2 に赤がある")
	if bi == 1 and not has_hold:
		errors.append(id + ": 敵 2 の型に ため が無い")
	if bi == 2 and not has_red:
		errors.append(id + ": 敵 3 の型に赤が無い")
	# (f) 数
	if attacks.size() < B.ATTACKS_MIN[pi] or attacks.size() > B.ATTACKS_MAX[pi]:
		errors.append("%s: 攻撃の数が %d〜%d でない" % [id, B.ATTACKS_MIN[pi], B.ATTACKS_MAX[pi]])
	# 教える型の中身(INV-9)
	if p["teach"]:
		if not TEACH.has(id):
			errors.append(id + ": 知らない教える型")
		elif p["length"] != TEACH[id]["length"] or attacks.size() != 1 or attacks[0] != TEACH[id]["attack"]:
			errors.append(id + ": 教える型の中身が仕様書 §9.7 と違う")
	return errors
