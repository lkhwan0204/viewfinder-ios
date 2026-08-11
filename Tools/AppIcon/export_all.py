#!/usr/bin/env python3
"""
Export the ViewFinder app icon.

Writes every size the AppIcon.appiconset needs, plus the branding preview
images under docs/branding/. Every size is a true vector render from the
geometry in gen_icons.py, not a downscale of a bitmap.

Run from anywhere:   python3 Tools/AppIcon/export_all.py
"""

import os
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)

from gen_icons import (SVG_FRAMED_HORIZON, blit, dummy_tile, grayscale,  # noqa: E402
                       hexc, mask_alpha, render_icon, solid,
                       spec_framed_horizon, spec_half_frame, upscale_nn,
                       vgradient, write_png)

APPICON = os.path.join(REPO, "Viewfinder", "Supporting", "Assets.xcassets",
                       "AppIcon.appiconset")
BRANDING = os.path.join(REPO, "docs", "branding")

SPEC = spec_framed_horizon()

# filename -> pixel size, matching the existing Contents.json
APPICON_SIZES = {
    "Icon-20@2x.png": 40,
    "Icon-20@3x.png": 60,
    "Icon-29@2x.png": 58,
    "Icon-29@3x.png": 87,
    "Icon-40@2x.png": 80,
    "Icon-40@3x.png": 120,
    "Icon-60@2x.png": 120,
    "Icon-60@3x.png": 180,
    "Icon-76@1x.png": 76,
    "Icon-76@2x.png": 152,
    "Icon-83.5@2x.png": 167,
    "Icon-1024.png": 1024,
}


def export_appiconset():
    print("AppIcon.appiconset")
    for name, size in sorted(APPICON_SIZES.items(), key=lambda kv: kv[1]):
        write_png(os.path.join(APPICON, name), size, size,
                  render_icon(SPEC, size))


def export_overview():
    """Single image telling the whole story."""
    W, HERO, STRIP_H, PAD = 900, 620, 250, 40
    SIZES = [180, 120, 80, 60, 40]

    y_hero = PAD
    y_sizes = y_hero + HERO + PAD + 10
    y_dark = y_sizes + max(SIZES) + PAD + 10
    y_light = y_dark + STRIP_H + 24
    H = y_light + STRIP_H + PAD

    canvas = solid(W, H, hexc("#6E6E73"))
    blit(canvas, W, render_icon(SPEC, HERO), HERO, HERO,
         (W - HERO) // 2, y_hero, mask_alpha(HERO))

    gap = 46
    x = (W - (sum(SIZES) + gap * (len(SIZES) - 1))) // 2
    for s in SIZES:
        blit(canvas, W, render_icon(SPEC, s), s, s,
             x, y_sizes + (max(SIZES) - s) // 2, mask_alpha(s))
        x += s + gap

    ICON = 132
    a_icon = mask_alpha(ICON)
    for y0, (wt, wb), (n1b, n1f), (n2b, n2f) in [
        (y_dark, ("#1C1B22", "#06060A"), ("#2C2C2E", "#F2F2F7"), ("#0A84FF", "#FFFFFF")),
        (y_light, ("#F2EEE7", "#CBC4BA"), ("#F2F2F7", "#8E8E93"), ("#34C759", "#FFFFFF")),
    ]:
        sw = W - PAD * 2
        blit(canvas, W, vgradient(sw, STRIP_H, hexc(wt), hexc(wb)), sw, STRIP_H, PAD, y0)
        tiles = [dummy_tile(ICON, n1b, n1f, "circle"),
                 render_icon(SPEC, ICON),
                 dummy_tile(ICON, n2b, n2f, "square")]
        g = 70
        x = (W - (ICON * 3 + g * 2)) // 2
        for t in tiles:
            blit(canvas, W, t, ICON, ICON, x, y0 + (STRIP_H - ICON) // 2, a_icon)
            x += ICON + g

    write_png(os.path.join(BRANDING, "overview.png"), W, H, canvas)


def export_homescreen(dark, out):
    ICON, W, H = 136, 860, 300
    if dark:
        canvas = vgradient(W, H, hexc("#1C1B22"), hexc("#06060A"))
        n1 = dummy_tile(ICON, "#2C2C2E", "#F2F2F7", "circle")
        n2 = dummy_tile(ICON, "#0A84FF", "#FFFFFF", "square")
    else:
        canvas = vgradient(W, H, hexc("#F2EEE7"), hexc("#CBC4BA"))
        n1 = dummy_tile(ICON, "#F2F2F7", "#8E8E93", "circle")
        n2 = dummy_tile(ICON, "#34C759", "#FFFFFF", "square")
    alpha = mask_alpha(ICON)
    g = 76
    x = (W - (ICON * 3 + g * 2)) // 2
    y = (H - ICON) // 2
    for t in (n1, render_icon(SPEC, ICON), n2):
        blit(canvas, W, t, ICON, ICON, x, y, alpha)
        x += ICON + g
    write_png(out, W, H, canvas)


def export_true_sizes(spec, out):
    SIZES = [180, 120, 80, 60, 40]
    gap, pad = 56, 56
    W = pad * 2 + sum(SIZES) + gap * (len(SIZES) - 1)
    H = pad * 2 + max(SIZES)
    canvas = solid(W, H, hexc("#6E6E73"))
    x = pad
    for s in SIZES:
        blit(canvas, W, render_icon(spec, s), s, s,
             x, pad + (max(SIZES) - s) // 2, mask_alpha(s))
        x += s + gap
    write_png(out, W, H, canvas)


def export_compare(out):
    """
    Why the frame needed a subject.
    Left: frame only - reads as a camera. Right: shipping mark.
    """
    s, f = 60, 6
    ua, uw, uh = upscale_nn(render_icon(spec_half_frame(), s), s, s, f)
    ub, _, _ = upscale_nn(render_icon(SPEC, s), s, s, f)
    gap, pad = 56, 56
    W = pad * 2 + uw * 2 + gap
    H = pad * 2 + uh
    canvas = solid(W, H, hexc("#6E6E73"))
    blit(canvas, W, ua, uw, uh, pad, pad)
    blit(canvas, W, ub, uw, uh, pad + uw + gap, pad)
    write_png(out, W, H, canvas)


def export_branding():
    print("docs/branding")
    with open(os.path.join(BRANDING, "app-icon.svg"), "w") as fh:
        fh.write(SVG_FRAMED_HORIZON)
    print("  wrote docs/branding/app-icon.svg")

    export_overview()
    write_png(os.path.join(BRANDING, "icon-1024.png"), 1024, 1024,
              render_icon(SPEC, 1024))
    export_true_sizes(SPEC, os.path.join(BRANDING, "true-sizes.png"))
    export_homescreen(True, os.path.join(BRANDING, "homescreen-dark.png"))
    export_homescreen(False, os.path.join(BRANDING, "homescreen-light.png"))
    write_png(os.path.join(BRANDING, "tinted-grayscale.png"), 512, 512,
              grayscale(render_icon(SPEC, 512)))
    export_compare(os.path.join(BRANDING, "compare-60px.png"))


if __name__ == "__main__":
    os.makedirs(BRANDING, exist_ok=True)
    export_appiconset()
    export_branding()
    print("done")
