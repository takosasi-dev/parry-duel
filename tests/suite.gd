# テストの土台。ok / eq で確かめ、失敗は errors にたまる。対戦を組み立てる道具も持つ。
# 各テストは最後に true を返す(途中で止まったことを見分けるため)。
extends RefCounted

const B := preload("res://core/balance.gd")
const Duel := preload("res://core/duel.gd")
const Bot := preload("res://tests/bot.gd")

var errors: Array = []


func ok(cond: bool, msg: String) -> void:
	if not cond:
		errors.append(msg)


func eq(got: Variant, want: Variant, msg: String) -> void:
	if typeof(got) != typeof(want) or got != want:
		errors.append("%s: %s のはずが %s" % [msg, want, got])


# 攻撃 1 つ(型のデータの形)。
static func atk(kind: String, arm: String, windup: int, travel1: int, at: int = 0, hold: int = 0, travel2: int = 0) -> Dictionary:
	return {"at": at, "kind": kind, "arm": arm, "windup": windup, "travel1": travel1, "hold": hold, "travel2": travel2}


# どの敵のどの段階も、渡した型だけを持つデータ。
static func bosses_of(patterns: Array) -> Array:
	var out: Array = []
	for b in B.BOSS_COUNT:
		var phases: Array = []
		for p in B.BOSS_HP:
			phases.append({"patterns": patterns})
		out.append({"id": "t%d" % b, "phases": phases})
	return out


static func pattern(id: String, attacks: Array, length: int = 600, teach: bool = false) -> Dictionary:
	return {"id": id, "teach": teach, "length": length, "attacks": attacks}


# 型 1 個だけの対戦(敵 1 から)。最初の型は tick 120 に始まる。
static func duel_of(attacks: Array, length: int = 600, teach: bool = false) -> Duel:
	return Duel.new(1, Duel.Mode.FIXED, 1, null, bosses_of([pattern("p", attacks, length, teach)]))


# d.tick が tick になるまで進める(次の step() が その tick を処理する)。
static func run_to(d: Duel, tick: int) -> void:
	var guard := 0
	while d.tick < tick and not d.over and guard < 100000:
		d.step()
		guard += 1


# tick に what("parry" か "dodge")を押して 1 tick 進め、その tick の出来事の type を返す。
static func press_at(d: Duel, tick: int, what: String) -> Array:
	run_to(d, tick)
	if what == "parry":
		d.press_parry()
	else:
		d.press_dodge()
	d.step()
	return types(d.events())


static func types(events: Array) -> Array:
	return events.map(func(e: Dictionary) -> String: return e["type"])


# tick まで進めながら、起きた出来事を全部集める。
static func collect_to(d: Duel, tick: int) -> Array:
	var out: Array = []
	var guard := 0
	while d.tick < tick and not d.over and guard < 100000:
		d.step()
		out.append_array(d.events())
		guard += 1
	return out


static func first_of(events: Array, type: String) -> Dictionary:
	for e: Dictionary in events:
		if e["type"] == type:
			return e
	return {}
