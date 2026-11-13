# 共有する文字を作る(仕様書 §9.12)。3 行で、最後は公開 URL。
# 入るのは 日付・受けた数・時間・ぴったりの数・やり直しの回数・URL だけ。
extends RefCounted

const S := preload("res://core/strings.gd")
const Rank := preload("res://core/rank.gd")
const Duel := preload("res://core/duel.gd")


# date は "2026-11-12"。first_today は「今日の3連戦」の 1 回目か。result は duel.result()。
static func build(date: String, mode: int, first_today: bool, result: Dictionary) -> String:
	var label := S.SHARE_FIXED
	if mode == Duel.Mode.DAILY:
		label = S.SHARE_DAILY_FIRST if first_today else S.SHARE_DAILY
	var n := int(result["hits"])
	var hits := S.hits(n) + ("(%s)" % S.UNHURT if n == 0 else "")
	return "%s %s(%s)\n%s / %s / %s / %s\n%s" % [
		S.GAME_NAME, date, label,
		hits, S.seconds(Rank.seconds_text(int(result["ticks"]))), S.justs(int(result["justs"])), S.retries(int(result["retries"])),
		S.SHARE_URL]
