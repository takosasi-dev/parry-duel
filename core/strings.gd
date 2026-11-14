# 画面に出す文言(画面設計書 §9)。文言はここにだけ置く(INV-8)。
# {n} などの差し込みは下の関数で行う。
extends RefCounted

const GAME_NAME := "ParryDuel"
const VERSION := "v0.2.0"
const SHARE_URL := "https://takosasi-dev.github.io/parry-duel/"

# S1 タイトル
const TAGLINE := "当たる瞬間に、弾く"
const BTN_FIXED := "いつもの3連戦"
const BTN_DAILY := "今日の3連戦"
const BTN_PRACTICE := "練習"
const BTN_SETTINGS := "設定"
const NOT_PLAYED := "まだ遊んでいない"
const UNHURT := "無傷"
const SAVE_BROKEN := "保存を読めなかったので、記録を初めからにした"
const DATA_BROKEN := "型のデータが壊れている"

# S2 対戦
const PHASE := "段階"
const STAGGER := "よろけ"
const HP := "体力"
const DODGE := "避ける"
const PARRY := "弾く"
const TEACH_PARRY := "白が線に届く瞬間に、右半分を押す"
const TEACH_DODGE := "赤は弾けない。左半分を押して避ける"
const TEACH_FREE := "今は減らない"
const JUST := "ぴったり"
const NOW := "いま!"
const COUNTER_HINT := "右半分を押して反撃"
# 画面の下の、左右の半分の案内(マウス・タッチは半分を押す。キーは Z / Space)
const KEYS_DODGE := "左半分 / Z"
const KEYS_PARRY := "右半分 / Space"
# 一時停止の画面に出す、操作の一覧
const HOW_PARRY := "弾く: 画面の右半分 / Space・X"
const HOW_DODGE := "避ける: 画面の左半分 / Z・左Shift"
const HOW_COUNTER := "敵がよろけたら、弾くで反撃"
const BTN_RETRY := "この敵からやり直す"
const BTN_TITLE := "タイトルへ"

# S3 合間
const SO_FAR := "ここまで"
const BTN_NEXT := "次の敵へ"

# S4 結果
const RESULT_WIN := "3 体を倒した"
const PRACTICE_LOSE := "練習: 負け"
const NEW_RECORD := "新しい記録"
const FIRST_RECORD := "初めての記録"
const SAME_AS_BEST := "最高と同じ"
const BTN_AGAIN := "もう1回"
const BTN_COPY := "コピー"
const COPIED := "コピーを試した。貼れない時は枠から写す"
const SAVE_FAILED := "このブラウザでは記録を残せない"

# S5 設定
const SETTINGS := "設定"
const VOLUME := "音量"
const SHAKE := "画面の揺れ"
const REDUCE_FLASH := "点滅を弱める"
const OFFSET := "判定のずれ"
const OFFSET_HINT := "押すのが遅れて外れる時は + にする"
const BTN_CALIB := "タイミング合わせで測る"
const ON := "入"
const OFF := "切"
const BTN_BACK := "戻る"

# S6 タイミング合わせ
const CALIB := "タイミング合わせ"
const CALIB_GUIDE := "頭が線に届く瞬間に、右半分を押す(8 回)"
const CALIB_DIFF := "今の差"
const CALIB_FAILED := "測れなかった。もう一度測る"
const BTN_USE := "この値を使う"
const BTN_REMEASURE := "もう一度測る"
const BTN_ZERO := "0 に戻す"

# S7 一時停止
const PAUSED := "一時停止"
const BTN_RESUME := "続ける"

# 共有する文字(§9.12)
const SHARE_DAILY_FIRST := "今日の3連戦・1回目"
const SHARE_DAILY := "今日の3連戦"
const SHARE_FIXED := "いつもの3連戦"

