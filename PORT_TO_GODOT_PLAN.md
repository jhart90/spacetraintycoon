# Space Train Tycoon → Blender + Godot Port Plan

> **Audience:** a Claude Code session that will execute this port.
> **Source of truth today:** `build_game.py` (~36,100 lines of Python that emits a self-contained ~3.95 MB `index.html`). Canvas2D rendering, custom HD text overlay, sprite-based trains, *procedurally-drawn* planets/stars/black holes/clouds.
> **Read `code_map_build_game.md` first** — it is the section-by-section map of the source. This plan references its sections (§N).

---

## 0. Locked decisions (do not relitigate)

| Decision | Choice | Consequence |
|---|---|---|
| **Render target** | **Hybrid** — 3D world (galaxy, stars, planets, trains) in a Godot **3D** scene; all HUD/popups/panels as Godot **Control** nodes in a `CanvasLayer` on top. | Two coordinate systems coexist. Need a clean 2D↔3D boundary contract (§3). |
| **Logic language** | **GDScript** | Port JS → GDScript idioms. No C#/.NET build. |
| **Philosophy** | **Parity-first, then overhaul** | Phase 1–4 reproduce current behavior with *placeholder* art. Visual overhaul (Blender) lands in Phase 5+ on top of verified systems. |

**Guiding principle:** the JS is the spec. When in doubt about a number, a formula, or a rule, the answer is whatever `build_game.py` does. Port behavior first; make it pretty second.

---

## 1. Why this is mostly a *logic* port, not an art port

Be honest about where the work is. The current game's **visuals are cheap** — almost everything except trains is procedural canvas drawing. The **value is in the systems**: galaxy generation, transit/orbit mechanics, the AI corporations, the economy/refinery chain, missions, fog/discovery, the tutorial and intro cutscene. That's the ~36k lines.

So the port splits cleanly:

- **~85% effort:** translate game *logic* from JS → GDScript, structured into Godot autoloads + nodes. Art-agnostic. Verifiable against the old build.
- **~15% effort (but high visible payoff):** the Blender pipeline + Godot 3D presentation that *replaces* the procedural canvas drawing. This is the "overhaul" and it rides on top of stable systems.

Do not start Blender modeling before the systems run with placeholders. Placeholder = a colored `CSGSphere3D` for a planet, a capsule for a train car. Ugly is fine in Phase 1–4.

---

## 2. Target Godot project layout

```
space-train-tycoon/            # new repo (or /godot subdir of this one)
├── project.godot
├── autoload/                  # singletons (the "engine" — pure logic, no rendering)
│   ├── GameState.gd           # the god-object the JS calls implicit globals
│   ├── Galaxy.gd              # generation + world model (stars, planets, relics, black holes)
│   ├── Economy.gd             # credits, supply/demand, refinery/cargo chain, pricing
│   ├── Transit.gd             # routing, orbit phases, tangents, occupancy
│   ├── AICorp.gd              # rival corporation sim
│   ├── Missions.gd            # MISSION_DEFS + updateMissions state machine
│   ├── Discovery.gd           # fog / discovered / visited tiers + credit awards
│   ├── SaveLoad.gd            # serialize/deserialize GameState
│   ├── Audio.gd               # SFX + music buses
│   └── Tuning.gd              # ALL constants/data tables (ported wholesale, see §6)
├── world/                     # 3D scene
│   ├── GalaxyView.tscn/.gd    # the 3D galaxy root + camera rig
│   ├── Star.tscn/.gd
│   ├── Planet.tscn/.gd        # mesh + clouds + ring + station attachment points
│   ├── Train.tscn/.gd         # engine + cars, follows a Path/curve
│   ├── Station.tscn/.gd
│   └── BlackHole.tscn/.gd
├── ui/                        # 2D Control layer (CanvasLayer)
│   ├── HUD.tscn               # top bar, bottom info bar, right panel, mission tracker
│   ├── popups/                # TrainBuilder, PlanetDetail, Routes, Stations, Options...
│   ├── Tutorial.gd            # callout/bubble system
│   ├── ChatLog.gd
│   └── theme.tres             # fonts + colors (replaces the HD-text-overlay hack)
├── assets/
│   ├── models/                # .glb from Blender (Phase 5+)
│   ├── textures/
│   ├── sprites/               # interim: the existing PNGs, copied verbatim
│   ├── fonts/                 # the existing WOFF2/TTF
│   └── audio/                 # the existing wav/mp3 → ogg
└── tools/
    ├── extract_assets.py      # pulls PNGs/fonts/sounds out of the repo for Godot import
    └── parity/                # parity-harness scripts (see §9)
```

