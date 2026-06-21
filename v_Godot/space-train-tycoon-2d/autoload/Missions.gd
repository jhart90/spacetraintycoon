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
	"research_royal_car": {"cars": ["car_royal"]},
}

# Active missions: each {id, status, objectives:[{id,done}], targetPlanetId, ...}
var active: Array = []
var completed: Dictionary = {}   # id -> true
var _pending_intros: Array = []  # ids queued (car-gated until their car unlocks)

signal mission_introduced(id: String)
signal mission_completed(id: String, reward: int)

func start_new_game() -> void:
	active = []
	completed = {}
	_pending_intros = []
	# Give the player a first goal (build_foundry's JS trigger is a tutorial
	# timer; here we surface it at game start so the build-chain is reachable).
	queue_intro("build_foundry")

func def_for(id: String) -> Dictionary:
	for d in Data.MISSION_DEFS:
		if d.id == id:
			return d
	return {}

# ── Introduction (car-gated — build_game.py _missionCarGateOk) ─────────────
func queue_intro(id: String) -> void:
	if is_active(id) or completed.has(id) or id in _pending_intros:
		return
	_pending_intros.append(id)
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
	active.append({"id": id, "status": "active", "objectives": objs, "targetPlanetId": -1})
	mission_introduced.emit(id)

# Call when a car unlocks so gated intros can promote (Phase 4 hook).
func on_car_unlocked(car_type: String) -> void:
	GameState.unlocked_cars[car_type] = true
	_try_promote_intros()

## Delivery-driven mission triggers (build_game.py updateMissions intro gates).
## Called from Transit when a player car unloads. Wires the counter-based intros
## that don't need station/foundry gameplay. (More triggers hook here as the
## station/refining systems land.)
func on_delivery(cargo: String, _planet_id: int) -> void:
	# research_royal_car: introduced at 100 passengers delivered (L21261).
	if cargo == "passengers" and GameState.total_passengers_delivered >= 100:
		queue_intro("research_royal_car")

# ── Build-action hooks (Player calls these; advance build-based objectives) ─
func on_station_built(p: Dictionary) -> void:
	if is_active("build_foundry") and p.type.id == "desert":
		mark_objective("build_foundry", "station_foundry_planet")

func on_upgrade_built(p: Dictionary, upgrade_id: String) -> void:
	if is_active("build_foundry") and upgrade_id == "iron_foundry" and p.type.id == "desert":
		mark_objective("build_foundry", "construct_foundry")

func on_large_station_built(_p: Dictionary) -> void:
	if is_active("upgrade_station"):
		mark_objective("upgrade_station", "upgrade_to_large_station")

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
