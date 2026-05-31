from PIL import Image
import os

img = Image.open(r'train_example.png')
w, h = img.size
cols, rows = 3, 3
cw, ch = w // cols, h // rows

# Names: row-major order, upper-left = engine, lower-right = caboose
names = [
    "engine",    "car_passenger", "car_royal",
    "car_tank",  "car_cargo",     "car_hazard",
    "car_cage",  "car_mail",      "caboose",
]

os.makedirs("sprites", exist_ok=True)

for i, name in enumerate(names):
    r, c = divmod(i, cols)
    box = (c * cw, r * ch, (c+1) * cw, (r+1) * ch)
    sprite = img.crop(box)
    sprite.save(f"sprites/{name}.png")
    print(f"Saved sprites/{name}.png  ({box})")

print("Done.")
