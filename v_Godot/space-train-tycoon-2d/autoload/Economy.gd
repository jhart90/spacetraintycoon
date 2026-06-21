extends Node
## Economy — population, supply/demand, economic health, cargo seeding.
## Ported from build_game.py (generatePopulation 6913, computeSupplyRate 7003,
## computeDemandRate 7077, computeEconomicHealth 7270, seedCargoPlanet 7283,
## _devMult 2137). See PLAN Phase 2, §5.
##
## Population uses RNG → pulls from Galaxy's seeded stream (Galaxy.random()).
## The compute* functions are pure (no RNG). Pricing/revenue lives in Transit
## (delivery) — Phase 2 slice 3.
##
## Globals referenced by the JS that are still stubbed here: _anyCargoProduced
## (GameState.any_cargo_produced, false at start) and active missions
## (Missions.is_active / target — false/-1 until Phase 3).

# build_game.py:2137
const DEV_MULT := [1.0, 1.15, 1.35, 1.6, 1.95, 2.4, 2.95, 3.65, 4.5, 5.5, 7.0]
func _dev_mult(lv: int) -> float:
	return DEV_MULT[clampi(lv, 0, 10)]

# ── generatePopulation (build_game.py:6913) ───────────────────────────────
func generate_population(p: Dictionary) -> int:
	var bio: String = p.type.id
	if bio == "ancient":
		return 0
	var biomeMult: float = {
		"ocean": 1.6, "jungle": 1.5, "resort": 1.4, "agri": 1.2, "rocky": 1.0,
		"desert": 0.8, "ice": 0.7, "oil": 0.0, "storm": 0.35, "lava": 0.25,
		"chemical": 0.3, "urban": 2.0,
	}.get(bio, 1.0)
	var sizeMult: float = {"XS": 0.5, "S": 0.75, "M": 1.0, "L": 1.3, "XL": 1.6, "XXL": 2.0}.get(p.size, 1.0)
	var factor := biomeMult * sizeMult
	if bio == "urban":
		var raw := 1.5e9 + Galaxy.random() * 4.85e10
		return int(round(min(5e10, max(1.5e9, raw * sizeMult))))
	var r := Galaxy.random()
	if r < 0.33 and not (bio == "agri" or bio == "resort"):
		return 0
	if r < 0.66:
		var raw := pow(10.0, 1.0 + Galaxy.random() * 4.9)
		return int(round(min(999999.0, max(10.0, raw * factor))))
	if r < 0.89:
		var raw := 1e6 * pow(100.0, Galaxy.random())
		return int(round(min(1e8, max(1e6, raw * factor))))
	if r < 0.96:
		var raw := 1.01e8 * pow(99.0, Galaxy.random())
		return int(round(min(1e10, max(1.01e8, raw * factor))))
	var raw := 1e10 + Galaxy.random() * 4e10
	return int(round(min(5e10, max(1e10, raw * factor))))

# ── computeSupplyRate (build_game.py:7003) ────────────────────────────────
func compute_supply_rate(p: Dictionary) -> Dictionary:
	var r := {}
	var bio: String = p.type.id
	var pop: float = float(p.get("population", 0))
	var _szSc: float = {"XS": 0.8, "S": 1.0, "M": 1.5, "L": 2.0, "XL": 2.5, "XXL": 3.0}.get(p.size, 1.0)
	if pop >= 1e10: r.passengers = 20.0
	elif pop >= 1e9: r.passengers = 12.0
	elif pop >= 1e8: r.passengers = 12.0
	elif pop >= 1e7: r.passengers = 10.0
	elif pop >= 1e6: r.passengers = 8.0
	elif pop >= 1e5: r.passengers = 6.0
	elif pop > 0: r.passengers = 4.0
	if pop > 0: r.mail = r.passengers / 2.0
	if bio == "ocean": r.water = 5.0 * _szSc
	if bio == "resort": r.water = 2.0 * _szSc
	if bio == "ice": r.ice = 4.0 * _szSc
	if bio == "desert": r.sand = 5.0 * _szSc
	if bio == "rocky": r.sand = 1.0 * _szSc
	if bio == "ancient": r.sand = 5.0 * _szSc
	if bio == "lava": r.molten_ore = 5.0 * _szSc
	if bio == "oil": r.oil = 4.0 * _szSc
	if bio == "storm": r.battery = 3.0 * _szSc
	if bio == "chemical": r.chemical = 4.0 * _szSc
	if bio == "jungle": r.medical = 2.0 * _szSc
	if bio == "jungle": r.fruit = 3.5 * _szSc
	if bio == "agri":
		if p.get("livestockUnlocked", false): r.livestock = 8.0 * _szSc
		if p.get("grainUnlocked", false): r.grain = 6.0 * _szSc
		if p.get("fruitUnlocked", false): r.fruit = 7.0 * _szSc
	if p.get("hasGold", false): r.gold = 4.0
	if p.get("hasDiamond", false): r.diamond = 3.0
	var dl: int = int(p.get("devLevel", 0))
	if dl > 0:
		var dm := _dev_mult(dl)
		for k in r.keys(): r[k] *= dm
	if bio == "jungle" and dl >= 6: r.livestock = r.get("livestock", 0.0) + 4.0
	if bio == "ocean" and dl >= 7: r.ice = r.get("ice", 0.0) + 4.0
	if bio == "ice" and dl >= 8: r.water = r.get("water", 0.0) + 4.0
	if p.get("isFlowersOrigin", false) and bio in ["jungle", "desert", "resort"]:
		r.flowers = 6.0
	elif p.get("flowerUnlocked", false) and bio in ["jungle", "desert", "resort"]:
		r.flowers = 3.0
	return r

