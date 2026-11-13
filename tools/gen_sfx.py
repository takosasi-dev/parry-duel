"""効果音 12 個(INTERFACES.md §2)を合成して assets/sfx/<名前>.wav に書く。標準ライブラリだけ・乱数は種を固定(何度回しても同じバイト列)。
16bit PCM・モノラル・44100 Hz。音ごとに最大振幅を決めて釣り合いを取る(一番大きい counter が -1 dBFS)。
v0.1.1: 「軽い・電子音っぽい・耳ざわり・小さい」を受けて、低い胴・部屋の響き・高域を丸める処理を足し、全体を大きくした。
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


def lowpass(buf, fc, passes=2):
    """1 次の低域通過を passes 回。耳に刺さる高い所を丸める。"""
    a = 1 - math.exp(-TAU * fc / RATE)
    for _ in range(passes):
        y = 0.0
        for i in range(len(buf)):
            y += a * (buf[i] - y)
            buf[i] = y
    return buf


def reverb(buf, tail, size=0.7, damp=0.4, wet=0.2):
    """小さな部屋の響き(櫛形 4 本 + 全域通過 2 本。Freeverb の形)。尻に tail 秒を足し、そこで静かに消す。
    合成した音の「乾いた電子音っぽさ」を消すのが目的。wet は響きの最大振幅を、元の音の最大振幅の何倍にするか。"""
    n = len(buf) + int(tail * RATE)
    dry = buf + [0.0] * (n - len(buf))
    out = [0.0] * n
    for d in (1116, 1188, 1277, 1356):
        line = [0.0] * d
        idx = 0
        store = 0.0
        for i in range(n):
            y = line[idx]
            store = y * (1 - damp) + store * damp
            line[idx] = dry[i] + store * size
            idx = (idx + 1) % d
            out[i] += y
    for d in (556, 441):
        line = [0.0] * d
        idx = 0
        for i in range(n):
            b = line[idx]
            x = out[i]
            line[idx] = x + b * 0.5
            out[i] = b - x
            idx = (idx + 1) % d
    k = wet * max(abs(s) for s in dry) / max(abs(s) for s in out)
    m = len(buf)
    for i in range(n):
        fade = 1.0 if i < m else 0.5 + 0.5 * math.cos(math.pi * (i - m) / (n - m))
        out[i] = (dry[i] + out[i] * k) * fade
    return out


def thump(dur, f0, f1, decay, amount=2.2):
    """低い胴(f0→f1 へ落ちる正弦 + 2 倍音)をつぶして倍音を足す。小さいスピーカーでも重さが残る。"""
    body = silence(dur)
    tone(body, 0, dur, f0, f1, decay=decay, bend=0.45)
    tone(body, 0, dur * 0.6, f0 * 2, f1 * 2, gain=0.5, decay=decay * 1.5, bend=0.45)
    return drive(norm(body), amount)


def _metal(dur, f0, parts):
    """金属の棒・板の倍音(整数倍でない)。parts は (比, 大きさ, 消える速さ)。近い比を 2 本置くと、うなりで金属のざらつきが出る。"""
    buf = silence(dur)
    for ratio, gain, decay in parts:
        tone(buf, 0, dur, f0 * ratio, gain=gain, decay=decay)
    return norm(buf)


def _parry_dry():
    # 「カッ」(頭のノイズ)+「ドッ」(胴)+「キィン」(金属)。金属の土台は 660 Hz で、+12 半音でも刺さらない高さにする
    out = silence(0.34)
    mix(out, burst(11, 0.012, 2600, 1700, 1.2, 320), gain=0.55)
    mix(out, thump(0.12, 170, 95, 30), gain=0.8)
    metal = _metal(0.34, 660, [(1.0, 1.0, 13), (1.011, 0.6, 13), (2.32, 0.5, 21), (2.355, 0.28, 23), (4.25, 0.2, 38), (6.63, 0.07, 70)])
    mix(out, metal, gain=0.7)
    return lowpass(out, 6500)


def parry():
    return reverb(_parry_dry(), 0.22, size=0.68, damp=0.45, wet=0.2)


def just():
    # 弾く音を太くして、澄んだ鐘(880 Hz、整数倍)を長く重ねる。最後に高い所がかすかにきらめく
    out = silence(0.55)
    mix(out, _parry_dry())
    mix(out, thump(0.16, 130, 70, 22), gain=0.5)
    bell = _metal(0.55, 880, [(1.0, 1.0, 7), (2.0, 0.45, 9), (3.0, 0.25, 13), (4.2, 0.08, 20)])
    mix(out, bell, at=0.004, gain=0.6)
    glint = silence(0.4)
    for f, gain in [(2637, 1.0), (2660, 0.9)]:
        tone(glint, 0, 0.4, f, gain=gain, decay=8, attack=0.015)
    mix(out, norm(glint), at=0.03, gain=0.16)
    lowpass(out, 7000)
    return reverb(out, 0.32, size=0.74, damp=0.4, wet=0.26)


def counter():
    # 低い衝撃(70→38 Hz を長く)+ 中域の割れ + 擦れ上がる刃 + 鳴り残る刃 + 下がっていく崩れ。響きは大きめ
    out = silence(0.66)
    mix(out, thump(0.6, 72, 38, 6, 2.6), gain=0.95)
    mix(out, burst(31, 0.03, 1800, 900, 0.9, 120), gain=0.8)
    scrape = silence(0.16)
    hiss(random.Random(32), scrape, 0, 0.16, 1500, 4500, 4.0, swell=0.3)
    mix(out, norm(scrape), gain=0.4)
    blade = _metal(0.45, 520, [(1.0, 1.0, 7), (1.012, 0.7, 7), (2.32, 0.45, 12), (4.25, 0.15, 22)])
    mix(out, blade, gain=0.42)
    crash = silence(0.6)
    hiss(random.Random(33), crash, 0, 0.6, 2400, 300, 0.8, decay=7, mode=0)
    mix(out, norm(crash), at=0.005, gain=0.6)
    lowpass(out, 7000)
    return drive(norm(reverb(out, 0.4, size=0.78, damp=0.4, wet=0.3)), 1.8)


def stagger():
    # 敵が崩れる「ゴォン」: 低い銅鑼の倍音(ゆっくりうなる)+ ゆっくり揺れるきしみ + 鈍い打撃
    out = silence(0.55)
    mix(out, burst(41, 0.02, 1500, 800, 0.9, 180), gain=0.6)
    gong = silence(0.55)
    for ratio, gain, decay in [(1.0, 1.0, 5), (1.007, 0.8, 5), (1.52, 0.5, 7), (2.0, 0.4, 9), (2.73, 0.3, 12), (3.5, 0.15, 16)]:
        tone(gong, 0, 0.55, 180 * ratio, 180 * ratio * 0.97, gain=gain, decay=decay)
    mix(out, drive(norm(gong), 1.6), gain=0.8)
    grind = silence(0.4)
    hiss(random.Random(42), grind, 0, 0.4, 900, 350, 2.0, decay=6)
    mix(out, norm(wobble(grind, 38, 14, 0.8)), gain=0.4)
    mix(out, thump(0.15, 95, 55, 18), gain=0.6)
    lowpass(out, 5000)
    return reverb(out, 0.32, size=0.75, damp=0.45, wet=0.22)


def shatter():
    # 割れる頭 + 低い崩れ + 石の粒 22 個(始めに密、あとはまばらに小さく)+ 部屋の響き
    rng = random.Random(51)
    out = silence(0.62)
    mix(out, burst(52, 0.02, 3000, 1300, 0.8, 180), gain=0.8)
    mix(out, thump(0.4, 80, 40, 9, 2.4), gain=0.8)
    rumble = silence(0.55)
    hiss(rng, rumble, 0, 0.55, 900, 300, 0.8, decay=6, mode=0)
    mix(out, norm(rumble), gain=0.4)
    for _ in range(22):
        u = rng.random()
        dur = 0.014 + 0.03 * rng.random()
        fc = 500 * 5 ** rng.random()
        grain = silence(dur)
        hiss(rng, grain, 0, dur, fc, fc * 0.8, 4 + 4 * rng.random(), decay=3 / dur)
        mix(out, norm(grain), at=0.015 + 0.5 * u ** 1.5, gain=(0.75 - 0.5 * u) * (0.6 + 0.4 * rng.random()))
    lowpass(out, 6000)
    return reverb(out, 0.4, size=0.78, damp=0.4, wet=0.26)


def hurt():
    # 鈍く重い「ドスッ」。−7 半音(player_down)でも消えないよう、つぶした胴に中域の叩く音を重ねる
    out = silence(0.22)
    mix(out, thump(0.2, 120, 55, 16, 2.6), gain=0.9)
    mix(out, burst(61, 0.05, 1400, 600, 0.8, 70, mode=0), gain=0.8)
    tone(out, 0, 0.06, 480, 300, gain=0.4, decay=45, bend=0.5)
    lowpass(out, 3500)
    return reverb(out, 0.16, size=0.6, damp=0.5, wet=0.12)


def whiff():
    # 空を切る「スッ」。帯域が上がっていくノイズ。高すぎない所に置く
    out = silence(0.17)
    cut = silence(0.17)
    hiss(random.Random(71), cut, 0, 0.17, 700, 2200, 1.4, swell=0.5)
    mix(out, norm(cut))
    air = silence(0.17)
    hiss(random.Random(72), air, 0, 0.17, 1500, 3500, 2.0, swell=0.5)
    mix(out, norm(air), gain=0.25)
    return lowpass(out, 5000)


def clank():
    # 赤を弾こうとした「ゴン」。低く詰まった金属がすぐ消える + 鈍い打撃。高い成分は入れない
    out = silence(0.18)
    mix(out, _metal(0.18, 260, [(1.0, 1.0, 30), (1.47, 0.7, 38), (2.09, 0.45, 50), (2.56, 0.3, 65)]))
    mix(out, burst(91, 0.02, 900, 500, 0.8, 160, mode=0), gain=0.6)
    mix(out, thump(0.1, 110, 70, 30), gain=0.6)
    lowpass(out, 3000)
    return reverb(out, 0.12, size=0.6, damp=0.5, wet=0.1)


def dodge():
    # 風の「シュッ」。上がる風と下がる風を重ねて、通り過ぎる感じにする
    out = silence(0.24)
    up = silence(0.24)
    hiss(random.Random(81), up, 0, 0.24, 300, 1300, 1.2, swell=0.6)
    mix(out, norm(up))
    down = silence(0.24)
    hiss(random.Random(82), down, 0, 0.24, 1600, 500, 1.2, swell=0.6)
    mix(out, norm(down), gain=0.4)
    return lowpass(out, 4000)


def soft():
    # 木を軽く叩いたようなクリック
    out = silence(0.06)
    tone(out, 0, 0.06, 700, 640, decay=70)
    tone(out, 0, 0.03, 1750, gain=0.2, decay=150)
    mix(out, burst(101, 0.003, 2500, 2500, 0.8, 900), gain=0.15)
    return lowpass(out, 5000)


def warn_white():
    # 白の予告。小さな金属の「チン」(頭に短いノイズ)。目立たせすぎない
    out = silence(0.1)
    mix(out, burst(111, 0.004, 3500, 3500, 1.0, 700), gain=0.4)
    for ratio, gain, decay in [(1.0, 1.0, 24), (2.76, 0.3, 42)]:
        tone(out, 0, 0.1, 1046 * ratio, gain=gain, decay=decay, attack=0.002)
    lowpass(out, 6000)
    return reverb(out, 0.08, size=0.6, damp=0.5, wet=0.15)


def warn_red():
    # 赤の予告。低く濁った「ドゥン、ドゥン」(98 Hz と 104 Hz の倍音を重ねてうならせ、つぶす)
    out = silence(0.15)
    for at in (0.0, 0.075):
        pulse = silence(0.07)
        for base in (98, 104):
            for k in range(1, 7):
                tone(pulse, 0, 0.07, base * k, base * k * 0.95, gain=1 / k, decay=25, attack=0.004)
        mix(out, drive(norm(pulse), 2.0), at=at)
    return lowpass(out, 2500)


# (名前, 作り方, 最大振幅 dBFS)。counter が一番大きく、parry / just は中、予告は小。
# v0.1.1 で全体を上げた(v0.1.0 は「小さい・迫力がない」)。低い音は、同じ大きさに聞こえるのに振幅が要る
SOUNDS = [
    ("warn_white", warn_white, -12), ("warn_red", warn_red, -10), ("parry", parry, -3.5), ("just", just, -2.5),
    ("whiff", whiff, -10), ("clank", clank, -5), ("dodge", dodge, -9), ("hurt", hurt, -2),
    ("soft", soft, -11), ("stagger", stagger, -2), ("counter", counter, -1), ("shatter", shatter, -1.5),
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
