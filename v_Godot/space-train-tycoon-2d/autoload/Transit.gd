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
		"fromId": -1, "toId": -1,
		"transitDist": 0.0, "transitSpeed": 0.0, "arrivalOrbitR": 0.0,
		"orbitSpun": 0.0,
		# Per-car cargo ops (build_game.py:7380): phase "" | "unloading" | "loading".
		"cargoPhase": "", "cargoQueue": [], "cargoTimer": 0.0, "_cargoChecked": false,
		# Maintenance + lifetime financials (build_game.py:8955).
		"maintenance": 1.0, "distSinceMaint": 0.0, "totalDist": 0.0,
		"totalRevenue": 0, "totalCosts": 0, "_engineBornSd": GameState.stardate,
		"_engineFailureSd": GameState.stardate + 30.0 + Galaxy.random() * 40.0, "_engineFailed": false,
		# Trains-list window stats (build_game.py:8994).
		"segments": 0, "orbitCounts": {},
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

signal route_rejected(reason: String)  # a hop crosses a star or exceeds engine range

# True if the segment a→b passes within any star's / black hole's radius
# (build_game.py segmentBlockedByStar:15100). Returns the blocker name or "".
func segment_blocked_by_star(ax: float, ay: float, bx: float, by: float) -> String:
	var sdx := bx - ax
	var sdy := by - ay
	var len2 := sdx * sdx + sdy * sdy
	for star in Galaxy.stars:
		var r: float = float(star.radius)
		var tt := 0.0 if len2 == 0.0 else clampf(((float(star.x) - ax) * sdx + (float(star.y) - ay) * sdy) / len2, 0.0, 1.0)
		if Vector2(float(star.x) - (ax + tt * sdx), float(star.y) - (ay + tt * sdy)).length() < r:
			return String(star.name)
	for bh in Galaxy.black_holes:
		var br: float = float(bh.radius)
		var tb := 0.0 if len2 == 0.0 else clampf(((float(bh.x) - ax) * sdx + (float(bh.y) - ay) * sdy) / len2, 0.0, 1.0)
		if Vector2(float(bh.x) - (ax + tb * sdx), float(bh.y) - (ay + tb * sdy)).length() < br:
			return "a black hole"
	return ""

# Validate a route's hops against star-blocking + engine max range
# (build_game.py transitPathBlocked:15134). Returns "" if all hops are clear,
# else a human-readable reason for the first blocked hop.
func route_block_reason(engine: String, stops: Array) -> String:
	var max_range: float = float(Tuning.ENGINE_MAX_RANGE.get(engine, 1e20))
	for i in range(stops.size() - 1):
		var a := _planet_idx(int(stops[i]))
		var b := _planet_idx(int(stops[i + 1]))
		if a < 0 or b < 0:
			continue
		var pa: Dictionary = Galaxy.planets[a]
		var pb: Dictionary = Galaxy.planets[b]
		var d := Vector2(float(pa.x) - float(pb.x), float(pa.y) - float(pb.y)).length()
		if d > max_range:
			return "%s is out of range for the %s" % [String(pb.name).to_upper(), String(engine).trim_prefix("engine_").to_upper()]
		var blk := segment_blocked_by_star(float(pa.x), float(pa.y), float(pb.x), float(pb.y))
		if blk != "":
			return "the route to %s is blocked by %s" % [String(pb.name).to_upper(), blk]
	return ""

## Assign a repeating route (array of planet ids). Loads at the current stop,
## then departs toward the next.
func assign_route(t: Dictionary, stops: Array) -> void:
	# Reject routes that fly through a star/black hole or exceed engine range
	# (the original reroutes via multi-hop; this port has no planner, so it
	# refuses the route — matching the "couldn't find a viable ROUTE" fallback).
	var reason := route_block_reason(String(t.get("engine", "engine_galaxy")), stops)
	if reason != "":
		route_rejected.emit(reason)
		return
	t.route = {"stops": stops.duplicate(), "idx": stops.find(t.planetId)}
	if t.route.idx < 0:
		t.route.idx = 0
	t.targetId = -1
	t.orbitSpun = 0.0
	t._cargoChecked = false  # run cargo ops at this first stop while orbiting
	t.cargoPhase = ""
	t.cargoQueue = []
	t.phase = Phase.ORBIT  # orbit (loading/unloading), then depart tangentially
	if bool(t.get("isPlayer", false)):
		Missions.on_route_assigned(stops)

