# BGM(autoload Bgm): ogg がある・ループが有効・長さ・大きさの予算・継ぎ目・Bgm の決まり(unlock の前と音量 0 は鳴らさない、同じ曲で始め直さない、知らない曲で止まらない)。
# ヘッドレスでは音は出ないので、「鳴ったか」は AudioStreamPlayer.playing と Bgm.started(頭から始めた回数)で見る。下げる途中は _process を直に呼んで進める。
extends "res://tests/suite.gd"

const BgmScript := preload("res://audio/bgm.gd")
const TRACKS := ["title", "duel"]
const BUDGET := 1200000  # assets/bgm の ogg の合計(バイト)。初回の読み込みを重くしない


func _root() -> Node:
	return (Engine.get_main_loop() as SceneTree).root


# 木に入れた新しい実体。autoload の状態を、ほかのテストへ漏らさない。使い終わったら free() する。
func _fresh(unlock: bool = true) -> Node:
	var b: Node = BgmScript.new()
	_root().add_child(b)
	if unlock:
		b.unlock()
	return b


# 鳴っている曲の名前(TRACKS の順)。
func _playing(b: Node) -> Array:
	var out: Array = []
	for track: String in TRACKS:
		if b._players.has(track) and b._players[track].playing:
			out.append(track)
	return out


func test_tracks_match_contract() -> bool:
	eq(BgmScript.TRACKS, TRACKS, "Bgm.TRACKS")
	return true


func test_autoload_is_registered() -> bool:
	var b := _root().get_node_or_null("Bgm")
	ok(b != null, "autoload Bgm が居る")
	if b != null:
		ok(b.get_script() == BgmScript, "autoload は audio/bgm.gd")
		for method: String in ["play", "stop", "set_volume", "unlock"]:
			ok(b.has_method(method), "Bgm.%s がある" % method)
		eq(b.process_mode, Node.PROCESS_MODE_ALWAYS, "一時停止中も鳴り続ける")
	return true


func test_files_loop_length_and_budget() -> bool:
	var total := 0
	for track: String in TRACKS:
		var path := "res://assets/bgm/%s.ogg" % track
		var stream := load(path) as AudioStreamOggVorbis
		ok(stream != null, track + ".ogg を読める")
		if stream == null:
			continue
		ok(stream.loop, track + ": ループが有効(.import の loop=true)")
		eq(stream.loop_offset, 0.0, track + ": 頭から繰り返す")
		var sec := stream.get_length()
		ok(sec >= 16.0 and sec <= 32.0, "%s: 1 周 %.2f 秒が 16〜32 秒の外" % [track, sec])
		total += FileAccess.get_file_as_bytes(path).size()
	ok(total > 0 and total <= BUDGET, "ogg の合計 %d バイトが予算 %d を超える" % [total, BUDGET])
	var b := _fresh(false)
	eq(b._players.size(), TRACKS.size(), "Bgm が全部の曲を読んだ")
	b.free()
	return true


# Godot の再生で、尻の 50 ms から頭へ回る 100 ms を取り出す(音は出さず、mix_audio で波形だけ)。
# 回った後が頭から鳴らした物と同じ(長さの丸めで ±2 サンプルまで)で、継ぎ目の段差が前後の段差の上位 1% に入らない事を見る。
func test_loop_seam_through_godot() -> bool:
	var rate := AudioServer.get_mix_rate()
	var half := int(rate * 0.05)
	for track: String in TRACKS:
		var stream := load("res://assets/bgm/%s.ogg" % track) as AudioStreamOggVorbis
		if stream == null:
			continue
		var tail := stream.instantiate_playback()
		tail.start(stream.get_length() - 0.05)
		var a := tail.mix_audio(1.0, half * 2)
		var head := stream.instantiate_playback()
		head.start(0.0)
		var b := head.mix_audio(1.0, half)
		eq([a.size(), b.size()], [half * 2, half], track + ": 取り出せた長さ")
		if a.size() != half * 2 or b.size() != half:
			continue
		var best := INF
		for shift in range(-2, 3):
			var worst := 0.0
			for k in range(8, half - 4):  # 頭の数サンプルは再生の立ち上がり(0 が入る)なので見ない
				worst = maxf(worst, absf(a[half + shift + k].x - b[k].x))
			best = minf(best, worst)
		ok(best < 0.00001, "%s: 尻から回った後が頭から鳴らした物と違う(差 %f。隙間かずれがある)" % [track, best])
		var steps: Array = []
		var near := 0.0
		for i in range(8, a.size()):
			var d := absf(a[i].x - a[i - 1].x)
			steps.append(d)
			if absi(i - half) <= 3:
				near = maxf(near, d)
		steps.sort()
		var p99: float = steps[int(steps.size() * 0.99)]
		ok(near <= p99, "%s: 継ぎ目の段差 %f が前後 100 ms の上位 1%%(%f)より大きい" % [track, near, p99])
	return true


