"""Draws the addon's window textures (WallOfShameForever/media/ui/*.tga) in the site's « forge » look:
red frame with a gold and black double rim, red ribbon for titles, gold pill buttons, panels, bars.

    python tools/ui_textures.py

Each texture is drawn 4 times bigger then reduced (smooth edges). Sizes are powers of two (the game
needs them). The addon cuts them in 9 or 3 pieces (UI.lua), so a window or a button of any size keeps
sharp corners. Fills meant to be tinted in game (pill, bar track) are white: SetVertexColor colors them,
the black outlines stay black.
"""

import os
import random

from PIL import Image, ImageChops, ImageDraw, ImageFilter

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "WallOfShameForever", "media", "ui")
S = 4  # supersampling

INK = (26, 11, 6)
GOLD = (240, 196, 110)
RED_MID = (74, 16, 9)


def save(img, name):
    os.makedirs(OUT, exist_ok=True)
    img.save(os.path.join(OUT, name))  # raw, like the banners the game already shows
    print(name, img.size)


def big(w, h):
    return Image.new("RGBA", (w * S, h * S), (0, 0, 0, 0))


def small(img, w, h):
    return img.resize((w, h), Image.LANCZOS)


def rounded(draw, box, radius, fill):
    draw.rounded_rectangle([v * S for v in box], radius=radius * S, fill=fill)


def frame():
    """Window: 128x128, 9-slice with 48 px corners. Halo, black border, gold ring, black ring, dark
    red inside with an inner shadow toward the rim (the glow texture lights the middle)."""
    size, radius = 128, 30
    img = big(size, size)
    d = ImageDraw.Draw(img)
    rounded(d, (0, 0, size - 1, size - 1), radius, GOLD + (90,))          # halo 2 px
    rounded(d, (2, 2, size - 3, size - 3), radius - 2, INK + (255,))      # black 5 px
    rounded(d, (7, 7, size - 8, size - 8), radius - 7, GOLD + (255,))     # gold 7 px
    rounded(d, (14, 14, size - 15, size - 15), radius - 14, INK + (255,))  # black 5 px
    inner = (19, 19, size - 20, size - 20)
    rounded(d, inner, radius - 19, (58, 9, 6, 255))
    # inner shadow: a lighter core blurred toward the dark rim
    core = big(size, size)
    rounded(ImageDraw.Draw(core), (34, 34, size - 35, size - 35), 10, RED_MID + (255,))
    core = core.filter(ImageFilter.GaussianBlur(12 * S))
    mask = big(size, size)
    rounded(ImageDraw.Draw(mask), inner, radius - 19, (255, 255, 255, 255))
    img = Image.alpha_composite(img, ImageChops.multiply(core, mask))
    save(small(img, size, size), "frame.tga")


def shadow():
    """Drop shadow under a window: 64x64 soft black blob, 9-slice with 24 px corners."""
    size = 64
    img = big(size, size)
    rounded(ImageDraw.Draw(img), (14, 14, size - 15, size - 15), 14, (0, 0, 0, 200))
    img = img.filter(ImageFilter.GaussianBlur(8 * S))
    save(small(img, size, size), "shadow.tga")


def glow():
    """Light in the middle of a window (radial, lighter red): 256x256, stretched over the inside."""
    size = 256
    img = big(size, size)
    ImageDraw.Draw(img).ellipse([60 * S, 60 * S, (size - 60) * S, (size - 60) * S], fill=(126, 34, 20, 235))
    img = img.filter(ImageFilter.GaussianBlur(40 * S))
    save(small(img, size, size), "glow.tga")


def grain():
    """Parchment grain: 128x128 tile of warm specks (repeats without seams)."""
    size = 128
    rnd = random.Random(7)
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    px = img.load()
    for y in range(size):
        for x in range(size):
            v = rnd.random()
            if v > 0.82:
                px[x, y] = (217, 158, 97, int(min(1, (v - 0.82) / 0.18) * 70))
            elif v < 0.10:
                px[x, y] = (10, 0, 0, int((0.10 - v) / 0.10 * 60))
    save(img, "grain.tga")


def ribbon():
    """Title ribbon: 512x64 (the site's path on 400x60), 3-slice with 48 px caps."""
    w, h = 512, 64
    sx, sy = w / 400, (h - 4) / 60

    def pts(path):
        return [(x * sx * S, (y * sy + 2) * S) for x, y in path]

    outer = pts([(2, 6), (398, 2), (384, 31), (398, 58), (2, 56), (16, 30)])
    inner = pts([(10, 10), (388, 7), (377, 31), (388, 53), (10, 51), (22, 30)])
    # red gradient, top to bottom
    grad = Image.new("RGBA", (w * S, h * S))
    gd = ImageDraw.Draw(grad)
    for y in range(h * S):
        t = y / (h * S)
        gd.line([(0, y), (w * S, y)], fill=(int(201 + (142 - 201) * t), int(54 + (29 - 54) * t), int(29 + (16 - 29) * t), 255))
    mask = Image.new("L", (w * S, h * S), 0)
    ImageDraw.Draw(mask).polygon(outer, fill=255)
    img = big(w, h)
    img.paste(grad, (0, 0), mask)
    d = ImageDraw.Draw(img)
    d.line(outer + [outer[0]], fill=INK + (255,), width=4 * S, joint="curve")
    d.line(inner + [inner[0]], fill=(242, 165, 92, 230), width=int(1.6 * S), joint="curve")
    save(small(img, w, h), "ribbon.tga")


