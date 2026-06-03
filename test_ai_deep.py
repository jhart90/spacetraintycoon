"""
Deep AI diagnostic: simulate Very Hard AI to +11 SD and report
per-SD cargo state, iron pipeline, large-station progress.
"""
import sys, json, time
from playwright.sync_api import sync_playwright

URL = "file:///C:/Users/jackh/Desktop/Claude/Train%20Game/index.html"
TARGET_OFFSET = float(sys.argv[1]) if len(sys.argv)>1 else 11.0
FRAMES_PER_BATCH = 1000

def main():
    with sync_playwright() as p:
        b = p.chromium.launch()
        pg = b.new_page()
        errors=[]
        pg.on("pageerror", lambda e: errors.append(str(e)))
        pg.goto(URL)
        pg.wait_for_timeout(2000)
        pg.evaluate("""
        (function(){
          try{startGame();}catch(e){}
          if(typeof gs!=='undefined') gs='galaxy';
          if(typeof _aiDifficulty!=='undefined') _aiDifficulty='very_hard';
          if(typeof activePopup!=='undefined') activePopup=null;
          if(typeof popupState!=='undefined') popupState={};
          if(typeof pendingMissionIntros!=='undefined') pendingMissionIntros=[];
          window.requestAnimationFrame=function(cb){return 0;};
          window._sdLog = [];
          window._lastLogSd = -999;
        })()
        """)
        pg.wait_for_timeout(200)
        gs_sd = pg.evaluate("typeof _gameStartSd!=='undefined'?_gameStartSd:stardate")
        target = gs_sd + TARGET_OFFSET
        # Frame loop that logs per-SD train+planet state
        BATCH = f"""
        (function(n){{
          const dtG=30,dt=3,dtSd=dtG*(0.01/600);
          for(let i=0;i<n;i++){{
            if(typeof _aiDifficulty!=='undefined'&&_aiDifficulty!=='none'&&!_aiCorp&&typeof stardate!=='undefined'&&stardate>=830.05){{
              try{{_initAICorp();}}catch(e){{}}
              if(typeof activePopup!=='undefined') activePopup=null;
            }}
            if(typeof _newspaper!=='undefined'&&_newspaper) _newspaper=null;
            if(typeof activePopup!=='undefined'&&activePopup){{activePopup=null;}}
            if(typeof pendingMissionIntros!=='undefined'&&pendingMissionIntros.length) pendingMissionIntros=[];
            if(typeof pendingCarUnlocks!=='undefined'&&pendingCarUnlocks.length) pendingCarUnlocks=[];
            stardate+=dtSd;
            try{{updateCargoSupplyDemand(dtSd);}}catch(e){{}}
            try{{updateFoundries(dtG);}}catch(e){{}}
            try{{updateMissions();}}catch(e){{}}
            try{{updatePlanetDevLevels(dtSd);}}catch(e){{}}
            if(typeof trains!=='undefined'){{ for(const t of trains){{ try{{updateTrain(t,dtG);}}catch(e){{}} }} }}
            try{{updateAICorp(dtG);}}catch(e){{}}
            try{{updatePlanetOrbits(dtG,dt);}}catch(e){{}}
            try{{updateFog();}}catch(e){{}}
            // Log per-SD AI state
            if(_aiCorp && stardate - window._lastLogSd >= 1.0){{
              window._lastLogSd = stardate;
              const trs = _aiCorp.trainIndices.map(ti=>{{
                const t=trains[ti]; if(!t) return null;
                const cargo = {{}};
                for(let ci=0;ci<(t.cars||[]).length;ci++){{
                  const c=t.cars[ci], crg=(t.carCargo||[])[ci];
                  if(t.carFull?.[ci] && crg) cargo[crg] = (cargo[crg]||0)+1;
                }}
                const here = galaxy.planets[t.planetId];
                return {{
                  name:t.name,
                  cars:(t.cars||[]).slice(),
                  cargo,
                  phase:t.route?.phase||'no_route',
                  at:here?.name||'?',
                  routeStops:(t.route?.stops||[]).map(id=>galaxy.planets[id]?.name||'?'),
                  revenue:Math.round(t.totalRevenue||0)
                }};
              }}).filter(Boolean);
              const ownedSummary = [..._aiCorp.ownedPlanetIds].map(pid=>{{
                const p=galaxy.planets[pid]; if(!p) return null;
                return {{name:p.name,biome:p.type.id,
                  hasLargeStation:!!p.hasLargeStation,
                  ironDel:p.ironDelivered||0,
                  devLevel:p.devLevel||0,
                  upgrades:p.upgrades||[]}};
              }}).filter(Boolean);
              window._sdLog.push({{
                sd:Math.round(stardate*100)/100,
                credits:Math.round(_aiCorp.credits),
                revenue:Math.round(_aiCorp.totalRevenue),
                costs:Math.round(_aiCorp.totalCosts),
                stationsBuilt:_aiCorp.stationsBuilt,
                trainCount:_aiCorp.trainIndices.length,
                trains:trs,
                ownedPlanets:ownedSummary,
                trainYard:Object.assign({{}},_aiCorp.trainYard||{{}}),
              }});
            }}
          }}
          return stardate;
        }})({FRAMES_PER_BATCH})
        """
        start = time.time()
        for _ in range(60):
            sd = pg.evaluate(BATCH)
            if sd >= target: break
            if time.time() - start > 300: break
        # Grab log
        log = pg.evaluate("window._sdLog || []")
        final = pg.evaluate("""(function(){
          if(!_aiCorp) return null;
          const owned = [..._aiCorp.ownedPlanetIds].map(pid=>{
            const p=galaxy.planets[pid]; if(!p) return null;
            return {name:p.name,biome:p.type.id,hasLargeStation:!!p.hasLargeStation,
              ironDel:p.ironDelivered||0,devLevel:p.devLevel||0,upgrades:p.upgrades||[]};
          }).filter(Boolean);
          return {
            credits:Math.round(_aiCorp.credits),
            revenue:Math.round(_aiCorp.totalRevenue),
            costs:Math.round(_aiCorp.totalCosts),
            largeStations:owned.filter(p=>p.hasLargeStation).length,
            maxIron:Math.max(...owned.map(p=>p.ironDel),0),
            foundries:owned.filter(p=>p.upgrades.includes('iron_foundry')).length,
            trainYard:_aiCorp.trainYard,
            owned
          };
        })()""")
        b.close()
        # Print compact log
        print(f"=== {len(log)} SD snapshots, target {target} ===")
        for entry in log:
            cred = entry['credits']
            print(f"SD {entry['sd']:.1f} | trains={entry['trainCount']} stns={entry['stationsBuilt']} cred=${cred} rev=${entry['revenue']}")
            for t in entry['trains']:
                cargo_str = ','.join(f"{k}:{v}" for k,v in t['cargo'].items()) or 'EMPTY'
                stops = '->'.join(t['routeStops'])
                print(f"   {t['name']:<22} @{t['at']:<18} [{t['phase']:<10}] cargo={cargo_str:<28} route={stops}")
        print("\n=== FINAL ===")
        print(json.dumps(final, indent=2))
        for e in errors[:5]:
            print('ERR:', e)

if __name__ == '__main__':
    main()
