# 効果音(INTERFACES.md §2): 12 個の wav が読める・長さと最大振幅・unlock の前と音量 0 では鳴らない・知らない名前で止まらない。
# ヘッドレスでは音は出ないので、「鳴ったか」は Sfx.played(再生を始めた回数)で見る。
extends "res://tests/suite.gd"

const SfxScript := preload("res://audio/sfx.gd")
const NAMES := ["warn_white", "warn_red", "parry", "just", "whiff", "clank", "dodge", "hurt", "soft", "stagger", "counter", "shatter"]
# 長さの目安(ms)
const LENGTH_MS := {
	"warn_white": [60, 120], "warn_red": [60, 120], "parry": [80, 140], "just": [200, 320],
	"whiff": [120, 180], "clank": [120, 180], "dodge": [180, 250], "hurt": [120, 200],
	"soft": [40, 80], "stagger": [250, 400], "counter": [350, 500], "shatter": [500, 700],
}
const PEAK_MAX := 23197  # −3 dBFS(32767 × 10^(−3/20))。これ以下なら割れていない
const PEAK_MIN := 2000  # 約 −24 dBFS。これより小さければ無音に近い


func _root() -> Node:
	return (Engine.get_main_loop() as SceneTree).root


# 木に入れた新しい実体。autoload の状態を、ほかのテストへ漏らさない。使い終わったら free() する。
func _fresh(unlock: bool = true) -> Node:
	var s: Node = SfxScript.new()
	_root().add_child(s)
	if unlock:
		s.unlock()
	return s


func _playing(s: Node) -> Array:
	return s.get_children().filter(func(v: AudioStreamPlayer) -> bool: return v.playing)


# wav の中身を生で読む(取り込みの設定に左右されない)。{ms, peak, first, last}。読めなければ空。
func _wav(sound_name: String) -> Dictionary:
	var b := FileAccess.get_file_as_bytes("res://assets/sfx/%s.wav" % sound_name)
	if b.size() <= 44 or b.slice(0, 4).get_string_from_ascii() != "RIFF" or b.slice(36, 40).get_string_from_ascii() != "data":
		return {}
	eq([b.decode_u16(22), b.decode_u32(24), b.decode_u16(34)], [1, 44100, 16], sound_name + ": モノラル・44100 Hz・16bit")
	var count := b.decode_u32(40) / 2
	eq(44 + count * 2, b.size(), sound_name + ": data の長さがファイルと合う")
	var peak := 0
	for i in count:
		peak = maxi(peak, absi(b.decode_s16(44 + i * 2)))
	return {"ms": count * 1000 / 44100, "peak": peak, "first": b.decode_s16(44), "last": b.decode_s16(b.size() - 2)}


func test_names_match_contract() -> bool:
	eq(SfxScript.NAMES, NAMES, "Sfx.NAMES は §2 の 12 個")
	eq(NAMES.size(), 12, "12 種(仕様書の上限)")
	return true


func test_autoload_is_registered() -> bool:
	var s := _root().get_node_or_null("Sfx")
	ok(s != null, "autoload Sfx が居る")
	if s != null:
		ok(s.get_script() == SfxScript, "autoload は audio/sfx.gd")
		for method: String in ["play", "set_volume", "unlock"]:
			ok(s.has_method(method), "Sfx.%s がある" % method)
	return true


func test_files_load() -> bool:
	for sound_name: String in NAMES:
		var stream := load("res://assets/sfx/%s.wav" % sound_name) as AudioStreamWAV
		ok(stream != null, sound_name + ".wav を読める")
		if stream != null:
			eq(stream.mix_rate, 44100, sound_name + ": 44100 Hz")
			ok(not stream.stereo, sound_name + ": モノラル")
			eq(stream.format, AudioStreamWAV.FORMAT_16_BITS, sound_name + ": 無圧縮で取り込む(.import の compress/mode=0。QOA だと金属の音がざらつく)")
			ok(stream.get_length() > 0.03, sound_name + ": 長さがある")
	var s := _fresh()
	eq(s._streams.size(), 12, "Sfx が 12 個とも読んだ")
	s.free()
	return true