# Transit motion model (build_game.py §6 / code_transit_architecture): trains
# travel the EXTERNAL COMMON TANGENT between the departure and arrival orbit
# circles (recomputed live so planet drift never causes a jump). They leave the
# orbit tangentially at orbital speed, accelerate to the engine's max, cruise,
# decelerate to match the arrival orbital speed, and slide onto the next orbit.
const ORBIT_GAP := 120.0          # radial spacing for queued trains at the same planet
const MIN_ORBIT_SPUN := TAU * 0.6 # orbit at least this far before departing (dwell)
const TRANSIT_ACCEL := 0.0009     # build_game.py:1033 (0.00018*5), constellation base
const ENGINE_ACCEL_MULT := {
	"engine_constellation": 1.0, "engine_galaxy": 2.0, "engine_classJ": 4.0,
	"engine_classR": 8.0, "engine_N700": 12.0,
}

func _engine_accel(engine: String) -> float:
	return TRANSIT_ACCEL * float(ENGINE_ACCEL_MULT.get(engine, 1.0))

## How many OTHER trains are already orbiting `pid` — arriving trains stack into
## higher concentric orbits (a lightweight stand-in for the §6 queueing phase).
func _orbit_occupancy(self_t: Dictionary, pid: int) -> int:
	var n := 0
	for o in trains:
		if o.id != self_t.id and o.phase == Phase.ORBIT and o.planetId == pid:
			n += 1
	return n

func _place_in_orbit(t: Dictionary, p: Dictionary) -> void:
	t.x = p.x + t.orbitR * cos(t.orbitAngle)
	t.y = p.y + t.orbitR * sin(t.orbitAngle)

# computeLiveTangent (code_transit_architecture): external common tangent between
# two orbit circles. Both touch points sit at the same orbit angle nAngle, so the
# line ax→bx is tangent to BOTH circles — and the orbital velocity at each touch
# point is along that line (seamless orbit↔tangent transitions). {} if degenerate.
func _compute_tangent(from_p: Dictionary, to_p: Dictionary, from_r: float, to_r: float) -> Dictionary:
	var dx: float = to_p.x - from_p.x
	var dy: float = to_p.y - from_p.y
	var d := sqrt(dx * dx + dy * dy)
	if d < 1.0:
		return {}
	var ratio := (from_r - to_r) / d
	if ratio < -1.0 or ratio > 1.0:
		return {}
	var n_angle := atan2(dy, dx) + acos(ratio)
	var ax: float = from_p.x + from_r * cos(n_angle)
	var ay: float = from_p.y + from_r * sin(n_angle)
	var bx: float = to_p.x + to_r * cos(n_angle)
	var by: float = to_p.y + to_r * sin(n_angle)
	return {"ax": ax, "ay": ay, "bx": bx, "by": by,
		"tanAngle": n_angle, "tanLen": sqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay))}

func _peek_next(t: Dictionary) -> int:
	var stops: Array = t.route.stops
	var n := stops.size()
	for k in n:
		var idx: int = (int(t.route.idx) + 1 + k) % n
		if int(stops[idx]) != t.planetId:
			return int(stops[idx])
	return -1

func _begin_transit(t: Dictionary, to_id: int, arr_r: float) -> void:
	t.fromId = t.planetId
	t.toId = to_id
	t.targetId = to_id
	t.arrivalOrbitR = arr_r
	t.transitDist = 0.0
	t.transitSpeed = Tuning.ORB_SPD * t.orbitR  # depart at orbital linear speed (seamless)
	t.phase = Phase.TRANSIT