# ── computeDemandRate (build_game.py:7077) ────────────────────────────────
func compute_demand_rate(p: Dictionary) -> Dictionary:
	var r := {}
	var bio: String = p.type.id
	var pop: float = float(p.get("population", 0))
	if bio == "ancient":
		return r
	var unh: bool = bio in ["storm", "lava", "chemical", "oil"]
	var supplyRate: Dictionary = p.get("supplyRate", {})
	var _passSup: float = supplyRate.get("passengers", 0.0)
	if _passSup > 0.0:
		r.passengers = _passSup * (2.0 if bio == "resort" else (1.8 if bio == "urban" else 1.0))
	elif not unh:
		r.passengers = 0.05
	var _mailSup: float = supplyRate.get("mail", 0.0)
	if _mailSup > 0.0:
		r.mail = min(8.0, _mailSup * (2.0 if bio == "resort" else (1.8 if bio == "urban" else 1.0)))
	if not unh and pop > 0.0:
		r.livestock = min(30.0 if bio == "urban" else 15.0, pop / 2e9 * 10.0 * (2.0 if bio == "urban" else 1.0))
	_apply_pop_table(r, "water", {"desert": 3.0, "lava": 2.5, "agri": 1.5, "urban": 4.0, "rocky": 0.5}, bio, pop, 0.3)
	_apply_pop_table(r, "ice", {"lava": 3.0, "desert": 2.0, "urban": 3.0, "chemical": 0.8, "rocky": 0.4}, bio, pop, 0.3)
	_apply_pop_table(r, "sand", {"resort": 3.0, "urban": 2.5, "ocean": 1.5, "agri": 0.8, "jungle": 0.5}, bio, pop, 0.3)
	_apply_pop_table(r, "molten_ore", {"rocky": 3.5, "urban": 3.0, "desert": 2.0, "ice": 1.5, "ocean": 0.5, "jungle": 0.4}, bio, pop, 0.3)
	_apply_pop_table(r, "iron", {"urban": 4.0, "rocky": 2.5, "ocean": 1.8, "jungle": 1.2, "agri": 1.0, "resort": 0.8, "desert": 0.6, "ice": 0.5}, bio, pop, 0.3)
	_apply_pop_table(r, "gold", {"resort": 2.0, "urban": 2.0, "ocean": 1.2, "jungle": 0.8, "rocky": 0.5, "desert": 0.4}, bio, pop, 0.2)
	_apply_pop_table(r, "diamond", {"resort": 1.8, "urban": 1.6, "ocean": 1.0, "jungle": 0.6, "rocky": 0.3, "desert": 0.3}, bio, pop, 0.15)
	_apply_pop_table(r, "oil", {"urban": 5.0, "lava": 3.5, "rocky": 3.0, "storm": 2.5, "desert": 2.0, "chemical": 1.5, "ice": 1.0, "ocean": 0.6, "jungle": 0.4}, bio, pop, 0.3)
	_apply_pop_table(r, "battery", {"urban": 4.5, "resort": 2.0, "ocean": 1.6, "jungle": 1.2, "agri": 1.0, "rocky": 0.8, "desert": 0.6, "ice": 0.5}, bio, pop, 0.2)
	var dl: int = int(p.get("devLevel", 0))
	if dl > 0:
		var dm := _dev_mult(dl)
		for k in r.keys(): r[k] *= dm
	if bio == "storm" and dl >= 2: r.ice = r.get("ice", 0.0) + 1.0
	if bio == "lava" and dl >= 3: r.water = r.get("water", 0.0) + 1.5
	if bio == "jungle" and dl >= 4: r.sand = r.get("sand", 0.0) + 1.0
	if bio == "agri" and dl >= 5: r.iron = r.get("iron", 0.0) + 1.5
	if bio == "ocean" and dl >= 6: r.molten_ore = r.get("molten_ore", 0.0) + 1.0
	if bio == "ice" and dl >= 7 and pop > 0: r.passengers = r.get("passengers", 0.0) + 2.0
	if bio == "resort" and dl >= 9: r.gold = r.get("gold", 0.0) + 1.5
	if bio == "rocky" and dl >= 10: r.gold = r.get("gold", 0.0) + 0.8
	if bio == "resort" and dl >= 10: r.diamond = r.get("diamond", 0.0) + 0.8
	var upgrades: Array = p.get("upgrades", [])
	var _upgradeCount := upgrades.size()
	if _upgradeCount > 0:
		var _cpf: float = min(2.0, 0.5 + pop / 2e9) if pop > 0 else 0.4
		r.chemical = r.get("chemical", 0.0) + 2.0 * _upgradeCount * _cpf
	if bio == "urban":
		var _ucpf: float = min(2.0, 0.5 + pop / 2e9) if pop > 0 else 1.0
		r.chemical = r.get("chemical", 0.0) + 3.5 * _ucpf
	if bio in ["jungle", "desert", "resort", "urban"]:
		var _fpf: float = min(2.0, 0.5 + pop / 1e9) if pop > 0 else 0.3
		var _fBase: float = 3.5 if bio == "urban" else 2.0
		r.flowers = _fBase * _fpf
	_apply_pop_table(r, "medical", {"urban": 3.0, "jungle": 0.5, "ocean": 1.0, "resort": 1.5, "agri": 0.8, "rocky": 0.6, "desert": 0.4, "ice": 0.3}, bio, pop, 0.2)
	if not unh and pop > 0:
		r.grain = min(30.0 if bio == "urban" else 15.0, pop / 2e9 * 8.0 * (2.5 if bio == "urban" else 1.0))
	_apply_pop_table(r, "fruit", {"urban": 3.0, "resort": 2.0, "ocean": 1.4, "jungle": 1.2, "agri": 0.8, "rocky": 0.6, "desert": 0.4, "ice": 0.3}, bio, pop, 0.2)
	if pop > 0: r.iron = r.get("iron", 0.0) + dl * 0.3
	if p.get("hasStation", false): r.iron = max(r.get("iron", 0.0), 1.0)
	if p.get("hasLargeStation", false) or p.get("hasTerminal", false): r.steel = max(r.get("steel", 0.0), 1.0)
	if bio == "urban": r.glass = max(r.get("glass", 0.0), 4.0)
	if pop > 0 and dl >= 4: r.glass = max(r.get("glass", 0.0), 1.0)
	if bio in ["agri", "ice", "oil", "storm"]:
		var _mpf: float = min(2.0, 0.5 + pop / 2e9) if pop > 0 else 0.5
		var _mBase: float = {"agri": 2.5, "ice": 2.0, "oil": 2.5, "storm": 2.0}.get(bio, 2.0)
		r.machinery = max(r.get("machinery", 0.0), _mBase * _mpf)
	# Juicery/Bakery floors + cargo-shift + mission floors: inert at generation
	# (no upgradeData, _anyCargoProduced=false, no active missions). See TODO.
	if GameState.any_cargo_produced:
		if pop > 0:
			r.cargo = max(r.get("cargo", 0.0), min(4.0, 0.5 + dl * 0.4))
		if bio != "agri":
			r.erase("grain"); r.erase("livestock"); r.erase("fruit")
			if "bakery" in upgrades: r.grain = max(r.get("grain", 0.0), 1.0)
			if "juicery" in upgrades: r.fruit = max(r.get("fruit", 0.0), 1.0)
	return r

