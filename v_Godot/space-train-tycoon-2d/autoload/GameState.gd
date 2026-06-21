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

# Front-end screen state machine (M6) — mirrors the JS `gs` string. The sim only
# ticks while gs == "galaxy"; the Screens overlay covers everything otherwise.
var gs := "galaxy"   # "title" | "corpsetup" | "aiselect" | "galaxy"
var corp_name := "STELLAR TRANSIT CO."
var ai_difficulty := "normal"
var ceo_name := ""
var ceo_revenue_mult: Dictionary = {}  # {cargo: 1.12} — the picked CEO's perks
# Full CEO model (build_game.py CEO_ROSTER/_genCeoCandidate ~2137). The current
# CEO + two re-rollable hire candidates + the hiring-cooldown clock.
var ceo: Dictionary = {}            # {name, sprite, salary, perks:[String,String], mult, nickname}
var ceo_candidates: Array = []      # up to 2 candidates available for hire
var ceo_last_hire_sd := -1.0        # SD of last hire; drives the 1.0-SD cooldown
var _ceo_rng := RandomNumberGenerator.new()
const _CEO_ROSTER := [["Gigi", "ceo_gigi"], ["Jaemin", "ceo_jaemin"], ["Keonho", "ceo_keonho"], ["Mega", "ceo_mega"]]
const _CEO_PERK_CARGO := [["Sand", "sand"], ["Water", "water"], ["Molten Ore", "molten_ore"], ["Iron", "iron"], ["Livestock", "livestock"], ["Mail", "mail"], ["Oil", "oil"], ["Battery", "battery"], ["Chemical", "chemical"], ["Passenger", "passengers"], ["Grain", "grain"], ["Fruit", "fruit"]]
const _CEO_NICKNAMES := {
	"sand": "\"The Desert Baron\"", "water": "\"The Water Mogul\"", "molten_ore": "\"The Smelter\"",
	"iron": "\"The Iron Magnate\"", "livestock": "\"The Rancher\"", "mail": "\"The Postmaster\"",
	"oil": "\"The Oil Baron\"", "battery": "\"The Power Broker\"", "chemical": "\"The Chemist\"",
	"passengers": "\"The People Person\"",
}

# Build a fresh CEO candidate (salary + two revenue perks) — mirrors Screens'
# corp-setup generation so the roster shape is identical.
func _gen_ceo(cname: String, sprite: String) -> Dictionary:
	var c1: Array = _CEO_PERK_CARGO[_ceo_rng.randi() % _CEO_PERK_CARGO.size()]
	var c2: Array = _CEO_PERK_CARGO[_ceo_rng.randi() % _CEO_PERK_CARGO.size()]
	var v1 := 5 + _ceo_rng.randi() % 20
	var v2 := 5 + _ceo_rng.randi() % 15
	return {
		"name": cname, "sprite": sprite, "salary": 40000 + (_ceo_rng.randi() % 30) * 10000,
		"perks": ["+%d%% %s Revenue" % [v1, c1[0]], "+%d%% %s Revenue" % [v2, c2[0]]],
		"mult": {String(c1[1]): 1.0 + v1 / 100.0, String(c2[1]): 1.0 + v2 / 100.0},
		"nickname": _CEO_NICKNAMES.get(String(c1[1]), "\"The Executive\""),
	}

# Re-roll the two hire candidates from the roster, excluding the sitting CEO.
func roll_ceo_candidates() -> void:
	var cur_sprite := String(ceo.get("sprite", ""))
	var pool: Array = []
	for e in _CEO_ROSTER:
		if String(e[1]) != cur_sprite:
			pool.append(e)
	for k in range(pool.size() - 1, 0, -1):
		var j := _ceo_rng.randi() % (k + 1)
		var tmp = pool[k]; pool[k] = pool[j]; pool[j] = tmp
	ceo_candidates = []
	for ci in mini(2, pool.size()):
		ceo_candidates.append(_gen_ceo(String(pool[ci][0]), String(pool[ci][1])))

# Install a CEO (from corp-setup or a hire) + refresh the revenue multipliers.
func set_ceo(c: Dictionary) -> void:
	ceo = c.duplicate(true)
	if not ceo.has("nickname"):
		var k := ""
		for key in (c.get("mult", {}) as Dictionary).keys():
			k = String(key); break
		ceo["nickname"] = _CEO_NICKNAMES.get(k, "\"The Executive\"")
	ceo_name = String(c.get("name", ""))
	ceo_revenue_mult = (c.get("mult", {}) as Dictionary).duplicate()

# Hire candidate `idx`: swap in, start the cooldown, re-roll the bench.
func hire_ceo(idx: int) -> void:
	if idx < 0 or idx >= ceo_candidates.size():
		return
	set_ceo(ceo_candidates[idx])
	ceo_last_hire_sd = stardate
	roll_ceo_candidates()

