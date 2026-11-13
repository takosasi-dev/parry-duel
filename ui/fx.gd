# 演出(仕様書 §9.15): 火花・輪・はね返る頭・通り抜ける頭・バツ・斬撃・割れる敵・縁の赤・字・揺れ。
# 出来事を受けたフレームに始め、実時間で進む。形だけで描く(光る物は加算の層に描く)。判定には関わらない。
extends Node2D

const Kit := preload("res://ui/kit.gd")

var shake_enabled := true
var reduce_flash := false

var _items: Array = []
var _shake_amp := 0.0
var _shake_left := 0.0
var _shake_life := 0.001
var _glow: Node2D


func _ready() -> void:
	_glow = Node2D.new()
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow.material = m
	add_child(_glow)
	_glow.draw.connect(_draw_glow)


func clear() -> void:
	_items.clear()
	_shake_left = 0.0


func advance(delta: float) -> void:
	for e: Dictionary in _items:
		e["t"] += delta
	_items = _items.filter(func(e: Dictionary) -> bool: return e["t"] < e["life"])
	_shake_left = maxf(_shake_left - delta, 0.0)
	queue_redraw()
	_glow.queue_redraw()


# 今の揺れのずれ(px)。設定で切っていれば 0。
func shake_offset() -> Vector2:
	if not shake_enabled or _shake_left <= 0.0:
		return Vector2.ZERO
	var k := _shake_amp * (_shake_left / _shake_life)
	return Vector2(randf_range(-k, k), randf_range(-k, k))


func shake(px: float, ms: float) -> void:
	if px * (ms / 1000.0) >= _shake_amp * _shake_left:
		_shake_amp = px
		_shake_left = ms / 1000.0
		_shake_life = ms / 1000.0


func _add(kind: String, life_ms: float, extra: Dictionary) -> void:
	extra["kind"] = kind
	extra["t"] = 0.0
	extra["life"] = life_ms / 1000.0
	_items.append(extra)


# 当たり点から放射の短い線。
func sparks(pos: Vector2, count: int, life_ms: float, color: Color, reach: float, up_bias: float = 0.35) -> void:
	var rays: Array = []
	for i in count:
		var ang := TAU * (i + randf_range(-0.3, 0.3)) / count
		var dir := Vector2.from_angle(ang)
		dir.y -= up_bias
		rays.append([dir.normalized(), reach * randf_range(0.65, 1.15), randf_range(0.5, 1.0)])
	_add("sparks", life_ms, {"pos": pos, "rays": rays, "color": color})


func ring(pos: Vector2, r0: float, r1: float, life_ms: float, color: Color, width: float = 4.0) -> void:
	_add("ring", life_ms, {"pos": pos, "r0": r0, "r1": r1, "color": color, "width": width})


func flash(pos: Vector2, radius: float, life_ms: float, color: Color, alpha: float) -> void:
	_add("flash", life_ms, {"pos": pos, "r": radius, "color": color, "alpha": alpha})


func popup(pos: Vector2, s: String, size: int, color: Color, life_ms: float, rise: float = 36.0) -> void:
	_add("popup", life_ms, {"pos": pos, "text": s, "size": size, "color": color, "rise": rise})


# 弾いた瞬間、線の上を走る横の光。
func streak(pos: Vector2, life_ms: float = 120.0) -> void:
	_add("streak", life_ms, {"pos": pos})


# 弾かれた頭が、当たり点から起点へはね返る。
func bounce_head(from: Vector2, to: Vector2, kind: String, life_ms: float = 200.0) -> void:
	_add("bounce", life_ms, {"from": from, "to": to, "head": kind})


# 避けられた頭が、線を通り抜けて消える。
func pass_head(from: Vector2, dir: Vector2, kind: String, life_ms: float = 150.0) -> void:
	_add("pass", life_ms, {"from": from, "dir": dir, "head": kind})


func fade_head(pos: Vector2, kind: String, life_ms: float = 140.0) -> void:
	_add("fade", life_ms, {"pos": pos, "head": kind})


# 赤を弾こうとした時の、赤いバツ。
func cross(pos: Vector2, life_ms: float = 200.0) -> void:
	_add("cross", life_ms, {"pos": pos})


# 反撃の斜めの線。hold_ms の間は細いまま止まり(止めの間)、その後に太く走って消える。
func slash(center: Vector2, hold_ms: float, life_ms: float = 260.0) -> void:
	_add("slash", hold_ms + life_ms, {"pos": center, "hold": hold_ms / 1000.0})


# 画面の縁が赤くなる(当たった時)。
func edge_red(life_ms: float = 150.0) -> void:
	_add("edge", life_ms, {})


# 画面全体が暗くなる(負けた時)。消えずに残る。
func darken(life_ms: float = 400.0) -> void:
	_add("dark", 99999.0 * 1000.0, {"fade": life_ms / 1000.0})


# 敵が 3 つに割れて落ちる。pieces は、敵の中心からの頂点の配列 3 つ。
func shatter(center: Vector2, pieces: Array, color: Color, life_ms: float = 600.0) -> void:
	for i in pieces.size():
		var pts: PackedVector2Array = pieces[i]
		var mid := Vector2.ZERO
		for p: Vector2 in pts:
			mid += p / pts.size()
		_add("piece", life_ms, {"pos": center, "pts": pts, "mid": mid, "color": color,
			"vel": mid.normalized() * randf_range(150.0, 240.0) + Vector2(0, -160), "spin": randf_range(-2.4, 2.4)})


