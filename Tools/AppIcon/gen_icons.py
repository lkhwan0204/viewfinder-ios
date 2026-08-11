#!/usr/bin/env python3
"""
ViewFinder app icon renderer.

Zero-dependency vector rasterizer + PNG encoder.
All geometry is defined in a 1024x1024 design space and rendered
analytically (signed distance fields), so every size is a true
vector render - exactly what iOS does with a PDF/SVG source.
"""

import math
import os
import struct
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PNG_DIR = os.path.join(ROOT, "png")
SVG_DIR = os.path.join(ROOT, "svg")


# --------------------------------------------------------------------------
# PNG output
# --------------------------------------------------------------------------

def write_png(path, w, h, buf):
    """buf = bytearray of RGB888, length w*h*3"""
    stride = w * 3
    raw = bytearray()
    for y in range(h):
        raw.append(0)                       # filter type 0 (None)
        raw += buf[y * stride:(y + 1) * stride]

    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data +
                struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)
    print("  wrote %-52s %dx%d" % (os.path.relpath(path, ROOT), w, h))


def hexc(s):
    s = s.lstrip("#")
    return (int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16))


def clamp01(v):
    return 0.0 if v < 0.0 else (1.0 if v > 1.0 else v)


def smoothstep(t):
    t = clamp01(t)
    return t * t * (3.0 - 2.0 * t)


# --------------------------------------------------------------------------
# Design tokens
# --------------------------------------------------------------------------

CANVAS = 1024.0

AMBER = "#F0A03C"          # brand primary
AMBER_SHADE = "#EA9A3C"    # bracket away from the light
AMBER_LIGHT = "#F3AC4E"    # bracket facing the light  (~9% luminance delta)


# --------------------------------------------------------------------------
# Bracket primitive:  an L-shaped corner mark with a rounded corner join
# --------------------------------------------------------------------------

def make_bracket(cx, cy, sx, sy, arm, radius, stroke, color, flat_caps=True):
    """
    cx, cy  : corner point of the implied frame (centerline)
    sx, sy  : +1/-1 direction the two arms travel from the corner
    arm     : arm length along the centerline, measured from the corner
    radius  : corner join radius on the centerline
    stroke  : stroke weight
    """
    return {
        "cx": cx, "cy": cy, "sx": sx, "sy": sy,
        "R": radius, "half": stroke / 2.0,
        "color": hexc(color), "flat": flat_caps,
        "ax": cx + sx * radius, "ay": cy + sy * radius,   # arc centre
        "endx": cx + sx * arm, "endy": cy + sy * arm,     # arm tips
        "hx0": min(cx + sx * radius, cx + sx * arm),      # horizontal arm span
        "hx1": max(cx + sx * radius, cx + sx * arm),
        "vy0": min(cy + sy * radius, cy + sy * arm),      # vertical arm span
        "vy1": max(cy + sy * radius, cy + sy * arm),
    }


def bracket_sdf(b, x, y):
    """Signed distance to the bracket surface, in design-space units."""
    # --- horizontal arm (a segment at y = cy) ---
    hx = x
    if hx < b["hx0"]:
        hx = b["hx0"]
    elif hx > b["hx1"]:
        hx = b["hx1"]
    d = math.hypot(x - hx, y - b["cy"])

    # --- vertical arm (a segment at x = cx) ---
    vy = y
    if vy < b["vy0"]:
        vy = b["vy0"]
    elif vy > b["vy1"]:
        vy = b["vy1"]
    d2 = math.hypot(x - b["cx"], y - vy)
    if d2 < d:
        d = d2

    # --- quarter-circle corner join ---
    rx = x - b["ax"]
    ry = y - b["ay"]
    if rx * b["sx"] <= 0.0 and ry * b["sy"] <= 0.0:
        d3 = abs(math.hypot(rx, ry) - b["R"])
        if d3 < d:
            d = d3

    d -= b["half"]

    # --- flat (butt) caps: intersect with two half-planes at the arm tips ---
    if b["flat"]:
        t = b["sx"] * (x - b["endx"])
        if t > d:
            d = t
        t = b["sy"] * (y - b["endy"])
        if t > d:
            d = t
    return d


def bracket_bbox(b):
    xs = (min(b["cx"], b["endx"]) - b["half"], max(b["cx"], b["endx"]) + b["half"])
    ys = (min(b["cy"], b["endy"]) - b["half"], max(b["cy"], b["endy"]) + b["half"])
    return xs[0] - 2, ys[0] - 2, xs[1] + 2, ys[1] + 2