# Remaining hiring cooldown in SD (build_game.py 1.0-SD lock after a hire).
func ceo_cooldown() -> float:
	if ceo_last_hire_sd < 0.0:
		return 0.0
	return maxf(0.0, 1.0 - (stardate - ceo_last_hire_sd))
var pending_cam: Dictionary = {}  # {x,y,scale} from a loaded save; GalaxyView applies on enter
var popup_active := false  # true while a modal popup is open → HUD/galaxy skip input
var autosave_enabled := true        # Options toggle (build_game.py autosaveEnabled)
var mission_tracker_enabled := true # Options toggle — show the floating mission tracker
var view_cam: Dictionary = {}  # {x,y,scale} pushed by GalaxyView each frame; read on save
signal screen_changed(gs: String)

func set_screen(s: String) -> void:
	gs = s
	phase = Phase.GALAXY if s == "galaxy" else Phase.TITLE
	screen_changed.emit(s)

# --- Selection (Phase 0 functional). ---
# selected = {} when nothing is selected, else {"kind": "planet"|"star"|"train", "id": String, "name": String}
var selected: Dictionary = {}
# World→screen projection result for the selected body, pushed by GalaxyView each
# frame (the §3 "world → screen" bridge). HUD reads this to float a label without
# ever touching the 3D tree. Vector2.INF when off-screen / nothing selected.
var selected_screen_pos: Vector2 = Vector2.INF

signal selection_changed(selected: Dictionary)
signal popup_requested(name: String)  # UI layer opens the named popup

# Routing: an in-progress multi-stop route built via "ROUTE TRAIN HERE"; the next
# train click assigns these stops. Empty = not routing.
var route_stops: Array = []

# Right panel expand-to-2× (build_game.py §22). PANEL_W is mutable.
var panel_expanded: bool = false
func panel_w() -> float:
	return Tuning.PANEL_W_BASE * (2.0 if panel_expanded else 1.0)

func select(kind: String, id: String, display_name: String) -> void:
	selected = {"kind": kind, "id": id, "name": display_name}
	selection_changed.emit(selected)

func clear_selection() -> void:
	selected = {}
	selected_screen_pos = Vector2.INF
	selection_changed.emit(selected)

# --- Finance ledger (build_game.py financeLedger / purchaseLedger). Drives the
#     [F] CORPORATE FINANCES popup. Revenue entries pushed at the player-delivery
#     site (Transit); purchases pushed at the Player build sites. ---
var finance_ledger: Array = []   # {sd, cargoType, trainName, planetId, starId, revenue, cost}
var purchase_ledger: Array = []  # {sd, amount}
var corp_value_history: Dictionary = {}  # {sd_floor: corp_value} for the SD-mode CORP VALUE column
const FINANCE_LEDGER_CAP := 4000

func record_revenue(cargo: String, train_name: String, planet_id: int, star_id: int, revenue: int) -> void:
	finance_ledger.append({"sd": stardate, "cargoType": cargo, "trainName": train_name, "planetId": planet_id, "starId": star_id, "revenue": revenue, "cost": 0})
	if finance_ledger.size() > FINANCE_LEDGER_CAP:
		finance_ledger.pop_front()

func record_purchase(amount: int) -> void:
	purchase_ledger.append({"sd": stardate, "amount": amount})
	if purchase_ledger.size() > FINANCE_LEDGER_CAP:
		purchase_ledger.pop_front()

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
signal first_delivery(planet_id: int, cargo: String, car_type: String, sd: float)
var delivered_planets: Dictionary = {}  # planet ids that have received player cargo
signal engine_unlocked(id: String)
signal car_unlocked(id: String)
# Planet-upgrade type newly unlocked (build_game.py pendingUpgradeUnlocks ~3564).
signal upgrade_unlocked(id: String)

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
	_ceo_rng.randomize()

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
	var prev_floor := int(floor(stardate))
	stardate += dtG * Tuning.SD_PER_DTG
	var new_floor := int(floor(stardate))
	if new_floor > prev_floor:
		corp_value_history[prev_floor] = Leaderboard._corp_value()  # snapshot at the SD boundary
		# CEO salary tick + bench re-roll (build_game.py SD-tick ~36317).
		if not ceo.is_empty():
			var sal := int(ceo.get("salary", 0))
			if sal > 0:
				credits = maxi(0, credits - sal)
				finance_ledger.append({"sd": new_floor, "cargoType": "ceo_salary", "trainName": "CEO", "planetId": -1, "starId": -1, "revenue": 0, "cost": sal})
				if finance_ledger.size() > FINANCE_LEDGER_CAP:
					finance_ledger.pop_front()
			roll_ceo_candidates()
	Galaxy.advance_orbits(dtG)
	Economy.accumulate(dtG * Tuning.SD_PER_DTG)  # replenish supply/demand pools
	Transit.tick(dtG)
	AICorp.tick(dtG)
	Fog.update(dtG * Tuning.SD_PER_DTG)
	stardate_changed.emit(stardate)

# --- TODO(port): mirror the rest of the JS global state here as phases land. ---
