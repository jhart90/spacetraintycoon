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

const SAVE_PATH := "user://savegame.json"
const VERSION := 1

func save_game(path: String = SAVE_PATH) -> bool:
	var planets := []
	for p in Galaxy.planets:
		planets.append({
			"id": p.id, "orbitAngle": p.orbitAngle,
			"supply": p.get("supply", {}), "demand": p.get("demand", {}),
			"hasStation": p.hasStation, "isAlienRelic": p.isAlienRelic,
			"upgrades": p.get("upgrades", []),
		})
	var data := {
		"version": VERSION, "seed": Galaxy._seed,
		"stardate": GameState.stardate, "credits": GameState.credits, "speed": GameState.game_speed_idx,
		"unlocked_engines": GameState.unlocked_engines, "unlocked_cars": GameState.unlocked_cars,
		"unlocked_upgrades": GameState.unlocked_upgrades, "any_cargo_produced": GameState.any_cargo_produced,
		"discovery": {
			"visited": Discovery.visited_planet_ids.keys(),
			"discovered": Discovery.discovered_planet_ids.keys(),
			"stars": Discovery.revealed_star_ids.keys(),
		},
		"missions": {"active": Missions.active, "completed": Missions.completed.keys(), "pending": Missions._pending_intros},
		"ai": {"active": AICorp.active, "difficulty": AICorp.difficulty, "credits": AICorp.credits,
			"total_revenue": AICorp.total_revenue, "home": AICorp.home_star_id, "tick_acc": AICorp._tick_acc},
		"trains": Transit.trains, "train_next_id": Transit._next_id,
		"planets": planets,
	}
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data))
	f.close()
	return true

func load_game(path: String = SAVE_PATH) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(data) != TYPE_DICTIONARY:
		return false

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
