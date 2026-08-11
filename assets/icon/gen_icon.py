#!/usr/bin/env python3
"""Emit the MyStats app-icon SVG for one target pixel size.

The glyph is lucide's `gauge` (https://lucide.dev, ISC licence), drawn in white
on a dark plate.

WHY THE ARTWORK IS FULL-BLEED (this is load-bearing, measured on macOS 26.6.1)
-----------------------------------------------------------------------------
Apple's classic icon template puts an 824px rounded plate inside a 1024px
canvas and lets the app draw its own corners and shadow. On macOS 26 that
template backfires: the system treats artwork that does not reach the canvas
edge as a loose symbol, drops it onto a pale "tray", and shrinks it to fit.
Measured on this app's icon: the 824px plate came back rendered at 556px
(67.5%) inside a pale tray -- two nested rounded rectangles.

What macOS 26 actually wants is full-bleed source art. It then does the
shaping itself: scales the 1024 canvas down to 824, clips it to a superellipse
(half-width 412px, fitted exponent n = 4.55), and adds its own drop shadow.
Leaving the corners transparent is not enough -- a full-bleed *squircle* still
let the tray bleed out around the rim. The corners must be opaque, so the
plate here is a plain full-canvas rectangle.

Consequence for macOS 13-15, which do NOT clip: they show the plate with
square corners. Set ROUNDED_SOURCE = True below to draw the corners in the
source instead -- correct on macOS 13-15, tray-rimmed on macOS 26. Only one of
the two eras can be served from a single .icns.

Usage: gen_icon.py <size-in-px> [--display]   ->  SVG on stdout

`--display` draws the plate the way macOS 26 ends up showing it -- rounded,
inset to 824px, with a drop shadow -- for READMEs and other places that render
the artwork directly instead of going through the system's icon pipeline.
"""
import math
import sys

CANVAS = 1024.0        # full-bleed: the plate covers all of it (see above)
ROUNDED_SOURCE = False # True = draw our own corners, for macOS 13-15
SUPER_N = 4.55         # matches the superellipse macOS 26 clips to
PLATE = 824.0          # the size macOS 26 scales the canvas down to

# min size -> (glyph width as a share of the canvas, stroke in lucide's 24px
#              grid, grain?)
BANDS = [
    (256, 0.62, 1.5, True),
    (128, 0.64, 1.8, False),
    (64,  0.66, 2.2, False),
    (32,  0.70, 2.7, False),
    (0,   0.74, 3.3, False),
]

# lucide `gauge`, in its native 24x24 grid:
#   <path d="M3.34 19a10 10 0 1 1 17.32 0"/>   240 deg arc, centre (12,14) r=10
#   <path d="m12 14 4-4"/>                     needle (12,14) -> (16,10)
GLYPH = ('M3.34 19a10 10 0 1 1 17.32 0', 'm12 14 4-4')
GLYPH_BBOX = (1.0, 3.0, 23.0, 20.0)   # including half of a width-2 stroke


def plate_path(half, rounded=None, samples=480):
    c = CANVAS / 2
    if not (ROUNDED_SOURCE if rounded is None else rounded):
        return (f'M {c-half} {c-half} L {c+half} {c-half} '
                f'L {c+half} {c+half} L {c-half} {c+half} Z')
    pts = []
    for i in range(samples):
        t = 2 * math.pi * i / samples
        ct, st = math.cos(t), math.sin(t)
        x = math.copysign(abs(ct) ** (2 / SUPER_N), ct) * half
        y = math.copysign(abs(st) ** (2 / SUPER_N), st) * half
        pts.append((c + x, c + y))
    return 'M ' + ' L '.join(f'{x:.2f} {y:.2f}' for x, y in pts) + ' Z'


def build(size, display=False):
    ratio, stroke, grain = next(b[1:] for b in BANDS if size >= b[0])

    gw = GLYPH_BBOX[2] - GLYPH_BBOX[0]
    gh = GLYPH_BBOX[3] - GLYPH_BBOX[1]
    # The glyph is sized against the full canvas; macOS 26 scales the canvas to
    # 824, which lands the glyph at ~62% of the visible plate.
    span = PLATE if display else CANVAS
    scale = (span * ratio) / gw
    tx = CANVAS / 2 - (GLYPH_BBOX[0] + gw / 2) * scale
    ty = CANVAS / 2 - (GLYPH_BBOX[1] + gh / 2) * scale

    plate = plate_path(span / 2, rounded=True if display else None)
    inner = [f'<path d="{plate}" fill="url(#sheen)"/>']
    if grain:
        origin = (CANVAS - span) / 2
        inner.append(f'<rect x="{origin}" y="{origin}" width="{span:.0f}" '
                     f'height="{span:.0f}" filter="url(#grain)"/>')
    glyph = ''.join(f'<path d="{d}"/>' for d in GLYPH)

    return f"""<?xml version="1.0" encoding="UTF-8"?>
<!-- MyStats app icon @{size}px. Glyph: lucide `gauge` (lucide.dev, ISC licence). -->
<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}"
     viewBox="0 0 {CANVAS:.0f} {CANVAS:.0f}">
  <defs>
    <linearGradient id="plate" x1="0.15" y1="0" x2="0.85" y2="1">
      <stop offset="0%" stop-color="#4c4c53"/>
      <stop offset="50%" stop-color="#2e2e33"/>
      <stop offset="100%" stop-color="#161619"/>
    </linearGradient>
    <radialGradient id="sheen" cx="0.28" cy="0.16" r="0.82">
      <stop offset="0%" stop-color="#ffffff" stop-opacity="0.16"/>
      <stop offset="55%" stop-color="#ffffff" stop-opacity="0.03"/>
      <stop offset="100%" stop-color="#ffffff" stop-opacity="0"/>
    </radialGradient>
    <!-- fine grain: breaks up 8-bit banding across the dark gradient -->
    <filter id="grain" x="0%" y="0%" width="100%" height="100%">
      <feTurbulence type="fractalNoise" baseFrequency="0.9" numOctaves="3" seed="7"/>
      <feColorMatrix type="saturate" values="0"/>
      <feComponentTransfer><feFuncA type="linear" slope="0.055"/></feComponentTransfer>
    </filter>
    <filter id="drop" x="-25%" y="-25%" width="150%" height="150%">
      <feDropShadow dx="0" dy="14" stdDeviation="18" flood-color="#000" flood-opacity="0.36"/>
    </filter>
    <clipPath id="plateClip"><path d="{plate}"/></clipPath>
  </defs>
  <g{' filter="url(#drop)"' if display else ''}>
    <path d="{plate}" fill="url(#plate)"/>
    <g clip-path="url(#plateClip)">{''.join(inner)}</g>
  </g>
  <g transform="translate({tx:.2f} {ty:.2f}) scale({scale:.4f})"
     fill="none" stroke="#ffffff" stroke-width="{stroke}"
     stroke-linecap="round" stroke-linejoin="round">{glyph}</g>
</svg>
"""


if __name__ == '__main__':
    args = sys.argv[1:]
    display = '--display' in args
    sizes = [a for a in args if not a.startswith('--')]
    sys.stdout.write(build(int(sizes[0]) if sizes else 1024, display=display))