func _apply_pop_table(r: Dictionary, key: String, table: Dictionary, bio: String, pop: float, low: float) -> void:
	if table.has(bio):
		var pf: float = min(2.0, 0.5 + pop / 2e9) if pop > 0 else low
		r[key] = table[bio] * pf

# ── computeEconomicHealth (build_game.py:7270) ────────────────────────────
func compute_economic_health(p: Dictionary) -> float:
	var pop: float = float(p.get("population", 0))
	var bm: float = {
		"urban": 1.5, "resort": 1.4, "ocean": 1.2, "jungle": 1.1, "agri": 1.0,
		"rocky": 0.9, "desert": 0.8, "ice": 0.7, "oil": 0.6, "storm": 0.4,
		"lava": 0.3, "chemical": 0.3,
	}.get(p.type.id, 1.0)
	var pm: float = 1.5 if pop >= 1e10 else (1.2 if pop >= 1e8 else (1.0 if pop >= 1e6 else (0.7 if pop >= 1e4 else (0.5 if pop > 0 else 0.3))))
	return round(bm * pm * 100.0) / 100.0

# ── Cargo revenue (build_game.py:7292-7318) ───────────────────────────────
func _sys_econ_mult(star: Dictionary) -> float:
	if star.is_empty() or not star.has("planetIds"):
		return 1.0
	var tot := 0.0
	for pid in star.planetIds:
		var idx: int = pid if (pid < Galaxy.planets.size() and Galaxy.planets[pid].id == pid) else -1
		if idx >= 0:
			tot += float(Galaxy.planets[idx].get("population", 0))
	if tot > 5e10: return 1.5
	if tot > 1e10: return 1.2
	if tot > 1e8: return 1.0
	if tot > 1e6: return 0.8
	if tot > 1e4: return 0.6
	return 0.3

