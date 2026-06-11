#!/usr/bin/env python3
"""
build_screensaver.py  — builds screensaver.html from the Space Train game engine.

Patches applied to the extracted JS:
  1. Canvas = full viewport (innerWidth × innerHeight).
  2. init() fires via document.fonts.ready when ASSETS={} (no onLoad callbacks).
  3. Screensaver overrides appended (last function declaration wins in global scope):
       _drawNebulaBackground()  — world-space gradient blobs; no tiling grid.
       _SS_classify / _SS_violates / _SS_arrange  — shot-constraint helpers.
       _SS_addUpgrades()        — 1/4 stars Dyson, 1/3 planets station/large/terminal/relic.
       init()                   — skip title, generate galaxy, add upgrades, start cinematic.
       _introToCorpSetup()      — no-op; screensaver never exits cinematic.
       _buildIntroShots()       — random pool: M+ planets only, black holes included,
                                  extra extreme close-ups, constraint-arranged.
       drawHowToPlay()          — cinematic only (no narration), starPan parallax update,
                                  shot-kind tracking for constraint enforcement.
       music bar wiring.
"""
import re, base64, os, sys

# ── Font bundling (same fonts as build_game.py) ──────────────────────────
FONT_FACES = [
    ("Orbitron",           "400 700", "Orbitron-Variable.woff2"),
    ("Exo 2",              "300 700", "Exo2-Variable.woff2"),
    ("UnifrakturMaguntia", "400",     "UnifrakturMaguntia-Regular.woff2"),
    ("Noto Sans Phags Pa", "400",     "NotoSansPhagsPa-Regular.woff2"),
    ("Lato",               "400",     "Lato-Regular.woff2"),
    ("Lato",               "700",     "Lato-Bold.woff2"),
]
font_parts = []
for family, weight, fname in FONT_FACES:
    fpath = os.path.join("fonts", fname)
    if not os.path.exists(fpath):
        print(f"  WARNING: missing font {fpath} — skipping")
        continue
    with open(fpath, "rb") as f:
        b64 = base64.b64encode(f.read()).decode()
    font_parts.append(
        "@font-face{font-family:'" + family + "';font-style:normal;font-weight:" + weight +
        ";font-display:swap;src:url(data:font/woff2;base64," + b64 + ") format('woff2');}"
    )
font_css = "\n".join(font_parts)

# ── Extract JS block from build_game.py ──────────────────────────────────
with open("build_game.py", "r", encoding="utf-8") as f:
    src = f.read()

m = re.search(r'\nJS\s*=\s*r"""(.*?)"""\n', src, re.DOTALL)
if not m:
    sys.exit("ERROR: Cannot find  JS = r\"\"\"...\"\"\"  in build_game.py")
js = m.group(1)

# ── Patch 1: full-screen canvas dimensions ────────────────────────────────
js = js.replace(
    "const W = 900, H = 500;\ncanvas.width = W; canvas.height = H;",
    "const W = window.innerWidth, H = window.innerHeight;\n"
    "canvas.width = W; canvas.height = H;"
)

# ── Patch 2: fire init() when ASSETS={} (no image onLoad callbacks fire) ─
js = js.replace(
    "for(const [k,v] of Object.entries(ASSETS)) {\n"
    "  const im = new Image(); im.onload = onLoad; im.src = v; imgs[k] = im;\n"
    "}",
    "for(const [k,v] of Object.entries(ASSETS)) {\n"
    "  const im = new Image(); im.onload = onLoad; im.src = v; imgs[k] = im;\n"
    "}\n"
    "if(total===0) document.fonts.ready.then(init);"
)

