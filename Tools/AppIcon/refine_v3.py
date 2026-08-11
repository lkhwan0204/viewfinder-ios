#!/usr/bin/env python3
"""
V3 refinement: window + horizon.

Open questions:
  - full-bleed horizon (splits the tile like a minus sign) vs inset
  - hard ends vs light spilling off (soft ends)
  - horizon height: centre-ish vs photographic lower third
  - bracket weight for home-screen presence
"""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)

from gen_icons import (AMBER, blit, dummy_tile, hexc, horizon,  # noqa: E402
                       make_bracket, mask_alpha, render_icon, solid,
                       upscale_nn, vgradient, write_png)

OUT = os.path.join(REPO, "docs", "branding", "explore")
SHADE, LIGHT, LINE = "#EA9A3C", "#F3AC4E", "#F5B25A"


def window(stroke=64.0, frame=700.0, arm_ratio=0.25, radius_ratio=0.40):
    cx, cy = 512.0, 500.0
    x0, x1 = cx - frame / 2, cx + frame / 2
    y0, y1 = cy - frame / 2, cy + frame / 2
    arm, R = frame * arm_ratio, stroke * radius_ratio
    return [make_bracket(x0, y0, +1, +1, arm, R, stroke, SHADE),
            make_bracket(x1, y0, -1, +1, arm, R, stroke, SHADE),
            make_bracket(x0, y1, +1, -1, arm, R, stroke, LIGHT),
            make_bracket(x1, y1, -1, -1, arm, R, stroke, LIGHT)]


def spec(brackets, subjects, bloom_y, peak=0.20):
    return {
        "base": hexc("#131218"),
        "veil": (hexc("#0D0C11"), hexc("#18161D"), 0.42),
        "bloom": (512.0, bloom_y, 500.0, hexc(AMBER), peak),
        "brackets": brackets,
        "subjects": subjects,
    }


VARIANTS = [
    ("A full width, hard", spec(
        window(), [horizon(578, 176, 848, 36, LINE)], 578)),

    ("B inset, hard", spec(
        window(), [horizon(592, 246, 778, 42, LINE)], 592)),

    ("C full width, soft ends", spec(
        window(), [horizon(592, 150, 874, 42, LINE, soft=0.30)], 592)),

    ("D inset, soft ends", spec(
        window(), [horizon(592, 232, 792, 42, LINE, soft=0.28)], 592)),

    ("E D + heavier brackets", spec(
        window(stroke=76.0), [horizon(596, 236, 788, 46, LINE, soft=0.28)], 596)),
]


def main():
    os.makedirs(OUT, exist_ok=True)
    BIG, SMALL, MAG, REAL = 320, 60, 4, 136
    gap, pad = 36, 44
    n = len(VARIANTS)

    W = pad * 2 + BIG * n + gap * (n - 1)
    row2_h = SMALL * MAG
    row3_h = REAL + 40
    H = pad * 2 + BIG + gap + row2_h + gap + row3_h

    canvas = solid(W, H, hexc("#6E6E73"))
    y2 = pad + BIG + gap
    y3 = y2 + row2_h + gap
    blit(canvas, W, vgradient(W - pad * 2, row3_h, hexc("#1C1B22"), hexc("#06060A")),
         W - pad * 2, row3_h, pad, y3)

    a_big, a_small, a_real = mask_alpha(BIG), mask_alpha(SMALL), mask_alpha(REAL)
    row2_w = SMALL * MAG * n + gap * (n - 1)
    x, x2 = pad, (W - row2_w) // 2

    for label, sp in VARIANTS:
        print("  %s" % label)
        blit(canvas, W, render_icon(sp, BIG), BIG, BIG, x, pad, a_big)

        small = bytearray(render_icon(sp, SMALL))
        for i, a in enumerate(a_small):
            if a < 1.0:
                for k in range(3):
                    j = i * 3 + k
                    small[j] = int(small[j] * a + 0x6E * (1 - a) + 0.5)
        up, uw, uh = upscale_nn(small, SMALL, SMALL, MAG)
        blit(canvas, W, up, uw, uh, x2, y2)

        cx = x + (BIG - REAL) // 2
        blit(canvas, W, render_icon(sp, REAL), REAL, REAL, cx, y3 + 20, a_real)

        x += BIG + gap
        x2 += uw + gap

    write_png(os.path.join(OUT, "v3-refinement.png"), W, H, canvas)


if __name__ == "__main__":
    main()
