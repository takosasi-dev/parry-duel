# 攻撃 1 つの当たる tick と、頭の進み具合・位置(仕様書 §9.4)。頭の位置を出す式はここにしか無い(INV-5)。
# float は描画専用。判定は contact_tick の整数だけを使う(INV-4)。頭は等速でまっすぐ動く(INV-6)。
extends RefCounted

const B := preload("res://core/balance.gd")


static func duration(a: Dictionary) -> int:
	return int(a["windup"]) + int(a["travel1"]) + int(a["hold"]) + int(a["travel2"])


# start は攻撃の始まる tick(型の始まった tick + at)。
static func contact_tick(a: Dictionary, start: int) -> int:
	return start + duration(a)


# 進み具合。phase は windup / move / hold / contact、p は その区間の 0〜1、
# along は 起点(0)から当たり点(1)までの道のりの割合。
static func progress(a: Dictionary, start: int, tick: int) -> Dictionary:
	var windup: int = a["windup"]
	var travel1: int = a["travel1"]
	var hold: int = a["hold"]
	var travel2: int = a["travel2"]
	var e := tick - start
	if e < windup:
		return {"phase": "windup", "p": float(maxi(e, 0)) / float(windup), "along": 0.0}
	e -= windup
	if hold == 0:
		if e < travel1:
			var p := float(e) / float(travel1)
			return {"phase": "move", "p": p, "along": p}
		return {"phase": "contact", "p": 1.0, "along": 1.0}
	if e < travel1:
		var p1 := float(e) / float(travel1)
		return {"phase": "move", "p": p1, "along": p1 * 0.5}
	e -= travel1
	if e < hold:
		return {"phase": "hold", "p": float(e) / float(hold), "along": 0.5}
	e -= hold
	if e < travel2:
		var p2 := float(e) / float(travel2)
		return {"phase": "move", "p": p2, "along": 0.5 + p2 * 0.5}
	return {"phase": "contact", "p": 1.0, "along": 1.0}


# 予兆で頭を引く向き。起点から敵の中心の向き(§9.4)。ただし上の腕(T)は敵の中心が起点より下にあり、
# そのままだと弾く線の向きへ進んでしまう(引いた後に戻る動きになる)ので、縦を返して線から離れる向きにする。
static func pull_dir(arm: String) -> Vector2:
	var dir: Vector2 = (B.ORIGIN[arm] as Vector2).direction_to(B.BOSS_POS)
	if dir.y > 0.0:
		dir.y = -dir.y
	return dir


# 頭の位置(論理の画面の px)。予兆の間は、起点から p × 20 px 引く。
static func head_pos(a: Dictionary, start: int, tick: int) -> Vector2:
	var origin: Vector2 = B.ORIGIN[a["arm"]]
	var pr := progress(a, start, tick)
	if pr["phase"] == "windup":
		return origin + pull_dir(a["arm"]) * (B.WINDUP_PULL * float(pr["p"]))
	return origin.lerp(B.CONTACT[a["arm"]], float(pr["along"]))
