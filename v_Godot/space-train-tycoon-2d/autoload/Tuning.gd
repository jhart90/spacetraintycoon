extends Node
## Tuning — constants and data tables ported VERBATIM from build_game.py.
## See PLAN §6. JS names preserved for cross-codebase greppability.
##
## PHASE 1 SCOPE: the generation-relevant tables are ported (world dims, sizes,
## star data, biomes/PTYPES, weights, orbit constants). The economy tables
## (cargo credit rates, engine specs, upgrade defs) are Phase 2 — see TODOs.
##
## Source line refs are into build_game.py (~v0.4.5, 2026-06-17).

# ── World dimensions (build_game.py:918-919) ──────────────────────────────
const WORLD_W: float = 204800.0
const WORLD_H: float = 153600.0

# Camera zoom reference (build_game.py:987-989): MIN_SC = W/65536, MAX_SC = W/512.
const ZOOM_MIN_VIEW_WIDTH: float = 65536.0  # widest view (most zoomed out)
const ZOOM_MAX_VIEW_WIDTH: float = 512.0    # narrowest view (most zoomed in)

# ── Logical canvas / layout (build_game.py:177, 899-902, 988-989) ─────────
# The faithful 2D port re-bases the design resolution to the JS logical canvas
# so every popup rect/font size/bar height ports as the literal JS constant.
const W: float = 900.0          # logical canvas width
const H: float = 500.0          # logical canvas height
const TOP_H: float = 28.0       # top bar height
const BAR_H: float = 72.0       # bottom info bar height
const GH: float = H - BAR_H     # galaxy viewport height (428); w2s/s2w centre Y
const PANEL_W_BASE: float = 185.0  # right panel width (mutable in-game, §22)
# Camera scale bounds: cam.scale ∈ [MIN_SC, MAX_SC]; scale = W / view-world-width.
const MIN_SC: float = W / 65536.0   # most zoomed OUT (~0.013733)
const MAX_SC: float = W / 512.0     # most zoomed IN  (~1.757813)
# Wheel-zoom multipliers + WASD pan rate (build_game.py:31328, 36302).
const ZOOM_IN_FACTOR: float = 1.12
const ZOOM_OUT_FACTOR: float = 0.89
const PAN_PX_FRAME: float = 10.0    # screen px/frame at scale=1 (÷scale in world)

# ── Planet world-unit radii (build_game.py:916) ───────────────────────────
const SIZE_R := {"XS": 24.0, "S": 48.0, "M": 96.0, "L": 192.0, "XL": 288.0, "XXL": 432.0}

# Weighted planet size distribution (build_game.py:1006)
const SIZE_W := [
	{"s": "XS", "w": 12}, {"s": "S", "w": 30}, {"s": "M", "w": 30},
	{"s": "L", "w": 16}, {"s": "XL", "w": 9}, {"s": "XXL", "w": 3},
]

# ── Star world-unit radii (build_game.py:992) ─────────────────────────────
const STAR_R := {"S": 512.0, "M": 1024.0, "L": 2048.0}

# Star colour palettes (build_game.py:994-1003). Each: hi/core/glow/edge hex.
# `core` is the representative albedo/emission colour for placeholder rendering.
const STAR_COLORS := {
	"yellow": {"hi": "#fffce0", "core": "#ffe040", "glow": "#ffaa10", "edge": "#cc6010"},
	"orange": {"hi": "#ffe8c0", "core": "#ff8820", "glow": "#ff4800", "edge": "#aa2800"},
	"blue":   {"hi": "#e8f4ff", "core": "#88c8ff", "glow": "#4488ff", "edge": "#1840c0"},
	"white":  {"hi": "#ffffff", "core": "#f4f4ff", "glow": "#d0d0f0", "edge": "#9090b0"},
	"red":    {"hi": "#ffccb8", "core": "#ff3c20", "glow": "#dd1200", "edge": "#880000"},
	"pink":   {"hi": "#fff0fa", "core": "#ff80e0", "glow": "#ee2090", "edge": "#880044"},
	"purple": {"hi": "#f2eaff", "core": "#cc88ff", "glow": "#8822ee", "edge": "#440099"},
	"teal":   {"hi": "#defffa", "core": "#40ffdd", "glow": "#00bb88", "edge": "#005544"},
}

# Star-colour pools by size (build_game.py:1020-1024, pickStarColor)
const STAR_COLORS_S := ["yellow", "orange", "blue", "white", "pink", "teal"]
const STAR_COLORS_M := ["yellow", "orange", "blue", "pink", "purple", "teal"]
const STAR_COLORS_L := ["yellow", "orange", "blue", "red", "purple", "teal"]

