# Space Train Tycoon — Blender + Godot Port (`v_Godot/`)

All work for the Blender + Godot port lives in this folder. The **source of truth**
for behavior remains the existing game: `../build_game.py` → `../index.html`. The
porting plan is `../PORT_TO_GODOT_PLAN.md` (referenced below as **PLAN §N**).

> **Parity-first, then overhaul.** Phases 0–4 reproduce current behavior with
> placeholder art (GDScript logic port). Phase 5+ is the Blender visual overhaul
> on top of verified systems. *Build a behavior, then a model.*

---

## Layout

```
v_Godot/
├── README.md                  ← this file
├── .gitignore                 ← ignores Godot cache + cloned MCP servers
├── space-train-tycoon/        ← the Godot 4.6 project (open this in Godot)
│   ├── project.godot
│   ├── Main.tscn / Main.gd     ← thin root: builds GalaxyView + HUD
│   ├── autoload/               ← the ported "engine" (logic singletons, PLAN §2)
│   │   ├── GameState.gd  (wired for Phase 0)
│   │   ├── Tuning.gd Galaxy.gd Economy.gd Transit.gd
│   │   ├── AICorp.gd Missions.gd Discovery.gd SaveLoad.gd Audio.gd  (skeletons)
│   ├── world/GalaxyView.gd     ← 3D galaxy + camera rig + picking (Phase 0 spike)
│   └── ui/HUD.gd               ← 2D CanvasLayer HUD (Phase 0 spike)
└── tools/                      ← cloned MCP servers (gitignored)
    ├── godot-mcp/              ← Node MCP server (built)
    └── blender-mcp/            ← Blender MCP server + addon source
```

## Environment (verified 2026-06-17)

