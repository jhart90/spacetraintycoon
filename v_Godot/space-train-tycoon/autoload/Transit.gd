extends Node
## Transit — train model + route phase machine + cargo delivery.
## CORE port of build_game.py updateTrain / cargo ops (PLAN Phase 2 slice 3,
## code map §6).
##
## IMPLEMENTED: train data model; route as an ordered stop cycle; ORBIT↔TRANSIT
## phase machine; constant max-speed movement toward each stop's LIVE position
## (planets keep orbiting); per-car cargo load/unload using the EXACT revenue
## formula (Economy.compute_cargo_revenue) → credits update.
##
## DEFERRED (the §6 "hairiest math", Phase 2 refinement): acceleration/decel
## ramp (ENGINE_ACCEL_RATE), queueing/descending orbit phases, two-pass
## occupancy map, live-tangent multi-car positioning, maintenance/repair,
## per-tick supply/demand accumulation. A single train builds, routes, orbits,
## transits, and delivers with correct revenue — the Phase-2 exit behaviour.

enum Phase { ORBIT, TRANSIT }

var trains: Array = []
var _next_id: int = 0

signal train_delivered(train_id: int, planet_id: int, cargo: String, revenue: int)

func reset() -> void:
	trains = []
	_next_id = 0

func _planet_idx(pid: int) -> int:
	if pid >= 0 and pid < Galaxy.planets.size() and Galaxy.planets[pid].id == pid:
		return pid
	for i in Galaxy.planets.size():
		if Galaxy.planets[i].id == pid:
			return i
	return -1

func _orbit_radius_for(p: Dictionary) -> float:
	return maxf(p.radius * 3.0, 200.0)

## Build a train orbiting `planet_id`. car_types: array of car/engine type strings.
func build_train(planet_id: int, engine: String, car_types: Array, is_player: bool = true) -> Dictionary:
	var p: Dictionary = Galaxy.planets[_planet_idx(planet_id)]
	var t := {
		"id": _next_id, "isPlayer": is_player, "engine": engine,
		"cars": car_types.duplicate(),
		"carCargo": [], "carSrc": [],
		"planetId": planet_id, "targetId": -1,
		"orbitR": _orbit_radius_for(p), "orbitAngle": random_angle(),
		"x": p.x, "y": p.y, "phase": Phase.ORBIT, "route": null,
		"speed": 0.0,   # current transit speed (world-units / frame-unit)
		"dwell": 0.0,   # orbital arc swept at the current stop
		"orbitDir": 1.0,
	}
	for _i in car_types.size():
		t.carCargo.append(null)
		t.carSrc.append(-1)
	_next_id += 1
	_place_in_orbit(t, p)
	trains.append(t)
	return t

func random_angle() -> float:
	return Galaxy.random() * TAU

## Assign a repeating route (array of planet ids). Loads at the current stop,
## then departs toward the next.
func assign_route(t: Dictionary, stops: Array) -> void:
	t.route = {"stops": stops.duplicate(), "idx": stops.find(t.planetId)}
	if t.route.idx < 0:
		t.route.idx = 0
	var p: Dictionary = Galaxy.planets[_planet_idx(t.planetId)]
	_cargo_ops(t, p)
	_depart(t)

const DWELL_ARC := PI * 0.6      # arc swept at a stop before departing
const ORBIT_OMEGA_MULT := 3.0    # train orbits a bit faster than a planet, for a lively read
const ORBIT_GAP := 120.0         # radial spacing for queued trains at the same planet

## How many OTHER trains are already orbiting `pid` — arriving trains stack into
## higher concentric orbits (a lightweight stand-in for the §6 queueing phase).
func _orbit_occupancy(self_t: Dictionary, pid: int) -> int:
	var n := 0
	for o in trains:
		if o.id != self_t.id and o.phase == Phase.ORBIT and o.planetId == pid:
			n += 1
	return n

func _depart(t: Dictionary) -> void:
	if t.route == null:
		return
	var stops: Array = t.route.stops
	var n := stops.size()
	for _k in n:
		t.route.idx = (t.route.idx + 1) % n
		var cand: int = stops[t.route.idx]
		if cand != t.planetId:
			t.targetId = cand
			t.phase = Phase.TRANSIT
			t.speed = _orbital_speed(t)  # leave the orbit at orbital speed, then accelerate
			return
	t.phase = Phase.ORBIT
	t.targetId = -1