func _draw() -> void:
	for e: Dictionary in _items:
		var k: float = e["t"] / e["life"]
		match e["kind"]:
			"popup":
				var a := 1.0 if k < 0.6 else 1.0 - (k - 0.6) / 0.4
				var up := 1.0 - (1.0 - k) * (1.0 - k)
				var pos: Vector2 = e["pos"] + Vector2(0, -e["rise"] * up)
				Kit.text(self, pos + Vector2(0, 3), e["text"], e["size"], Color(Kit.C_BG, 0.8 * a), 900)
				Kit.text(self, pos, e["text"], e["size"], Color(e["color"], a), 900)
			"bounce":
				var back := 1.0 - (1.0 - k) * (1.0 - k)
				Kit.draw_head(self, (e["from"] as Vector2).lerp(e["to"], back * 0.55), e["head"], 1.0, 1.0 - 0.35 * k, 1.0 - k)
			"pass":
				Kit.draw_head(self, e["from"] + e["dir"] * (150.0 * k), e["head"], 0.7, 1.0, 0.7 * (1.0 - k))
			"fade":
				Kit.draw_head(self, e["pos"], e["head"], 0.5, 1.0 - 0.3 * k, 0.6 * (1.0 - k))
			"cross":
				var c: Vector2 = e["pos"]
				var s := 30.0 + 8.0 * k
				var col := Color(Kit.C_RED, 1.0 - k * k)
				draw_line(c + Vector2(-s, -s), c + Vector2(s, s), col, 7.0, true)
				draw_line(c + Vector2(-s, s), c + Vector2(s, -s), col, 7.0, true)
			"edge":
				_draw_edge(Color(Kit.C_RED, (0.2 if reduce_flash else 0.6) * (1.0 - k)))
			"dark":
				var d: float = minf(e["t"] / e["fade"], 1.0)
				draw_rect(Rect2(-2000, -2000, 4720, 5280), Color(0.02, 0.025, 0.035, 0.72 * d))
			"piece":
				var t: float = e["t"]
				var off: Vector2 = e["pos"] + e["vel"] * t + Vector2(0, 1500.0 * t * t)
				draw_set_transform(off + e["mid"], e["spin"] * t, Vector2.ONE)
				var local := PackedVector2Array()
				for p: Vector2 in e["pts"]:
					local.append(p - e["mid"])
				var fade := 1.0 - k * k * k
				draw_colored_polygon(local, Color((e["color"] as Color).darkened(0.35), fade))
				Kit.outline(self, local, Color((e["color"] as Color).lightened(0.25), fade), 4.0)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_edge(col: Color) -> void:
	var clear := Color(col, 0.0)
	var w := 720.0
	var h := 1280.0
	var d := 150.0
	var quads := [
		[Vector2(0, 0), Vector2(w, 0), Vector2(w, d), Vector2(0, d)],
		[Vector2(0, h), Vector2(w, h), Vector2(w, h - d), Vector2(0, h - d)],
		[Vector2(0, 0), Vector2(0, h), Vector2(d, h), Vector2(d, 0)],
		[Vector2(w, 0), Vector2(w, h), Vector2(w - d, h), Vector2(w - d, 0)],
	]
	for q: Array in quads:
		draw_polygon(PackedVector2Array(q), PackedColorArray([col, col, clear, clear]))


func _draw_glow() -> void:
	for e: Dictionary in _items:
		var k: float = e["t"] / e["life"]
		match e["kind"]:
			"sparks":
				var pos: Vector2 = e["pos"]
				var out := 1.0 - (1.0 - k) * (1.0 - k)
				for ray: Array in e["rays"]:
					var dir: Vector2 = ray[0]
					var reach: float = ray[1]
					var far := reach * out
					var near := far - reach * 0.45 * (1.0 - k * 0.5)
					_glow.draw_line(pos + dir * maxf(near, 6.0), pos + dir * (far + 8.0), Color(e["color"], (1.0 - k) * float(ray[2])), 3.0 + 2.0 * (1.0 - k), true)
			"ring":
				var r: float = lerpf(e["r0"], e["r1"], 1.0 - (1.0 - k) * (1.0 - k))
				_glow.draw_arc(e["pos"], r, 0.0, TAU, 56, Color(e["color"], 1.0 - k), e["width"] * (1.0 - 0.6 * k), true)
			"streak":
				var sp: Vector2 = e["pos"]
				var half := 50.0 + 130.0 * (1.0 - (1.0 - k) * (1.0 - k))
				_glow.draw_line(sp - Vector2(half, 0), sp + Vector2(half, 0), Color(1, 1, 1, 0.9 * (1.0 - k)), 6.0 * (1.0 - k) + 1.0, true)
			"flash":
				Kit.glow(_glow, e["pos"], e["r"] * (0.7 + 0.5 * k), e["color"], e["alpha"] * (1.0 - k) * (0.35 if reduce_flash else 1.0))
			"slash":
				var c: Vector2 = e["pos"]
				var dir2 := Vector2(0.86, -0.5)
				var hold: float = e["hold"]
				if e["t"] < hold:
					_glow.draw_line(c - dir2 * 250.0, c + dir2 * 250.0, Color(1, 1, 1, 0.95), 3.0, true)
				else:
					var s: float = (e["t"] - hold) / (e["life"] - hold)
					var half := 250.0 + 260.0 * (1.0 - (1.0 - s) * (1.0 - s))
					_glow.draw_line(c - dir2 * half, c + dir2 * half, Color(Kit.C_SPARK, 0.5 * (1.0 - s)), 34.0 * (1.0 - s) + 2.0, true)
					_glow.draw_line(c - dir2 * half, c + dir2 * half, Color(1, 1, 1, 1.0 - s), 12.0 * (1.0 - s) + 1.0, true)
