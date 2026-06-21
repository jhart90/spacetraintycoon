extends Node
## AICorp — rival corporation simulation (CORE).
## Ported from build_game.py AI architecture (code map §15). See PLAN Phase 3.
##
## IMPLEMENTED: a rival corp with difficulty-scaled start credits + investment
## cadence (AI_TICK_INTERVALS); it operates from an AI home system, buys trains
## (non-player) and routes them through the shared Transit system, earning
## revenue into its own treasury and growing net worth over time.
##
## DEFERRED (full-fidelity AI from §15): the mirror-system transform for the AI
## home, station building, difficulty-specific strategy/route optimisation, the
## VS-RIVAL finance metrics. Validate full behaviour later with the `ai-snapshot`
## skill. This core runs and grows, which is what Phase 3's exit needs.

var active: bool = false
var difficulty: String = "normal"
var corp_name: String = ""
var credits: int = 0
var total_revenue: int = 0
var home_star_id: int = -1
var _tick_acc: float = 0.0
var _route_planets: Array = []

func reset() -> void:
	active = false
	credits = 0
	total_revenue = 0
	home_star_id = -1
	_tick_acc = 0.0
	_route_planets = []

func init_corp(diff: String = "normal") -> void:
	reset()
	difficulty = diff
	active = true
	corp_name = Tuning.AI_CORP_NAMES.get(diff, "Rival Corp")
	credits = int(Tuning.AI_START_CREDITS.get(diff, 400000))
	_pick_home()

## AI home = the populated system farthest from Orijen (a stand-in for the full
## mirror-system transform — see DEFERRED note).
func _pick_home() -> void:
	var best := -1
	var best_d := -1.0
	for s in Galaxy.stars:
		if s.id == Galaxy.home_star_id:
			continue
		var pops := 0
		for pid in s.planetIds:
			if int(Galaxy.planets[pid].population) > 0:
				pops += 1
		if pops >= 2:
			var d: float = Vector2(s.x, s.y).length()
			if d > best_d:
				best_d = d
				best = s.id
	home_star_id = best
	_route_planets = []
	if best >= 0:
		for pid in Galaxy.stars[best].planetIds:
			if int(Galaxy.planets[pid].population) > 0:
				_route_planets.append(pid)

func tick(dtG: float) -> void:
	if not active or home_star_id < 0:
		return
	_tick_acc += dtG * Tuning.SD_PER_DTG
	var interval: float = Tuning.AI_TICK_INTERVALS.get(difficulty, 7.0)
	while _tick_acc >= interval:
		_tick_acc -= interval
		_invest()

func _invest() -> void:
	if _route_planets.size() < 2:
		return
	var cost: int = int(Tuning.ENGINE_COSTS["engine_constellation"]) + Tuning.CAR_COST * 2
	if credits < cost:
		return
	credits -= cost
	var t := Transit.build_train(_route_planets[0], "engine_constellation", ["car_passenger", "car_passenger"], false)
	Transit.assign_route(t, _route_planets.slice(0, mini(3, _route_planets.size())))

func train_value() -> int:
	var v := 0
	for t in Transit.trains:
		if not t.isPlayer:
			v += int(Tuning.ENGINE_COSTS.get(t.engine, 10000)) + t.cars.size() * Tuning.CAR_COST
	return v

func net_worth() -> int:
	return credits + train_value()
