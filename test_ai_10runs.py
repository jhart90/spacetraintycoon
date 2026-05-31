"""
Run 10 Very Hard AI games headlessly to SD 880 (player does nothing).

Strategy: bypass the rendering loop entirely.  After loading the page we
call startGame(), jump gs → 'galaxy', then drive the simulation by directly
calling the game's update functions in a tight JavaScript loop (no canvas
draw calls → no rendering bottleneck).  Each page.evaluate() batch advances
~1 SD; we call it in a Python loop until we reach SD 880.
"""

import time, json
from playwright.sync_api import sync_playwright

GAME_URL  = "file:///C:/Users/jackh/Desktop/Claude/Train%20Game/index.html"
TARGET_SD = 880.0
TIMEOUT_S = 600        # 10-min hard limit per run
FRAMES_PER_BATCH = 2000   # game frames per page.evaluate() call
DTG       = 30          # dt(=3) × speed(=10×) — max cap

# ── batch advance: runs N game-update iterations, returns current stardate ───
# We skip canvas drawing but execute all game-logic update functions.
# AI corp is initialized automatically when stardate crosses 830.05.
BATCH_JS = f"""
(function(n) {{
  const dtG = {DTG};
  const dt  = 3;
  const dtSd = dtG * (0.01 / 600);   // stardate increment per frame

  for (let i = 0; i < n; i++) {{
    // Trigger AI corp init at SD 830.05 (mirrors what the galaxy loop does)
    if (typeof _aiDifficulty !== 'undefined' && _aiDifficulty !== 'none' &&
        !_aiCorp && typeof stardate !== 'undefined' && stardate >= 830.05) {{
      try {{ _initAICorp(); }} catch(e) {{}}
      // Clear the rival_founded popup that _initAICorp triggers
      if (typeof activePopup !== 'undefined') activePopup = null;
      if (typeof popupState  !== 'undefined') popupState  = {{}};
    }}

    // Dismiss any popup / newspaper before advancing
    if (typeof _newspaper !== 'undefined' && _newspaper) _newspaper = null;
    if (typeof activePopup !== 'undefined' && activePopup) {{
      activePopup = null;
      if (typeof popupState !== 'undefined') popupState = {{}};
    }}
    if (typeof pendingMissionIntros !== 'undefined' && pendingMissionIntros.length)
      pendingMissionIntros = [];
    if (typeof pendingCarUnlocks !== 'undefined' && pendingCarUnlocks.length)
      pendingCarUnlocks = [];

    // Advance stardate
    stardate += dtSd;

    // Core simulation update functions (order matches the galaxy loop)
    try {{ updateCargoSupplyDemand(dtSd); }} catch(e) {{}}
    try {{ updateFoundries(dtG); }}          catch(e) {{}}
    try {{ updateMissions(); }}              catch(e) {{}}
    try {{ updatePlanetDevLevels(dtSd); }}  catch(e) {{}}

    if (typeof trains !== 'undefined') {{
      for (const t of trains) {{ try {{ updateTrain(t, dtG); }} catch(e) {{}} }}
    }}
    try {{ updateAICorp(dtG); }}             catch(e) {{}}
    try {{ updatePlanetOrbits(dtG, dt); }}   catch(e) {{}}
    try {{ updateFog(); }}                   catch(e) {{}}
  }}

  return typeof stardate !== 'undefined' ? stardate : -1;
}})({FRAMES_PER_BATCH})
"""

# ── stats extractor ─────────────────────────────────────────────────────────
STATS_JS = """
(function() {
  if (typeof _aiCorp === 'undefined' || !_aiCorp) return { error: 'no _aiCorp' };
  const vals = {
    engine_constellation:10000,engine_galaxy:20000,engine_classJ:50000,
    engine_classR:70000,engine_N700:100000,
    car_passenger:5000,car_royal:12000,car_water_tank:8000,car_cargo:4000,
    car_livestock:6000,car_mail:4000,car_ice:9000,car_sand:5000,car_ore:8000,
    car_iron:10000,car_hazmat:7000,car_oil:9000,car_battery:11000,
    car_chemical:9000,car_gold:30000,car_diamond:45000,car_flowers:7000,
    car_medical:8000,caboose:3000
  };
  let trainVal = 0, engineTypes = {};
  for (const ti of _aiCorp.trainIndices) {
    const t = trains[ti]; if (!t) continue;
    for (const c of t.cars) { trainVal += vals[c] || 4000; }
    if (t.cars[0]) engineTypes[t.cars[0]] = (engineTypes[t.cars[0]] || 0) + 1;
  }
  const foundries = [..._aiCorp.ownedPlanetIds].filter(id => {
    const p = galaxy && galaxy.planets[id];
    return p && (p.upgrades||[]).includes('iron_foundry');
  }).length;
  return {
    stardate:     Math.round(stardate * 10) / 10,
    credits:      Math.round(_aiCorp.credits),
    totalRevenue: Math.round(_aiCorp.totalRevenue),
    totalCosts:   Math.round(_aiCorp.totalCosts),
    netProfit:    Math.round(_aiCorp.totalRevenue - _aiCorp.totalCosts),
    trains:       _aiCorp.trainIndices.length,
    stations:     _aiCorp.stationsBuilt,
    foundries:    foundries,
    trainAssetVal: trainVal,
    stationAsset:  _aiCorp.stationsBuilt * 50000,
    netWorth:     Math.round(_aiCorp.credits + trainVal + _aiCorp.stationsBuilt * 50000),
    discovStars:  _aiCorp.discoveredStarIds.size,
    phase:        _aiCorp.phase,
    engineTypes:  engineTypes,
    corpName:     _aiCorp.name,
  };
})()
"""

