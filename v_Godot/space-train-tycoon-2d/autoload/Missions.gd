extends Node
## Missions — MISSION_DEFS data + lifecycle state machine.
## Data ported via tools/gen_missions.py (_mission_data.gd). Lifecycle/chain/
## rewards/unlocks ported from build_game.py updateMissions. See PLAN Phase 3,
## code map §2/§15; graph extracted with the `mission-map` skill.
##
## IMPLEMENTED: the mission graph (25 defs), car-gated introduction, the
## active→completed lifecycle, reward payment, prerequisite chaining, and the
## unlock effects (engines/cars/upgrades).
##
## DEFERRED: per-objective `checkObj` evaluation + intro TRIGGERS are tied to
## gameplay systems not yet ported (station/foundry build, refining, delivery
## counters, tutorial/selection state). Those hook in via mark_objective() /
## trigger checks as Phase 4 lands the UI actions. For now missions advance via
## explicit complete() calls (and the headless harness drives the chain).

const Data = preload("res://autoload/_mission_data.gd")

# Unlock effects on completion (build_game.py updateMissions completion sweep).
const UNLOCKS := {
	"produce_iron": {"upgrades": ["large_station"]},
	"design_better_train": {"engines": ["engine_classJ", "engine_classR"]},
	"mad_scientist": {"engines": ["engine_classJ"]},
	"research_royal_car": {"cars": ["car_royal"]},
}

# Active missions: each {id, status, objectives:[{id,done}], targetPlanetId, ...}
var active: Array = []
var completed: Dictionary = {}   # id -> true
var _pending_intros: Array = []  # ids queued (car-gated until their car unlocks)

signal mission_introduced(id: String)
signal mission_completed(id: String, reward: int)

func _ready() -> void:
	# Visit-driven intro triggers (now that Discovery.track_visit fires).
	Discovery.planet_visited.connect(_on_planet_visited)

func start_new_game() -> void:
	active = []
	completed = {}
	_pending_intros = []
	_pending_targets = {}
	_flower_planets = {}
	_another_dim_start = -1.0
	_dispose_hazmat_snapshot = 0
	# Give the player a first goal (build_foundry's JS trigger is a tutorial
	# timer; here we surface it at game start so the build-chain is reachable).
	queue_intro("build_foundry")

# Visit-driven mission triggers (build_game.py trackVisit/updateMissions).
func _on_planet_visited(pid: int, _reward: int) -> void:
	var visited := Discovery.visited_planet_ids.size()
	# create_route: armed on the first visit to a non-home planet (build_game.py:16138).
	if pid != Galaxy.origen_id:
		queue_intro("create_route")
	# galaxy_census: introduced once 15 planets are visited; objective at 50 (L16132).
	if visited >= 15:
		queue_intro("galaxy_census")
	if is_active("galaxy_census") and visited >= 50:
		mark_objective("galaxy_census", "visit_50_planets")
	# Distinct-system count → stellar_cartography (visit 5 systems) + galactic_distance.
	var systems := {}
	for vp in Discovery.visited_planet_ids:
		var vpp := _planet_at(int(vp))
		if not vpp.is_empty():
			systems[int(vpp.starId)] = true
	if systems.size() >= 2:
		queue_intro("stellar_cartography")
		queue_intro("galactic_distance")
	if is_active("stellar_cartography") and systems.size() >= 5:
		mark_objective("stellar_cartography", "visit_5_systems")
	# Role-based intros (build_game.py trackVisit:16259-16280). The famine/outbreak
	# planet IS the delivery target; lost_colony targets the nearest other relic.
	var p := _planet_at(pid)
	if bool(p.get("isFaminePlanet", false)):
		queue_intro("famine", pid)
	if bool(p.get("isOutbreakPlanet", false)):
		queue_intro("outbreak", pid)
	if bool(p.get("isAlienRelic", false)):
		var nr := _nearest_relic(pid)
		if nr >= 0:
			queue_intro("lost_colony", nr)
	# seeking_home: first visit to a rocky planet → ferry Rocky to a far rocky world.
	if String(p.get("type", {}).get("id", "")) == "rocky":
		var rt := _far_rocky(pid)
		if rt >= 0:
			queue_intro("seeking_home", rt)
	# sandstorm_relief: first desert visit → clear 10 sand by delivering it anywhere.
	if String(p.get("type", {}).get("id", "")) == "desert":
		queue_intro("sandstorm_relief")
	# ancient_schematics: visit an ancient world → ferry the schematics to Orijen.
	if String(p.get("type", {}).get("id", "")) == "ancient":
		queue_intro("ancient_schematics", Galaxy.origen_id)
	# bh_research: visit the black-hole research planet → deliver chemical there.
	if bool(p.get("isBhResearchPlanet", false)):
		queue_intro("bh_research", pid)
	# colony_train: visit the colony source → ferry colonists to the dest world.
	if bool(p.get("isColonyTrainSource", false)):
		queue_intro("colony_train", int(p.get("colonyTrainDestId", -1)))
	# spread_the_seed: visit a flowers-origin world → unlock the Flowers Car + seed
	# 10 flower-capable planets.
	if bool(p.get("isFlowersOrigin", false)):
		if not GameState.unlocked_cars.has("car_flowers"):
			GameState.unlocked_cars["car_flowers"] = true
			GameState.car_unlocked.emit("car_flowers")
		queue_intro("spread_the_seed")
	# Visit-objective completion: reaching a mission's target planet.
	for m in active:
		if int(m.get("targetPlanetId", -1)) == pid:
			for ob in def_for(String(m.id)).get("objectives", []):
				if String(ob.id) in ["visit_relic_target", "visit_planet"]:
					mark_objective(String(m.id), String(ob.id))

