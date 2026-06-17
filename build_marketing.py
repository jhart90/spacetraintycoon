#!/usr/bin/env python3
"""
build_marketing.py  —  builds marketing.html from the Space Train Tycoon engine.

This is a DERIVED build, re-generated from the CURRENT build_game.py each run
(it never edits build_game.py). It:

  1. Re-uses build_game.py's asset/font/sound bundling prelude VERBATIM (so the
     real sprites, fonts and sounds are inlined — unlike screensaver.html, which
     stubs the assets out).
  2. Extracts the giant `JS = r"..."` block and applies a small set of
     string-anchored patches:
       a. NO-UI in galaxy view (the rebuild-no-ui recipe): one `_NO_UI` flag,
          the three galaxy-layout constants zeroed, and every HUD/chrome draw in
          drawGalaxy guarded with `if(!_NO_UI)`. Popups, input, pan/zoom/select,
          in-world labels + route visuals are all kept.
       b. Two SCENE buttons added to the title screen, and the normal
          PLAY/LOAD/LEADERBOARD title actions intercepted.
       c. Four hook injections at the top of existing functions so the marketing
          scene system can take over cleanly without the function-hoisting trap:
            updateAICorp        -> drives the per-frame scene tick
            updateMissions      -> suppressed (no mission popups)
            updateCargoSupplyDemand -> scene-controlled supply/demand
            _startCargoOps      -> scene 1 skips all loading/unloading
  3. Appends the marketing scene system (_MKT_JS).

SCENES (see the user spec):
  Scene 1 — a single train shuttling Orijen <-> the lava planet (Gigi Prime
            system) on a repeating route with NO loading/unloading pauses. It
            starts as Constellation + Caboose and every 0.5 s grows by one random
            (full) car while its engine swaps to a different type, up to
            engine + 10 cars + caboose; then 10 more random full trains of that
            length are shown, then it resets to Constellation + Caboose and the
            cycle repeats.
  Scene 2 — the galaxy focused on Orijen (with a ring), Orijen + every other
            Gigi-Prime planet carrying a Large Station, and Orijen holding a
            standing demand floor for every cargo type. Once a second, if an
            orbit (LOW/MED/HIGH) around Orijen is free, a new random full train
            is spawned on a repeating route from a random non-Orijen Gigi-Prime
            planet to Orijen. Cars are always full leaving a non-Orijen planet.

The galaxy view shows NO HUD (like screensaver.html) but clicking, dragging,
zooming, hotkeys and the windows they open all still work.
"""
import re, os, sys

# Run relative to this script's directory so the asset paths resolve.
os.chdir(os.path.dirname(os.path.abspath(__file__)) or ".")

# ── 1. Re-use build_game.py's prelude verbatim ────────────────────────────
with open("build_game.py", "r", encoding="utf-8") as f:
    src = f.read()

MARKER = '\nJS = r"""'
mi = src.find(MARKER)
if mi < 0:
    sys.exit('ERROR: could not find  JS = r"""  in build_game.py')

prelude = src[:mi]
# Execute ONLY the prelude (everything before the JS block) so we get
# font_css / asset_js / sound_js exactly as build_game.py computes them,
# WITHOUT running the tail that writes index.html.
ns = {}
exec(compile(prelude, "build_game_prelude", "exec"), ns)
font_css = ns["font_css"]
asset_js = ns["asset_js"]
sound_js = ns["sound_js"]

m = re.search(r'JS\s*=\s*r"""(.*?)"""', src[mi:], re.DOTALL)
if not m:
    sys.exit("ERROR: could not extract the JS block body from build_game.py")
js = m.group(1)


# ── 2. String-anchored patches ─────────────────────────────────────────────
def rep(old, new, count=1, label=""):
    """Replace `old` with `new`, asserting it occurs exactly `count` times so
    we fail loudly if build_game.py drifts and an anchor no longer matches."""
    global js
    n = js.count(old)
    if n != count:
        sys.exit(f"ERROR: anchor {'['+label+'] ' if label else ''}matched {n} "
                 f"time(s), expected {count}:\n  {old[:90]!r}")
    js = js.replace(old, new)