# --------------------------------------------------------------------------
# Icon specs
# --------------------------------------------------------------------------

def spec_half_frame(flat_caps=True, diagonal="TL-BR",
                    frame=672.0, stroke=104.0, arm_ratio=0.40, radius_ratio=0.40,
                    bloom_peak=0.14, base="#131218",
                    veil=("#0D0C11", "#18161D", 0.42),
                    amber_shade=AMBER_SHADE, amber_light=AMBER_LIGHT):
    """
    HALF FRAME - two diagonally opposed viewfinder brackets.
    `arm_ratio`    : arm length as a fraction of the frame side
    `radius_ratio` : corner join radius as a fraction of the stroke weight
    """
    cxm, cym = 512.0, 504.0                        # 8px optical lift
    x0, x1 = cxm - frame / 2, cxm + frame / 2
    y0, y1 = cym - frame / 2, cym + frame / 2
    ARM = frame * arm_ratio
    R = stroke * radius_ratio

    if diagonal == "TL-BR":
        corners = ((x0, y0, +1, +1, amber_shade), (x1, y1, -1, -1, amber_light))
    else:                                          # TR-BL
        corners = ((x1, y0, -1, +1, amber_shade), (x0, y1, +1, -1, amber_light))

    brackets = [make_bracket(cx, cy, sx, sy, ARM, R, stroke, col, flat_caps)
                for cx, cy, sx, sy, col in corners]

    # bloom follows the "light" bracket so the light source stays coherent
    bx, by = (640.0, 660.0) if diagonal == "TL-BR" else (384.0, 660.0)

    return {
        "base": hexc(base),
        "veil": (hexc(veil[0]), hexc(veil[1]), veil[2]),
        "bloom": (bx, by, 540.0, hexc(AMBER), bloom_peak),
        "brackets": brackets,
    }


def spec_golden_aperture():
    """
    GOLDEN APERTURE - four corner brackets around a low warm bloom.
    Implied frame 700x700, centred at (512, 500).
    """
    FRAME = 700.0
    cxm, cym = 512.0, 500.0
    x0, x1 = cxm - FRAME / 2, cxm + FRAME / 2     # 162 .. 862
    y0, y1 = cym - FRAME / 2, cym + FRAME / 2     # 150 .. 850
    ARM, R, W = 175.0, 48.0, 64.0

    return {
        "base": hexc("#0D0D10"),
        "veil": (hexc("#08080A"), hexc("#111114"), 0.40),
        "bloom": (512.0, 620.0, 460.0, hexc("#F2A544"), 0.32),
        "brackets": [
            make_bracket(x0, y0, +1, +1, ARM, R, W, AMBER_SHADE),
            make_bracket(x1, y0, -1, +1, ARM, R, W, AMBER_SHADE),
            make_bracket(x0, y1, +1, -1, ARM, R, W, AMBER_LIGHT),
            make_bracket(x1, y1, -1, -1, ARM, R, W, AMBER_LIGHT),
        ],
    }


# --------------------------------------------------------------------------
# Renderer
# --------------------------------------------------------------------------

