# Full faithfulness sweep — every surface vs build_game.py (2026-06-20)

Produced by reading the REAL draw functions line-by-line (6 parallel audit agents), NOT eyeballing.
Verdict key: ✅ faithful · 🟡 approximated (geometry close, details/data wrong) · 🟠 fabricated (invented data/elements) · ⛔ missing · 🔒 blocked on missing sim data.

## CRITICAL input-architecture fix (2026-06-20) — ✅
**Root cause of "nothing is clickable":** Screens and PopupManager were Controls parented to a CanvasLayer, which gives them NO viewport-sized rect, so `_gui_input` NEVER fired — the entire title screen and all popups were dead to the mouse. (Chrome already used global `_input`, so the in-game HUD worked.)
- ☑ Converted **Screens** and **PopupManager** to global `_input` (rect-independent, hit-test our own `_rects`). Added `GameState.popup_active`; Chrome + GalaxyView skip input while a modal popup is open. **Verified by injecting a synthetic click on PLAY → `gs: title→intro`.** The whole front-end flow + all popups are now clickable.

## Title screen (2026-06-20) — ✅ FAITHFUL REBUILD
Was: 2 invented static vignettes, flat 56px dark-stroked wordmark, flat unsized buttons, dead.
- ☑ Rebuilt to `drawTitleScreen`: **scrolling planet parade** (recycled biome planets + rings + orbiting moons), **2-line 75px wordmark** with doubled cyan glow + no stroke, auto-fit subtitle, **correctly-sized pulsing rounded buttons** (PLAY 190×46 cyan, LOAD/LEADERBOARD 2/3-size amber/purple), rail + sleepers (28px) + scrolling train, version, gear. `_round_rect` now draws REAL rounded corners (fixes the square-corner bug across corp-setup/AI-select/intro too). Screenshot-verified.

## Cross-cutting defects (affect many surfaces)
- **`_round_rect` / `_btn` draw SQUARE corners** (ignore the radius arg) — every "rounded" panel/button in the port is wrong. Original uses 4–8px `roundRect` everywhere.
- **No glow/shadow anywhere** — the original leans on `ctx.shadowBlur` for titles/buttons/sprites; the port has none.
- **Reduced Transit sim** stores none of: `maintenance`, `distSinceMaint`, `totalDist`, `totalRevenue/totalCosts`, `orbitCounts/_topOrbited`, `_segmentCount`, `orbitTier`, `_engineFailureSd/_engineBornSd`. This 🔒-blocks: train-detail maintenance/engine-age/financial bars, trains-list Dist/Most-orbited/Segments/orbit-tier, builder RANGE/MAINT/REPAIR, planet-detail STATS tab.

