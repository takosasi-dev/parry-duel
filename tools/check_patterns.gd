# 型のデータ(data/patterns.json)の検査 (a)〜(f) を回し、型ごとの当たる tick の並びを印字する(仕様書 §9.7・FR-28)。
# 実行: python tools/gd.py run res://tools/check_patterns.gd  (検査に落ちたら終了コード 1)
extends SceneTree

const PatternStore := preload("res://core/pattern_store.gd")
const B := preload("res://core/balance.gd")


func _initialize() -> void:
	var data := PatternStore.load_file(PatternStore.PATH)
	var errors: Array = data["errors"]
	if data["ok"]:
		errors = PatternStore.check_all(data["bosses"])
		var count := 0
		for boss: Dictionary in data["bosses"]:
			for pi in boss["phases"].size():
				for p: Dictionary in boss["phases"][pi]["patterns"]:
					count += 1
					var marks: Array = []
					for c: Dictionary in PatternStore.contacts(p):
						marks.append("%s%d" % ["赤" if c["kind"] == "red" else "白", c["tick"]])
					print("%-14s 段階 %d  長さ %3d(%.1f 秒)  %s%s" % [p["id"], pi + 1, p["length"], p["length"] / float(B.TICK_HZ),
						"  ".join(marks), "  [教える型]" if p["teach"] else ""])
		print("型 %d 個" % count)
	for e: String in errors:
		print("NG  ", e)
	print("検査に落ちた物: %d 件" % errors.size())
	quit(1 if not errors.is_empty() else 0)