def render_icon(spec, size):
    """Render the full-bleed square icon at `size` px. Returns bytearray RGB."""
    S = size / CANVAS
    buf = bytearray(size * size * 3)

    br, bg, bb = spec["base"]
    vt, vb, vo = spec["veil"]
    lx, ly, lr, (mr, mg, mb), peak = spec["bloom"]

    # ---- background ----
    # A 12% amber bloom over near-black spans only a handful of 8-bit levels,
    # so it bands into visible concentric rings. Dither with +/-0.5 LSB of
    # deterministic noise to break the ramp up.
    i = 0
    for py in range(size):
        Y = (py + 0.5) / S
        t = Y / CANVAS
        # vertical veil over the base
        vr = vt[0] + (vb[0] - vt[0]) * t
        vg = vt[1] + (vb[1] - vt[1]) * t
        vbl = vt[2] + (vb[2] - vt[2]) * t
        r0 = br * (1 - vo) + vr * vo
        g0 = bg * (1 - vo) + vg * vo
        b0 = bb * (1 - vo) + vbl * vo
        dy = Y - ly
        dy2 = dy * dy
        for px in range(size):
            X = (px + 0.5) / S
            dx = X - lx
            dist = math.sqrt(dx * dx + dy2)
            a = peak * smoothstep(1.0 - dist / lr) if dist < lr else 0.0
            h = ((px * 73856093) ^ (py * 19349663)) * 2654435761 & 0xFFFFFFFF
            n = h / 4294967295.0          # 0 .. 1
            if a > 0.0:
                buf[i] = int(r0 * (1 - a) + mr * a + n)
                buf[i + 1] = int(g0 * (1 - a) + mg * a + n)
                buf[i + 2] = int(b0 * (1 - a) + mb * a + n)
            else:
                buf[i] = int(r0 + n)
                buf[i + 1] = int(g0 + n)
                buf[i + 2] = int(b0 + n)
            i += 3

    # ---- brackets (analytic AA from the SDF) ----
    for b in spec["brackets"]:
        bx0, by0, bx1, by1 = bracket_bbox(b)
        px0 = max(0, int(bx0 * S) - 1)
        px1 = min(size, int(bx1 * S) + 2)
        py0 = max(0, int(by0 * S) - 1)
        py1 = min(size, int(by1 * S) + 2)
        cr, cg, cb = b["color"]
        for py in range(py0, py1):
            Y = (py + 0.5) / S
            row = py * size * 3
            for px in range(px0, px1):
                X = (px + 0.5) / S
                cov = 0.5 - bracket_sdf(b, X, Y) * S
                if cov <= 0.0:
                    continue
                if cov > 1.0:
                    cov = 1.0
                j = row + px * 3
                buf[j] = int(buf[j] * (1 - cov) + cr * cov + 0.5)
                buf[j + 1] = int(buf[j + 1] * (1 - cov) + cg * cov + 0.5)
                buf[j + 2] = int(buf[j + 2] * (1 - cov) + cb * cov + 0.5)
    return buf


# --------------------------------------------------------------------------
# iOS icon mask (superellipse / "squircle") + compositing helpers
# --------------------------------------------------------------------------

MASK_N = 4.6


def mask_alpha(size, samples=3):
    """Antialiased superellipse coverage, 0.0-1.0 per pixel."""
    h = size / 2.0
    out = [0.0] * (size * size)
    step = 1.0 / samples
    off = step / 2.0
    inv = 1.0 / (samples * samples)
    for py in range(size):
        for px in range(size):
            hit = 0
            for sy in range(samples):
                v = abs((py + off + sy * step) - h) / h
                vn = v ** MASK_N
                for sx in range(samples):
                    u = abs((px + off + sx * step) - h) / h
                    if u ** MASK_N + vn <= 1.0:
                        hit += 1
            out[py * size + px] = hit * inv
    return out


def blit(dst, dst_w, src, src_w, src_h, x, y, alpha=None):
    for sy in range(src_h):
        dy = y + sy
        for sx in range(src_w):
            dx = x + sx
            a = 1.0 if alpha is None else alpha[sy * src_w + sx]
            if a <= 0.0:
                continue
            si = (sy * src_w + sx) * 3
            di = (dy * dst_w + dx) * 3
            if a >= 1.0:
                dst[di] = src[si]
                dst[di + 1] = src[si + 1]
                dst[di + 2] = src[si + 2]
            else:
                for k in range(3):
                    dst[di + k] = int(dst[di + k] * (1 - a) + src[si + k] * a + 0.5)


def upscale_nn(buf, w, h, factor):
    """Nearest-neighbour magnification, so small renders stay inspectable."""
    W, H = w * factor, h * factor
    out = bytearray(W * H * 3)
    for y in range(H):
        sy = y // factor
        for x in range(W):
            sx = x // factor
            si = (sy * w + sx) * 3
            di = (y * W + x) * 3
            out[di] = buf[si]
            out[di + 1] = buf[si + 1]
            out[di + 2] = buf[si + 2]
    return out, W, H


def solid(w, h, rgb):
    buf = bytearray(w * h * 3)
    for i in range(0, len(buf), 3):
        buf[i], buf[i + 1], buf[i + 2] = rgb
    return buf


def vgradient(w, h, top, bottom):
    buf = bytearray(w * h * 3)
    i = 0
    for y in range(h):
        t = y / max(1, h - 1)
        r = int(top[0] + (bottom[0] - top[0]) * t + 0.5)
        g = int(top[1] + (bottom[1] - top[1]) * t + 0.5)
        b = int(top[2] + (bottom[2] - top[2]) * t + 0.5)
        for x in range(w):
            buf[i], buf[i + 1], buf[i + 2] = r, g, b
            i += 3
    return buf


