# 第三者の素材

配布物(Web 書き出し)に入る物を、同梱するファイルと 1 対 1 で書く。自作の物も、出どころが分かるように載せている。

## Noto Sans JP(同梱する字体)

- ファイル: `assets/fonts/NotoSansJP-Subset.ttf`
- 原本: `NotoSansJP[wght].ttf`。入手元は https://github.com/google/fonts/tree/main/ofl/notosansjp (コミット `295d98a7a0c17c68f1341eaeea354e7960ea70d3`)
- 原本の SHA-256: `c2f3b4d463500a2ddcd3849cded1fceeb9fd6d1c32e6cbecd568453ba50fc68f`
- 変えた所: 原本を、画面に出す文字だけの部分集合にした(`tools/subset_font.py`。`core/strings.gd` に出てくる文字と、ASCII の印字できる文字。太さの軸は残している)。文言を足すたびに作り直すので、同梱するファイルのハッシュは版ごとに変わる。字の形は変えていない
- ライセンス: SIL Open Font License, Version 1.1。原文は [`assets/fonts/OFL.txt`](assets/fonts/OFL.txt)(入手元の `OFL.txt` をそのまま置いた)
- 著作権表示: Copyright 2014-2021 Adobe (http://www.adobe.com/), with Reserved Font Name 'Source'

## 効果音(自作)

- ファイル: `assets/sfx/` の 12 個(`warn_white.wav` `warn_red.wav` `parry.wav` `just.wav` `whiff.wav` `clank.wav` `dodge.wav` `hurt.wav` `soft.wav` `stagger.wav` `counter.wav` `shatter.wav`)
- 作り方: `tools/gen_sfx.py` が、正弦波と雑音から合成する(Python の標準ライブラリだけ。録音や、ほかの人の素材は使っていない)
- ライセンス: このリポジトリのコードと同じ [MIT](LICENSE)

## アイコン(自作)

- ファイル: `assets/icon.png`
- 作り方: `tools/make_icon.py` が描く(ほかの人の素材は使っていない)
- ライセンス: このリポジトリのコードと同じ [MIT](LICENSE)

## Godot Engine

Web 書き出し(`index.wasm`・`index.js` など)には、Godot Engine 4.7.2-stable の本体が入る。

```
This game uses Godot Engine, available under the following license:

Copyright (c) 2014-present Godot Engine contributors.
Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- Godot Engine のライセンス: https://godotengine.org/license
- Godot Engine が中に持っている第三者のライブラリ(FreeType・HarfBuzz・zlib など)の著作権表示とライセンスは、Godot の `COPYRIGHT.txt` にまとまっている: https://github.com/godotengine/godot/blob/4.7.2-stable/COPYRIGHT.txt
