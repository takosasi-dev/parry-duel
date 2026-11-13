"""タブとホーム画面のアイコン(assets/icon.png、512×512)を描く。ゲームの絵と同じ、弾く線・白い頭・火花。

Pillow で 4 倍の大きさに描いてから縮める(なめらかにするため)。乱数は使わないので、何度回しても同じ絵になる。

    python tools/make_icon.py
"""

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "icon.png"
SIZE = 512
K = 4  # 描く時の倍率
BG = (14, 17, 22)
LINE = (230, 230, 230)
SPARK = (255, 224, 102)


def main() -> None:
    n = SIZE * K
    img = Image.new("RGB", (n, n), BG)
    glow = Image.new("RGB", (n, n), (0, 0, 0))
    g = ImageDraw.Draw(glow)
    d = ImageDraw.Draw(img)
    cx, line_y = n // 2, int(n * 0.66)

    # 火花(線の上の当たり点から放射)
    for i in range(14):
        ang = math.pi + math.pi * (i + 0.5) / 14
        r0, r1 = n * 0.14, n * (0.30 if i % 2 else 0.24)
        p0 = (cx + math.cos(ang) * r0, line_y + math.sin(ang) * r0)
        p1 = (cx + math.cos(ang) * r1, line_y + math.sin(ang) * r1)
        g.line([p0, p1], fill=SPARK, width=int(n * 0.016))
    g.ellipse([cx - n * 0.2, line_y - n * 0.2, cx + n * 0.2, line_y + n * 0.2], fill=(120, 105, 48))
    glow = glow.filter(ImageFilter.GaussianBlur(n * 0.03))
    img = Image.composite(Image.new("RGB", (n, n), SPARK), img, glow.convert("L").point(lambda v: min(255, int(v * 0.9))))
    d = ImageDraw.Draw(img)
    for i in range(14):
        ang = math.pi + math.pi * (i + 0.5) / 14
        r0, r1 = n * 0.15, n * (0.30 if i % 2 else 0.24)
        p0 = (cx + math.cos(ang) * r0, line_y + math.sin(ang) * r0)
        p1 = (cx + math.cos(ang) * r1, line_y + math.sin(ang) * r1)
        d.line([p0, p1], fill=SPARK, width=int(n * 0.012))

    # 弾く線と、白い頭
    w = int(n * 0.022)
    d.line([(n * 0.14, line_y), (n * 0.86, line_y)], fill=LINE, width=w)
    r = n * 0.105
    d.ellipse([cx - r - w, line_y - r - w, cx + r + w, line_y + r + w], fill=BG)
    d.ellipse([cx - r, line_y - r, cx + r, line_y + r], fill=(255, 255, 255))

    # 自分の印(下の三角)
    t = n * 0.07
    ty = n * 0.875
    d.polygon([(cx, ty - t), (cx + t * 0.9, ty + t * 0.55), (cx - t * 0.9, ty + t * 0.55)], fill=(124, 227, 139))

    OUT.parent.mkdir(parents=True, exist_ok=True)
    img.resize((SIZE, SIZE), Image.LANCZOS).save(OUT)
    print(f"{OUT}: {SIZE}x{SIZE}")


if __name__ == "__main__":
    main()