func test_silent_until_unlock() -> bool:
	var b := _fresh(false)
	b.play("title")
	eq(b.current, "title", "unlock の前でも頼まれた曲は覚える")
	eq(_playing(b), [], "unlock の前は鳴らない")
	b.unlock()
	eq(_playing(b), ["title"], "unlock で今の曲を始める")
	eq(b.started, 1, "頭から始めたのは 1 回")
	b.free()
	return true


func test_volume_zero_is_silent() -> bool:
	var b := _fresh()
	b.set_volume(0)
	b.play("duel")
	eq(_playing(b), [], "音量 0 では鳴らない")
	eq(b.current, "duel", "曲は覚えておく")
	b.set_volume(50)
	eq(_playing(b), ["duel"], "音量を戻すと今の曲が始まる")
	b.set_volume(0)
	eq(_playing(b), [], "鳴っている時に 0 にすると止まる")
	b.set_volume(25)
	eq(_playing(b), ["duel"], "もう一度戻すとまた鳴る")
	b.free()
	return true


func test_volume_steps_like_sfx() -> bool:
	var b := _fresh()
	b.play("title")
	var player: AudioStreamPlayer = b._players["title"]
	var want := {100: 0.0, 75: -5.0, 50: -12.0, 25: -24.1}
	for percent: int in want:
		b.set_volume(percent)
		ok(absf(player.volume_db - want[percent]) < 0.1, "音量 %d は %.1f dB(%.1f dB だった)" % [percent, want[percent], player.volume_db])
	b.set_volume(250)
	eq(b.volume, 100, "100 を超える値は 100")
	b.set_volume(-5)
	eq(b.volume, 0, "負の値は 0")
	b.free()
	return true


func test_same_track_does_not_restart() -> bool:
	var b := _fresh()
	b.play("title")
	b.play("title")
	b._process(0.3)
	b.play("title")
	eq(b.started, 1, "同じ曲の play で始め直さない")
	eq(_playing(b), ["title"], "鳴り続けている")
	ok(b._fading.is_empty(), "下げてもいない")
	b.free()
	return true


func test_unknown_track_is_ignored() -> bool:
	var b := _fresh()
	b.play("title")
	for track: String in ["", "no_such_track", "title.ogg", "TITLE"]:
		b.play(track)
	eq(b.current, "title", "知らない曲では今の曲を変えない")
	eq(_playing(b), ["title"], "知らない曲で止まらない")
	eq(b.started, 1, "始め直さない")
	b.free()
	return true


func test_missing_files_do_not_stop() -> bool:
	var b: Node = BgmScript.new()
	b.dir = "res://no_such_dir/"
	_root().add_child(b)
	b.unlock()
	for track: String in TRACKS:
		b.play(track)
	b.stop()
	b.set_volume(50)
	b._process(1.0)
	eq(b.started, 0, "ファイルが無ければ音なしで続ける")
	eq(b.current, "", "読めない曲は頼まれても覚えない")
	b.free()
	return true


func test_crossfade_and_stop() -> bool:
	var b := _fresh()
	b.play("title")
	b.play("duel")
	eq(b.current, "duel", "今の曲が替わる")
	eq(_playing(b), ["title", "duel"], "入れ替えの間は両方鳴る")
	var title: AudioStreamPlayer = b._players["title"]
	var duel: AudioStreamPlayer = b._players["duel"]
	ok(absf(duel.volume_db - b._base_db()) < 0.01, "新しい曲は目標の音量で始まる(下げた所から上げない)")
	b._process(0.3)
	ok(title.volume_db < duel.volume_db - 3.0, "古い曲は下がっていく")
	b._process(0.35)
	eq(_playing(b), ["duel"], "0.6 秒ほどで古い曲は止まる")
	b.stop()
	eq(b.current, "", "stop で曲なし")
	eq(_playing(b), ["duel"], "stop の直後はまだ消えていく途中")
	b._process(0.65)
	eq(_playing(b), [], "0.6 秒ほどで消える")
	eq(b.started, 2, "頭から始めたのは title と duel の 2 回")
	b.free()
	return true


func test_back_to_fading_track() -> bool:
	var b := _fresh()
	b.play("title")
	b.stop()
	b._process(0.3)
	b.play("title")
	eq(b.started, 1, "消えていく途中の曲を頼み直しても始め直さない")
	ok(absf(b._players["title"].volume_db - b._base_db()) < 0.01, "音量は目標に戻る")
	b._process(1.0)
	eq(_playing(b), ["title"], "消えずに鳴り続ける")
	b.free()
	return true
