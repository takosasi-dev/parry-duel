"""BGM 2 曲(title・duel)を合成して assets/bgm/<名前>.ogg(ffmpeg の libvorbis)と試聴ページ build/bgm_listen.html を書く。標準ライブラリだけ・乱数は種を固定。
1 周ぴったりに音を置いて尾は頭へ回し、響きと EQ は 2 周つないで掛けて後ろの 1 周を取る(継ぎ目なしで繰り返せる)。
効果音の合図(warn_red 約 100 Hz・parry 660 Hz・warn_white 1046 Hz)の帯域を削り、大きさは parry の BELOW_PARRY_LU 下に置く。
    python tools/gen_bgm.py
"""

import array
import base64
import json
import math
import random
import subprocess
import wave
from pathlib import Path

from gen_sfx import RATE, TAU, burst, hiss, lowpass, mix, norm, reverb, silence, thump, tone

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "bgm"
WORK = ROOT / "build" / "bgm"
PAGE = ROOT / "build" / "bgm_listen.html"
SFX = ROOT / "assets" / "sfx"
PEAK_MAX_DB = -11.5  # ogg にすると 1 dB ほど上がり得る。−10 dBFS を超えないように余裕を取る
BELOW_PARRY_LU = 16.0  # parry の瞬間の大きさ(K 特性・400 ms)より、これだけ小さく。聞こえ方でおよそ 1/3
OGG_QUALITY = 4  # libvorbis の -q:a。モノラルで 80 kbps 前後

SIZE = 4096  # 波形表の長さ


def hz(m):
    return 440.0 * 2 ** ((m - 69) / 12)


def rms(buf):
    return math.sqrt(sum(s * s for s in buf) / len(buf)) or 1e-12


def db(x):
    return 20 * math.log10(max(x, 1e-12))


def put(dst, src, at, gain=1.0):
    """src を dst の at サンプル目から足す。1 周の終わりを越えた分は頭へ回す(ループの継ぎ目で音が切れない)。"""
    n = len(dst)
    at %= n
    i = 0
    while i < len(src):
        k = min(len(src) - i, n - at)
        dst[at:at + k] = [d + s * gain for d, s in zip(dst[at:at + k], src[i:i + k])]
        i += k
        at = 0


def fade(buf, attack, release):
    """頭を attack 秒で上げ、尻を release 秒で下げる(どちらも余弦)。"""
    n = len(buf)
    a, r = max(1, int(attack * RATE)), max(1, int(release * RATE))
    for i in range(min(a, n)):
        buf[i] *= 0.5 - 0.5 * math.cos(math.pi * i / a)
    for i in range(max(0, n - r), n):
        buf[i] *= 0.5 - 0.5 * math.cos(math.pi * (n - 1 - i) / r)
    return buf


# ---- 音色 -------------------------------------------------------------------------------------------

_cache = {}


def table(amps):
    """1 周期の波形(amps[k-1] が k 倍音の大きさ)。補間のために頭の 1 点を尻に足しておく。"""
    key = ("table", amps)
    if key not in _cache:
        t = norm([sum(a * math.sin(TAU * k * j / SIZE) for k, a in enumerate(amps, 1)) for j in range(SIZE)])
        _cache[key] = t + t[:1]
    return _cache[key]


def bowed(amps, m, dur, attack, release, cents=(-7, 0, 6)):
    """弦の合奏のような持続音。少しずらした 3 本を重ねてうならせる(1 本だけの電子音っぽさを消す)。dur 秒の後、release 秒で消える。
    amps は波形の倍音の大きさ(タプル)。"""
    key = ("bowed", amps, m, round(dur, 4), attack, release, cents)
    if key in _cache:
        return _cache[key]
    tab = table(amps)
    n = int((dur + release) * RATE)
    out = [0.0] * n
    rng = random.Random(m * 131 + len(cents))
    for c in cents:
        inc = SIZE * hz(m) * 2 ** (c / 1200) / RATE
        p = rng.random() * SIZE
        for i in range(n):
            j = int(p)
            a = tab[j]
            out[i] += a + (tab[j + 1] - a) * (p - j)
            p += inc
            if p >= SIZE:
                p -= SIZE
    k = 1 / len(cents)
    a, d = int(attack * RATE), int(dur * RATE)
    for i in range(n):
        if i < a:
            e = 0.5 - 0.5 * math.cos(math.pi * i / a)
        elif i < d:
            e = 1.0
        else:
            e = 0.5 + 0.5 * math.cos(math.pi * (i - d) / (n - d))
        out[i] *= e * k
    _cache[key] = out
    return out


