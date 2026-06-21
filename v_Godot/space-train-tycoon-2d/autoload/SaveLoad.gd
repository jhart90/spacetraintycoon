extends Node
## SaveLoad — JSON serialize/restore of the whole game (PLAN Phase 4, §5).
##
## Strategy: the galaxy LAYOUT is fully determined by its seed, so we save the
## seed + only the mutable runtime (planet orbit angles, supply/demand, station/
## upgrade state) and regenerate on load. Plus all scalar state, discovery sets,
## missions, AI, and trains. JSON parses numbers as float, so int fields are
## re-cast on load (_ti / _tia).
##
## NOTE (PLAN §10): old index.html saves are NOT compatible — this is a new format.

const SAVE_PATH := "user://savegame.stt"
const VERSION := 2

# Save in the original `.stt` interchange format (full galaxy + state), so saves
# round-trip through the same loader and are compatible with the original game's
# format. The reduced port sim simply doesn't populate the fields it doesn't model.
func save_game(path: String = SAVE_PATH) -> bool:
	# Galaxy: serialize planets with `type` collapsed back to {id} (the original
	# format; the loader rebuilds the full biome dict from the id).
	var planets := []
	for p in Galaxy.planets:
		var pp: Dictionary = p.duplicate()
		var ty = p.get("type", {})
		pp["type"] = {"id": String(ty.get("id", "rocky"))} if ty is Dictionary else {"id": "rocky"}
		pp.erase("supplyRate")
		pp.erase("demandRate")
		planets.append(pp)
	# Trains: original stores cars = [engine, ...cars]; rebuild that shape.
	var trains := []
	for t in Transit.trains:
		var tt: Dictionary = t.duplicate()
		var combined := [String(t.get("engine", "engine_galaxy"))]
		for c in t.get("cars", []):
			combined.append(String(c))
		tt["cars"] = combined
		trains.append(tt)
	var data := {
		"version": VERSION,
		"seed": Galaxy._seed,
		"missions": {"active": Missions.active, "completed": Missions.completed.keys(), "pending": Missions._pending_intros},
		"galaxy": {
			"stars": Galaxy.stars, "planets": planets, "blackHoles": Galaxy.black_holes,
			"homeStarId": Galaxy.home_star_id, "origenId": Galaxy.origen_id,
		},
		"stardate": GameState.stardate, "credits": GameState.credits, "gameSpeedIdx": GameState.game_speed_idx,
		"corpName": GameState.corp_name,
		"_totalPassengersDelivered": GameState.total_passengers_delivered,
		"_anyCargoProduced": GameState.any_cargo_produced,
		"financeLedger": GameState.finance_ledger, "purchaseLedger": GameState.purchase_ledger,
		"corpValueHistory": GameState.corp_value_history,
		"cam": GameState.view_cam if not GameState.view_cam.is_empty() else {"x": 0.0, "y": 0.0, "scale": Tuning.MIN_SC * 8.0},
		"discoveredPlanetIds": Discovery.discovered_planet_ids.keys(),
		"visitedPlanetIds": Discovery.visited_planet_ids.keys(),
		"revealedStarIds": Discovery.revealed_star_ids.keys(),
		"trains": trains,
		"_aiCorp": {"credits": AICorp.credits, "totalRevenue": AICorp.total_revenue, "homeStarId": AICorp.home_star_id, "name": AICorp.corp_name} if AICorp.active else null,
		"_aiDifficulty": AICorp.difficulty,
	}
	# Unlock flags (original _*Unlocked).
	data["_classJEngineUnlocked"] = GameState.unlocked_engines.has("engine_classJ")
	data["_classREngineUnlocked"] = GameState.unlocked_engines.has("engine_classR")
	data["_N700EngineUnlocked"] = GameState.unlocked_engines.has("engine_N700")
	data["_largeStationUnlocked"] = GameState.unlocked_upgrades.has("large_station")
	data["_terminalUnlocked"] = GameState.unlocked_upgrades.has("terminal")
	var carflags := {"_ironCarUnlocked": "car_iron", "_steelCarUnlocked": "car_steel", "_glassCarUnlocked": "car_glass", "_hazmatCarUnlocked": "car_hazmat", "_machineryCarUnlocked": "car_machinery", "_cargoCarUnlocked": "car_cargo", "_livestockCarUnlocked": "car_livestock", "_flowersCarUnlocked": "car_flowers", "_medicalCarUnlocked": "car_medical", "_grainCarUnlocked": "car_grain", "_fruitCarUnlocked": "car_fruit", "_royalCarUnlocked": "car_royal"}
	for fk in carflags:
		data[fk] = GameState.unlocked_cars.has(carflags[fk])
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data))
	f.close()
	# Submit this corp's stats to the public leaderboard on save (build_game.py
	# _lbSubmit at the manual-save site). Fire-and-forget; throttled internally.
	Leaderboard.submit()
	return true