def grayscale(buf):
    out = bytearray(len(buf))
    for i in range(0, len(buf), 3):
        y = int(0.2126 * buf[i] + 0.7152 * buf[i + 1] + 0.0722 * buf[i + 2] + 0.5)
        out[i] = out[i + 1] = out[i + 2] = y
    return out


def dummy_tile(size, base, fg, kind):
    """Neutral neighbour icons, purely for home-screen context."""
    buf = solid(size, size, hexc(base))
    f = hexc(fg)
    c = size / 2.0
    if kind == "circle":
        rad = size * 0.26
        for py in range(size):
            for px in range(size):
                d = math.hypot(px + 0.5 - c, py + 0.5 - c) - rad
                cov = clamp01(0.5 - d)
                if cov > 0:
                    i = (py * size + px) * 3
                    for k in range(3):
                        buf[i + k] = int(buf[i + k] * (1 - cov) + f[k] * cov + 0.5)
    else:                                       # rounded square
        half, rad = size * 0.21, size * 0.07
        for py in range(size):
            for px in range(size):
                qx = abs(px + 0.5 - c) - (half - rad)
                qy = abs(py + 0.5 - c) - (half - rad)
                d = math.hypot(max(qx, 0), max(qy, 0)) + min(max(qx, qy), 0) - rad
                cov = clamp01(0.5 - d)
                if cov > 0:
                    i = (py * size + px) * 3
                    for k in range(3):
                        buf[i + k] = int(buf[i + k] * (1 - cov) + f[k] * cov + 0.5)
    return buf


# --------------------------------------------------------------------------
# SVG source (the authoritative vector asset)
# --------------------------------------------------------------------------

SVG_HALF_FRAME = """<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <title>ViewFinder - Half Frame</title>
  <defs>
    <linearGradient id="veil" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#0D0C11"/>
      <stop offset="1" stop-color="#18161D"/>
    </linearGradient>
    <radialGradient id="bloom" cx="640" cy="660" r="540" gradientUnits="userSpaceOnUse">
      <stop offset="0"    stop-color="#F0A03C" stop-opacity="0.14"/>
      <stop offset="0.5"  stop-color="#F0A03C" stop-opacity="0.07"/>
      <stop offset="1"    stop-color="#F0A03C" stop-opacity="0"/>
    </radialGradient>
  </defs>

  <rect width="1024" height="1024" fill="#131218"/>
  <rect width="1024" height="1024" fill="url(#veil)" opacity="0.42"/>
  <rect width="1024" height="1024" fill="url(#bloom)"/>

  <!-- top-left bracket : frame 672x672 centred at (512,504) -->
  <path d="M176 437 V210 A42 42 0 0 1 218 168 H445"
        fill="none" stroke="#EA9A3C" stroke-width="104" stroke-linecap="butt"/>
  <!-- bottom-right bracket -->
  <path d="M848 571 V798 A42 42 0 0 1 806 840 H579"
        fill="none" stroke="#F3AC4E" stroke-width="104" stroke-linecap="butt"/>
</svg>
"""

SVG_GOLDEN_APERTURE = """<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <title>ViewFinder - Golden Aperture</title>
  <defs>
    <linearGradient id="veil" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#08080A"/>
      <stop offset="1" stop-color="#111114"/>
    </linearGradient>
    <radialGradient id="bloom" cx="512" cy="620" r="460" gradientUnits="userSpaceOnUse">
      <stop offset="0"   stop-color="#F2A544" stop-opacity="0.32"/>
      <stop offset="0.5" stop-color="#F2A544" stop-opacity="0.16"/>
      <stop offset="1"   stop-color="#F2A544" stop-opacity="0"/>
    </radialGradient>
  </defs>

  <rect width="1024" height="1024" fill="#0D0D10"/>
  <rect width="1024" height="1024" fill="url(#veil)" opacity="0.40"/>
  <rect width="1024" height="1024" fill="url(#bloom)"/>

  <g fill="none" stroke-width="64" stroke-linecap="butt">
    <path d="M162 325 V198 A48 48 0 0 1 210 150 H337" stroke="#EA9A3C"/>
    <path d="M862 325 V198 A48 48 0 0 0 814 150 H687" stroke="#EA9A3C"/>
    <path d="M162 675 V802 A48 48 0 0 0 210 850 H337" stroke="#F3AC4E"/>
    <path d="M862 675 V802 A48 48 0 0 1 814 850 H687" stroke="#F3AC4E"/>
  </g>
</svg>
"""