def pluck(m, dur, decay, bright, variant=0):
    """弦をはじく音(Karplus-Strong)。decay 秒で −60 dB。bright は最初のノイズを丸める Hz(小さいほど柔らかい)。
    dur 秒の後は 0.08 秒で消す。最大振幅は 1。"""
    key = ("pluck", m, round(dur, 4), decay, bright, variant)
    if key in _cache:
        return _cache[key]
    period = RATE / hz(m)
    size = int(period - 0.6)
    frac = period - 0.5 - size  # 平均の 0.5 サンプルの残りを全域通過で作る(音程を合わせる)
    c = (1 - frac) / (1 + frac)
    rng = random.Random(m * 977 + variant)
    line = lowpass([rng.random() * 2 - 1 for _ in range(size)], bright, 2)
    mean = sum(line) / size
    line = [x - mean for x in line]
    g = 0.001 ** (period / (decay * RATE))
    n = int((dur + 0.08) * RATE)
    out = [0.0] * n
    idx = 0
    prev = ax = ay = 0.0
    for i in range(n):
        x = line[idx]
        out[i] = x
        y = g * 0.5 * (x + prev)
        prev = x
        ay = c * (y - ay) + ax
        ax = y
        line[idx] = ay
        idx += 1
        if idx == size:
            idx = 0
    out = norm(fade(out, 0.0005, 0.08))
    _cache[key] = out
    return out


def drum(seed, dur, f0, f1, decay, modes, skin, amount):
    """膜の太鼓。音程の落ちる胴(つぶして倍音を足す)+ 円い膜の整数倍でない倍音 + 打った所のノイズ + 小さな部屋の響き。"""
    out = silence(dur)
    mix(out, thump(dur, f0, f1, decay, amount))
    for ratio, gain, dec in modes:
        tone(out, 0, dur, f0 * ratio, f1 * ratio, gain=gain, decay=dec, bend=0.45)
    mix(out, burst(seed, 0.04, skin, skin * 0.5, 0.8, 70, mode=0), gain=0.3)
    out = lowpass(out, 3000, 1)
    return norm(reverb(norm(out), 0.25, size=0.7, damp=0.45, wet=0.18))


def shaker(seed):
    """高い所だけのノイズの粒(7 kHz より上)。拍を刻む。合図の帯域には入らない。"""
    out = silence(0.07)
    hiss(random.Random(seed), out, 0, 0.07, 7000, 6500, 1.2, swell=0.35, mode=2)
    out = lowpass(norm(out), 12000, 1)
    return norm(reverb(norm(out), 0.12, size=0.6, damp=0.5, wet=0.2))


# ---- 仕上げ(響き・EQ) ---------------------------------------------------------------------------------

def hall(buf, size, damp, wet, predelay=0.02):
    """広い部屋の響き(櫛形 8 本 + 全域通過 4 本。Freeverb の長さ)。同じ長さで返す。wet は響きの RMS を元の RMS の何倍にするか。"""
    n = len(buf)
    pd = int(predelay * RATE)
    x = [0.0] * pd + buf[:n - pd]
    acc = [0.0] * n
    for d in (1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617):
        line = [0.0] * d
        idx = 0
        store = 0.0
        for i in range(n):
            y = line[idx]
            store = y * (1 - damp) + store * damp
            line[idx] = x[i] + store * size
            idx += 1
            if idx == d:
                idx = 0
            acc[i] += y
    for d in (556, 441, 341, 225):
        line = [0.0] * d
        idx = 0
        for i in range(n):
            b = line[idx]
            v = acc[i]
            line[idx] = v + b * 0.5
            acc[i] = b - v
            idx += 1
            if idx == d:
                idx = 0
    k = wet * rms(buf) / rms(acc)
    return [a + b * k for a, b in zip(buf, acc)]


def biquad(buf, b0, b1, b2, a1, a2):
    out = [0.0] * len(buf)
    x1 = x2 = y1 = y2 = 0.0
    for i, x in enumerate(buf):
        y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1, y2, y1 = x1, x, y1, y
        out[i] = y
    return out


