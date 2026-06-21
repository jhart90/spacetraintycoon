extends Node
## GameState — the god-object the JS used as implicit globals.
##
## In build_game.py, gameplay state lived in a sea of module-level `let`s and a
## big `gameState`/`gs` machine. Here it is the single source of truth that both
## the 3D world (world/) and the 2D HUD (ui/) read and write. Per PLAN §3:
## the UI never reads the 3D scene tree and the 3D scene never reads Control
## nodes — both talk through this autoload (+ the two camera projection helpers).
##
## Phase 0: only selection state is implemented. Everything else is a stub.

# --- High-level game phase. Mirrors the JS `gs` string machine (§8/§13). ---
enum Phase { TITLE, INTRO, GALAXY, PAUSED }
var phase: int = Phase.GALAXY

# --- Selection (Phase 0 functional). ---
# selected = {} when nothing is selected, else {"kind": "planet"|"star"|"train", "id": String, "name": String}
var selected: Dictionary = {}
# World→screen projection result for the selected body, pushed by GalaxyView each
# frame (the §3 "world → screen" bridge). HUD reads this to float a label without
# ever touching the 3D tree. Vector2.INF when off-screen / nothing selected.
var selected_screen_pos: Vector2 = Vector2.INF

signal selection_changed(selected: Dictionary)
signal popup_requested(name: String)  # UI layer opens the named popup

func select(kind: String, id: String, display_name: String) -> void:
	selected = {"kind": kind, "id": id, "name": display_name}
	selection_changed.emit(selected)

func clear_selection() -> void:
	selected = {}
	selected_screen_pos = Vector2.INF
	selection_changed.emit(selected)

# --- Economy / time (Phase 2). ---
var credits: int = 0
var stardate: float = 0.0           # JS "SD" clock
var game_speed_idx: int = Tuning.SPEED_DEFAULT_IDX  # index into Tuning.SPEED_OPTS
# Set true once any Bakery/Juicery produces "cargo" — shifts global demand
# (build_game.py _anyCargoProduced). False until Phase 2/3 production lands.
var any_cargo_produced: bool = false
# Player-only passenger deliveries (build_game.py _totalPassengersDelivered) —
# gates research_royal_car at 100.
var total_passengers_delivered: int = 0

signal stardate_changed(sd: float)
signal player_delivered(revenue: int)  # a player car unloaded for revenue (SFX hook)

# Unlock sets (Phase 3 — missions grant these). {key: true}.
var unlocked_engines: Dictionary = {}
var unlocked_cars: Dictionary = {}
var unlocked_upgrades: Dictionary = {}

## Initialise a fresh game's clock/credits (call after Galaxy.generate).
func start_new_game() -> void:
	stardate = Tuning.START_STARDATE
	credits = Tuning.PLAYER_START_CREDITS
	game_speed_idx = Tuning.SPEED_DEFAULT_IDX
	phase = Phase.GALAXY
	# Starting unlocks (the basic engines + early cars).
	unlocked_engines = {"engine_constellation": true, "engine_galaxy": true}
	unlocked_cars = {"car_passenger": true, "car_mail": true, "car_water_tank": true, "car_ore": true, "caboose": true}
	unlocked_upgrades = {}
	any_cargo_produced = false
	total_passengers_delivered = 0

func set_speed_idx(idx: int) -> void:
	game_speed_idx = clampi(idx, 0, Tuning.SPEED_OPTS.size() - 1)

## Simulation tick (PLAN §10: sim runs on the autoload; views read in _process).
func _physics_process(delta: float) -> void:
	if phase != Phase.GALAXY or Galaxy.planets.is_empty():
		return
	var dt_frames := delta * 60.0                       # JS dt: 1.0 per 60fps frame
	var dtG: float = dt_frames * Tuning.SPEED_OPTS[game_speed_idx]
	if dtG <= 0.0:
		return
	stardate += dtG * Tuning.SD_PER_DTG
	Galaxy.advance_orbits(dtG)
	Transit.tick(dtG)
	AICorp.tick(dtG)
	stardate_changed.emit(stardate)

# --- TODO(port): mirror the rest of the JS global state here as phases land. ---