| Tool | Path |
|---|---|
| Godot 4.6.3 (GUI) | `C:\Users\jackh\Downloads\Godot463\Godot_v4.6.3-stable_win64.exe` |
| Godot 4.6.3 (console) | `…\Godot463\Godot_v4.6.3-stable_win64_console.exe` |
| Blender 5.1 | `C:\Program Files\Blender Foundation\Blender 5.1\blender.exe` |
| Node | `C:\Program Files\nodejs\node.exe` (v24) |
| uv / uvx | `C:\Users\jackh\AppData\Local\Programs\Python\Python310\Scripts\` |

---

## MCP server setup

Both servers are configured in `~/.claude.json` under this project's `mcpServers`
(backup at `~/.claude.json.bak-godot-mcp`):

- **godot** → `node …/tools/godot-mcp/build/index.js`, `GODOT_PATH` → the Godot exe.
- **blender** → `uvx blender-mcp` (package pre-installed via `uv tool install`).

### ⚠️ To activate the MCP servers — RESTART Claude Code
MCP servers load at startup, so they are **not available in the session that
configured them**. After restarting, run `/mcp` (or check the MCP status) to
confirm `godot` and `blender` are connected.

### ⚠️ Blender MCP also needs the addon running (manual, once per Blender session)
The Blender server talks to a socket (port 9876) opened by an addon *inside*
Blender. The addon has been copied to Blender's auto-discovered folder:
`…\Blender Foundation\Blender\5.1\scripts\addons\blender_mcp_addon.py`.

1. Open Blender 5.1.
2. `Edit → Preferences → Add-ons`, search **"Blender MCP"**, tick to enable.
3. In the 3D viewport press `N` for the sidebar → **BlenderMCP** tab →
   **"Connect to MCP server"**.
4. Leave Blender open while using the `blender` MCP tools.

(The `godot` MCP server needs no manual step — it drives the Godot binary directly.)

---

## Running the Godot project

- **Editor:** open `space-train-tycoon/project.godot` in Godot 4.6.3, press F5.
- **Headless smoke test** (no window):
  ```sh
  GODOT="C:/Users/jackh/Downloads/Godot463/Godot_v4.6.3-stable_win64_console.exe"
  "$GODOT" --headless --path space-train-tycoon --quit-after 90
  ```
  (Used during the port to confirm scripts compile and `_ready` doesn't crash.)

---

## Status

- [x] **Phase 0 — Spike & scaffold.** Godot project, autoload skeletons, 3D
      `GalaxyView` with orbit/pan/zoom camera + raycast picking, `CanvasLayer`
      HUD. 3 placeholder stars + 5 placeholder planets. Proves the hybrid 2D/3D
      boundary (PLAN §3): screen→world picking and world→screen labels via
      `GameState`. Imports + runs headless with no errors.
- [x] **Phase 1 — World model & generation.** `Tuning.gd` (generation tables),
      `Galaxy.gd` (seeded port of `generateGalaxy` geometry: black holes, stars,
      home system w/ `HOME_BIOMES`, overlap correction, close-neighbour, relics),
      `Discovery.gd` (fog tiers + new-game init + visit tracking). `GalaxyView`
      renders the generated galaxy with fog (F = debug reveal-all, V = visit
      selected planet's system). **Parity harness** `tools/parity/run_parity.sh`
      runs the Godot invariant check AND the real `index.html` `generateGalaxy`
      headlessly in Node — both PASS the same invariants; Godot output sits inside
      the JS distribution. (Economy/cosmetic/mission-role/AI-mirror generation is
      stubbed → Phase 2/3/5.)
- [x] **Phase 2 — Economy, transit, trains.** Sim clock + planet orbital
      motion (`GameState._physics_process` → `Galaxy.advance_orbits`); `Economy.gd`
      (population/supply/demand/economic-health/cargo seeding + the revenue
      formula, **parity-confirmed** against the real JS — Orijen pop & populated
      counts sit in the JS distribution); `Transit.gd` (train model, route phase
      machine ORBIT↔TRANSIT, live-position movement, per-car cargo load/unload
      with exact revenue → credits). A demo train runs Orijen⇄home in the scene.
      Deferred refinements (code map §6): accel ramp, queueing/descending,
      occupancy map, live-tangent multi-car positioning, supply/demand accrual.
- [x] **Phase 3 — AI corporations & missions (cores).** `Missions.gd` (25-def
      graph via `tools/gen_missions.py`, car-gated intros, lifecycle, prerequisite
      chain, rewards, unlock effects — verified) + `AICorp.gd` (difficulty-scaled
      rival that buys trains, earns revenue, grows net worth — verified).
      *Deferred:* per-objective `checkObj`/intro triggers tied to un-ported
      gameplay; AI mirror-system transform + station building.
- [~] **Phase 4 — UI + systems (functional core + persistence).** HUD
      (credits/stardate/speed/AI top bar, mission tracker, fog-aware selection),
      speed `[`/`]` + SPACE-pause; **`SaveLoad.gd`** (full JSON round-trip:
      seed + planet runtime + scalar state + discovery + missions + AI + trains,
      verified); **live mission triggers** (100 passenger deliveries →
      `research_royal_car`, verified); **`Player.gd` interactive actions** —
      build station / upgrade (foundry/etc.) / large station / buy train / assign
      route, with cost + prerequisite validation and mission hooks (building a
      station + iron foundry on a desert *completes* `build_foundry` → chains
      `produce_iron`); **hotkeys** N=station, G=foundry, B=build+route train, with
      HUD action feedback; **Train Builder popup** (`ui/TrainBuilder.gd` — engine
      + car picker, live cost, BUILD→`Player.build_train`+auto-route; opened with
      `T`) and **context action buttons**; **all read/light popups** —
      Options (SFX/Music sliders), Routes `[R]`, Stations `[U]`, Finances `[C]`
      (you-vs-rival), Planet Detail `[P]` (supply/demand + build buttons);
      **ChatLog** (event feed); **Title screen** (New Game / Continue / Options)
      and **Intro** (the 3 `_INTRO_TEXT` paragraphs) over a slow-rotating galaxy
      backdrop → full title→intro→play→mission flow; **Tutorial** (`ui/Tutorial.gd`)
      — a guided onboarding chain (look → select planet → build train → build
      station → build foundry → done) that auto-advances as it detects each
      action, with Skip. *Deferred (only remaining Phase 4 item):* the cinematic
      11-shot 3D intro cutscene (the narration screen stands in for it).
- [~] **Phase 5 — Blender pipeline PROVEN + 2 assets.**
      `tools/blender/gen_{train,car}_glb.py` build PBR engine + passenger car and
      export `.glb` headlessly; Godot imports them and renders **multi-car
      consists** (engine + cars, oriented along travel) in place of boxes. The
      swap path works end-to-end. **Galaxy visual overhaul (in-Godot):**
      biome-aware planet materials (atmosphere rim; lava/storm emission; ice/ocean
      specular), rings on some gas/storm worlds, black-hole **accretion disks**,
      and blue **station track-rings** on built stations. *Deferred:* the rest of
      the `.glb` set (other engines/cars/3-D stations) — same template, one each.
- [~] **Audio (Phase 4/6 start).** `Audio.gd` — SFX/Music buses, sounds in
      assets/audio, wired to events (delivery ding, build chime, mission
      notification, discovery sting). **Transit queueing:** arriving trains stack
      into concentric orbits at busy hubs (lightweight §6 contention stand-in).
- [ ] Phase 6 — remaining: LODs/instancing for the 300-star galaxy, music track,
      full §6 contention (waiting/blocked, occupancy two-pass), Windows/web export.

See `../PORT_TO_GODOT_PLAN.md` for the full phase definitions and the JS→GDScript
system map.
