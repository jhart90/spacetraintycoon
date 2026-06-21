# Brand-new faithfulness audit — Godot 2D port vs original (build_game.py)

Date: 2026-06-21. Method: 8 parallel agents each read the REAL draw/sim code on BOTH sides
(build_game.py = source of truth) and cited line numbers. The existing `AUDIT_INVENTORY.md` /
`DISCREPANCIES.md` were explicitly NOT trusted — they over-report faithfulness.

## Top-line verdict

The port is a **faithful-ish renderer wrapped around a heavily simplified simulation.** The galaxy
camera transform/clamp/pan, the revenue math, the train-consist galaxy sizing, and many popup
*shells* are accurate. But:

1. **The core gameplay loop is largely non-functional.** `Discovery.track_visit()` — the function
   that rewards exploration, reveals systems, unlocks biome cars, and arms ~8 missions — **has zero
   callers**. The mission-trigger graph is absent (only 2 of ~24 missions can appear). Trains fly
   straight through stars and black holes (no `segmentBlockedByStar`, no engine range limit, no
   queueing/descending phases). There is no SPACE pause and no autosave. The "parity-verified" claim
   in memory applied to isolated pure functions, NOT the integrated loop.
2. **Several "done" UI surfaces are stripped or wrong**: Missions popup, Finances (no Loans/VS-Rival
   tabs), Corp dashboard (120px short, missing half its content), Train Builder (car grid truncated
   to 12, wrong cost model), corp-setup + AI-select screens (wrong title/cards/sprites).
3. **Whole visual systems missing**: Dyson sphere, both nebula layers, storm lightning, lava
   volcanoes, mountains, flowers, hazmat/escort car glows.
4. **Typography**: italics are entirely absent (~25 sites); auto-bold-CAPS absent; mission text
   token styling flat; the NEW-MISSION details paragraph is omitted entirely.

---

## ✅ FIX PROGRESS (2026-06-21, post-audit)

**Visuals — step 4:**
- ◐ **V3** — per-biome surface effects added to `GalaxyContent._draw_surface`: **lava volcanoes**
  (2–4 cones extruding from the rim with a dark-basalt body + glowing lava cap + pulsing crater bloom —
  the "flat red sphere" is now an active volcanic world), **mountains** (3–6 snow-capped ridge triangles
  on rocky/ice/ancient rims), and **storm lightning** (animated purple bolt polylines + ambient electric
  glow on storm planets). Per-planet data is seed-generated + cached like the existing resort/agri/oil
  surfaces. Lava + mountains screenshot-verified. REMAINING in V3: flower fields (baked, lower priority).
- ◐ **V4** — **hazmat warning light** added to `TrainsLayer._draw_car`: a pulsing 3-layer yellow glow
  (outer bloom + halo + mid + white core, quick-on/gradual-fade via sin^0.5) above a FULL hazmat car
  (build_game.py:29807). Compiles clean; not screenshot-verified (the demo train has no hazmat car).
  REMAINING in V4: the mission **escort-car backlit glow** — needs the `carEscort` tag set by the
  Ancient Schematics / Mad Scientist missions, which aren't wired in the port yet.