func load_game(path: String = SAVE_PATH) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(data) != TYPE_DICTIONARY:
		return false
	# Original index.html `.stt` interchange format: stores the FULL galaxy (no
	# seed). Detect + load it directly so existing .stt saves are playable.
	if data.has("galaxy") and (data.galaxy is Dictionary) and (data.galaxy as Dictionary).has("stars"):
		return _load_stt_data(data)

	Galaxy.generate(_ti(data.seed))
	# Overlay mutable planet runtime + recompute world positions from orbit angle.
	for pr in data.planets:
		var idx := _ti(pr.id)
		if idx < 0 or idx >= Galaxy.planets.size():
			continue
		var p: Dictionary = Galaxy.planets[idx]
		p.orbitAngle = float(pr.orbitAngle)
		p.supply = pr.get("supply", {})
		p.demand = pr.get("demand", {})
		p.hasStation = pr.get("hasStation", false)
		p.isAlienRelic = pr.get("isAlienRelic", false)
		p.upgrades = pr.get("upgrades", [])
		var star: Dictionary = Galaxy.stars[p.starId]
		p.x = star.x + p.orbitRadius * cos(p.orbitAngle)
		p.y = star.y + p.orbitRadius * sin(p.orbitAngle)

	GameState.stardate = float(data.stardate)
	GameState.credits = _ti(data.credits)
	GameState.game_speed_idx = _ti(data.speed)
	GameState.unlocked_engines = _bool_set(data.unlocked_engines)
	GameState.unlocked_cars = _bool_set(data.unlocked_cars)
	GameState.unlocked_upgrades = _bool_set(data.unlocked_upgrades)
	GameState.any_cargo_produced = bool(data.any_cargo_produced)

	Discovery.visited_planet_ids = _id_set(data.discovery.visited)
	Discovery.discovered_planet_ids = _id_set(data.discovery.discovered)
	Discovery.revealed_star_ids = _id_set(data.discovery.stars)

	Missions.active = []
	for m in data.missions.active:
		m["id"] = String(m.id)
		m["targetPlanetId"] = _ti(m.get("targetPlanetId", -1))
		Missions.active.append(m)
	Missions.completed = {}
	for id in data.missions.completed:
		Missions.completed[String(id)] = true
	Missions._pending_intros = []
	for id in data.missions.pending:
		Missions._pending_intros.append(String(id))

	AICorp.active = bool(data.ai.active)
	AICorp.difficulty = String(data.ai.difficulty)
	AICorp.credits = _ti(data.ai.credits)
	AICorp.total_revenue = _ti(data.ai.total_revenue)
	AICorp.home_star_id = _ti(data.ai.home)
	AICorp._tick_acc = float(data.ai.tick_acc)
	AICorp.corp_name = Tuning.AI_CORP_NAMES.get(AICorp.difficulty, "Rival Corp")

	Transit.trains = []
	for t in data.trains:
		Transit.trains.append(_sanitize_train(t))
	Transit._next_id = _ti(data.train_next_id)
	return true