func _arrive(t: Dictionary, tp: Dictionary, ang: float) -> void:
	t.planetId = t.toId
	t.fromId = -1
	t.toId = -1
	t.targetId = -1
	t.orbitR = t.arrivalOrbitR            # the radius the tangent landed on (continuous)
	t.orbitAngle = ang
	t.orbitSpun = 0.0
	t.transitSpeed = 0.0
	t.phase = Phase.ORBIT
	t._cargoChecked = false  # load/unload car-by-car while orbiting this stop
	t.cargoPhase = ""
	t.cargoQueue = []
	# Per-train stats for the trains-list window (build_game.py orbitCounts/segments
	# ~8994): each arrival = one completed transit segment + one orbit of this planet.
	t.segments = int(t.get("segments", 0)) + 1
	var _ocounts: Dictionary = t.get("orbitCounts", {})
	_ocounts[int(t.planetId)] = int(_ocounts.get(int(t.planetId), 0)) + 1
	t.orbitCounts = _ocounts
	# Exploration: a player train entering orbit visits the planet — discovery,
	# fog reveal, first-visit credit reward + car/upgrade unlocks, mission arming
	# (build_game.py trackVisit, called at every arrival ~15796).
	if bool(t.get("isPlayer", false)):
		Discovery.track_visit(int(t.planetId))
	if t.route != null:
		var ix: int = t.route.stops.find(t.planetId)
		if ix >= 0:
			t.route.idx = ix
	# Maintenance repair on orbit entry at a station (build_game.py:15335). Cost
	# scales with damage × car count × engine repair-mult × repair-drones discount.
	if bool(t.isPlayer) and float(t.get("maintenance", 1.0)) < 1.0 and (bool(tp.get("hasStation", false)) or bool(tp.get("aiHasStation", false))):
		var rdmg: float = 1.0 - float(t.maintenance)
		var rmult: float = float(Tuning.ENGINE_REPAIR_MULT.get(String(t.engine), 1.0))
		var maint_mult := 0.75 if (tp.get("upgrades", []) as Array).has("repair_drones") else 1.0
		var rcost := int(round(rdmg * (t.cars.size() + 1) * Tuning.REPAIR_COST_PER_MAINT * rmult * maint_mult))
		if rcost > 0:
			GameState.credits -= rcost
			t.totalCosts = int(t.get("totalCosts", 0)) + rcost
			GameState.finance_ledger.append({"sd": GameState.stardate, "cargoType": "maintenance", "trainName": String(t.get("name", "")), "planetId": int(tp.id), "starId": int(tp.get("starId", -1)), "revenue": 0, "cost": rcost})
		t.maintenance = 1.0
		t.distSinceMaint = 0.0
	_place_in_orbit(t, tp)

# Current segment's live external tangent (for route-line drawing), or {}.
func segment_tangent(t: Dictionary) -> Dictionary:
	if int(t.phase) != Phase.TRANSIT or int(t.toId) < 0:
		return {}
	return _compute_tangent(Galaxy.planets[_planet_idx(int(t.fromId))], Galaxy.planets[_planet_idx(int(t.toId))], float(t.orbitR), float(t.arrivalOrbitR))

