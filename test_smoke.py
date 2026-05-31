"""Smoke test: confirm turbo patch makes the game advance."""
import time
from playwright.sync_api import sync_playwright

GAME_URL = "file:///C:/Users/jackh/Desktop/Claude/Train%20Game/index.html"
MAX_SPD  = 3

TURBO_JS = f"""
(function() {{
  if (typeof gameSpeedIdx !== 'undefined') gameSpeedIdx = {MAX_SPD};
  window._turboInstalled = true;
  window.requestAnimationFrame = function(cb) {{
    return setTimeout(function() {{
      if (typeof lastT !== 'undefined') lastT = performance.now() - 50;
      cb(performance.now());
    }}, 0);
  }};
}})()
"""

DISMISSER = f"""
(function() {{
  try {{
    if (typeof _newspaper !== 'undefined' && _newspaper)   _newspaper = null;
    if (typeof activePopup !== 'undefined' && activePopup) {{ activePopup = null; popupState = {{}}; }}
    if (typeof pendingMissionIntros !== 'undefined') pendingMissionIntros = [];
    if (typeof pendingCarUnlocks    !== 'undefined') pendingCarUnlocks    = [];
    if (typeof gameSpeedIdx !== 'undefined') gameSpeedIdx = {MAX_SPD};
  }} catch(e) {{}}
}})()
"""

with sync_playwright() as p:
    browser = p.chromium.launch(
        headless=True,
        args=["--allow-file-access-from-files","--no-sandbox",
              "--disable-background-timer-throttling",
              "--disable-backgrounding-occluded-windows",
              "--disable-renderer-backgrounding"]
    )
    page = browser.new_page(viewport={"width": 1400, "height": 900})
    page.goto(GAME_URL)
    page.wait_for_timeout(3000)

    # Start fresh VH game, skip UI screens by jumping gs directly to 'galaxy'
    page.evaluate(f"""
    (function() {{
      try {{ startGame(); }} catch(e) {{}}
      // Skip fadeout->howtoplay->corpsetup->aiselect; jump straight to game
      if (typeof gs !== 'undefined') gs = 'galaxy';
      _aiDifficulty = 'very_hard';
      activePopup = null;
      pendingMissionIntros = [];
    }})()
    """)
    page.wait_for_timeout(200)
    page.evaluate(TURBO_JS)

    # Sample stardate over 20 seconds
    t0 = time.time()
    prev_sd = page.evaluate("stardate")
    print(f"t=0s  SD={prev_sd:.3f}")

    for tick in range(20):
        page.evaluate(DISMISSER)
        page.wait_for_timeout(1000)
        sd = page.evaluate("typeof stardate !== 'undefined' ? stardate : -1")
        elapsed = time.time() - t0
        delta = sd - prev_sd
        print(f"t={elapsed:.1f}s  SD={sd:.3f}  d={delta:.4f}/s  (proj 880 in {((880-sd)/max(delta,0.0001)):.0f}s)")
        prev_sd = sd

    browser.close()