# A rocky planet 50k–100k SU from `from_pid` (build_game.py:16071); falls back to
# the nearest other rocky world if none in that band.
func _far_rocky(from_pid: int) -> int:
	var fp := _planet_at(from_pid)
	if fp.is_empty():
		return -1
	var banded := -1
	var nearest := -1
	var nearest_d := INF
	for p in Galaxy.planets:
		if int(p.id) == from_pid or String(p.get("type", {}).get("id", "")) != "rocky":
			continue
		var d: float = Vector2(float(p.x) - float(fp.x), float(p.y) - float(fp.y)).length()
		if d > 50000.0 and d <= 100000.0 and banded < 0:
			banded = int(p.id)
		if d < nearest_d:
			nearest_d = d
			nearest = int(p.id)
	return banded if banded >= 0 else nearest

func _nearest_relic(from_pid: int) -> int:
	var fp := _planet_at(from_pid)
	if fp.is_empty():
		return -1
	var best := -1
	var best_d := INF
	for p in Galaxy.planets:
		if int(p.id) == from_pid or not bool(p.get("isAlienRelic", false)):
			continue
		var d: float = Vector2(float(p.x) - float(fp.x), float(p.y) - float(fp.y)).length_squared()
		if d < best_d:
			best_d = d
			best = int(p.id)
	return best

# create_route completes when the player assigns a route of 3+ stops
# (the mission's goal; build_game.py marks its objectives via the tutorial chain).
func on_route_assigned(stops: Array) -> void:
	if is_active("create_route") and stops.size() >= 3:
		complete("create_route")

func def_for(id: String) -> Dictionary:
	for d in Data.MISSION_DEFS:
		if d.id == id:
			return d
	return {}

# ── Introduction (car-gated — build_game.py _missionCarGateOk) ─────────────
var _pending_targets: Dictionary = {}   # id -> targetPlanetId for queued intros
func queue_intro(id: String, target: int = -1) -> void:
	if is_active(id) or completed.has(id) or id in _pending_intros:
		return
	_pending_intros.append(id)
	if target >= 0:
		_pending_targets[id] = target
	_try_promote_intros()

## A queued mission becomes active only once its required car is unlocked.
func _try_promote_intros() -> void:
	var still := []
	for id in _pending_intros:
		if _car_gate_ok(id):
			_activate(id)
		else:
			still.append(id)
	_pending_intros = still

