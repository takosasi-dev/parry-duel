# 調整値(仕様書 §9.9)。ゲームの進み方を決める数値は、ここにだけ置く(INV-8)。
# 時間はすべて tick(1/120 秒)の整数。
extends RefCounted

const TICK_HZ := 120
const MAX_STEPS_PER_FRAME := 8

const PARRY_WINDOW := 12  # 弾くの窓(±tick)
const JUST_WINDOW := 5  # ぴったりの窓(±tick)
const WHIFF_LOCK := 54  # 空振りと、赤を弾こうとした時の硬直(0.45 秒。0.3 秒では連打で敵 1 を倒せたので延ばした)
const DODGE_TICKS := 30  # 避けるの当たらない時間
const DODGE_LOCK := 54  # 避けるを押してから入力を捨てる時間
const HURT_TICKS := 60  # 当たった後、当たらない時間
const HURT_LOCK := 24  # 当たった後の硬直
const PUSH_TICKS := PARRY_WINDOW + 1  # 白い攻撃が線に届いてから当たるまで(押し込み)

const PLAYER_HP := 5
const BOSS_COUNT := 3
const BOSS_HP := 3  # 段階の数

const STAGGER_THRESHOLD := 8
const STAGGER_GAIN_PARRY := 1
const STAGGER_GAIN_JUST := 2
const STAGGER_TICKS := 180
const STAGGER_AFTER_RECOVER := 4
const COUNTER_FREEZE := 12
const RECOVER_TICKS := 240
const INTRO_TICKS := 120
const GAP_TICKS := 72
const RESUME_WAIT_TICKS := 120

const OFFSET_MIN := -12
const OFFSET_MAX := 12

# v0.2.0(依頼者の決定 2026-11-14): やさしい設定・型の練習・押したずれの表示
const SPEED_NORMAL := 100  # 攻撃の速さ(%)の基準
const SPEED_MIN := 50
const SPEED_MAX := 200
const EASY_SPEED := 80  # やさしい: 攻撃の速さ(%)。型の時間は 100/80 倍になる
const EASY_PARRY_WINDOW := 18  # やさしい: 弾くの窓(±tick、150 ms)。押し込みも窓 + 1 に伸びる
const EASY_JUST_WINDOW := 7  # やさしい: ぴったりの窓(±tick)
const SLOW_SPEED := 75  # 型の練習の「ゆっくり」
const NEAR_MISS_TICKS := 36  # 空振りの時、当たる tick がこれより近い白があれば「早すぎ・遅すぎ」を出す
const TENDENCY_MIN := 8  # 押す癖を出すのに要る数
const TENDENCY_MIN_TICKS := 2  # 平均のずれがこれ以上(約 17 ms)なら、判定のずれの直しを勧める
# v0.3.0: 終わらない連戦。3 体を繰り返し、1 周ごとに攻撃を速くする。上限は人が読める速さ(一番短い予兆が 125% で 29 tick)。
# 完璧に押す相手は 160% まで無傷で倒せる(2026-11-14 に測った)ので、上限を決めるのは人の側
const ENDLESS_STEP := 5  # 1 周(3 体)ごとに足す速さ(%)
const ENDLESS_MAX := 125  # 速さの上限(%)
const ENDLESS_HEAL := 1  # 体力は敵ごとに戻さず持ち越し、1 体倒すごとにこれだけ戻す
const ENDLESS_SEED_MUL := 0x27D4EB2D  # 周ごとに型の順を変える種
# v0.3.0: 実績
const ACH_JUST_STREAK := 10  # ぴったりを続ける数
const ACH_RED_DODGES := 20  # 赤を避けた数(合わせて)
const ACH_DRILL_PARRIES := 50  # 型の練習で弾いた数(合わせて)

# タイミング合わせ(§9.14)
const CALIB_COUNT := 8
const CALIB_SKIP := 2
const CALIB_MIN_VALID := 4
const CALIB_INTERVAL := 144
const CALIB_WINDUP := 48
const CALIB_TRAVEL := 96
const CALIB_MAX_DIFF := 36
const CALIB_LEAD := 60  # 最初の攻撃が出るまで
const CALIB_TAIL := 60  # 最後の当たる tick から終わりまで

# 型の検査(§9.7)と NFR-7
const MIN_WINDUP := 36
const MIN_TRAVEL := 42
const HOLD_MIN := 36
const HOLD_MAX := 96
const MIN_SPLIT_TRAVEL := 24
const MIN_CONTACT_GAP := 30
const RED_AFTER_GAP := 66
const MIN_TAIL := 24
const MIN_READ_TICKS := 78
const PATTERNS_PER_PHASE := [3, 3, 4]
const ATTACKS_MIN := [1, 2, 3]
const ATTACKS_MAX := [2, 3, 4]
const RESHUFFLE_TRIES := 4

# 種(§9.8・§9.13)
const FIXED_SEED := 1
const SEED_BOSS_MUL := 0x9E3779B1
const SEED_PHASE_MUL := 0x85EBCA6B
const DAY_SEED_MUL := 2654435761
const EPOCH_YEAR := 2026

# 位置(§9.1・§9.4)。論理の画面は 720×1280
const SCREEN_W := 720
const SCREEN_H := 1280
const BOSS_POS := Vector2(360, 420)
const LINE_Y := 1000
const LINE_X0 := 160
const LINE_X1 := 560
const PLAYER_POS := Vector2(360, 1090)
const ORIGIN := {"L": Vector2(200, 480), "R": Vector2(520, 480), "T": Vector2(360, 300)}
const CONTACT := {"L": Vector2(300, 1000), "R": Vector2(420, 1000), "T": Vector2(360, 1000)}
const WINDUP_PULL := 20.0

# 設定の既定値と範囲(§9.11)
const VOLUMES := [0, 25, 50, 75, 100]
const DEFAULT_VOLUME := 75
const DEFAULT_BGM_VOLUME := 75  # v0.3.0
