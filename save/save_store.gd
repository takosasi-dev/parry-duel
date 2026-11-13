# user://save.json の読み書き(仕様書 §9.11・E-12・E-15・E-16)。記録・着いた敵・設定を持つ。
# 読めない・壊れている時は既定値で始め、書けなくてもエラーで止めない。外から来た値は型を見てから使う。
extends RefCounted

const B := preload("res://core/balance.gd")
const Rank := preload("res://core/rank.gd")
const Duel := preload("res://core/duel.gd")

const PATH := "user://save.json"
const VERSION := 1

var path: String
var data: Dictionary = {}
var load_failed := false  # 保存があったのに読めなかった(E-15)
var write_failed := false  # 直前の書き込みが失敗した(E-16)


func _init(p_path: String = PATH) -> void:
	path = p_path
	load_data()


static func default_settings() -> Dictionary:
	return {"volume": B.DEFAULT_VOLUME, "shake": true, "reduce_flash": false, "offset_ticks": 0}


static func defaults() -> Dictionary:
	return {"version": VERSION, "fixed": null, "daily": null, "reached_boss": 1, "settings": default_settings()}


func load_data() -> void:
	data = defaults()
	load_failed = false
	if not FileAccess.file_exists(path):
		return
	var read: Variant = _parse(FileAccess.get_file_as_string(path))
	if read == null:
		load_failed = true
		return
	data = read


# 保存の文字を読んで、決まった形に直す。JSON として読めない・辞書でない時は null。
static func _parse(text: String) -> Variant:
	var j := JSON.new()
	if j.parse(text) != OK or not (j.data is Dictionary):
		return null
	var v: Dictionary = j.data
	var out := defaults()
	out["settings"] = _read_settings(v.get("settings"))
	if not _is_num(v.get("version")) or float(v["version"]) != float(VERSION):
		return out  # 知らない版。記録は初めから、設定だけ引き継ぐ
	out["fixed"] = _read_record(v.get("fixed"), true)
	var daily: Variant = v.get("daily")
	if daily is Dictionary and _is_num(daily.get("day")):
		out["daily"] = {"day": int(daily["day"]), "first": _read_record(daily.get("first"), false), "best": _read_record(daily.get("best"), false)}
	if _is_num(v.get("reached_boss")):
		out["reached_boss"] = clampi(int(v["reached_boss"]), 1, B.BOSS_COUNT)
	return out


# 書く直前に、今あるファイルを読み直して記録を合わせる。同じブラウザの別のタブが先に書いた記録を、
# 古い方のタブが上書きして消さないようにする。記録は良い方、着いた敵は先の方、今日の記録は新しい日の方を残す。設定は今の物。
func _merge_from_disk() -> void:
	if not FileAccess.file_exists(path):
		return
	var disk: Variant = _parse(FileAccess.get_file_as_string(path))
	if disk == null:
		return
	data["reached_boss"] = maxi(int(data["reached_boss"]), int(disk["reached_boss"]))
	data["fixed"] = _better_of(data["fixed"], disk["fixed"])
	var mine: Variant = data["daily"]
	var theirs: Variant = disk["daily"]
	if not (theirs is Dictionary):
		return
	if not (mine is Dictionary) or int(theirs["day"]) > int(mine["day"]):
		data["daily"] = theirs
	elif int(theirs["day"]) == int(mine["day"]):
		# 同じ日。1 回目は、先に書かれていた方(ファイルの方)を残す
		data["daily"] = {"day": int(mine["day"]), "first": theirs["first"] if theirs["first"] != null else mine["first"],
			"best": _better_of(mine["best"], theirs["best"])}


static func _better_of(a: Variant, b: Variant) -> Variant:
	if not (a is Dictionary):
		return b
	if not (b is Dictionary):
		return a
	return b if Rank.better(b, a) else a


func save_data() -> bool:
	_merge_from_disk()
	var f := FileAccess.open(path, FileAccess.WRITE)
	write_failed = f == null
	if f == null:
		return false
	f.store_string(JSON.stringify(data, "", false))
	f.close()
	return true


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
	return out


func settings() -> Dictionary:
	return data["settings"]


# 設定を 1 つ変えて、すぐ保存する。
func set_setting(key: String, value: Variant) -> void:
	if key == "offset_ticks":
		value = clampi(int(value), B.OFFSET_MIN, B.OFFSET_MAX)
	data["settings"][key] = value
	save_data()


func reached_boss() -> int:
	return data["reached_boss"]


# 敵に着いた時に呼ぶ。先へ進んだ時だけ保存する。
func reach(boss: int) -> void:
	if boss > int(data["reached_boss"]):
		data["reached_boss"] = clampi(boss, 1, B.BOSS_COUNT)
		save_data()


# いつもの3連戦の最高。無ければ null。
func fixed_best() -> Variant:
	return data["fixed"]


# 今日の記録 { day, first, best }。日付が変わっていたら空の物を返す(保存はまだ書き換えない)。
func daily(day: int) -> Dictionary:
	var d: Variant = data["daily"]
	if d is Dictionary and int(d["day"]) == day:
		return d
	return {"day": day, "first": null, "best": null}


# 入口ごとの今の最高。無ければ null。
func best_for(mode: int, day: int) -> Variant:
	if mode == Duel.Mode.FIXED:
		return fixed_best()
	if mode == Duel.Mode.DAILY:
		return daily(day)["best"]
	return null


# 3 体を倒した回を記録する(練習は残さない)。{ prev_best, new_best, first_today, saved } を返す。
func record_win(mode: int, day: int, result: Dictionary) -> Dictionary:
	var out := {"prev_best": best_for(mode, day), "new_best": false, "first_today": false, "saved": true}
	if mode == Duel.Mode.PRACTICE:
		return out
	var rec := {"hits": int(result["hits"]), "ticks": int(result["ticks"])}
	out["new_best"] = out["prev_best"] == null or Rank.better(rec, out["prev_best"])
	if mode == Duel.Mode.FIXED:
		if out["new_best"]:
			data["fixed"] = {"hits": rec["hits"], "ticks": rec["ticks"], "justs": int(result["justs"]), "retries": int(result["retries"])}
	else:
		var stored: Variant = data["daily"]
		if stored is Dictionary and int(stored["day"]) > day:
			# 日付をまたいで終わった回。もう新しい日の記録があるので、古い日の物で置き換えない
			out["new_best"] = false
			return out
		var today := daily(day)
		if today["first"] == null:
			today["first"] = rec.duplicate()
			out["first_today"] = true
		if out["new_best"]:
			today["best"] = rec.duplicate()
		data["daily"] = today
	out["saved"] = save_data()
	return out
