# Stacked variant of wordmark2: "SPACE" / "TRAIN" / "TYCOON" each on its own
# line, vertically stacked, sharing ONE horizontal gradient + cyan-blue glow,
# with the Exo2 subtitle below. Derived from make_wordmark2.py (same palette,
# glow, gradient spec). Outputs wordmark2_stacked.png (original untouched).
import os, tempfile
from PIL import Image, ImageDraw, ImageFont, ImageFilter
from fontTools.ttLib import TTFont

ROOT = os.path.dirname(os.path.abspath(__file__))
TMP  = tempfile.mkdtemp()

def woff2_to_ttf(woff2, out):
    f = TTFont(os.path.join(ROOT, "fonts", woff2)); f.flavor = None; f.save(out); return out
orb_ttf = woff2_to_ttf("Orbitron-Variable.woff2", os.path.join(TMP, "orb.ttf"))
exo_ttf = woff2_to_ttf("Exo2-Variable.woff2",     os.path.join(TMP, "exo.ttf"))

S          = 4.0
GRAD_HALF  = round(200 * S)          # gradient spans +/-200 design px
ST_TARGET  = GRAD_HALF * 2           # widest title word == gradient width
BUFFER     = round(40 * S)           # left/right buffer
GLOW_BLUR  = 24 * S * 0.5            # shadowBlur 24, tuned for PIL gaussian
LINE_GAP   = round(0.10 * S * 58)    # gap between the three title lines

TITLES = ["SPACE", "TRAIN", "TYCOON"]
SUB    = "INTERSTELLAR SHIPPING CORPORATION SIMULATOR"

def orb(sz):
    f = ImageFont.truetype(orb_ttf, sz)
    try: f.set_variation_by_axes([700])
    except Exception: pass
    return f
def exo(sz):
    f = ImageFont.truetype(exo_ttf, sz)
    try: f.set_variation_by_axes([500])
    except Exception: pass
    return f

probe = Image.new("RGBA", (4, 4)); pd = ImageDraw.Draw(probe)

# ---- auto-fit Orbitron bold so the WIDEST title word spans ST_TARGET ----------
lo, hi = 10, 1000
while lo < hi:
    mid = (lo + hi + 1) // 2
    w = max(pd.textlength(t, font=orb(mid)) for t in TITLES)
    if w <= ST_TARGET: lo = mid
    else: hi = mid - 1
TITLE_PX   = lo
title_font = orb(TITLE_PX)

# ---- subtitle: fit Exo 2 to ~widest title word width --------------------------
SUB_TARGET = round(1.0 * ST_TARGET)
lo2, hi2 = 6, 400
while lo2 < hi2:
    mid = (lo2 + hi2 + 1) // 2
    if pd.textlength(SUB, font=exo(mid)) <= SUB_TARGET: lo2 = mid
    else: hi2 = mid - 1
SUB_PX   = lo2
sub_font = exo(SUB_PX)

# measure each title line + subtitle
tb = [pd.textbbox((0,0), t, font=title_font) for t in TITLES]
th = [b[3]-b[1] for b in tb]
tw = [b[2]-b[0] for b in tb]
bs = pd.textbbox((0,0), SUB, font=sub_font); hs = bs[3]-bs[1]
wmax = max(tw)

pad = round(GLOW_BLUR * 3 + 30)
W   = wmax + BUFFER*2 + pad*2
sub_gap = round(1.7 * SUB_PX)
H   = pad + sum(th) + LINE_GAP*(len(TITLES)-1) + sub_gap + hs + pad
cx  = W // 2
canvas = Image.new("RGBA", (W, H), (0,0,0,0))

# vertical tops for each title line
tops = []
y = pad
for i, t in enumerate(TITLES):
    tops.append(y)
    y += th[i] + (LINE_GAP if i < len(TITLES)-1 else 0)
ys = y + sub_gap   # subtitle top

def line_mask(text, font, top):
    m = Image.new("L", (W, H), 0)
    ImageDraw.Draw(m).text((cx, top), text, font=font, fill=255, anchor="ma")
    return m

# combined title interior mask (all three lines share one gradient)
mt = Image.new("L", (W, H), 0)
for i, t in enumerate(TITLES):
    mt.paste(255, (0,0), line_mask(t, title_font, tops[i]))

# ---- glow: cyan-blue silhouette, blurred, composited under (no dark stroke) ---
glow_solid = Image.new("RGBA", (W, H), (68, 170, 255, 255))
glow = Image.composite(glow_solid, Image.new("RGBA",(W,H),(0,0,0,0)), mt)
glow = glow.filter(ImageFilter.GaussianBlur(GLOW_BLUR))
canvas = Image.alpha_composite(canvas, glow)
canvas = Image.alpha_composite(canvas, glow)

# ---- gradient fill (absolute canvas coords, all lines sample same gradient) ---
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
out = os.path.join(ROOT, "wordmark2_stacked.png")
canvas.save(out)
print("title_px", TITLE_PX, "sub_px", SUB_PX, "->", out, canvas.size)
