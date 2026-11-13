# 画面の切り替え(タイトル・対戦・合間・結果・設定・タイミング合わせ・一時停止)。
# 保存と設定を持ち、各画面に渡す。ゲームの決まりは持たない(core に聞く)。
extends Node

const B := preload("res://core/balance.gd")
const Duel := preload("res://core/duel.gd")
const DayIndex := preload("res://core/day_index.gd")
const PatternStore := preload("res://core/pattern_store.gd")
const ShareText := preload("res://core/share_text.gd")
const SaveStore := preload("res://save/save_store.gd")
const Kit := preload("res://ui/kit.gd")
const DuelView := preload("res://ui/duel_view.gd")
const CalibView := preload("res://ui/calib_view.gd")
const Debug := preload("res://ui/debug.gd")

const SCREENS := {
	"title": "res://ui/title.gd", "interval": "res://ui/interval.gd", "result": "res://ui/result.gd",
	"settings": "res://ui/settings.gd", "pause": "res://ui/pause.gd",
}

var save: SaveStore
var data_ok := true  # 型のデータが読めて、形の検査を通ったか(E-17)
var stage: Control  # 論理の画面 720×1280。ウィンドウの中央に置く
var view: DuelView
var calib_view: CalibView = null
var debug: Debug = null
var screen_name := ""
var run := {}  # 今の回: { mode, boss(練習で選んだ敵), y, m, d, day, date }

var _back: Node2D
var _screen: Control = null  # タイトル・合間・結果のどれか
var _pause: Control = null
var _settings: Control = null
var _visibility_cb: Variant = null


func _ready() -> void:
	save = SaveStore.new()
	data_ok = PatternStore.shared()["ok"]
	_back = Node2D.new()
	_back.draw.connect(_draw_back)
	add_child(_back)
	stage = Control.new()
	stage.size = Vector2(B.SCREEN_W, B.SCREEN_H)
	stage.clip_contents = true
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stage)
	view = DuelView.new()
	view.visible = false
	view.boss_beaten.connect(_on_boss_beaten)
	view.finished.connect(_on_finished)
	view.retry_requested.connect(retry)
	view.title_requested.connect(go_title)
	view.pause_requested.connect(pause)
	stage.add_child(view)
	get_viewport().size_changed.connect(_layout)
	_layout()
	settings_changed()
	if Debug.wanted():
		debug = Debug.new()
		debug.main = self
		stage.add_child(debug)
		view.debug = debug
	_watch_visibility()
	go_title()
	if debug != null:
		_debug_jump(Debug.go_target())


func _layout() -> void:
	var vp := get_viewport().get_visible_rect().size
	stage.position = ((vp - stage.size) / 2.0).floor()
	_back.queue_redraw()


# 余りは背景色で埋める(§9.1)。画面の柱だけ、ほんの少し明るくして場所を見せる。
func _draw_back() -> void:
	var vp := get_viewport().get_visible_rect().size
	_back.draw_rect(Rect2(Vector2.ZERO, vp), Kit.C_BG)
	var r := Rect2(stage.position, stage.size)
	var top := Color(Kit.C_BG_HI, 0.0)
	var mid := Color(Kit.C_BG_HI, 0.85)
	_back.draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), Vector2(r.end.x, r.position.y + 640), Vector2(r.position.x, r.position.y + 640)]),
		PackedColorArray([top, top, mid, mid]))
	_back.draw_polygon(PackedVector2Array([Vector2(r.position.x, r.position.y + 640), Vector2(r.end.x, r.position.y + 640), r.end, Vector2(r.position.x, r.end.y)]),
		PackedColorArray([mid, mid, top, top]))


func _input(event: InputEvent) -> void:
	# 音は、最初の操作の後から鳴らす(FR-29)
	if (event is InputEventKey or event is InputEventMouseButton or event is InputEventScreenTouch) and event.pressed:
		Sfx.unlock()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		_auto_pause()


# タブが裏に回ったら一時停止にする(E-10)。Web では通知が来ないことがあるので、ブラウザにも聞く。
func _watch_visibility() -> void:
	if not OS.has_feature("web"):
		return
	_visibility_cb = JavaScriptBridge.create_callback(func(_args: Array) -> void: _auto_pause())
	var doc: Variant = JavaScriptBridge.get_interface("document")
	if doc != null:
		doc.addEventListener("visibilitychange", _visibility_cb)


func _auto_pause() -> void:
	if view != null and view.visible and view.is_playing() and not view.paused:
		pause()


# 端末の今日の日付。{ y, m, d, day, date }
func today() -> Dictionary:
	var t := Time.get_date_dict_from_system()
	var y := int(t["year"])
	var m := int(t["month"])
	var d := int(t["day"])
	return {"y": y, "m": m, "d": d, "day": DayIndex.day_index(y, m, d), "date": DayIndex.date_string(y, m, d)}


# 設定を変えた後に呼ぶ。音量・揺れ・点滅・判定のずれを、動いている物に入れる。
func settings_changed() -> void:
	var st := save.settings()
	Sfx.set_volume(st["volume"])
	if view != null:
		view.apply_settings(st)