## Credits earned unloading one unit of cargoType (carType) at destPlanet,
## sourced from srcPlanet. CEO perks omitted (Phase 3) → ceoM = 1.
func compute_cargo_revenue(carType: String, cargoType: String, destPlanet: Dictionary, srcPlanet: Dictionary) -> int:
	var base: float = float(Tuning.CARGO_BASE_RATE.get(cargoType, {}).get(carType, 500))
	var dem: float = destPlanet.get("demand", {}).get(cargoType, 0.0)
	var demM: float = 2.0 if dem > 20 else (1.5 if dem > 10 else (1.0 if dem > 5 else (0.7 if dem > 2 else (0.4 if dem > 0.5 else 0.1))))
	var ph: float = destPlanet.get("economicHealth", 1.0)
	var phM: float = 1.4 if ph > 1.3 else (1.1 if ph > 1.0 else (0.9 if ph > 0.7 else (0.7 if ph > 0.5 else (0.5 if ph > 0.3 else 0.2))))
	var shM := _sys_econ_mult(Galaxy.stars[destPlanet.starId])
	var distM := 1.0
	if cargoType == "passengers" and not srcPlanet.is_empty():
		var sSrc: Dictionary = Galaxy.stars[srcPlanet.starId]
		var sDst: Dictionary = Galaxy.stars[destPlanet.starId]
		distM = 1.0 + Vector2(sSrc.x - sDst.x, sSrc.y - sDst.y).length() / 1000.0 * 0.02
	elif not srcPlanet.is_empty():
		var d: float = Vector2(srcPlanet.x - destPlanet.x, srcPlanet.y - destPlanet.y).length()
		distM = 2.5 if d > 120000 else (1.8 if d > 60000 else (1.3 if d > 20000 else (1.0 if d > 5000 else (0.8 if d > 1000 else 0.5))))
	var unitMult: float = Tuning.CAR_CARGO_UNITS.get(carType, 1.0)
	return int(round(base * demM * phM * shM * distM * unitMult))

# ── seedCargoPlanet (build_game.py:7283) ──────────────────────────────────
func seed_cargo_planet(p: Dictionary) -> void:
	var _devCap: float = float(int(p.get("devLevel", 0)) + 1)
	var _init := _devCap * 0.25
	p.supply = {}
	p.demand = {}
	for t in p.get("supplyRate", {}).keys(): p.supply[t] = _init
	for t in p.get("demandRate", {}).keys(): p.demand[t] = _init


# updateCargoSupplyDemand (build_game.py:13958) — replenish supply (and demand)
# pools over time so a planet keeps producing/wanting cargo. Each pool grows by
# rate·dtSd, capped at devLevel+1. Trains draw the pools down on load/unload.
func accumulate(dt_sd: float) -> void:
	if dt_sd <= 0.0:
		return
	for p in Galaxy.planets:
		var sr: Dictionary = p.get("supplyRate", {})
		var dr: Dictionary = p.get("demandRate", {})
		if not bool(p.get("hasStation", false)) and sr.is_empty() and dr.is_empty():
			continue
		var cap := float(int(p.get("devLevel", 0)) + 1)
		for type in sr:
			p.supply[type] = minf(cap, float(p.supply.get(type, 0.0)) + float(sr[type]) * dt_sd)
		for type in dr:
			p.demand[type] = minf(cap, float(p.demand.get(type, 0.0)) + float(dr[type]) * dt_sd)
