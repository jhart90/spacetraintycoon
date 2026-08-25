---
name: rebuild-no-ui
description: >
  Re-derive a "no-UI" build of the game — build_game_without_UI.py that emits
  index_without_UI.html — in which galaxy view fills the whole screen with NO HUD
  chrome (top bar, right panel, bottom info bar, mission tracker, chat log, hint
  bar, zoom/speed indicators, selection rings, tutorial/educational callouts),
  while trains/planets/stars stay selectable and all popups still open via
  hotkeys and render unchanged. Use whenever the user wants to (re)create the
  no-UI / clean / cinematic / screenshot variant of the game, port it to a new
  version (e.g. v1.0.0), or asks "rebuild without UI", "make a no-UI version",
  "regenerate build_game_without_UI", "headless view build", "clean galaxy view".
  Optional cinematic/video variant (Step 4b) ALSO strips all text from the intro
  cutscene (narration, SKIP button, dim overlay) so the 11-shot camera loops as
  clean, text-free footage — use for "video-ready", "promo clips", "remove
  cutscene text", "text-free intro" requests.
---

# Rebuild the game without UI

## Why this is a *method*, not a patch

`build_game.py` is a single ~32k-line Python script that prints `index.html`. It
drifts constantly — line numbers move, new UI elements get added between
versions. So **do not** keep `build_game_without_UI.py` as a long-lived file that
you hand-merge; it will bitrot. Instead, **re-derive it from the CURRENT
`build_game.py` each time** using the recipe below. The edits are anchored on
searchable strings (and a single concept), so they survive line drift.

Read `memory/code_map_build_game.md` §4 (drawGalaxy z-order) first if you're
unfamiliar with the render structure.

## The core idea (one flag, two mechanisms)

A single JS flag `const _NO_UI = true;` drives everything:

1. **Zero the three galaxy layout constants** so the galaxy viewport fills the
   whole canvas. Every cull check, the galaxy clip rect, the fog canvas, and the
   `w2s`/`s2w` world↔screen mapping all derive from these constants — so zeroing
   them makes galaxy content span the full screen automatically, with no need to
   touch scattered cull math.
   - `BAR_H` → 0  (so `GH = H - BAR_H` becomes full height `H`)
   - `TOP_H` → 0
   - `PANEL_W` → 0

   **Why this doesn't move popups:** `drawPopupBase` centers popups on full
   `W`/`H` (`(W-pw)/2, (H-ph)/2`), NOT on the viewport. So popups render in
   exactly the same place. **Verify this is still true** in the target version
   (grep `function drawPopupBase`); if a future version starts offsetting popups
   by `PANEL_W`/`TOP_H`, you'd need to special-case those popups.

   **Why input still works everywhere:** with the constants zeroed, the panel/bar
   hit-test branches collapse — `galaxyClick`'s early returns (`if(sy<TOP_H)`,
   `if(sy>GH)`, `if(sx>W-PANEL_W)`) never fire, and the mousedown panel branch
   `if(cp.x>=W-PANEL_W && cp.y<GH)` never matches — so every click falls through
   to galaxy selection. UI bounds arrays (`_hintBounds`, `_missionTrackerBounds`,
   etc.) stay empty because we skip drawing the chrome that fills them, so no UI
   hit handler intercepts. (Confirm no code *divides* by these constants:
   `grep -nE "/\s*(PANEL_W|TOP_H|BAR_H|GH)\b"` — at v0.4.x there were none.)

2. **Guard every chrome DRAW call** in `drawGalaxy` with `if(!_NO_UI)`. Zeroing
   the constants alone would still call the draw functions (drawing 0-size junk),
   so each chrome draw is explicitly skipped.

## Recipe

### Step 1 — copy
```
Copy-Item build_game.py build_game_without_UI.py
```

### Step 2 — change the output filename (2 sites near end of file)
Find `with open("index.html"` and the `print("Built index.html,`:
- `open("index.html"` → `open("index_without_UI.html"`
- `print("Built index.html,` → `print("Built index_without_UI.html,`

