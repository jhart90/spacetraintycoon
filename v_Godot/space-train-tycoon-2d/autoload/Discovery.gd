extends Node
## Discovery — fog / discovered / visited tiers. Ported from build_game.py.
## See PLAN Phase 1, code map §10 + §5.6; memory [[discovery-visit-system]].
##
## Three tiers (build_game.py):
##   UNKNOWN    — the planet's star system has never been entered. Hidden in fog,
##                obscured ("??? UNKNOWN") in all UIs.
##   DISCOVERED — some planet in this system was visited, so the whole system is
##                discovered, but THIS planet hasn't been individually visited.
##                Shown as a blacked-out disc.
##   VISITED    — this specific planet was visited (orbit entered). Full details.
## Stars: revealed == visited (happens when any planet in the system is visited).
##
## PHASE 1 SCOPE: the tier data model + init + visit tracking + queries + a
## discovery_changed signal for the view. The credit reward on first visit is
## Economy (Phase 2) — see TODO in track_visit. Mission/news/car-unlock side
## effects of the JS trackVisit are Phase 2-4.

enum Tier { UNKNOWN, DISCOVERED, VISITED }

# Sets modelled as Dictionaries {id:true} for O(1) membership (build_game.py
# uses JS Set: discoveredPlanetIds / visitedPlanetIds / revealedStarIds).
var discovered_planet_ids: Dictionary = {}
var visited_planet_ids: Dictionary = {}
var revealed_star_ids: Dictionary = {}

signal discovery_changed
signal star_revealed(star_id: int)  # a star newly entered the registry (SFX hook)
# Gold/diamond deposit surveys (build_game.py trackVisit ~15998): fired the
# moment the player visits a planet carrying an undiscovered deposit.
signal gold_discovered(planet_id: int)
signal diamond_discovered(planet_id: int)
# A planet was visited for the first time (build_game.py trackVisit ~16118):
# chat "<name> — VISITED" + a credit reward float at the planet.
signal planet_visited(planet_id: int, reward: int)

# Biome → car unlocked on the FIRST visit to a planet of that biome
# (build_game.py:16239; lava omitted — molten-ore car is unlocked at start).
const _BIOME_UNLOCK_CAR := {
	"desert": "car_sand", "ice": "car_ice", "oil": "car_oil",
	"storm": "car_battery", "chemical": "car_chemical",
}

# ── New-game initialisation (build_game.py:35243-35268) ───────────────────
# Orijen pre-visited (no credit), home star revealed, all home-system planets
# pre-discovered.
func init_for_new_game() -> void:
	discovered_planet_ids = {}
	visited_planet_ids = {}
	revealed_star_ids = {}
	Fog.reset()
	if Galaxy.planets.is_empty():
		return
	var origen_id := Galaxy.origen_id
	visited_planet_ids[origen_id] = true
	_reveal_star_for_planet(origen_id)
	Fog.reveal_orbited(origen_id)
	# Pre-discover every planet in the home system.
	var home_star: Dictionary = Galaxy.stars[Galaxy.home_star_id]
	for pid in home_star.planetIds:
		discovered_planet_ids[pid] = true
	discovery_changed.emit()

