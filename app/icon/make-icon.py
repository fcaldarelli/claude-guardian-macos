#!/usr/bin/env python3
"""Genera l'icona dell'app: AppIcon.png (1024 px) e AppIcon.icns.

Un terminale (Claude Code) con il prompt in alto e tre sessioni sotto, ognuna con
il suo pallino di stato: al lavoro (terracotta), aspetta te (ambra), inattiva (grigio).
Palette calda avorio/terracotta. Non usa il logo di Claude, che è un marchio di Anthropic.

Requisiti: Python 3 con Pillow (pip install pillow).
Uso: python3 make-icon.py   (scrive i file nella stessa cartella)
"""
import math
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

OUT = Path(__file__).resolve().parent
SS = 4                      # supersampling per bordi morbidi
SIZE = 1024 * SS

# Palette
BG_TOP = (247, 242, 233)       # avorio
BG_BOTTOM = (231, 221, 205)    # sabbia
CARD = (43, 38, 34)            # antracite caldo
CARD_TOP = (58, 51, 45)
PROMPT = (217, 119, 87)        # terracotta
CURSOR = (240, 232, 220)
BAR = (88, 80, 72)
WORKING = (217, 119, 87)       # terracotta
WAITING = (242, 181, 68)       # ambra
IDLE = (138, 129, 120)         # grigio caldo


def s(v):
    return v * SS


def superellipse(cx, cy, half, n=5.0, steps=720):
    """Contorno a 'squircle' come le icone di macOS."""
    pts = []
    for i in range(steps):
        t = 2 * math.pi * i / steps
        c, si = math.cos(t), math.sin(t)
        pts.append((cx + half * math.copysign(abs(c) ** (2 / n), c),
                    cy + half * math.copysign(abs(si) ** (2 / n), si)))
    return pts


def vertical_gradient(size, top, bottom):
    grad = Image.new("RGB", (1, 256))
    for y in range(256):
        f = y / 255
        grad.putpixel((0, y), tuple(round(top[i] + (bottom[i] - top[i]) * f) for i in range(3)))
    return grad.resize(size, Image.BICUBIC)


def soft_shadow(mask, dy, blur, opacity, color=(40, 28, 18)):
    layer = Image.new("RGBA", mask.size, color + (0,))
    layer.putalpha(mask.point(lambda v: int(v * opacity)))
    return ImageChops.offset(layer, 0, dy).filter(ImageFilter.GaussianBlur(blur))


def build():
    size = (SIZE, SIZE)
    c = SIZE / 2
    canvas = Image.new("RGBA", size, (0, 0, 0, 0))

    # Corpo avorio con ombra
    body_mask = Image.new("L", size, 0)
    ImageDraw.Draw(body_mask).polygon(superellipse(c, c, s(412)), fill=255)
    canvas.alpha_composite(soft_shadow(body_mask, s(14), s(18), 0.40, (0, 0, 0)))
    body = vertical_gradient(size, BG_TOP, BG_BOTTOM).convert("RGBA")
    body.putalpha(body_mask)
    canvas.alpha_composite(body)

    # Finestra del terminale
    x0, y0, x1, y1 = c - s(316), c - s(286), c + s(316), c + s(290)
    radius = s(64)
    card_mask = Image.new("L", size, 0)
    ImageDraw.Draw(card_mask).rounded_rectangle((x0, y0, x1, y1), radius=radius, fill=255)
    canvas.alpha_composite(soft_shadow(card_mask, s(18), s(26), 0.45))

    card = vertical_gradient(size, CARD_TOP, CARD).convert("RGBA")
    card.putalpha(card_mask)
    canvas.alpha_composite(card)

    d = ImageDraw.Draw(canvas)

    # Prompt: chevron terracotta + cursore
    arm = s(54)
    width = s(32)
    px, py = x0 + s(70) + arm + width / 2, y0 + s(140)   # punta del chevron a destra
    d.line([(px - arm, py - arm), (px, py), (px - arm, py + arm)],
           fill=PROMPT + (255,), width=width, joint="curve")
    for (ex, ey) in [(px - arm, py - arm), (px - arm, py + arm), (px, py)]:
        d.ellipse((ex - width / 2, ey - width / 2, ex + width / 2, ey + width / 2), fill=PROMPT + (255,))
    d.rounded_rectangle((px + s(56), py + arm - s(14), px + s(176), py + arm + s(16)), radius=s(10), fill=CURSOR + (255,))

    # Tre sessioni: pallino di stato + riga di testo stilizzata
    rows = [
        (y0 + s(300), WORKING, 0.92),
        (y0 + s(400), WAITING, 0.70),
        (y0 + s(500), IDLE, 0.52),
    ]
    dot_r = s(30)
    dot_x = x0 + s(70) + dot_r
    bar_x0 = dot_x + s(66)
    bar_max = (x1 - s(70)) - bar_x0
    for (ry, color, frac) in rows:
        d.ellipse((dot_x - dot_r, ry - dot_r, dot_x + dot_r, ry + dot_r), fill=color + (255,))
        d.rounded_rectangle((bar_x0, ry - s(15), bar_x0 + bar_max * frac, ry + s(15)),
                            radius=s(15), fill=BAR + (255,))

    # Leggero alone sul pallino "al lavoro", per suggerire attività
    glow = Image.new("L", size, 0)
    gy = rows[0][0]
    ImageDraw.Draw(glow).ellipse((dot_x - s(54), gy - s(54), dot_x + s(54), gy + s(54)), fill=90)
    glow = glow.filter(ImageFilter.GaussianBlur(s(18)))
    halo = Image.new("RGBA", size, WORKING + (0,))
    halo.putalpha(ImageChops.multiply(glow, card_mask))
    under = canvas.copy()
    canvas = Image.alpha_composite(under, halo)
    d = ImageDraw.Draw(canvas)
    d.ellipse((dot_x - dot_r, gy - dot_r, dot_x + dot_r, gy + dot_r), fill=WORKING + (255,))

    return canvas.resize((1024, 1024), Image.LANCZOS)


if __name__ == "__main__":
    icon = build()
    icon.save(OUT / "AppIcon.png")
    # Pillow genera tutte le dimensioni richieste da macOS (16 … 1024) dal PNG a 1024 px.
    icon.save(OUT / "AppIcon.icns")
    print(f"✓ {OUT / 'AppIcon.png'}\n✓ {OUT / 'AppIcon.icns'}")
