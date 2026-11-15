# デバッグ用の窓口(URL に ?debug=1、または起動の引数に --debug を付けた時だけ動く)。遊び方は変えない、読み取り専用。
# 入力から描画までの時間と 1 フレームの時間を測り、今の状態を window.pdState(JSON の文字)に出す。自動の確認が読む。
extends Control

const B := preload("res://core/balance.gd")
const Duel := preload("res://core/duel.gd")
const Kit := preload("res://ui/kit.gd")

const MAX_SAMPLES := 400
const MAX_FRAMES := 7200
const STATE_NAMES := ["INTRO", "PATTERN", "GAP", "STAGGER", "RECOVER", "WAIT_NEXT", "DONE"]

var main: Node
var lat_godot: Array = []  # 入力を受けたフレームの頭から、そのフレームを描き終えるまで(ms)
var lat_js: Array = []  # ブラウザのイベントの時刻から、描き終えるまで(ms)。Web だけ
var input_log: Array = []  # 届いた入力イベントの中身(直近 8 個)
var frame_ms: Array = []
const BAND_Y := 140.0  # 計測の帯の上の端
var frame := 0

var press_diffs: Array = []  # タイミング合わせで押したずれ(ms)。何組測っても足していく(仕様書 §8.2 の「押すずれ」用)
var auto := false
var band := true  # 計測の帯を描くか(?band=0 で消す。README の画像を撮る時に使う)
var _auto_done := {}
var _auto_wait := 0.0
var _calib_seen := 0  # 数え終わったタイミング合わせ(同じ組を 2 回足さない)
var _web := false
var _pending := false
var _t_input := 0
var _perf := {}
var _perf_at := 0.0
var _time := 0.0


static func wanted() -> bool:
	if OS.has_feature("web"):
		var q: Variant = JavaScriptBridge.eval("location.search", true)
		return q is String and q.contains("debug=1")
	return OS.get_cmdline_user_args().has("--debug")


# URL の ?go=duel などの値(Web)、または --go=duel(引数)。無ければ ""。
static func go_target() -> String:
	if OS.has_feature("web"):
		var q: Variant = JavaScriptBridge.eval("new URLSearchParams(location.search).get('go') || ''", true)
		return q if q is String else ""
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--go="):
			return a.trim_prefix("--go=")
	return ""


func _ready() -> void:
	_web = OS.has_feature("web")
	if _web:
		var q: Variant = JavaScriptBridge.eval("location.search", true)
		auto = q is String and q.contains("auto=1")
		band = not (q is String and q.contains("band=0"))
	else:
		auto = OS.get_cmdline_user_args().has("--auto")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(B.SCREEN_W, B.SCREEN_H)
	z_index = 100
	RenderingServer.frame_post_draw.connect(_after_draw)
	if _web:
		JavaScriptBridge.eval("""
			window.pdIn = { t: 0, n: 0 };
			for (const name of ['keydown', 'mousedown', 'touchstart'])
				window.addEventListener(name, (e) => { window.pdIn.t = e.timeStamp; window.pdIn.n++; }, true);
			window.pdState = '{}';
		""", true)


func _input(event: InputEvent) -> void:
	var pressed: bool = (event is InputEventKey or event is InputEventMouseButton or event is InputEventScreenTouch) and event.pressed
	if pressed:
		input_log.append(str(event))
		if input_log.size() > 8:
			input_log.pop_front()


# 弾く・避けるの入力を使った時に、画面が呼ぶ。
func mark_input() -> void:
	_pending = true
	_t_input = Time.get_ticks_usec()


func _after_draw() -> void:
	if not _pending:
		return
	_pending = false
	_push(lat_godot, (Time.get_ticks_usec() - _t_input) / 1000.0)
	if _web:
		var v: Variant = JavaScriptBridge.eval("performance.now() - window.pdIn.t", true)
		if v is float or v is int:
			_push(lat_js, float(v))


static func _push(list: Array, v: float) -> void:
	list.append(snappedf(v, 0.01))
	if list.size() > MAX_SAMPLES:
		list.pop_front()


