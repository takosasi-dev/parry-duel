# 保存の読み書き(仕様書 §9.11・E-12・E-15・E-16)。記録・着いた敵・設定を持つ。
# 読めない・壊れている時は既定値で始め、書けなくてもエラーで止めない。外から来た値は型を見てから使う。
# 置き場: Web はブラウザの localStorage(このゲームだけのキー)、それ以外は user://save.json。
# Web で user:// を使わないのは、user:// の実体(IndexedDB の /userfs)が同じサイトの Godot のゲーム全部で 1 つだからで、
# どれかのタブが書くと、そのタブが起動した時の写しで全体を書き戻す(別のタブ・別のゲームの新しい保存が古い物に戻る・消える)。
# localStorage はタブの間で同じ物を読み書きするので、書く前の読み直し(_merge_from_disk)が別のタブの記録を拾える。
#
# 保存は 2 つ。本の保存(save)は v0.1.2 と同じ形のまま変えない。v0.1.2 のタブは知らない項目を消して書くので、
# v0.2.0 から増えた物(やさしい設定の記録・新しい設定)は、別の保存(ext)に置く。どちらも、知らない項目は消さずに書き戻す。
extends RefCounted

const B := preload("res://core/balance.gd")
const Rank := preload("res://core/rank.gd")
const Duel := preload("res://core/duel.gd")

const PATH := "user://save.json"
const VERSION := 1  # 上げない(上げると v0.1.2 が記録を捨てて書き戻す)
const EXT_VERSION := 1
const WEB_KEY := "parry-duel/save"
const WEB_KEY_EXT := "parry-duel/ext"
# 使えない時(保存を止めたブラウザなど)は投げずに null / "no" を返す。
# 書けたかは文字の "ok" で返す(JS の true は、Godot 4.7.2 の Web では bool として届かず、`is bool` が偽になった。v0.1.2 の不具合)
const JS_READ := "(() => { try { return localStorage.getItem('%s'); } catch (e) { return null; } })()"
const JS_WRITE := "(() => { try { localStorage.setItem('%s', %s); return 'ok'; } catch (e) { return 'no'; } })()"
const EXT_SETTINGS := ["easy", "show_diff"]  # ext に置く設定

var path: String
var data: Dictionary = {}
var ext: Dictionary = {}
var load_failed := false  # 保存があったのに読めなかった(E-15)
var write_failed := false  # 直前の書き込みが失敗した(E-16)
var _web := OS.has_feature("web")


func _init(p_path: String = PATH) -> void:
	path = p_path
	load_data()


static func default_settings() -> Dictionary:
	return {"volume": B.DEFAULT_VOLUME, "shake": true, "reduce_flash": false, "offset_ticks": 0}


static func default_ext_settings() -> Dictionary:
	return {"easy": false, "show_diff": true}


static func defaults() -> Dictionary:
	return {"version": VERSION, "fixed": null, "daily": null, "reached_boss": 1, "settings": default_settings()}


static func ext_defaults() -> Dictionary:
	return {"version": EXT_VERSION, "settings": default_ext_settings(), "easy": {"fixed": null, "daily": null}}


func ext_path() -> String:
	return path.get_basename() + "_ext.json"


func load_data() -> void:
	data = defaults()
	ext = ext_defaults()
	load_failed = false
	var text: Variant = _read_text(WEB_KEY, path, true)
	if text != null:
		var read: Variant = _parse(text)
		if read == null:
			load_failed = true
		else:
			data = read
	var text_ext: Variant = _read_text(WEB_KEY_EXT, ext_path(), false)
	if text_ext != null:
		var read_ext: Variant = _parse_ext(text_ext)
		if read_ext == null:
			load_failed = true
		else:
			ext = read_ext


# 保存の文字。無ければ null。legacy が真なら、Web で localStorage に無い時に v0.1.1 までの user:// のファイルを読む
# (次に書く時に localStorage へ移る)。
func _read_text(web_key: String, file: String, legacy: bool) -> Variant:
	if _web:
		var v: Variant = JavaScriptBridge.eval(JS_READ % web_key, true)
		if v is String:
			return v
		if not legacy:
			return null
	if not FileAccess.file_exists(file):
		return null
	return FileAccess.get_file_as_string(file)


