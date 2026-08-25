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

**SIM build-out — refining / production (unblocks most of G2):**
- ✅ **Foundry/refining system** ([Economy.gd](autoload/Economy.gd)). Ported the full recipe model
  (`RECIPES`): iron_foundry (1 molten_ore + 1 water → 1 iron + 0.5 hazmat, ~40 s), blast_furnace
  (iron + chemical → steel, 2×), glassworks (sand + chemical → glass), factory (iron + oil → machinery),
  bakery (grain → cargo), juicery (fruit → cargo). `foundry_intake()` (called from Transit on a player
  unload) stockpiles input cargo on the planet (cap 10); `update_foundries(dtG)` (ticked in
  GameState._physics_process) advances each player-built processor's timer, consumes inputs, emits the
  output into the planet's supply (loadable by trains), adds byproducts, increments iron/steelDelivered,
  sets `any_cargo_produced`, and **unlocks the producing car** (Iron/Steel/Glass/Machinery/Hazmat) on
  first production. Headless-verified: ore+water → 1 iron + 0.5 hazmat, Iron Car unlocked, anyProduced=true.
- ✅ This unblocks the keystone mission chain: **build_foundry → produce_iron → upgrade_station**.
  `produce_iron` objectives now complete via `Missions.on_foundry_intake` (deliver ore+water) +
  `on_production` (iron smelted); completing it unlocks the Large Station + chains `upgrade_station`.
  The cargo-refinement tree (iron→steel→machinery, sand+chemical→glass) is now live.
- ✅ **Generic delivery-objective counter** (`Missions._DELIVER_OBJ` + `on_delivery`): handles the
  ~11 "deliver N <cargo> to <origen|station|target>" objectives across the mission set (4 iron for
  upgrade, 20 steel/battery/oil for design_better_train, livestock/medical/sand/chemical/colonists for
  the relief missions, 50 passengers to Orijen). Counts accumulate per active mission and complete the
  objective at the threshold. **upgrade_station** now completes (4 iron to a station + large-station
  upgrade), and the "to target" objectives are ready for when their missions' triggers land.
- ✅ **buy_second_train** wired (queued when build_foundry completes; UI-step objectives via
  `on_window_opened` (trains/builder) + `on_train_built` (2+ iron cars) + `deliver_iron_orijen` via the
  delivery counter). **Verified headless**: the full chain build_foundry → produce_iron → upgrade_station
  completes, with buy_second_train surfaced (`--test-missions`).
- ✅ **Mission-role missions** (famine / outbreak / lost_colony). `Galaxy._assign_mission_roles()` flags a
  famine + outbreak target planet at gen; `queue_intro(id, target)` threads a `targetPlanetId` through to
  the active mission; `Missions._on_planet_visited` fires the visit-triggers (famine/outbreak on visiting
  the flagged planet, lost_colony on a relic → nearest other relic) and completes visit-objectives
  (`visit_relic_target`) when the target is reached. **Verified headless** (`--test-roles`): visiting the
  famine planet + delivering 10 livestock completes famine; outbreak + 4 medical completes outbreak.
  Completable mission set is now **10**: build_foundry, produce_iron, upgrade_station, buy_second_train,
  create_route, galaxy_census, research_royal_car, famine, outbreak, lost_colony.
- ✅ **More missions** (no gen role needed): **stellar_cartography** (visit a planet in 5 distinct star
  systems — distinct-`starId` count), **galactic_distance** (a single delivery whose source→dest trip
  > 15,000 SU — checked at the Transit unload site), and **seeking_home** (visit a rocky planet → ferry
  1 passenger to a far rocky world via `_far_rocky` + the delivery counter). **Verified headless**
  (`--test-roles`): famine, outbreak, stellar_cartography, galactic_distance, seeking_home all complete.
  **Completable mission set is now 13** of ~25.
