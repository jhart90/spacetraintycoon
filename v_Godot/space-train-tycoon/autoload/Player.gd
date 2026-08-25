extends Node
## Player — interactive player commands (PLAN Phase 4): build station / upgrade /
## large station, buy train, assign route. Each validates cost + prerequisites,
## mutates state, recomputes affected economy, and fires mission hooks. The UI
## (HUD buttons / hotkeys) calls these; the harness drives them headlessly.

signal action_done(msg: String)
signal action_failed(reason: String)

func _pidx(pid: int) -> int:
	if pid >= 0 and pid < Galaxy.planets.size() and Galaxy.planets[pid].id == pid:
		return pid
	for i in Galaxy.planets.size():
		if Galaxy.planets[i].id == pid:
			return i
	return -1

func _ok(msg: String) -> bool:
	action_done.emit(msg)
	return true

func _fail(reason: String) -> bool:
	action_failed.emit(reason)
	return false

func can_afford(c: int) -> bool:
	return GameState.credits >= c

# ── Build a station (build_game.py _stationBuildCost) ─────────────────────
func build_station(planet_id: int) -> bool:
	var idx := _pidx(planet_id)
	if idx < 0:
		return _fail("no such planet")
	var p: Dictionary = Galaxy.planets[idx]
	if p.hasStation:
		return _fail("already has a station")
	if not can_afford(Tuning.STATION_COST):
		return _fail("not enough credits")
	GameState.credits -= Tuning.STATION_COST
	p.hasStation = true
	p.playerBuiltStation = true
	p.demandRate = Economy.compute_demand_rate(p)  # station iron floor etc.
	Missions.on_station_built(p)
	return _ok("Station built at %s" % p.name)

# ── Build an industrial/agri upgrade (foundry, glassworks, …) ─────────────
func build_upgrade(planet_id: int, upgrade_id: String) -> bool:
	var idx := _pidx(planet_id)
	if idx < 0:
		return _fail("no such planet")
	var p: Dictionary = Galaxy.planets[idx]
	if not p.hasStation:
		return _fail("build a station first")
	if upgrade_id in p.get("upgrades", []):
		return _fail("already built")
	var biome = Tuning.UPGRADE_BIOME.get(upgrade_id, null)
	if biome != null and p.type.id != biome:
		return _fail("wrong biome for %s" % upgrade_id)
	var cost := int(Tuning.UPGRADE_COST.get(upgrade_id, 10000))
	if not can_afford(cost):
		return _fail("not enough credits")
	GameState.credits -= cost
	var ups: Array = p.get("upgrades", [])
	ups.append(upgrade_id)
	p.upgrades = ups
	p.supplyRate = Economy.compute_supply_rate(p)
	p.demandRate = Economy.compute_demand_rate(p)
	Missions.on_upgrade_built(p, upgrade_id)
	return _ok("%s built at %s" % [upgrade_id, p.name])

func build_large_station(planet_id: int) -> bool:
	var idx := _pidx(planet_id)
	if idx < 0:
		return _fail("no such planet")
	var p: Dictionary = Galaxy.planets[idx]
	if not p.hasStation or p.get("hasLargeStation", false):
		return _fail("needs a station / already large")
	if not GameState.unlocked_upgrades.has("large_station"):
		return _fail("Large Station not unlocked yet")
	if not can_afford(Tuning.LARGE_STATION_COST):
		return _fail("not enough credits")
	GameState.credits -= Tuning.LARGE_STATION_COST
	p.hasLargeStation = true
	p.demandRate = Economy.compute_demand_rate(p)  # steel floor
	Missions.on_large_station_built(p)
	return _ok("Large Station at %s" % p.name)

# ── Buy a train (engine + cars) ───────────────────────────────────────────
func train_cost(engine: String, cars: Array) -> int:
	var c := int(Tuning.ENGINE_COSTS.get(engine, 10000))
	for ct in cars:
		c += 10000 if ct == "car_royal" else Tuning.CAR_COST
	return c

## Returns the new train dict, or {} on failure.
func build_train(planet_id: int, engine: String, cars: Array) -> Dictionary:
	if not GameState.unlocked_engines.has(engine):
		_fail("engine %s not unlocked" % engine)
		return {}
	if cars.size() > int(Tuning.ENGINE_MAX_CARS.get(engine, 6)):
		_fail("too many cars for %s" % engine)
		return {}
	var cost := train_cost(engine, cars)
	if not can_afford(cost):
		_fail("not enough credits")
		return {}
	if _pidx(planet_id) < 0:
		_fail("no such planet")
		return {}
	GameState.credits -= cost
	var t := Transit.build_train(planet_id, engine, cars, true)
	_ok("Train built (%d cars)" % cars.size())
	return t

func assign_route(train_id: int, stops: Array) -> bool:
	for t in Transit.trains:
		if t.id == train_id and t.isPlayer:
			Transit.assign_route(t, stops)
			return _ok("Route assigned")
	return _fail("train not found")
