# 実績の判定(v0.3.0)。対戦の出来事と 3 連戦の結果を見て、取った実績の id を返す。文言は strings.gd の ACHIEVEMENTS。
# 1 回の対戦の間だけ持つ物(ぴったりの連続・敵の始まりの受けた数)はここに、ずっと数える物(赤を避けた数など)は保存の counts に置く。
# 返す id には、もう取った物も入る(どれが新しいかは保存の側で絞る)。
extends RefCounted

const B := preload("res://core/balance.gd")
const Duel := preload("res://core/duel.gd")

const IDS := ["first_parry", "first_just", "first_counter", "just_streak", "unhurt_boss", "win_fixed", "win_daily",
	"unhurt_run", "no_retry", "dodge_red", "endless_lap2", "endless_lap4", "calib", "drill"]

var _streak := 0  # ぴったりの連続
var _boss_hits := 0  # 今の敵を始めた時の受けた数


# 対戦を始めた(やり直しを含む)。
func begin(d: Duel) -> void:
	_streak = 0
	boss_start(d)


# 次の敵へ進んだ。ぴったりの連続は続く。
func boss_start(d: Duel) -> void:
	_boss_hits = d.hits


# 出来事 1 つ。counts は保存の数(ここで足す)。
func on_event(e: Dictionary, d: Duel, counts: Dictionary) -> Array:
	var got: Array = []
	match e["type"]:
		"parry":
			got.append("first_parry")
			if e["just"]:
				got.append("first_just")
				_streak += 1
				if _streak >= B.ACH_JUST_STREAK:
					got.append("just_streak")
			else:
				_streak = 0
			if d.mode == Duel.Mode.DRILL:
				counts["drill_parries"] = int(counts.get("drill_parries", 0)) + 1
				if int(counts["drill_parries"]) >= B.ACH_DRILL_PARRIES:
					got.append("drill")
		"parry_whiff", "parry_red", "hurt":
			_streak = 0
		"dodge_avoid":
			if e["attack"]["kind"] == "red":
				counts["red_dodges"] = int(counts.get("red_dodges", 0)) + 1
				if int(counts["red_dodges"]) >= B.ACH_RED_DODGES:
					got.append("dodge_red")
		"counter":
			got.append("first_counter")
		"boss_down":
			if d.hits == _boss_hits:
				got.append("unhurt_boss")
			if d.mode == Duel.Mode.ENDLESS:
				if d.kills >= B.BOSS_COUNT * 2:
					got.append("endless_lap2")
				if d.kills >= B.BOSS_COUNT * 4:
					got.append("endless_lap4")
	return got


# 3 連戦(いつも・今日)を終えた。
static func on_result(r: Dictionary) -> Array:
	var got: Array = []
	var mode := int(r["mode"])
	if not r["won"] or (mode != Duel.Mode.FIXED and mode != Duel.Mode.DAILY):
		return got
	got.append("win_fixed" if mode == Duel.Mode.FIXED else "win_daily")
	if int(r["hits"]) == 0:
		got.append("unhurt_run")
	if int(r["retries"]) == 0:
		got.append("no_retry")
	return got
