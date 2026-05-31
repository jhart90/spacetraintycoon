"""
AI Snapshot diagnostic — run 1 (or more) Very Hard AI games headlessly to
game_start + OFFSET SD and print a rich decision-level breakdown.

Usage:
  python test_ai_snapshot.py [--offset 10] [--runs 1]

The offset is in SD past game start (~829).  Default: 10 SD.
"""
import argparse, time, json
from playwright.sync_api import sync_playwright

GAME_URL        = "file:///C:/Users/jackh/Desktop/Claude/Train%20Game/index.html"
TIMEOUT_S       = 600
FRAMES_PER_BATCH = 2000
DTG             = 30          # dt(=3) × speed(=10×) — max speed cap

# ── batch-advance: same pattern as test_ai_10runs.py ────────────────────────
BATCH_JS = f"""
(function(n) {{
  const dtG  = {DTG};
  const dt   = 3;
  const dtSd = dtG * (0.01 / 600);   // stardate increment per frame

  for (let i = 0; i < n; i++) {{
    // Trigger AI corp init at SD 830.05
    if (typeof _aiDifficulty !== 'undefined' && _aiDifficulty !== 'none' &&
        !_aiCorp && typeof stardate !== 'undefined' && stardate >= 830.05) {{
      try {{ _initAICorp(); }} catch(e) {{}}
      if (typeof activePopup !== 'undefined') activePopup = null;
      if (typeof popupState  !== 'undefined') popupState  = {{}};
    }}
    // Dismiss popups / newspapers
    if (typeof _newspaper !== 'undefined' && _newspaper) _newspaper = null;
    if (typeof activePopup !== 'undefined' && activePopup) {{
      activePopup = null;
      if (typeof popupState !== 'undefined') popupState = {{}};
    }}
    if (typeof pendingMissionIntros !== 'undefined' && pendingMissionIntros.length)
      pendingMissionIntros = [];
    if (typeof pendingCarUnlocks !== 'undefined' && pendingCarUnlocks.length)
      pendingCarUnlocks = [];

    stardate += dtSd;

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

# ── rich stats extractor ─────────────────────────────────────────────────────
RICH_STATS_JS = """
(function() {
  if (typeof _aiCorp === 'undefined' || !_aiCorp)
    return { error: 'no _aiCorp', stardate: typeof stardate !== 'undefined' ? stardate : -1 };

  const age = stardate - _gameStartSd;

  // Train asset values (mirrors test_ai_10runs.py)
  const carVals = {
    engine_constellation:10000,engine_galaxy:20000,engine_classJ:50000,
    engine_classR:70000,engine_N700:100000,
    car_passenger:5000,car_royal:12000,car_water_tank:8000,car_cargo:4000,
    car_livestock:6000,car_mail:4000,car_ice:9000,car_sand:5000,car_ore:8000,
    car_iron:10000,car_hazmat:7000,car_oil:9000,car_battery:11000,
    car_chemical:9000,car_gold:30000,car_diamond:45000,car_flowers:7000,
    car_medical:8000,caboose:3000
  };

  let trainAssetVal = 0;
  const trainDetails = _aiCorp.trainIndices.map((ti, idx) => {
    const t = trains[ti]; if (!t) return null;
    const tv = t.cars.reduce((s,c) => s + (carVals[c] || 4000), 0);
    trainAssetVal += tv;
    const routePhase = t.route ? t.route.phase : 'no_route';
    const cargoEntries = t.cargo
      ? Object.entries(t.cargo).filter(([,v]) => v > 0).map(([k,v]) => k+'×'+v)
      : [];
    const stops = (t.route?.stops || []).map(id => {
      const p = galaxy && galaxy.planets[id]; return p ? p.name : ('id:'+id);
    });
    return {
      num:       idx + 1,
      isStarter: idx < 3,
      routePhase,
      cargo:     cargoEntries.join(', ') || 'empty',
      idleTimer: Math.round((_aiCorp.idleTimers[ti] || 0) * 10) / 10,
      assetVal:  tv,
      route:     stops.join(' -> '),
    };
  }).filter(Boolean);

  // Cost of the next VH train (engine_galaxy + 5 specialist cars + caboose)
  const nextCars  = ['engine_galaxy','car_passenger','car_water_tank','car_ore','car_iron','car_oil','caboose'];
  const cCosts    = {engine_galaxy:20000,car_passenger:5000,car_water_tank:8000,
                     car_ore:8000,car_iron:10000,car_oil:9000,caboose:3000};
  const nextTrainCost      = nextCars.reduce((s,c) => s + (cCosts[c] || 4000), 0);
  const nextTrainThreshold = Math.round(nextTrainCost * 1.1);  // 1.1× buffer

  // Exploration status
  const discCount       = _aiCorp.discoveredStarIds.size;
  const explTarget      = 15;
  const activeExplorers = _aiCorp.trainIndices.filter(ti => {
    const et = trains[ti];
    if (!et?.route?.stops) return false;
    const dp = galaxy && galaxy.planets[et.route.stops[et.route.stops.length - 1]];
    return dp && !_aiCorp.discoveredStarIds.has(dp.starId);
  }).length;

  // Cooldown state
  const trainCooldownRemaining   = Math.max(0, 0.4  - (stardate - _aiCorp.lastTrainBuildSd));
  const stationCooldownRemaining = Math.max(0, 0.15 - (stardate - _aiCorp.lastStationBuildSd));
  const canBuyTrain   = _aiCorp.credits >= nextTrainThreshold && trainCooldownRemaining <= 0;
  const canBuyStation = _aiCorp.credits >= 55000             && stationCooldownRemaining <= 0;

  // Idle trains (idle threshold for VH is 5 game-minutes)
  const idleCount = _aiCorp.trainIndices.filter(ti => (_aiCorp.idleTimers[ti] || 0) > 5).length;

  const netWorth = Math.round(_aiCorp.credits + trainAssetVal + _aiCorp.stationsBuilt * 50000);

  // Action queue (type + planet id if present)
  const queue = (_aiCorp.actionQueue || []).map(a =>
    a.type + (a.planetId !== undefined ? ' @ pid=' + a.planetId : '')
  );

  // Foundries on AI planets
  const foundries = [..._aiCorp.ownedPlanetIds].filter(id => {
    const p = galaxy && galaxy.planets[id];
    return p && (p.upgrades || []).includes('iron_foundry');
  }).length;

  return {
    stardate:               Math.round(stardate * 100) / 100,
    gameStartSd:            Math.round(_gameStartSd * 100) / 100,
    age:                    Math.round(age * 100) / 100,
    phase:                  _aiCorp.phase,
    credits:                Math.round(_aiCorp.credits),
    totalRevenue:           Math.round(_aiCorp.totalRevenue),
    totalCosts:             Math.round(_aiCorp.totalCosts),
    netProfit:              Math.round(_aiCorp.totalRevenue - _aiCorp.totalCosts),
    netWorth,
    trainCount:             _aiCorp.trainIndices.length,
    purchasedTrains:        Math.max(0, _aiCorp.trainIndices.length - 3),
    stationsBuilt:          _aiCorp.stationsBuilt,
    foundries,
    trainDetails,
    actionQueue:            queue,
    nextTrainCost,
    nextTrainThreshold,
    canBuyTrain,
    credits_vs_threshold:   _aiCorp.credits - nextTrainThreshold,
    trainCooldownRemaining: Math.round(trainCooldownRemaining * 1000) / 1000,
    lastTrainBuildSd:       Math.round(_aiCorp.lastTrainBuildSd * 100) / 100,
    canBuyStation,
    stationCooldownRemaining: Math.round(stationCooldownRemaining * 1000) / 1000,
    lastStationBuildSd:     Math.round(_aiCorp.lastStationBuildSd * 100) / 100,
    discoveredStars:        discCount,
    exploreTarget:          explTarget,
    explorationComplete:    discCount >= explTarget,
    activeExplorers,
    idleTrains:             idleCount,
    revenuePerSd:           age > 0 ? Math.round(_aiCorp.totalRevenue / age) : 0,
    trainAssetVal,
    stationAssetVal:        _aiCorp.stationsBuilt * 50000,
  };
})()
"""

# ── single run ───────────────────────────────────────────────────────────────
def run_one(browser, run_num: int, offset: float) -> dict:
    page = browser.new_page(viewport={"width": 1400, "height": 900})
    try:
        print(f"\n  Run {run_num}: loading...", flush=True)
        page.goto(GAME_URL)
        page.wait_for_timeout(3000)

        page.evaluate("""
        (function() {
          try { startGame(); } catch(e) {}
          if (typeof gs !== 'undefined')            gs            = 'galaxy';
          if (typeof _aiDifficulty !== 'undefined') _aiDifficulty = 'very_hard';
          if (typeof activePopup    !== 'undefined') activePopup   = null;
          if (typeof popupState     !== 'undefined') popupState    = {};
          if (typeof pendingMissionIntros !== 'undefined') pendingMissionIntros = [];
          window.requestAnimationFrame = function(cb) { return 0; };
        })()
        """)
        page.wait_for_timeout(200)

        game_start = page.evaluate(
            "typeof _gameStartSd !== 'undefined' ? _gameStartSd : stardate"
        )
        target_sd = game_start + offset
        print(f"  Run {run_num}: gameStartSd={game_start:.3f}  target={target_sd:.3f}", flush=True)

        deadline  = time.time() + TIMEOUT_S
        last_log  = time.time()
        sd        = game_start
        batch_num = 0

        while time.time() < deadline:
            sd = page.evaluate(BATCH_JS)
            batch_num += 1
            if sd >= target_sd:
                break
            if sd < 0:
                break
            if time.time() - last_log >= 8:
                elapsed = time.time() - (deadline - TIMEOUT_S)
                print(f"    SD {sd:.2f}  batch={batch_num}  t={elapsed:.0f}s", flush=True)
                last_log = time.time()

        stats = page.evaluate(RICH_STATS_JS)
        if stats is None:
            stats = {"error": "null return from RICH_STATS_JS", "stardate": sd}
        stats["run"] = run_num
        stats["elapsed_s"] = round(time.time() - (deadline - TIMEOUT_S), 1)
        return stats

    except Exception as e:
        return {"run": run_num, "error": str(e), "stardate": -1}
    finally:
        try: page.close()
        except: pass


# ── pretty printer ───────────────────────────────────────────────────────────
def _cr(n):
    """Format an integer as comma-separated credits with $ sign."""
    return f"${int(n):,}"

def _ok(cond):
    return "[Y]" if cond else "[N]"

def print_snapshot(s: dict, run_label: str):
    if "error" in s:
        print(f"\n  !! {run_label}: {s['error']}")
        return

    W = 68
    print("\n" + "=" * W)
    print(f"  AI SNAPSHOT -- Very Hard  |  {run_label}")
    print(f"  SD {s['stardate']}  |  age={s['age']} SD  |  phase={s['phase']}")
    print("=" * W)

    # ── Fleet & Assets ──────────────────────────────────────────────────────
    bought = s.get('purchasedTrains', s['trainCount'] - 3)
    print(f"\n  FLEET & ASSETS")
    print(f"    Trains:        {s['trainCount']}  (3 free starters + {bought} purchased)")
    print(f"    Stations:      {s['stationsBuilt']}  built  (3 free starters + {max(0,s['stationsBuilt']-3)} purchased)")
    print(f"    Foundries:     {s.get('foundries', 0)}")
    print(f"    Train assets:  {_cr(s['trainAssetVal'])}")
    print(f"    Station assets:{_cr(s['stationAssetVal'])}")
    print(f"    Net Worth:     {_cr(s['netWorth'])}")

    # ── Financials ──────────────────────────────────────────────────────────
    print(f"\n  FINANCIALS")
    print(f"    Credits:       {_cr(s['credits'])}")
    print(f"    Total revenue: {_cr(s['totalRevenue'])}  ({_cr(s['revenuePerSd'])}/SD)")
    print(f"    Total costs:   {_cr(s['totalCosts'])}")
    print(f"    Net profit:    {_cr(s['netProfit'])}")

    # ── Decision Blockers ───────────────────────────────────────────────────
    crd_gap    = s['credits_vs_threshold']
    gap_str    = f"+{_cr(abs(crd_gap))}" if crd_gap >= 0 else f"-{_cr(abs(crd_gap))}"
    cd_train   = s['trainCooldownRemaining']
    cd_station = s['stationCooldownRemaining']

    print(f"\n  DECISION BLOCKERS")
    print(f"    Next train cost:   {_cr(s['nextTrainCost'])}  (threshold {_cr(s['nextTrainThreshold'])})")
    print(f"    Credits vs thresh: {gap_str}")
    ok_cr = _ok(crd_gap >= 0)
    ok_cd = _ok(cd_train == 0)
    print(f"    Buy train?  {ok_cr} credits  {ok_cd} cooldown (remaining: {cd_train:.3f} SD)  => {'CAN BUY' if s['canBuyTrain'] else 'BLOCKED'}")
    ok_s  = _ok(s['canBuyStation'])
    print(f"    Buy station?  {ok_s} credits ({_cr(s['credits'])} vs 55k)  cooldown: {cd_station:.3f} SD  => {'CAN BUY' if s['canBuyStation'] else 'BLOCKED'}")
    stars    = s['discoveredStars']
    target   = s['exploreTarget']
    complete = "COMPLETE" if s['explorationComplete'] else f"IN PROGRESS ({s['activeExplorers']} active explorer)"
    print(f"    Exploration: {stars}/{target} stars discovered  => {complete}")
    print(f"    Idle trains: {s['idleTrains']}")

    # ── Train Details ────────────────────────────────────────────────────────
    print(f"\n  TRAIN DETAILS")
    for t in s.get('trainDetails', []):
        tag     = "[STARTER]" if t['isStarter'] else "[BOUGHT ]"
        phase   = t['routePhase'].ljust(10)
        idle    = f"idle={t['idleTimer']:.1f}m"
        route   = t['route'][:50] if t['route'] else "(no route)"
        cargo   = t['cargo']
        print(f"    #{t['num']} {tag}  {phase}  {idle}  cargo={cargo}")
        if route:
            print(f"           route: {route}")

    # ── Action Queue ─────────────────────────────────────────────────────────
    queue = s.get('actionQueue', [])
    print(f"\n  ACTION QUEUE  ({len(queue)} pending)")
    for i, a in enumerate(queue):
        print(f"    [{i}] {a}")
    if not queue:
        print(f"    (empty — AI waiting for next decision tick)")

    # ── Diagnosis hints ──────────────────────────────────────────────────────
    print(f"\n  DIAGNOSIS HINTS")
    hints = []
    ratio = s['stationsBuilt'] / max(1, s['trainCount'])
    if ratio > 1.5:
        extra_sta = s['stationsBuilt'] - s['trainCount']
        wasted_k  = extra_sta * 50
        hints.append(f"  [!] Stations ({s['stationsBuilt']}) >> Trains ({s['trainCount']})  ratio={ratio:.1f}x"
                     f" -- station cadence draining ~${wasted_k}k that could fund {extra_sta} more trains")
    if not s['explorationComplete'] and s['activeExplorers'] == 0 and s['discoveredStars'] < target:
        hints.append(f"  [!] Exploration incomplete ({stars}/{target} stars) but no active explorer assigned")
    if s['revenuePerSd'] < 3000 and s['age'] > 5:
        hints.append(f"  [!] Low revenue rate ({_cr(s['revenuePerSd'])}/SD) -- trains may be exploring or stuck in orbit")
    if s['idleTrains'] > 1:
        hints.append(f"  [!] {s['idleTrains']} idle trains -- AI may be failing to find routes")
    if crd_gap < 0 and abs(crd_gap) > 30000:
        deficit = _cr(abs(crd_gap))
        hints.append(f"  [!] Credits {deficit} short of train threshold -- saving time at {_cr(s['revenuePerSd'])}/SD"
                     + (f" approx {abs(crd_gap)//max(1,s['revenuePerSd'])} SD to recover" if s['revenuePerSd'] > 0 else ""))
    for h in hints:
        print(h)
    if not hints:
        print("    (no obvious blockers detected)")

    print()


# ── multi-run aggregation ────────────────────────────────────────────────────
def aggregate(results: list, offset: float):
    valid = [r for r in results if "error" not in r]
    if not valid:
        return
    print("\n" + "=" * 68)
    print(f"  AGGREGATE  ({len(valid)} runs  |  +{offset:.0f} SD from game start)")
    print("=" * 68)
    def _avg(key):   return sum(r.get(key,0) for r in valid) / len(valid)
    def _mn(key):    return min(r.get(key,0) for r in valid)
    def _mx(key):    return max(r.get(key,0) for r in valid)
    def _fmt(v):     return f"{int(v):,}"

    print(f"  Trains:         min={_mn('trainCount')}  max={_mx('trainCount')}  avg={_avg('trainCount'):.1f}")
    print(f"  Stations:       min={_mn('stationsBuilt')}  max={_mx('stationsBuilt')}  avg={_avg('stationsBuilt'):.1f}")
    print(f"  Credits:        min={_fmt(_mn('credits'))}  max={_fmt(_mx('credits'))}  avg={_fmt(_avg('credits'))}")
    print(f"  Net Worth:      min={_fmt(_mn('netWorth'))}  max={_fmt(_mx('netWorth'))}  avg={_fmt(_avg('netWorth'))}")
    print(f"  Revenue/SD:     min={_fmt(_mn('revenuePerSd'))}  max={_fmt(_mx('revenuePerSd'))}  avg={_fmt(_avg('revenuePerSd'))}")
    print(f"  Purchased trains: avg={_avg('purchasedTrains'):.1f}  (beyond 3 free starters)")
    print(f"  Station/train ratio: avg={_avg('stationsBuilt')/_avg('trainCount'):.2f}x")
    print()


# ── main ─────────────────────────────────────────────────────────────────────
def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--offset", type=float, default=10,
                        help="SD past game start to snapshot (default: 10)")
    parser.add_argument("--runs",   type=int,   default=1,
                        help="Number of independent runs (default: 1)")
    args = parser.parse_args()

    print(f"\nVery Hard AI Snapshot — target: game_start + {args.offset:.0f} SD")
    print(f"Runs: {args.runs}")

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
        for i in range(1, args.runs + 1):
            t0    = time.time()
            stats = run_one(browser, i, args.offset)
            stats["elapsed_s"] = round(time.time() - t0, 1)
            label = f"+{args.offset:.0f} SD  (Run {i}  |  {stats['elapsed_s']:.0f}s)"
            print_snapshot(stats, label)
            results.append(stats)

        browser.close()

    if args.runs > 1:
        aggregate(results, args.offset)

    # Save raw JSON for further analysis
    out_path = f"C:/Users/jackh/Desktop/Claude/Train Game/ai_snapshot_results.json"
    with open(out_path, "w") as f:
        json.dump(results, f, indent=2)
    print(f"Raw results saved to: ai_snapshot_results.json")


if __name__ == "__main__":
    main()
