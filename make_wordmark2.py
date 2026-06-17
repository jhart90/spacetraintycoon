# Reproduces the title_card.png wordmark: two lines "SPACE TRAIN" / "TYCOON"
# in bold Orbitron sharing ONE horizontal gradient, a cyan-blue glow, and an
# Exo2 subtitle. Spec (canvas units, design scale):
#   Title    : bold Orbitron; size so "SPACE TRAIN" spans width (with buffer)
#   Glow     : shadowColor #4af, shadowBlur 24   (NO dark stroke)
#   Fill     : linear gradient, horizontal, +/-200px around center,
#              #88ddff @0 -> #fff @0.5 -> #88aaff @1
#   Subtitle : 18px "Exo 2", #89b4d8, shadowBlur 0
# All design values scaled by S for a crisp high-res transparent PNG.
import os, tempfile
from PIL import Image, ImageDraw, ImageFont, ImageFilter
from fontTools.ttLib import TTFont

ROOT = os.path.dirname(os.path.abspath(__file__))
TMP  = tempfile.mkdtemp()

def woff2_to_ttf(woff2, out):
    f = TTFont(os.path.join(ROOT, "fonts", woff2)); f.flavor = None; f.save(out); return out
orb_ttf = woff2_to_ttf("Orbitron-Variable.woff2", os.path.join(TMP, "orb.ttf"))
exo_ttf = woff2_to_ttf("Exo2-Variable.woff2",     os.path.join(TMP, "exo.ttf"))

# ---- scale: design canvas W=480 (SPACE TRAIN ~400 wide = gradient +/-200) -----
S          = 4.0
GRAD_HALF  = round(200 * S)          # gradient spans +/-200 design px
ST_TARGET  = GRAD_HALF * 2           # "SPACE TRAIN" width == gradient width
BUFFER     = round(40 * S)           # left/right buffer
SUB_PX     = round(18 * S)           # subtitle 18px design
GLOW_BLUR  = 24 * S * 0.5            # shadowBlur 24, tuned for PIL gaussian
LINE_GAP   = round(0.06 * S * 58)    # small gap between the two title lines

# ---- auto-fit Orbitron bold so "SPACE TRAIN" spans ST_TARGET ------------------
def orb(sz):
    f = ImageFont.truetype(orb_ttf, sz)
    try: f.set_variation_by_axes([700])
    except Exception: pass
    return f
probe = Image.new("RGBA", (4, 4)); pd = ImageDraw.Draw(probe)
lo, hi = 10, 1000
while lo < hi:
    mid = (lo + hi + 1) // 2
    w = pd.textlength("SPACE TRAIN", font=orb(mid))
    if w <= ST_TARGET: lo = mid
    else: hi = mid - 1
TITLE_PX   = lo
title_font = orb(TITLE_PX)

L1, L2, SUB = "SPACE TRAIN", "TYCOON", "INTERSTELLAR SHIPPING CORPORATION SIMULATOR"

# Subtitle: the spec's literal "18px" is relative to the original ~480px design
# canvas, but the subtitle string is ~4x longer than "SPACE TRAIN", so matching
# the MEASURED proportion of title_card.png is more faithful: subtitle width is
# ~0.60x the "SPACE TRAIN" width there. Auto-fit Exo 2 to that.
def exo(sz):
    f = ImageFont.truetype(exo_ttf, sz)
    try: f.set_variation_by_axes([500])
    except Exception: pass
    return f
SUB_TARGET = round(0.60 * ST_TARGET)
lo2, hi2 = 6, 400
while lo2 < hi2:
    mid = (lo2 + hi2 + 1) // 2
    if pd.textlength(SUB, font=exo(mid)) <= SUB_TARGET: lo2 = mid
    else: hi2 = mid - 1
SUB_PX   = lo2
sub_font = exo(SUB_PX)
b1  = pd.textbbox((0,0), L1,  font=title_font)
b2  = pd.textbbox((0,0), L2,  font=title_font)
bs  = pd.textbbox((0,0), SUB, font=sub_font)
h1, h2, hs = b1[3]-b1[1], b2[3]-b2[1], bs[3]-bs[1]
w1 = b1[2]-b1[0]

pad = round(GLOW_BLUR * 3 + 30)
W   = w1 + BUFFER*2 + pad*2
sub_gap = round(1.7 * SUB_PX)
H   = pad + h1 + LINE_GAP + h2 + sub_gap + hs + pad
cx  = W // 2
canvas = Image.new("RGBA", (W, H), (0,0,0,0))

y1 = pad
y2 = y1 + h1 + LINE_GAP
ys = y2 + h2 + sub_gap

def line_mask(text, font, top):
    m = Image.new("L", (W, H), 0)
    ImageDraw.Draw(m).text((cx, top), text, font=font, fill=255, anchor="ma")
    return m

# combined title interior mask (both lines, one gradient)
m1 = line_mask(L1, title_font, y1)
m2 = line_mask(L2, title_font, y2)
mt = Image.new("L", (W, H), 0)
mt.paste(255, (0,0), m1); mt.paste(255, (0,0), m2)

# ---- glow: cyan-blue silhouette, blurred, composited under (no dark stroke) ---
glow_solid = Image.new("RGBA", (W, H), (68, 170, 255, 255))     # #44aaff
glow = Image.composite(glow_solid, Image.new("RGBA",(W,H),(0,0,0,0)), mt)
glow = glow.filter(ImageFilter.GaussianBlur(GLOW_BLUR))
canvas = Image.alpha_composite(canvas, glow)
canvas = Image.alpha_composite(canvas, glow)                    # double for punch

# ---- gradient fill (absolute canvas coords, both lines sample same gradient) --
grad = Image.new("RGB", (W, 1))
g0, g1 = cx - GRAD_HALF, cx + GRAD_HALF
c0, c1, c2 = (0x88,0xdd,0xff), (0xff,0xff,0xff), (0x88,0xaa,0xff)
def lerp(a,b,t): return tuple(round(a[i]+(b[i]-a[i])*t) for i in range(3))
for x in range(W):
    t = 0.0 if g1==g0 else min(1.0, max(0.0, (x-g0)/(g1-g0)))
    col = lerp(c0,c1,t/0.5) if t < 0.5 else lerp(c1,c2,(t-0.5)/0.5)
    grad.putpixel((x,0), col)
grad = grad.resize((W, H)).convert("RGBA")
grad.putalpha(mt)
canvas = Image.alpha_composite(canvas, grad)

# ---- subtitle: solid #89b4d8, no glow ----------------------------------------
ms = line_mask(SUB, sub_font, ys)
sub_rgb = Image.new("RGBA", (W, H), (0x89, 0xb4, 0xd8, 255))
sub_rgb.putalpha(ms)
canvas = Image.alpha_composite(canvas, sub_rgb)

# ---- autocrop to content + small margin --------------------------------------
bbox = canvas.getbbox()
if bbox:
    m = round(GLOW_BLUR)
    bbox = (max(0,bbox[0]-m), max(0,bbox[1]-m), min(W,bbox[2]+m), min(H,bbox[3]+m))
    canvas = canvas.crop(bbox)
out = os.path.join(ROOT, "wordmark2.png")
canvas.save(out)
print("title_px", TITLE_PX, "fit_w", round(pd.textlength(L1,font=title_font)),
      "->", out, canvas.size)