def pill():
    """Button: 128x64, capsule 36 px high + 3 px black drop (the rest is empty), 3-slice with 20 px
    caps. White fill: tinted in game (gold, red, dark)."""
    w, h, ph = 128, 64, 36
    img = big(w, h)
    d = ImageDraw.Draw(img)
    rounded(d, (0, 3, w - 1, ph + 2), ph // 2, INK + (255,))        # drop below
    rounded(d, (0, 0, w - 1, ph - 1), ph // 2, INK + (255,))        # 3 px border
    rounded(d, (3, 3, w - 4, ph - 4), ph // 2 - 3, (255, 255, 255, 255))
    # a soft light along the top of the fill
    rounded(d, (8, 5, w - 9, 9), 3, (255, 255, 255, 255))
    save(small(img, w, h), "pill.tga")


def close():
    """Close button: 64x64 gold disc, black border and drop, black cross."""
    size = 64
    img = big(size, size)
    d = ImageDraw.Draw(img)
    d.ellipse([4 * S, 7 * S, 59 * S, 62 * S], fill=INK + (255,))
    d.ellipse([4 * S, 4 * S, 59 * S, 59 * S], fill=INK + (255,))
    d.ellipse([8 * S, 8 * S, 55 * S, 55 * S], fill=GOLD + (255,))
    for a, b in (((22, 22), (41, 41)), ((41, 22), (22, 41))):
        d.line([(a[0] * S, a[1] * S), (b[0] * S, b[1] * S)], fill=INK + (255,), width=6 * S)
    save(small(img, size, size), "close.tga")


def panel():
    """Inner panel: 64x64, 9-slice with 16 px corners, dark see-through fill and a faint gold border."""
    size = 64
    img = big(size, size)
    d = ImageDraw.Draw(img)
    rounded(d, (0, 0, size - 1, size - 1), 16, GOLD + (90,))
    rounded(d, (2, 2, size - 3, size - 3), 14, INK + (150,))
    save(small(img, size, size), "panel.tga")


def bar():
    """Progress bar: track (64x32, black with a gold ring) and fill (64x32, gold gradient), 3-slice
    with 16 px caps; the capsules are 16 px high."""
    w, h, bh = 64, 32, 16
    track = big(w, h)
    d = ImageDraw.Draw(track)
    rounded(d, (0, 0, w - 1, bh - 1), bh // 2, GOLD + (120,))
    rounded(d, (2, 2, w - 3, bh - 3), bh // 2 - 2, INK + (255,))
    save(small(track, w, h), "bar.tga")
    fill = big(w, h)
    grad = Image.new("RGBA", (w * S, h * S))
    gd = ImageDraw.Draw(grad)
    for y in range(bh * S):
        t = y / (bh * S)
        gd.line([(0, y), (w * S, y)], fill=(255, int(211 + (154 - 211) * t), int(107 + (46 - 107) * t), 255))
    mask = Image.new("L", (w * S, h * S), 0)
    ImageDraw.Draw(mask).rounded_rectangle([3 * S, 3 * S, (w - 4) * S, (bh - 4) * S], radius=(bh // 2 - 3) * S, fill=255)
    fill.paste(grad, (0, 0), mask)
    save(small(fill, w, h), "barfill.tga")


def icon():
    """The guild's logo (tools/bagarre-club.png, the site's icon): icon.tga 128x128 (notification, empty
    list) and icon_round.tga 64x64 cut round (minimap button, inside its ring)."""
    logo = Image.open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "bagarre-club.png")).convert("RGBA")
    save(logo.resize((128, 128), Image.LANCZOS), "icon.tga")
    big_logo = logo.resize((64 * S, 64 * S), Image.LANCZOS)
    mask = Image.new("L", (64 * S, 64 * S), 0)
    ImageDraw.Draw(mask).ellipse([0, 0, 64 * S - 1, 64 * S - 1], fill=255)
    round_logo = Image.new("RGBA", (64 * S, 64 * S), (0, 0, 0, 0))
    round_logo.paste(big_logo, (0, 0), mask)
    save(small(round_logo, 64, 64), "icon_round.tga")


if __name__ == "__main__":
    icon()
    frame()
    shadow()
    glow()
    grain()
    ribbon()
    pill()
    close()
    panel()
    bar()