static func stats(list: Array) -> Dictionary:
	if list.is_empty():
		return {"n": 0}
	var s := list.duplicate()
	s.sort()
	@warning_ignore("integer_division")
	return {"n": s.size(), "p50": s[s.size() / 2], "p95": s[mini(int(ceil(s.size() * 0.95)) - 1, s.size() - 1)], "max": s[s.size() - 1]}


# 自動で押す(?auto=1 か --auto)。速さの計測と、窓なしの通し確認に使う。入力は画面と同じ入口(_press)を通す。
func _auto_play() -> void:
	var view: Node = main.view
	if main.screen_name == "interval":
		_auto_wait += get_process_delta_time()
		if _auto_wait >= 2.0:  # 合間の画面が見えるよう、2 秒待ってから進む
			_auto_wait = 0.0
			main.next_boss()
		return
	if view == null or view.duel == null or not view.visible or not view.is_playing():
		return
	var d: Duel = view.duel
	if d.state == Duel.State.STAGGER:
		if d.tick >= d.state_from + 48:  # 「いま!」が見えるよう、少し待ってから反撃する
			view._press(true)
		return
	for a: Dictionary in d.snapshot()["attacks"]:
		if _auto_done.has(a["id"]):
			continue
		var jt: int = a["contact"] + a["offset"]
		if a["kind"] == "white" and d.tick >= jt - 2:
			_auto_done[a["id"]] = true
			view._press(true)
		elif a["kind"] == "red" and d.tick >= jt - 14:
			_auto_done[a["id"]] = true
			view._press(false)


func _process(delta: float) -> void:
	if auto:
		_auto_play()
	frame += 1
	_time += delta
	frame_ms.append(snappedf(delta * 1000.0, 0.01))
	if frame_ms.size() > MAX_FRAMES:
		frame_ms.pop_front()
	if _time - _perf_at >= 1.0:
		_perf_at = _time
		_perf = stats(frame_ms)
	_collect_press_diffs()
	queue_redraw()
	if not _web and frame % 300 == 0:  # 窓なしの通し確認で、進み具合を読むための 1 行
		var st := state()
		var d: Dictionary = st.get("duel", {})
		print("pd frame=%d screen=%s boss=%s phase=%s hp=%s hits=%s parries=%s justs=%s tick=%s over=%s won=%s" % [frame, st["screen"],
			d.get("boss"), d.get("phase"), d.get("player_hp"), d.get("hits"), d.get("parries"), d.get("justs"), d.get("tick"), d.get("over"), d.get("won")])
	if _web:
		JavaScriptBridge.eval("window.pdState=" + JSON.stringify(JSON.stringify(state())), true)


# タイミング合わせが 1 組終わるたびに、最初の 2 回を除いた押すずれを ms で足す。
func _collect_press_diffs() -> void:
	var cv: Node = main.calib_view
	if cv == null or not is_instance_valid(cv) or not cv.calib.done or cv.calib.get_instance_id() == _calib_seen:
		return
	_calib_seen = cv.calib.get_instance_id()
	for k in range(B.CALIB_SKIP, B.CALIB_COUNT):
		if cv.calib.diffs[k] != null:
			press_diffs.append(int(cv.calib.diffs[k]) * 1000.0 / B.TICK_HZ)


# 押すずれの { n, median, sd }(ms)。
func press_stats() -> Dictionary:
	var n := press_diffs.size()
	if n == 0:
		return {"n": 0}
	var sorted := press_diffs.duplicate()
	sorted.sort()
	var mean := 0.0
	for v: float in press_diffs:
		mean += v / n
	var sq := 0.0
	for v: float in press_diffs:
		sq += (v - mean) * (v - mean)
	@warning_ignore("integer_division")
	return {"n": n, "median": snappedf(sorted[n / 2], 0.1), "sd": snappedf(sqrt(sq / maxi(n - 1, 1)), 0.1)}