# Faithful per-car world position + heading at cumulative offset `off` behind the
# engine (getTrainCarPos, code_transit_architecture §133): the consist snakes
# along the real path — departure orbit → tangent line → arrival orbit.
func car_path_pos(t: Dictionary, off: float) -> Array:
	# ORBIT (or parked): trail behind along the orbit. Orbit is CW (angle
	# decreasing) so the tail sits at a LARGER angle (+off/r).
	if int(t.phase) != Phase.TRANSIT or int(t.toId) < 0:
		var p: Dictionary = Galaxy.planets[_planet_idx(int(t.planetId))]
		var orbit_r: float = maxf(1.0, float(t.orbitR))
		var ang: float = float(t.orbitAngle) + off / orbit_r
		return [Vector2(float(p.x) + float(t.orbitR) * cos(ang), float(p.y) + float(t.orbitR) * sin(ang)), atan2(-cos(ang), sin(ang))]
	var from_p: Dictionary = Galaxy.planets[_planet_idx(int(t.fromId))]
	var tp: Dictionary = Galaxy.planets[_planet_idx(int(t.toId))]
	var lt := _compute_tangent(from_p, tp, float(t.orbitR), float(t.arrivalOrbitR))
	if lt.is_empty():
		return [Vector2(float(t.x), float(t.y)), 0.0]
	var car_dist: float = float(t.transitDist) - off
	var tan_len: float = lt.tanLen
	if car_dist < 0.0:
		# Tail car still on the departure orbit.
		var fr: float = maxf(1.0, float(t.orbitR))
		var ang2: float = float(lt.tanAngle) - car_dist / fr
		return [Vector2(float(from_p.x) + float(t.orbitR) * cos(ang2), float(from_p.y) + float(t.orbitR) * sin(ang2)), atan2(-cos(ang2), sin(ang2))]
	elif car_dist <= tan_len:
		# On the tangent line.
		var frac: float = car_dist / maxf(0.001, tan_len)
		var hx: float = float(lt.bx) - float(lt.ax)
		var hy: float = float(lt.by) - float(lt.ay)
		return [Vector2(lerpf(float(lt.ax), float(lt.bx), frac), lerpf(float(lt.ay), float(lt.by), frac)), atan2(hy, hx)]
	else:
		# Leading car already sliding onto the arrival orbit.
		var ar: float = maxf(1.0, float(t.arrivalOrbitR))
		var ang3: float = float(lt.tanAngle) - (car_dist - tan_len) / ar
		return [Vector2(float(tp.x) + float(t.arrivalOrbitR) * cos(ang3), float(tp.y) + float(t.arrivalOrbitR) * sin(ang3)), atan2(-cos(ang3), sin(ang3))]

# ── Per-tick advance ──────────────────────────────────────────────────────
func tick(dtG: float) -> void:
	for t in trains:
		_tick_train(t, dtG)

