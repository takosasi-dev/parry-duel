"""効果音 12 個(INTERFACES.md §2)を合成して assets/sfx/<名前>.wav に書く。標準ライブラリだけ・乱数は種を固定(何度回しても同じバイト列)。
16bit PCM・モノラル・44100 Hz。音ごとに最大振幅を決めて釣り合いを取る(一番大きい counter が -3 dBFS)。
    python tools/gen_sfx.py
"""

import math
import random
import struct
import wave
from pathlib import Path

OUT = Path(__file__).resolve().parents[1] / "assets" / "sfx"
RATE = 44100
TAU = 2 * math.pi
RELEASE = int(0.003 * RATE)  # 部品の尻を切る時の短い下り
HEAD_FADE = int(0.0005 * RATE)  # ファイルの頭。打つ音の立ち上がりを 1 ms 以内に保つ
TAIL_FADE = int(0.006 * RATE)  # ファイルの尻


def silence(dur):
    return [0.0] * int(dur * RATE)


def tone(buf, at, dur, f0, f1=None, gain=1.0, decay=0.0, attack=0.0, bend=1.0):
    """正弦波 1 本を buf に足す。f0→f1 へ指数で滑り(bend が 1 より小さいと前半で大きく動く)、exp(-decay*t) で消える。"""
    f1 = f1 or f0
    start = int(at * RATE)
    n = min(int(dur * RATE), len(buf) - start)
    phase = 0.0
    for i in range(n):
        t = i / RATE
        e = gain * math.exp(-decay * t) * min(1.0, (n - i) / RELEASE)
        if t < attack:
            e *= t / attack
        buf[start + i] += e * math.sin(phase)
        phase += TAU * f0 * (f1 / f0) ** ((i / n) ** bend) / RATE


def hiss(rng, buf, at, dur, f0, f1, q, gain=1.0, decay=0.0, attack=0.0, swell=0.0, mode=1):
    """帯域を f0→f1 へ動かしたノイズを buf に足す(状態変数フィルター)。mode: 0 低域・1 帯域・2 高域。
    swell を入れると音量が山なりになる(小さいほど山が前に寄る)。入れなければ exp(-decay*t)。"""
    start = int(at * RATE)
    n = min(int(dur * RATE), len(buf) - start)
    low = band = 0.0
    for i in range(n):
        x = i / n
        t = i / RATE
        f = 2 * math.sin(math.pi * min(f0 * (f1 / f0) ** x, 7000.0) / RATE)
        damp = min(1.0 / q, 2.0 / f - 0.5 * f - 0.05)  # これを超えるとフィルターが発散する
        high = rng.random() * 2 - 1 - low - damp * band
        band += f * high
        low += f * band
        if swell:
            e = math.sin(math.pi * x ** swell)
        else:
            e = math.exp(-decay * t) * min(1.0, (n - i) / RELEASE)
        if t < attack:
            e *= t / attack
        buf[start + i] += gain * e * (low, band, high)[mode]


def norm(buf):
    """最大振幅を 1 にそろえる。部品を重ねる時の gain を、聞こえる大きさの比として書けるようにする。"""
    peak = max(abs(s) for s in buf)
    for i in range(len(buf)):
        buf[i] /= peak
    return buf


def drive(buf, amount):
    """tanh でつぶして倍音を足す。低い音が小さいスピーカーでも聞こえるようにする。"""
    for i in range(len(buf)):
        buf[i] = math.tanh(buf[i] * amount)
    return buf


def wobble(buf, r0, r1, depth):
    """音量を r0→r1 Hz で揺らす(きしみ)。"""
    n = len(buf)
    phase = 0.0
    for i in range(n):
        buf[i] *= 1 - depth * (0.5 + 0.5 * math.sin(phase)) ** 2
        phase += TAU * r0 * (r1 / r0) ** (i / n) / RATE
    return buf


def mix(dst, src, at=0.0, gain=1.0):
    start = int(at * RATE)
    for i in range(min(len(src), len(dst) - start)):
        dst[start + i] += src[i] * gain


def burst(seed, dur, f0, f1, q, decay, mode=1):
    """打撃の頭に置く、短いノイズ。"""
    buf = silence(dur)
    hiss(random.Random(seed), buf, 0, dur, f0, f1, q, decay=decay, mode=mode)
    return norm(buf)


def parry():
    # 金属の棒の倍音(1 : 2.76 : 5.4 : 8.9)。上の倍音ほど小さく速く消して、+12 半音でも刺さらないようにする。
    # 5 度上(1.5)で音に芯を足し、2.76 のすぐ隣(2.79)とのうなりで金属のざらつきを出す
    out = silence(0.115)
    ring = silence(0.115)
    for ratio, gain, decay in [(1.0, 1.0, 26), (1.5, 0.3, 34), (2.76, 0.55, 40), (2.79, 0.3, 40), (5.4, 0.26, 70), (8.9, 0.05, 130)]:
        tone(ring, 0, 0.115, 1245 * ratio, gain=gain, decay=decay)
    mix(out, norm(ring))
    mix(out, burst(11, 0.006, 4200, 4200, 0.8, 500), gain=0.5)
    tone(out, 0, 0.03, 620, 480, gain=0.3, decay=110)  # 当たりの重み
    return out


