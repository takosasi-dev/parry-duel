"""同梱する字体を、画面に出す文字だけに絞る(SlingArc と同じ Noto Sans JP。太さの軸は残す)。

core/strings.gd の文字列リテラルの全文字と、ASCII の印字できる文字(0x20〜0x7E)を集めて絞り、assets/fonts/ に書く。
原本は google/fonts の固定コミットから取り、sha256 を照らす。tools/font_src/ に置き、git には入れない。
文言を足したら、これを回し直す。

    pip install fonttools
    python tools/subset_font.py
"""

import hashlib
import re
import sys
import urllib.request
from pathlib import Path

from fontTools import subset
from fontTools.ttLib import TTFont

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "tools" / "font_src" / "NotoSansJP.ttf"
OUT = ROOT / "assets" / "fonts" / "NotoSansJP-Subset.ttf"
URL = "https://raw.githubusercontent.com/google/fonts/295d98a7a0c17c68f1341eaeea354e7960ea70d3/ofl/notosansjp/NotoSansJP%5Bwght%5D.ttf"
SHA256 = "c2f3b4d463500a2ddcd3849cded1fceeb9fd6d1c32e6cbecd568453ba50fc68f"
ASCII = "".join(chr(c) for c in range(0x20, 0x7F))


def strings_chars() -> set[str]:
    text = (ROOT / "core" / "strings.gd").read_text(encoding="utf-8")
    return set("".join(re.findall(r'"((?:[^"\\\n]|\\.)*)"', text)))


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    if not SRC.exists():
        SRC.parent.mkdir(parents=True, exist_ok=True)
        print(f"取得: {URL}")
        urllib.request.urlretrieve(URL, SRC)
    digest = hashlib.sha256(SRC.read_bytes()).hexdigest()
    if digest != SHA256:
        sys.exit(f"{SRC} の sha256 が違う: {digest}(消して取り直す)")

    chars = set(ASCII) | strings_chars()
    font = TTFont(SRC)
    options = subset.Options()
    options.layout_features = ["*"]
    subsetter = subset.Subsetter(options)
    subsetter.populate(unicodes=[ord(c) for c in chars])
    subsetter.subset(font)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    font.save(OUT)
    missing = sorted(c for c in chars if ord(c) not in font.getBestCmap())
    print(f"{OUT.name}: {SRC.stat().st_size:,} -> {OUT.stat().st_size:,} バイト、{len(chars)} 文字、太さの軸: {'fvar' in font}")
    if missing:
        sys.exit(f"原本に無い文字: {''.join(missing)}")


if __name__ == "__main__":
    main()