**Autoloads are the ported game.** Nodes in `world/` and `ui/` are *views* that read autoload state and render it. This is the single most important architectural change vs. the JS, where logic and `ctx.draw*` are interleaved in one giant loop. **Separate simulation from presentation from the start** — it's what makes the visual overhaul (Phase 5) a swap rather than a rewrite.

---

## 3. The hybrid 2D/3D boundary contract

Because UI is 2D Control and the world is 3D, you need a disciplined bridge:

- **World → screen:** `camera.unproject_position(world_pos)` to place a 2D label/bubble/selection ring over a 3D planet or train. This replaces every place the JS drew text at a moving world anchor (planet names, the tutorial bubbles, intro narration anchors, cargo beams' endpoints). Memory note: the JS had a whole `_smoothTextMode` / bitmap-blit hack to keep moving-anchor text from jittering (code map §1.2) — **that entire hack disappears**; Godot Control nodes positioned via `unproject_position` are crisp and stable for free.
- **Screen → world (picking):** `camera.project_ray_origin/normal` + a `PhysicsRayQuery` or per-object `Area3D` for click selection of stars/planets/trains. Replaces the JS hit-testing math.
- **Z-order / layering:** 3D world renders first; `CanvasLayer` (layer ≥ 1) holds all HUD so it always composites on top. The old "HD text overlay composited last" discipline (§1.1) is now just *Godot's natural layer order* — **delete that mental model**, don't port the monkey-patched `fillText`.
- **Camera:** the JS had pan/zoom/WASD with `SC` zoom levels and `MAX_SC`. Port to a 3D camera rig: an orbit/pan gimbal with clamped zoom (dolly or FOV). Keep the *feel* (same min/max framing, same WASD/drag/scroll bindings) — verify against the old build by eye.

**Rule:** UI never reads the 3D scene tree directly and the 3D scene never reads Control nodes. Both read/write the autoloads. The boundary is autoload state + the two projection helpers above.

---

## 4. Phasing & milestones

Each phase ends in a **runnable, demonstrable** state. Do not begin a phase before the prior one is verified.

### Phase 0 — Spike & scaffold (1 vertical sliver)
- Create the Godot project, autoload skeletons (empty), the `GalaxyView` 3D scene with a camera rig, and a `CanvasLayer` HUD stub.
- Hardcode 3 stars + 5 planets as placeholder spheres. Get pan/zoom/select working. Click a planet → a Control panel shows its (fake) name.
- **Exit criteria:** the hybrid boundary (§3) works end to end with placeholder data. This de-risks everything else.

### Phase 1 — World model & generation (no gameplay yet)
- Port `Tuning.gd` (all constants/tables, §6) and `Galaxy.gd` (generation: star placement, planet counts, overlap correction, home-star rules, black holes, alien relics — code map §15, §13; `code_galaxy_generation.md` *with its known gaps noted*).
- Render the generated galaxy with placeholder spheres, real positions/sizes/biomes (biome = material color for now).
- Port `Discovery.gd` (fog tiers, §10).
- **Exit criteria:** a generated galaxy that matches the old build's layout for a fixed seed (see parity harness §9). Selection + camera feel right.

### Phase 2 — Economy, transit, trains
- Port `Economy.gd` (supply/demand, refinery/cargo chain, pricing — code map §ref chain).
- Port `Transit.gd` (route phases incl. `queueing`/`descending`, live tangents, occupancy map, car positioning — code map §6; `code_transit_architecture.md` *pre-dates queueing/descending — trust §6*).
- Port `Train.tscn` to follow routes in 3D (engine + cars along a curve). Placeholder car meshes; **reuse existing 160×160 PNGs as billboards** as a cheap interim look (§7).
- **Exit criteria:** build a train, assign a route, watch it orbit/transit/deliver, credits change correctly. Numbers match old build.

### Phase 3 — AI corporations & missions
- Port `AICorp.gd` (rival sim, mirror-system transform, AI home rules — code map §15; the `ai-snapshot` skill is your diagnostic — see §9).
- Port `Missions.gd` (MISSION_DEFS, `updateMissions`, car-gating, the chain incl. "A Mad Scientist"/Class J, corporate_expansion gate — code map §2/§15; **use the `mission-map` skill to extract the full trigger/objective/reward/unlock graph** rather than hand-reading).
- **Exit criteria:** a full AI opponent runs; missions fire/complete in the right order with the right gates.

### Phase 4 — Full UI parity & onboarding
- Port every popup/panel as Control scenes: TrainBuilder, PlanetDetail (+ upgrades panel), Routes [R], Stations [U], Options (SFX/Music), Controls, Finances, Star Registry [Y]. (code map §22–§23 is the current UI truth; the `code_infobar.md`/`code_planet_detail.md`/etc. sub-memories **significantly pre-date §22–§23** — verify against §23.)
- Port the tutorial chain (~25 phases, §11) and the intro cutscene (§13) — the cutscene becomes a 3D camera-rig sequence (11 shots) with Control narration via `unproject_position` anchors.
- Port chat log (§12), educational callouts, hint bar, watermark, save/load (`SaveLoad.gd`).
- **Exit criteria:** a new player can go title → intro → tutorial → first delivery → mission flow entirely in Godot, matching the old build's flow. **This is "parity done."** Tag it `v0.5.0-godot-parity`.

### Phase 5 — Blender visual overhaul (the payoff)
- Now, and only now, replace placeholders with Blender assets (§8). Planets become textured 3D spheres with real atmospheres/rings/clouds; stars get volumetric glow; trains get 3D models; black holes get a proper shader; stations become 3D structures.
- Lighting pass, post-processing (bloom, etc.), particle systems for cargo beams/engine exhaust.
- **Exit criteria:** the overhaul ships as a *swap* — systems untouched, parity preserved, game looks like a different product.

### Phase 6 — Polish, perf, export
- LODs, instancing for the galaxy, occlusion, audio bus mixing, settings menu, platform export (Windows first; the web export is a nice bonus and keeps the "playable in a page" lineage).

---

## 5. System-by-system port map (JS → GDScript)

For each, the JS lives somewhere in `build_game.py`; find it via the code map section noted, then port to the target autoload. Translate **behavior**, not line-by-line structure — collapse the interleaved draw calls out, keep the math exact.

| JS subsystem | code map § | → Godot home | Port notes / gotchas |
|---|---|---|---|
| Constants, data tables, cargo/engine defs | §project overview, §15 | `Tuning.gd` | Port *first*, *verbatim*. Everything depends on it. Keep names identical to JS for greppability. |
| Galaxy generation | §15, §13; `code_galaxy_generation.md` | `Galaxy.gd` | RNG must be seedable & reproducible (§9). Note: sub-memory pre-dates mirror transform, `_initialOrbitAngle` snapshot, desert-always-inhabited rule. |
| Discovery/visit fog | §10, §5.6 | `Discovery.gd` | 3 tiers; trackOrbit credit awards; `???` obscuring; AI-station view-through gates. |
| Economy / supply-demand | refinery/cargo chain | `Economy.gd` | Pricing & demand formulas are exact — parity-test them. |
| Refinery/cargo chain | refinery/cargo chain | `Economy.gd` | Car-unlock gating via `playerBuiltUpgrades` (`_pBuilt`) — AI production must NOT unlock player cars (memory headline). |
| Transit / routing / orbit | §6 | `Transit.gd` + `Train.gd` | `queueing`/`descending` phases, two-pass occupancy map, live tangent. The hairiest math — port carefully. |
| Train rendering/sizing | §20 | `Train.gd` | The 160×160 bundle + `SPRITE_SOLID` + area-consistency logic is *2D-canvas-specific*. In 3D it's replaced by real models (Phase 5) — but for the interim billboard look (Phase 2) you can keep proportions. Don't over-port the sizing math; 3D solves it natively. |
| AI corporations | §15 | `AICorp.gd` | Use `ai-snapshot` skill to validate (§9). Mirror-system transform for AI home. |
| Missions | §2, §15 | `Missions.gd` | Use `mission-map` skill to extract the full graph. Car-gated intros (`_MISSION_REQUIRED_CAR`). |
| Stations & upgrades | §15; `code_station.md`, `code_planet_detail.md` | `Economy.gd` + `Station.gd` + UI | Blast furnace gated behind Large Station; "PURCHASE" buttons. |
| Save/load | save/load | `SaveLoad.gd` | New format (JSON resource). **Old `index.html` saves are NOT portable** — document this; offer a one-time importer only if the user wants it. |
| HUD / info bar / right panel | §22–§23; `code_infobar.md` | `ui/HUD.tscn` | §23 is truth; sub-memory is stale. Full-height expandable panel, bottom bar spans `0→W-PANEL_W`. |
| Popups (all) | §10, §17; per-popup sub-memories | `ui/popups/*` | Each becomes a Control scene. The `_clearTextOverlayRect` footgun (§1.1) **vanishes** — Godot layering handles it. |
| Tutorial chain | §11 | `ui/Tutorial.gd` | Bubbles anchored via `unproject_position`. Frozen-anchor hack (§11) unneeded. |
| Intro cutscene | §13 | `world/IntroSequence.gd` | 11-shot camera rig + typed narration. `_introOverrides` → temporary scene state. |
| Chat log | §12 | `ui/ChatLog.gd` | SD-timestamp wrap logic; rival-corp countdown warnings. |
| Audio (SFX + music) | Options | `Audio.gd` | Two buses (SFX/Music), volume from settings; replaces `_sfxVol`/`_soundtrack.volume`. |
| Title screen | §14 | `ui/Title.tscn` + 3D vignette | Biome vignettes can become a slow 3D camera over a showcase system. |

---

## 6. Porting the data tables (do this first, mechanically)

The constants/data tables (cargo types, engine specs, biome lists, mission defs, upgrade defs, pricing curves, world constants like `MAX_SC`, orbit radii, SD timing) are the spec's backbone.

- Extract them from `build_game.py` into `Tuning.gd` as `const` dictionaries/arrays, **keeping the exact JS names** so you can grep both codebases in parallel during the port.
- Where the JS computes a table at build time (e.g. `SPRITE_SOLID`), decide: is it still needed in 3D? `SPRITE_SOLID` (opaque-body bbox for 2D sizing) is **not** needed once cars are 3D models. Drop it; note the drop.
- Suggested approach for Claude Code: write a throwaway Python script that imports/parses the relevant literals out of `build_game.py` and prints GDScript `const` blocks. Cheaper and less error-prone than hand-transcription for the big tables (cargo list, mission defs). Spot-check the output.

---

## 7. Asset extraction (interim, for Phases 1–4)

Current embedding pipeline (verified): `build_game.py` reads `assets.json`, base64-inlines `sprites/*.png` (160-bundled via `optimize_assets.py`), `*.woff2` fonts, and `sounds/*` into `index.html`.

For Godot you don't want base64 — you want loose files in `assets/`:

1. **Sprites:** copy `sprites/*.png` (the real PNGs already exist on disk — engines `engine_N700/galaxy/classJ/classR/constellation`, the `car_*` set + `_empty` variants, `caboose`, `ceo_*` portraits, `trophy`, logos) straight into `assets/sprites/`. Use as billboard textures in Phase 2 for the interim train look. The `unused sprites/` folder can be ignored.
2. **Fonts:** copy the WOFF2/TTF into `assets/fonts/`, build a Godot `Theme` (`ui/theme.tres`). This *replaces* the entire HD-text-overlay / DPR / `_smoothTextMode` apparatus.
3. **Audio:** convert `sounds/*.wav` and `*.mp3` to `.ogg` (Godot's friendliest) into `assets/audio/`. Keep names. (Files present: `button`, `discovery`, `breakdown`, `notification`, `construction_complete`, `ding`, `blip`.)
4. **Procedural visuals have no asset to extract** — planets/stars/black holes/clouds are drawn in code. Their *parameters* (palettes, cloud gen, ring math, accretion-disk look — `code_clouds.md`, `code_black_hole.md`) are design references for the Blender/shader work in Phase 5, not files to copy.

Write `tools/extract_assets.py` to automate copy+convert so it's repeatable.

---

## 8. Blender pipeline (Phase 5 — the overhaul)

Only after parity. Establish conventions up front:

- **Units & scale:** pick a Godot world unit = N game units; document it once. Export `+Y up` (Godot) — set Blender export accordingly.
- **Format:** glTF 2.0 (`.glb`), one file per asset. PBR materials. Naming mirrors the sprite names (`engine_galaxy.glb`, `car_iron.glb`, …) for a clean 1:1 swap from billboards.
- **Trains:** model each engine + car as a low-poly mesh with PBR textures. The `car_*` / `_empty` pairing becomes a material/mesh-swap or a visibility toggle (loaded vs empty), not two sprites. Keep coupling/bounding proportions consistent so the existing spacing logic (now trivially 3D) still reads as a coherent train.
- **Planets:** a sphere + biome material set (rock/lava/ice/desert/ocean/gas) + atmosphere shell shader + optional ring mesh + cloud layer (animated shader or a second transparent sphere). This is where "overhaul of visualizations" shines — port the *biome palettes and cloud-drift parameters* from the JS as the art direction starting point.
- **Stars:** emissive sphere + a Godot bloom/glow environment + optional volumetric. Dyson-sphere variant for the intro (§13).
- **Black hole:** a shader (lensing + two-half accretion annulus) — port the *look* from `code_black_hole.md`, implemented as a Godot spatial shader rather than canvas arcs.
- **Stations:** modular 3D kit (small / large / terminal tiers) snapped to planet attachment points.
- **CEO portraits / UI art:** keep as 2D textures (they're already PNGs); optionally re-render in Blender for consistency.
- **Render strategy:** real-time meshes (not pre-rendered sprites), since we chose a 3D world. Reserve pre-rendered turntables only if perf forces a 2.5D fallback for the densest galaxy zoom-out.

Deliver Blender assets incrementally: trains → planets → stars → stations → black hole. Each swap is independently verifiable.

---

## 9. Parity & verification harness

Parity-first only works if parity is *measured*, not eyeballed. Build this early (Phase 1).

- **Seeded determinism:** make galaxy gen + sim deterministic from a seed in both builds. In the JS, find the RNG and add a way to dump state; in Godot, seed `RandomNumberGenerator`.
- **Golden-state dumps:** for a fixed seed, dump from the old `index.html` (via a small injected JS hook, or the existing headless sim scripts — `ai_sim*.py`, `sim_v4.py`, `sim_playtests.py`) a JSON of: star/planet positions & attributes, initial economy, and a tick-by-tick log of credits / train positions / mission state for N stardates. Dump the same from Godot. Diff.
- **Existing skills are your test oracles:**
  - `ai-snapshot` — single headless Very-Hard AI run, rich diagnostic at +N SD. Use to validate `AICorp.gd` matches the JS AI's net worth / buying cadence at checkpoints.
  - `mission-map` — extract the canonical mission graph from `build_game.py`; assert `Missions.gd` reproduces every trigger/objective/reward/unlock edge.
- **Tolerance:** floating-point and iteration-order differences are expected. Define acceptable tolerances (exact for discrete state like unlocks/mission flags; small epsilon for positions/credits) and log divergences instead of hard-failing.
- **The rule from memory still applies:** *don't browser-verify changes yourself* (`rule_no_browser_verify.md`). After each Godot milestone, produce a **numbered manual-verification checklist** for the user to run in the actual Godot build, plus the automated parity diff for the parts that can be machine-checked.

---

## 10. Risks, gotchas, and things NOT to port

- **Don't port the HD-text-overlay hack** (§1.1: monkey-patched `fillText` → separate canvas, composited last, `_clearTextOverlayRect` everywhere, `_smoothTextMode`, `_computeDPR`). It's a workaround for Canvas2D limits Godot doesn't have. Deleting it removes the single biggest footgun in the old codebase.
- **Don't port 2D sizing math you don't need** (`SPRITE_SOLID`, `_carGalAreaFactor`, area-consistency, `_carReserveHalfW` lineage — §20). 3D meshes have real volume; spacing is native.
- **The interleaved render-in-update loop is the enemy.** The JS computes and draws in one pass. Resist the urge to mirror that. Sim in `_physics_process` on autoloads; views read state in `_process`. This is non-negotiable for the Phase-5 swap to be cheap.
- **Saves are not compatible.** Be explicit with the user; don't pretend otherwise.
- **Scope of "one file."** The current single-`index.html` distribution is a feature the user values (playable in a page). Godot web export preserves a version of this — keep it as a Phase-6 target, not a Phase-1 worry.
- **Determinism drift** between JS `Math` and GDScript float ops can accumulate over a long sim. The parity harness must tolerate this for continuous quantities while staying exact on discrete state.
- **Memory sub-files are partially stale.** Several (`code_infobar`, `code_station`, `code_planet_detail`, `code_transit_architecture`, `code_galaxy_generation`, `code_parallax_stars`) pre-date recent waves of work. **`code_map_build_game.md` §22–§23 is the authority for UI; §6 for transit; §13/§15 for gen.** Always cross-check.
- **Build a behavior, then a model.** Every phase must run before it's pretty.

---

## 11. Concrete first tasks for the Claude Code session

In order. Each is a small, verifiable PR.

1. **Read** `code_map_build_game.md` end to end (and re-read §6, §13, §15, §22–§23). Confirm the system inventory in §5 of this plan against the actual source; flag anything missing.
2. **Scaffold** the Godot project per §2 (empty autoloads, `GalaxyView` 3D scene, camera rig, `CanvasLayer` HUD stub). Commit.
3. **Phase 0 spike:** hardcoded 3 stars / 5 planets as placeholder spheres; pan/zoom/select working; click-planet → Control panel via `unproject_position`/raycast. This proves the hybrid boundary (§3). Demo to user.
4. **Port `Tuning.gd`** (§6) — data tables verbatim, names preserved. Write the throwaway extractor script; spot-check.
5. **Port `Galaxy.gd`** generation (§Phase 1) with seedable RNG; stand up the **parity harness** (§9) and show a matching galaxy layout for a fixed seed vs. the old build.
6. Proceed through Phases 1→6, **one phase per milestone**, each ending in a runnable build + a numbered manual-verification checklist for the user (per `rule_no_browser_verify.md`).

**At every step:** the JS in `build_game.py` is the spec. Port behavior exactly; make it beautiful only after it's correct.

---

### Appendix A — quick reference to existing tooling worth reusing

- Headless sim / AI test scripts: `ai_sim.py`, `ai_sim2.py`, `ai_sim3.py`, `ai_sim_detail.py`, `sim_v4.py`, `sim_playtests.py`, `ai_test_results.json` — mine these for golden-state dumps.
- Asset tooling: `encode_assets.py`, `resize_assets.py`, `remove_bg.py`, `optimize_assets.py` (the 160-bundler), `assets.json` (sprite manifest).
- Skills: `ai-snapshot`, `mission-map`, `rebuild-no-ui` (the no-UI build is a useful reference for *which* things are UI vs world — its strip-list is essentially the §3 boundary already enumerated).
- Validation: `check_js.py`, `check_parens.py`.
