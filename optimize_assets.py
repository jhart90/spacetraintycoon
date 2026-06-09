"""
optimize_assets.py
Fixes three issues:
  1. Re-processes oversized sprites (car_flowers, car_flowers_empty,
     car_livestock, car_hazmat) to 160x160 like every other sprite.
  2. Converts WAV sounds to MP3 via ffmpeg and updates build_game.py.
  3. Removes unused sprites (car_hazard, car_cage, car_metal) from assets.json.
"""

import json, base64, io, os, subprocess, shutil, re
import numpy as np
from PIL import Image

BASE = os.path.dirname(os.path.abspath(__file__))
ASSETS_PATH = os.path.join(BASE, "assets.json")
BUILD_PATH  = os.path.join(BASE, "build_game.py")
SOUNDS_DIR  = os.path.join(BASE, "sounds")
SPRITES_DIR = os.path.join(BASE, "sprites")

with open(ASSETS_PATH, "r") as f:
    assets = json.load(f)

sprite_bottoms = assets.get("sprite_bottoms", {})

# ── FIX 1: re-process oversized sprites ──────────────────────────────────────
# Sprites listed here get re-bundled from their source PNG in sprites/ to a
# 160x160 LANCZOS-resized PNG, with a fresh sprite_bottoms value. Used for both
# (a) bringing oversized sources (~1300x1100) down to the standard bundle size
# and (b) refreshing the bundled image when the source PNG has been updated.
OVERSIZED = [
    "car_mail", "car_mail_empty",
]

def process_sprite(name):
    path = os.path.join(SPRITES_DIR, f"{name}.png")
    if not os.path.exists(path):
        print(f"  SKIP {name} — source not found at {path}")
        return

    img = Image.open(path).convert("RGBA")
    orig_w, orig_h = img.size

    # Use LANCZOS for high-res source images (better quality downscale)
    img_r = img.resize((160, 160), Image.LANCZOS)

    buf = io.BytesIO()
    img_r.save(buf, "PNG", optimize=True)
    b64 = base64.b64encode(buf.getvalue()).decode()

    # Compute sprite_bottoms
    alpha = np.array(img_r)[:, :, 3]
    rows = np.where((alpha > 30).sum(axis=1) >= 3)[0]
    if len(rows) > 0:
        last_row = int(rows[-1])
        sb = round((160 - 1 - last_row) / 160, 4)
    else:
        sb = 0.0

    old_size = len(assets.get(name, ""))
    assets[name] = b64
    sprite_bottoms[name] = sb
    new_size = len(b64)

    print(f"  {name}: {orig_w}x{orig_h} → 160x160  |  "
          f"{old_size//1024} KB → {new_size//1024} KB  |  sprite_bottom={sb}")

print("Fix 1: Re-processing oversized sprites...")
for name in OVERSIZED:
    process_sprite(name)

# ── FIX 3: remove unused sprites ─────────────────────────────────────────────
UNUSED = ["car_hazard", "car_cage", "car_metal"]

print("\nFix 3: Removing unused sprites...")
for name in UNUSED:
    if name in assets:
        sz = len(assets[name]) // 1024
        del assets[name]
        print(f"  Removed {name} ({sz} KB)")
    if name in sprite_bottoms:
        del sprite_bottoms[name]

# Save sprite_bottoms back
assets["sprite_bottoms"] = sprite_bottoms

with open(ASSETS_PATH, "w") as f:
    json.dump(assets, f)
print("\nassets.json updated.")

# ── FIX 2: convert WAV sounds to MP3 ─────────────────────────────────────────
print("\nFix 2: Converting WAV sounds to MP3...")

sound_names = ["button", "discovery", "breakdown"]
mp3_data = {}

for sn in sound_names:
    wav_path = os.path.join(SOUNDS_DIR, f"{sn}.wav")
    mp3_path = os.path.join(SOUNDS_DIR, f"{sn}.mp3")
    if not os.path.exists(wav_path):
        print(f"  SKIP {sn} — WAV not found")
        continue

    # Convert with ffmpeg: 128 kbps MP3, mono for SFX, no metadata
    result = subprocess.run([
        "ffmpeg", "-y", "-i", wav_path,
        "-codec:a", "libmp3lame", "-q:a", "4",  # VBR ~165 kbps
        "-map_metadata", "-1",
        mp3_path
    ], capture_output=True)

    if result.returncode != 0:
        print(f"  ERROR converting {sn}:", result.stderr.decode()[-200:])
        continue

    wav_size = os.path.getsize(wav_path)
    mp3_size = os.path.getsize(mp3_path)
    with open(mp3_path, "rb") as f:
        mp3_b64 = base64.b64encode(f.read()).decode()

    mp3_data[sn] = mp3_b64
    print(f"  {sn}: {wav_size//1024} KB WAV → {mp3_size//1024} KB MP3")

# Patch build_game.py: change data:audio/wav to data:audio/mpeg and use .mp3 files
if mp3_data:
    with open(BUILD_PATH, "r", encoding="utf-8") as f:
        build_src = f.read()

    # Replace the sound loading section
    old_sound_block = '''_sound_js_lines = []
for _sn in _sound_names:
    _sp = os.path.join("sounds", f"{_sn}.wav")
    with open(_sp, "rb") as _sf:
        _sb64 = base64.b64encode(_sf.read()).decode()
    _sound_js_lines.append(f\'  "{_sn}": "data:audio/wav;base64,{_sb64}"\')'''

    new_sound_block = '''_sound_js_lines = []
for _sn in _sound_names:
    # Prefer MP3 for smaller file size; fall back to WAV if MP3 not present
    _mp3 = os.path.join("sounds", f"{_sn}.mp3")
    _wav = os.path.join("sounds", f"{_sn}.wav")
    if os.path.exists(_mp3):
        _sp, _mime = _mp3, "audio/mpeg"
    else:
        _sp, _mime = _wav, "audio/wav"
    with open(_sp, "rb") as _sf:
        _sb64 = base64.b64encode(_sf.read()).decode()
    _sound_js_lines.append(f\'  "{_sn}": "data:{_mime};base64,{_sb64}"\')'''

    if old_sound_block in build_src:
        build_src = build_src.replace(old_sound_block, new_sound_block)
        with open(BUILD_PATH, "w", encoding="utf-8") as f:
            f.write(build_src)
        print("\nbuild_game.py patched to prefer MP3 over WAV.")
    else:
        print("\nWARNING: Could not find expected sound block in build_game.py — patch skipped.")
        print("Manual change needed: replace 'data:audio/wav' with 'data:audio/mpeg' and load .mp3 files.")

print("\nDone. Run `python build_game.py` to rebuild index.html.")
