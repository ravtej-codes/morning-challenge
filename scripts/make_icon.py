"""Regenerates the app icon: a sun rising over the horizon, in the app's accent orange.

Usage: python scripts/make_icon.py   (needs Pillow)
Writes a 1024x1024 opaque PNG; iOS applies the rounded corners itself.
"""
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
SCALE = 4  # draw large, then downsample for smooth edges
S = SIZE * SCALE
OUT = Path(__file__).resolve().parent.parent / "App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"

SKY_TOP = (20, 18, 43)
SKY_LOW = (122, 54, 66)
GROUND = (14, 12, 28)
SUN_TOP = (255, 205, 120)
SUN_LOW = (250, 158, 64)  # the app's accent colour
HORIZON = int(S * 0.68)
CENTER = (S // 2, HORIZON)
RADIUS = int(S * 0.235)


def lerp(a, b, t):
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def vertical_gradient(top, low, y0, y1):
    """An image S wide and S tall whose colour runs from top at y0 to low at y1."""
    col = Image.new("RGB", (1, S))
    for y in range(S):
        col.putpixel((0, y), lerp(top, low, min(max((y - y0) / (y1 - y0), 0), 1)))
    return col.resize((S, S))


img = vertical_gradient(SKY_TOP, SKY_LOW, 0, HORIZON)

# Soft glow behind the sun.
glow = Image.new("L", (S, S), 0)
r = int(RADIUS * 1.75)
ImageDraw.Draw(glow).ellipse([CENTER[0] - r, CENTER[1] - r, CENTER[0] + r, CENTER[1] + r], fill=120)
glow = glow.filter(ImageFilter.GaussianBlur(S * 0.05))
img.paste(Image.new("RGB", (S, S), SUN_LOW), mask=glow)

# Rays: rounded bars fanning out above the horizon.
sun_fill = vertical_gradient(SUN_TOP, SUN_LOW, HORIZON - RADIUS, HORIZON)
rays = Image.new("L", (S, S), 0)
d = ImageDraw.Draw(rays)
inner, outer, width = RADIUS * 1.24, RADIUS * 1.62, int(S * 0.036)
for deg in (-60, -30, 0, 30, 60):
    a = math.radians(deg - 90)
    p0 = (CENTER[0] + inner * math.cos(a), CENTER[1] + inner * math.sin(a))
    p1 = (CENTER[0] + outer * math.cos(a), CENTER[1] + outer * math.sin(a))
    d.line([p0, p1], fill=255, width=width)
    for x, y in (p0, p1):
        d.ellipse([x - width / 2, y - width / 2, x + width / 2, y + width / 2], fill=255)
img.paste(sun_fill, mask=rays)

# The sun.
disc = Image.new("L", (S, S), 0)
ImageDraw.Draw(disc).ellipse(
    [CENTER[0] - RADIUS, CENTER[1] - RADIUS, CENTER[0] + RADIUS, CENTER[1] + RADIUS], fill=255
)
img.paste(sun_fill, mask=disc)

# The ground hides the lower half of the sun.
ImageDraw.Draw(img).rectangle([0, HORIZON, S, S], fill=GROUND)

OUT.parent.mkdir(parents=True, exist_ok=True)
img.resize((SIZE, SIZE), Image.LANCZOS).convert("RGB").save(OUT, optimize=True)
print(f"wrote {OUT}")
