# BGM の再生(autoload Bgm)。assets/bgm/<曲>.ogg を曲ごとのプレイヤーに読み、play で入れ替え・stop で消す。
# unlock() の前と音量 0 では鳴らさないが、頼まれた曲(current)は覚えておき、unlock や音量を戻した時に始める。
# 新しい曲は目標の音量のまま始め、古い曲だけを FADE 秒で下げて止める(Web で再生中の音量の変更が届かなくても無音で固まらない)。
extends Node

const TRACKS: Array = ["title", "duel"]
const FADE := 0.6  # 入れ替え・stop で古い曲を下げきるまでの秒

var dir := "res://assets/bgm/"
var volume := 75  # 0〜100(設定は 0・25・50・75・100)
var unlocked := false  # 最初の入力イベントで unlock() が真にする
var current := ""  # 頼まれている曲。"" は無し(テストが読む)
var started := 0  # 曲を頭から始めた回数(テストが読む)

var _players := {}  # 曲の名前 → AudioStreamPlayer(読めた曲だけ)
var _fading := {}  # 下げている途中のプレイヤー → 残りの割合(1 → 0)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # 一時停止中も鳴り続ける
	for track: String in TRACKS:
		var path := dir + track + ".ogg"
		if not ResourceLoader.exists(path):
			continue
		var stream := load(path) as AudioStream
		if stream == null:
			continue
		var player := AudioStreamPlayer.new()
		player.stream = stream  # 曲ごとに分けて最初に入れておく(入れ替えのたびに入れ直さない)
		add_child(player)
		_players[track] = player
	set_volume(volume)


func unlock() -> void:
	unlocked = true
	_start()


func play(track: String) -> void:
	if not _players.has(track) or track == current:
		return
	stop()
	current = track
	_start()


func stop() -> void:
	current = ""
	for player: AudioStreamPlayer in _players.values():
		if player.playing and not _fading.has(player):
			_fading[player] = 1.0


# 音量の式は Sfx と同じ(100 → 0 dB、75 → −5 dB、50 → −12 dB、25 → −24 dB)。0 は止める。
func set_volume(percent: int) -> void:
	volume = clampi(percent, 0, 100)
	if volume == 0:
		_fading.clear()
		for player: AudioStreamPlayer in _players.values():
			player.stop()
		return
	for player: AudioStreamPlayer in _players.values():
		if not _fading.has(player):
			player.volume_db = _base_db()
	_start()


func _base_db() -> float:
	return linear_to_db(pow(volume / 100.0, 2.0)) if volume > 0 else -80.0


# 今の曲を目標の音量で鳴らす(下げている途中なら戻す。鳴っていれば始め直さない)。
func _start() -> void:
	if not unlocked or volume <= 0 or current == "":
		return
	var player: AudioStreamPlayer = _players[current]
	_fading.erase(player)
	player.volume_db = _base_db()
	if not player.playing:
		player.play()
		started += 1


func _process(delta: float) -> void:
	for player: AudioStreamPlayer in _fading.keys():
		var left: float = _fading[player] - delta / FADE
		if left <= 0.0:
			_fading.erase(player)
			player.stop()
		else:
			_fading[player] = left
			player.volume_db = _base_db() + linear_to_db(left)
