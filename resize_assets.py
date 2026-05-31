from PIL import Image
import base64, json, io, numpy as np

sprite_names = [
    "engine_constellation", "engine_galaxy", "engine_classJ", "engine_classR", "engine_N700",
    "car_passenger", "car_passenger_empty",
    "car_royal", "car_water_tank", "car_water_tank_empty",
    "car_cargo", "car_hazard", "car_cage", "car_mail", "car_mail_empty",
    "car_metal", "caboose", "car_ore", "car_ore_empty", "car_iron", "car_iron_empty",
    "car_gold", "car_gold_empty",
    "car_diamond", "car_diamond_empty",
]

# Sprites with large source images — use LANCZOS for better downscale quality
sprite_names_hires = [
    "car_ice", "car_ice_empty", "car_sand", "car_sand_empty",
]

assets = {}
sprite_bottoms = {}

# Sprites: resize to 160px tall, keep aspect ratio
for name in sprite_names:
    img = Image.open(f"sprites/{name}.png").convert("RGBA")
    img = img.resize((160, 160), Image.NEAREST)
    buf = io.BytesIO()
    img.save(buf, "PNG", optimize=True)
    assets[name] = base64.b64encode(buf.getvalue()).decode()

    # Find bottom-most row with substantial content (>= 3 pixels with alpha > 30)
    alpha = np.array(img)[:, :, 3]
    rows_with_content = np.where((alpha > 30).sum(axis=1) >= 3)[0]
    if len(rows_with_content) > 0:
        last_row = int(rows_with_content[-1])
        transparent_rows_at_bottom = 160 - 1 - last_row
        sprite_bottoms[name] = round(transparent_rows_at_bottom / 160, 4)
    else:
        sprite_bottoms[name] = 0.0

    print(f"{name}: {len(assets[name])//1024}KB  bottom_pad={sprite_bottoms[name]:.3f}")

# Hi-res sprites: use LANCZOS for quality downscale
for name in sprite_names_hires:
    img = Image.open(f"sprites/{name}.png").convert("RGBA")
    img = img.resize((160, 160), Image.LANCZOS)
    buf = io.BytesIO()
    img.save(buf, "PNG", optimize=True)
    assets[name] = base64.b64encode(buf.getvalue()).decode()

    alpha = np.array(img)[:, :, 3]
    rows_with_content = np.where((alpha > 30).sum(axis=1) >= 3)[0]
    if len(rows_with_content) > 0:
        last_row = int(rows_with_content[-1])
        transparent_rows_at_bottom = 160 - 1 - last_row
        sprite_bottoms[name] = round(transparent_rows_at_bottom / 160, 4)
    else:
        sprite_bottoms[name] = 0.0

    print(f"{name}: {len(assets[name])//1024}KB  bottom_pad={sprite_bottoms[name]:.3f}")

# Planet: resize to 256px
img = Image.open("planet_example.png")
img = img.resize((256, 256), Image.LANCZOS)
buf = io.BytesIO()
img.save(buf, "PNG", optimize=True)
assets["planet"] = base64.b64encode(buf.getvalue()).decode()
print(f"planet: {len(assets['planet'])//1024}KB")

assets["sprite_bottoms"] = sprite_bottoms

with open("assets.json", "w") as f:
    json.dump(assets, f)

print("\nDone. Total:", sum(len(v) for v in assets.items() if isinstance(v[1], str))//1024, "KB")
