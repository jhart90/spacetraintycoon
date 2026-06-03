"""Single-run per-SD trace, fixed formatting."""
import sys, time
from playwright.sync_api import sync_playwright

URL="file:///C:/Users/jackh/Desktop/Claude/Train%20Game/index.html"
OFFSET=float(sys.argv[1]) if len(sys.argv)>1 else 31.0

BATCH=f"""
(function(n){{
  const dtG=30,dt=3,dtSd=dtG*(0.01/600);
  for(let i=0;i<n;i++){{
    if(typeof _aiDifficulty!=='undefined'&&_aiDifficulty!=='none'&&!_aiCorp&&typeof stardate!=='undefined'&&stardate>=830.05){{try{{_initAICorp();}}catch(e){{}}}}
    if(typeof _newspaper!=='undefined'&&_newspaper) _newspaper=null;
    if(typeof activePopup!=='undefined'&&activePopup) activePopup=null;
    if(typeof pendingMissionIntros!=='undefined'&&pendingMissionIntros.length) pendingMissionIntros=[];
    stardate+=dtSd;
    try{{updateCargoSupplyDemand(dtSd);}}catch(e){{}}
    try{{updateFoundries(dtG);}}catch(e){{}}
    try{{updateMissions();}}catch(e){{}}
    try{{updatePlanetDevLevels(dtSd);}}catch(e){{}}
    if(typeof trains!=='undefined') for(const t of trains) try{{updateTrain(t,dtG);}}catch(e){{}};
    try{{updateAICorp(dtG);}}catch(e){{}}
    try{{updatePlanetOrbits(dtG,dt);}}catch(e){{}}
    try{{updateFog();}}catch(e){{}}
    if(_aiCorp && stardate-window._lastLog>=1.0){{
      window._lastLog=stardate;
      window._snap.push({{
        sd:Math.round(stardate*100)/100,
        cred:Math.round(_aiCorp.credits),
        rev:Math.round(_aiCorp.totalRevenue),
        trains:_aiCorp.trainIndices.length,
        stns:_aiCorp.stationsBuilt,
        fnd:[..._aiCorp.ownedPlanetIds].filter(id=>(galaxy.planets[id]?.upgrades||[]).includes('iron_foundry')).length,
        lstn:[..._aiCorp.ownedPlanetIds].filter(id=>galaxy.planets[id]?.hasLargeStation).length,
        locked:_aiCorp.trainIndices.filter(ti=>trains[ti]?._aiStarterLocked).length,
        cycle:_aiCorp._priorityCycle||'?',
        idle:_aiCorp.trainIndices.filter(ti=>(_aiCorp.idleTimers[ti]||0)>5).length,
      }});
    }}
  }}
  return stardate;
}})(1500)
"""

with sync_playwright() as p:
    b=p.chromium.launch()
    pg=b.new_page()
    pg.goto(URL); pg.wait_for_timeout(1500)
    pg.evaluate("""(function(){
      try{startGame();}catch(e){}
      if(typeof gs!=='undefined') gs='galaxy';
      if(typeof _aiDifficulty!=='undefined') _aiDifficulty='very_hard';
      if(typeof activePopup!=='undefined') activePopup=null;
      window.requestAnimationFrame=function(){return 0;};
      window._snap=[]; window._lastLog=-999;
    })()""")
    pg.wait_for_timeout(100)
    gs=pg.evaluate("typeof _gameStartSd!=='undefined'?_gameStartSd:stardate")
    target=gs+OFFSET
    while True:
        sd=pg.evaluate(BATCH)
        if sd>=target: break
    snap=pg.evaluate("window._snap||[]")
    b.close()
    print(f"\n{'SD':>6} | {'Tr':>2} {'Stn':>3} {'LSt':>3} {'Fnd':>3} {'Cyc':<7} {'Cred':>10} {'Rev':>10} {'Idle':>4} {'Lck':>3}")
    print("-"*68)
    for s in snap:
        if s is None: continue
        print(f"{s.get('sd',0):>6.1f} | {s.get('trains',0):>2} {s.get('stns',0):>3} {s.get('lstn',0):>3} {s.get('fnd',0):>3} {(s.get('cycle') or '-'):<7} ${s.get('cred',0):>9,} ${s.get('rev',0):>9,} {s.get('idle',0):>4} {s.get('locked',0):>3}")
