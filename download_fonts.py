"""
One-shot helper: download the Google Fonts WOFF2 files used by Space Train so
build_game.py can inline them as base64 data URIs. After this script writes
the .woff2 files into ./fonts/, the build script reads them and emits
@font-face rules — index.html then has zero runtime dependency on
fonts.googleapis.com / fonts.gstatic.com.

Orbitron and Exo 2 are served by Google as variable fonts (one file covers
all weights), so each is stored as a single ...-Variable.woff2 file. Lato is
not a variable font, so the 400 and 700 weights are saved separately.

Re-run this only if you want to refresh the cached font files.
"""
import os, re, urllib.request

# (family, css-name, weight-css-string, out-filename)
# weight-css-string is what we write into the @font-face rule AND what we
# pass to Google for the CSS query. For variable fonts that's a range like
# "400 700" or "300 700"; for static fonts it's a single weight.
FAMILIES = [
    ("Orbitron",            "Orbitron",            "400;700",          "400 700", "Orbitron-Variable.woff2"),
    ("Exo 2",               "Exo+2",               "300;400;600;700",  "300 700", "Exo2-Variable.woff2"),
    ("UnifrakturMaguntia",  "UnifrakturMaguntia",  None,               "400",     "UnifrakturMaguntia-Regular.woff2"),
    ("Noto Sans Phags Pa",  "Noto+Sans+Phags+Pa",  None,               "400",     "NotoSansPhagsPa-Regular.woff2"),
    ("Lato",                "Lato",                "400",              "400",     "Lato-Regular.woff2"),
    ("Lato",                "Lato",                "700",              "700",     "Lato-Bold.woff2"),
]

# Modern Chrome UA so Google Fonts returns woff2 URLs (older UAs get ttf).
UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
      "AppleWebKit/537.36 (KHTML, like Gecko) "
      "Chrome/130.0 Safari/537.36")

os.makedirs("fonts", exist_ok=True)

for family, css_name, css_weights, _, fname in FAMILIES:
    if css_weights:
        css_url = (f"https://fonts.googleapis.com/css2?family={css_name}"
                   f":wght@{css_weights}&display=swap")
    else:
        css_url = f"https://fonts.googleapis.com/css2?family={css_name}&display=swap"
    print(f"Fetching CSS: {css_url}")
    req = urllib.request.Request(css_url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req) as r:
        css = r.read().decode("utf-8", "replace")

    # Find all woff2 URLs in the CSS. Variable fonts have one URL repeated
    # across multiple unicode-range blocks; static fonts have one URL per
    # weight. We just take the first URL we see (Latin subset is first).
    urls = re.findall(r"url\((https://fonts\.gstatic\.com/[^)]+\.woff2)\)", css)
    if not urls:
        print(f"  ! No woff2 URL found for {family}")
        continue
    # For static fonts the CSS includes all requested weights; first URL = first weight.
    # We requested only one weight at a time for static fonts, so first URL is correct.
    url = urls[0]
    out = os.path.join("fonts", fname)
    print(f"  Downloading: {url}")
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req) as r:
        data = r.read()
    with open(out, "wb") as f:
        f.write(data)
    print(f"  -> {out} ({len(data):,} bytes)")

print("Done. fonts/ now contains the woff2 files for build_game.py.")