**Front-end screens — step 3 + typography:**
- ◐ **U7 / T1 / T2** — intro **narration typography** rebuilt to `_introRenderText`: ported
  `_find_caps_ranges` so all-caps runs render **bold**, screen-2 italic targets ("inter-galactic
  domination", "catastrophic demise!") render **italic**, and the closing "The race has begun…" line
  renders fully bold; text is 15px, vertically centred, single `rgba(0,0,0,0.42)` dim. Built the
  reusable **italic Exo 2** (synthetic glyph-shear FontVariation) + **bold Exo 2** variants (T1).
  Replaced the SKIP stub with **SKIP ▶▶ / ◀ QUIT / ♪ mute** controls that proximity-fade (0.25→1.0
  within 60px); removed the non-original progress dots; fixed the para-3 wording ("is able to re-build"
  + the `\n` before THE MULTI-VERSE). Screenshot-verified. REMAINING in U7: the 11-shot cinematic
  camera path (the port's 5-shot sequence still drives the camera) — a separate camera-work pass.
- ✅ **U5** — **corp-setup** and **AI-select** rebuilt to the faithful panelled spec. Corp-setup:
  full-screen bordered panel, glowing "ESTABLISH YOUR CORPORATION" title, "NAME YOUR CORPORATION:"
  label + name field (click to rename), and the 242×240 CEO cards with portrait + nickname + the three
  labelled pill rows (**SALARY** tier-colored / **ABILITY** blue / **STARTING CREDITS** green), green
  selection, and the pulsing blue **NEXT ▶** button. AI-select: amber-bordered panel, glowing
  "SELECT YOUR OPPONENT", the **correct sprite set** (engine_galaxy/car_flowers/car_water_tank/car_sand/
  car_ore/car_hazmat — 5 of 6 were wrong), per-difficulty fill colors with dark/light text, sprites
  straddling the top edge, the corner-bleed ✓, and the spurious corp banner removed. Both
  screenshot-verified. (Remaining step-3 item: U7 intro cinematic.)

**Headline popups — step 2:**
- ✅ **U2** — Finances `[F]` gained the **file-folder tab strip** (FINANCIALS / LOANS / VS RIVAL, the
  last only when a rival exists) with click-to-switch. **VS-RIVAL tab** ported from
  `_drawFinancesVersusTab`: player-vs-rival Corp-Value line chart over the last 10 SD with nice-step Y
  gridlines, SD X axis, two plotted series + corp-name legend — backed by the real `corp_value_history`
  and a new `ai_corp_value_history` snapshot recorded each SD boundary. Screenshot-verified. The
  **LOANS tab** is an honest stub stating loan financing isn't simulated (the original's interest/
  amortization/tier subsystem is a genuine feature build, not a UI port — deliberately not faked).
- ✅ **U3** — Corp dashboard restored to the faithful `drawCorpPopup` (570×440): taller frame,
  two-sub-column financials (P&L + balance sheet; LIQUID ASSETS label fixed, TOTAL DEBTS shows "—"),
  CEO pane now has the **salary pill** (tier-colored) + **perk pills** (green/blue) + nickname, and the
  full bottom **EXPLORATION** (8 stats: planets/stars discovered & visited, resource types, gold/diamond
  patches, phenomena) + **FLEET & OPERATIONS** (8 stats: distance, trains, cars, stations, upgrades,
  cargo, passengers, hazmat) section. Screenshot-verified — all 16 bottom stats populate from the live
  Discovery/Transit/ledger data.
- ◐ **U4** — Train Builder car grid fixed: now shows ALL 23 car types (build_game.py ALL_MID_CARS),
  unlocked-first, 6 per row, with locked cars greyed + a LOCKED overlay, row-snapped scroll +
  scrollbar + mouse-wheel — resolving the functional blocker (couldn't reach cars beyond the first 12,
  and locked cars were invisible). Also added the full engine-details RANGE/ACCEL rows earlier.
  REMAINING for U4: trainyard cost model (charge only for cars not already owned; needs a trainyard
  sim) and per-car removal in the preview (currently removes the last car).
- ✅ **U1** — Missions `[M]` popup rebuilt to the faithful `drawMissionsPopup` structure (480×360):
  status line "N active · N completed", active-first sorted rows with per-row variable height +
  mouse-wheel scroll, 52×52 image box (target glyph + ✓ overlay for completed), ellipsized yellow/grey
  name, ACTIVE/COMPLETE badge, green REWARD pill + "REWARD" label, italic details, ○/✓ objectives
  with wrapped text, and the "— COMPLETED —" divider. (Data-limited vs original: no mission-image
  sprites, deadline badges, or quantified-objective progress bars — the ported sim lacks those fields.)
  Screenshot-verified.

**Gameplay loop — step 1 of the priority order:**
- ✅ **G1** — `Discovery.track_visit()` is now CALLED from the Transit arrival site for player
  trains. Added the first-visit credit reward (1000 home / 2000 other-star / 3000 >100k SU), biome
  car unlocks (desert→sand, ice→ice, oil→oil, storm→battery, chemical→chemical; agri→grain/livestock/
  fruit by upgrade), Bakery/Glassworks upgrade unlocks, a "<planet> — VISITED" chat message, and a
  reward credit-float. Verified headless: visiting P122 fired "+1000 cr", visited 1→2.
- ◐ **G2** — visit-driven mission intros wired: `create_route` (first non-home visit), `galaxy_census`
  (15 visited → intro, 50 → objective), and route-assign completes `create_route`. Verified:
  create_route activates on the visit. REMAINING: the full ~24-trigger graph + granular per-objective
  `checkObj` ticking (many objectives are coupled to specific UI/build/timer events) is the next pass.
- ✅ **G3** — trains no longer fly through stars/black holes and can't exceed engine range. Ported
  `segment_blocked_by_star` (point-to-segment vs star/BH radius) + `route_block_reason` (range +
  blocking); `Transit.assign_route` refuses a blocked/over-range route and emits `route_rejected` →
  red chat "couldn't find a viable ROUTE — <reason>". Verified the valid demo route still assigns.
- ✅ **G4** — SPACE pause (`GameState.toggle_pause` stashes/restores the running speed) + per-stardate
  autosave to a reserved `Autosave_<corp>.stt` slot when `autosave_enabled`.

---

## CRITICAL — gameplay loop (highest impact; these change what the player can DO)

- **G1. `track_visit()` is never called** — exploration is dead. Orbiting a new planet does NOT
  reveal the system, award the `dist>100k?3000:other?2000:1000` credit reward, unlock biome cars
  (sand/ice/oil/battery/chemical/…), unlock bakery/glassworks, or arm visit-gated missions.
  Original `build_game.py:16098`; port `Discovery.gd:56` (definition only — no caller; `Transit.gd`
  never references `Discovery`/`Fog`).
- **G2. Mission-trigger graph absent.** Original `updateMissions` evaluates ~24 `pendingMissionIntros`
  triggers every frame (`build_game.py:21450+`). Port wires only `build_foundry` (at start) +
  `research_royal_car` (100 pax) + build hooks (`Missions.gd:11-15,39,90`). ~20 missions can never
  appear; per-objective `checkObj` is deferred.
- **G3. Transit reduced to 2 phases (ORBIT/TRANSIT).** No `segmentBlockedByStar`/`transitPathBlocked`
  → **trains fly through stars and black holes**. No `ENGINE_MAX_RANGE` gating → any engine reaches
  anywhere. No multi-hop detours, no queueing/descending/waiting states. Original `code_map §6`,
  `updateTrain ~13007`; port `Transit.gd:17` (`enum Phase { ORBIT, TRANSIT }`).
- **G4. No SPACE pause.** Original `_spacePauseResumeIdx` (`build_game.py:34374`). Port has no
  KEY_SPACE handler anywhere; only `[`/`]` change speed.
- **G5. AICorp is a stub.** Picks farthest populated system, force-builds stations at init, then each
  tick buys one 2-car constellation. No mirror-system transform, no upgrade/foundry building, no ROI
  route ranking, no exploration. Original `code_map §5`; port `AICorp.gd` (95 lines, deferrals noted).
- **G6. No autosave loop.** `autosave_enabled` toggle (`GameState.gd:92`) controls nothing — no
  per-stardate write. Original `build_game.py:3762`.
- **G7. Camera feel: no selection-pivot zoom / zoom-return.** Original pivots wheel-zoom on the
  selected object and arms a 5s `zoomReturnPos` ease-home (`build_game.py:31582-31614`). Port
  `_zoom_at` always pivots on the cursor (`GalaxyView2D.gd:223`).

## CRITICAL — UI reconstructions

- **U1. Missions `[M]` popup stripped.** Missing 52×52 image boxes, italic details line, REWARD pill,
  ACTIVE/COMPLETE/FAILED badge, deadline countdown badge, per-objective progress bars, scrollbar,
  failed-count in status. Original `build_game.py:21817`; port `_draw_missions` `PopupManager.gd:1861`.
- **U2. Finances `[F]` missing LOANS + VS-RIVAL tabs.** Port draws one non-interactive FINANCIALS
  tab; no tab strip, no loan subsystem, no 10-SD player-vs-rival chart. Original `18550` (`_drawFinancesLoansTab 18336`, `_drawFinancesVersusTab 18178`); port `_draw_finances 2490`.
- **U3. Corp dashboard wrong.** `ph=320` vs original `570×440` (`build_game.py:17742`). Missing the
  entire bottom EXPLORATION / FLEET & OPERATIONS two-column section, CEO salary pill + perk pills,
  logo sprite, DEBTS=loan sum (hardcoded 0). Port `_draw_corp 2651`.
- **U4. Train Builder car grid truncated.** Iterates only unlocked cars and `break`s after 12 — no
  scroll, locked cars never shown (original shows all 23 in a scrollable grid w/ LOCKED overlays,
  `build_game.py:26868`). Cost model is flat `engine + cars*1000` — no trainyard credit, overcharges
  in edit mode (`PopupManager.gd:1344,1377`). No per-car removal/hover-✕/tooltip (whole viz removes
  last car only).
- **U5. Corp-setup + AI-select are wrong-screen reimplementations.** No full-screen bordered panel;
  title 16-18px flat-amber vs original 30px gradient+glow; wrong text ("FOUND" vs "ESTABLISH");
  CEO cards 220×232 (vs 242×240) missing nickname + SALARY/ABILITY/STARTING-CREDITS pill rows;
  selection amber vs green; **AI sprite set 5/6 wrong** (`engine_constellation/car_livestock/...` vs
  `engine_galaxy/car_flowers/car_water_tank/car_sand/car_ore/car_hazmat`); per-difficulty fill colors
  gone; spurious corp banner added. Original `6153-6448`; port `Screens.gd:521-616`.
- **U6. Planet Detail.** STATS tab fabricated (DEV LEVEL/POP/DELIVERIES/ECON HEALTH vs original
  train-visit history); supply/demand sorts wrong dict (`supplyRate` vs `supply` pool) + no
  gold/diamond reveal guard; portrait omits structures/station/patches; upgrades sidebar shows ≤1
  per biome with no STATION card, no gate-lock sort, no scroll. Original `25366+/24192+`; port
  `_pd_* 599-757`.
- **U7. Intro cutscene.** 5-shot hand-rolled camera (durations 6/4.5/4.5/5/6s) vs original 11-shot
  pool with a 22s Orijen opener, 8-direction planet pans, Dyson/black-hole shots, shuffle. Narration
  flat (see T-block). Missing QUIT + MUTE buttons; SKIP is "SKIP ›" 92×26 Exo2 vs "SKIP ▶▶" 110×28
  bold Orbitron w/ proximity fade. Extra invented progress dots. Para-3 text reworded. Original
  `5042-5373`; port `Screens.gd:145-277`.

## CRITICAL — visuals

- **V1. Dyson sphere missing** (220 hex panels, Fibonacci sphere, animated). Original
  `build_game.py:12530`; port `_draw_star GalaxyContent.gd:137` has no Dyson code.
- **V2. Both nebula systems missing.** No tiling nebula sheet (home-quadrant blend + core layer), no
  world-space named nebulas + labels. Port = 7 static faint blobs. Original `11939/8388/8119`; port
  `ScreenBackground.gd:36`.
- **V3. Per-biome surface signatures missing**: storm lightning bolts, lava volcanoes (cones+smoke),
  mountain ridges (snow caps), flower fields. Port `_draw_surface` handles only resort/agri/oil.
  Original `drawPlanet 12275-12459`; port `GalaxyContent.gd:876`.
- **V4. Galaxy car VFX missing**: hazmat warning light (3-layer pulsing glow), escort-car backlit
  glow. Original `29580-29626`; port `TrainsLayer._draw_car 323`.

## CRITICAL — typography

- **T1. Italics entirely absent** (~25 original sites: mission details/flavor, newspaper bylines,
  tutorial emphasis). No italic FontVariation is ever built in the port.
- **T2. Auto-bold-CAPS absent.** Intro narration renders flat; original bolds all-caps runs +
  italicizes target phrases + bolds the closing line (`_findAllCapsRanges 5152`). Port
  `Screens.gd:268` = one flat `draw_multiline_string`.
- **T3. Mission text token styling flat + details omitted.** Tracker, NEW-MISSION popup, and [M] list
  render plain (no `[Cargo]` color/bold, no biome-colored UPPERCASE planet names). The NEW-MISSION
  popup omits the italic `def.details` paragraph entirely. The port HAS a tokenizer (`_tok_words`)
  but wired it into only the upgrade-unlock popup, and even there colored tokens aren't bold and
  planet-name styling isn't handled. Original `16830-16911/22034/1134-1271`; port `Chrome.gd:227`,
  `PopupManager.gd:895,909,1148`.
- **T4. UnifrakturMaguntia (newspaper masthead) never `load()`-ed at runtime** (newspaper itself
  unported).

---

## MODERATE (high-value, scoped fixes)

- Train-status labels wrong/truncated — port emits only LOADING/UNLOADING/IN TRANSIT/IN ORBIT; missing
  `/ PARKED`, `/ ON ROUTE`, QUEUEING, DESCENDING, WAITING FOR CARGO/DEMAND. `Chrome.gd:494` vs `13598`.
- Selected-train info bar is a stub — no color square, route strip, speed bar, coords, Seg%, or
  **CANCEL ROUTE button**. `Chrome.gd:730` vs `30239`.
- Train names show "TRAIN 0" in the info bar instead of the real name. `Chrome.gd:734`.
- Chat-log ↔ hint-bar vertical overlap clips the leftmost hint items. `Chrome.gd:241,266`.
- Selection ring: single yellow `*1.35+7` ring for everything vs blue(planet)/gold(star)/orange(car)
  `+5` rings + grey orbit-tier rings + glow. `GalaxyContent.gd:128` vs `29643`.
- Fog reveals ~2.2× too small (star) / missing ×1.1 (orbited/breadcrumb); sensor-upgrade 1.5× boost
  unimplemented. `FogLayer.gd:78-97` vs `16373-16463`.
- `draw_car_strip` ignores `opts.scale` (0.9/0.8/0.75) and `fogEmpty` (empty-car dimming); spacing is
  a flat `dw*0.72+2` approximation not the shared metrics. `TrainsLayer.gd:261-288`.
- Credit floats: wrong font (13px fallback vs 9px Exo2), no arrow triangle, **green-only (no red for
  losses)**; screen-space floats for purchases/loans not ported. `TrainsLayer.gd:173`.
- Options MUSIC pane missing prev/next/progress-bar/timestamp/track-title/sound-wave/artist; adds
  non-original SAVE-LOAD + QUIT-TO-TITLE buttons. `PopupManager.gd:437` vs `22412`.
- Mission-reward popup: flat pill (no gradient), no detail line, fixed height. New-mission popup: no
  image/details/reward-caption/dynamic sizing. CEO-hire: perk color by index not `isPrimary`.
- Stations window: cargo filter bar entirely missing; planet not edge-clipped. `PopupManager.gd:1714`.
- Routes window: no RULES buttons / rule asterisks / horizontal scroll.
- Trains window: `+NEW` header button and add-row share the same `win_new` rect key (collision); no
  speed bar / reorder arrows / right-edge fade.
- Registry/Pokedex: SORT dropdown + orbit-count column missing.
- Economy: juicery/bakery/mission demand floors "inert at generation"; `any_cargo_produced`
  cargo-shift rarely fires (no faithful foundry tick).
- Top-bar: missing shine gradient, corp/credits hover-brighten, corp-name dynamic shrink-to-fit.
- Mission tracker: shows ALL objectives w/ drawn checkboxes vs original's first-uncompleted "• "
  bullet only; wrong fonts (11/10px vs 8/8px) and bluish vs soft-yellow objective color.
- Cargo-token coloring isn't bold (original always bolds colored tokens); planet-name styling absent.
- Planet sphere shading is a concentric bake vs the original eccentric two-offset-circle gradient.
- `_finish_intro` starts gameplay at `sc=W/12000` on the home star vs original MAX_SC tracking the
  player train.

## MINOR (representative; full list in agent findings)

- Star corona 2-glow approx vs 4-stop gradient; photon ring too bright/thick.
- Oil cargo beam `#1a1a1a` vs `#0a0a0a`; oil rainbow-sprinkle missing; beam glow uses fill color not
  the per-cargo `glow` value.
- Watermark: "SPACE TRAIN" 17px vs equal-15px; ringed-planet glyph behind wordmark missing.
- Speed arrow triangle proportions (hw4/hh5 vs hw3/hh6); gear button has no border stroke.
- Chat log persistent bg panel (original shows bg only on hover); timestamp "SD" vs "S.D."; 11px vs
  8px bold-Orbitron-with-glow.
- Add-train pseudo-row hover is green (original blue).
- Dev-bar cells plain rects vs skewed gradient chevrons.
- Version string hardcoded "v0.4.5" (game is v0.4.6).
- Corp-name word pools, "optimised" vs "optimized", various ±2px offsets and ~rgba(±5) color nits.
- RIVAL-FOUNDED event popup has no port dispatch (falls through to generic).

---

## Verified FAITHFUL (no action — so the report is balanced)

Camera transform/clamp/parallax + MIN_SC/MAX_SC/zoom factors; revenue formula (demM/phM/shM/distM/
unitMult); galaxy train-consist sizing core (`_GAL_SCALE`, `_GAL_REF_ASPECT`, engine tiers,
area-consistency, bottom-align, x-flip, draw order, empty-sprite swap); cargo-beam funnel math; biome
palettes (`PTYPES`) and star palettes exact; black-hole accretion disk geometry + purple lensing;
cloud generation/projection/tints/drift/back-cull; rings/moons/gold-diamond patches; station track
ring + relic-green/AI-orange/player-blue palette; parallax star LOD; popup shells' dimensions/borders/
tab geometry (Train Builder 620×444, Planet Detail 470×416, window 648×476, builder engine 6-row
stats, leaderboard online client, tech-tree shell, controls 4-col, event popups gold/diamond/upgrade/
ceohire/ancient); fonts load+map correctly with REAL bold (FontVariation wght700); Phags-pa ancient
broadcast; maintenance/breakdown sim (decay/repair/breakdown). Godot's native device-res text makes
the original's HD-overlay DPR machinery unnecessary (no sharpness loss).

---

## Recommended priority order

1. **Make the gameplay loop real (G1-G4):** call `track_visit` from the Transit arrival site (rewards
   + car/upgrade unlocks + mission arming); add a per-frame mission-trigger evaluator; add
   `segmentBlockedByStar` + engine-range gating to transit; add SPACE pause + autosave.
2. **Finish the headline popups (U1-U4):** Missions card layout, Finances Loans+VS-Rival tabs, Corp
   dashboard bottom section + CEO pills, Train Builder scrollable grid + trainyard cost + per-car
   removal.
3. **Fix the front-end screens (U5, U7):** rebuild corp-setup + AI-select to the panelled spec with
   correct titles/cards/sprites; faithful intro camera + narration styling.
4. **Restore the missing visuals (V1-V4):** Dyson sphere, nebula layers, per-biome surface effects,
   car VFX.
5. **Typography pass (T1-T3):** add an italic Exo2 variant; build auto-bold-CAPS; route mission +
   tutorial text through a bold-aware, planet-name-aware tokenizer; restore the NEW-MISSION details
   paragraph.
6. Moderate cluster (train-status labels, info-bar CANCEL ROUTE, selection rings, fog radii,
   draw_car_strip scale/fog, credit-float red/arrow, Options music transport).