func _car_gate_ok(id: String) -> bool:
	var req = Data.MISSION_REQUIRED_CAR.get(id, null)
	return req == null or GameState.unlocked_cars.has(req)

func _activate(id: String) -> void:
	var d := def_for(id)
	if d.is_empty():
		return
	var objs := []
	for o in d.objectives:
		objs.append({"id": o.id, "done": false})
	active.append({"id": id, "status": "active", "objectives": objs, "targetPlanetId": int(_pending_targets.get(id, -1))})
	_pending_targets.erase(id)
	mission_introduced.emit(id)

# Call when a car unlocks so gated intros can promote (Phase 4 hook).
func on_car_unlocked(car_type: String) -> void:
	GameState.unlocked_cars[car_type] = true
	_try_promote_intros()

# Generic "deliver N <cargo> to <target>" objective table (build_game.py checkObj
# delivery counters). `to`: origen | station | target (the mission's targetPlanetId)
# | any. Counts accumulate per active mission on its objective.
const _DELIVER_OBJ := {
	"deliver_iron_orijen": {"cargo": "iron", "n": 1, "to": "origen"},
	"deliver_4_iron_for_upgrade": {"cargo": "iron", "n": 4, "to": "station"},
	"deliver_50_to_origen": {"cargo": "passengers", "n": 50, "to": "origen"},
	"deliver_10_steel_home": {"cargo": "steel", "n": 20, "to": "target"},
	"deliver_10_battery_home": {"cargo": "battery", "n": 20, "to": "target"},
	"deliver_10_oil_home": {"cargo": "oil", "n": 20, "to": "target"},
	"deliver_20_livestock": {"cargo": "livestock", "n": 10, "to": "target"},
	"deliver_4_medical": {"cargo": "medical", "n": 4, "to": "target"},
	"deliver_10_sand": {"cargo": "sand", "n": 10, "to": "any"},
	"deliver_5_chemical": {"cargo": "chemical", "n": 5, "to": "target"},
	"deliver_colonists": {"cargo": "passengers", "n": 5, "to": "target"},
	"rocky_home": {"cargo": "passengers", "n": 1, "to": "target"},
}

# Escort / multi-step missions: meeting the single delivery requirement completes
# the WHOLE mission (all objectives marked) — a faithful-enough collapse of the
# pickup→deliver flow the port can't otherwise express.
const _ESCORT := {
	"ancient_schematics": {"cargo": "cargo", "n": 1, "to": "origen"},
	"mad_scientist": {"cargo": "passengers", "n": 1, "to": "origen"},
	"more_scientists": {"cargo": "passengers", "n": 3, "to": "target"},
	"colony_train": {"cargo": "passengers", "n": 5, "to": "target"},
}

## Delivery-driven mission triggers + objective counters (build_game.py
## updateMissions). Called from Transit when a player car unloads.
func on_delivery(cargo: String, planet_id: int) -> void:
	# research_royal_car: introduced at 100 passengers delivered (L21261).
	if cargo == "passengers" and GameState.total_passengers_delivered >= 100:
		queue_intro("research_royal_car")
	# Generic per-objective delivery counting across every active mission.
	for m in active:
		var def := def_for(String(m.id))
		for ob in def.get("objectives", []):
			var req: Dictionary = _DELIVER_OBJ.get(String(ob.id), {})
			if req.is_empty() or String(req.cargo) != cargo:
				continue
			if not _to_matches(String(req.to), planet_id, m):
				continue
			var key := "_cnt_" + String(ob.id)
			m[key] = int(m.get(key, 0)) + 1
			if int(m[key]) >= int(req.n):
				mark_objective(String(m.id), String(ob.id))
	# Escort missions: a single delivery count completes the whole mission.
	for m in active:
		var er: Dictionary = _ESCORT.get(String(m.id), {})
		if er.is_empty() or String(er.cargo) != cargo:
			continue
		if not _to_matches(String(er.to), planet_id, m):
			continue
		var ek := "_esc"
		m[ek] = int(m.get(ek, 0)) + 1
		if int(m[ek]) >= int(er.n):
			_complete_all(String(m.id))
	# spread_the_seed: flowers delivered to ≥10 distinct jungle/desert/resort worlds.
	if cargo == "flowers" and is_active("spread_the_seed"):
		var bio := String(_planet_at(planet_id).get("type", {}).get("id", ""))
		if bio in ["jungle", "desert", "resort"]:
			_flower_planets[planet_id] = true
			if _flower_planets.size() >= 10:
				mark_objective("spread_the_seed", "deliver_flowers_10")