# 2a. NO-UI flag + zero the three galaxy-layout constants.
rep("const BAR_H    = 72;",
    "const _NO_UI = true;\nconst BAR_H    = _NO_UI?0:72;", label="BAR_H")
rep("const TOP_H    = 28;", "const TOP_H    = _NO_UI?0:28;", label="TOP_H")
rep("const PANEL_W  = 185;", "const PANEL_W  = _NO_UI?0:185;", label="PANEL_W")

# 2b. drawGalaxy chrome guards (rebuild-no-ui recipe).
# Selection ring.
rep("  // Selection ring\n  if(sel){",
    "  // Selection ring\n  if(sel&&!_NO_UI){", label="sel-ring")
# Open the chrome span right after the galaxy-viewport clip restore...
rep("  ctx.restore(); // end galaxy-viewport clip\n",
    "  ctx.restore(); // end galaxy-viewport clip\n  if(!_NO_UI){\n",
    label="span-open")
# ...and close it right before drawSpeedIndicator(), also guarding that call.
rep("  drawSpeedIndicator();\n  // Player-paused banner",
    "  }\n  if(!_NO_UI) drawSpeedIndicator();\n  // Player-paused banner",
    label="span-close")
# Paused banner.
rep("  if(gameSpeedIdx===0 && activePopup!=='quitconfirm') _drawPausedBanner(H/2,null,true);",
    "  if(!_NO_UI && gameSpeedIdx===0 && activePopup!=='quitconfirm') _drawPausedBanner(H/2,null,true);",
    label="paused-banner")
# Educational-callout block (open before the [M] tip, close after the galaxy
# tutorial chain).
rep("  _maybeStartMissionTip(); // promote a queued [M] tip once other callouts clear",
    "  if(!_NO_UI){\n  _maybeStartMissionTip(); // promote a queued [M] tip once other callouts clear",
    label="callout-open")
rep("  _drawTutorialChain('galaxy');",
    "  _drawTutorialChain('galaxy');\n  }", label="callout-close")
# Buy-train-plus callout (lives inside the popup chain).
rep("  _drawBuyTrainPlusHintCallout();",
    "  if(!_NO_UI) _drawBuyTrainPlusHintCallout();", label="buytrainplus")
# Top bar + panel tabs.
rep("  drawTopBar();\n  drawPanelTabs();",
    "  if(!_NO_UI) drawTopBar();\n  if(!_NO_UI) drawPanelTabs();", label="topbar")
# Popup-stage tutorial chain.
rep("  _drawTutorialChain('popup');",
    "  if(!_NO_UI) _drawTutorialChain('popup');", label="tut-popup")
# Visit hint.
rep("  _drawVisitHint();", "  if(!_NO_UI) _drawVisitHint();", label="visithint")

# 2c. Hook injections at function tops (avoids the function-redeclare/hoisting
# trap — we modify the existing definitions in place).
rep("function updateAICorp(dt){",
    "function updateAICorp(dt){ if(typeof _MKT_SCENE!=='undefined'&&_MKT_SCENE){ _mktTick(); return; }",
    label="hook-ai")
rep("function updateMissions(dtSd){",
    "function updateMissions(dtSd){ if(typeof _MKT_SCENE!=='undefined'&&_MKT_SCENE) return;",
    label="hook-missions")
rep("function updateCargoSupplyDemand(dtSd){",
    "function updateCargoSupplyDemand(dtSd){ if(typeof _MKT_SCENE!=='undefined'&&_MKT_SCENE){ _mktSupplyDemandTick(); return; }",
    label="hook-supdem")
rep("function _startCargoOps(t, p){",
    "function _startCargoOps(t, p){ if(typeof _MKT_SCENE!=='undefined'&&_MKT_SCENE===1){ t.cargoPhase=null; t.cargoQueue=[]; t.cargoTimer=0; return; }",
    label="hook-cargo")

