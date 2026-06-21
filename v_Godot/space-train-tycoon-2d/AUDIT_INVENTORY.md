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
- ✅ **FIXED: rounded corners** — added `_fill_round`/`_stroke_round` to PopupManager + Chrome; popup `_base` (8px) and every `_btn`/`_btn_pill` now draw real rounded corners (Screens already done). ON/OFF toggle pills stay square (faithful — original uses `fillRect`).
- ✅ **FIXED: window dimensions** — the unified TRAINS/ROUTES/STATIONS window now uses ONE size (648×476, the original's WIN_PW/WIN_PH) instead of three different per-tab sizes, so switching tabs no longer resizes.
- ✅ **FIXED: double-click** — galaxy double-click a planet → planet detail, a train → train details; panel double-click a train/station row → its detail popup (build_game.py panelDblClick). Train-detail falls back to the selected train.
- **No glow/shadow anywhere** — the original leans on `ctx.shadowBlur` for titles/buttons/sprites; the port has none (title wordmark + unlock/tech glow are simulated; general button glow not yet).
- ✅ **MAINTENANCE/BREAKDOWN MODEL ADDED** (2026-06-20, ports build_game.py:1834-1857/15335/15677): Transit now tracks `maintenance` (decays per SU in transit by `ENGINE_MAINT_DECAY`), `distSinceMaint`, `totalDist`, `totalRevenue`/`totalCosts`, `_engineBornSd`/`_engineFailureSd`/`_engineFailed`. Repairs on station arrival (cost = damage × cars × `REPAIR_COST_PER_MAINT` × engine mult × repair-drones discount → ledger entry), breakdown SFX on crossing 0. **Unblocked: train-detail MAINTENANCE + ENGINE-AGE + FINANCIAL-PERFORMANCE bars ✅, builder MAINT/REPAIR stats ✅.** Still missing from sim: `orbitCounts/_topOrbited`, `_segmentCount`, `orbitTier`, `ENGINE_MAX_RANGE` → trains-list Dist/Most-orbited/Segments/orbit-tier, builder RANGE, planet-detail STATS tab.

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
| Train Detail | ✅ **FIXED** (bars) | now renders MAINTENANCE bar (color-graded + "N SU since service"), ENGINE-AGE bar ("N.N SD until breakdown"/"engine failed"), FINANCIAL PERFORMANCE (REVENUE/COSTS/PROFIT) from the new sim model. (STATS tab + CARGO row still simplified) |
| Train Builder | 🟡 + 🟠 | CARS cap hardcoded 10 (should be `ENGINE_MAX_CARS`); car grid capped 2 rows no-scroll, only unlocked shown; **cost formula fabricated** (no trainyard/edit-delta); engine panel 2/6 stats; title "AT planet" suffix invented |
| Trains window `[T]` | 🟡 | wrong size (580×430 vs 648×476); missing hover, Dist/Most-orbited/Segments (🔒), orbit-tier; route is text not `drawRouteStrip` |
| Routes window | ✅ **rebuilt earlier** | planet-blocks + per-stop supply/demand (RULES/N≥6 scroll omitted) |
| Stations window | 🟡 (5 rows ✅) | ✅ now shows **up to 5 supply / 5 demand** car-icon rows (PANE 136). Still: no cargo filter bar; planet shown as flat disc not station+surface-structures |
| Options | ✅ **FIXED** (minus music transport) | added the **Fullscreen / Autosave / Mission-Objectives-Tracker** toggle rows (functional — fullscreen via DisplayServer, autosave/tracker flags on GameState; tracker gates the HUD overlay). SFX/MUSIC panes kept. (full MUSIC transport/waveform/title still simplified; QUIT-TO-TITLE kept for usability) |
| Controls | ✅ **FIXED** | rebuilt to 620×300 with the 4 original columns (REPEATING ROUTES / BUY-EDIT TRAINS / UPGRADE PLANETS / CAMERA & SPEED), exact bullet text, underline accents, word-wrap |
| Save Manager | ✅ **FIXED** (slots) | now a multi-slot manager: lists every `.stt` in `user://saves/` with **LOAD / DELETE** per slot + a **NEW SAVE** button (slot named `<corp>_SD<n>`). (export/import .stt + save-over still simplified) |
| Missions `[M]` | ✅ **FIXED** (minus art/progress-bars) | 480×360 green glow title, "N active · M completed" status line, active-first cards w/ ○/✓ checkbox glyphs + reward pill, completed section. (52×52 art + per-objective progress bars omitted — bars need sim counters the reduced sim lacks) |
| Quit Confirm | ✅ **FIXED** | 390×110, "QUIT TO MAIN MENU?" + "Save first…" subtitle, 3 buttons (YES,QUIT / SAVE GAME / NO,STAY) with SAVE wired. (paused banner minor) |
| Pre-Departure Checklist | ⛔ | entire conditional-departure rules feature unported |
| **Event popups (×12)** | ◐ 9/12 done | ✅ **engine-unlock + car-unlock** rebuilt as faithful sprite-hero popups (320×360 green, glowing name, big sprite, OKAY); ✅ **mission-reward** popup wired to `Missions.mission_completed` (green, reward pill). ✅ **new-mission** now bespoke (green, glowing name, OBJECTIVES w/ ○ checkboxes + real text, REWARD pill, ACCEPT — no more `{SOURCE}` tokens). ✅ **corp dashboard** now built (logo + name + CORPORATE FINANCES 4×2 grid from the real ledger + CEO pane; opens via the top-bar corp-name click). ✅ **first-delivery** wired (`GameState.first_delivery` at Transit delivery site; blue popup, loaded-car-over-rail + flavour line; `delivered_planets` pre-populated on load). ✅ **gold-discovery + diamond-discovery** wired (`Discovery.gold_discovered`/`diamond_discovered` fired in `track_visit` when player visits a planet with `hasGold`/`hasDiamond` & not yet revealed; sets `goldRevealed`/`diamondRevealed`; 320×340 amber EUREKA! / blue FOR REAL? popups w/ big car sprite — match build_game.py:16469/16501). ✅ **event queue** — `_present_event`/`_dismiss_event` show queued events one-at-a-time (faithful to JS `pendingGold/DiamondDiscoveries`). ✅ **upgrade-unlock** wired (`GameState.upgrade_unlocked` emitted in `Missions._apply_unlocks` when an upgrade newly unlocks; amber popup w/ glowing name, station-rings OR planet+foundry visual, COST pill, BUILDABLE ON, ENABLES + formula with cargo-colored `[token]` text + processing time — matches build_game.py `_UPGRADE_UNLOCK_INFO`/`drawUpgradeUnlockPopup` 17037/17097; all 5 keys: large_station/terminal/iron_foundry/bakery/glassworks). ✅ **ceo-hire** wired (full CEO sim in GameState: `ceo`/`ceo_candidates`/`ceo_last_hire_sd`, `_gen_ceo`/`roll_ceo_candidates`/`hire_ceo`/`ceo_cooldown`; per-SD salary deduction + bench re-roll at the SD boundary; 700×370 3-column HIRE A CEO popup with portraits/salary-tier pills/green-blue perk pills/HIRE buttons + cooldown banner — opened by clicking the corp-dashboard CEO portrait; matches build_game.py `drawCeoHirePopup` 17882). REMAINING: rival-founded (no mid-game trigger — AI set up at start), ancient-message (Phags-pa) |

## Front-end screens
| Surface | Verdict | Headline gap |
|---|---|---|
| Title | 🟡 + 🟠 | flat 56px wordmark (vs 75px gradient + double-glow); **2 static vignettes invented** (original = animated 10-template planet parade); buttons no pulse/glow; **dead gear button** |
| Intro cutscene | ✅ **FIXED** (shot sequence) | replaced the sinusoidal wobble with a real **camera shot sequence** (`_build_intro_shots`): Orijen zoom-out opener → planet portrait → home-system → pan to a distant star → galaxy zoom-out, smoothstep-eased. Added **click-to-advance** (snap-finish then next paragraph). (Not the full 11 named shots / Dyson pan, but shot-based not wobble) |
| Corp Setup | 🟡 + 🟠 | wrong title; CEO data model invented (dual %-perks vs salary/ability/starting-credits pills); invented "↻ NEW NAME" button |
| AI Select | 🟡 + 🟠 | no amber panel/gradient; **invented corp banner**; wrong sprite map; uniform card styling vs per-difficulty palettes |

## World render (galaxy)
| Surface | Verdict | Headline gap |
|---|---|---|
| Parallax stars | ✅ | faithful (800 stars, exact ranges, batched) |
| Nebula background | 🟠 | **fabricated** — 7 static blobs vs the quadrant-blended baked tile sheet |
| Named world nebulas + labels | ⛔ | absent entirely |
| Layer z-order | 🟡 | ring-front/front-moon drawn before trains (inverted vs original's post-train pass) |
| Star corona/disc | ✅ **FIXED** (corona) | corona now layers a wide GLOW-coloured halo + tighter CORE-coloured inner corona (uses the palette's distinct `glow` hue), approximating the 4-stop falloff. (disc eccentric-gradient still approximated) |
| Black hole | ✅ **FIXED** (lensing) | lensing now two layered purple glows (bright violet core → dim halo) approximating the 4-stop radial, not a single flat-alpha blob |
| Clouds | ✅ **FIXED** (taper) | per-puff atmosphere taper (full inside `r`, fade to 0 by `r*1.40`) so clouds thin toward the limb instead of spilling into space. (generic puff profile still approximated) |
| Station (large/terminal) | 🟡 (AI tint ✅) | ✅ **AI rival stations now tinted ORANGE** (3-way palette: relic green / AI orange / player blue, build_game.py 28810). Still: dock-ring radius approximated (`r*1.8/2.3`), Large/Terminal tower tiers not built |
| Foundry/agri/factory planet buildings | ✅ **FIXED** | ported `drawFoundry/Granary/Farm/Orchard` → `_draw_upgrade_buildings` (called per planet from `_draw_planet`, gated `r>12`): foundry (per-kind indicator light: iron/blast/glass/bakery/juicery), red granary w/ conical hat, gabled barn w/ door, 6-tree orchard w/ fruit dots. Agri grouped w/ spread, industrial spaced apart. |
| Selection ring | 🟠 | invented generic yellow ring (original uses orbit-recolor) |
| Hazmat ring | ✅ **FIXED** | now a dashed ring (`_dashed_ring`, ~4px dashes / 9px gaps) matching `setLineDash([4,9])` |
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
✅ Leaderboard (real online client) · ✅ Finances FINANCIALS tab (real ledger) · ✅ Routes window planet-blocks layout · ✅ finance ledger sim infra · ✅ **interactivity foundation (hover + dead-click wiring + shift-click routes)** · ✅ **save/load original `.stt` format (load + save, verified)** · ✅ **Pokédex + Star Registry faithful rebuild** · ✅ **critical input-architecture fix (all popups + title now clickable)** · ✅ **faithful title rebuild** · ✅ **tech tree `[I]`** · ✅ **engine/car-unlock + mission-reward event popups** · ✅ **galaxy-draw perf pass (scaled arcs, tiny-planet dots)** · ✅ **Controls + Quit-Confirm + Missions popups** · ✅ **Options toggles (fullscreen/autosave/tracker)** · ✅ **AI orange rival stations** · ✅ **cross-cutting: rounded corners + unified window size + double-click** · ✅ **Stations-window 5-row supply/demand + dashed HazMat ring** · ✅ **star corona + black-hole lensing multi-stop glow** · ✅ **cloud atmosphere taper + multi-slot Save Manager** · ✅ **on-planet upgrade buildings (foundry/granary/farm/orchard)** · ✅ **intro cinematic shot-sequence + click-to-advance** · ✅ **new-mission bespoke popup (objectives + reward + ACCEPT)** · ✅ **corp dashboard popup (top-bar corp-name → ledger-backed finances grid + CEO pane)** · ✅ **SIM: maintenance/breakdown model → train-detail bars + builder MAINT/REPAIR** · ✅ **first-delivery discovery event + popup** · ✅ **gold/diamond deposit discovery events + popups + one-at-a-time event queue** · ✅ **upgrade-unlock event + popup (5 keys, cargo-colored token text, station/foundry visuals)** · ✅ **CEO sim + Hire-a-CEO 3-column window (roster/perks/salary/cooldown, per-SD salary tick, corp-dashboard portrait → hire)**.