# ── Original `.stt` loader (build_game.py interchange format) ───────────────
# The .stt stores the entire galaxy (1000+ planets), trains, discovery, ledgers,
# and unlock flags as plain JSON. We populate the port's autoloads directly. The
# reduced port sim ignores train fields it doesn't model (maintenance, etc.).
func load_stt(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(d) != TYPE_DICTIONARY or not d.has("galaxy"):
		return false
	return _load_stt_data(d)

func _load_stt_data(d: Dictionary) -> bool:
	var g: Dictionary = d.galaxy
	if Galaxy._rng_state == 0:
		Galaxy._rng_state = 0x2545F491  # seed the LCG so build_train's random() works
	# ── Stars (fields map 1:1) ──
	var stars: Array = []
	for s in g.get("stars", []):
		var sd: Dictionary = s
		sd["id"] = _ti(sd.get("id", 0))
		sd["radius"] = float(sd.get("radius", 100.0))
		sd["x"] = float(sd.get("x", 0.0)); sd["y"] = float(sd.get("y", 0.0))
		sd["planetIds"] = _tia(sd.get("planetIds", []))
		stars.append(sd)
	Galaxy.stars = stars
	# ── Planets (reconstruct biome dict from type.id; recompute supply/demand rates) ──
	var planets: Array = []
	for p in g.get("planets", []):
		var pd: Dictionary = p
		pd["id"] = _ti(pd.get("id", 0))
		pd["starId"] = _ti(pd.get("starId", 0))
		pd["orbitRadius"] = float(pd.get("orbitRadius", 100.0))
		pd["orbitAngle"] = float(pd.get("orbitAngle", 0.0))
		pd["orbitSpeed"] = float(pd.get("orbitSpeed", 0.0))
		pd["radius"] = float(pd.get("radius", 50.0))
		pd["x"] = float(pd.get("x", 0.0)); pd["y"] = float(pd.get("y", 0.0))
		var ty = pd.get("type", {})
		pd["type"] = Tuning.ptype(String(ty.id)) if (ty is Dictionary and ty.has("id")) else Tuning.ptype("rocky")
		pd["isAlienRelic"] = bool(pd.get("isAlienRelic", false))
		pd["supplyRate"] = Economy.compute_supply_rate(pd)
		pd["demandRate"] = Economy.compute_demand_rate(pd)
		planets.append(pd)
	Galaxy.planets = planets
	var bhs: Array = []
	for b in g.get("blackHoles", []):
		var bd: Dictionary = b
		bd["x"] = float(bd.get("x", 0.0)); bd["y"] = float(bd.get("y", 0.0)); bd["radius"] = float(bd.get("radius", 100.0))
		bhs.append(bd)
	Galaxy.black_holes = bhs
	Galaxy.home_star_id = _ti(g.get("homeStarId", 0))
	Galaxy.origen_id = _ti(g.get("origenId", 0))
	Galaxy._seed = _ti(d.get("seed", Galaxy._seed))  # restore for harness round-trip
	# ── Scalars ──
	GameState.credits = _ti(d.get("credits", 250000))
	GameState.stardate = float(d.get("stardate", 829.0))
	GameState.corp_name = String(d.get("corpName", "STELLAR TRANSIT CO."))
	GameState.game_speed_idx = clampi(_ti(d.get("gameSpeedIdx", 2)), 0, Tuning.SPEED_OPTS.size() - 1)
	GameState.total_passengers_delivered = _ti(d.get("_totalPassengersDelivered", 0))
	GameState.any_cargo_produced = bool(d.get("_anyCargoProduced", false))
	GameState.finance_ledger = d.get("financeLedger", [])
	GameState.purchase_ledger = d.get("purchaseLedger", [])
	GameState.corp_value_history = {}
	var cvh = d.get("corpValueHistory", {})
	if cvh is Dictionary:
		for k in cvh.keys():
			GameState.corp_value_history[_ti(k)] = _ti(cvh[k])
	# ── Unlocks (from the _*Unlocked flags) ──
	GameState.unlocked_engines = {"engine_constellation": true, "engine_galaxy": true}
	if bool(d.get("_classJEngineUnlocked", false)): GameState.unlocked_engines["engine_classJ"] = true
	if bool(d.get("_classREngineUnlocked", false)): GameState.unlocked_engines["engine_classR"] = true
	if bool(d.get("_N700EngineUnlocked", false)): GameState.unlocked_engines["engine_N700"] = true
	GameState.unlocked_cars = {"car_passenger": true, "car_mail": true, "car_water_tank": true, "car_ore": true, "caboose": true}
	var carflags := {"_ironCarUnlocked": "car_iron", "_steelCarUnlocked": "car_steel", "_glassCarUnlocked": "car_glass", "_hazmatCarUnlocked": "car_hazmat", "_machineryCarUnlocked": "car_machinery", "_cargoCarUnlocked": "car_cargo", "_livestockCarUnlocked": "car_livestock", "_flowersCarUnlocked": "car_flowers", "_medicalCarUnlocked": "car_medical", "_grainCarUnlocked": "car_grain", "_fruitCarUnlocked": "car_fruit", "_royalCarUnlocked": "car_royal"}
	for fk in carflags:
		if bool(d.get(fk, false)):
			GameState.unlocked_cars[carflags[fk]] = true
	GameState.unlocked_upgrades = {}
	if bool(d.get("_largeStationUnlocked", false)): GameState.unlocked_upgrades["large_station"] = true
	if bool(d.get("_terminalUnlocked", false)): GameState.unlocked_upgrades["terminal"] = true
	# ── Discovery (arrays → {id:true}) ──
	Discovery.discovered_planet_ids = _id_set(d.get("discoveredPlanetIds", []))
	Discovery.visited_planet_ids = _id_set(d.get("visitedPlanetIds", []))
	Discovery.revealed_star_ids = _id_set(d.get("revealedStarIds", []))
	# ── AI corp ──
	var ac = d.get("_aiCorp", null)
	if ac is Dictionary and not (ac as Dictionary).is_empty():
		AICorp.active = true
		AICorp.difficulty = String(d.get("_aiDifficulty", "normal"))
		AICorp.credits = _ti(ac.get("credits", 0))
		AICorp.total_revenue = _ti(ac.get("totalRevenue", 0))
		AICorp.home_star_id = _ti(ac.get("homeStarId", -1))
		AICorp.corp_name = String(ac.get("name", Tuning.AI_CORP_NAMES.get(AICorp.difficulty, "Rival Corp")))
	else:
		AICorp.active = false
	# ── Trains (best-effort; the reduced sim re-orbits them at their stop) ──
	Transit.trains = []
	Transit._next_id = 0
	for t in d.get("trains", []):
		if t is Dictionary:
			_load_stt_train(t)
	# ── Missions ──
	# Port-saved format is {active, completed, pending} (a Dict). Restore it fully
	# (the harness round-trip checks a completed mission survives). Original-game
	# `.stt` files store missions as a LIST with a different objective shape —
	# clear those to avoid mission-update/draw crashes on unknown defs.
	Missions.active = []
	Missions.completed = {}
	Missions._pending_intros = []
	var mz = d.get("missions", null)
	if mz is Dictionary and (mz as Dictionary).has("completed"):
		for mid in mz.get("completed", []):
			Missions.completed[String(mid)] = true
		for m in mz.get("active", []):
			if m is Dictionary:
				m["id"] = String(m.get("id", ""))
				if m.has("targetPlanetId"):
					m["targetPlanetId"] = _ti(m.get("targetPlanetId", -1))
				Missions.active.append(m)
		for mid in mz.get("pending", []):
			Missions._pending_intros.append(String(mid))
	# ── Camera (applied by GalaxyView2D on enter_galaxy via GameState.pending_cam) ──
	var cam = d.get("cam", null)
	if cam is Dictionary:
		GameState.pending_cam = {"x": float(cam.get("x", 0.0)), "y": float(cam.get("y", 0.0)), "scale": float(cam.get("scale", 0.001))}
	GameState.phase = GameState.Phase.GALAXY
	GameState.gs = "galaxy"
	return true

func _planet_idx_safe(pid: int) -> int:
	if pid >= 0 and pid < Galaxy.planets.size() and int(Galaxy.planets[pid].id) == pid:
		return pid
	for i in Galaxy.planets.size():
		if int(Galaxy.planets[i].id) == pid:
			return i
	return -1

func _load_stt_train(t: Dictionary) -> void:
	var cars_all: Array = t.get("cars", [])
	if cars_all.is_empty():
		return
	var engine := String(cars_all[0])
	var cars: Array = []
	for i in range(1, cars_all.size()):
		cars.append(String(cars_all[i]))
	var pid := _ti(t.get("planetId", Galaxy.origen_id))
	if _planet_idx_safe(pid) < 0:
		pid = Galaxy.origen_id
	if _planet_idx_safe(pid) < 0:
		return
	var nt := Transit.build_train(pid, engine, cars, bool(t.get("isPlayer", true)))
	nt["name"] = String(t.get("name", "TRAIN %d" % int(nt.id)))
	nt["color"] = String(t.get("color", "#7eddc8"))
	var cc = t.get("carCargo", [])
	if cc is Array:
		for i in range(min(cc.size(), (nt.cars as Array).size())):
			if cc[i] != null:
				nt.carCargo[i] = cc[i]
	var r = t.get("route", null)
	if r is Dictionary:
		var stops: Array = []
		for sid in r.get("stops", []):
			var s := _ti(sid)
			if _planet_idx_safe(s) >= 0:
				stops.append(s)
		if stops.size() >= 2:
			Transit.assign_route(nt, stops)

# ── helpers: JSON parses numbers as float; restore ints ────────────────────
func _ti(v) -> int:
	return int(round(float(v)))

func _tia(arr: Array) -> Array:
	var out := []
	for v in arr:
		out.append(_ti(v))
	return out

func _bool_set(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d.keys():
		out[String(k)] = true
	return out

func _id_set(arr) -> Dictionary:
	var out := {}
	for v in arr:
		out[_ti(v)] = true
	return out

func _sanitize_train(t: Dictionary) -> Dictionary:
	t["id"] = _ti(t.id)
	t["planetId"] = _ti(t.planetId)
	t["targetId"] = _ti(t.targetId)
	t["phase"] = _ti(t.phase)
	t["orbitR"] = float(t.orbitR)
	t["orbitAngle"] = float(t.orbitAngle)
	t["x"] = float(t.x)
	t["y"] = float(t.y)
	t["carSrc"] = _tia(t.carSrc)
	if t.route != null:
		t.route["idx"] = _ti(t.route.idx)
		t.route["stops"] = _tia(t.route.stops)
	return t
