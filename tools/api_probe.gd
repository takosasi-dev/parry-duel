# 仕様書 §9 と ui で使う Godot の API 名が、この版の ClassDB に実在するかを確かめて印字する(§8.1「API 名の確認」)。
# 実行: python tools/gd.py run res://tools/api_probe.gd
extends SceneTree

const PROPS := {
	"InputEvent": ["device"],
	"InputEventKey": ["pressed", "echo", "keycode", "physical_keycode", "location"],
	"InputEventMouseButton": ["button_index", "pressed", "position", "double_click"],
	"InputEventScreenTouch": ["index", "position", "pressed", "canceled", "double_tap"],
	"AudioStreamPlayer": ["stream", "volume_db", "pitch_scale", "max_polyphony", "playback_type", "bus"],
	"FontVariation": ["base_font", "variation_opentype"],
	"TextEdit": ["text", "editable", "selecting_enabled", "context_menu_enabled", "wrap_mode"],
	"CanvasItemMaterial": ["blend_mode"],
	"Label": ["text", "autowrap_mode", "horizontal_alignment"],
}
const METHODS := {
	"Time": ["get_ticks_usec", "get_date_dict_from_system"],
	"JavaScriptBridge": ["eval", "get_interface"],
	"DisplayServer": ["clipboard_set", "window_get_size"],
	"CanvasItem": ["draw_line", "draw_polyline", "draw_colored_polygon", "draw_polygon", "draw_arc", "draw_circle",
		"draw_rect", "draw_string", "draw_set_transform", "queue_redraw"],
	"FileAccess": ["open", "file_exists", "get_file_as_string", "store_string"],
	"JSON": ["parse", "stringify"],
	"AudioServer": ["set_bus_volume_db", "get_bus_index"],
	"TextEdit": ["select_all"],
	"Viewport": ["get_visible_rect", "set_input_as_handled"],
	"OS": ["has_feature", "get_cmdline_user_args"],
	"RenderingServer": ["get_video_adapter_name"],
}
const CONSTS := {
	"InputEvent": ["DEVICE_ID_EMULATION"],
	"Node": ["NOTIFICATION_APPLICATION_FOCUS_OUT", "NOTIFICATION_APPLICATION_FOCUS_IN", "NOTIFICATION_WM_WINDOW_FOCUS_OUT",
		"NOTIFICATION_APPLICATION_PAUSED", "NOTIFICATION_WM_CLOSE_REQUEST"],
	"MainLoop": ["NOTIFICATION_APPLICATION_FOCUS_OUT"],
	"CanvasItemMaterial": ["BLEND_MODE_ADD"],
	"TextServer": ["AUTOWRAP_ARBITRARY"],
}


func _initialize() -> void:
	var ng := 0
	for c: String in PROPS:
		var have := ClassDB.class_get_property_list(c).map(func(p: Dictionary) -> String: return p["name"])
		for p: String in PROPS[c]:
			ng += _say(c + "." + p, have.has(p))
	for c: String in METHODS:
		for m: String in METHODS[c]:
			ng += _say(c + "." + m + "()", ClassDB.class_has_method(c, m))
	for c: String in CONSTS:
		for k: String in CONSTS[c]:
			ng += _say(c + "." + k + " = " + str(ClassDB.class_get_integer_constant(c, k)), ClassDB.class_has_integer_constant(c, k))
	# 前提 7: 入力イベントが時刻を持つか。InputEvent とその子の項目名から time・stamp を探す。
	for c: String in ["InputEvent", "InputEventKey", "InputEventMouseButton", "InputEventScreenTouch", "InputEventWithModifiers", "InputEventFromWindow", "InputEventMouse"]:
		var names := ClassDB.class_get_property_list(c).map(func(p: Dictionary) -> String: return p["name"])
		var timed := names.filter(func(n: String) -> bool: return n.contains("time") or n.contains("stamp"))
		print("  %s の項目: %s / 時刻らしい項目: %s" % [c, ", ".join(names.filter(func(n: String) -> bool: return not n.contains(" ") and n != "script")), timed])
	print("KeyLocation: ", ClassDB.class_get_enum_constants("InputEventKey", "KeyLocation") if ClassDB.class_has_enum("InputEventKey", "KeyLocation") else "(InputEventKey には無い。@GlobalScope の KEY_LOCATION_LEFT = %d)" % KEY_LOCATION_LEFT)
	print("版: ", Engine.get_version_info()["string"])
	print("確かめられなかった物: %d 件" % ng)
	quit(1 if ng > 0 else 0)


func _say(what: String, ok: bool) -> int:
	print(("OK  " if ok else "NG  ") + what)
	return 0 if ok else 1
