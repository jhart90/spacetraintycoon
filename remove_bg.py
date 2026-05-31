"""
The sprite sheet has a near-white border (~254,254,254) and dark-space interior
background (~0-15, 0-15, 0-25). Neither belongs on the train cars.

Strategy:
  1. Make all near-white pixels (luma > 200) transparent – this covers the border.
  2. BFS flood fill from those transparent pixels into the dark interior background
     (pixels with luma < 50, connected to already-transparent area).
  3. A couple of expansion passes for anti-aliased fringe pixels.
"""
from PIL import Image
from collections import deque
import io, base64, json, os

SPRITE_NAMES = [
    "engine", "car_passenger", "car_royal",
    "car_tank", "car_cargo", "car_hazard",
    "car_cage", "car_mail", "caboose",
]

WHITE_LUMA    = 200   # pixels brighter than this = white border → transparent
DARK_LUMA     = 55    # pixels darker than this, adjacent to transparent → transparent
EXPAND_PASSES = 8

def luma(r, g, b):
    return 0.299*r + 0.587*g + 0.114*b

def remove_background(img_rgba):
    w, h = img_rgba.size
    pix = img_rgba.load()
    trans = [[False]*h for _ in range(w)]
    queue = deque()

    # Step 1: mark all near-white pixels transparent (borders)
    for y in range(h):
        for x in range(w):
            r,g,b,a = pix[x,y]
            if luma(r,g,b) > WHITE_LUMA:
                pix[x,y] = (0,0,0,0)
                trans[x][y] = True
                queue.append((x,y))

    # Step 2: BFS from white pixels into dark interior background
    while queue:
        x, y = queue.popleft()
        for dx,dy in ((-1,0),(1,0),(0,-1),(0,1)):
            nx,ny = x+dx, y+dy
            if 0<=nx<w and 0<=ny<h and not trans[nx][ny]:
                r,g,b,a = pix[nx,ny]
                if luma(r,g,b) < DARK_LUMA:
                    trans[nx][ny] = True
                    pix[nx,ny] = (0,0,0,0)
                    queue.append((nx,ny))

    # Step 3: expand a few more times to catch fringe/AA pixels
    for _ in range(EXPAND_PASSES):
        changed = False
        for y in range(h):
            for x in range(w):
                if trans[x][y]:
                    continue
                r,g,b,a = pix[x,y]
                if luma(r,g,b) >= DARK_LUMA:
                    continue  # bright pixel – keep (part of car)
                has_trans = any(
                    0<=x+dx<w and 0<=y+dy<h and trans[x+dx][y+dy]
                    for dx,dy in ((-1,0),(1,0),(0,-1),(0,1))
                )
                if has_trans:
                    trans[x][y] = True
                    pix[x,y] = (0,0,0,0)
                    changed = True
        if not changed:
            break

    return img_rgba

os.makedirs("sprites_alpha", exist_ok=True)

for name in SPRITE_NAMES:
    # Use the full-res 418px crop, remove BG, then resize to 160px
    img = Image.open(f"sprites/{name}.png").convert("RGBA")
    result = remove_background(img)
    # Resize AFTER background removal so we get clean edges
    result = result.resize((160, 160), Image.LANCZOS)
    out_path = f"sprites_alpha/{name}.png"
    result.save(out_path)
    w, h = result.size
    n_trans = sum(1 for x in range(w) for y in range(h) if result.getpixel((x,y))[3]==0)
    print(f"{name}: {100*n_trans//(w*h)}% transparent")

print("\nDone – sprites saved to sprites_alpha/")

# Re-encode assets for the game
print("\nRe-encoding assets...")
assets = {}
for name in SPRITE_NAMES:
    with open(f"sprites_alpha/{name}.png","rb") as f:
        assets[name] = base64.b64encode(f.read()).decode()

with open("planet_example.png","rb") as f:
    planet = Image.open(f).resize((256,256), Image.LANCZOS)
    buf = io.BytesIO()
    planet.save(buf, "PNG", optimize=True)
    assets["planet"] = base64.b64encode(buf.getvalue()).decode()

with open("assets.json","w") as f:
    json.dump(assets, f)

total_kb = sum(len(v) for v in assets.values())//1024
print(f"Assets encoded: {total_kb} KB total")