# Title-screen: draw the scene buttons (over the normal PLAY/LOAD/LEADERBOARD).
rep("    drawTitleScreen(ts,dt);\n    // Save Manager can be opened from the title screen via LOAD GAME.",
    "    drawTitleScreen(ts,dt);\n    _mktDrawTitleButtons(ts);\n    // Save Manager can be opened from the title screen via LOAD GAME.",
    label="title-draw")
# Title-screen: intercept clicks (scene buttons; block normal start actions).
rep("    const b=startBtnBounds;",
    "    if(_mktTitleClick(cp)){return;}\n    const b=startBtnBounds;",
    label="title-click")


# ── 3. Marketing scene system (appended; ASCII only) ───────────────────────
MKT_JS = r"""
// ============================================================================
//  MARKETING SCENE SYSTEM  (appended by build_marketing.py)
// ============================================================================
var _MKT_SCENE = 0;                 // 0 = none/title, 1 = showcase, 2 = Orijen hub
var _MKT_CARGO_TYPES = Array.from(new Set(Object.values(CAR_CARGO_TYPE)));
var _mktOrijenId = -1, _mktLavaId = -1, _mktHomeStarId = -1, _mktHomePids = [];
var _mktLastMs = 0, _mkt1Acc = 0, _mkt2Acc = 0;
var _mkt1Mids = [], _mkt1Phase = 'grow', _mkt1Cycle = 0, _mkt2Count = 0;
var _mktMx = -1, _mktMy = -1, _mktBtn1 = null, _mktBtn2 = null;

function _mktIn(p, b){ return b && p.x>=b.x && p.x<=b.x+b.w && p.y>=b.y && p.y<=b.y+b.h; }

// ── train composition helpers ──────────────────────────────────────────────
function _mktRandCar(){ return pick(CAR_MID); }
function _mktRandEngine(cur){
  var e; var guard = 0;
  do { e = pick(ENGINE_TYPES_ALL); } while(e === cur && ++guard < 30);
  return e;
}
// Fill every cargo car (not engine / caboose) to a FULL state, tagging the
// cargo source so it will unload at a *different* planet.
function _mktFillTrain(t, srcPid){
  for(var i=0;i<t.cars.length;i++){
    var nm = t.cars[i];
    var cg = CAR_CARGO_TYPE[nm];
    if(cg && !isEngineType(nm) && nm !== 'caboose'){
      t.carFull[i] = true;
      t.carCargo[i] = cg;
      t.carCargoSource[i] = (srcPid != null ? srcPid : _mktLavaId);
    }
  }
}
// Replace a train's car list and rebuild every parallel per-car array so the
// engine/updateTrain logic stays consistent. Mid cargo cars come out full.
function _mktApplyCars(t, cars, srcPid){
  t.cars = cars.slice();
  var n = cars.length;
  t.carFull          = new Array(n).fill(false);
  t.carCargo         = new Array(n).fill(null);
  t.carCargoSource   = new Array(n).fill(null);
  t.carEscort        = new Array(n).fill(false);
  t.carPurchaseSd    = new Array(n).fill(stardate);
  t.carRevenue       = new Array(n).fill(0);
  t.carSegments      = new Array(n).fill(0);
  t.carFullSegments  = new Array(n).fill(0);
  t.carUnitsLoaded   = new Array(n).fill(0);
  t.carUnitsUnloaded = new Array(n).fill(0);
  t.carEngineHistory = cars.map(function(c){
    return (c && !c.startsWith('engine_') && c !== 'caboose')
      ? [{type: cars[0], startSd: stardate}] : [];
  });
  t._engineHistory = [{type: cars[0], startSd: stardate}];
  t.cargoPhase = null; t.cargoQueue = []; t.cargoTimer = 0;
  _mktFillTrain(t, srcPid);
}

// ── title-screen scene buttons ─────────────────────────────────────────────
function _mktDrawBtn(b, label, hov){
  ctx.save();
  ctx.shadowColor = '#4af'; ctx.shadowBlur = hov ? 26 : 14;
  ctx.strokeStyle = hov ? 'rgba(120,200,255,0.95)' : 'rgba(60,160,255,0.7)';
  ctx.lineWidth = hov ? 2.5 : 2;
  ctx.fillStyle = hov ? 'rgba(14,36,90,0.97)' : 'rgba(8,22,58,0.92)';
  ctx.beginPath(); ctx.roundRect(b.x, b.y, b.w, b.h, 9); ctx.fill(); ctx.stroke();
  ctx.shadowBlur = hov ? 12 : 8;
  ctx.font = 'bold 17px Orbitron,sans-serif';
  ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
  ctx.fillStyle = hov ? '#d6f0ff' : '#aadcff';
  ctx.fillText(label, b.x + b.w/2, b.y + b.h/2);
  ctx.restore();
}
function _mktDrawTitleButtons(ts){
  var bw = 300, bh = 56, cx = W/2;
  var y1 = 158, y2 = y1 + bh + 16;
  var pTop = 140, pBot = y2 + bh + 8;
  _mktBtn1 = {x: cx - bw/2, y: y1, w: bw, h: bh};
  _mktBtn2 = {x: cx - bw/2, y: y2, w: bw, h: bh};
  // Wipe the HD text overlay under our panel so the normal PLAY / LOAD GAME /
  // LEADERBOARD labels (drawn to the overlay) don't bleed through. Keeps the
  // title + subtitle (above pTop) and the version/mute corners untouched.
  _clearTextOverlayRect(cx - bw/2 - 16, pTop, bw + 32, pBot - pTop);
  ctx.save();
  ctx.fillStyle = 'rgba(6,8,16,0.95)';
  ctx.strokeStyle = 'rgba(60,120,200,0.30)';
  ctx.lineWidth = 1;
  ctx.beginPath();
  ctx.roundRect(cx - bw/2 - 16, pTop, bw + 32, pBot - pTop, 12);
  ctx.fill(); ctx.stroke();
  ctx.font = 'bold 12px Orbitron,sans-serif';
  ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
  ctx.fillStyle = 'rgba(150,200,255,0.88)';
  ctx.fillText('MARKETING SCENE SELECT', cx, y1 - 14);
  ctx.restore();
  var mp = {x: _mktMx, y: _mktMy};
  _mktDrawBtn(_mktBtn1, 'SCENE 1  -  TRAIN SHOWCASE', _mktIn(mp, _mktBtn1));
  _mktDrawBtn(_mktBtn2, 'SCENE 2  -  ORIJEN HUB',     _mktIn(mp, _mktBtn2));
}
function _mktTitleClick(cp){
  if(_mktIn(cp, _mktBtn1)){ try{playSound('button');}catch(e){} _mktStartScene(1); return true; }
  if(_mktIn(cp, _mktBtn2)){ try{playSound('button');}catch(e){} _mktStartScene(2); return true; }
  // Swallow every other title click so the normal PLAY / LOAD / LEADERBOARD
  // actions never fire on the marketing build (mute + Save Manager are handled
  // earlier in the click handler, before this hook).
  return true;
}
// Track the logical-space cursor for button hover (capture phase; passive).
canvas.addEventListener('mousemove', function(e){
  try { var cp = getCP(e); _mktMx = cp.x; _mktMy = cp.y; } catch(_){}
}, true);

// ── scene boot ─────────────────────────────────────────────────────────────
function _mktStartScene(n){
  startGame();                 // fresh galaxy + default player train + state
  _aiDifficulty = 'none';      // no rival corporation
  _aiCorp = null;
  fogEnabled = false;          // marketing wants the galaxy fully visible
  _MKT_SCENE = n;
  _mktLastMs = performance.now();
  _mkt1Acc = 0; _mkt2Acc = 0; _mkt2Count = 0;

  var orijen = galaxy.planets[galaxy.origenId];
  _mktOrijenId = galaxy.origenId;
  _mktHomeStarId = orijen.starId;
  var homeStar = galaxy.stars[_mktHomeStarId];
  _mktHomePids = homeStar.planetIds.slice();
  // Lava planet in the Gigi Prime system.
  _mktLavaId = (typeof _tutorialLavaPlanetId !== 'undefined' && _tutorialLavaPlanetId >= 0)
    ? _tutorialLavaPlanetId : -1;
  if(_mktLavaId < 0){
    for(var i=0;i<_mktHomePids.length;i++){
      var hp = galaxy.planets[_mktHomePids[i]];
      if(hp && hp.type && hp.type.id === 'lava'){ _mktLavaId = hp.id; break; }
    }
  }
  if(_mktLavaId < 0){ // last-ditch: any non-Orijen home planet
    _mktLavaId = _mktHomePids.find(function(p){ return p !== _mktOrijenId; });
  }

  if(n === 1) _mktInitScene1(orijen, homeStar);
  else        _mktInitScene2(orijen, homeStar);

  activePopup = null; popupState = {};
  gs = 'galaxy';
  var rb = document.getElementById('refresh-btn');
  if(rb) rb.classList.add('hidden');
}

function _mktInitScene1(orijen, homeStar){
  // One showcase train, Constellation + Caboose, looping Orijen <-> lava.
  var t = makeGalaxyTrain('SHOWCASE', _mktOrijenId, 'LOW',
                          ['engine_constellation','caboose'], false);
  t.color = pick(TRAIN_COLORS);
  t._engineFailureSd = Infinity; t._engineFailed = false; t.maintenance = 1.0;
  trains = [t];
  _mkt1Mids = []; _mkt1Phase = 'grow'; _mkt1Cycle = 0;

  var lava = _gp(_mktLavaId);
  routeStops = [orijen, lava, orijen];   // first === last -> repeating loop
  assignRouteToTrain(t);
  routeStops = [];

  // Track the showcase train so it stays large + centred while it shuttles and
  // grows. Scale is tuned to fit the longest form (engine + 10 cars + caboose).
  var sc = (Math.min(W, H) * 0.78) / (12 * CAR_ORB_GAP);
  sc = Math.max(MIN_SC, Math.min(MAX_SC, sc));
  var ep = getTrainCarPos(t, 0);
  cam = {x: ep[0], y: ep[1], scale: sc};
  starPan = {x: 0, y: 0};
  sel = {type: 'car', data: {trainIdx: 0, carIdx: 0, car: t.cars[0]}};
  tracking = true; trackingOffset = {x: 0, y: 0};
  clampCamera();
}

function _mktInitScene2(orijen, homeStar){
  trains = [];                       // hub is populated by spawns
  // Ring around Orijen.
  orijen.ring = {rot: 0.5, outerFrac: 2.6, innerFrac: 1.45, incl: 0.34,
                 rgb: [225, 195, 130]};
  // Large station on Orijen + every other Gigi-Prime planet.
  for(var i=0;i<_mktHomePids.length;i++){
    var p = galaxy.planets[_mktHomePids[i]];
    if(!p) continue;
    p.hasStation = true;
    p.hasLargeStation = true;
    if(!p.stationAngle) p.stationAngle = Math.random() * Math.PI * 2;
    if(!p.stationSpeed) p.stationSpeed = 0.00015 + Math.random() * 0.00030;
  }
  _mktSupplyDemandTick();           // seed the demand floor immediately

  // Focus on Orijen, framed so its orbit tiers (where trains stream in) show.
  var tiers = ORBIT_TIERS[orijen.size] || ORBIT_TIERS.L;
  var sc = (Math.min(W, H) * 0.46) / ((tiers.HIGH || 525) * 1.15);
  sc = Math.max(MIN_SC, Math.min(MAX_SC, sc));
  cam = {x: orijen.x, y: orijen.y, scale: sc};
  starPan = {x: 0, y: 0};
  sel = {type: 'planet', data: orijen};   // tracking keeps Orijen centred
  tracking = true; trackingOffset = {x: 0, y: 0};
  clampCamera();
  _mkt2Acc = 0;
}

// ── per-frame scene tick (driven from updateAICorp) ────────────────────────
function _mktTick(){
  var now = performance.now();
  var d = now - _mktLastMs; _mktLastMs = now;
  if(!(d >= 0)) d = 16;
  if(d > 200) d = 200;            // ignore long pauses (tab backgrounded etc.)

  // Hold the clock below SD 830 so no newspaper / rival-corp events fire, and
  // keep every train healthy so nothing breaks down mid-demo.
  if(typeof stardate !== 'undefined' && stardate > 829.8) stardate = 829.5;
  for(var i=0;i<trains.length;i++){
    var t = trains[i]; if(!t) continue;
    t.maintenance = 1.0; t._engineFailed = false; t._engineFailureSd = Infinity;
  }

  if(_MKT_SCENE === 1){
    _mkt1Acc += d;
    while(_mkt1Acc >= 500){ _mkt1Acc -= 500; _mktScene1Step(); }
  } else if(_MKT_SCENE === 2){
    _mkt2Acc += d;
    while(_mkt2Acc >= 1000){ _mkt2Acc -= 1000; _mktScene2Spawn(); }
  }
}

function _mktScene1Step(){
  var t = trains[0]; if(!t) return;
  if(_mkt1Phase === 'grow'){
    // Add one random (full) car between engine + caboose; swap engine type.
    _mkt1Mids.push(_mktRandCar());
    var eng = _mktRandEngine(t.cars[0]);
    _mktApplyCars(t, [eng].concat(_mkt1Mids, ['caboose']), _mktLavaId);
    if(_mkt1Mids.length >= 10){ _mkt1Phase = 'cycle'; _mkt1Cycle = 0; }
  } else {
    // 10 fresh random full trains at the max length (engine + 10 + caboose).
    var eng2 = _mktRandEngine(t.cars[0]);
    var mids = [];
    for(var i=0;i<10;i++) mids.push(_mktRandCar());
    _mktApplyCars(t, [eng2].concat(mids, ['caboose']), _mktLavaId);
    _mkt1Cycle++;
    if(_mkt1Cycle >= 10){
      _mkt1Mids = [];
      _mktApplyCars(t, ['engine_constellation','caboose'], _mktLavaId);
      _mkt1Phase = 'grow';
    }
  }
}

function _mktScene2Spawn(){
  if(!galaxy) return;
  if(!getAvailableOrbitTier(_mktOrijenId, null)) return; // gate: Orijen has room

  // Cap each origin -> Orijen route at 2 trains: tally trains by their tagged
  // origin planet and only consider origins with fewer than 2 so far.
  var counts = {};
  for(var i=0;i<trains.length;i++){
    var op = trains[i] && trains[i]._mktOriginPid;
    if(op != null) counts[op] = (counts[op] || 0) + 1;
  }
  var cands = _mktHomePids.filter(function(pid){
    return pid !== _mktOrijenId && (counts[pid] || 0) < 2;
  });
  if(!cands.length) return;
  // Prefer an eligible origin that currently has a free orbit slot.
  var pid = null, av = null;
  for(var tries=0; tries<8; tries++){
    var c = cands[randInt(0, cands.length - 1)];
    var a = getAvailableOrbitTier(c, null);
    if(a){ pid = c; av = a; break; }
  }
  if(pid == null){ pid = cands[randInt(0, cands.length - 1)]; av = {tier: 'LOW'}; }

  var nMid = randInt(1, 7);
  var cars = [_mktRandEngine(null)];
  for(var k=0;k<nMid;k++) cars.push(_mktRandCar());
  cars.push('caboose');

  var t = makeGalaxyTrain('FREIGHT ' + (++_mkt2Count), pid, av.tier, cars, false);
  t.color = pick(TRAIN_COLORS);
  t._mktOriginPid = pid;          // tag origin for the per-route 2-train cap
  t._engineFailureSd = Infinity; t._engineFailed = false; t.maintenance = 1.0;
  _mktFillTrain(t, pid);          // depart the origin full
  trains.push(t);

  // assignRouteToTrain() ends by clearing the global selection (sel=null), which
  // would deselect (and stop the camera tracking) whatever planet the viewer is
  // watching as trains keep spawning. Preserve the current selection + follow-cam
  // across the call so a tracked planet stays selected and tracked.
  var _savSel = sel, _savTrack = tracking, _savOff = trackingOffset;
  routeStops = [_gp(pid), _gp(_mktOrijenId), _gp(pid)]; // repeating loop -> Orijen
  assignRouteToTrain(t);
  sel = _savSel; tracking = _savTrack; trackingOffset = _savOff;
  routeStops = [];
}

// Scene-controlled supply/demand: Orijen is an infinite sink (demand floor,
// no supply); every other Gigi-Prime planet is an infinite source. So trains
// always load full at an origin and always unload (with beams + credit floats)
// at Orijen, with no stalls.
function _mktSupplyDemandTick(){
  if(_MKT_SCENE !== 2 || !galaxy) return;
  for(var i=0;i<_mktHomePids.length;i++){
    var p = galaxy.planets[_mktHomePids[i]]; if(!p) continue;
    if(!p.supply) p.supply = {};
    if(!p.demand) p.demand = {};
    if(p.id === _mktOrijenId){
      for(var a=0;a<_MKT_CARGO_TYPES.length;a++){ var ct=_MKT_CARGO_TYPES[a]; p.demand[ct]=30; p.supply[ct]=0; }
    } else {
      for(var b=0;b<_MKT_CARGO_TYPES.length;b++){ var ct2=_MKT_CARGO_TYPES[b]; p.supply[ct2]=30; p.demand[ct2]=0; }
    }
  }
}
"""

