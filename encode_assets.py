import base64, json, os

assets = {}
sprite_names = [
    "engine", "car_passenger", "car_royal",
    "car_tank", "car_cargo", "car_hazard",
    "car_cage", "car_mail", "caboose",
]

for name in sprite_names:
    path = f"sprites/{name}.png"
    with open(path, "rb") as f:
        assets[name] = base64.b64encode(f.read()).decode()

with open("planet_example.png", "rb") as f:
    assets["planet"] = base64.b64encode(f.read()).decode()

with open("assets.json", "w") as f:
    json.dump(assets, f)

print("Encoded", len(assets), "assets")
for k, v in assets.items():
    print(f"  {k}: {len(v)//1024}KB")