### Step 3 — add the flag + zero the constants
Find the `// ── galaxy constants ──` block (anchor: `const BAR_H`):
```js
const _NO_UI   = true;
const BAR_H    = _NO_UI ? 0 : 72;
const TOP_H    = _NO_UI ? 0 : 28;
const GH       = H - BAR_H;
const PANEL_W  = _NO_UI ? 0 : 185;
```
(Keep whatever the current numeric literals are — only wrap them in `_NO_UI ? 0 : <orig>`. `_NO_UI` must be declared at/above this point, before its first use.)

### Step 4 — guard the chrome draws in drawGalaxy
`drawGalaxy` renders galaxy content inside a viewport clip, then `ctx.restore()`s
that clip and draws all HUD chrome. Guard each of these (anchors in **bold**):

| Element | Anchor to find | Edit |
|---|---|---|
| Selection ring | `// Selection ring` then `if(sel){` | → `if(sel&&!_NO_UI){` |
| Right panel + info bar + mission tracker + chat log + hint bar | the line `ctx.restore(); // end galaxy-viewport clip` (block START), through the hint-bar `for` loop just before `drawSpeedIndicator();` (block END) | wrap the whole span in `if(!_NO_UI){ … }` — insert `if(!_NO_UI){` right AFTER the clip-restore line, and a matching `}` right BEFORE `drawSpeedIndicator();` |
| Zoom + speed indicator | `drawSpeedIndicator();` | → `if(!_NO_UI) drawSpeedIndicator();` |
| `[GAME PAUSED]` banner | `_drawPausedBanner(H/2,null,true);` | prefix the `if` with `!_NO_UI &&` |
| Educational callouts + galaxy tutorial chain | the block from `_maybeStartMissionTip();` / `_drawMissionTip();` … through `_drawTutorialChain('galaxy');` | wrap that whole block in `if(!_NO_UI){ … }` |
| Buy-train-plus callout | `_drawBuyTrainPlusHintCallout();` | → `if(!_NO_UI) _drawBuyTrainPlusHintCallout();` |
| Top bar | `drawTopBar();` | → `if(!_NO_UI) drawTopBar();` |
| Panel folder tabs | `drawPanelTabs();` | → `if(!_NO_UI) drawPanelTabs();` |
| Popup-stage tutorial chain | `_drawTutorialChain('popup');` | → `if(!_NO_UI) _drawTutorialChain('popup');` |
| Visit hint | `_drawVisitHint();` | → `if(!_NO_UI) _drawVisitHint();` |

**The wrapped span (clip-restore → before drawSpeedIndicator)** is the trickiest
edit. It must START after `ctx.restore(); // end galaxy-viewport clip` (that
restore MUST still run — it closes the viewport clip) and END right before
`drawSpeedIndicator();`. Everything inside (drawTrainsPanel, info bar, mission
tracker, chat log, hint bar) uses self-contained `ctx.save()/restore()` pairs, so
skipping the whole block leaves the canvas state balanced.

### Step 4b — (cinematic / video variant ONLY) strip intro cutscene text

Apply this step **only** when the user wants video-ready / promo / text-free
cutscene footage. It is OPTIONAL — skip it for a plain no-UI screenshot build if
the user still wants a readable, skippable intro.

The intro cutscene is a SEPARATE render path (`gs==='howtoplay'`) that the Step-4
galaxy guards never touch, so by default the no-UI build still plays the full
narration. The cutscene's looping camera (`_drawCutsceneBg`) draws **no** in-world
text — line `_clearTextOverlay(); // nothing in the cutscene bg writes HD text`
confirms it — so the ONLY text in the cutscene is three calls in the intro draw
function. Gate all three behind `!_NO_UI`.

Find the block (anchor: `_introRenderText(ts);`) and wrap the dim overlay +
narration + skip button:
```js
  // ── Cinematic dim overlay so the narration text reads cleanly. ─
  if(!_NO_UI){
    ctx.fillStyle='rgba(0,0,0,0.42)';
    ctx.fillRect(0, 0, W, H);
    _introRenderText(ts);     // narration (typed one word at a time)
    _introRenderSkipBtn(ts);  // SKIP button (bottom-right)
  }
```
(Keep whatever the current dim-overlay alpha/lines are — just wrap the whole
block.) The dim overlay is gated too: it only exists to make narration legible,
so with no text it would needlessly darken the footage; skipping it gives
full-bright cinematic scenes.