# ── Screensaver overrides (appended; last function declaration wins) ───────
SS_JS = r"""
// ═══════════════════════════════════════════════════════════════════════
//  SCREENSAVER OVERRIDES — appended by build_screensaver.py
// ═══════════════════════════════════════════════════════════════════════
var _SS_MODE = true;
var _ssCamPrevX = null, _ssCamPrevY = null;
var _SS_lastShotKind = null;   // kind of the most-recently-finished shot
var _SS_shotsSinceZoomOut = 99; // shots elapsed since the last zoom-out played
var _SS_nebulaBlobs = null;    // world-space gradient blobs; reset on each new galaxy

// ── Fix 1: replace tiling nebula background with world-space gradient blobs
// The original _drawNebulaBackground() tiles a pre-baked canvas, producing a
// visible grid pattern.  This version places large radial gradients at fixed
// world-space positions — they move with the camera and never repeat.
function _drawNebulaBackground() {
  if (!_SS_nebulaBlobs) {
    // Four colour palette families; one is chosen randomly per galaxy.
    const _pals = [
      [[80,20,180],[40,80,220],[180,60,20]],
      [[20,60,200],[10,120,80],[200,80,20]],
      [[140,30,200],[20,140,180],[200,120,20]],
      [[20,150,80],[60,20,180],[200,80,60]],
    ];
    const _pal = _pals[Math.floor(Math.random() * _pals.length)];
    _SS_nebulaBlobs = [];
    // 10 blobs spread in a ring around the galactic centre
    for (let _i = 0; _i < 10; _i++) {
      const _ang = (_i / 10) * Math.PI * 2 + Math.random() * 0.5;
      const _d   = WORLD_W * (0.08 + Math.random() * 0.70);
      _SS_nebulaBlobs.push({
        wx:    Math.cos(_ang) * _d,
        wy:    Math.sin(_ang) * _d * (WORLD_H / WORLD_W),
        col:   _pal[_i % _pal.length],
        alpha: 0.06 + Math.random() * 0.09,
        r:     WORLD_W * (0.22 + Math.random() * 0.40),
      });
    }
    // 3 softer blobs near the galactic core for depth
    for (let _i = 0; _i < 3; _i++) {
      _SS_nebulaBlobs.push({
        wx:    (Math.random() - 0.5) * WORLD_W * 0.25,
        wy:    (Math.random() - 0.5) * WORLD_H * 0.25,
        col:   _pal[(_i + 1) % _pal.length],
        alpha: 0.05 + Math.random() * 0.07,
        r:     WORLD_W * (0.28 + Math.random() * 0.26),
      });
    }
  }
  ctx.save();
  for (const _blob of _SS_nebulaBlobs) {
    const [_sx, _sy] = w2s(_blob.wx, _blob.wy);
    const _sr = _blob.r * cam.scale;
    // Cull blobs whose screen circle doesn't intersect the viewport
    if (_sx + _sr < -50 || _sx - _sr > W + 50 ||
        _sy + _sr < -50 || _sy - _sr > H + 50) continue;
    const _g = ctx.createRadialGradient(_sx, _sy, 0, _sx, _sy, Math.max(1, _sr));
    const [_r, _gv, _b] = _blob.col;
    _g.addColorStop(0,    'rgba(' + _r + ',' + _gv + ',' + _b + ',' + _blob.alpha.toFixed(3) + ')');
    _g.addColorStop(0.42, 'rgba(' + _r + ',' + _gv + ',' + _b + ',' + (_blob.alpha * 0.32).toFixed(3) + ')');
    _g.addColorStop(1,    'rgba(0,0,0,0)');
    ctx.fillStyle = _g;
    ctx.beginPath();
    ctx.arc(_sx, _sy, _sr, 0, Math.PI * 2);
    ctx.fill();
  }
  ctx.restore();
}

// ── Helper: end-scale so that N stars fall inside the viewport ───────────
// Used by zoom-out shots so they end at a meaningful astronomical framing
// rather than a random far scale.  Planet position is approximate (orbit
// moves it slightly between pool-build and shot-play, but star distances
// are large enough that the error doesn't matter).
function _SS_endScaleForStarCount(px, py, N) {
  if (!galaxy || !galaxy.stars || !galaxy.stars.length) return MIN_SC;
  // Sort all stars by distance from the planet's current world position
  const sorted = galaxy.stars
    .map(s => Math.hypot(s.x - px, s.y - py))
    .sort((a, b) => a - b);
  const dist = sorted[Math.min(N - 1, sorted.length - 1)];
  if (dist <= 0) return MIN_SC;
  // Scale so the Nth star sits at ~65% of the viewport's shorter half-dimension
  // (well inside the frame with a comfortable margin).
  const s = Math.min(W, H) * 0.65 / dist;
  return Math.max(MIN_SC * 0.4, s); // never go below 40% of min-scale
}

// ── Fix 5: shot-constraint helpers ───────────────────────────────────────
// Classify each shot as zoomIn / zoomOut / pan-h / pan-v / pan-d / static.
function _SS_classify(shot) {
  if (!shot) return 'unknown';
  if (shot.mode === 'planetStatic') return 'static';
  if (shot.s0 == null || shot.s1 == null) return 'unknown';
  const _ratio = shot.s0 / Math.max(shot.s1, 0.0001);
  if (_ratio > 1.08) return 'zoomOut';   // s0 substantially > s1: zooming out
  if (_ratio < 0.92) return 'zoomIn';    // s0 substantially < s1: zooming in
  // Pan: determine dominant camera-motion axis
  let _cdx, _cdy;
  if (shot.pid != null) {
    _cdx = (shot.ox1 || 0) - (shot.ox0 || 0);  // delta in camera offset (world units)
    _cdy = (shot.oy1 || 0) - (shot.oy0 || 0);
  } else {
    _cdx = (shot.x1 || 0) - (shot.x0 || 0);   // absolute world-coord camera path
    _cdy = (shot.y1 || 0) - (shot.y0 || 0);
  }
  const _adx = Math.abs(_cdx), _ady = Math.abs(_cdy);
  if (_adx > _ady * 1.5) return 'pan-h';
  if (_ady > _adx * 1.5) return 'pan-v';
  return 'pan-d';
}

// Returns true when the proposed nextKind shot is disallowed given context.
// Rules:
//   • no back-to-back zoomIn, pan-h, or pan-v
//   • zoom-out requires at least 4 non-zoom-out shots since the last zoom-out
function _SS_violates(prevKind, nextKind, sinceZoomOut) {
  if (!prevKind || prevKind === 'unknown') return false;
  if (prevKind === 'zoomIn' && nextKind === 'zoomIn') return true;
  if (prevKind === 'pan-h'  && nextKind === 'pan-h')  return true;
  if (prevKind === 'pan-v'  && nextKind === 'pan-v')  return true;
  if (nextKind === 'zoomOut' && (sinceZoomOut || 0) < 4) return true;
  return false;
}

// Greedy constraint-aware re-ordering.  Tracks both the last shot kind and
// the running count of shots-since-last-zoom-out so the 4-shot gap rule is
// enforced across the entire arranged sequence.  Falls back gracefully when
// no valid candidate exists (takes the next shot regardless).
function _SS_arrange(shots) {
  const _result = [], _rem = [...shots];
  let _last   = _SS_lastShotKind || null;
  let _sinceZ = _SS_shotsSinceZoomOut;
  while (_rem.length > 0) {
    let _found = -1;
    for (let _i = 0; _i < _rem.length; _i++) {
      if (!_SS_violates(_last, _SS_classify(_rem[_i]), _sinceZ)) { _found = _i; break; }
    }
    if (_found < 0) _found = 0; // fallback: no ideal candidate, just take next
    const _shot = _rem.splice(_found, 1)[0];
    _result.push(_shot);
    const _k = _SS_classify(_shot);
    _last = _k;
    if (_k === 'zoomOut') _sinceZ = 0; else _sinceZ++;
  }
  return _result;
}

// ── Post-galaxy upgrade layer ─────────────────────────────────────────────
function _SS_addUpgrades() {
  if (!galaxy) return;
  _SS_nebulaBlobs = null; // reset per-galaxy nebula blobs
  // 1/4 of stars get Dyson spheres
  for (const _s of galaxy.stars) _s.hasDysonSphere = Math.random() < 0.25;
  // 1/3 of planets get a station (four varieties)
  for (const _p of galaxy.planets) {
    if (Math.random() >= 0.34) continue;
    _p.hasStation = true;
    if (!_p.stationAngle) _p.stationAngle = Math.random() * Math.PI * 2;
    if (!_p.stationSpeed) _p.stationSpeed = 0.00015 + Math.random() * 0.00030;
    const _sr = Math.random();
    if      (_sr < 0.12) { _p.isAlienRelic = true; }                    // alien relic
    else if (_sr < 0.55) { /* regular station */                       } // player blue
    else if (_sr < 0.76) { _p.hasLargeStation = true;                 } // large
    else                 { _p.hasLargeStation = true; _p.hasTerminal = true; } // terminal
  }
}

// ── init: skip title screen, generate galaxy, enter cinematic ─────────────
function init() {
  buildNebula(); makeStars();
  _buildNebulaTiles();
  _buildUrbanSkylineCache();
  _buildAncientRuinsCache();
  startGame();          // generateGalaxy() + makeGStars(); sets gs='fadeout'
  _SS_addUpgrades();    // post-gen: Dyson spheres + stations
  gs = 'howtoplay';     // override gs='fadeout' set by startGame()
  _SS_lastShotKind = null;
  _SS_shotsSinceZoomOut = 99; // start high so first shot may be any type
  _introShots = _buildIntroShots();
  _introShotIdx = 0;
  _introShotStartTs = performance.now();
  _ssCamPrevX = null; _ssCamPrevY = null;
  requestAnimationFrame(loop);
}

// Screensaver never exits cinematic mode
function _introToCorpSetup() { /* screensaver: stay in cinematic */ }

// ── Shot pool builder ─────────────────────────────────────────────────────
// Generates a large random pool of cinematic shots from all galaxy objects.
// Rules:
//   • Planet targets: M, L, XL, XXL only (Fix 3)
//   • Black holes included (Fix 4)
//   • Extra extreme close-up shots on planets (Fix 2)
//   • Pool is constraint-arranged so no two consecutive shots violate (Fix 5)
function _buildIntroShots() {
  if (!galaxy) return [];
  _restoreIntroOverrides();
  const shots = [];
  const _maxSc = MAX_SC, _minSc = MIN_SC;
  const _DIRS = [
    [0, 1],[0,-1],[1, 0],[-1, 0],
    [1, 1],[-1,1],[1,-1],[-1,-1]
  ];
  // ── Planet pool: all biomes/sizes eligible, biased toward rings & moons ─
  // Weight legend:
  //   base 1  +  ring +3  +  >3 moons +2  +  2-3 moons +1  +  L/XL/XXL +1
  // A ringed planet with 4+ moons appears up to 7× as often as a plain one.
  // Each extra entry generates a *different* shot type / direction so the
  // pool stays varied even for heavily-weighted planets.
  const _planetPool = [];
  for (const _pp of galaxy.planets) {
    if (!_pp) continue;
    let _ww = 1;
    if (_pp.ring) _ww += 3;
    const _mc = (_pp.moons || []).length;
    if (_mc > 3)      _ww += 2;
    else if (_mc >= 2) _ww += 1;
    if (['L','XL','XXL'].includes(_pp.size)) _ww += 1;
    for (let _j = 0; _j < _ww; _j++) _planetPool.push(_pp);
  }
  const _pShuf  = _planetPool.sort(() => Math.random() - 0.5);
  const _dShuf  = [..._DIRS].sort(() => Math.random() - 0.5);

  for (let _i = 0; _i < _pShuf.length; _i++) {
    const _p  = _pShuf[_i];
    // Target scale: ~130 px planet-body radius on screen (matches intro cutscene math)
    const _tsc  = Math.min(_maxSc, 130 / Math.max(1, _p.radius));
    const _vpHW = (W / 2) / _tsc, _vpHH = (H / 2) / _tsc;
    const _R    = _p.radius;
    const _d    = _dShuf[_i % _dShuf.length];
    const _dx   = _d[0], _dy = _d[1];

    // ── Pan portrait shot (same offset math as original _buildIntroShots) ──
    shots.push({
      pid: _p.id, durMs: 5000 + Math.random() * 4000,
      ox0:  _dx * (_vpHW - _R * 0.5), oy0:  _dy * (_vpHH - _R * 0.5),
      ox1: -_dx * (_vpHW - _R * 2),   oy1: -_dy * (_vpHH - _R * 2),
      s0: _tsc, s1: _tsc,
    });

    // ── Standard zoom-in (far → close, 40% probability) ────────────────
    if (Math.random() < 0.40) {
      const _fs = Math.max(_minSc, _minSc * (3 + Math.random() * 5));
      shots.push({
        pid: _p.id, durMs: 15000 + Math.random() * 7000,
        ox0: 0, oy0: 0, ox1: 0, oy1: 0,
        s0: _fs, s1: _tsc,
      });
    }

    // ── EXTREME close-up zoom-in (galaxy-wide → max scale, Fix 2) ───────
    // 45% probability — bias the pool toward dramatic close-ups.
    if (Math.random() < 0.45) {
      shots.push({
        pid: _p.id, durMs: 18000 + Math.random() * 4000,
        ox0: 0, oy0: 0, ox1: 0, oy1: 0,
        s0: _minSc * 0.55, s1: Math.min(_maxSc, Math.max(_tsc, _maxSc * 0.85)),
      });
    }

    // ── Zoom-out from extreme close-up → N-stars-in-view endpoint ────────
    // Starts maximally zoomed in, ends when ~5 stars or ~50 stars are in
    // view.  Plain centered zoom-outs starting from the normal portrait
    // scale are excluded — they read as "planet slowly shrinking into
    // darkness" with nothing interesting happening.
    if (Math.random() < 0.35) {
      const _N   = Math.random() < 0.5 ? 5 : 50;
      const _end = _SS_endScaleForStarCount(_p.x, _p.y, _N);
      shots.push({
        pid: _p.id, durMs: 18000 + Math.random() * 4000,
        ox0: 0, oy0: 0, ox1: 0, oy1: 0,
        s0: Math.min(_maxSc, Math.max(_tsc, _maxSc * 0.90)),
        s1: _end,
      });
    }

    // ── Static hold: planet drifts across locked frame via orbit (18%) ──
    if (Math.random() < 0.18) {
      shots.push({
        mode: 'planetStatic', pid: _p.id, scale: _tsc,
        capturedX: null, capturedY: null, capturedTs: -1,
        durMs: 5000 + Math.random() * 5000,
      });
    }
  }

  // ── Star shots ─────────────────────────────────────────────────────────
  const _nonHuge = galaxy.stars.filter(s => s && s.size !== 'L');
  const _sSrc    = _nonHuge.length >= 2 ? _nonHuge : galaxy.stars.filter(Boolean);
  const _sShuf   = [..._sSrc].sort(() => Math.random() - 0.5);
  for (const _s of _sShuf) {
    const _rv = Math.random();
    if (_rv < 0.36) {
      // Tight pan across the star disc: both directions (Dyson-sphere framing)
      // Star body fills ~60% of viewport height; pans at ~half its own radius.
      const _sc = Math.min(_maxSc, (H * 0.6) / Math.max(1, _s.radius));
      const _hw = (W / 2) / _sc;
      // Original: star centre at left edge, drifts rightward across screen
      shots.push({ kind: 'star', durMs: 5000 + Math.random() * 3000,
        x0: _s.x + _hw,           y0: _s.y, s0: _sc,
        x1: _s.x + _hw - _s.radius * 0.5, y1: _s.y, s1: _sc });
      // Mirror: star centre at right edge, drifts leftward across screen
      shots.push({ kind: 'star', durMs: 5000 + Math.random() * 3000,
        x0: _s.x - _hw,           y0: _s.y, s0: _sc,
        x1: _s.x - _hw + _s.radius * 0.5, y1: _s.y, s1: _sc });
    } else if (_rv < 0.72) {
      // Zoom-out: star body → whole solar system
      const _maxOrb = galaxy.planets
        .filter(p => p && p.starId === _s.id && !p.isStarProxy)
        .reduce((mx, p) => Math.max(mx, p.orbitRadius || 0), 800);
      const _wide  = Math.max(_minSc * 4, (W * 0.40) / Math.max(1, _maxOrb));
      const _close = Math.min(_maxSc, 220 / Math.max(50, _s.radius));
      const _dr    = _maxOrb * 0.10 * (Math.random() < 0.5 ? 1 : -1);
      shots.push({ kind: 'star', durMs: 15000 + Math.random() * 7000,
        x0: _s.x, y0: _s.y, s0: _close,
        x1: _s.x + _dr, y1: _s.y - _dr * 0.5, s1: _wide });
    } else {
      // Dense cluster pan at fixed mid-zoom
      const _dsc = _maxSc * 0.18;
      const _hw2 = (W / 2) / _dsc;
      const _pan = _hw2 * 0.35;
      const _pd  = Math.random() < 0.5 ? 1 : -1;
      shots.push({ kind: 'star', durMs: 6000 + Math.random() * 3000,
        x0: _s.x - _pan * _pd, y0: _s.y - _pan * 0.4, s0: _dsc,
        x1: _s.x + _pan * _pd, y1: _s.y + _pan * 0.4, s1: _dsc });
    }
  }

  // ── Nebula shots ───────────────────────────────────────────────────────
  if (galaxy.nebulas && galaxy.nebulas.length) {
    for (const _n of galaxy.nebulas) {
      const _mid = Math.min(_maxSc * 0.3,
        (Math.min(W, H) * 0.6) / Math.max(_n.rx || 1, _n.ry || 1));
      const _out = Math.max(_minSc * 2, _mid * 0.35);
      const _zIn = Math.random() < 0.5;
      shots.push({ kind: 'nebula', durMs: 12000 + Math.random() * 8000,
        x0: _n.x, y0: _n.y, s0: _zIn ? _out : _mid,
        x1: _n.x, y1: _n.y, s1: _zIn ? _mid : _out });
    }
  }

  // ── Black hole shots (Fix 4) ───────────────────────────────────────────
  if (galaxy.blackHoles && galaxy.blackHoles.length) {
    for (const _bh of galaxy.blackHoles) {
      const _far   = _minSc * 3;
      const _close = Math.min(_maxSc * 0.7, 220 / Math.max(20, _bh.radius));
      // Zoom in toward the event horizon
      shots.push({ kind: 'blackHole', durMs: 15000 + Math.random() * 7000,
        x0: _bh.x, y0: _bh.y, s0: _far, x1: _bh.x, y1: _bh.y, s1: _close });
      // Zoom out from the event horizon into deep space
      shots.push({ kind: 'blackHole', durMs: 12000 + Math.random() * 6000,
        x0: _bh.x, y0: _bh.y, s0: _close, x1: _bh.x, y1: _bh.y, s1: _far });
    }
  }

  // Shuffle for variety, then apply constraint-aware arrangement (Fix 5)
  shots.sort(() => Math.random() - 0.5);
  return _SS_arrange(shots);
}

// ── Cinematic loop ────────────────────────────────────────────────────────
// Pure cinematic render: no dim overlay, no narration, no buttons.
// Tracks shot kinds for constraint enforcement (Fix 5).
// Updates starPan so parallax background stars move with the camera.
function drawHowToPlay(ts) {
  if (!_introShots || !_introShots.length) {
    _introShots = _buildIntroShots();
    _introShotIdx = 0; _introShotStartTs = ts;
    _ssCamPrevX = null; _ssCamPrevY = null;
  }

  if (_introShots.length) {
    const _shot0 = _introShots[_introShotIdx];
    const _dur0  = (_shot0 && _shot0.durMs) || _INTRO_SHOT_MS;
    if (ts - _introShotStartTs >= _dur0) {
      // Record kind of completed shot; update gap counter; inform next constraint
      _SS_lastShotKind = _SS_classify(_shot0);
      if (_SS_lastShotKind === 'zoomOut') _SS_shotsSinceZoomOut = 0;
      else _SS_shotsSinceZoomOut++;
      _introShotIdx++;
      _introShotStartTs = ts;
      if (_introShotIdx >= _introShots.length) {
        // Pool exhausted — rebuild; _SS_shotsSinceZoomOut seeds the gap check
        _introShots = _buildIntroShots();
        _introShotIdx = 0;
        _ssCamPrevX = null; _ssCamPrevY = null;
      }
    }

    const _shot = _introShots[_introShotIdx];
    if (!_shot) return;
    const _dur = (_shot.durMs) || _INTRO_SHOT_MS;
    // Constant-speed linear t — same as updated intro cutscene (no ease)
    const _t = Math.min(1, (ts - _introShotStartTs) / _dur);

    // ── Camera dispatch — identical to original drawHowToPlay ─────────
    if (_shot.mode === 'planetStatic') {
      const _ap = galaxy && galaxy.planets[_shot.pid];
      if (_ap) {
        if (_shot.capturedTs !== _introShotStartTs) {
          _shot.capturedX = _ap.x; _shot.capturedY = _ap.y;
          _shot.capturedTs = _introShotStartTs;
        }
        cam.x = _shot.capturedX; cam.y = _shot.capturedY;
      }
      cam.scale = _shot.scale;
    } else if (_shot.mode === 'orijenZoomOut') {
      const _ap = galaxy && galaxy.planets[_shot.pid];
      if (_ap) { cam.x = _ap.x; cam.y = _ap.y; }
      cam.scale = _shot.s0 * Math.pow(_shot.s1 / _shot.s0, _t);
    } else if (_shot.pid != null) {
      const _ap = galaxy && galaxy.planets[_shot.pid];
      if (_ap) {
        cam.x = _ap.x + _shot.ox0 + (_shot.ox1 - _shot.ox0) * _t;
        cam.y = _ap.y + _shot.oy0 + (_shot.oy1 - _shot.oy0) * _t;
      }
      cam.scale = _shot.s0 * Math.pow(_shot.s1 / _shot.s0, _t);
    } else {
      cam.x = _shot.x0 + (_shot.x1 - _shot.x0) * _t;
      cam.y = _shot.y0 + (_shot.y1 - _shot.y0) * _t;
      cam.scale = _shot.s0 * Math.pow(_shot.s1 / _shot.s0, _t);
    }

    // Update starPan so parallax background stars move with the camera.
    // Formula matches the game's WASD / tracking branches:
    //   starPan.x -= (oldCam.x - newCam.x) * cam.scale
    if (_ssCamPrevX !== null) {
      starPan.x -= (_ssCamPrevX - cam.x) * cam.scale;
      starPan.y -= (_ssCamPrevY - cam.y) * cam.scale;
    }
    _ssCamPrevX = cam.x;
    _ssCamPrevY = cam.y;
  }

  if (galaxy) {
    try { updatePlanetOrbits(1.0, 1); } catch (e) { /* swallow */ }
    _drawCutsceneBg(ts);
    _clearTextOverlay();
  } else {
    ctx.fillStyle = '#060810'; ctx.fillRect(0, 0, W, H);
  }
}

// ── Music bar wiring ──────────────────────────────────────────────────────
(function _SS_wireMusicBar() {
  const _bar  = document.getElementById('ss-music-bar');
  const _mute = document.getElementById('ss-mute');
  const _prev = document.getElementById('ss-prev');
  const _next = document.getElementById('ss-next');
  const _fill = document.getElementById('ss-fill');
  const _ttl  = document.getElementById('ss-title');
  if (!_bar) return;

  function _ui() {
    if (!_mute) return;
    const _mt = typeof _musicMuted !== 'undefined' && _musicMuted;
    _mute.textContent  = _mt ? '\u{1F507}' : '\u{1F50A}';
    _mute.style.background  = _mt ? 'rgba(90,30,30,0.92)'   : 'rgba(20,40,80,0.85)';
    _mute.style.borderColor = _mt ? 'rgba(255,100,100,0.8)' : 'rgba(60,120,200,0.55)';
    _mute.style.color       = _mt ? '#f88'                   : '#8cf';
    if (_ttl && typeof _MUSIC_TRACKS !== 'undefined' && typeof _musicIdx !== 'undefined') {
      const _tk = _MUSIC_TRACKS[_musicIdx];
      _ttl.textContent = (_tk && _tk.title ? _tk.title : '').toUpperCase();
    }
  }
  function _prog() {
    if (!_fill || typeof _soundtrack === 'undefined' || !_soundtrack) return;
    const _d = _soundtrack.duration;
    const _f = (isFinite(_d) && _d > 0)
      ? Math.max(0, Math.min(1, _soundtrack.currentTime / _d)) : 0;
    _fill.style.width = (_f * 100) + '%';
  }

  if (_mute) _mute.addEventListener('click', e => {
    e.stopPropagation();
    if (typeof _toggleMusicMute === 'function') _toggleMusicMute();
    _ui();
  });
  if (_prev) _prev.addEventListener('click', e => {
    e.stopPropagation();
    if (typeof _musicPrev === 'function') _musicPrev();
    _ui();
  });
  if (_next) _next.addEventListener('click', e => {
    e.stopPropagation();
    if (typeof _musicNext === 'function') _musicNext();
    _ui();
  });

  if (typeof _soundtrack !== 'undefined' && _soundtrack) {
    _soundtrack.addEventListener('timeupdate', _prog);
    _soundtrack.addEventListener('loadedmetadata', () => { _ui(); _prog(); });
    _soundtrack.addEventListener('ended', () => setTimeout(_ui, 80));
  }

  // First click anywhere: start music + reveal bar
  let _started = false;
  document.addEventListener('click', function _onFirst() {
    if (_started) return;
    _started = true;
    if (typeof _tryPlaySoundtrack === 'function') _tryPlaySoundtrack();
    _bar.style.opacity = '1';
    _bar.style.pointerEvents = 'auto';
    _ui();
  }, true);

  // Auto-reveal bar after 4 s as a hint
  setTimeout(() => {
    _bar.style.opacity = '1';
    _bar.style.pointerEvents = 'auto';
    _ui();
  }, 4000);

  setInterval(_prog, 250);
})();
"""

