# 効果音の再生(INTERFACES.md §2・仕様書 §9.15)。assets/sfx/*.wav を読み、プレイヤーを順繰りに使って重ねて鳴らす。
# 音量 0 か、unlock() の前なら鳴らさない(FR-29)。知らない名前・読めないファイルは音なしで続ける。
extends Node

const NAMES: Array = ["warn_white", "warn_red", "parry", "just", "whiff", "clank", "dodge", "hurt", "soft", "stagger", "counter", "shatter"]
# 同時に鳴らせる数。1 つのプレイヤーの max_polyphony で重ねると、pitch_scale を変えた時に鳴っている音まで動くので、分けて持つ
const VOICES := 8

var dir := "res://assets/sfx/"
var volume := 75  # 0〜100(設定は 0・25・50・75・100)
var unlocked := false  # 最初の入力イベントで unlock() が真にする
var played := 0  # 再生を始めた回数(テストが読む)
var last_pitch := 1.0  # 最後に鳴らした pitch_scale(テストが読む)

var _streams := {}
var _voices: Array[AudioStreamPlayer] = []
var _next := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # ポーズ中もボタンの音を鳴らす
	for sound_name: String in NAMES:
		var path := dir + sound_name + ".wav"
		if ResourceLoader.exists(path):
			var stream := load(path) as AudioStream
			if stream != null:
				_streams[sound_name] = stream
	for i in VOICES:
		var voice := AudioStreamPlayer.new()
		add_child(voice)
		_voices.append(voice)
	set_volume(volume)


func unlock() -> void:
	unlocked = true


# 25〜100 は 2 乗で dB に直す(100 → 0 dB、75 → −5 dB、50 → −12 dB、25 → −24 dB)。0 は play が鳴らさない。
func set_volume(percent: int) -> void:
	volume = clampi(percent, 0, 100)
	var db := linear_to_db(pow(volume / 100.0, 2.0)) if volume > 0 else -80.0
	for voice in _voices:
		voice.volume_db = db


func play(sound_name: String, semitones: int = 0) -> void:
	if not unlocked or volume <= 0 or not _streams.has(sound_name):
		return
	var voice := _voices[_next]
	_next = (_next + 1) % VOICES
	last_pitch = pow(2.0, semitones / 12.0)
	voice.stream = _streams[sound_name]
	voice.pitch_scale = last_pitch  # play() の前に入れる(Web の Sample 再生は、始める時の値を写す)
	voice.play()
	played += 1