def _rbj(kind, f, q=0.7071, gain_db=0.0):
    """RBJ の式の 2 次フィルター係数(b0, b1, b2, a1, a2)。"""
    w = TAU * f / RATE
    cs, al = math.cos(w), math.sin(w) / (2 * q)
    a = 10 ** (gain_db / 40)
    if kind == "lp":
        b, den = ((1 - cs) / 2, 1 - cs, (1 - cs) / 2), (1 + al, -2 * cs, 1 - al)
    elif kind == "hp":
        b, den = ((1 + cs) / 2, -(1 + cs), (1 + cs) / 2), (1 + al, -2 * cs, 1 - al)
    elif kind == "peak":
        b, den = (1 + al * a, -2 * cs, 1 - al * a), (1 + al / a, -2 * cs, 1 - al / a)
    else:  # 高域の棚
        sq = 2 * math.sqrt(a) * al
        b = (a * ((a + 1) + (a - 1) * cs + sq), -2 * a * ((a - 1) + (a + 1) * cs), a * ((a + 1) + (a - 1) * cs - sq))
        den = ((a + 1) - (a - 1) * cs + sq, 2 * ((a - 1) - (a + 1) * cs), (a + 1) - (a - 1) * cs - sq)
    return b[0] / den[0], b[1] / den[0], b[2] / den[0], den[1] / den[0], den[2] / den[0]


def filt(buf, kind, f, q=0.7071, gain_db=0.0):
    return biquad(buf, *_rbj(kind, f, q, gain_db))


# 効果音の合図の所を削る: warn_red(98/104 Hz)・parry(660/667 Hz)・warn_white(1046 Hz)。
# 2.2 kHz 付近の広い谷は、parry の 1.5 kHz・2.8 kHz の倍音と、合図の頭のノイズ(2.6〜3.5 kHz)の場所を空ける
CUTS = [(104, 1.6, -10.0), (665, 2.2, -12.0), (1060, 2.5, -12.0), (2200, 0.8, -6.0)]


def master(dry, size, damp, wet, top, extra=None):
    """1 周の dry に響きと EQ を掛ける。2 周つないで掛け、後ろの 1 周を取る(響きの尾と EQ の状態が頭に回った形になる)。
    extra(高い所だけの粒)は低域通過を通さずに後から足す。返り値は (仕上げ, EQ の前)。"""
    n = len(dry)
    x = hall(dry + dry, size, damp, wet)
    x = filt(x, "hp", 35)
    raw = x[n:]
    for f, q, g in CUTS:
        x = filt(x, "peak", f, q, g)
    x = filt(filt(x, "lp", top), "lp", top)
    out = x[n:]
    if extra is not None:
        out = [a + b for a, b in zip(out, extra)]
    return out, raw


# ---- 曲 ----------------------------------------------------------------------------------------------

def lines(chords, beat, cap):
    """和音の並び [(拍, 長さ, [音...])] を、声部ごとの音符 [(拍, 長さ, 音)] にする。同じ音が続けば cap 拍までつなぐ。"""
    out = []
    for v in range(len(chords[0][2])):
        cur = None
        for at, length, notes in chords:
            m = notes[v]
            if cur and cur[2] == m and cur[1] + length <= cap:
                cur[1] += length
            else:
                if cur:
                    out.append(tuple(cur))
                cur = [at, length, m]
        out.append(tuple(cur))
    return out


