# 自動で押す相手(仕様書 AC-19〜AC-22)。白は T' ちょうどに弾き、赤は T' − 10 に避け、よろけたらすぐ弾く。
# shift で押す tick をずらせる。押した記録(log)を残せるので、同じ入力のくり返しにも使う。
extends RefCounted

const Duel := preload("res://core/duel.gd")

var shift := 0  # 白を弾く tick のずれ
var dodge_lead := 10  # 赤を避ける tick(T' の何 tick 前か)
var parry_whites := true
var dodge_reds := true
var counter := true
var auto_next := true
var only_teach := false  # 教える型だけ成功して、後は押さない
var record: Array = []  # [何回目の step か, "p" か "d" か "n"]
var steps := 0
var patterns: Array = []  # 出た型の記録 [敵, 段階, id, 入れ替えたか]
var counts := {}  # 出来事の type ごとの数(parry_plain は ぴったり でない弾き)


# step() の前に呼ぶ。
func act(d: Duel) -> void:
	if d.state == Duel.State.WAIT_NEXT:
		if auto_next:
			d.next_boss()
			record.append([steps, "n"])
		return
	if only_teach and d.teach_done[d.boss - 1]:
		return
	if d.state == Duel.State.STAGGER:
		if counter:
			_press(d, "p")
		return
	for a: Dictionary in d.snapshot()["attacks"]:
		var jt: int = a["contact"] + a["offset"]
		if a["kind"] == "white" and parry_whites and d.tick == jt + shift:
			_press(d, "p")
		elif a["kind"] == "red" and dodge_reds and d.tick == jt - dodge_lead + shift:
			_press(d, "d")


func _press(d: Duel, what: String) -> void:
	if what == "p":
		d.press_parry()
	else:
		d.press_dodge()
	record.append([steps, what])


# 終わるか max_steps に届くまで回す。終わったら true。
func run(d: Duel, max_steps: int) -> bool:
	while not d.over and steps < max_steps:
		act(d)
		d.step()
		steps += 1
		for e: Dictionary in d.events():
			counts[e["type"]] = int(counts.get(e["type"], 0)) + 1
			if e["type"] == "pattern_start":
				patterns.append([d.boss, d.phase, e["id"], e["swapped"]])
			elif e["type"] == "parry" and not e["just"]:
				counts["parry_plain"] = int(counts.get("parry_plain", 0)) + 1
	return d.over


# 記録した入力を、新しい Duel にそのまま流す。
static func replay(d: Duel, record: Array, total_steps: int) -> void:
	var i := 0
	for s in total_steps:
		while i < record.size() and record[i][0] == s:
			match record[i][1]:
				"p": d.press_parry()
				"d": d.press_dodge()
				"n": d.next_boss()
			i += 1
		d.step()