# ── First entry into a planet's orbit (build_game.py trackVisit ~15942) ────
# Discovers the whole system, marks the planet visited, reveals its star.
func track_visit(pid: int) -> void:
	var idx := _planet_idx(pid)
	if idx < 0:
		return
	var p: Dictionary = Galaxy.planets[idx]
	var star: Dictionary = Galaxy.stars[p.starId]
	for opid in star.planetIds:
		discovered_planet_ids[opid] = true
	_reveal_star_for_planet(pid)
	Fog.reveal_orbited(pid)
	# Gold / diamond deposit survey on visit (build_game.py trackVisit ~15998).
	if p.get("hasGold", false) and not p.get("goldRevealed", false):
		p["goldRevealed"] = true
		gold_discovered.emit(pid)
	if p.get("hasDiamond", false) and not p.get("diamondRevealed", false):
		p["diamondRevealed"] = true
		diamond_discovered.emit(pid)
	if not visited_planet_ids.has(pid):
		visited_planet_ids[pid] = true
		# Ancient-world first-visit broadcast (build_game.py trackVisit ~16035):
		# each visit translates 3 more words, then queues the popup.
		if String(p.type.id) == "ancient":
			GameState.translate_ancient_words()
			GameState.ancient_message.emit(pid)
		_award_visit_unlocks(p)
		# First-visit credit reward (build_game.py:16294): >100k SU from Orijen
		# → 3000, another star → 2000, home system → 1000.
		var origen: Dictionary = Galaxy.planets[Galaxy.origen_id]
		var dist := sqrt(pow(p.x - origen.x, 2.0) + pow(p.y - origen.y, 2.0))
		var reward := 3000 if dist > 100000.0 else (2000 if int(p.starId) != Galaxy.home_star_id else 1000)
		GameState.credits = mini(GameState.credits + reward, 999999999)
		Audio.play("discovery")
		planet_visited.emit(pid, reward)
	discovery_changed.emit()

# Biome / agri car + upgrade unlocks on first visit (build_game.py:16239-16292).
func _award_visit_unlocks(p: Dictionary) -> void:
	var bio := String(p.type.id)
	# Biome car — only when this is the FIRST visited planet of this biome.
	if _BIOME_UNLOCK_CAR.has(bio):
		var count := 0
		for op in Galaxy.planets:
			if visited_planet_ids.has(int(op.id)) and String(op.type.id) == bio:
				count += 1
		if count == 1:
			_unlock_car(String(_BIOME_UNLOCK_CAR[bio]))
	# Agri: first agri visit unlocks the Bakery upgrade; per-planet upgrade
	# buildings unlock their food car.
	if bio == "agri":
		_unlock_upgrade("bakery")
		var ups: Array = p.get("upgrades", [])
		if ups.has("granary"): _unlock_car("car_grain")
		if ups.has("farm"): _unlock_car("car_livestock")
		if ups.has("orchard"): _unlock_car("car_fruit")
	# Sand + Chemical cars discovered → Glassworks upgrade (build_game.py:16290).
	if GameState.unlocked_cars.has("car_sand") and GameState.unlocked_cars.has("car_chemical"):
		_unlock_upgrade("glassworks")

func _unlock_car(car: String) -> void:
	if not GameState.unlocked_cars.has(car):
		GameState.unlocked_cars[car] = true
		GameState.car_unlocked.emit(car)

func _unlock_upgrade(up: String) -> void:
	if not GameState.unlocked_upgrades.has(up):
		GameState.unlocked_upgrades[up] = true
		GameState.upgrade_unlocked.emit(up)

func _reveal_star_for_planet(pid: int) -> void:
	var idx := _planet_idx(pid)
	if idx < 0:
		return
	var sid: int = Galaxy.planets[idx].starId
	var was_new := not revealed_star_ids.has(sid)
	revealed_star_ids[sid] = true
	if was_new:
		Fog.reveal_star(Galaxy.stars[sid])
		star_revealed.emit(sid)

# ── Tier queries ──────────────────────────────────────────────────────────
func planet_tier(pid: int) -> int:
	if visited_planet_ids.has(pid):
		return Tier.VISITED
	if discovered_planet_ids.has(pid):
		return Tier.DISCOVERED
	return Tier.UNKNOWN

func is_star_revealed(sid: int) -> bool:
	return revealed_star_ids.has(sid)

func _planet_idx(pid: int) -> int:
	# Galaxy.planets is generated in id order, so index == id in practice, but
	# guard against that ever changing.
	if pid >= 0 and pid < Galaxy.planets.size() and Galaxy.planets[pid].id == pid:
		return pid
	for i in Galaxy.planets.size():
		if Galaxy.planets[i].id == pid:
			return i
	return -1

# ── Debug: reveal / re-fog the whole galaxy (dev key in GalaxyView) ─────────
func reveal_all() -> void:
	for s in Galaxy.stars:
		revealed_star_ids[s.id] = true
	for p in Galaxy.planets:
		discovered_planet_ids[p.id] = true
		visited_planet_ids[p.id] = true
	discovery_changed.emit()
