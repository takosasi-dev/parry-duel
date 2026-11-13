"""撮った画像を 1 枚に並べる(見た目をまとめて確かめる用)。Pillow を使う。

    python tools/sheet.py <出力.png> <列の数> <画像 ...>
"""

import sys
from pathlib import Path

from PIL import Image


def main() -> None:
    out, cols, files = Path(sys.argv[1]), int(sys.argv[2]), [Path(f) for f in sys.argv[3:]]
    images = [Image.open(f).convert("RGB") for f in files]
    w = min(im.width for im in images)
    h = min(im.height for im in images)
    rows = (len(images) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * w, rows * h), (0, 0, 0))
    for i, im in enumerate(images):
        sheet.paste(im.resize((w, h)), ((i % cols) * w, (i // cols) * h))
    sheet.save(out)
    print(f"{out}: {sheet.width}×{sheet.height}、{len(images)} 枚")


if __name__ == "__main__":
    main()
