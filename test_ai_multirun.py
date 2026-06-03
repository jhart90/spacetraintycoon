"""
Multi-run AI analyzer: simulates N Very Hard AI runs to OFFSET SD and prints
per-SD progress + final-state distribution + diagnostics across runs.
Usage: python test_ai_multirun.py OFFSET RUNS
"""
import sys, json, time, statistics
from playwright.sync_api import sync_playwright

URL = "file:///C:/Users/jackh/Desktop/Claude/Train%20Game/index.html"
OFFSET = float(sys.argv[1]) if len(sys.argv) > 1 else 21.0
RUNS   = int(sys.argv[2])   if len(sys.argv) > 2 else 10
FRAMES_PER_BATCH = 1500

BATCH = f"""
(function(n) {{
  const dtG = 30, dt = 3, dtSd = dtG * (0.01/600);
  for (let i = 0; i < n; i++) {{
    if (typeof _aiDifficulty!=='undefined' && _aiDifficulty!=='none' && !_aiCorp
        && typeof stardate!=='undefined' && stardate>=830.05) {{
      try{{_initAICorp();}}catch(e){{}}
    }}
    if (typeof _newspaper!=='undefined' && _newspaper) _newspaper=null;
    if (typeof activePopup!=='undefined' && activePopup) activePopup=null;
    if (typeof pendingMissionIntros!=='undefined' && pendingMissionIntros.length) pendingMissionIntros=[];
    if (typeof pendingCarUnlocks!=='undefined' && pendingCarUnlocks.length) pendingCarUnlocks=[];
    stardate += dtSd;
    try{{updateCargoSupplyDemand(dtSd);}}catch(e){{}}
    try{{updateFoundries(dtG);}}catch(e){{}}
    try{{updateMissions();}}catch(e){{}}
    try{{updatePlanetDevLevels(dtSd);}}catch(e){{}}
    if (typeof trains!=='undefined') for (const t of trains) try{{updateTrain(t,dtG);}}catch(e){{}};
    try{{updateAICorp(dtG);}}catch(e){{}}
    try{{updatePlanetOrbits(dtG,dt);}}catch(e){{}}
    try{{updateFog();}}catch(e){{}}
    if (_aiCorp && stardate - window._lastLog >= 1.0) {{
      window._lastLog = stardate;
      window._snap.push({{
        sd: Math.round(stardate*100)/100,
        cred: Math.round(_aiCorp.credits),
        rev: Math.round(_aiCorp.totalRevenue),
        costs: Math.round(_aiCorp.totalCosts),
        trains: _aiCorp.trainIndices.length,
        stns: _aiCorp.stationsBuilt,
        foundries: [..._aiCorp.ownedPlanetIds].filter(id=>{{
          const p=galaxy.planets[id]; return p&&(p.upgrades||[]).includes('iron_foundry');
        }}).length,
        largeStns: [..._aiCorp.ownedPlanetIds].filter(id=>galaxy.planets[id]?.hasLargeStation).length,
        cycle: _aiCorp._priorityCycle,
        idle: _aiCorp.trainIndices.filter(ti=>(_aiCorp.idleTimers[ti]||0)>5).length,
        lockedTrains: _aiCorp.trainIndices.filter(ti=>trains[ti]?._aiStarterLocked).length,
      }});
    }}
  }}
  return stardate;
}})({FRAMES_PER_BATCH})
"""

FINAL = """
(function(){
  if(!_aiCorp) return null;
  const owned=[..._aiCorp.ownedPlanetIds].map(id=>{
    const p=galaxy.planets[id]; if(!p) return null;
    return {name:p.name,biome:p.type.id,hasLargeStation:!!p.hasLargeStation,
      ironDel:p.ironDelivered||0,devLevel:p.devLevel||0,upgrades:(p.upgrades||[])};
  }).filter(Boolean);
  const cargoOut={};
  for(const ti of _aiCorp.trainIndices){
    const t=trains[ti]; if(!t||!t._revLog) continue;
  }
  // Aggregate per-train profit + lock state
  const trs=_aiCorp.trainIndices.map((ti,i)=>{
    const t=trains[ti]; if(!t) return null;
    let netLastSd=0;
    if(t._revLog) for(const e of t._revLog) netLastSd+=e.rev;
    return {idx:i, name:t.name, locked:!!t._aiStarterLocked,
      iron:!!t._aiIronTrain, netLastSd:Math.round(netLastSd),
      totalRev:Math.round(t.totalRevenue||0), phase:t.route?.phase||'none'};
  }).filter(Boolean);
  return {
    credits:Math.round(_aiCorp.credits),
    revenue:Math.round(_aiCorp.totalRevenue),
    costs:Math.round(_aiCorp.totalCosts),
    netWorth:Math.round(_aiCorp.credits + owned.length*50000 + trs.reduce((s,t)=>s+0,0)),
    largeStations:owned.filter(p=>p.hasLargeStation).length,
    foundries:owned.filter(p=>p.upgrades.includes('iron_foundry')).length,
    upgradesAll:owned.flatMap(p=>p.upgrades),
    maxIron:Math.max(...owned.map(p=>p.ironDel),0),
    sumIron:owned.reduce((s,p)=>s+p.ironDel,0),
    trains:trs,
    lockedTrainCount:trs.filter(t=>t.locked).length,
    ownedPlanetCount:owned.length,
    visitedCount:_aiCorp.visitedPlanetIds.size,
    discoveredStarsCount:_aiCorp.discoveredStarIds.size,
    cycle:_aiCorp._priorityCycle,
    snap:window._snap||[]
  };
})()
"""