# --------------------------------------------------------------------------
# Sheets
# --------------------------------------------------------------------------

def sheet_variants(out):
    """2x2 grid of the four A/B combinations, 512 each."""
    cell, gap, pad = 512, 40, 40
    W = pad * 2 + cell * 2 + gap
    H = pad * 2 + cell * 2 + gap
    canvas = solid(W, H, hexc("#4A4A4E"))
    combos = [
        (True, "TL-BR"), (False, "TL-BR"),
        (True, "TR-BL"), (False, "TR-BL"),
    ]
    alpha = mask_alpha(cell)
    for idx, (flat, diag) in enumerate(combos):
        icon = render_icon(spec_half_frame(flat, diag), cell)
        x = pad + (idx % 2) * (cell + gap)
        y = pad + (idx // 2) * (cell + gap)
        blit(canvas, W, icon, cell, cell, x, y, alpha)
    write_png(out, W, H, canvas)


def sheet_small_sizes(spec, out, magnified_out=None):
    """True-size row: 180 / 120 / 80 / 60 / 40 px, iOS-masked."""
    sizes = [180, 120, 80, 60, 40]
    gap, pad = 56, 56
    W = pad * 2 + sum(sizes) + gap * (len(sizes) - 1)
    H = pad * 2 + max(sizes)
    canvas = solid(W, H, hexc("#6E6E73"))
    x = pad
    rendered = {}
    for s in sizes:
        icon = render_icon(spec, s)
        rendered[s] = icon
        blit(canvas, W, icon, s, s, x, pad + (max(sizes) - s) // 2, mask_alpha(s))
        x += s + gap
    write_png(out, W, H, canvas)

    if magnified_out:
        # 60px and 40px blown up 6x so the compression is actually visible
        mags = [(60, 6), (40, 6)]
        gap2, pad2 = 48, 48
        tiles = []
        for s, f in mags:
            up, uw, uh = upscale_nn(rendered[s], s, s, f)
            tiles.append((up, uw, uh))
        W2 = pad2 * 2 + sum(t[1] for t in tiles) + gap2 * (len(tiles) - 1)
        H2 = pad2 * 2 + max(t[2] for t in tiles)
        c2 = solid(W2, H2, hexc("#6E6E73"))
        x = pad2
        for up, uw, uh in tiles:
            blit(c2, W2, up, uw, uh, x, pad2 + (H2 - pad2 * 2 - uh) // 2)
            x += uw + gap2
        write_png(magnified_out, W2, H2, c2)


def sheet_homescreen(spec, out, dark=True):
    icon_size = 136
    W, H = 860, 300
    if dark:
        canvas = vgradient(W, H, hexc("#1C1B22"), hexc("#06060A"))
        n1 = dummy_tile(icon_size, "#2C2C2E", "#F2F2F7", "circle")
        n2 = dummy_tile(icon_size, "#0A84FF", "#FFFFFF", "square")
    else:
        canvas = vgradient(W, H, hexc("#F2EEE7"), hexc("#CBC4BA"))
        n1 = dummy_tile(icon_size, "#F2F2F7", "#8E8E93", "circle")
        n2 = dummy_tile(icon_size, "#34C759", "#FFFFFF", "square")

    icon = render_icon(spec, icon_size)
    alpha = mask_alpha(icon_size)
    gap = 76
    total = icon_size * 3 + gap * 2
    x = (W - total) // 2
    y = (H - icon_size) // 2
    for tile in (n1, icon, n2):
        blit(canvas, W, tile, icon_size, icon_size, x, y, alpha)
        x += icon_size + gap
    write_png(out, W, H, canvas)


def sheet_weight_study(specs, out, icon_size=136):
    """
    Candidate weights at true home-screen size, on both a dark and a light
    wallpaper, flanked by neutral neighbour icons for honest comparison.
    """
    n = len(specs) + 2
    gap, pad = 44, 46
    W = pad * 2 + icon_size * n + gap * (n - 1)
    band = icon_size + pad * 2
    H = band * 2
    canvas = bytearray(W * H * 3)

    dark = vgradient(W, band, hexc("#1C1B22"), hexc("#06060A"))
    light = vgradient(W, band, hexc("#F2EEE7"), hexc("#CBC4BA"))
    blit(canvas, W, dark, W, band, 0, 0)
    blit(canvas, W, light, W, band, 0, band)

    alpha = mask_alpha(icon_size)
    rows = [
        (0, dummy_tile(icon_size, "#2C2C2E", "#F2F2F7", "circle"),
            dummy_tile(icon_size, "#0A84FF", "#FFFFFF", "square")),
        (band, dummy_tile(icon_size, "#F2F2F7", "#8E8E93", "circle"),
               dummy_tile(icon_size, "#34C759", "#FFFFFF", "square")),
    ]
    icons = [render_icon(s, icon_size) for s in specs]
    for y0, n1, n2 in rows:
        x = pad
        for tile in [n1] + icons + [n2]:
            blit(canvas, W, tile, icon_size, icon_size, x, y0 + pad, alpha)
            x += icon_size + gap
    write_png(out, W, H, canvas)


def amber_coverage(frame, stroke, arm_ratio=0.401):
    """Approximate solid-amber share of the canvas, as a percentage."""
    arm = frame * arm_ratio
    return 2 * (2 * stroke * arm) / (CANVAS * CANVAS) * 100.0


def sheet_concept_compare(out):
    """Half Frame vs Golden Aperture, at 60px, magnified 6x. The decisive test."""
    s, f = 60, 6
    a = render_icon(spec_half_frame(), s)
    b = render_icon(spec_golden_aperture(), s)
    ua, uw, uh = upscale_nn(a, s, s, f)
    ub, _, _ = upscale_nn(b, s, s, f)
    gap, pad = 56, 56
    W = pad * 2 + uw * 2 + gap
    H = pad * 2 + uh
    canvas = solid(W, H, hexc("#6E6E73"))
    blit(canvas, W, ua, uw, uh, pad, pad)
    blit(canvas, W, ub, uw, uh, pad + uw + gap, pad)
    write_png(out, W, H, canvas)


# --------------------------------------------------------------------------

def main():
    os.makedirs(PNG_DIR, exist_ok=True)
    os.makedirs(SVG_DIR, exist_ok=True)

    print("SVG sources")
    for name, body in (("viewfinder-halfframe-1024.svg", SVG_HALF_FRAME),
                       ("viewfinder-goldenaperture-1024.svg", SVG_GOLDEN_APERTURE)):
        p = os.path.join(SVG_DIR, name)
        with open(p, "w") as fh:
            fh.write(body)
        print("  wrote %s" % os.path.relpath(p, ROOT))

    hf = spec_half_frame()
    ga = spec_golden_aperture()

    print("Half Frame (recommended)")
    write_png(os.path.join(PNG_DIR, "01-halfframe-1024.png"), 1024, 1024,
              render_icon(hf, 1024))
    sheet_variants(os.path.join(PNG_DIR, "02-halfframe-ab-variants.png"))
    sheet_small_sizes(hf,
                      os.path.join(PNG_DIR, "03-halfframe-true-sizes.png"),
                      os.path.join(PNG_DIR, "04-halfframe-60px-40px-magnified.png"))
    write_png(os.path.join(PNG_DIR, "05-halfframe-grayscale-tinted-512.png"), 512, 512,
              grayscale(render_icon(hf, 512)))
    sheet_homescreen(hf, os.path.join(PNG_DIR, "06-homescreen-dark.png"), dark=True)
    sheet_homescreen(hf, os.path.join(PNG_DIR, "07-homescreen-light.png"), dark=False)

    print("Golden Aperture (comparison)")
    write_png(os.path.join(PNG_DIR, "08-goldenaperture-1024.png"), 1024, 1024,
              render_icon(ga, 1024))
    sheet_small_sizes(ga, os.path.join(PNG_DIR, "09-goldenaperture-true-sizes.png"))
    write_png(os.path.join(PNG_DIR, "10-goldenaperture-grayscale-tinted-512.png"), 512, 512,
              grayscale(render_icon(ga, 512)))

    print("Head to head")
    sheet_concept_compare(os.path.join(PNG_DIR, "11-compare-at-60px-magnified.png"))

    print("done")


if __name__ == "__main__":
    main()
