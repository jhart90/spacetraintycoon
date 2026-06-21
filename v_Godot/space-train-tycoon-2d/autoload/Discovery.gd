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
	if not visited_planet_ids.has(pid):
		visited_planet_ids[pid] = true
		# TODO(Phase 2 / Economy): award the first-visit credit reward. Per
		# memory: reward = dist_from_Orijen > 100000 ? 3000 : (otherStar ? 2000 : 1000),
		# plus a separate star-discovery reward. Verify against current JS.
	discovery_changed.emit()

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