## Popups
| Surface | Verdict | Headline gap |
|---|---|---|
| Leaderboard `[L]` + title full-screen | ✅ **FIXED this session** | was 🟠 (fabricated local sort); now the real online Cloudflare client |
| Finances `[F]` | ✅ **FIXED this session (FINANCIALS tab)** | was 🟠 (invented rows + VS-RIVAL bars); now real ledger table. LOANS + VS-RIVAL tabs deferred (own subsystems) |
| Planet Detail `[click]` | 🟡 + 🟠 | STATS tab fabricated (`economicHealth`/`passengerDeliveries` invented); upgrades sidebar drops the STATION/Large/Terminal card + all gate-locking; supply/demand gate wrong (shows hidden cargo); no +N MORE panel, resource badges, on-planet structures, chevron dev-bar |
| Tech Tree `[I]` | ✅ **FIXED** | full faithful `drawTechTreePopup` — ported `_TT_*` data (names/hints/supply/demand/positions/edges), `_tt_locked` unlock logic, ENGINES/CARS header, L-shaped prerequisite edges, sprite nodes (dimmed when locked), `???` mystery row, hover tooltip. `[I]` is no longer dead. |
| Pokédex `[P]` | ✅ **FIXED** | rebuilt to 460×390 — PLANETS/STARS tabs, rank + mini biome disc + name·[HOME] + TYPE·size·star, `???` rows, zebra/hover, VISITED-ONLY toggle, scroll (orbit-count column omitted — sim doesn't track it) |
| Star Registry `[Y]` | ✅ **FIXED** | shared window, **amber palette**, rendered star discs (core color + glow), COLORNAME·N-planets, `???` rows, discovered-first sort |
| Star Detail | 🟡 | missing CONSTRUCT DYSON button, rename pencil, left-bleed star render, Hazmat/HOME lines; wrong dims (440×320 vs 520×390) |
| Car Detail | ⛔ | not implemented at all (no draw fn, no dispatch). Needs per-car stats arrays in sim |
| Train Detail | ⛔/🔒 | renders ~1/4; missing AT-A-GLANCE/STATS tabs, CARGO row, MAINTENANCE/ENGINE-AGE/FINANCIAL bars (🔒), CURRENT ROUTE; invented STATUS row |
| Train Builder | 🟡 + 🟠 | CARS cap hardcoded 10 (should be `ENGINE_MAX_CARS`); car grid capped 2 rows no-scroll, only unlocked shown; **cost formula fabricated** (no trainyard/edit-delta); engine panel 2/6 stats; title "AT planet" suffix invented |
| Trains window `[T]` | 🟡 | wrong size (580×430 vs 648×476); missing hover, Dist/Most-orbited/Segments (🔒), orbit-tier; route is text not `drawRouteStrip` |
| Routes window | ✅ **rebuilt earlier** | planet-blocks + per-stop supply/demand (RULES/N≥6 scroll omitted) |
| Stations window | 🟡 + 🟠 | no filter bar; 3 rows not 5; flat disc not station+structures; **invented rival orange recolor** |
| Options | ✅ **FIXED** (minus music transport) | added the **Fullscreen / Autosave / Mission-Objectives-Tracker** toggle rows (functional — fullscreen via DisplayServer, autosave/tracker flags on GameState; tracker gates the HUD overlay). SFX/MUSIC panes kept. (full MUSIC transport/waveform/title still simplified; QUIT-TO-TITLE kept for usability) |
| Controls | ✅ **FIXED** | rebuilt to 620×300 with the 4 original columns (REPEATING ROUTES / BUY-EDIT TRAINS / UPGRADE PLANETS / CAMERA & SPEED), exact bullet text, underline accents, word-wrap |
| Save Manager | 🟠 | reduced to single-file save/load; original is a multi-slot manager (autosave slot, export/import/delete/save-over) |
| Missions `[M]` | ✅ **FIXED** (minus art/progress-bars) | 480×360 green glow title, "N active · M completed" status line, active-first cards w/ ○/✓ checkbox glyphs + reward pill, completed section. (52×52 art + per-objective progress bars omitted — bars need sim counters the reduced sim lacks) |
| Quit Confirm | ✅ **FIXED** | 390×110, "QUIT TO MAIN MENU?" + "Save first…" subtitle, 3 buttons (YES,QUIT / SAVE GAME / NO,STAY) with SAVE wired. (paused banner minor) |
| Pre-Departure Checklist | ⛔ | entire conditional-departure rules feature unported |
| **Event popups (×12)** | ◐ 3/12 done | ✅ **engine-unlock + car-unlock** rebuilt as faithful sprite-hero popups (320×360 green, glowing name, big sprite, OKAY); ✅ **mission-reward** popup wired to `Missions.mission_completed` (green, reward pill). REMAINING (need new sim triggers or large bespoke layouts): gold/diamond discovery, upgrade-unlock, new-mission-bespoke (still generic box w/ `{SOURCE}` tokens), first-delivery, rival-founded, ancient-message (Phags-pa), corp dashboard, ceo-hire |

## Front-end screens
| Surface | Verdict | Headline gap |
|---|---|---|
| Title | 🟡 + 🟠 | flat 56px wordmark (vs 75px gradient + double-glow); **2 static vignettes invented** (original = animated 10-template planet parade); buttons no pulse/glow; **dead gear button** |
| Intro cutscene | 🟠 | **fabricated** — a single sinusoidal wobble instead of the 11-shot cinematic camera (Orijen zoom-out, planet portraits, Dyson/cluster/nebula/black-hole shots); invented dark band |
| Corp Setup | 🟡 + 🟠 | wrong title; CEO data model invented (dual %-perks vs salary/ability/starting-credits pills); invented "↻ NEW NAME" button |
| AI Select | 🟡 + 🟠 | no amber panel/gradient; **invented corp banner**; wrong sprite map; uniform card styling vs per-difficulty palettes |

## World render (galaxy)
| Surface | Verdict | Headline gap |
|---|---|---|
| Parallax stars | ✅ | faithful (800 stars, exact ranges, batched) |
| Nebula background | 🟠 | **fabricated** — 7 static blobs vs the quadrant-blended baked tile sheet |
| Named world nebulas + labels | ⛔ | absent entirely |
| Layer z-order | 🟡 | ring-front/front-moon drawn before trains (inverted vs original's post-train pass) |
| Star corona/disc | 🟡 | single-stop glow vs 4-stop palette-mixed corona + eccentric disc gradient |
| Black hole | 🟡 | close; lensing flattened to single-alpha glow |
| Clouds | 🟡 | no atmosphere alpha-mask (`r→1.40r` taper); generic puff profile |
| Station (large/terminal) | 🟡 (AI tint ✅) | ✅ **AI rival stations now tinted ORANGE** (3-way palette: relic green / AI orange / player blue, build_game.py 28810). Still: dock-ring radius approximated (`r*1.8/2.3`), Large/Terminal tower tiers not built |
| Foundry/agri/factory planet buildings | ⛔ | none rendered in galaxy |
| Selection ring | 🟠 | invented generic yellow ring (original uses orbit-recolor) |
| Hazmat ring | 🟡 | solid vs dashed |
| Dyson sphere | 🔒 | blocked — sim never sets `hasDysonSphere` |
| Fog | 🟡 | faithful mechanism; missing sensor-1.5× + distinct reveal gradients |
| Planet sphere shading | 🟡 | reconstructed bake; gold/diamond reveal-gating dropped |

## Interactivity sweep (hover + clickability) — 2026-06-20
**Root cause found:** the port had ZERO hover tracking — the only mouse-motion handler was slider drag. No button had a hover state.
**Foundation added:** live cursor tracking + `_hov()`/`_hov_k()` in all 3 immediate-mode UIs (PopupManager, Chrome, Screens) + pointing-hand cursor over clickables.
**Hover states wired:** `_btn`/`_esc_hint`/`_btn_pill` (covers most buttons + every ESC); hint-bar items; panel tabs + expand arrow; train/station panel rows; "+ Add new train"; gear; speed arrows; unified-window tabs; planet-detail tabs; leaderboard headers + page arrows (popup + full screen); finances dropdown + options; train-builder car/engine tiles; info-bar planet-strip discs; star-popup planet discs; title buttons; CEO cards; difficulty cards; leaderboard-screen BACK; window train rows.
**Dead/missing clicks WIRED:** mission tracker → Missions; "+ Add new train" → builder; info-bar planet strip → select planet; star-popup planet discs → planet detail; **galaxy SHIFT+CLICK → multi-stop route building** (was entirely missing).
**Interactivity gaps still open (smaller / feature-blocked):**
- Title **gear** dead (needs Options-on-title — PopupManager gates options to galaxy).
- Intro cutscene: no QUIT / mute / click-to-advance.
- Corp-name **rename** (click-to-edit) — only the regenerate button exists.
- ROUTE TRAIN HERE uses direct append vs the original `routeHerePending` panel-handoff; top-bar **corp name** → corp popup (corp popup unported); train-click toggle-to-planet + panel focus.
- Remaining hover: train-detail EDIT, window station-rows / route-panes, regen button; finances scroll has no wheel handler.

## Save / load (2026-06-20) — ✅ FAITHFUL
The original interchange format is `.stt` (plain JSON storing the FULL galaxy + trains + ledgers + unlock flags). The port previously saved a tiny seed-based JSON, incompatible.
- ☑ **`SaveLoad.load_stt()` / `_load_stt_data()`** — loads original `.stt` files directly: rebuilds Galaxy.stars/planets (biome `type` reconstructed from `{id}` via `Tuning.ptype`, supply/demand rates recomputed), black holes, home/origen ids; restores credits/stardate/corpName/speed/ledgers/corp-value-history/unlock-flags/discovery sets/AI corp/camera; best-effort trains (engine = `cars[0]`, route filtered to existing stops). `load_game()` auto-detects the `.stt` (galaxy) format.
- ☑ **`save_game()` rewritten to the `.stt` format** — writes the full galaxy (type→`{id}`), discovery arrays, trains (cars = `[engine,…]`), ledgers, unlock flags, camera. Round-trips through the same loader.
- ☑ **VERIFIED**: loaded 2 real project `.stt` files (`space_tycoon_for_jack_with_love`, `Sterling_s_Helix_Freight`) — both RUN + RENDER (real trains/names/credits/corp, sim ticks, camera restored), and save→reload is byte-identical in counts/credits/SD/corp. Dev flags: `--load-stt=<abs.stt>`, `--save-roundtrip=<path>`.
- Remaining: a faithful multi-slot **Save Manager** UI (list/import/export/delete `.stt` slots) — currently single-file `user://savegame.stt`.

## Already fixed this session
✅ Leaderboard (real online client) · ✅ Finances FINANCIALS tab (real ledger) · ✅ Routes window planet-blocks layout · ✅ finance ledger sim infra · ✅ **interactivity foundation (hover + dead-click wiring + shift-click routes)** · ✅ **save/load original `.stt` format (load + save, verified)** · ✅ **Pokédex + Star Registry faithful rebuild** · ✅ **critical input-architecture fix (all popups + title now clickable)** · ✅ **faithful title rebuild** · ✅ **tech tree `[I]`** · ✅ **engine/car-unlock + mission-reward event popups** · ✅ **galaxy-draw perf pass (scaled arcs, tiny-planet dots)** · ✅ **Controls + Quit-Confirm + Missions popups** · ✅ **Options toggles (fullscreen/autosave/tracker)** · ✅ **AI orange rival stations**.
