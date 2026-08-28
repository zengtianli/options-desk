#!/usr/bin/env python3
"""画 options-desk 的 app 图标 —— 一条净值曲线压在深色盘面上。

每个 app 画自己的图标(`/appios`:make_icon.py 属「内容会随 app 变」那一类,
不共享)。这里刻意跟姊妹 app `options-calc` 区分开:那个是计算器(网格),
这个是盘面(曲线)。桌面上要能一眼分得出来,否则两个期权 app 会互相认错。

    python3 make_icon.py        # → Resources/icon-1024.png 及 Assets.xcassets 那份
"""
from __future__ import annotations

import pathlib
import sys

try:
    from PIL import Image, ImageDraw
except ImportError:                                          # noqa: BLE001
    sys.exit("❌ 缺 Pillow: /opt/homebrew/bin/python3 -m pip install pillow")

HERE = pathlib.Path(__file__).resolve().parent
S = 1024
BG_TOP = (18, 26, 38)
BG_BOT = (10, 15, 24)
LINE = (64, 200, 140)
BENCH = (90, 100, 118)
GRID = (38, 50, 68)

# 一条「跑赢基准」的形状:两条线同起点,绿线在后段拉开。
# 不是真数据 —— 图标是标识不是图表,真数据在 app 里。
MINE = [0.50, 0.46, 0.55, 0.44, 0.38, 0.47, 0.52, 0.60, 0.58, 0.68, 0.74, 0.86]
QQQ = [0.50, 0.47, 0.53, 0.45, 0.41, 0.46, 0.49, 0.52, 0.50, 0.54, 0.55, 0.58]


def main() -> int:
    img = Image.new("RGB", (S, S), BG_BOT)
    d = ImageDraw.Draw(img)
    for y in range(S):                                       # 竖直渐变
        t = y / S
        d.line([(0, y), (S, y)],
               fill=tuple(int(a + (b - a) * t) for a, b in zip(BG_TOP, BG_BOT)))
    for i in range(1, 5):                                    # 淡网格
        y = S * i / 5
        d.line([(S * 0.10, y), (S * 0.90, y)], fill=GRID, width=3)

    def pts(series):
        n = len(series)
        return [(S * (0.10 + 0.80 * i / (n - 1)), S * (0.88 - 0.62 * v))
                for i, v in enumerate(series)]

    d.line(pts(QQQ), fill=BENCH, width=18, joint="curve")
    d.line(pts(MINE), fill=LINE, width=30, joint="curve")
    x, y = pts(MINE)[-1]
    d.ellipse([x - 30, y - 30, x + 30, y + 30], fill=LINE)

    out = HERE / "Resources" / "icon-1024.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    img.save(out)
    dup = HERE / "Resources" / "Assets.xcassets" / "AppIcon.appiconset" / "icon-1024.png"
    if dup.parent.is_dir():
        img.save(dup)
    print(f"✅ {out}  ({out.stat().st_size // 1024} KB)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
