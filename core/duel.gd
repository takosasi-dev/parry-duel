# 1 回の対戦の全状態と step()(仕様書 §9.3・§9.6)。よろけ・反撃・段階・敵の進み・勝ち負けを持つ。
# 弾く・避ける・当たるの判定そのものは judge.gd に聞く。ui は events() と snapshot() を読むだけ(INV-1)。
extends RefCounted

const B := preload("res://core/balance.gd")
const Attack := preload("res://core/attack.gd")
const Judge := preload("res://core/judge.gd")
const PatternStore := preload("res://core/pattern_store.gd")
const Sequencer := preload("res://core/sequencer.gd")

enum Mode { FIXED, DAILY, PRACTICE }
enum State { INTRO, PATTERN, GAP, STAGGER, RECOVER, WAIT_NEXT, DONE }

var seed_value: int
var mode: int
var boss: int  # 1〜3
var phase := 1  # 1〜3
var tick := 0
var offset := 0

var player_hp: int = B.PLAYER_HP
var lock := 0
var dodge_ticks := 0
var hurt_ticks := 0
var freeze_ticks := 0

var boss_hp: int = B.BOSS_HP
var stagger := 0
var state: int = State.INTRO
var state_from := 0  # 今の状態に入った tick
var state_until: int = B.INTRO_TICKS  # 今の状態が明ける tick

var hits := 0
var justs := 0
var parries := 0
var combo := 0
var retries := 0
var base_ticks := 0  # やり直しの前までの時間
var teach_done: Array = [false, false, false]
var over := false
var won := false

var _bosses: Array
var _seq: Sequencer
var _pattern: Dictionary = {}
var _pattern_start := 0
var _attacks: Array = []
var _next_id := 1
var _want_parry := false
var _want_dodge := false
var _events: Array = []


# mode 0 = いつも、1 = 今日、2 = 練習。carry は retry_carry() の値か null。
# bosses はテスト用(null なら同梱の型)。
func _init(p_seed: int, p_mode: int, start_boss: int, carry: Variant = null, bosses: Variant = null) -> void:
	seed_value = p_seed
	mode = p_mode
	boss = clampi(start_boss, 1, B.BOSS_COUNT)
	_bosses = bosses if bosses is Array else PatternStore.shared()["bosses"]
	if carry is Dictionary:
		hits = int(carry.get("hits", 0))
		base_ticks = int(carry.get("ticks", 0))
		justs = int(carry.get("justs", 0))
		parries = int(carry.get("parries", 0))
		retries = int(carry.get("retries", 0))
		var done: Variant = carry.get("teach_done")
		if done is Array and done.size() == B.BOSS_COUNT:
			for i in B.BOSS_COUNT:
				teach_done[i] = done[i] is bool and done[i]
	_seq = _new_sequencer()


# 判定のずれ。変えた後に始まる攻撃から効く(飛んでいる攻撃は、始まった時の値のまま)。
func set_offset(offset_ticks: int) -> void:
	offset = clampi(offset_ticks, B.OFFSET_MIN, B.OFFSET_MAX)


func press_parry() -> void:
	_want_parry = true


func press_dodge() -> void:
	_want_dodge = true


# 覚えている押しを捨てる。一時停止に入る時と、再開する時に ui が呼ぶ(止まる直前の押しを、再開の後に使わない)。
func clear_input() -> void:
	_want_parry = false
	_want_dodge = false


func is_over() -> bool:
	return over


func events() -> Array:
	return _events


func time_ticks() -> int:
	return base_ticks + tick


func result() -> Dictionary:
	return {"won": won, "mode": mode, "boss": boss, "hits": hits, "ticks": time_ticks(),
		"justs": justs, "parries": parries, "retries": retries}


# 負けて「この敵からやり直す」の時に、次の Duel へ渡す値(E-13)。
func retry_carry() -> Dictionary:
	return {"hits": hits, "ticks": time_ticks(), "justs": justs, "parries": parries,
		"retries": retries + 1, "teach_done": teach_done.duplicate()}