def just():
    # 整った倍音の澄んだ鐘 + 近い高さの 2 本ずつがうなる「きらめき」が尾を引く + 少し遅れて 1 オクターブ上が乗る
    out = silence(0.28)
    bell = silence(0.28)
    for ratio, gain, decay in [(1.0, 1.0, 16), (2.0, 0.5, 20), (3.01, 0.32, 28), (4.2, 0.1, 42)]:
        tone(bell, 0, 0.28, 1568 * ratio, gain=gain, decay=decay)
    mix(out, norm(bell))
    glint = silence(0.24)  # +12 半音で 2 倍の高さになっても 9 kHz を超えない所に置く
    for f, gain in [(3520, 1.0), (3552, 0.9), (4186, 0.6), (4229, 0.55)]:
        tone(glint, 0, 0.24, f, gain=gain, decay=7, attack=0.012)
    mix(out, norm(glint), at=0.03, gain=0.45)
    tone(out, 0.045, 0.2, 3136, gain=0.3, decay=26, attack=0.002)
    mix(out, burst(21, 0.006, 5200, 5200, 0.8, 500), gain=0.45)
    return out


def counter():
    # 低い衝撃(88→56 Hz をつぶして倍音を足す)+ 擦れ上がる金属 + 刃の鳴り + 下がっていくノイズの払い
    out = silence(0.46)
    thump = silence(0.42)
    tone(thump, 0, 0.42, 88, 56, decay=8, bend=0.5)
    tone(thump, 0, 0.25, 176, 100, gain=0.7, decay=14, bend=0.5)
    mix(out, drive(norm(thump), 2.2), gain=0.8)
    tone(out, 0, 0.18, 250, 140, gain=0.7, decay=18, bend=0.5)  # 胴。小さいスピーカーでも重さが残る
    mix(out, burst(31, 0.014, 2600, 1800, 0.8, 260))
    scrape = silence(0.09)
    hiss(random.Random(32), scrape, 0, 0.09, 2400, 6600, 5.0, decay=14, attack=0.003)
    mix(out, norm(scrape), gain=0.6)
    blade = silence(0.22)
    for ratio, gain, decay in [(1.0, 1.0, 13), (1.59, 0.7, 16), (2.71, 0.45, 22)]:
        tone(blade, 0, 0.22, 2040 * ratio, 2040 * ratio * 0.985, gain=gain, decay=decay)
    mix(out, norm(blade), gain=0.45)
    sweep = silence(0.4)
    hiss(random.Random(33), sweep, 0, 0.4, 5200, 600, 1.1, swell=0.4)
    mix(out, norm(sweep), at=0.02, gain=0.9)
    return drive(norm(out), 2.2)  # 頭の山をつぶして、そのぶん全体を太くする(尻は小さいのでほぼ素通り)


def stagger():
    # 鋸っぽい倍音のうなりが 290→105 Hz へ落ち、揺れがだんだん遅くなる(きしみ)。頭に、落ちる笛で「いま!」
    out = silence(0.34)
    growl = silence(0.34)
    for k in range(1, 11):
        tone(growl, 0, 0.34, 290 * k, 105 * k, gain=1 / k, decay=4, bend=0.7)
    mix(out, norm(wobble(growl, 60, 22, 0.75)))
    grind = silence(0.34)  # 同じ揺れで擦れるノイズ。電子音っぽさを消す
    hiss(random.Random(42), grind, 0, 0.34, 1800, 500, 2.0, decay=5)
    mix(out, norm(wobble(grind, 60, 22, 0.75)), gain=0.35)
    tone(out, 0, 0.16, 1480, 520, gain=0.5, decay=16, bend=0.6)
    mix(out, burst(41, 0.012, 2000, 1500, 0.9, 300), gain=0.6)
    tone(out, 0, 0.12, 120, 62, gain=0.4, decay=20)
    return out


def shatter():
    # 割れる頭 + 低い崩れ + 石の粒 22 個(始めに密、あとはまばらに小さく)
    rng = random.Random(51)
    out = silence(0.62)
    mix(out, burst(52, 0.02, 3200, 1400, 0.8, 180), gain=0.8)
    tone(out, 0, 0.12, 130, 64, gain=0.5, decay=28)
    rumble = silence(0.55)
    hiss(rng, rumble, 0, 0.55, 900, 300, 0.8, decay=6, mode=0)
    mix(out, norm(rumble), gain=0.35)
    for _ in range(22):
        u = rng.random()
        dur = 0.014 + 0.03 * rng.random()
        fc = 600 * 6 ** rng.random()
        grain = silence(dur)
        hiss(rng, grain, 0, dur, fc, fc * 0.8, 4 + 4 * rng.random(), decay=3 / dur)
        mix(out, norm(grain), at=0.015 + 0.5 * u ** 1.5, gain=(0.75 - 0.5 * u) * (0.6 + 0.4 * rng.random()))
    return out


