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
	"settings": "res://ui/settings.gd", "pause": "res://ui/pause.gd", "practice": "res://ui/practice.gd",
}

var save: SaveStore
var data_ok := true  # 型のデータが読めて、形の検査を通ったか(E-17)
var stage: Control  # 論理の画面 720×1280。ウィンドウの中央に置く
var view: DuelView
var calib_view: CalibView = null
var debug: Debug = null
var screen_name := ""
var run := {}  # 今の回: { mode, boss(練習で選んだ敵), y, m, d, day, date, seed, opts }
var drill_slow := false  # 型の練習の「ゆっくり」(この回の間だけ覚える)
var pad := false  # ゲームパッドで操作している間は真。ボタンを選べる(focus)ようにする

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
	if (event is InputEventKey or event is InputEventMouseButton or event is InputEventScreenTouch or event is InputEventJoypadButton) and event.pressed:
		Sfx.unlock()
	if event is InputEventJoypadButton and event.pressed:
		_pad_input(event)
	elif (event is InputEventMouseButton or event is InputEventScreenTouch or event is InputEventKey) and event.pressed and pad:
		_set_pad(false)


# ゲームパッド(v0.2.0)。メニューでは十字キー・左スティックでボタンを選び(Godot の ui_up など)、A で押す。
# Godot 4.7 の ui_accept にパッドの A は入っていないので、A はここで選んだボタンを押す。
# B は「戻る」、一時停止の Start は「続ける」。どちらも Esc と同じに扱う(一番上の画面の Esc の受け口を通す)。
func _pad_input(event: InputEventJoypadButton) -> void:
	var was := pad
	pad = true
	if _playing():
		return  # 対戦の弾く・避ける・一時停止は duel_view が受ける
	if not was or get_viewport().gui_get_focus_owner() == null:
		# パッドに替えた時と、画面が替わった後の最初の押しは、ボタンを選ぶだけ(いきなり押さない)
		_apply_focus()
		get_viewport().set_input_as_handled()
		return
	if event.button_index == JOY_BUTTON_A:
		var f := get_viewport().gui_get_focus_owner()
		if f is BaseButton and not f.disabled:
			get_viewport().set_input_as_handled()
			f.pressed.emit()
		return
	var back: bool = event.button_index == JOY_BUTTON_B or (event.button_index == JOY_BUTTON_START and screen_name == "pause")
	var top := _top()
	if back and top != null and top.has_method("_input"):
		get_viewport().set_input_as_handled()
		var esc := InputEventKey.new()
		esc.pressed = true
		esc.keycode = KEY_ESCAPE
		esc.physical_keycode = KEY_ESCAPE
		top._input(esc)  # 一番上の画面の Esc の受け口へ


# 対戦を遊んでいる最中か(負けた後の 2 つのボタンが出ている時は違う)。
func _playing() -> bool:
	return screen_name == "duel" and not view.lost()


func _set_pad(on: bool) -> void:
	pad = on
	_apply_focus()


# パッドの間は、見えている画面のボタンを選べるようにし、何も選ばれていなければ最初のボタンを選ぶ。
# マウス・タッチ・キーに戻ったら選べないようにする(クリックの後に選んだ印が残らないように)。
# 対戦の最中は選ばない(A で弾いた時に、選んだ一時停止ボタンまで押されないように)。
func _apply_focus() -> void:
	var allow := pad and not _playing()
	var first: Button = null
	for b: Button in _buttons(stage, []):
		b.focus_mode = Control.FOCUS_ALL if allow else Control.FOCUS_NONE
		if first == null and b.is_visible_in_tree() and not b.disabled:
			first = b
	if not allow:
		get_viewport().gui_release_focus()
	elif first != null and get_viewport().gui_get_focus_owner() == null:
		first.grab_focus()


# 一番上の画面のボタン(下に重なった画面のボタンは選ばない)。
func _buttons(node: Node, out: Array) -> Array:
	var top := _top()
	if top == null:
		top = view if view.visible else node
	_collect_buttons(top, out)
	return out


# 一番上に開いている画面(タイミング合わせ・設定・一時停止・タイトルなど)。対戦だけの時は null。
func _top() -> Node:
	for c: Variant in [calib_view, _settings, _pause, _screen]:
		if c != null and is_instance_valid(c) and not c.is_queued_for_deletion():
			return c
	return null


static func _collect_buttons(node: Node, out: Array) -> void:
	for c: Node in node.get_children():
		if c is Button:
			out.append(c)
		_collect_buttons(c, out)


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
	get_viewport().gui_release_focus()  # 消える画面のボタンを選んだままにしない
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
	if pad:
		_apply_focus.call_deferred()  # 部品は _ready で作られるので、その後に
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
	run["opts"] = play_opts()
	_start_duel(Duel.new(run["seed"], mode, boss, null, null, run["opts"]))


# 設定から、対戦の遊び方の違い(やさしい設定)を作る。drill は型の練習の型の id。
func play_opts(drill: String = "") -> Dictionary:
	var easy: bool = save.settings()["easy"] == true
	var opts := {"easy": easy}
	if easy:
		opts.merge({"speed": B.EASY_SPEED, "window": B.EASY_PARRY_WINDOW, "just": B.EASY_JUST_WINDOW})
	if drill != "":
		opts["drill"] = drill
		if drill_slow:
			opts["speed"] = B.SLOW_SPEED
	return opts


# 型の練習(v0.2.0)。1 つの型を繰り返す。記録に残さない。
func start_drill(pattern_id: String) -> void:
	if not data_ok:
		return
	run = today()
	run["mode"] = Duel.Mode.DRILL
	run["boss"] = 1
	run["seed"] = B.FIXED_SEED
	run["opts"] = play_opts(pattern_id)
	_start_duel(Duel.new(run["seed"], Duel.Mode.DRILL, 1, null, null, run["opts"]))


# 型の練習の、型を選ぶ画面。
func open_practice() -> void:
	_clear_screens()
	view.visible = false
	view.duel = null
	screen_name = "practice"
	_screen = _open("practice", {})


func _start_duel(d: Duel) -> void:
	_clear_screens()
	screen_name = "duel"
	view.visible = true
	view.start(d, save.settings())
	if (d.mode == Duel.Mode.FIXED or d.mode == Duel.Mode.DAILY) and _records():
		save.reach(d.boss)


# 記録と着いた敵を保存してよい回か。デバッグ用の自動の相手(?auto=1)が押した回は残さない。
func _records() -> bool:
	return debug == null or not debug.auto


# 負けた後の「この敵からやり直す」(E-13)。
func retry() -> void:
	var old: Duel = view.duel
	_start_duel(Duel.new(old.seed_value, old.mode, old.boss, old.retry_carry(), null, run.get("opts", {})))


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
	if _pause == null and screen_name != "title":
		go_title()  # タイトルを作り直す(やさしい設定の印と記録の行を、変えた設定に合わせる)
		return
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
	elif target == "practice":
		open_practice()
	elif target.begins_with("drill_"):  # 例 go=drill_stone_2_a
		start_drill(target.trim_prefix("drill_"))
	elif target.begins_with("duel") and data_ok:
		var boss := maxi(int(target.trim_prefix("duel")), 1)
		run = today()
		run.merge({"mode": Duel.Mode.PRACTICE if boss > 1 else Duel.Mode.FIXED, "boss": boss, "seed": B.FIXED_SEED})
		_start_duel(Duel.new(B.FIXED_SEED, run["mode"], mini(boss, B.BOSS_COUNT)))