def title():
    """タイトル・メニュー用。72 BPM・4/4・8 小節(26.67 秒)。ニ短調(Dm9 → B♭maj9 → Gm7 → A7sus4 → A)。
    柔らかい合奏の和音 + 低い弦 + ハープのような撥弦の分散和音。後半は撥弦の歌が乗り、分散和音は低く薄くなる。"""
    beat = 60 / 72
    n = int(round(32 * beat * RATE))
    rng = random.Random(7)
    pad = tuple(1.0 / k ** 1.6 for k in range(1, 13))
    deep = (1.0, 0.22, 0.08)
    out = [0.0] * n

    # 和音の中で半音が低い所に長く並ばないように積む(A3 と B♭3 などは濁って聞こえる)
    chords = [
        (0, 4, [50, 53, 57, 64]), (4, 4, [50, 53, 57, 60]), (8, 4, [50, 53, 58, 62]),
        (12, 2, [52, 55, 57, 62]), (14, 2, [52, 55, 57, 61]),
        (16, 4, [50, 53, 57, 64]), (20, 4, [50, 53, 57, 64]), (24, 4, [50, 53, 58, 62]),
        (28, 2, [52, 55, 57, 62]), (30, 2, [52, 55, 57, 61]),
    ]
    for at, length, m in lines(chords, beat, 8):
        put(out, bowed(pad, m, length * beat, 0.7, 1.4), int(at * beat * RATE), 0.32)
    bass = [(0, 4, [38]), (4, 4, [34]), (8, 4, [31]), (12, 4, [33]), (16, 4, [38]), (20, 4, [34]), (24, 4, [31]), (28, 4, [33])]
    for at, length, m in lines(bass, beat, 4):
        put(out, bowed(deep, m, length * beat, 0.3, 1.0, (-3, 3)), int(at * beat * RATE), 0.3)

    def hit(m, t, dur, decay, bright, gain):
        jitter = rng.uniform(-0.006, 0.006)
        put(out, pluck(m, dur, decay, bright, rng.randrange(3)), int((t + jitter) * RATE), gain * rng.uniform(0.88, 1.0))

    arp = [
        [57, 62, 64, 65, 69, None, 65, 64], [62, 65, 69, None, 70, 69, 65, 62],
        [55, 58, 62, 65, 69, None, 65, 62], [57, 62, 64, 67, 64, 61, 64, None],
    ]
    for bar, notes in enumerate(arp):
        for slot, m in enumerate(notes):
            if m is not None:
                hit(m, (bar * 4 + slot / 2) * beat, 1.5, 1.6, 2200, 0.62 if slot == 0 else 0.5)
    low = [[50, 57, 53, 57], [50, 57, 53, 57], [50, 58, 55, 58], [52, 57, 55, 61]]
    for bar, notes in enumerate(low):
        for slot, m in enumerate(notes):
            hit(m, (16 + bar * 4 + slot) * beat, 1.8, 2.0, 1600, 0.42)
    melody = [
        (16, 1.5, 69), (17.5, 0.5, 67), (18, 1, 65), (19, 1, 64),
        (20, 2, 65), (22, 1, 62), (23, 1, 64),
        (24, 1.5, 74), (25.5, 0.5, 69), (26, 1, 70), (27, 1, 69),
        (28, 1, 67), (29, 1, 65), (30, 2, 64),
    ]
    for at, length, m in melody:
        hit(m, at * beat, max(1.4, length * beat + 0.6), 2.4, 3000, 0.62)
    return master(out, 0.88, 0.35, 0.6, 4500)