func _write_text(web_key: String, file: String, text: String) -> bool:
	if _web:
		var ok: Variant = JavaScriptBridge.eval(JS_WRITE % [web_key, JSON.stringify(text)], true)
		return ok is String and ok == "ok"
	var f := FileAccess.open(file, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.close()
	return true


# 本の保存の文字を読んで、決まった形に直す。JSON として読めない・辞書でない時は null。知らない項目はそのまま持つ。
static func _parse(text: String) -> Variant:
	var j := JSON.new()
	if j.parse(text) != OK or not (j.data is Dictionary):
		return null
	var v: Dictionary = j.data
	var out := defaults()
	out["settings"] = _read_settings(v.get("settings"))
	if not _is_num(v.get("version")) or float(v["version"]) != float(VERSION):
		return out  # 知らない版。記録は初めから、設定だけ引き継ぐ
	_read_book(v, out)
	if _is_num(v.get("reached_boss")):
		out["reached_boss"] = clampi(int(v["reached_boss"]), 1, B.BOSS_COUNT)
	_keep_unknown(v, out)
	return out


# ext の保存を読む。読めなければ null。
static func _parse_ext(text: String) -> Variant:
	var j := JSON.new()
	if j.parse(text) != OK or not (j.data is Dictionary):
		return null
	var v: Dictionary = j.data
	var out := ext_defaults()
	var st: Variant = v.get("settings")
	if st is Dictionary:
		for k: String in EXT_SETTINGS:
			if st.get(k) is bool:
				out["settings"][k] = st[k]
		_keep_unknown(st, out["settings"])
	if _is_num(v.get("version")) and float(v["version"]) == float(EXT_VERSION):
		if v.get("easy") is Dictionary:
			_read_book(v["easy"], out["easy"])
			_keep_unknown(v["easy"], out["easy"])
	_keep_unknown(v, out)
	return out


# 知らない項目(後の版が足した物)を、消さずに写す。
static func _keep_unknown(from: Dictionary, to: Dictionary) -> void:
	for k: Variant in from:
		if not to.has(k):
			to[k] = from[k]


# 記録の帳面(いつもの3連戦の最高 fixed と、今日の記録 daily)を読む。
static func _read_book(v: Dictionary, out: Dictionary) -> void:
	out["fixed"] = _read_record(v.get("fixed"), true)
	var daily: Variant = v.get("daily")
	if daily is Dictionary and _is_num(daily.get("day")):
		out["daily"] = {"day": int(daily["day"]), "first": _read_record(daily.get("first"), false), "best": _read_record(daily.get("best"), false)}


# 書く直前に、今ある保存を読み直して記録を合わせる。同じブラウザの別のタブが先に書いた記録を、
# 古い方のタブが上書きして消さないようにする。記録は良い方、着いた敵は先の方、今日の記録は新しい日の方を残す。設定は今の物。
func _merge_from_disk() -> void:
	var text: Variant = _read_text(WEB_KEY, path, true)
	var disk: Variant = _parse(text) if text != null else null
	if disk != null:
		data["reached_boss"] = maxi(int(data["reached_boss"]), int(disk["reached_boss"]))
		_merge_book(data, disk)
		_keep_unknown(disk, data)
	var text_ext: Variant = _read_text(WEB_KEY_EXT, ext_path(), false)
	var disk_ext: Variant = _parse_ext(text_ext) if text_ext != null else null
	if disk_ext != null:
		_merge_book(ext["easy"], disk_ext["easy"])
		_keep_unknown(disk_ext, ext)
		_keep_unknown(disk_ext["settings"], ext["settings"])


static func _merge_book(mine_book: Dictionary, disk_book: Dictionary) -> void:
	mine_book["fixed"] = _better_of(mine_book["fixed"], disk_book["fixed"])
	var mine: Variant = mine_book["daily"]
	var theirs: Variant = disk_book["daily"]
	if not (theirs is Dictionary):
		return
	if not (mine is Dictionary) or int(theirs["day"]) > int(mine["day"]):
		mine_book["daily"] = theirs
	elif int(theirs["day"]) == int(mine["day"]):
		# 同じ日。1 回目は、先に書かれていた方(ファイルの方)を残す
		mine_book["daily"] = {"day": int(mine["day"]), "first": theirs["first"] if theirs["first"] != null else mine["first"],
			"best": _better_of(mine["best"], theirs["best"])}


static func _better_of(a: Variant, b: Variant) -> Variant:
	if not (a is Dictionary):
		return b
	if not (b is Dictionary):
		return a
	return b if Rank.better(b, a) else a


func save_data() -> bool:
	_merge_from_disk()
	var ok_main := _write_text(WEB_KEY, path, JSON.stringify(data, "", false))
	var ok_ext := _write_text(WEB_KEY_EXT, ext_path(), JSON.stringify(ext, "", false))
	write_failed = not (ok_main and ok_ext)
	return not write_failed


static func _is_num(v: Variant) -> bool:
	return v is float or v is int


static func _read_record(v: Variant, full: bool) -> Variant:
	if not (v is Dictionary) or not _is_num(v.get("hits")) or not _is_num(v.get("ticks")):
		return null
	var out := {"hits": maxi(int(v["hits"]), 0), "ticks": maxi(int(v["ticks"]), 0)}
	if full:
		out["justs"] = maxi(int(v["justs"]), 0) if _is_num(v.get("justs")) else 0
		out["retries"] = maxi(int(v["retries"]), 0) if _is_num(v.get("retries")) else 0
	return out


static func _read_settings(v: Variant) -> Dictionary:
	var out := default_settings()
	if not (v is Dictionary):
		return out
	if _is_num(v.get("volume")) and int(v["volume"]) in B.VOLUMES:
		out["volume"] = int(v["volume"])
	if v.get("shake") is bool:
		out["shake"] = v["shake"]
	if v.get("reduce_flash") is bool:
		out["reduce_flash"] = v["reduce_flash"]
	if _is_num(v.get("offset_ticks")):
		out["offset_ticks"] = clampi(int(v["offset_ticks"]), B.OFFSET_MIN, B.OFFSET_MAX)  # E-12
	_keep_unknown(v, out)
	return out


# 今の設定(本の保存と ext を合わせた写し)。変える時は set_setting を使う。
func settings() -> Dictionary:
	var out: Dictionary = data["settings"].duplicate()
	for k: String in EXT_SETTINGS:
		out[k] = ext["settings"][k]
	return out


# 設定を 1 つ変えて、すぐ保存する。
func set_setting(key: String, value: Variant) -> void:
	if key == "offset_ticks":
		value = clampi(int(value), B.OFFSET_MIN, B.OFFSET_MAX)
	if key in EXT_SETTINGS:
		ext["settings"][key] = value
	else:
		data["settings"][key] = value
	save_data()


func reached_boss() -> int:
	return data["reached_boss"]


# 敵に着いた時に呼ぶ。先へ進んだ時だけ保存する。
func reach(boss: int) -> void:
	if boss > int(data["reached_boss"]):
		data["reached_boss"] = clampi(boss, 1, B.BOSS_COUNT)
		save_data()


# 記録の帳面。やさしい設定の回は ext の方。
func _book(easy: bool) -> Dictionary:
	return ext["easy"] if easy else data


# いつもの3連戦の最高。無ければ null。
func fixed_best(easy: bool = false) -> Variant:
	return _book(easy)["fixed"]


# 今日の記録 { day, first, best }。日付が変わっていたら空の物を返す(保存はまだ書き換えない)。
func daily(day: int, easy: bool = false) -> Dictionary:
	var d: Variant = _book(easy)["daily"]
	if d is Dictionary and int(d["day"]) == day:
		return d
	return {"day": day, "first": null, "best": null}


# 入口ごとの今の最高。無ければ null。
func best_for(mode: int, day: int, easy: bool = false) -> Variant:
	if mode == Duel.Mode.FIXED:
		return fixed_best(easy)
	if mode == Duel.Mode.DAILY:
		return daily(day, easy)["best"]
	return null


# 3 体を倒した回を記録する(練習は残さない)。やさしい設定の回(result.easy)は別の帳面に。
# { prev_best, new_best, first_today, saved } を返す。
func record_win(mode: int, day: int, result: Dictionary) -> Dictionary:
	var easy: bool = result.get("easy", false) == true
	var out := {"prev_best": best_for(mode, day, easy), "new_best": false, "first_today": false, "saved": true}
	if mode != Duel.Mode.FIXED and mode != Duel.Mode.DAILY:
		return out
	var book := _book(easy)
	var rec := {"hits": int(result["hits"]), "ticks": int(result["ticks"])}
	out["new_best"] = out["prev_best"] == null or Rank.better(rec, out["prev_best"])
	if mode == Duel.Mode.FIXED:
		if out["new_best"]:
			book["fixed"] = {"hits": rec["hits"], "ticks": rec["ticks"], "justs": int(result["justs"]), "retries": int(result["retries"])}
	else:
		var stored: Variant = book["daily"]
		if stored is Dictionary and int(stored["day"]) > day:
			# 日付をまたいで終わった回。もう新しい日の記録があるので、古い日の物で置き換えない
			out["new_best"] = false
			return out
		var today := daily(day, easy)
		if today["first"] == null:
			today["first"] = rec.duplicate()
			out["first_today"] = true
		if out["new_best"]:
			today["best"] = rec.duplicate()
		book["daily"] = today
	out["saved"] = save_data()
	return out