def hurt():
    # 低い打撃。−7 半音(player_down)でも小さいスピーカーで消えないように、中域の胴と叩く音を重ねる
    out = silence(0.16)
    body = silence(0.16)
    tone(body, 0, 0.16, 185, 82, decay=20, bend=0.5)
    tone(body, 0, 0.12, 330, 190, gain=0.8, decay=26, bend=0.5)
    mix(out, drive(norm(body), 2.0), gain=0.7)
    tone(out, 0, 0.07, 620, 360, gain=0.8, decay=38, bend=0.5)
    mix(out, burst(61, 0.04, 1800, 800, 0.8, 90, mode=0))
    return out


def whiff():
    # 空を切る「スッ」。帯域が上がっていくノイズを 2 枚
    out = silence(0.15)
    cut = silence(0.15)
    hiss(random.Random(71), cut, 0, 0.15, 1300, 4200, 1.6, swell=0.55)
    mix(out, norm(cut))
    air = silence(0.15)
    hiss(random.Random(72), air, 0, 0.15, 2200, 6000, 2.5, swell=0.55)
    mix(out, norm(air), gain=0.3)
    return out


def clank():
    # 鈍い「ゴッ」。低く詰まった倍音がすぐ消える。高い成分は入れない
    out = silence(0.15)
    bar = silence(0.15)
    for ratio, gain, decay in [(1.0, 1.0, 34), (1.47, 0.7, 42), (2.09, 0.45, 55), (2.56, 0.3, 70)]:
        tone(bar, 0, 0.15, 420 * ratio, gain=gain, decay=decay)
    mix(out, norm(bar))
    mix(out, burst(91, 0.02, 900, 500, 0.8, 160, mode=0), gain=0.7)
    tone(out, 0, 0.08, 150, 95, gain=0.4, decay=35)
    return out


def dodge():
    # 風の「シュッ」。whiff より低く長く、上がる風と下がる風を重ねて通り過ぎる感じにする
    out = silence(0.22)
    up = silence(0.22)
    hiss(random.Random(81), up, 0, 0.22, 500, 2200, 1.5, swell=0.7, mode=0)
    mix(out, norm(up))
    down = silence(0.22)
    hiss(random.Random(82), down, 0, 0.22, 2600, 800, 1.5, swell=0.7, mode=0)
    mix(out, norm(down), gain=0.5)
    return out


def soft():
    # 木を軽く叩いたようなクリック
    out = silence(0.06)
    tone(out, 0, 0.06, 940, 860, decay=75)
    tone(out, 0, 0.03, 2260, gain=0.3, decay=160)
    mix(out, burst(101, 0.003, 3000, 3000, 0.8, 900), gain=0.25)
    return out


def warn_white():
    # 澄んだ音が G5→C6 へ上がる。立ち上がりを丸めて主張を抑える
    out = silence(0.09)
    tone(out, 0, 0.09, 784, 1047, decay=14, attack=0.006, bend=0.6)
    tone(out, 0, 0.09, 1568, 2094, gain=0.18, decay=22, attack=0.006, bend=0.6)
    return out


def warn_red():
    # 低く濁った 2 連。増 4 度(196 と 277 Hz)と、近い 2 本(392 と 415 Hz)のうなりで濁らせる
    out = silence(0.105)
    for at in (0.0, 0.058):
        for f, gain in [(196, 0.5), (277, 0.6), (392, 0.7), (415, 0.6), (588, 0.4), (831, 0.25)]:
            tone(out, at, 0.044, f, f * 0.94, gain=gain, decay=22, attack=0.003)
    return out


# (名前, 作り方, 最大振幅 dBFS)。counter が一番大きく、parry / just は中、予告は小。
# 値は、A 特性を掛けた 30 ms の大きさを比べて決めた(低い音は、同じ大きさに聞こえるのに振幅が要る)
SOUNDS = [
    ("warn_white", warn_white, -20), ("warn_red", warn_red, -14), ("parry", parry, -7), ("just", just, -11),
    ("whiff", whiff, -16), ("clank", clank, -7), ("dodge", dodge, -14), ("hurt", hurt, -4),
    ("soft", soft, -13), ("stagger", stagger, -6), ("counter", counter, -3), ("shatter", shatter, -5),
]


def finish(buf, peak_db):
    """頭と尻を短くフェードしてから、最大振幅を peak_db に合わせて 16bit にする。"""
    n = len(buf)
    faded = [s * min(1.0, i / HEAD_FADE, (n - 1 - i) / TAIL_FADE) for i, s in enumerate(buf)]
    scale = 10 ** (peak_db / 20) * 32767 / max(abs(s) for s in faded)
    return struct.pack("<%dh" % n, *(round(s * scale) for s in faded))


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for name, make, peak_db in SOUNDS:
        data = finish(make(), peak_db)
        with wave.open(str(OUT / (name + ".wav")), "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(RATE)
            w.writeframes(data)
        print("%-10s %4d ms  %5.1f dBFS" % (name, len(data) * 500 // RATE, peak_db))


if __name__ == "__main__":
    main()