func _tick_train(t: Dictionary, dtG: float) -> void:
	var w: float = Tuning.ORB_SPD
	if t.phase == Phase.ORBIT:
		var p: Dictionary = Galaxy.planets[_planet_idx(t.planetId)]
		t.orbitAngle -= w * dtG          # orbit CW (matches JS t.angle -= ORB_SPD*dt)
		t.orbitSpun += w * dtG
		_place_in_orbit(t, p)
		# Car-by-car cargo ops while orbiting a planet that has a station (the
		# train's orbit tier is serviceable). One car per CARGO_OP_TIME; beams are
		# drawn render-side from t.cargoPhase / t.cargoQueue.
		if bool(p.get("hasStation", false)):
			if not bool(t.get("_cargoChecked", false)):
				t._cargoChecked = true
				_start_cargo_ops(t, p)
			if String(t.cargoPhase) != "":
				t.cargoTimer = float(t.cargoTimer) - dtG
				if t.cargoTimer <= 0.0:
					_process_cargo_queue(t, p)
		# Depart only when cargo ops are done, we've dwelled, and the angle lines
		# up with the tangent to the next stop → smooth tangential exit.
		if t.route != null and t.targetId == -1 and String(t.cargoPhase) == "" and t.orbitSpun >= MIN_ORBIT_SPUN:
			var nid := _peek_next(t)
			if nid >= 0:
				var tp: Dictionary = Galaxy.planets[_planet_idx(nid)]
				var arr := _orbit_radius_for(tp) + _orbit_occupancy(t, nid) * ORBIT_GAP
				var lt := _compute_tangent(p, tp, t.orbitR, arr)
				if not lt.is_empty():
					var d_cw := fposmod(t.orbitAngle - float(lt.tanAngle), TAU)
					if d_cw <= w * dtG * 1.5:
						t.orbitAngle = float(lt.tanAngle)
						_place_in_orbit(t, p)
						_begin_transit(t, nid, arr)
		return

	# TRANSIT — live tangent + accelerate / cruise / decelerate.
	var from_p: Dictionary = Galaxy.planets[_planet_idx(t.fromId)]
	var tp2: Dictionary = Galaxy.planets[_planet_idx(t.toId)]
	var lt2 := _compute_tangent(from_p, tp2, t.orbitR, t.arrivalOrbitR)
	if lt2.is_empty():
		_arrive(t, tp2, t.orbitAngle)
		return
	var tan_len: float = lt2.tanLen
	var arr_r: float = maxf(1.0, float(t.arrivalOrbitR))
	# The engine reaching the tangent end (transitDist=tan_len) is NOT arrival —
	# the train only docks once the WHOLE consist has slid onto the arrival orbit,
	# i.e. transitDist >= tan_len + consist_len. Until then the engine keeps moving
	# along the arrival orbit at orbital speed and the trailing cars finish the
	# tangent (car_path_pos already snakes them through), so no car ever snaps.
	var consist_len: float = float(t.get("consist_len", 0.0))
	var arrive_dist: float = tan_len + consist_len
	var v_target: float = Tuning.ORB_SPD * arr_r  # match arrival orbital speed
	var v_max: float = float(Tuning.ENGINE_MAX_SPD.get(t.engine, 4.0))
	var accel := _engine_accel(t.engine)
	if t.transitDist >= tan_len:
		# Engine already on the arrival orbit — hold orbital speed (seamless into
		# the ORBIT phase, whose angular speed gives the same linear speed).
		t.transitSpeed = v_target
	else:
		# On the tangent: decelerate so we hit v_target exactly at the tangent end.
		var remaining: float = tan_len - t.transitDist
		var decel_dist := maxf(0.0, (t.transitSpeed * t.transitSpeed - v_target * v_target) / (2.0 * accel))
		if remaining <= decel_dist:
			t.transitSpeed = maxf(v_target, t.transitSpeed - accel * dtG)
		else:
			t.transitSpeed = minf(v_max, t.transitSpeed + accel * dtG)
	var moved: float = t.transitSpeed * dtG
	t.transitDist += moved
	# Maintenance decay + distance tracking (player trains only; build_game.py:15677).
	if bool(t.isPlayer):
		t.distSinceMaint = float(t.get("distSinceMaint", 0.0)) + moved
		t.totalDist = float(t.get("totalDist", 0.0)) + moved
		var pm: float = float(t.get("maintenance", 1.0))
		var decay: float = float(Tuning.ENGINE_MAINT_DECAY.get(String(t.engine), Tuning.MAINT_DECAY_PER_AU))
		t.maintenance = maxf(0.0, pm - decay * moved)
		if pm > 0.0 and float(t.maintenance) <= 0.0:
			Audio.play("breakdown")
	if t.transitDist >= arrive_dist:
		# Whole consist on the orbit → dock at the engine's CURRENT orbit angle so
		# every car's position is continuous across the TRANSIT→ORBIT switch.
		var ea: float = float(lt2.tanAngle) - (t.transitDist - tan_len) / arr_r
		_arrive(t, tp2, ea)
	elif t.transitDist <= tan_len:
		# Engine on the tangent line.
		var frac: float = t.transitDist / maxf(0.001, tan_len)
		t.x = lerpf(float(lt2.ax), float(lt2.bx), frac)
		t.y = lerpf(float(lt2.ay), float(lt2.by), frac)
	else:
		# Engine sliding along the arrival orbit while the tail catches up.
		var ea: float = float(lt2.tanAngle) - (t.transitDist - tan_len) / arr_r
		t.x = float(tp2.x) + t.arrivalOrbitR * cos(ea)
		t.y = float(tp2.y) + t.arrivalOrbitR * sin(ea)

# ── Phased per-car cargo ops (build_game.py:7380-7815) ──────────────────────
const CARGO_OP_TIME := 180.0   # dtG frame-units per car (~3 s at 1× speed)
const CAR_CARGO_UNITS := {"car_royal": 0.5}  # default 1.0

func _car_units(car_type: String) -> float:
	return float(CAR_CARGO_UNITS.get(car_type, 1.0))

# Build the unload queue (full cars the planet demands ≥0.5 units), else load.
func _start_cargo_ops(t: Dictionary, p: Dictionary) -> void:
	var demand: Dictionary = p.get("demand", {})
	var uq: Array = []
	for i in t.cars.size():
		var cargo = t.carCargo[i]
		if cargo == null:
			continue
		var units := _car_units(String(t.cars[i]))
		if float(demand.get(cargo, 0.0)) < 0.5 * units:
			continue
		if int(t.carSrc[i]) == int(p.id):  # never unload at the source planet
			continue
		uq.append(i)
	if not uq.is_empty():
		t.cargoPhase = "unloading"
		t.cargoQueue = uq
		t.cargoTimer = CARGO_OP_TIME
		return
	_start_load_phase(t, p)

