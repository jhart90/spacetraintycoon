"""Stress test: pan around 200+ frames to see if ctx state leaks anywhere."""
import json, sys
sys.stdout.reconfigure(encoding='utf-8')
from playwright.sync_api import sync_playwright

URL = "file:///C:/Users/jackh/Desktop/Claude/Train%20Game/index.html"
SAVE_FILE = "C:/Users/jackh/Desktop/Claude/Train Game/The_Trans-Stellar_Railways_Trust_84429.stt"
with open(SAVE_FILE, "r", encoding="utf-8") as f: SAVE = f.read()

with sync_playwright() as p:
    b = p.chromium.launch()
    pg = b.new_page(viewport={"width":1400,"height":900})
    errs = []
    pg.on("pageerror", lambda e: errs.append(("PERR", str(e))))
    pg.goto(URL); pg.wait_for_timeout(2500)
    pg.evaluate("try{startGame();}catch(e){}")
    pg.wait_for_timeout(500)
    pg.evaluate(f"_restoreFromSave(JSON.parse({json.dumps(SAVE)})); gs='galaxy';")

    # Instrument ctx.save/restore to count balance, and instrument fillRect for UI areas
    pg.evaluate("""(function(){
      window._saveDepth=0; window._maxDepth=0;
      const _os=ctx.save.bind(ctx), _or=ctx.restore.bind(ctx);
      ctx.save=function(){_os(); window._saveDepth++; if(window._saveDepth>window._maxDepth) window._maxDepth=window._saveDepth;};
      ctx.restore=function(){_or(); window._saveDepth--;};
      window._barDrawn=false;
      // Wrap fillRect to detect if info bar bg got drawn
      const _ofr=ctx.fillRect.bind(ctx);
      ctx.fillRect=function(x,y,w,h){
        if(y>=GH-1 && y<=GH+1 && w>=W-1) window._barDrawn=true;
        return _ofr(x,y,w,h);
      };
    })()""")

    # Pan to a series of locations: fogged → unfogged → fogged → unfogged
    locations=[
      {"x": 50000, "y": 50000, "scale": 0.3, "tag": "deep_fog_1"},
      {"x": 0, "y": 0, "scale": 0.3, "tag": "near_center"},
      {"x": -50000, "y": -30000, "scale": 0.5, "tag": "deep_fog_2"},
    ]
    pg.evaluate("_newspaper=null;")
    for loc in locations:
      pg.evaluate(f"cam.x={loc['x']}; cam.y={loc['y']}; cam.scale={loc['scale']}; clampCamera && clampCamera();")
      pg.evaluate("window._saveDepth=0; window._maxDepth=0; window._barDrawn=false;")
      # Run frames
      pg.evaluate(f"""(function(){{window._done=false; let i=0; function tick(){{if(i>=10){{window._done=true;return;}} i++; _newspaper=null; try{{drawGalaxy(performance.now(),1);}}catch(e){{if(!window._drawErr) window._drawErr={{msg:e.message,stack:String(e.stack||'').slice(0,400)}};}} requestAnimationFrame(tick);}} tick();}})()""")
      for _ in range(40):
        if pg.evaluate("window._done"): break
        pg.wait_for_timeout(50)
      depth = pg.evaluate("window._saveDepth")
      maxd = pg.evaluate("window._maxDepth")
      bar = pg.evaluate("window._barDrawn")
      derr = pg.evaluate("window._drawErr||null")
      print(f"  {loc['tag']:<14} saveDepth_end={depth} max={maxd} barDrawn={bar} derr={derr}")
    b.close()