def duel():
    """対戦用。120 BPM・4/4・12 小節(24 秒)。ニ短調(Dm → E♭/D → Dm → B♭ → C → A)。
    太鼓の 3+3+2 の刻み + 背の打音 + 高いシェイカー + 低い弦の 16 分のはじき + 合奏の和音。5 小節目から合奏の歌、9 小節目から高い弦のトレモロ。"""
    beat = 0.5
    n = int(48 * beat * RATE)
    s16 = beat / 4
    rng = random.Random(11)
    out = [0.0] * n
    high = [0.0] * n
    strings = tuple(1.0 / k for k in range(1, 21))
    deep = (1.0, 0.3, 0.12)

    taikos = [drum(200 + i, 0.9, 84, 56, 5.0, [(1.59, 0.35, 14), (2.14, 0.22, 18), (2.65, 0.12, 24)], 900, 1.5) for i in range(3)]
    frames = [drum(210 + i, 0.35, 200, 140, 14.0, [(1.59, 0.3, 30), (2.14, 0.2, 40)], 1300, 1.3) for i in range(2)]
    shakers = [shaker(220 + i) for i in range(4)]

    def at(bar, slot, jitter=0.003):
        return int(((bar * 16 + slot) * s16 + rng.uniform(-jitter, jitter)) * RATE)

    for bar in range(12):
        hits = {0: 1.0, 6: 0.75, 12: 0.85}
        if bar in (3, 7):
            hits[14] = 0.6
        if bar == 11:
            hits = {0: 1.0, 6: 0.75, 8: 0.6, 10: 0.7, 12: 0.8, 13: 0.6, 14: 0.9, 15: 0.75}
        for slot, v in hits.items():
            put(out, taikos[rng.randrange(3)], at(bar, slot), 0.8 * v)
        for slot in ((12,) if bar < 4 else (4, 12)):
            put(out, frames[rng.randrange(2)], at(bar, slot), 0.32)
        for slot in range(16):
            v = (0.55, 0.3, 0.9, 0.3)[slot % 4] * (0.75 if bar < 4 else 1.0)
            put(high, shakers[rng.randrange(4)], at(bar, slot, 0.002), 0.11 * v * rng.uniform(0.85, 1.0))

    roots = [50, 50, 50, 50, 50, 50, 46, 48, 46, 48, 50, 45]
    accent = [1.0, 0.4, 0.5, 0.4, 0.55, 0.4, 0.9, 0.4, 0.5, 0.4, 0.55, 0.4, 0.9, 0.4, 0.6, 0.45]
    for bar, r in enumerate(roots):
        for slot, v in enumerate(accent):
            m = r + (12 if slot in (10, 14) else 0)
            put(out, pluck(m, 0.11, 0.35, 1400, rng.randrange(3)), at(bar, slot), 0.4 * v * rng.uniform(0.9, 1.0))

    # 3 小節目の E♭ は、下で鳴り続ける D(はじく弦・低い音)と半音で濁らないよう、上に積む(D3 と E♭4 は短 9 度)
    chords = [[50, 53, 57], [50, 53, 57], [55, 58, 63], [50, 53, 57], [50, 53, 57], [50, 53, 57],
              [50, 53, 58], [52, 55, 60], [50, 53, 58], [52, 55, 60], [50, 53, 57], [52, 57, 61]]
    for a, length, m in lines([(i * 4, 4, c) for i, c in enumerate(chords)], beat, 8):
        put(out, bowed(strings, m, length * beat, 0.5, 0.8), int(a * beat * RATE), 0.2)
    sub = [38, 38, 38, 38, 38, 38, 34, 36, 34, 36, 38, 33]
    for a, length, m in lines([(i * 4, 4, [r]) for i, r in enumerate(sub)], beat, 8):
        put(out, bowed(deep, m, length * beat, 0.05, 0.3, (-3, 3)), int(a * beat * RATE), 0.3)

    melody = [
        (16, 1, 57), (17, 1, 62), (18, 2, 65),
        (20, 1.5, 64), (21.5, 0.5, 62), (22, 1, 60), (23, 1, 57),
        (24, 2, 58), (26, 1, 62), (27, 1, 65),
        (28, 2, 67), (30, 1, 65), (31, 1, 64),
        (32, 1, 65), (33, 1, 70), (34, 2, 69),
        (36, 2, 67), (38, 1, 69), (39, 1, 67),
        (40, 2, 65), (42, 1, 64), (43, 1, 62),
        (44, 2, 61), (46, 1, 64), (47, 1, 57),
    ]
    for a, length, m in melody:
        for octave, gain in ((0, 0.42), (-12, 0.2)):
            put(out, bowed(strings, m + octave, length * beat, 0.07, 0.25), int(a * beat * RATE), gain)

    # 9 小節目からの高い弦のトレモロ。8 Hz(16 分)で揺らす。1 周 24 秒で 192 回なので、継ぎ目でも揺れがそろう
    for a, length, m in [(32, 4, 69), (36, 4, 67), (40, 8, 69)]:
        note = bowed(strings, m, length * beat, 0.4, 0.5)
        start = int(a * beat * RATE)
        note = [s * (1 - 0.7 * (0.5 + 0.5 * math.cos(TAU * 8 * (start + i) / RATE))) for i, s in enumerate(note)]
        put(out, note, start, 0.13)
    return master(out, 0.82, 0.4, 0.35, 5000, extra=high)


# (名前, 作り方, 試聴ページの説明)
TRACKS = [
    ("title", title, "タイトル・メニュー用。72 BPM、ニ短調、26.7 秒で 1 周。合奏の和音とハープのような撥弦"),
    ("duel", duel, "対戦用。120 BPM、ニ短調、24 秒で 1 周。太鼓の 3+3+2 の刻みと低い弦の 16 分"),
]


# ---- 確かめ(大きさ・帯域・継ぎ目) -------------------------------------------------------------------

def kweight(buf):
    """BS.1770 の K 特性に近い重み(高域の棚 +4 dB と 38 Hz の低域カット)。"""
    return filt(filt(buf, "shelf", 1500, 0.7071, 4.0), "hp", 38, 0.5)


def loudness(buf, window=None):
    """K 特性の大きさ(LUFS 相当)。window 秒を渡すと、その窓の中で一番大きい所(効果音の「瞬間の大きさ」)。"""
    k = kweight(buf)
    if window is None:
        ms = sum(s * s for s in k) / len(k)
    else:
        w = int(window * RATE)
        k = [0.0] * w + k + [0.0] * w
        acc = [0.0]
        for s in k:
            acc.append(acc[-1] + s * s)
        ms = max(acc[i + w] - acc[i] for i in range(0, len(k) - w, 441)) / w
    return -0.691 + 10 * math.log10(max(ms, 1e-20))