var _flower_planets: Dictionary = {}

func _to_matches(to: String, planet_id: int, m: Dictionary) -> bool:
	match to:
		"origen": return planet_id == Galaxy.origen_id
		"station": return bool(_planet_at(planet_id).get("hasStation", false))
		"target": return planet_id == int(m.get("targetPlanetId", -1))
		_: return true

func _complete_all(id: String) -> void:
	var m := _find_active(id)
	if m.is_empty():
		return
	for o in m.objectives:
		o.done = true
	complete(id)

# another_dimension is a research-WAIT mission (build_game.py wait_research): it
# completes a short while after bh_research finishes.
var _another_dim_start := -1.0
func _process(_dt: float) -> void:
	if is_active("another_dimension") and _another_dim_start >= 0.0 and GameState.stardate - _another_dim_start >= 0.5:
		mark_objective("another_dimension", "wait_research")

func _bh_research_target() -> int:
	for p in Galaxy.planets:
		if bool(p.get("isBhResearchPlanet", false)):
			return int(p.id)
	return Galaxy.origen_id

func _planet_at(pid: int) -> Dictionary:
	return Galaxy.planets[pid] if pid >= 0 and pid < Galaxy.planets.size() else {}

# ── Build-action hooks (Player calls these; advance build-based objectives) ─
func on_station_built(p: Dictionary) -> void:
	if is_active("build_foundry") and p.type.id == "desert":
		mark_objective("build_foundry", "station_foundry_planet")

func on_hazmat_incinerated() -> void:
	# dispose_hazmat: incinerate 2 units (build_game.py:1576).
	if is_active("dispose_hazmat") and GameState.hazmat_incinerated >= int(_dispose_hazmat_snapshot) + 2:
		mark_objective("dispose_hazmat", "incinerate_hazmat")

var _dispose_hazmat_snapshot := 0

func on_upgrade_built(p: Dictionary, upgrade_id: String) -> void:
	# Building an iron foundry starts hazmat production → queue dispose_hazmat
	# (stays car-gated until car_hazmat unlocks).
	if upgrade_id == "iron_foundry":
		_dispose_hazmat_snapshot = GameState.hazmat_incinerated
		queue_intro("dispose_hazmat")
	if is_active("build_foundry") and upgrade_id == "iron_foundry" and p.type.id == "desert":
		mark_objective("build_foundry", "construct_foundry")

func on_large_station_built(_p: Dictionary) -> void:
	if is_active("upgrade_station"):
		mark_objective("upgrade_station", "upgrade_to_large_station")
	# mad_scientist: a large station unlocks the Class-J research arc (build_game.py
	# gates this on 2 large stations; one is close enough for the port). Ferry the
	# scientist back to Orijen → Class J engine.
	queue_intro("mad_scientist", Galaxy.origen_id)

# Refining hooks (Economy.foundry_intake / update_foundries).
func on_foundry_intake(p: Dictionary, upgrade: String) -> void:
	if is_active("produce_iron") and upgrade == "iron_foundry":
		var ud: Dictionary = p.get("upgradeData", {}).get("iron_foundry", {})
		if float(ud.get("molten_ore", 0.0)) >= 1.0 and float(ud.get("water", 0.0)) >= 1.0:
			mark_objective("produce_iron", "deliver_ore_water")

func on_production(_p: Dictionary, output: String) -> void:
	if is_active("produce_iron") and output == "iron":
		mark_objective("produce_iron", "wait_smelt")
	# design_better_train: first steel produced arms the engine-design contract
	# (deliver 20 steel/battery/oil to Orijen → Class J + Class R).
	if output == "steel":
		queue_intro("design_better_train", Galaxy.origen_id)