# Build the load queue (empty cars whose cargo the planet supplies enough of).
func _start_load_phase(t: Dictionary, p: Dictionary) -> void:
	var supply: Dictionary = p.get("supply", {})
	var remaining: Dictionary = {}
	var lq: Array = []
	for i in t.cars.size():
		if t.carCargo[i] != null:
			continue  # not empty
		var cargo = Tuning.CAR_CARGO_TYPE.get(String(t.cars[i]), null)
		if cargo == null:
			continue
		var units := _car_units(String(t.cars[i]))
		if not remaining.has(cargo):
			remaining[cargo] = float(supply.get(cargo, 0.0))
		if float(remaining[cargo]) >= units:
			remaining[cargo] = float(remaining[cargo]) - units
			lq.append(i)
	if not lq.is_empty():
		t.cargoPhase = "loading"
		t.cargoQueue = lq
		t.cargoTimer = CARGO_OP_TIME
	else:
		t.cargoPhase = ""

# Process ONE car from the front of the queue (called each CARGO_OP_TIME).
func _process_cargo_queue(t: Dictionary, p: Dictionary) -> void:
	if t.cargoQueue.is_empty():
		t.cargoPhase = ""
		return
	var i: int = t.cargoQueue[0]
	if String(t.cargoPhase) == "unloading":
		var cargo = t.carCargo[i]
		if cargo != null:
			var src: Dictionary = {}
			if int(t.carSrc[i]) >= 0:
				src = Galaxy.planets[_planet_idx(int(t.carSrc[i]))]
			var rev := Economy.compute_cargo_revenue(String(t.cars[i]), cargo, p, src)
			if t.isPlayer:
				# CEO revenue perk (build_game.py corp perks). Default mult 1.0.
				rev = int(round(float(rev) * float(GameState.ceo_revenue_mult.get(String(cargo), 1.0))))
				GameState.credits += rev
				t.totalRevenue = int(t.get("totalRevenue", 0)) + rev
				# First-ever delivery to this planet → celebration popup.
				if not GameState.delivered_planets.has(int(p.id)):
					GameState.delivered_planets[int(p.id)] = true
					GameState.first_delivery.emit(int(p.id), String(cargo), String(t.cars[i]), GameState.stardate)
				GameState.record_revenue(String(cargo), String(t.get("name", "")), int(p.id), int(p.get("starId", -1)), rev)
				if cargo == "passengers":
					GameState.total_passengers_delivered += 1
				GameState.player_delivered.emit(rev)
				Missions.on_delivery(cargo, p.id)
			elif AICorp.active:
				AICorp.credits += rev
				AICorp.total_revenue += rev
			train_delivered.emit(t.id, p.id, cargo, rev)
			if p.has("demand"):
				p.demand[cargo] = maxf(0.0, float(p.demand.get(cargo, 0.0)) - _car_units(String(t.cars[i])))
			t.carCargo[i] = null
			t.carSrc[i] = -1
		t.cargoQueue.pop_front()
		if t.cargoQueue.is_empty():
			_start_load_phase(t, p)  # unload done → load
		else:
			t.cargoTimer = CARGO_OP_TIME
	else:  # loading
		var cargo = Tuning.CAR_CARGO_TYPE.get(String(t.cars[i]), null)
		var units := _car_units(String(t.cars[i]))
		var supply: Dictionary = p.get("supply", {})
		if cargo != null and float(supply.get(cargo, 0.0)) >= units:
			p.supply[cargo] = float(supply[cargo]) - units
			t.carCargo[i] = cargo
			t.carSrc[i] = t.planetId
		t.cargoQueue.pop_front()
		if t.cargoQueue.is_empty():
			t.cargoPhase = ""
		else:
			t.cargoTimer = CARGO_OP_TIME
