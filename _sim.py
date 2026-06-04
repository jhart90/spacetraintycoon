"""Simulate forward, log PLASMA SURGE's route state every transition."""
import json, sys
sys.stdout.reconfigure(encoding='utf-8')
from playwright.sync_api import sync_playwright

URL = "file:///C:/Users/jackh/Desktop/Claude/Train%20Game/index.html"
SAVE_FILE = "C:/Users/jackh/Desktop/Claude/Train Game/Autosave_The_Trans-Stellar_Railways_Trust.stt"
with open(SAVE_FILE,"r",encoding="utf-8") as f: SAVE=f.read()

SIMULATE = """
(function(){
  const ti = trains.findIndex(x=>x.name==='PLASMA SURGE');
  if(ti<0) return {err:'no train'};
  const t = trains[ti];
  const snap = ()=>{
    const cp = _gp(t.planetId);
    return {
      sd: Math.round(stardate*100)/100,
      planet: cp?.name,
      tier: t.orbitTier, orbitR: Math.round(t.orbitR),
      phase: t.route?.phase,
      from: t.route?.stops? _gp(t.route.stops[t.route.fromIdx])?.name : null,
      to: t.route?.stops? _gp(t.route.stops[t.route.toIdx])?.name : null,
      temp: !!t.route?.isTempRoute,
      multiHopDest: t.route?._multiHopDest ?? null,
      cancelAfterArrival: !!t.route?.cancelAfterArrival,
      arrivalR: t.route?.arrivalOrbitR ?? null,
      arrivalTier: t.route?.arrivalOrbitTier ?? null,
      detour: t._detourPermanentRoute ? 'YES' : null,
      qStartR: t.route?._queueDescStartR ?? null,
      qTargetR: t.route?._queueDescTargetR ?? null,
    };
  };
  const log = [snap()];
  let lastSig = JSON.stringify(log[0]).slice(0,120);
  const dtG = 30, dt = 3, dtSd = dtG*(0.01/600);
  for(let i=0;i<60000;i++){
    stardate += dtSd;
    try{updateCargoSupplyDemand(dtSd);}catch(e){}
    try{updateMissions();}catch(e){}
    for(const tr of trains){ try{updateTrain(tr,dtG);}catch(e){} }
    try{updatePlanetOrbits(dtG,dt);}catch(e){}
    const cur = snap();
    const sig = JSON.stringify(cur).slice(0,120);
    if(sig !== lastSig){
      log.push(cur);
      lastSig = sig;
      if(log.length>40) break;
    }
    if(stardate > 850) break;
  }
  return {log, finalSD: Math.round(stardate*100)/100};
})()
"""

with sync_playwright() as p:
    b=p.chromium.launch()
    pg=b.new_page(viewport={"width":1400,"height":900})
    pg.goto(URL); pg.wait_for_timeout(2500)
    pg.evaluate("try{startGame();}catch(e){}"); pg.wait_for_timeout(300)
    pg.evaluate(f"_restoreFromSave(JSON.parse({json.dumps(SAVE)})); gs='galaxy'; window.requestAnimationFrame=function(){{return 0;}};")
    res = pg.evaluate(SIMULATE)
    print(f"Final SD: {res.get('finalSD')}")
    print(f"State transitions ({len(res['log'])}):\n")
    for s in res['log']:
        cancel = ' (cancel)' if s.get('cancelAfterArrival') else ''
        mh = f" mh={s.get('multiHopDest')}" if s.get('multiHopDest') is not None else ''
        dt = ' DETOUR' if s.get('detour') else ''
        arr = f" arr={s.get('arrivalTier')}@{s.get('arrivalR')}" if s.get('arrivalTier') else ''
        print(f"  SD {s['sd']:>7.2f}  {s['phase']:<11}  {s['from'] or '-'} → {s['to'] or '-'}  @{s['planet']} {s['tier']}({s['orbitR']}){cancel}{mh}{dt}{arr}")
    b.close()