# galactic_distance: a single delivery whose trip exceeded 15,000 SU.
func on_long_delivery(dist: float) -> void:
	if is_active("galactic_distance") and dist > 15000.0:
		mark_objective("galactic_distance", "deliver_15k_au")

# buy_second_train UI-step objectives (build_game.py tutorial gates).
func on_window_opened(window: String) -> void:
	if is_active("buy_second_train"):
		if window == "trains":
			mark_objective("buy_second_train", "open_trains")
		elif window == "trainbuilder":
			mark_objective("buy_second_train", "open_builder")

func on_train_built(cars: Array) -> void:
	if is_active("buy_second_train"):
		var iron_n := 0
		for c in cars:
			if String(c) == "car_iron":
				iron_n += 1
		if iron_n >= 2:
			mark_objective("buy_second_train", "purchase_train")

# ── Objective + completion ────────────────────────────────────────────────
func _find_active(id: String) -> Dictionary:
	for m in active:
		if m.id == id:
			return m
	return {}

func mark_objective(mission_id: String, obj_id: String) -> void:
	var m := _find_active(mission_id)
	if m.is_empty():
		return
	for o in m.objectives:
		if o.id == obj_id:
			o.done = true
	if m.objectives.all(func(o): return o.done):
		complete(mission_id)

## Complete a mission: pay reward, apply unlocks, chain prerequisites.
func complete(id: String) -> void:
	var m := _find_active(id)
	if m.is_empty() or completed.has(id):
		return
	m.status = "completed"
	active.erase(m)
	completed[id] = true
	var d := def_for(id)
	var reward: int = int(d.get("reward", 0)) if d.get("reward", null) != null else 0
	if reward > 0:
		GameState.credits += reward
	_apply_unlocks(id)
	mission_completed.emit(id, reward)
	# Side missions not chained purely by prerequisite (build_game.py timer gates):
	# finishing the foundry surfaces the parallel "Buy an Iron-delivery Train".
	if id == "build_foundry":
		queue_intro("buy_second_train")
	# bh_research → another_dimension (a research-wait mission) → more_scientists.
	if id == "bh_research":
		_another_dim_start = GameState.stardate
		queue_intro("another_dimension")
	if id == "another_dimension":
		queue_intro("more_scientists", _bh_research_target())
	# colony_train: the destination becomes a thriving new colony (population 541).
	if id == "colony_train":
		var dest := _planet_at(int(m.get("targetPlanetId", -1)))
		if not dest.is_empty():
			dest["population"] = 541
			dest["catchphrase"] = "Reza Mansoor and his people arrived here on a colony ship."
	# Prerequisite chain: introduce every mission gated on this one.
	for nd in Data.MISSION_DEFS:
		if nd.get("prerequisite", "") == id:
			queue_intro(nd.id)

func _apply_unlocks(id: String) -> void:
	var u: Dictionary = UNLOCKS.get(id, {})
	for e in u.get("engines", []):
		if not GameState.unlocked_engines.has(e):
			GameState.unlocked_engines[e] = true
			GameState.engine_unlocked.emit(String(e))
	for c in u.get("cars", []):
		if not GameState.unlocked_cars.has(c):
			GameState.unlocked_cars[c] = true
			GameState.car_unlocked.emit(String(c))
	for up in u.get("upgrades", []):
		if not GameState.unlocked_upgrades.has(up):
			GameState.unlocked_upgrades[up] = true
			GameState.upgrade_unlocked.emit(String(up))
	# Newly-unlocked cars may release car-gated mission intros.
	if u.has("cars"):
		_try_promote_intros()

# ── Queries (the stubs Economy referenced are now real) ───────────────────
func is_active(id: String) -> bool:
	return not _find_active(id).is_empty()

func is_completed(id: String) -> bool:
	return completed.has(id)

func active_target_planet(id: String) -> int:
	var m := _find_active(id)
	return int(m.get("targetPlanetId", -1)) if not m.is_empty() else -1