func _clear_screens() -> void:
	for c: Variant in [_screen, _pause, _settings, calib_view]:
		if c != null and is_instance_valid(c):
			c.queue_free()
	_screen = null
	_pause = null
	_settings = null
	calib_view = null


func _open(key: String, info: Dictionary) -> Control:
	if not ResourceLoader.exists(SCREENS[key]):
		return null
	var c: Control = load(SCREENS[key]).new()
	c.size = stage.size
	c.setup(self, info)
	stage.add_child(c)
	if debug != null:
		stage.move_child(debug, -1)
	return c


func go_title() -> void:
	_clear_screens()
	view.visible = false
	view.duel = null
	screen_name = "title"
	_screen = _open("title", {"load_failed": save.load_failed, "data_ok": data_ok})


# いつもの3連戦(Duel.Mode.FIXED)か、今日の3連戦(Duel.Mode.DAILY)を敵 1 から始める。
func start_run(mode: int) -> void:
	_begin(mode, 1)


# 練習(FR-30)。着いたことのある敵を 1 体。記録に残さない。
func start_practice(boss: int) -> void:
	_begin(Duel.Mode.PRACTICE, clampi(boss, 1, save.reached_boss()))


func _begin(mode: int, boss: int) -> void:
	if not data_ok:
		return
	run = today()
	run["mode"] = mode
	run["boss"] = boss
	run["seed"] = DayIndex.day_seed(run["day"]) if mode == Duel.Mode.DAILY else B.FIXED_SEED
	_start_duel(Duel.new(run["seed"], mode, boss))


func _start_duel(d: Duel) -> void:
	_clear_screens()
	screen_name = "duel"
	view.visible = true
	view.start(d, save.settings())
	if d.mode != Duel.Mode.PRACTICE and _records():
		save.reach(d.boss)


# 記録と着いた敵を保存してよい回か。デバッグ用の自動の相手(?auto=1)が押した回は残さない。
func _records() -> bool:
	return debug == null or not debug.auto


# 負けた後の「この敵からやり直す」(E-13)。
func retry() -> void:
	var old: Duel = view.duel
	_start_duel(Duel.new(old.seed_value, old.mode, old.boss, old.retry_carry()))


func _on_boss_beaten() -> void:
	var r: Dictionary = view.duel.result()
	view.visible = false
	screen_name = "interval"
	_screen = _open("interval", {"boss": r["boss"], "hits": r["hits"], "ticks": r["ticks"], "justs": r["justs"]})


# 合間の「次の敵へ」。
func next_boss() -> void:
	_clear_screens()
	screen_name = "duel"
	view.visible = true
	view.next_boss()
	if _records():
		save.reach(view.duel.boss)


func _on_finished() -> void:
	var r: Dictionary = view.duel.result()
	var practice: bool = r["mode"] == Duel.Mode.PRACTICE
	var info := {"result": r, "mode": r["mode"], "practice": practice, "date": run["date"],
		"record": {"prev_best": null, "new_best": false, "first_today": false, "saved": true}, "share_text": ""}
	if not practice and r["won"] and _records():
		info["record"] = save.record_win(r["mode"], run["day"], r)
		info["share_text"] = ShareText.build(run["date"], r["mode"], info["record"]["first_today"], r)
	view.visible = false
	screen_name = "result"
	_screen = _open("result", info)


# 結果の「もう1回」。同じ入口をもう一度。
func again() -> void:
	if run["mode"] == Duel.Mode.PRACTICE:
		start_practice(run["boss"])
	else:
		start_run(run["mode"])


func pause() -> void:
	if view.paused or not view.visible:
		return
	view.pause()
	screen_name = "pause"
	_pause = _open("pause", {})


# 一時停止の「続ける」。1 秒待ってから進む(E-9)。
func resume() -> void:
	if not view.paused:
		return
	if _pause != null:
		_pause.queue_free()
		_pause = null
	screen_name = "duel"
	view.resume()


# 設定を開く(タイトルからでも、一時停止からでも)。「戻る」で来た画面に戻る。
func open_settings() -> void:
	if _settings != null:
		return
	screen_name = "settings"
	_settings = _open("settings", {})


func close_settings() -> void:
	if _settings != null:
		_settings.queue_free()
		_settings = null
	screen_name = "pause" if _pause != null else "title"


func open_calib() -> void:
	if calib_view != null:
		return
	screen_name = "calib"
	calib_view = CalibView.new()
	calib_view.setup(self, {})
	stage.add_child(calib_view)
	if debug != null:
		stage.move_child(debug, -1)


func close_calib() -> void:
	if calib_view != null:
		calib_view.queue_free()
		calib_view = null
	screen_name = "settings" if _settings != null else ("pause" if _pause != null else "title")


# 自動の確認用: ?debug=1&go=duel / duel2 / duel3 / calib で、その画面から始める。
func _debug_jump(target: String) -> void:
	if target == "calib":
		open_calib()
	elif target.begins_with("duel") and data_ok:
		var boss := maxi(int(target.trim_prefix("duel")), 1)
		run = today()
		run.merge({"mode": Duel.Mode.PRACTICE if boss > 1 else Duel.Mode.FIXED, "boss": boss, "seed": B.FIXED_SEED})
		_start_duel(Duel.new(B.FIXED_SEED, run["mode"], mini(boss, B.BOSS_COUNT)))