# ── Planet types / biomes (build_game.py:2202-2220) ───────────────────────
# rim is [r,g,b] 0-255. base/hi are hex strings.
const PTYPES := [
	{"id": "ocean",    "base": "#1a5cc8", "hi": "#5090ff", "rim": [60, 150, 255]},
	{"id": "desert",   "base": "#c07820", "hi": "#f0a040", "rim": [240, 150, 60]},
	{"id": "storm",    "base": "#4a1880", "hi": "#9050d8", "rim": [130, 60, 210]},
	{"id": "ice",      "base": "#78b8e8", "hi": "#c8eeff", "rim": [140, 200, 255]},
	{"id": "lava",     "base": "#c01800", "hi": "#ff4020", "rim": [255, 60, 0]},
	{"id": "chemical", "base": "#28980c", "hi": "#60d820", "rim": [80, 220, 40]},
	{"id": "rocky",    "base": "#585040", "hi": "#847060", "rim": [130, 115, 100]},
	{"id": "jungle",   "base": "#134820", "hi": "#286838", "rim": [40, 150, 70]},
	{"id": "resort",   "base": "#0e58b8", "hi": "#38aaf0", "rim": [65, 175, 255]},
	{"id": "agri",     "base": "#72ae32", "hi": "#a8d450", "rim": [135, 210, 55]},
	{"id": "oil",      "base": "#060608", "hi": "#14101e", "rim": [90, 20, 120]},
	{"id": "urban",    "base": "#2a3548", "hi": "#5a6c84", "rim": [180, 210, 255]},
	{"id": "ancient",  "base": "#a89060", "hi": "#d8b878", "rim": [230, 200, 140]},
]
# Per-biome relative frequency for generation (build_game.py:2225). Default 1.0.
const BIOME_WEIGHTS := {"urban": 0.5, "ancient": 0.25}

# Home-system fixed biome sequence, closest→furthest (build_game.py:8400).
# Orijen (the starter planet) sits at index 1.
const HOME_BIOMES := ["lava", "resort", "desert", "agri", "rocky", "chemical"]
# AI mirror-system biome sequence (build_game.py:8992).
const AI_HOME_BIOMES := ["lava", "resort", "desert", "agri", "rocky", "chemical"]

# ── Time / speed model (build_game.py:2935, 36096-36119) ──────────────────
# dt_frames = real_delta_seconds * 60 ; dtG = dt_frames * SPEED_OPTS[idx]
# stardate += dtG * SD_PER_DTG ; orbits advance orbitAngle += orbitSpeed * dtG.
const SPEED_OPTS := [0.0, 0.5, 1.0, 2.0, 5.0, 10.0]
const SPEED_DEFAULT_IDX := 2          # 1×
const SD_PER_DTG: float = 0.01 / 600.0
const CLOUD_SPEED: float = 0.000070   # build_game.py:1798
const START_STARDATE: float = 829.0   # _corp.foundingStardate
const PLAYER_START_CREDITS: int = 250000  # build_game.py:909

# ── Orbit / motion constants ──────────────────────────────────────────────
const ORB_SPD: float = 0.004  # build_game.py:1031
# Generation tuning used by Galaxy.gd (all from build_game.py generateGalaxy):
const SYS_GAP: float = 800.0          # min clear space between system orbit edges (8564)
const HOME_ORBIT_CAP: float = 14000.0 # home star orbit cap (8409)
const STAR_ORBIT_CAP: float = 9000.0  # other stars orbit cap (8409)

