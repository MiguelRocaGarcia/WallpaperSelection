"""Draws the app icon: a sunset mountain wallpaper, full-bleed.

Renders at 4x and downsamples for smooth edges. Requires Pillow.
Usage: python3 scripts/make_icon.py
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

S = 4096  # working size
OUT_SIZE = 1024
OUT = Path(__file__).resolve().parent.parent / 'WallpaperSelection/Assets.xcassets/AppIcon.appiconset/AppIcon.png'

SKY = [(0, '#ffd89b'), (.5, '#ff9f80'), (1, '#c9607e')]
SUN_COLOR, SUN_CENTER, SUN_RADIUS = '#fffaf0', (.5, .40), .13
# Back to front: color, then ridge points as (x, y) fractions of the icon.
MOUNTAINS = [
    ('#f08a6c', [(0, .58), (.18, .47), (.33, .56), (.52, .40), (.7, .54), (.86, .46), (1, .55)]),
    ('#7b3f8c', [(0, .70), (.15, .60), (.35, .72), (.58, .57), (.78, .70), (1, .62)]),
    ('#2e1f55', [(0, .82), (.25, .72), (.45, .83), (.7, .74), (1, .84)]),
]


def hex_rgb(h):
    h = h.lstrip('#')
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def vertical_gradient(size, stops):
    img = Image.new('RGB', (size, size))
    draw = ImageDraw.Draw(img)
    stops = [(p, hex_rgb(c)) for p, c in stops]
    for y in range(size):
        t = y / (size - 1)
        for (p0, c0), (p1, c1) in zip(stops, stops[1:]):
            if p0 <= t <= p1:
                f = (t - p0) / (p1 - p0)
                draw.line([(0, y), (size, y)], fill=tuple(int(c0[i] + (c1[i] - c0[i]) * f) for i in range(3)))
                break
    return img


def draw_icon():
    img = vertical_gradient(S, SKY)
    cx, cy, r = SUN_CENTER[0] * S, SUN_CENTER[1] * S, SUN_RADIUS * S

    glow = Image.new('L', (S, S), 0)
    ImageDraw.Draw(glow).ellipse([cx - r * 1.9, cy - r * 1.9, cx + r * 1.9, cy + r * 1.9], fill=90)
    glow = glow.filter(ImageFilter.GaussianBlur(r * 0.6))
    img = Image.composite(Image.new('RGB', (S, S), SUN_COLOR), img, glow)

    draw = ImageDraw.Draw(img)
    draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=SUN_COLOR)
    for color, ridge in MOUNTAINS:
        draw.polygon([(0, S)] + [(x * S, y * S) for x, y in ridge] + [(S, S)], fill=color)
    return img


if __name__ == '__main__':
    OUT.parent.mkdir(parents=True, exist_ok=True)
    # iOS rejects icons with transparency, so save plain RGB.
    draw_icon().resize((OUT_SIZE, OUT_SIZE), Image.LANCZOS).save(OUT)
    print(f'Wrote {OUT}')