- ✅ **Hazmat incineration loop + dispose_hazmat.** The port's iron-foundry already emits a hazmat
  byproduct + unlocks `car_hazmat`; added the disposal side: hazmat (waste, no demand) now incinerates
  when a hazmat car reaches ANY non-source planet (`Transit._start_cargo_ops` bypasses the demand gate
  for hazmat), incrementing `GameState.hazmat_incinerated`; `dispose_hazmat` is queued when an iron
  foundry is built (car-gated on `car_hazmat`) and completes at 2 units. The corp-dashboard "Hazmat
  Incinerated" stat now reads the real counter (was hardcoded 0). Also wired **sandstorm_relief**
  (desert visit → clear 10 sand by delivering it anywhere). **Verified headless** (`--test-roles`):
  dispose_hazmat completes. **Completable mission set is now 15** of ~25.
- ✅ **G2 COMPLETE — the entire mission graph now plays through.** Wired the final 8:
  **design_better_train** (steel produced → deliver 20 steel/battery/oil to Orijen → Class J + Class R),
  **bh_research** (visit the black-hole research planet → 5 chemical → chains the research arc),
  **another_dimension** (research-wait timer, `Missions._process`), **more_scientists** (3 passengers to
  the outpost), **ancient_schematics** (visit ancient → ferry cargo to Orijen), **mad_scientist** (large
  station → ferry scientist to Orijen → Class J), **colony_train** (visit source → ferry colonists to
  the dest, which becomes a 541-pop colony), and **spread_the_seed** (visit a flowers-origin world →
  unlock the Flowers Car + seed 10 flower-capable planets). New machinery: `Galaxy._assign_mission_roles`
  flags colony source/dest + black-hole-research + flowers-origin planets (the last with sustained flower
  `supplyRate`); an `_ESCORT` table collapses pickup→deliver flows to a delivery count that completes the
  whole mission; a flower distinct-planet tracker; and the bh_research → another_dimension →
  more_scientists chain. **Verified headless** (`--test-missions3`): all 8 complete. **Completable
  mission set is now 23 of ~26** — every active mission in `MISSION_DEFS` (the only unwired ones are
  dormant/removed like `visit_planet`). Escort missions collapse the multi-step pickup→deliver to a
  delivery count (no exact-source check) — a documented simplification.


**Cleanup — small remaining items:**
- ✅ **T3 (mission text styling)** — added a left-aligned token renderer (`_draw_tok_left`) and routed the
  **NEW-MISSION popup** and the **missions-list `[M]` objectives** through it: `[Cargo]` refs now render
  in their cargo colour (e.g. Molten Ore orange, Water blue), and the NEW-MISSION popup's **italic
  details paragraph is restored** (was omitted entirely) with content-sized height. Screenshot-verified.
  (Remaining: the in-HUD mission tracker in Chrome still renders plain — it has no token renderer there.)
- ✅ **`draw_car_strip` scale + fog** — added `opts` to the strip renderer: `scale` (0.9 panel rows /
  0.8 train-detail / 0.75 info-bar) and `fog_empty` (milky-pale dim on mid empty cars). Wired into the
  panel rows, trains-list rows, train-detail, and the selected-train info-bar strip (was all 100%, no fog).

**MODERATE cluster — step 6:**
- ✅ **Train-status labels** — a single shared `Transit.train_status()` now returns the faithful
  `getTrainStatus` labels (IN ORBIT / PARKED, IN ORBIT / ON ROUTE, EN ROUTE → <dest>, LOADING,
  UNLOADING) with matching colors; Chrome + PopupManager both call it (was just IN ORBIT / IN TRANSIT).
- ✅ **Selection ring** — added the grey orbit ring on a selected planet (port has one orbit tier, not
  the JS LOW/MED/HIGH set). Per-kind colors (blue planet / gold star / orange train) + glow were already
  correct (audit was stale there).
- ✅ **Fog reveal radii** — applied the missing JS multipliers: star-system reveals ×2.2, breadcrumb
  ×1.2, orbited-planet ×1.1 (3300). Reveal holes are now the right size (were ~½).
- (Verified already-done, audit was stale): **credit floats** (9px Exo 2 + up/down arrow + red-for-loss),
  the **CANCEL ROUTE button** in the train info bar (drawn + wired to un-route), and the **train info bar**
  (color square + real name + status + consist strip).