func _arrive(t: Dictionary, p: Dictionary) -> void:
	t.planetId = t.targetId
	t.targetId = -1  # ORBIT phase departs to the next stop once dwell completes
	t.orbitR = _orbit_radius_for(p) + _orbit_occupancy(t, t.planetId) * ORBIT_GAP
	# Enter orbit at the angle we approached from → position is continuous.
	t.orbitAngle = atan2(t.y - p.y, t.x - p.x)
	t.orbitDir = 1.0 if (t.id % 2 == 0) else -1.0
	t.dwell = 0.0
	_place_in_orbit(t, p)
	_cargo_ops(t, p)  # load/unload happens on orbital insertion
	t.phase = Phase.ORBIT

func _place_in_orbit(t: Dictionary, p: Dictionary) -> void:
	t.x = p.x + t.orbitR * cos(t.orbitAngle)
	t.y = p.y + t.orbitR * sin(t.orbitAngle)

func _orbital_speed(t: Dictionary) -> float:
	return Tuning.ORB_SPD * t.orbitR  # linear speed at orbit radius (v = ωr)

# ── Per-tick advance ──────────────────────────────────────────────────────
func tick(dtG: float) -> void:
	for t in trains:
		_tick_train(t, dtG)

func _tick_train(t: Dictionary, dtG: float) -> void:
	if t.phase == Phase.ORBIT:
		# Circle the (itself-orbiting) planet; depart after sweeping DWELL_ARC.
		var p: Dictionary = Galaxy.planets[_planet_idx(t.planetId)]
		var dtheta := Tuning.ORB_SPD * ORBIT_OMEGA_MULT * dtG
		t.orbitAngle += dtheta * t.orbitDir
		t.dwell += dtheta
		_place_in_orbit(t, p)
		if t.route != null and t.targetId == -1 and t.dwell >= DWELL_ARC:
			_depart(t)
		return

	# TRANSIT — accelerate out, cruise, decelerate onto the target orbit.
	var tp: Dictionary = Galaxy.planets[_planet_idx(t.targetId)]
	var dx: float = tp.x - t.x
	var dy: float = tp.y - t.y
	var dist := sqrt(dx * dx + dy * dy)
	var arrive_r := _orbit_radius_for(tp)
	var v_orbit := Tuning.ORB_SPD * arrive_r
	var v_max: float = float(Tuning.ENGINE_MAX_SPD.get(t.engine, 4.0))
	var accel := v_max * 0.03  # per frame-unit; ~smooth ramp to cruise
	var remaining := dist - arrive_r
	# Distance needed to brake from current speed down to orbital speed.
	var brake_dist := maxf(0.0, (t.speed * t.speed - v_orbit * v_orbit) / (2.0 * accel))
	if remaining > brake_dist:
		t.speed = minf(v_max, t.speed + accel * dtG)
	else:
		t.speed = maxf(v_orbit, t.speed - accel * dtG)
	var step: float = t.speed * dtG
	if dist <= arrive_r or dist <= step:
		_arrive(t, tp)
	else:
		t.x += dx / dist * step
		t.y += dy / dist * step

# ── Cargo ops at a stop: unload (revenue) then load (build_game.py cargo ops) ─
func _cargo_ops(t: Dictionary, p: Dictionary) -> void:
	var supplyRate: Dictionary = p.get("supplyRate", {})
	var demandRate: Dictionary = p.get("demandRate", {})
	for i in t.cars.size():
		var carType: String = t.cars[i]
		var cargoType = Tuning.CAR_CARGO_TYPE.get(carType, null)
		if cargoType == null:
			continue  # an engine or non-cargo car
		# Unload: this car is loaded and the planet demands that cargo.
		if t.carCargo[i] != null and demandRate.has(t.carCargo[i]):
			var src: Dictionary = {}
			if t.carSrc[i] >= 0:
				src = Galaxy.planets[_planet_idx(t.carSrc[i])]
			var rev := Economy.compute_cargo_revenue(carType, t.carCargo[i], p, src)
			var delivered_cargo: String = t.carCargo[i]
			if t.isPlayer:
				GameState.credits += rev
				if delivered_cargo == "passengers":
					GameState.total_passengers_delivered += 1
				GameState.player_delivered.emit(rev)
				Missions.on_delivery(delivered_cargo, p.id)
			elif AICorp.active:
				AICorp.credits += rev
				AICorp.total_revenue += rev
			train_delivered.emit(t.id, p.id, t.carCargo[i], rev)
			t.carCargo[i] = null
			t.carSrc[i] = -1
		# Load: this car is empty and the planet supplies its native cargo.
		if t.carCargo[i] == null and supplyRate.has(cargoType):
			t.carCargo[i] = cargoType
			t.carSrc[i] = p.id