# 描画用。attacks は { id, start, contact, kind, arm, windup, travel1, hold, travel2, free, pushed, offset } の配列(読むだけ)。
func snapshot() -> Dictionary:
	return {
		"tick": tick, "mode": mode, "boss": boss, "phase": phase, "boss_hp": boss_hp, "stagger": stagger,
		"state": state, "state_from": state_from, "state_until": state_until,
		"player_hp": player_hp, "lock": lock, "dodge_ticks": dodge_ticks, "hurt_ticks": hurt_ticks,
		"freeze_ticks": freeze_ticks, "hits": hits, "justs": justs, "parries": parries, "combo": combo,
		"retries": retries, "time_ticks": time_ticks(), "teaching": not teach_done[boss - 1],
		"pattern_id": _pattern.get("id", ""), "attacks": _attacks, "over": over, "won": won,
	}


# 敵を倒した後、次の敵へ進める。
func next_boss() -> void:
	if state != State.WAIT_NEXT:
		return
	boss += 1
	phase = 1
	boss_hp = B.BOSS_HP
	stagger = 0
	player_hp = B.PLAYER_HP
	lock = 0
	dodge_ticks = 0
	hurt_ticks = 0
	freeze_ticks = 0
	_attacks.clear()
	_pattern = {}
	_seq = _new_sequencer()
	_enter(State.INTRO, B.INTRO_TICKS)


# 1 tick 進める。中の順番は §9.3 のとおりで、変えない。
func step() -> void:
	_events = []
	if over or state == State.WAIT_NEXT:  # 1. 終わり・次の敵待ち
		_want_parry = false
		_want_dodge = false
		return
	if freeze_ticks > 0:  # 2. 止め。入力は 1 つずつ覚えたまま(E-8)
		freeze_ticks -= 1
		return
	_use_input()  # 3.
	_advance_boss()  # 4.
	_resolve_attacks()  # 5.
	lock = maxi(lock - 1, 0)  # 6.
	dodge_ticks = maxi(dodge_ticks - 1, 0)
	hurt_ticks = maxi(hurt_ticks - 1, 0)
	if player_hp <= 0 and not over:  # 7.
		over = true
		won = false
		state = State.DONE
		_attacks.clear()
		_emit("player_down")
	tick += 1


func _emit(type: String, extra: Dictionary = {}) -> void:
	var e := extra.duplicate()  # 既定値の {} は呼び出しをまたいで同じ物なので、書き込む前に写す
	e["type"] = type
	e["tick"] = tick
	_events.append(e)


func _enter(new_state: int, ticks: int) -> void:
	state = new_state
	state_from = tick
	state_until = tick + ticks


func _new_sequencer() -> Sequencer:
	return Sequencer.new(seed_value, boss, phase, _bosses[boss - 1]["phases"][phase - 1]["patterns"], teach_done[boss - 1])


# 3. 入力を使う。弾く → 避ける の順。硬直の間は捨てる(E-2)。弾くを使った tick の避けるは捨てる(E-1)。
func _use_input() -> void:
	var parry := _want_parry
	var dodge := _want_dodge
	_want_parry = false
	_want_dodge = false
	if lock > 0:
		return
	if parry:
		_parry()
	elif dodge:
		dodge_ticks = B.DODGE_TICKS
		lock = B.DODGE_LOCK
		_emit("dodge")


func _parry() -> void:
	if state == State.STAGGER:
		_counter()
		return
	var i := Judge.parry_target(_attacks, tick)
	if i == -1:
		lock = B.WHIFF_LOCK
		combo = 0
		_emit("parry_whiff")
		return
	var a: Dictionary = _attacks[i]
	if a["kind"] == "red":  # 弾けない。赤は残る(E-4)
		lock = B.WHIFF_LOCK
		combo = 0
		_emit("parry_red", {"attack": a})
		return
	var diff := tick - Judge.judged_tick(a["contact"], a["offset"])
	var grade := Judge.grade(diff)
	_attacks.remove_at(i)
	parries += 1
	combo += 1
	if grade == Judge.Grade.JUST:
		justs += 1
	stagger = mini(stagger + Judge.stagger_gain(grade), B.STAGGER_THRESHOLD)
	_emit("parry", {"just": grade == Judge.Grade.JUST, "attack": a, "combo": combo, "diff": diff})
	if a["free"]:
		_teach_clear()
	if stagger >= B.STAGGER_THRESHOLD:
		_attacks.clear()
		_pattern = {}
		_enter(State.STAGGER, B.STAGGER_TICKS)
		_emit("stagger")