# ── Stubs for game assets we don't need in the screensaver ───────────────
STUBS = (
    "const ASSETS = {};\n"
    "const SPRITE_BOT = {};\n"
    "const SPRITE_NATURAL = {};\n"
    "const SPRITE_CONTENT = {};\n"
    "const SOUNDS = {};\n"
)

# ── HTML fragments (string concat avoids f-string / brace conflicts) ───────
MUSIC_BAR_HTML = (
    '<div id="ss-music-bar">\n'
    '  <div id="ss-music-label">MUSIC</div>\n'
    '  <div id="ss-controls">\n'
    '    <button class="ss-btn" id="ss-mute" title="Mute / Unmute">&#x1F50A;</button>\n'
    '    <button class="ss-btn" id="ss-prev" title="Previous track">&#9664;</button>\n'
    '    <div id="ss-progress-wrap">\n'
    '      <div id="ss-progress-bar"><div id="ss-fill"></div></div>\n'
    '      <div id="ss-title">&#8212;</div>\n'
    '    </div>\n'
    '    <button class="ss-btn" id="ss-next" title="Next track">&#9654;</button>\n'
    '  </div>\n'
    '</div>\n'
)

SCREENSAVER_CSS = """
*{margin:0;padding:0;box-sizing:border-box}
html,body{width:100%;height:100%;overflow:hidden;background:#000}
canvas{display:block;width:100vw;height:100vh}
#ss-music-bar{
  position:fixed;bottom:20px;left:50%;transform:translateX(-50%);
  background:rgba(0,0,0,0.88);border:1px solid rgba(60,120,200,0.40);
  border-radius:14px;padding:9px 16px 11px;
  display:flex;flex-direction:column;align-items:center;gap:5px;
  min-width:260px;user-select:none;
  opacity:0;pointer-events:none;transition:opacity 0.6s;
  box-shadow:0 4px 24px rgba(0,0,0,0.7);z-index:99;
}
#ss-music-label{
  font:bold 11px Orbitron,sans-serif;color:#4af;letter-spacing:0.14em;
}
#ss-controls{display:flex;align-items:center;gap:8px;width:100%}
.ss-btn{
  width:22px;height:22px;border-radius:4px;
  border:1.5px solid rgba(60,120,200,0.55);
  background:rgba(20,40,80,0.85);color:#8cf;
  font-size:13px;font-weight:bold;cursor:pointer;
  display:flex;align-items:center;justify-content:center;
  flex-shrink:0;transition:background 0.15s,border-color 0.15s;
  padding:0;line-height:1;
}
.ss-btn:hover{background:rgba(35,95,200,0.97);border-color:rgba(140,210,255,0.95)}
#ss-progress-wrap{flex:1;display:flex;flex-direction:column;gap:3px;align-items:center}
#ss-progress-bar{
  width:100%;height:6px;background:rgba(0,0,0,0.85);border-radius:2px;
  border:1px solid rgba(80,140,210,0.55);overflow:hidden;
}
#ss-fill{
  height:100%;background:rgba(120,200,255,0.92);border-radius:2px;
  width:0%;transition:width 0.22s linear;
}
#ss-title{
  font:9px "Exo 2",sans-serif;color:#fa4;white-space:nowrap;
  overflow:hidden;text-overflow:ellipsis;max-width:160px;
}
"""