# ── single run ───────────────────────────────────────────────────────────────
def run_one(browser, run_num: int) -> dict:
    page = browser.new_page(viewport={"width": 1400, "height": 900})
    try:
        print(f"  Run {run_num}: loading...", flush=True)
        page.goto(GAME_URL)
        page.wait_for_timeout(3000)  # let the game fully init

        # Start fresh game, skip all UI screens (gs='fadeout'→'howtoplay'→…)
        page.evaluate("""
        (function() {
          try { startGame(); } catch(e) {}
          // Jump directly to 'galaxy' so the sim logic is live immediately
          if (typeof gs !== 'undefined') gs = 'galaxy';
          if (typeof _aiDifficulty !== 'undefined') _aiDifficulty = 'very_hard';
          if (typeof activePopup    !== 'undefined') activePopup   = null;
          if (typeof popupState     !== 'undefined') popupState    = {};
          if (typeof pendingMissionIntros !== 'undefined') pendingMissionIntros = [];
          // Stop the rAF loop from firing — we drive the sim ourselves
          window.requestAnimationFrame = function(cb) { return 0; };
        })()
        """)
        page.wait_for_timeout(200)

        sd0 = page.evaluate("typeof stardate !== 'undefined' ? stardate : -1")
        print(f"  Run {run_num}: starting at SD {sd0:.3f}, batch-driving sim...", flush=True)

        deadline   = time.time() + TIMEOUT_S
        last_log   = time.time()
        sd         = sd0
        batch_num  = 0

        while time.time() < deadline:
            sd = page.evaluate(BATCH_JS)
            batch_num += 1

            if sd >= TARGET_SD:
                break
            if sd < 0:
                print(f"  Run {run_num}: stardate went negative — aborting", flush=True)
                break
            if time.time() - last_log >= 10:
                elapsed = time.time() - (deadline - TIMEOUT_S)
                print(f"    SD {sd:.2f}  batch={batch_num}  t={elapsed:.0f}s", flush=True)
                last_log = time.time()

        print(f"  Run {run_num}: reached SD {sd:.2f} after {batch_num} batches", flush=True)
        stats = page.evaluate(STATS_JS)
        if stats is None:
            stats = {"error": "no _aiCorp at end", "stardate": sd}
        stats["run"] = run_num
        return stats

    except Exception as e:
        return {"run": run_num, "error": str(e), "stardate": -1}
    finally:
        try: page.close()
        except: pass

# ── table printer ────────────────────────────────────────────────────────────
def fmt(n):
    if isinstance(n, (int, float)): return f"{int(n):,}"
    return str(n) if n is not None else ""

def print_table(results):
    cols = ["run","trains","stations","foundries","netWorth","credits",
            "totalRevenue","netProfit","trainAssetVal","stationAsset",
            "discovStars","phase","stardate"]
    labels = dict(zip(cols, ["Run","Trains","Stations","Foundries","Net Worth","Credits",
                              "Revenue","Net Profit","Train Assets","Station Assets",
                              "Stars","Phase","SD"]))
    data = [[labels[c]] + [fmt(r.get(c,"")) for r in results] for c in cols]
    widths = [max(len(row[i]) for row in data) for i in range(len(results)+1)]
    sep = "  ".join("-"*w for w in widths)
    for row in data:
        print("  ".join(cell.ljust(widths[i]) for i, cell in enumerate(row)))
        if row[0] == "Run":
            print(sep)

# ── main ─────────────────────────────────────────────────────────────────────
def main():
    results = []
    with sync_playwright() as p:
        browser = p.chromium.launch(
            headless=True,
            args=["--allow-file-access-from-files", "--no-sandbox",
                  "--disable-setuid-sandbox", "--disable-gpu",
                  "--disable-background-timer-throttling",
                  "--disable-backgrounding-occluded-windows",
                  "--disable-renderer-backgrounding"]
        )
        for i in range(1, 11):
            t0    = time.time()
            stats = run_one(browser, i)
            elapsed = time.time() - t0
            stats["elapsed_s"] = round(elapsed, 1)
            print(f"  Run {i} complete in {elapsed:.0f}s  "
                  f"trains={stats.get('trains','?')}  "
                  f"stations={stats.get('stations','?')}  "
                  f"netWorth={fmt(stats.get('netWorth',0))}", flush=True)
            results.append(stats)

        browser.close()

    print("\n" + "="*90)
    print("RESULTS — Very Hard AI, SD 880, player does nothing")
    print("="*90)
    print_table(results)

    valid = [r for r in results if "error" not in r and r.get("trains") is not None]
    if valid:
        tr  = [r["trains"]   for r in valid]
        st  = [r["stations"] for r in valid]
        nw  = [r["netWorth"] for r in valid]
        ok  = sum(1 for r in valid if r["trains"] >= 25 and r["stations"] >= 25)
        print(f"\n25+ trains AND 25+ stations: {ok}/{len(valid)}")
        print(f"Trains:   min={min(tr)}  max={max(tr)}  avg={sum(tr)/len(tr):.1f}")
        print(f"Stations: min={min(st)}  max={max(st)}  avg={sum(st)/len(st):.1f}")
        print(f"NetWorth: min={fmt(min(nw))}  max={fmt(max(nw))}  avg={fmt(int(sum(nw)/len(nw)))}")

    with open("C:/Users/jackh/Desktop/Claude/Train Game/ai_test_results.json", "w") as f:
        json.dump(results, f, indent=2)
    print("\nSaved to ai_test_results.json")

if __name__ == "__main__":
    main()