# 教える型を成功した。型の残りを待たずに GAP へ進む(§9.8)。
func _teach_clear() -> void:
	teach_done[boss - 1] = true
	_seq.teach_cleared()
	_pattern = {}
	_enter(State.GAP, B.GAP_TICKS)
	_emit("teach_clear")


func _counter() -> void:
	boss_hp -= 1
	freeze_ticks = B.COUNTER_FREEZE
	_emit("counter", {"boss": boss, "boss_hp": boss_hp})
	if boss_hp > 0:
		phase += 1
		stagger = 0
		_seq = _new_sequencer()
		_enter(State.RECOVER, B.RECOVER_TICKS)
		_emit("boss_phase", {"phase": phase})
		return
	_emit("boss_down", {"boss": boss})
	if boss >= B.BOSS_COUNT or mode == Mode.PRACTICE:
		over = true
		won = true
		state = State.DONE
	else:
		state = State.WAIT_NEXT
		state_from = tick


# 4. 敵の状態を進める。
func _advance_boss() -> void:
	match state:
		State.INTRO, State.GAP, State.RECOVER:
			if tick >= state_until:
				_start_pattern()
		State.STAGGER:
			if tick >= state_until:  # 立ち直り(E-5)
				stagger = B.STAGGER_AFTER_RECOVER
				_enter(State.GAP, B.GAP_TICKS)
				_emit("boss_recover")
	if state == State.PATTERN:
		for a: Dictionary in _pattern["attacks"]:
			if _pattern_start + a["at"] == tick:
				_spawn(a)
		if tick - _pattern_start >= _pattern["length"]:
			_pattern = {}
			_enter(State.GAP, B.GAP_TICKS)


func _start_pattern() -> void:
	var picked := _seq.next()
	_pattern = picked["pattern"]
	_pattern_start = tick
	_enter(State.PATTERN, _pattern["length"])
	_emit("pattern_start", {"id": _pattern["id"], "teach": _pattern["teach"], "swapped": picked["swapped"]})


func _spawn(def: Dictionary) -> void:
	var a := {
		"id": _next_id, "start": tick, "contact": Attack.contact_tick(def, tick), "kind": def["kind"], "arm": def["arm"],
		"windup": def["windup"], "travel1": def["travel1"], "hold": def["hold"], "travel2": def["travel2"],
		"free": _pattern["teach"], "pushed": false, "offset": offset,
	}
	_next_id += 1
	_attacks.append(a)
	_emit("attack_start", {"attack": a})


# 5. 攻撃の時刻の処理。
func _resolve_attacks() -> void:
	var i := 0
	while i < _attacks.size():
		var a: Dictionary = _attacks[i]
		var due := Judge.due(a, tick, dodge_ticks, hurt_ticks)
		if due == Judge.Due.NONE:
			i += 1
			continue
		if due == Judge.Due.PUSH:
			a["pushed"] = true
			i += 1
			continue
		_attacks.remove_at(i)
		match due:
			Judge.Due.AVOID:
				_emit("dodge_avoid", {"attack": a})
				if a["free"] and a["kind"] == "red":
					_teach_clear()
			Judge.Due.FADE:
				_emit("attack_fade", {"attack": a})
			Judge.Due.HIT:
				_hit(a)


func _hit(a: Dictionary) -> void:
	if a["free"]:  # 教える型の間は減らない(E-6)
		_emit("hurt_free", {"attack": a})
		return
	player_hp -= 1
	hits += 1
	hurt_ticks = B.HURT_TICKS
	lock = maxi(lock, B.HURT_LOCK)
	combo = 0
	_emit("hurt", {"attack": a, "player_hp": player_hp})