**Visuals — step 4:**
- ✅ **V1** — **Dyson sphere** built (was flagged "blocked", but it's actually a player-built
  megastructure, not a random event). `GalaxyContent._draw_dyson()` renders the faithful
  `drawDysonSphere`: a Fibonacci-distributed shell of **220 lit hexagonal panels** rotating slowly
  around the Y axis, painter-sorted, with per-panel diffuse lighting + specular highlight + rim stroke;
  back panels behind the star disc are culled (approximating the JS even-odd clip). Wired the
  player-build flow: a **CONSTRUCT DYSON · 1,000,000 cr** button in the star-detail popup (greyed until
  affordable) → deducts credits, sets `star.hasDysonSphere`, plays the purchase SFX; shows
  "★ DYSON SPHERE ACTIVE" once built. Persists through save/load (the star dict round-trips).
  Screenshot-verified — Gigi Prime wears the full hex shell.
- ◐ **V2** — **world-space named nebulas** built. `Galaxy._gen_nebulas()` generates 16 colored nebula
  regions around Orijen (placement + declumping + distinct names from a 66-name pool + a 5-band HSL
  palette with distinct primary/secondary colors, all from the seeded RNG so saves stay deterministic).
  `GalaxyContent._draw_nebulas()` renders each as a seed-generated cluster of soft tinted radial blobs
  (secondary halo + secondary cloud + main cloud + bright knots + dark dust lanes) at 0.55 translucency,
  cam-scaled, rotated to 90°, with an uppercase "X NEBULA" label that fades in above ~150px on-screen.
  Screenshot-verified (colored named cloud regions across the galaxy, was a flat dark backdrop). Loaded
  saves get them too (load regenerates from seed). REMAINING in V2: the screen-space tiling nebula sheet
  with home-quadrant blend (still the 7-blob stand-in in ScreenBackground).
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

**Intro cinematic camera — last large piece:**
- ✅ **U7 (camera)** — rebuilt `_build_intro_shots` to the faithful `_buildIntroShots` shape: a
  **22-second Orijen MAX_SC → deep zoom-out opener** (was a 6 s tight→wide), then a **shuffled pool**
  of shots — planet portraits (partial-on-screen → opposite-edge pan in one of 8 random directions),
  a home-system zoom-out, a **Dyson/distant star pan** (prefers a Dyson star), a **nebula zoom-out**
  (largest-nearest, now that nebulas exist), and a **black-hole zoom-in**. Pool order is Fisher-Yates
  shuffled each playthrough; total runtime comfortably outlasts the narration. Screenshot-verified
  (Orijen framed at MAX_SC with the bold "STARDATE 829." narration + QUIT/SKIP). This completes U7
  (narration typography was done earlier).

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

## ✅ MODERATE cluster — fix progress (2026-06-21)
- ✅ **Train-status labels** unified into one faithful `Transit.train_status()` (build_game.py
  getTrainStatus): UNLOADING / LOADING / **IN ORBIT / PARKED** (no route) / **IN ORBIT / ON ROUTE** /
  **EN ROUTE → DEST** — with the original colors. Chrome panel, info bar, and all popups now share it.
  (Queueing/descending/waiting states still absent — those phases aren't in the port's transit.)
- ✅ **Selection-ring color** now matches the selection kind: **blue** planet (#4af) / **gold** star
  (#ffd700) / **orange** train (#fa8), at radius+5 with a soft glow (was one yellow `*1.35+7` ring for
  everything). (Grey orbit-tier rings still omitted — need per-planet orbit-radius data.)
- ✅ **Credit floats** rebuilt to the faithful style: **9px Exo 2**, an up/down **triangle arrow**, and
  **red for losses / green for gains** (was 13px fallback-font, green-only, no arrow). (Screen-space
  purchase/loan floats still only fire on delivery + visit reward — the `spawnCreditFloatScreen` call
  sites aren't wired yet.)

- ✅ **Selected-train info bar** now shows the **color square + real train name** (was "TRAIN 0") and a
  red **CANCEL ROUTE** button (with hover) that un-routes the train — the original's key interaction
  (build_game.py:30310) was entirely missing. (The route strip / speed bar / coords / Seg% line are
  still simplified.)

## MODERATE (remaining)

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