# 今の状態。自動の確認が読む物で、ゲームはこれを読まない。
func state() -> Dictionary:
	var out := {
		"frame": frame, "screen": main.screen_name, "vp": [get_viewport_rect().size.x, get_viewport_rect().size.y],
		"stage": [main.stage.position.x, main.stage.position.y], "renderer": RenderingServer.get_video_adapter_name(),
		"lat_godot": stats(lat_godot), "lat_js": stats(lat_js), "press": press_stats(), "perf": _perf, "inputs": input_log, "buttons": _buttons(main.stage, {}),
		"sfx": Sfx.get("played") if Sfx.get("played") != null else -1, "pad": main.pad, "save_failed": main.save.write_failed, "ach": main.save.achievements().keys(), "toast": main.toast.current,
		"focus": str(get_viewport().gui_get_focus_owner().name) if get_viewport().gui_get_focus_owner() != null else "",
	}
	var view: Node = main.view
	if view != null and view.duel != null:
		var d: Duel = view.duel
		var attacks: Array = []
		for a: Dictionary in d.snapshot()["attacks"]:
			attacks.append({"id": a["id"], "kind": a["kind"], "arm": a["arm"], "contact": a["contact"], "judged": a["contact"] + a["offset"]})
		out["duel"] = {
			"tick": d.tick, "mode": d.mode, "boss": d.boss, "phase": d.phase, "boss_hp": d.boss_hp, "stagger": d.stagger,
			"state": STATE_NAMES[d.state], "player_hp": d.player_hp, "lock": d.lock, "dodge": d.dodge_ticks, "hurt": d.hurt_ticks,
			"freeze": d.freeze_ticks, "hits": d.hits, "justs": d.justs, "parries": d.parries, "retries": d.retries,
			"over": d.over, "won": d.won, "offset": d.offset, "teaching": not d.teach_done[d.boss - 1],
			"paused": view.paused, "resume_left": view.resume_left, "attacks": attacks, "events": view.event_log,
			"steps": view.steps_last_frame, "speed": d.speed, "easy": d.easy, "drill_id": d.drill_id, "diffs": d.diffs.size(), "kills": d.kills,
		}
	var calib_view: Node = main.calib_view
	if calib_view != null and is_instance_valid(calib_view):
		var c: Dictionary = calib_view.calib.snapshot()
		out["calib"] = {"tick": c["tick"], "count": c["count"], "done": c["done"], "last_diff": c["last_diff"],
			"diffs": calib_view.calib.diffs, "contacts": c["attacks"].map(func(a: Dictionary) -> int: return a["contact"])}
	return out


# 見えているボタンの名前と、中心(ビューポートの座標)。
func _buttons(node: Node, out: Dictionary) -> Dictionary:
	for child: Node in node.get_children():
		if child is CanvasItem and not child.visible:
			continue
		if child is BaseButton and not child.disabled:
			var r: Rect2 = child.get_global_rect()
			out[child.name] = [snappedf(r.get_center().x, 0.1), snappedf(r.get_center().y, 0.1)]
		_buttons(child, out)
	return out


func _draw() -> void:
	var g := stats(lat_godot)
	var j := stats(lat_js)
	var lines := ["debug  frame %.1f ms (p95 %s)" % [frame_ms[frame_ms.size() - 1] if not frame_ms.is_empty() else 0.0, _perf.get("p95", "-")]]
	if g["n"] > 0:
		lines.append("input>draw godot  n=%d  p50 %.1f  p95 %.1f ms" % [g["n"], g["p50"], g["p95"]])
	if j["n"] > 0:
		lines.append("input>draw event  n=%d  p50 %.1f  p95 %.1f ms" % [j["n"], j["p50"], j["p95"]])
	var ps := press_stats()
	if ps["n"] > 0:
		lines.append("press diff (calib)  n=%d  median %+.0f ms  sd %.0f ms" % [ps["n"], ps["median"], ps["sd"]])
	if not input_log.is_empty():
		lines.append(input_log[input_log.size() - 1].left(96))
	if not band:
		return
	# 上の HUD のすぐ下に置く(下には操作の案内がある)
	draw_rect(Rect2(0, BAND_Y, 720, 22 * lines.size() + 8), Color(0, 0, 0, 0.6))
	for i in lines.size():
		Kit.text(self, Vector2(8, BAND_Y + 22 * i + 20), lines[i], 15, Kit.C_SPARK, 500, HORIZONTAL_ALIGNMENT_LEFT, 710.0)
