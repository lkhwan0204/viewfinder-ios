#!/usr/bin/env python3
"""
Revision study: what goes INSIDE the frame.

Brackets alone read as "camera". The app is not a camera - it is about
finding a place and a time. So the frame needs a subject: the horizon
(a place in the world) and/or the low sun (the hour).
"""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)

from gen_icons import (AMBER, blit, disc, hexc, horizon, make_bracket,  # noqa: E402
                       mask_alpha, render_icon, solid, upscale_nn, write_png)

OUT = os.path.join(REPO, "docs", "branding", "explore")

AMBER_SHADE, AMBER_LIGHT = "#EA9A3C", "#F3AC4E"
LIGHT_LINE, SUN = "#F5B25A", "#F7B45C"


def half_frame_brackets():
    """frame 672 centred (512,504); stroke 104, arm 269, corner R 42"""
    x0, x1, y0, y1 = 176.0, 848.0, 168.0, 840.0
    return [make_bracket(x0, y0, +1, +1, 269, 42, 104, AMBER_SHADE),
            make_bracket(x1, y1, -1, -1, 269, 42, 104, AMBER_LIGHT)]


def window_brackets():
    """frame 700 centred (512,500); stroke 64, arm 175, corner R 26"""
    x0, x1, y0, y1 = 162.0, 862.0, 150.0, 850.0
    return [make_bracket(x0, y0, +1, +1, 175, 26, 64, AMBER_SHADE),
            make_bracket(x1, y0, -1, +1, 175, 26, 64, AMBER_SHADE),
            make_bracket(x0, y1, +1, -1, 175, 26, 64, AMBER_LIGHT),
            make_bracket(x1, y1, -1, -1, 175, 26, 64, AMBER_LIGHT)]


def bg(base, vt, vb, vo, bloom):
    return {"base": hexc(base), "veil": (hexc(vt), hexc(vb), vo), "bloom": bloom}


DARK = ("#131218", "#0D0C11", "#18161D", 0.42)


def spec(brackets, subjects, bloom):
    s = bg(DARK[0], DARK[1], DARK[2], DARK[3], bloom)
    s["brackets"] = brackets
    s["subjects"] = subjects
    return s


# ---------------------------------------------------------------- variants
VARIANTS = [
    # V0 - what is currently on the branch: frame only, no subject
    ("V0 frame only", spec(
        half_frame_brackets(), [],
        (640.0, 660.0, 540.0, hexc(AMBER), 0.14))),

    # V1 - frame + horizon. A place in the world, lit low.
    ("V1 + horizon", spec(
        half_frame_brackets(),
        [horizon(548.0, 252.0, 756.0, 40.0, LIGHT_LINE)],
        (512.0, 548.0, 480.0, hexc(AMBER), 0.20))),

    # V2 - frame + low sun. The hour, no landscape.
    ("V2 + low sun", spec(
        half_frame_brackets(),
        [disc(556.0, 620.0, 80.0, SUN)],
        (556.0, 620.0, 460.0, hexc(AMBER), 0.24))),

    # V3 - window + horizon. Most explicit "looking at a place".
    ("V3 window + horizon", spec(
        window_brackets(),
        [horizon(578.0, 176.0, 848.0, 36.0, LIGHT_LINE)],
        (512.0, 578.0, 500.0, hexc(AMBER), 0.20))),

    # V4 - window + horizon + sun. The most literal end of the spectrum.
    ("V4 window + horizon + sun", spec(
        window_brackets(),
        [horizon(578.0, 176.0, 848.0, 36.0, LIGHT_LINE),
         disc(620.0, 508.0, 64.0, SUN)],
        (560.0, 560.0, 500.0, hexc(AMBER), 0.22))),
]


def main():
    os.makedirs(OUT, exist_ok=True)

    BIG, SMALL, MAG = 320, 60, 4
    gap, pad = 36, 44
    n = len(VARIANTS)
    row2_w = SMALL * MAG * n + gap * (n - 1)
    W = pad * 2 + BIG * n + gap * (n - 1)
    H = pad * 2 + BIG + gap + SMALL * MAG

    canvas = solid(W, H, hexc("#6E6E73"))
    a_big, a_small = mask_alpha(BIG), mask_alpha(SMALL)

    x = pad
    x2 = (W - row2_w) // 2
    y2 = pad + BIG + gap
    for label, sp in VARIANTS:
        print("  %s" % label)
        blit(canvas, W, render_icon(sp, BIG), BIG, BIG, x, pad, a_big)

        small = render_icon(sp, SMALL)
        # keep the iOS corner mask on the magnified小 render too
        masked = bytearray(small)
        for i, a in enumerate(a_small):
            if a < 1.0:
                for k in range(3):
                    j = i * 3 + k
                    masked[j] = int(masked[j] * a + 0x6E * (1 - a) + 0.5)
        up, uw, uh = upscale_nn(masked, SMALL, SMALL, MAG)
        blit(canvas, W, up, uw, uh, x2, y2)

        x += BIG + gap
        x2 += uw + gap

    write_png(os.path.join(OUT, "subject-study.png"), W, H, canvas)

    # full-size renders of every variant, for close inspection
    for label, sp in VARIANTS:
        name = label.split()[0].lower()
        write_png(os.path.join(OUT, "%s-1024.png" % name), 1024, 1024,
                  render_icon(sp, 1024))


if __name__ == "__main__":
    main()