**Behavioural notes to relay to the user:**
- There is NO time-based auto-exit from the cutscene — it leaves only on
  click/key (advancing past the last `_INTRO_TEXT` paragraph) or ESC. So with
  text removed the 11-shot camera loops **indefinitely** hands-free — ideal for
  capture.
- A click/keypress still silently advances the (now invisible) narration; after
  ~3 it exits to the game, and ESC exits immediately. Tell the user NOT to touch
  input during the cutscene if they want the loop.

### Things to KEEP (do NOT guard)
- `drawPopupBase` and every popup draw (`drawPokedex`, `drawPlanetDetailPopup`,
  `drawRoutesPopup`, `drawCarDetailPopup`, `drawFinancesPopup`, …) — popups must
  render as usual.
- Popup/hover tooltips tied to popups: `_drawStationHoverTooltipOverlay()`,
  `_drawRoutesVizTooltip()`.
- In-world scene/gameplay visuals: planet/star **name labels**, route-planning
  preview + route-stop rings, credit floats, cargo particle beams, fog,
  mission-target outline rings, `_drawNewspaper`.
- The whole keyboard handler — hotkeys (`P Y T R I M O`, `C` in Options, etc.)
  open popups regardless of rendering.

### Step 5 — build
```
cd "C:\Users\jackh\Desktop\Claude\Train Game"
python build_game_without_UI.py
```
Expect `Built index_without_UI.html, ~3700+ KB`. A Python error here usually
means a bad string match; a *silent* success but broken game usually means an
unbalanced `{ }` in the wrapped span (recount the closers before
`drawSpeedIndicator();`).

## Handling NEW UI added since the last port (IMPORTANT for v1.0.0)

Future versions will add HUD elements this recipe doesn't name. After applying
the recipe, **sweep `drawGalaxy` for any draw that happens AFTER the
`ctx.restore(); // end galaxy-viewport clip` line** — almost everything drawn
after that restore is screen-space HUD chrome and is a candidate to guard.
Useful greps over `build_game.py`:
```
grep -nE "draw[A-Z][A-Za-z]*\(|_draw[A-Z][A-Za-z]*\(" build_game.py   # all draw calls
grep -nE "TOP_H|PANEL_W|BAR_H" build_game.py                          # new chrome geometry
```
Decision rule for a new element:
- **Persistent HUD chrome** (bars, panels, trackers, indicators, on-canvas
  buttons, floating hint/tutorial text) → guard with `if(!_NO_UI)`.
- **A popup window or its internal tooltip** → keep (popups render as usual).
- **In-world scene content** (labels on planets/stars, route visuals, particle
  effects, fog) → keep.

## Verification checklist (give this to the user — do NOT browser-verify yourself)

Per project rule `memory/rule_no_browser_verify.md`, hand the user a numbered
list to check in `index_without_UI.html`:

1. No top bar, right panel, or bottom info bar — galaxy reaches all 4 edges.
2. No chat log, no mission tracker, no `[P] planets … [O] options` hint bar.
3. No zoom bar / speed selector; SPACE pause shows no `[GAME PAUSED]` banner
   (but speed/zoom keys still work).
4. Clicking a train/planet/star selects it (camera tracks) with **no ring**.
5. Each hotkey popup (`P Y T R I M O`, `C` in Options) opens, centered as normal.
6. Double-click a train/planet/star opens its detail popup.
7. Shift-click two planets still builds a route (preview shows); trains animate.
8. Pan (WASD/drag) + zoom (Up/Down) — content fills edge-to-edge, no black bands.
9. `python build_game.py` still produces a normal-UI `index.html` (sanity check
   the original wasn't touched).
10. **(cinematic variant only)** On load the intro cutscene plays with ZERO text —
    no narration, no SKIP button, no dim wash; scenes are full-bright and the
    camera loops indefinitely if you don't touch input.

## Reference: the v0.4.x baseline

The first no-UI port was done against v0.4.3-dev (build_game.py ~32.5k lines).
If the current file is close to that, the exact `_NO_UI` guards and wrapped span
from that port are a good starting template; if it has drifted a lot, fall back
to the method above. The decisions made then (suppress tutorials/callouts and the
pause banner; keep popup tooltips, name labels, and route visuals) are the
default scope — confirm with the user if they want a different cut.