func test_wav_length_and_peak() -> bool:
	var peaks := {}
	for sound_name: String in NAMES:
		var w := _wav(sound_name)
		ok(not w.is_empty(), sound_name + ".wav が RIFF の形")
		if w.is_empty():
			continue
		var want: Array = LENGTH_MS[sound_name]
		ok(w["ms"] >= want[0] and w["ms"] <= want[1], "%s: 長さ %d ms が %d〜%d ms の外" % [sound_name, w["ms"], want[0], want[1]])
		ok(w["peak"] <= PEAK_MAX, "%s: 最大振幅 %d が −3 dBFS を超える" % [sound_name, w["peak"]])
		ok(w["peak"] >= PEAK_MIN, "%s: 最大振幅 %d は無音に近い" % [sound_name, w["peak"]])
		ok(absi(w["first"]) < 200 and absi(w["last"]) < 200, "%s: 頭と尻が 0 から離れている(プチッと鳴る)" % sound_name)
		peaks[sound_name] = w["peak"]
	if peaks.size() == 12:
		for sound_name: String in NAMES:
			ok(peaks["counter"] >= peaks[sound_name], "counter が一番大きい(%s の方が大きい)" % sound_name)
		ok(peaks["warn_white"] < peaks["parry"], "予告(白)は parry より小さい")
		ok(peaks["warn_red"] < peaks["parry"], "予告(赤)は parry より小さい")
	return true


func test_silent_until_unlock() -> bool:
	var s := _fresh(false)
	s.play("parry")
	s.play("counter", 3)
	eq(s.played, 0, "unlock の前は鳴らない")
	eq(_playing(s).size(), 0, "プレイヤーも動いていない")
	s.unlock()
	s.play("parry")
	eq(s.played, 1, "unlock の後は鳴る")
	eq(_playing(s).size(), 1, "プレイヤーが 1 つ動いている")
	s.free()
	return true


func test_volume_zero_is_silent() -> bool:
	var s := _fresh()
	s.set_volume(0)
	s.play("parry")
	eq(s.played, 0, "音量 0 では鳴らない")
	s.set_volume(50)
	s.play("parry")
	eq(s.played, 1, "音量を戻せば鳴る")
	s.free()
	return true


func test_volume_steps() -> bool:
	var s := _fresh()
	var db: Array = []
	for percent: int in [25, 50, 75, 100]:
		s.set_volume(percent)
		db.append(s.get_child(0).volume_db)
		eq(s.get_child(s.get_child_count() - 1).volume_db, db[-1], "どのプレイヤーも同じ音量")
	ok(absf(db[3]) < 0.01, "100 は 0 dB")
	for i in 3:
		var step: float = db[i + 1] - db[i]
		ok(step >= 3.0 and step <= 14.0, "段の差 %.1f dB が自然な幅(3〜14 dB)の外" % step)
	ok(db[0] >= -30.0, "25 でも聞こえる大きさ(%.1f dB)" % db[0])
	s.set_volume(250)
	eq(s.volume, 100, "100 を超える値は 100")
	s.set_volume(-5)
	eq(s.volume, 0, "負の値は 0")
	s.free()
	return true


func test_unknown_name_is_ignored() -> bool:
	var s := _fresh()
	s.play("no_such_sound")
	s.play("")
	s.play("parry.wav", 5)
	eq(s.played, 0, "知らない名前は何もしない")
	s.free()
	return true


func test_missing_files_do_not_stop() -> bool:
	var s: Node = SfxScript.new()
	s.dir = "res://no_such_dir/"
	_root().add_child(s)
	s.unlock()
	for sound_name: String in NAMES:
		s.play(sound_name)
	eq(s.played, 0, "ファイルが無ければ音なしで続ける")
	s.free()
	return true


func test_all_twelve_play() -> bool:
	var s := _fresh()
	for sound_name: String in NAMES:
		s.play(sound_name)
	eq(s.played, 12, "12 個とも鳴る")
	s.free()
	return true


func test_pitch_from_semitones() -> bool:
	var s := _fresh()
	s.play("parry")
	ok(is_equal_approx(s.last_pitch, 1.0), "0 半音は 1.0")
	s.play("parry", 12)
	ok(is_equal_approx(s.last_pitch, 2.0), "+12 半音は 2.0")
	s.play("parry", 1)
	ok(absf(s.last_pitch - 1.059463) < 0.0001, "+1 半音は 2^(1/12)")
	s.play("hurt", -7)
	ok(absf(s.last_pitch - 0.667420) < 0.0001, "−7 半音は 2^(−7/12)")
	s.free()
	return true


func test_same_sound_overlaps() -> bool:
	var s := _fresh()
	for semitones in 3:
		s.play("parry", semitones)
	var playing := _playing(s)
	eq(playing.size(), 3, "同じ音が 3 つ重なって鳴る")
	if playing.size() == 3:
		ok(is_equal_approx(playing[0].pitch_scale, 1.0), "後から鳴らした音が、先の音の高さを動かさない")
		ok(playing[2].pitch_scale > playing[1].pitch_scale, "半音ずつ上がる")
	for i in 20:
		s.play("soft")
	eq(s.played, 23, "プレイヤーの数を超えても止まらない")
	ok(_playing(s).size() <= s.VOICES, "同時に鳴るのは VOICES まで")
	s.free()
	return true
