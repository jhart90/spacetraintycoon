"""Performance profiler for the loaded save."""
import json, time
from playwright.sync_api import sync_playwright

URL = "file:///C:/Users/jackh/Desktop/Claude/Train%20Game/index.html"
SAVE_FILE = "C:/Users/jackh/Desktop/Claude/Train Game/The_Trans-Stellar_Railways_Trust_84429.stt"

with open(SAVE_FILE, "r", encoding="utf-8") as f:
    SAVE_CONTENT = f.read()

# Instrument every major update + render function with timing accumulators
INSTRUMENT_JS = """
(function(){
  window._perf = {};
  const FNS = [
    'updateCargoSupplyDemand','updateFoundries','updateMissions','updatePlanetDevLevels',
    'updateAICorp','updatePlanetOrbits','updateFog','drawGalaxy',
    'updateTrain','trackOrbit','_buildOccOrbitMap','_promoteQueueingTrainsAtPlanet',
    '_checkEngineUnlocks','_processCargoQueue','_startCargoOps','_startUnloadPhase',
    '_startLoadPhase','transitPathBlocked','findMultiHopPath','computeLiveTangent',
    'getAvailableOrbitTier','segmentBlockedByStar','_corpAssets','_recomputeMissionTargets',
    'computeSupplyRate','computeDemandRate','_drawTutorialChain',
    'drawTrainsPanel','drawPanelTabs','drawTopBar','drawPlanet','drawTrainCar',
    'drawStarRegistry','drawPokedex','drawFinancesPopup','drawCorpPopup',
    'drawTrainBuilderPopup','drawTrainDetailPopup','drawPlanetDetailPopup',
    'drawStarDetailPopup','drawTrainsPopup','drawRoutesPopup','drawPlanetStation',
    'updateCargoSupplyDemand'
  ];
  for(const fn of FNS){
    if(typeof window[fn]!=='function') continue;
    const orig=window[fn];
    window._perf[fn]={n:0,t:0,max:0};
    window[fn]=function(){
      const s=performance.now();
      try{return orig.apply(this, arguments);}
      finally{
        const d=performance.now()-s;
        window._perf[fn].n++;
        window._perf[fn].t+=d;
        if(d>window._perf[fn].max) window._perf[fn].max=d;
      }
    };
  }
  // Frame timing — wrap the rAF loop
  window._frameTimings=[];
  window._frameStartTs=performance.now();
  const _origRaf=window.requestAnimationFrame;
  window.requestAnimationFrame=function(cb){
    return _origRaf.call(window, function(ts){
      const frameStart=performance.now();
      try{return cb(ts);}
      finally{
        const fd=performance.now()-frameStart;
        window._frameTimings.push(fd);
        if(window._frameTimings.length>500) window._frameTimings.shift();
      }
    });
  };
  return Object.keys(window._perf);
})()
"""

def main():
    with sync_playwright() as p:
        b = p.chromium.launch(headless=True)
        pg = b.new_page(viewport={"width": 1400, "height": 900})
        errs = []
        pg.on("pageerror", lambda e: errs.append(("PERR", str(e))))
        pg.on("console", lambda m: errs.append((m.type, m.text)) if m.type=='error' else None)

        print("Loading game shell...")
        pg.goto(URL)
        pg.wait_for_timeout(2500)

        # Inject save and restore
        print(f"Restoring save ({len(SAVE_CONTENT):,} bytes)...")
        result = pg.evaluate(f"""
        (function(){{
          try{{
            const saveObj = JSON.parse({json.dumps(SAVE_CONTENT)});
            _restoreFromSave(saveObj);
            gs='galaxy';
            return {{ok:true, sd:stardate, trains:trains.length, planets:galaxy.planets.length, gs:gs}};
          }}catch(e){{ return {{ok:false, err:e.message, stack:e.stack}}; }}
        }})()
        """)
        print(f"Restore: {result}")
        if not result.get("ok"):
            for tag,e in errs[:5]: print(f"  {tag}: {e}")
            b.close(); return

        # Set 1x speed so the game runs roughly at real-time
        pg.evaluate("(function(){ if(typeof gameSpeedIdx!=='undefined'){gameSpeedIdx=1;} })()")

        # Instrument
        print("\nInstrumenting...")
        wrapped = pg.evaluate(INSTRUMENT_JS)
        print(f"Wrapped {len(wrapped)} functions")

        # Let the game tick at native rAF for ~10 real seconds
        # Read start stardate, then wait until +0.5 SD
        sd0 = pg.evaluate("stardate")
        print(f"\nStart SD: {sd0:.4f}")
        print(f"Target SD: {sd0+0.5:.4f}")
        print("Running game for 0.5 SD with real-time rAF...")

        # Just let it tick naturally — the page already has rAF set up
        deadline = time.time() + 60  # max 60 real seconds
        last_log = time.time()
        while time.time() < deadline:
            cur = pg.evaluate("stardate")
            if cur >= sd0 + 0.5: break
            if time.time() - last_log > 3:
                print(f"  SD now {cur:.4f} (target {sd0+0.5:.4f})")
                last_log = time.time()
            pg.wait_for_timeout(500)

        end_sd = pg.evaluate("stardate")
        print(f"End SD: {end_sd:.4f}  (elapsed {end_sd-sd0:.4f} SD)")

        # Pull perf data
        print("\nReading perf data...")
        perf = pg.evaluate("(function(){return {perf:window._perf||{}, frames:window._frameTimings||[], frameElapsed:performance.now()-window._frameStartTs};})()")

        frames = perf.get("frames", [])
        elapsed_ms = perf.get("frameElapsed", 0)
        n_frames = len(frames)
        if n_frames > 0:
            avg_ms = sum(frames)/n_frames
            mx_ms = max(frames)
            p95 = sorted(frames)[int(0.95*len(frames))] if len(frames)>20 else mx_ms
            p99 = sorted(frames)[int(0.99*len(frames))] if len(frames)>100 else mx_ms
            print(f"\n=== Frame timings ({n_frames} sampled) ===")
            print(f"  Wall elapsed: {elapsed_ms/1000:.1f} s")
            print(f"  Avg frame: {avg_ms:.2f} ms ({1000/avg_ms:.1f} FPS effective)")
            print(f"  p95 frame: {p95:.2f} ms")
            print(f"  p99 frame: {p99:.2f} ms")
            print(f"  Max frame: {mx_ms:.2f} ms")
            # count frames over 16.7ms
            slow = sum(1 for f in frames if f > 16.7)
            print(f"  Frames > 16.7 ms (under 60fps): {slow}/{n_frames} ({100*slow/n_frames:.1f}%)")
            slow_30 = sum(1 for f in frames if f > 33.3)
            print(f"  Frames > 33.3 ms (under 30fps): {slow_30}/{n_frames} ({100*slow_30/n_frames:.1f}%)")

        print(f"\n=== Per-function timings (sorted by total time) ===")
        rows = []
        for fn, d in perf.get("perf", {}).items():
            n,t,mx = d.get("n",0), d.get("t",0), d.get("max",0)
            if n == 0: continue
            rows.append((fn, n, t, t/n if n>0 else 0, mx))
        rows.sort(key=lambda r: -r[2])
        print(f"  {'function':<35} {'calls':>8} {'total_ms':>10} {'avg_ms':>9} {'max_ms':>9}")
        for fn,n,t,avg,mx in rows[:30]:
            print(f"  {fn:<35} {n:>8} {t:>10.1f} {avg:>9.3f} {mx:>9.2f}")

        b.close()

if __name__ == '__main__':
    main()
