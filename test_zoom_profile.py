"""Profile drawGalaxy at multiple zoom levels with the late-game save loaded."""
import json, time
from playwright.sync_api import sync_playwright

URL = "file:///C:/Users/jackh/Desktop/Claude/Train%20Game/index.html"
SAVE_FILE = "C:/Users/jackh/Desktop/Claude/Train Game/The_Trans-Stellar_Railways_Trust_84429.stt"

with open(SAVE_FILE, "r", encoding="utf-8") as f:
    SAVE_CONTENT = f.read()

INSTRUMENT_JS = """
(function(){
  window._perf = {};
  const FNS = [
    'drawGalaxy','drawPlanet','drawPlanetClouds','drawTrainsPanel',
    'updatePlanetOrbits','drawPlanetRing','drawMoon','drawStar',
    'drawPlanetStation','drawFoundryBuilding','computeLiveTangent',
    'transitPathBlocked','segmentBlockedByStar','w2s','getMoonScreenPos',
    '_drawNebulas','_drawNebulaBackground','_drawNebulaNames','_bakeNebulaTile',
    '_genNebulaCanvas','drawTrainCar','drawTrain','generatePlanetClouds',
    'drawNewspaper','_drawTutorialChain','_drawOrbitHintCallout',
    'hexRGB','_drawStationHoverTooltipOverlay','_planetTop4','_planetTopN'
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
  return Object.keys(window._perf);
})()
"""

def reset_perf(pg):
    pg.evaluate("(function(){for(const k in window._perf){window._perf[k]={n:0,t:0,max:0};}})()")

def profile_at_scale(pg, scale, frames=60):
    """Set cam.scale, run N frames, return perf snapshot."""
    pg.evaluate(f"cam.scale={scale}; clampCamera && clampCamera();")
    # Reset perf
    reset_perf(pg)
    # Run N animation frames
    pg.evaluate(f"""
    (function(){{
      window._frameCount = 0;
      window._frameStart = performance.now();
      const target = {frames};
      function tick(){{
        if(window._frameCount >= target){{ window._done = true; return; }}
        window._frameCount++;
        try{{ drawGalaxy(performance.now(), 1); }} catch(e){{}}
        requestAnimationFrame(tick);
      }}
      window._done = false;
      tick();
    }})()
    """)
    # Wait until done
    for _ in range(200):
        if pg.evaluate("window._done"): break
        pg.wait_for_timeout(50)
    elapsed = pg.evaluate("performance.now()-window._frameStart")
    perf = pg.evaluate("window._perf")
    return {"scale": scale, "frames": frames, "elapsed_ms": elapsed, "perf": perf}

def main():
    with sync_playwright() as p:
        b = p.chromium.launch()
        pg = b.new_page(viewport={"width":1400,"height":900})
        errs = []
        pg.on("pageerror", lambda e: errs.append(("PERR", str(e))))

        pg.goto(URL); pg.wait_for_timeout(2500)
        print(f"Loading save ({len(SAVE_CONTENT):,} bytes)...")
        result = pg.evaluate(f"""
        (function(){{
          try{{
            const saveObj = JSON.parse({json.dumps(SAVE_CONTENT)});
            _restoreFromSave(saveObj);
            gs='galaxy';
            return {{ok:true, sd:stardate, trains:trains.length}};
          }}catch(e){{ return {{ok:false, err:e.message}}; }}
        }})()
        """)
        print(f"Restore: {result}")

        # Get zoom bounds
        bounds = pg.evaluate("({MIN_SC:typeof MIN_SC!=='undefined'?MIN_SC:0.01, MAX_SC:typeof MAX_SC!=='undefined'?MAX_SC:1, scale:cam.scale})")
        print(f"Zoom bounds: {bounds}")

        print("\nInstrumenting...")
        wrapped = pg.evaluate(INSTRUMENT_JS)
        print(f"Wrapped: {len(wrapped)} functions: {wrapped[:8]}...")

        # Test at a range of zoom levels from very zoomed out to medium
        # MIN_SC is fully zoomed out, MAX_SC fully zoomed in
        MIN, MAX = bounds["MIN_SC"], bounds["MAX_SC"]
        # Use log-spaced samples between min and max
        import math
        scales = [
            MIN,                    # fully zoomed out
            MIN * 1.5,
            MIN * 2.5,
            MIN * 5,
            MIN * 10,               # ~50% zoomed out
            MIN * 30,
            MAX                     # zoomed in
        ]
        # Constrain to range
        scales = [max(MIN, min(MAX, s)) for s in scales]

        print(f"\nMIN_SC={MIN}, MAX_SC={MAX}")
        print(f"Testing at {len(scales)} zoom levels...\n")
        results = []
        for s in scales:
            r = profile_at_scale(pg, s, frames=60)
            r["fps_eff"] = 1000 * r["frames"] / r["elapsed_ms"] if r["elapsed_ms"] > 0 else 0
            results.append(r)
            print(f"  scale={s:.5f}: {r['elapsed_ms']:.0f} ms for {r['frames']} frames = {r['fps_eff']:.1f} FPS effective")

        # Print drawGalaxy avg + top contributors per zoom level
        print(f"\n{'='*80}")
        print(f"{'scale':>10}  {'frames':>6}  {'elapsed':>9}  {'avg_dg':>9}  {'fps':>6}  Top expensive")
        print(f"{'='*80}")
        for r in results:
            p = r["perf"]
            dg = p.get("drawGalaxy",{})
            dg_avg = dg.get("t",0)/max(1,dg.get("n",1))
            # find top 4 funcs by total time
            others = sorted([(fn, d.get("t",0), d.get("n",1)) for fn,d in p.items() if fn != "drawGalaxy"], key=lambda x: -x[1])[:4]
            ohit = ", ".join(f"{fn}:{t:.0f}ms" for fn,t,n in others)
            print(f"  {r['scale']:>8.5f}  {r['frames']:>6}  {r['elapsed_ms']:>7.0f}ms  {dg_avg:>7.2f}ms  {r['fps_eff']:>5.1f}  {ohit}")

        # Print details for most-zoomed-out scenario
        print(f"\n{'='*80}\nDetail for fully zoomed out (scale={results[0]['scale']:.5f}):")
        p = results[0]["perf"]
        rows = sorted([(fn, d.get("n",0), d.get("t",0), d.get("max",0)) for fn,d in p.items() if d.get("n",0)>0], key=lambda r: -r[2])[:15]
        print(f"  {'function':<32} {'calls':>8} {'total_ms':>10} {'avg_ms':>9} {'max_ms':>9}")
        for fn,n,t,mx in rows:
            avg = t/max(1,n)
            print(f"  {fn:<32} {n:>8} {t:>10.1f} {avg:>9.4f} {mx:>9.2f}")

        b.close()

if __name__ == '__main__':
    main()