# v0.2.0: やさしい設定・押したずれ・型の練習・ゲームパッド
const EASY := "やさしい"
const EASY_ON := "やさしい設定で遊ぶ(記録は別)"
const EASY_HINT := "弾く窓が広く、攻撃が遅くなる。記録は別に残す"
const SHOW_DIFF := "押したずれを出す"
const TOO_EARLY := "早すぎ"
const TENDENCY_OK := "押す癖: ほぼ合っている"
const OFFSET_APPLIED := "判定のずれを変えた"
const BTN_DRILL := "型の練習"
const DRILL := "型の練習"
const DRILL_GUIDE := "繰り返し練習する型を選ぶ。体力は減らない"
const SPEED := "速さ"
const SPEED_NORMAL := "ふつう"
const SPEED_SLOW := "ゆっくり"
const HOW_PAD := "パッド: A・RB で弾く / B・LB で避ける / Start で一時停止"


static func boss_of(n: int, total: int) -> String:
	return "敵 %d/%d" % [n, total]


static func boss_n(n: int) -> String:
	return "敵 %d" % n


static func hits(n: int) -> String:
	return "受けた数 %d" % n


# 受けた数。0 の時は「無傷」。
static func hits_or_unhurt(n: int) -> String:
	return UNHURT if n == 0 else hits(n)


static func seconds(sec_text: String) -> String:
	return "%s秒" % sec_text


static func best_line(n: int, sec_text: String) -> String:
	return "最高 %s / %s" % [hits_or_unhurt(n), seconds(sec_text)]


static func daily_line(first_hits: int, best_hits: int) -> String:
	return "1回目 %s / 今日の最高 %s" % [hits_or_unhurt(first_hits), hits_or_unhurt(best_hits)]


static func boss_beaten(n: int) -> String:
	return "敵 %d を倒した" % n


static func so_far(n: int, sec_text: String) -> String:
	return "%s  %s / %s" % [SO_FAR, hits_or_unhurt(n), seconds(sec_text)]


static func justs(n: int) -> String:
	return "%s %d" % [JUST, n]


static func retries(n: int) -> String:
	return "やり直し %d" % n


static func practice_win(n: int) -> String:
	return "練習: 敵 %d を倒した" % n


static func diff_fewer_hits(n: int) -> String:
	return "最高より 受けた数 −%d(%s)" % [n, NEW_RECORD]


static func diff_faster(sec_text: String) -> String:
	return "最高と同じ受けた数、時間 −%s秒(%s)" % [sec_text, NEW_RECORD]


static func diff_more_hits(n: int) -> String:
	return "最高まで 受けた数 +%d" % n


static func diff_slower(sec_text: String) -> String:
	return "最高まで 時間 +%s秒" % sec_text


# +17 ms のように符号をつける。
static func signed_ms(ms: int) -> String:
	return ("+%d ms" % ms) if ms > 0 else ("−%d ms" % -ms) if ms < 0 else "0 ms"


static func calib_now(ms: int) -> String:
	return "%s %s" % [CALIB_DIFF, signed_ms(ms)]


static func calib_result(ms: int) -> String:
	return "結果: %s がよさそう" % signed_ms(ms)


static func calib_count(n: int, total: int) -> String:
	return "%d / %d" % [n, total]


static func volume(v: int) -> String:
	return "%d" % v


# 押したずれ(ms、負 = 早い)。「早い 25 ms」「遅い 42 ms」。
static func press_diff(ms: int) -> String:
	return ("早い %d ms" % -ms) if ms < 0 else ("遅い %d ms" % ms)


# 押す癖の 1 行。mean_ms は平均(負 = 早い)、n は数。
static func tendency(mean_ms: int, n: int) -> String:
	if absi(mean_ms) < 5:
		return "%s(%d 回)" % [TENDENCY_OK, n]
	return "押す癖: 平均 %d ms %s(%d 回)" % [absi(mean_ms), "早い" if mean_ms < 0 else "遅い", n]


static func apply_offset(ms: int) -> String:
	return "判定のずれを %s にする" % signed_ms(ms)


# 型の練習の型の名前。「敵 2・段階 3・B」。
static func drill_name(boss: int, phase: int, letter: String) -> String:
	return "敵 %d・%s %d・%s" % [boss, PHASE, phase, letter]


static func phase_n(n: int) -> String:
	return "%s %d" % [PHASE, n]


static func drill_stats(parries: int, justs: int) -> String:
	return "弾いた %d / %s %d" % [parries, JUST, justs]