# ── 4. Assemble marketing.html (same shell as build_game.py's index.html) ──
html = (
    "<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n"
    "<meta charset=\"UTF-8\">\n"
    "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">\n"
    "<title>Space Train Tycoon &#8212; Marketing Scenes</title>\n"
    "<style>" + font_css + "</style>\n"
    "<style>\n"
    "  *{margin:0;padding:0;box-sizing:border-box;}\n"
    "  body{background:#000;display:flex;justify-content:center;align-items:center;height:100vh;overflow:hidden;\n"
    "        -webkit-font-smoothing:antialiased;-moz-osx-font-smoothing:grayscale;\n"
    "        text-rendering:optimizeLegibility;}\n"
    "  #c{display:block;image-rendering:pixelated;}\n"
    "  #tc{display:block;image-rendering:auto;-webkit-font-smoothing:antialiased;\n"
    "       -moz-osx-font-smoothing:grayscale;}\n"
    "  #refresh-btn{position:fixed;bottom:28px;right:28px;width:48px;height:48px;border-radius:50%;\n"
    "    background:rgba(30,40,80,0.85);border:2px solid #4af;color:#4af;font-size:22px;cursor:pointer;\n"
    "    display:flex;align-items:center;justify-content:center;transition:background .2s,transform .15s;\n"
    "    z-index:10;user-select:none;}\n"
    "  #refresh-btn:hover{background:rgba(60,80,160,0.95);transform:scale(1.1);}\n"
    "  #refresh-btn:active{transform:scale(0.95) rotate(30deg);}\n"
    "  #refresh-btn.hidden{display:none;}\n"
    "</style>\n"
    "</head>\n<body>\n"
    "<canvas id=\"c\"></canvas>\n"
    "<button id=\"refresh-btn\" title=\"New train\">&#x21BB;</button>\n"
    "<input id=\"name-edit\" type=\"text\" maxlength=\"32\" autocomplete=\"off\" spellcheck=\"false\"\n"
    "  style=\"position:fixed;display:none;background:rgba(4,8,28,0.97);color:#4af;border:1.5px solid rgba(80,160,255,0.7);\n"
    "  outline:none;font:bold 11px Orbitron,sans-serif;padding:2px 6px;border-radius:2px;z-index:20;\"/>\n"
    "<script>\n"
    + asset_js + "\n"
    + sound_js + "\n"
    + js + "\n"
    + MKT_JS + "\n"
    + "</script>\n</body>\n</html>\n"
)

with open("marketing.html", "w", encoding="utf-8") as f:
    f.write(html)

print("Built marketing.html,", len(html) // 1024, "KB")
