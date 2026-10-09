#!/usr/bin/env python3
"""スクリーンショットを横に並べて1枚にする(README の docs/screens-*.jpg)。

使い方:
    python3 scripts/compose-screens.py docs/screens-ai.jpg 20-体験.png 21-提案.png ...

CI の UI テスト(ci-output ブランチの screenshots/)の画像を、高さ 696px にそろえて
16px の余白で並べる。背景は README の他の画像と同じ薄い灰色。
"""
import sys

from PIL import Image

PAD = 16
HEIGHT = 696
BG = (243, 244, 248)


def main() -> None:
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    out, paths = sys.argv[1], sys.argv[2:]
    shots = []
    for path in paths:
        image = Image.open(path).convert("RGB")
        width = round(image.width * HEIGHT / image.height)
        shots.append(image.resize((width, HEIGHT), Image.LANCZOS))
    canvas = Image.new("RGB", (PAD + sum(s.width + PAD for s in shots), HEIGHT + 2 * PAD), BG)
    x = PAD
    for shot in shots:
        canvas.paste(shot, (x, PAD))
        x += shot.width + PAD
    canvas.save(out, quality=85, optimize=True, progressive=True)
    print(f"{out}: {canvas.width}x{canvas.height}")


if __name__ == "__main__":
    main()
