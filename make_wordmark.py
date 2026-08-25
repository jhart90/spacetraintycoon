# Renders the official SPACE TRAIN TYCOON wordmark (exact in-game title-screen
# spec from build_game.py ~line 4134) onto a TRANSPARENT background as a
# high-res PNG for use as a video overlay.
#
# In-game spec:
#   Title    : bold 58px Orbitron, gradient #88ddff -> #fff(.5) -> #88aaff,
#              dark outline rgba(0,0,0,.88) lineWidth 10 round, glow #44aaff blur 24
#   Subtitle : 18px "Exo 2", fill #89b4d8, dark outline lineWidth 3.5
import os, tempfile
from PIL import Image, ImageDraw, ImageFont, ImageFilter
from fontTools.ttLib import TTFont

ROOT = os.path.dirname(os.path.abspath(__file__))
TMP  = tempfile.mkdtemp()

def woff2_to_ttf(woff2, out):
    f = TTFont(os.path.join(ROOT, "fonts", woff2))
    f.flavor = None
    f.save(out)
    return out

orb_ttf = woff2_to_ttf("Orbitron-Variable.woff2", os.path.join(TMP, "orb.ttf"))
exo_ttf = woff2_to_ttf("Exo2-Variable.woff2",     os.path.join(TMP, "exo.ttf"))

# ---- master scale (in-game 58px -> render at this for a crisp 1080p overlay) --
TITLE_PX = 200                       # title cap size in the master PNG
r        = TITLE_PX / 58.0           # scale ratio vs the in-game 58px
SUB_PX   = round(18 * r)             # subtitle size, same ratio
TITLE_STROKE = max(1, round((10/2) * r))   # canvas lineWidth 10 => 5px/side
SUB_STROKE   = max(1, round((3.5/2) * r))
GLOW_BLUR    = (24 * r) * 0.55       # shadowBlur 24, tuned for PIL's gaussian
LINE_GAP     = round((122 - 90) * r) # baseline gap title->subtitle in-game

title_font = ImageFont.truetype(orb_ttf, TITLE_PX)
try: title_font.set_variation_by_axes([700])   # bold
except Exception: pass
sub_font = ImageFont.truetype(exo_ttf, SUB_PX)
try: sub_font.set_variation_by_axes([500])
except Exception: pass

TITLE = "SPACE TRAIN TYCOON"
SUB   = "INTERSTELLAR SHIPPING CORPORATION SIMULATOR"

# ---- canvas big enough for text + outline + glow bleed --------------------
pad = round(GLOW_BLUR * 3 + TITLE_STROKE + 40)
tmp = Image.new("RGBA", (10, 10))
td  = ImageDraw.Draw(tmp)
tb  = td.textbbox((0, 0), TITLE, font=title_font, stroke_width=TITLE_STROKE)
sb  = td.textbbox((0, 0), SUB,   font=sub_font,   stroke_width=SUB_STROKE)
tw, th = tb[2]-tb[0], tb[3]-tb[1]
sw, sh = sb[2]-sb[0], sb[3]-sb[1]

W = max(tw, sw) + pad*2
H = th + LINE_GAP + sh + pad*2
cx = W // 2

canvas = Image.new("RGBA", (W, H), (0, 0, 0, 0))

# title baseline-ish positioning: place title block at top pad, subtitle below
title_y = pad - tb[1]
sub_y   = pad + th + LINE_GAP - sb[1]

def text_mask(text, font, stroke, anchor_y):
    """Return (interior_mask, outline_mask) 'L' images for centered text."""
    interior = Image.new("L", (W, H), 0)
    outline  = Image.new("L", (W, H), 0)
    di, do = ImageDraw.Draw(interior), ImageDraw.Draw(outline)
    di.text((cx, anchor_y), text, font=font, fill=255, anchor="ma")
    do.text((cx, anchor_y), text, font=font, fill=255,
            stroke_width=stroke, stroke_fill=255, anchor="ma")
    return interior, outline

# ----- TITLE ---------------------------------------------------------------
ti, to = text_mask(TITLE, title_font, TITLE_STROKE, pad)

# glow: blue blurred silhouette under everything
glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
glow_solid = Image.new("RGBA", (W, H), (68, 170, 255, 255))   # #44aaff
glow = Image.composite(glow_solid, glow, to)
glow = glow.filter(ImageFilter.GaussianBlur(GLOW_BLUR))
canvas = Image.alpha_composite(canvas, glow)
canvas = Image.alpha_composite(canvas, glow)   # double for intensity

# dark outline (the whole dilated silhouette painted dark)
dark = Image.new("RGBA", (W, H), (0, 0, 0, 224))             # rgba(0,0,0,.88)
canvas = Image.alpha_composite(canvas, Image.composite(
    dark, Image.new("RGBA", (W, H), (0, 0, 0, 0)), to))

# gradient fill over the glyph interiors. Horizontal across the title width.
grad = Image.new("RGB", (W, 1))
gx0, gx1 = cx - tw//2, cx + tw//2
def lerp(a, b, t): return tuple(round(a[i] + (b[i]-a[i])*t) for i in range(3))
c0, c1, c2 = (0x88,0xdd,0xff), (0xff,0xff,0xff), (0x88,0xaa,0xff)
for x in range(W):
    t = 0 if gx1==gx0 else min(1, max(0, (x-gx0)/(gx1-gx0)))
    col = lerp(c0, c1, t/0.5) if t < 0.5 else lerp(c1, c2, (t-0.5)/0.5)
    grad.putpixel((x, 0), col)
grad = grad.resize((W, H))
grad_rgba = grad.convert("RGBA")
grad_rgba.putalpha(ti)
canvas = Image.alpha_composite(canvas, grad_rgba)

# ----- SUBTITLE ------------------------------------------------------------
si, so = text_mask(SUB, sub_font, SUB_STROKE, sub_y)
darks = Image.new("RGBA", (W, H), (0, 0, 0, 217))           # rgba(0,0,0,.85)
canvas = Image.alpha_composite(canvas, Image.composite(
    darks, Image.new("RGBA", (W, H), (0, 0, 0, 0)), so))
subfill = Image.new("RGBA", (W, H), (0x89, 0xb4, 0xd8, 255)) # #89b4d8
subfill.putalpha(si)
# rebuild subfill alpha properly (putalpha on solid replaced alpha, good)
subfill = Image.new("RGBA", (W, H), (0x89, 0xb4, 0xd8, 0))
sf = Image.new("RGBA", (W, H), (0x89, 0xb4, 0xd8, 255))
canvas = Image.alpha_composite(canvas, Image.composite(
    sf, subfill, si))

# ----- autocrop to content + small margin ----------------------------------
bbox = canvas.getbbox()
if bbox:
    m = round(GLOW_BLUR)
    bbox = (max(0,bbox[0]-m), max(0,bbox[1]-m), min(W,bbox[2]+m), min(H,bbox[3]+m))
    canvas = canvas.crop(bbox)

out = os.path.join(ROOT, "wordmark.png")
canvas.save(out)
print("Wrote", out, canvas.size)