def band(buf, lo, hi, window=None):
    """lo〜hi Hz の大きさ(dBFS の RMS)。window 秒を渡すと、その窓で一番大きい所。"""
    x = filt(filt(filt(filt(buf, "hp", lo), "hp", lo), "lp", hi), "lp", hi)
    if window is None:
        return db(rms(x))
    w = int(window * RATE)
    acc = [0.0]
    for s in x:
        acc.append(acc[-1] + s * s)
    return db(math.sqrt(max(acc[i + w] - acc[i] for i in range(0, max(1, len(x) - w), 220)) / w))


def read_wav(path):
    with wave.open(str(path), "rb") as w:
        data = array.array("h", w.readframes(w.getnframes()))
    return [s / 32768 for s in data]


# 合図の帯域と、それを持つ効果音
BANDS = [("warn_red", 80, 130), ("parry", 560, 780), ("warn_white", 900, 1250)]


def ffmpeg(*args, out=False):
    done = subprocess.run(["ffmpeg", "-hide_banner", "-v", "error", "-y", *args], check=True,
                          stdout=subprocess.PIPE if out else None)
    return done.stdout


def encode(wav, ogg, *extra):
    # bitexact: Ogg のシリアル番号と ffmpeg の版の文字を入れない(同じ wav なら同じ ogg)
    ffmpeg("-i", str(wav), "-map_metadata", "-1", "-fflags", "+bitexact", "-flags:a", "+bitexact", *extra,
           "-c:a", "libvorbis", "-q:a", str(OGG_QUALITY), "-ac", "1", str(ogg))