def run_one(browser, run_num, offset):
    page = browser.new_page(viewport={"width":1400,"height":900})
    try:
        page.goto(URL)
        page.wait_for_timeout(1500)
        page.evaluate("""
        (function(){
          try{startGame();}catch(e){}
          if(typeof gs!=='undefined') gs='galaxy';
          if(typeof _aiDifficulty!=='undefined') _aiDifficulty='very_hard';
          if(typeof activePopup!=='undefined') activePopup=null;
          if(typeof popupState!=='undefined') popupState={};
          window.requestAnimationFrame=function(cb){return 0;};
          window._snap=[]; window._lastLog=-999;
        })()
        """)
        page.wait_for_timeout(100)
        gs_sd = page.evaluate("typeof _gameStartSd!=='undefined'?_gameStartSd:stardate")
        target = gs_sd + offset
        deadline = time.time() + 600
        sd = gs_sd
        while time.time() < deadline:
            sd = page.evaluate(BATCH)
            if sd >= target: break
        final = page.evaluate(FINAL)
        return final
    except Exception as e:
        return {"error":str(e)}
    finally:
        try: page.close()
        except: pass

def main():
    print(f"\n{'='*78}\nMulti-Run AI Test: OFFSET +{OFFSET} SD, RUNS={RUNS}\n{'='*78}")
    all_runs = []
    with sync_playwright() as p:
        b = p.chromium.launch()
        for i in range(RUNS):
            print(f"\n--- Run {i+1}/{RUNS} ---", flush=True)
            r = run_one(b, i+1, OFFSET)
            if r and not r.get('error'):
                all_runs.append(r)
                snap = r.get('snap',[])
                if snap:
                    last = snap[-1]
                    print(f"  Final SD ~{last['sd']:.1f}: trains={last['trains']} stns={last['stns']} "
                          f"LStns={last['largeStns']} fnd={last['foundries']} "
                          f"cred=${last['cred']} rev=${last['rev']} locked={last['lockedTrains']}")
            else:
                print(f"  ERROR: {r}")
        b.close()
    # Print per-SD progress for run 1 (illustrative)
    if all_runs:
        print(f"\n\n{'='*78}\nPER-SD PROGRESS (Run 1 illustrative)\n{'='*78}")
        for s in all_runs[0]['snap']:
            print(f"  SD {s['sd']:>6.1f} | tr={s['trains']:>2} stn={s['stns']:>2} LStn={s['largeStns']:>2} "
                  f"fnd={s['foundries']} cyc={s['cycle']:<7} cred=${s['cred']:>8} "
                  f"rev=${s['rev']:>8} idle={s['idle']} locked={s['lockedTrains']}")
        # Aggregate stats
        print(f"\n\n{'='*78}\nAGGREGATE STATS over {len(all_runs)} runs\n{'='*78}")
        def stat(name, vals, fmt='{:.1f}'):
            if not vals: return
            mn,mx,avg = min(vals),max(vals),statistics.mean(vals)
            med = statistics.median(vals)
            print(f"  {name:<25}  min={fmt.format(mn):>10}  med={fmt.format(med):>10}  avg={fmt.format(avg):>10}  max={fmt.format(mx):>10}")
        stat("Revenue",            [r['revenue'] for r in all_runs], '${:,.0f}')
        stat("Costs",              [r['costs']   for r in all_runs], '${:,.0f}')
        stat("Net (rev-costs)",    [r['revenue']-r['costs'] for r in all_runs], '${:,.0f}')
        stat("Credits",            [r['credits'] for r in all_runs], '${:,.0f}')
        stat("Train count",        [len(r['trains']) for r in all_runs], '{:.0f}')
        stat("Stations (AI-owned)",[r['ownedPlanetCount'] for r in all_runs], '{:.0f}')
        stat("Large Stations",     [r['largeStations'] for r in all_runs], '{:.0f}')
        stat("Foundries",          [r['foundries'] for r in all_runs], '{:.0f}')
        stat("Max iron / planet",  [r['maxIron'] for r in all_runs], '{:.0f}')
        stat("Sum iron all planets",[r['sumIron'] for r in all_runs], '{:.0f}')
        stat("Locked trains",      [r['lockedTrainCount'] for r in all_runs], '{:.0f}')
        stat("Discovered stars",   [r['discoveredStarsCount'] for r in all_runs], '{:.0f}')
        # Upgrade distribution
        upg_counts={}
        for r in all_runs:
            for u in r.get('upgradesAll',[]):
                upg_counts[u]=upg_counts.get(u,0)+1
        if upg_counts:
            print("\n  UPGRADE BUILD COUNTS (across all runs):")
            for u in sorted(upg_counts,key=lambda k:-upg_counts[k]):
                print(f"    {u:<24}  {upg_counts[u]} build(s)")

if __name__ == '__main__':
    main()