# ── Cargo / engine tables (build_game.py:1037,1063,1065,1816,2128) ────────
const CAR_CARGO_TYPE := {
	"car_passenger": "passengers", "car_royal": "passengers", "car_livestock": "livestock",
	"car_mail": "mail", "car_water_tank": "water", "car_ice": "ice", "car_sand": "sand",
	"car_ore": "molten_ore", "car_iron": "iron", "car_gold": "gold", "car_diamond": "diamond",
	"car_hazmat": "hazmat", "car_oil": "oil", "car_battery": "battery", "car_chemical": "chemical",
	"car_flowers": "flowers", "car_medical": "medical", "car_grain": "grain", "car_fruit": "fruit",
	"car_steel": "steel", "car_glass": "glass", "car_machinery": "machinery", "car_cargo": "cargo",
}
const CAR_CARGO_UNITS := {"car_royal": 0.5}  # all others default 1.0
# Cargo → car sprite for supply/demand icon strips (build_game.py:1090 CARGO_CAR_SPRITE).
const CARGO_CAR_SPRITE := {
	"passengers": "car_passenger", "livestock": "car_livestock", "mail": "car_mail",
	"water": "car_water_tank", "ice": "car_ice", "sand": "car_sand", "molten_ore": "car_ore",
	"iron": "car_iron", "gold": "car_gold", "diamond": "car_diamond", "hazmat": "car_hazmat",
	"oil": "car_oil", "battery": "car_battery", "chemical": "car_chemical", "flowers": "car_flowers",
	"medical": "car_medical", "grain": "car_grain", "fruit": "car_fruit", "steel": "car_steel",
	"glass": "car_glass", "machinery": "car_machinery", "cargo": "car_cargo",
}
# {cargoType: {carType: base_credits_per_unit}}
const CARGO_BASE_RATE := {
	"passengers": {"car_passenger": 1000, "car_royal": 1500},
	"livestock": {"car_livestock": 800}, "mail": {"car_mail": 1000},
	"water": {"car_water_tank": 2000}, "ice": {"car_ice": 2500}, "sand": {"car_sand": 1200},
	"molten_ore": {"car_ore": 3800}, "iron": {"car_iron": 6200}, "gold": {"car_gold": 12000},
	"diamond": {"car_diamond": 18000}, "hazmat": {"car_hazmat": 2500}, "oil": {"car_oil": 5500},
	"battery": {"car_battery": 4800}, "chemical": {"car_chemical": 3800}, "flowers": {"car_flowers": 2200},
	"medical": {"car_medical": 3500}, "grain": {"car_grain": 900}, "fruit": {"car_fruit": 1100},
	"steel": {"car_steel": 8000}, "glass": {"car_glass": 5500}, "machinery": {"car_machinery": 9500},
	"cargo": {"car_cargo": 1800},
}
const ENGINE_MAX_SPD := {"engine_constellation": 4.0, "engine_galaxy": 6.0, "engine_classJ": 8.0, "engine_classR": 10.0, "engine_N700": 20.0}
const ENGINE_MAX_CARS := {"engine_constellation": 6, "engine_galaxy": 8, "engine_classJ": 10, "engine_classR": 10, "engine_N700": 10}
const ENGINE_COSTS := {"engine_constellation": 10000, "engine_galaxy": 20000, "engine_classJ": 50000, "engine_classR": 70000, "engine_N700": 100000}
const CAR_COST: int = 1000  # non-engine car (build_game.py sim ref)
const STATION_COST: int = 50000        # _stationBuildCost base (build_game.py:2397)
const LARGE_STATION_COST: int = 50000  # build_game.py:9961
# Upgrade build costs (build_game.py UPGRADES, :1239-1264).
const UPGRADE_COST := {
	"pumping_station": 0, "iron_foundry": 10000, "blast_furnace": 25000, "glassworks": 25000,
	"factory": 40000, "bakery": 15000, "juicery": 15000, "granary": 8000, "farm": 12000,
	"orchard": 10000, "repair_drones": 10000,
}
# Biome each buildable upgrade is eligible on (build_game.py UPGRADES eligibleBiomes).
const UPGRADE_BIOME := {
	"iron_foundry": "desert", "blast_furnace": "rocky", "glassworks": "resort", "factory": "urban",
	"bakery": "resort", "juicery": "jungle", "granary": "agri", "farm": "agri", "orchard": "agri",
}

# ── AI rival corporation (build_game.py:907-913) ──────────────────────────
# Tick interval = SD between AI investment decisions (lower = more aggressive).
const AI_TICK_INTERVALS := {"very_easy": 22.0, "easy": 13.0, "normal": 7.0, "hard": 3.5, "very_hard": 1.8}
const AI_START_CREDITS := {"very_easy": 250000, "easy": 300000, "normal": 400000, "hard": 500000, "very_hard": 750000}
const AI_CORP_NAMES := {"very_easy": "Cosmic Crawlers Inc.", "easy": "Frontier Lines", "normal": "Stellar Transport Corp.", "hard": "Galaxy Express Corp.", "very_hard": "Omnivore Logistics"}

# ── Helper: look up a PTYPE dict by id ────────────────────────────────────
func ptype(id: String) -> Dictionary:
	for t in PTYPES:
		if t.id == id:
			return t
	return PTYPES[0]

# ── TODO(Phase 2): port the economy tables ────────────────────────────────
#   CAR_CARGO_TYPE (1037), CAR_CARGO_UNITS (1063), credit-rate table (1064+),
#   UPGRADES defs, ENGINE specs, supply/demand/economic-health formulas,
#   generatePopulation, seedCargoPlanet. These feed Economy.gd, not layout.