html = (
    "<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n"
    "<meta charset=\"UTF-8\">\n"
    "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">\n"
    "<title>Space Train &#8212; Screensaver</title>\n"
    "<style>" + font_css + "</style>\n"
    "<style>" + SCREENSAVER_CSS + "</style>\n"
    "</head>\n<body>\n"
    "<canvas id=\"c\"></canvas>\n"
    # Hidden elements the game JS references
    "<button id=\"refresh-btn\" style=\"display:none\"></button>\n"
    "<input id=\"name-edit\" type=\"text\" maxlength=\"32\" autocomplete=\"off\" "
    "spellcheck=\"false\" style=\"position:fixed;display:none;background:rgba(4,8,28,0.97);"
    "color:#4af;border:1.5px solid rgba(80,160,255,0.7);outline:none;"
    "font:bold 11px Orbitron,sans-serif;padding:2px 6px;border-radius:2px;z-index:20;\"/>\n"
    + MUSIC_BAR_HTML
    + "<script>\n"
    + STUBS + "\n"
    + js + "\n"
    + SS_JS
    + "\n</script>\n</body>\n</html>\n"
)

with open("screensaver.html", "w", encoding="utf-8") as f:
    f.write(html)

kb = len(html) // 1024
print(f"Built screensaver.html  ({kb} KB)")