def small(buf):
    """150 Hz より下を切る(ノート PC や電話の小さいスピーカーの代わり)。"""
    return filt(filt(buf, "hp", 150), "hp", 150)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    WORK.mkdir(parents=True, exist_ok=True)
    (WORK / ".gdignore").touch()  # 作業用の wav・ogg を Godot に取り込ませない
    sfx = {name: read_wav(SFX / (name + ".wav")) for name in ("parry", "warn_red", "warn_white")}
    target = loudness(sfx["parry"], 0.4) - BELOW_PARRY_LU
    parry_small = loudness(small(sfx["parry"]), 0.4)
    cues = {name: band(sfx[name], lo, hi, 0.1) for name, lo, hi in BANDS}
    info = []
    for name, make, desc in TRACKS:
        loop, raw = make()
        gain_loud = 10 ** ((target - loudness(loop)) / 20)
        gain_peak = 10 ** (PEAK_MAX_DB / 20) / max(abs(s) for s in loop)
        gain = min(gain_loud, gain_peak)
        pcm = array.array("h", (max(-32767, min(32767, round(s * gain * 32767))) for s in loop))
        wav = WORK / (name + ".wav")
        with wave.open(str(wav), "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(RATE)
            w.writeframes(pcm.tobytes())
        ogg = OUT / (name + ".ogg")
        encode(wav, ogg)
        encode(wav, WORK / (name + "_up.ogg"), "-af", "volume=6dB")  # 試聴ページの「+6 dB」(今より大きい側)

        # ここから下は、ogg をデコードし直した物で確かめる
        dec = array.array("h", ffmpeg("-i", str(ogg), "-f", "s16le", "-ac", "1", "-ar", str(RATE), "-", out=True))
        d = [s / 32768 for s in dec]
        steps = sorted(abs(dec[i] - dec[i - 1]) for i in range(1, len(dec)))
        seam = abs(dec[0] - dec[-1])
        e = int(0.02 * RATE)
        mid = len(pcm) // 2

        def err(lo, hi):
            return db(math.sqrt(sum((dec[i] - pcm[i]) ** 2 for i in range(lo, hi)) / (hi - lo)) / 32768)

        print("%s: %.2f 秒 (%d サンプル、元と同じ長さ: %s)  %d バイト  %s" % (
            name, len(dec) / RATE, len(dec), len(dec) == len(pcm), ogg.stat().st_size,
            "大きさで合わせた" if gain_loud <= gain_peak else "ピークの上限で止めた"))
        print("  ピーク %.1f dBFS  RMS %.1f dBFS  大きさ %.1f LUFS(parry の瞬間 %.1f LUFS より %.1f 小さい)" % (
            db(max(abs(s) for s in d)), db(rms(d)), loudness(d), target + BELOW_PARRY_LU, target + BELOW_PARRY_LU - loudness(d)))
        print("  継ぎ目: 尻→頭の差 %d、曲の中の隣どうしの差 中央 %d・99.9%% %d・最大 %d" % (
            seam, steps[len(steps) // 2], steps[int(len(steps) * 0.999)], steps[-1]))
        print("  圧縮の誤差: 頭 20 ms %.1f dB・尻 20 ms %.1f dB・中ほど %.1f dB(元の波形との差の RMS、dBFS)" % (
            err(0, e), err(len(pcm) - e, len(pcm)), err(mid, mid + e)))
        for cue, lo, hi in BANDS:
            got, before = band(d, lo, hi), band([s * gain for s in raw], lo, hi)
            print("  %4d〜%4d Hz: BGM %.1f dBFS(削る前 %.1f)、%s の 100 ms %.1f dBFS → 合図が %.1f dB 上" % (
                lo, hi, got, before, cue, cues[cue], cues[cue] - got))
        print("  150 Hz より下を切った時(小さいスピーカー): parry の瞬間より %.1f LU 小さい" % (parry_small - loudness(small(d))))
        info.append({"name": name, "desc": desc, "seconds": round(len(dec) / RATE, 2),
                     "data": base64.b64encode(ogg.read_bytes()).decode("ascii")})
    total = sum((OUT / (name + ".ogg")).stat().st_size for name, _, _ in TRACKS)
    print("合計 %d バイト(予算 1,200,000)" % total)
    write_page(info)
    print("試聴ページ:", PAGE)


def write_page(info):
    names = ["warn_white", "warn_red", "parry", "just", "whiff", "clank", "dodge", "hurt", "soft", "stagger", "counter", "shatter"]
    cards = "".join(
        '<section class="card"><h2>%s</h2><p>%s</p>'
        '<audio class="bgm" data-name="%s" controls loop preload="auto" src="../assets/bgm/%s.ogg"></audio>'
        '<div class="row"><button data-seam="%s">継ぎ目を聞く(ゲームと同じ繋ぎ方で、終わりの 4 秒前から)</button></div></section>'
        % (t["name"], t["desc"], t["name"], t["name"], t["name"]) for t in info)
    sfx = "".join('<button data-sfx="%s">%s</button>' % (n, n) for n in names)
    data = json.dumps({t["name"]: t["data"] for t in info})
    PAGE.write_text(PAGE_HTML.replace("__CARDS__", cards).replace("__SFX__", sfx).replace("__DATA__", data),
                    encoding="utf-8", newline="\n")


PAGE_HTML = """<!doctype html>
<html lang="ja">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>ParryDuel BGM の試聴</title>
<style>
:root { --bg: #0e1116; --card: #161b23; --line: #262d39; --text: #e6e6e6; --sub: #8b95a5; --on: #e6e6e6; }
* { box-sizing: border-box; }
body { margin: 0; background: var(--bg); color: var(--text); font: 15px/1.7 system-ui, sans-serif; }
main { max-width: 760px; margin: 0 auto; padding: 24px 16px 64px; }
h1 { font-size: 22px; margin: 0 0 8px; }
h2 { font-size: 17px; margin: 0 0 4px; }
p { margin: 0 0 12px; color: var(--sub); }
.card { background: var(--card); border: 1px solid var(--line); border-radius: 10px; padding: 16px; margin: 0 0 16px; }
audio { width: 100%; margin: 4px 0 8px; }
.row { display: flex; flex-wrap: wrap; gap: 8px; }
button { background: transparent; color: var(--text); border: 1px solid var(--line); border-radius: 8px; padding: 8px 12px; font: inherit; cursor: pointer; }
button:hover { border-color: var(--sub); }
button.on { background: var(--on); color: var(--bg); border-color: var(--on); }
#vol-db { color: var(--sub); margin-left: 8px; }
</style>
</head>
<body>
<main>
<h1>BGM の試聴</h1>
<p>BGM を鳴らしたまま、下の効果音のボタンを押すと重ねて聞けます。「対戦のように鳴らす」は、予告と弾く音を対戦に近い間隔で自動で鳴らします。<br>
効果音はいつもゲームの音量 100 と同じ大きさです。BGM の大きさだけを変えられます(25〜100 はゲームの設定と同じ式)。100 が今の作りで、聞こえ方で効果音のおよそ 1/3 です。「+6 dB」は今より大きくした物です。<br>
audio 要素の繰り返しは、ブラウザによって境い目に短い隙間が入ることがあります。ゲームの中と同じ繋ぎ方は「継ぎ目を聞く」で確かめてください。</p>
__CARDS__
<section class="card"><h2>BGM の大きさ</h2>
<div class="row"><button data-vol="25">25</button><button data-vol="50">50</button><button data-vol="75">75</button><button data-vol="100" class="on">100</button><button data-vol="up">+6 dB</button><span id="vol-db"></span></div></section>
<section class="card"><h2>効果音を重ねる</h2>
<div class="row" style="margin-bottom:8px"><button id="auto">対戦のように鳴らす</button></div>
<div class="row">__SFX__</div></section>
</main>
<script>
const DATA = __DATA__;
let ctx = null, gain = null, src = null, vol = "100", timer = null;
const audios = [...document.querySelectorAll("audio.bgm")];
const level = () => vol === "up" ? 2 : (Number(vol) / 100) ** 2;  // "up" は +6 dB

function stopSeam() {
  if (src) { src.stop(); src = null; }
  document.querySelectorAll("[data-seam]").forEach(b => b.classList.remove("on"));
}
audios.forEach(a => a.addEventListener("play", () => {
  stopSeam();
  audios.forEach(o => { if (o !== a) o.pause(); });
}));

async function seam(name, button) {
  const again = button.classList.contains("on");
  stopSeam();
  audios.forEach(a => a.pause());
  if (again) return;
  ctx = ctx || new AudioContext();
  if (!gain) { gain = ctx.createGain(); gain.connect(ctx.destination); }
  gain.gain.value = level();
  const bytes = Uint8Array.from(atob(DATA[name]), c => c.charCodeAt(0));
  const buffer = await ctx.decodeAudioData(bytes.buffer);
  src = ctx.createBufferSource();
  src.buffer = buffer;
  src.loop = true;
  src.connect(gain);
  src.start(0, Math.max(0, buffer.duration - 4));
  button.classList.add("on");
}
document.querySelectorAll("[data-seam]").forEach(b => b.addEventListener("click", () => seam(b.dataset.seam, b)));

// audio 要素は 1 より大きくできないので、+6 dB の時は大きくした ogg(build/bgm/<名前>_up.ogg)に差し替える
function setSrc(a, url) {
  if (a.getAttribute("src") === url) return;
  const t = a.currentTime, playing = !a.paused;
  a.src = url;
  a.addEventListener("loadedmetadata", () => { a.currentTime = t; if (playing) a.play(); }, { once: true });
}
function setVol(p) {
  vol = p;
  audios.forEach(a => {
    setSrc(a, p === "up" ? "bgm/" + a.dataset.name + "_up.ogg" : "../assets/bgm/" + a.dataset.name + ".ogg");
    a.volume = Math.min(1, level());
  });
  if (gain) gain.gain.value = level();
  document.querySelectorAll("[data-vol]").forEach(b => b.classList.toggle("on", b.dataset.vol === p));
  document.getElementById("vol-db").textContent = (20 * Math.log10(level())).toFixed(1) + " dB";
}
document.querySelectorAll("[data-vol]").forEach(b => b.addEventListener("click", () => setVol(b.dataset.vol)));
setVol("100");

const sfx = name => new Audio("../assets/sfx/" + name + ".wav").play();
document.querySelectorAll("[data-sfx]").forEach(b => b.addEventListener("click", () => sfx(b.dataset.sfx)));

// 対戦に近い並び(秒, 音)。白の予告 → 弾く、赤の予告 → 避ける、よろけ → 反撃
const SCRIPT = [[0, "warn_white"], [0.55, "parry"], [1.1, "warn_white"], [1.65, "just"], [2.4, "warn_red"], [2.95, "dodge"],
  [3.6, "warn_white"], [4.15, "parry"], [4.5, "warn_white"], [5.05, "parry"], [5.7, "warn_red"], [6.25, "dodge"],
  [6.8, "stagger"], [7.4, "counter"]];
function round() {
  SCRIPT.forEach(([t, name]) => setTimeout(() => { if (timer) sfx(name); }, t * 1000));
  timer = setTimeout(round, 8600);
}
document.getElementById("auto").addEventListener("click", e => {
  if (timer) { clearTimeout(timer); timer = null; e.target.classList.remove("on"); }
  else { e.target.classList.add("on"); round(); }
});
</script>
</body>
</html>
"""


if __name__ == "__main__":
    main()
