extends Node
## Galaxy — procedural generation + world model. Ported from build_game.py
## generateGalaxy() (~line 8339). See PLAN Phase 1, code map §15/§13.
##
## PHASE 1 SCOPE — LAYOUT GEOMETRY ONLY:
##   ✔ black-hole placement (4 quadrants)
##   ✔ star reject-sampling + sizes/colours
##   ✔ home star (Gigi Prime, M yellow) + closest-to-origin rule
##   ✔ planets: HOME_BIOMES fixed sequence (home) / bell distribution (others),
##     sizes, orbit radii, angles (incl. Orijen/lava/desert anchors), biome,
##     _initialOrbitAngle snapshot, world x/y
##   ✔ system-overlap correction + close-neighbour "almost touching"
##   ✔ alien-relic placement (4×4 sector grid, one per sector)
##
## STUBBED (TODO Phase 2/5 — they consume RNG in the JS, so bit-exact parity
## with the JS stream is NOT yet claimed; see PLAN §9):
##   ✗ population / supply / demand / economic health / cargo seeding (Economy)
##   ✗ moons / clouds / rings / catchphrase (cosmetic → Phase 5)
##   ✗ mission-role seeding (flowers/colony/famine/outbreak/bh) + gold/diamond
##   ✗ AI mirror-system transform (_initAICorp)
##
## RNG: mulberry32 (deterministic, seedable). The JS currently uses unseeded
## Math.random(); swapping it to this same algorithm + matching the call order
## is what would upgrade us from invariant-parity to bit-exact parity.

# ── World model (populated by generate()) ─────────────────────────────────
var stars: Array = []        # {id,x,y,size,radius,colorName,name,planetIds[]}
var planets: Array = []      # {id,starId,orbitRadius,orbitAngle,orbitSpeed,_initialOrbitAngle,x,y,size,radius,type,name,isStarter,hasStation,isAlienRelic}
var black_holes: Array = []  # {x,y,radius}
var nebulas: Array = []      # {x,y,rx,ry,rot,colorIdx,secColorIdx,seed,name} (build_game.py _genNebulas)

# 5 base colour bands (HSL h,s,l) — deep purple/red/pink/blue/yellow.
const NEBULA_PALETTE := [[268, 62, 32], [0, 70, 30], [328, 62, 34], [220, 72, 34], [45, 62, 36]]
const NEBULA_NAME_POOL := [
	"Carina", "Orion", "Eagle", "Crab", "Helix", "Veil", "Tarantula", "Horsehead",
	"Phoenix", "Serpent", "Drake", "Ghost", "Wolf", "Lotus", "Storm", "Spire",
	"Crystal", "Mirror", "Ember", "Echo", "Whisper", "Halo", "Crown", "Anvil",
	"Forge", "Garden", "Bloom", "Spectre", "Phantom", "Shroud", "Crescent", "Beacon",
	"Vault", "Talon", "Wing", "Lantern", "Cinder", "Vortex", "Cradle", "Pyre",
	"Cascade", "Glimmer", "Quasar", "Argent", "Verdant", "Vermilion", "Azure", "Obsidian",
	"Aurora", "Borealis", "Aether", "Empyrean", "Hyperion", "Sigil", "Arcanum", "Solstice",
	"Equinox", "Zenith", "Nadir", "Penumbra", "Umbra", "Astra", "Lumen", "Radiant", "Dusk", "Dawn",
]
var home_star_id: int = 0
var origen_id: int = 0       # the starter planet's id
var _seed: int = 0

# ── Seedable RNG (mulberry32) ─────────────────────────────────────────────
var _rng_state: int = 0

func _set_seed(s: int) -> void:
	_seed = s
	_rng_state = s & 0xFFFFFFFF

func random() -> float:
	# mulberry32 — matches the canonical JS reference bit-for-bit.
	_rng_state = (_rng_state + 0x6D2B79F5) & 0xFFFFFFFF
	var t: int = _rng_state
	t = (t ^ (t >> 15)) * (t | 1) & 0xFFFFFFFF
	t = (t ^ (t + ((t ^ (t >> 7)) * (t | 61) & 0xFFFFFFFF))) & 0xFFFFFFFF
	return float((t ^ (t >> 14)) & 0xFFFFFFFF) / 4294967296.0

func rand(a: float, b: float) -> float:
	return random() * (b - a) + a

func randInt(a: int, b: int) -> int:
	return int(floor(rand(float(a), float(b) + 0.999)))

func pick(arr: Array):
	return arr[int(floor(random() * arr.size()))]

func _pick_size() -> String:
	var tot := 0
	for x in Tuning.SIZE_W:
		tot += x.w
	var r := random() * tot
	for x in Tuning.SIZE_W:
		r -= x.w
		if r <= 0:
			return x.s
	return "M"

func _pick_star_size() -> String:
	var r := random()
	if r < 0.55:
		return "S"
	if r < 0.85:
		return "M"
	return "L"

func _pick_star_color(sz: String) -> String:
	if sz == "S":
		return pick(Tuning.STAR_COLORS_S)
	if sz == "M":
		return pick(Tuning.STAR_COLORS_M)
	return pick(Tuning.STAR_COLORS_L)

func _bell_planet_count() -> int:
	var u := 0.0
	for i in 6:
		u += random()
	return int(clamp(round((u - 3.0) * 2.828 + 4.0), 1, 12))

func _pick_biome_weighted() -> Dictionary:
	var total := 0.0
	for pt in Tuning.PTYPES:
		total += Tuning.BIOME_WEIGHTS.get(pt.id, 1.0)
	var r := random() * total
	for pt in Tuning.PTYPES:
		r -= Tuning.BIOME_WEIGHTS.get(pt.id, 1.0)
		if r <= 0:
			return pt
	return Tuning.PTYPES[0]

# ── Generation ────────────────────────────────────────────────────────────
func generate(seed: int) -> void:
	_set_seed(seed)
	stars = []
	planets = []
	black_holes = []
	nebulas = []
	var pid := 0
	var W: float = Tuning.WORLD_W
	var H: float = Tuning.WORLD_H

	# Black holes: one per quadrant, placed before stars (build_game.py:8362).
	var bh_quad := [[1, 1], [-1, 1], [-1, -1], [1, -1]]
	for q in bh_quad:
		var bhR := randInt(6000, 10000)
		for _ba in 400:
			var bx: float = rand(8000.0, W - 14000.0) * float(q[0])
			var by: float = rand(8000.0, H - 14000.0) * float(q[1])
			if sqrt(bx * bx + by * by) < 35000.0:
				continue
			var apart := true
			for b in black_holes:
				if Vector2(b.x - bx, b.y - by).length() < 40000.0:
					apart = false
					break
			if not apart:
				continue
			black_holes.append({"x": bx, "y": by, "radius": float(bhR)})
			break

	# Reject-sample star positions (build_game.py:8378).
	var attempt := 0
	while attempt < 25000 and stars.size() < 300:
		attempt += 1
		var sz := _pick_star_size()
		var sr: float = Tuning.STAR_R[sz]
		var x := rand(-W + 9500.0, W - 9500.0)
		var y := rand(-H + 9500.0, H - 9500.0)
		var ok := true
		for s in stars:
			if Vector2(s.x - x, s.y - y).length() <= s.radius + sr + 12000.0:
				ok = false
				break
		if not ok:
			continue
		for b in black_holes:
			if Vector2(b.x - x, b.y - y).length() < b.radius + sr + 9000.0:
				ok = false
				break
		if not ok:
			continue
		var cn := _pick_star_color(sz)
		stars.append({
			"id": stars.size(), "x": x, "y": y, "size": sz, "radius": sr,
			"colorName": cn, "name": "S%d" % stars.size(), "planetIds": [],
		})

	# Home star = closest to origin (build_game.py:8390), forced M yellow Gigi Prime.
	home_star_id = 0
	var minD := INF
	for s in stars:
		var d: float = Vector2(s.x, s.y).length()
		if d < minD:
			minD = d
			home_star_id = s.id
	if not stars.is_empty():
		var hs: Dictionary = stars[home_star_id]
		hs.name = "Gigi Prime"
		hs.size = "M"
		hs.radius = Tuning.STAR_R["M"]
		hs.colorName = "yellow"

	# Planets per star.
	origen_id = 0
	for star in stars:
		var isHome: bool = star.id == home_star_id
		var np: int = Tuning.HOME_BIOMES.size() if isHome else _bell_planet_count()
		var orbitCap: float = Tuning.HOME_ORBIT_CAP if isHome else Tuning.STAR_ORBIT_CAP
		var boundLimit: float = min(W - abs(star.x), H - abs(star.y)) - 400.0
		var orbitR: float = star.radius * 1.8 + 400.0
		var dominantDir: int = 1 if random() < 0.5 else -1
		var homeOrijenAngle: float = (PI if dominantDir > 0 else 0.0) if isHome else 0.0
		var homeLavaAngle = null
		for i in np:
			var isStarter: bool = isHome and i == 1
			var psz: String = "L" if isStarter else ("M" if (isHome and i == 0) else _pick_size())
			var pr: float = Tuning.SIZE_R[psz]
			orbitR += pr + (rand(280.0, 720.0) if isHome else rand(300.0, 1200.0))
			if not isHome and orbitR > orbitCap:
				break
			if orbitR + pr > boundLimit:
				break
			var angle := rand(0.0, TAU)
			if isHome and i == 0:
				angle = homeOrijenAngle + (random() * 2.0 - 1.0) * (PI / 6.0)
				homeLavaAngle = angle
			elif isHome and i == 1:
				angle = homeOrijenAngle
			elif isHome and i == 2 and homeLavaAngle != null:
				angle = homeLavaAngle
			var forceDominant: bool = isHome and (i == 0 or i == 1)
			var dir: int = dominantDir if forceDominant else (-dominantDir if random() < 0.02 else dominantDir)
			var spd := 0.00025 * sqrt(800.0 / orbitR) * dir
			var typeForSlot: Dictionary = Tuning.ptype(Tuning.HOME_BIOMES[i]) if isHome else _pick_biome_weighted()
			var p := {
				"id": pid, "starId": star.id,
				"orbitRadius": orbitR, "orbitAngle": angle, "orbitSpeed": spd,
				"_initialOrbitAngle": angle,
				"x": star.x + orbitR * cos(angle), "y": star.y + orbitR * sin(angle),
				"size": psz, "radius": pr,
				"type": typeForSlot,
				"name": "Orijen" if isStarter else "P%d" % pid,
				"isStarter": isStarter,
				"hasStation": false,   # set AFTER demand (JS order: 8532 demand, 8535 station)
				"isAlienRelic": false,
			}
			pid += 1
			if isStarter:
				origen_id = p.id
			_gen_planet_economy(p, isHome, isStarter, i)
			if isStarter:
				p.hasStation = true
			star.planetIds.append(p.id)
			planets.append(p)
			orbitR += pr + (rand(180.0, 520.0) if isHome else rand(200.0, 800.0))

	_separate_systems()
	_place_relics()
	_gen_nebulas()
	_assign_mission_roles()

# Pick the mission-role planets at gen (build_game.py:8831-9035). Simplified vs
# the JS quadrant logic: assign roles to distinct suitable populated planets.
func _assign_mission_roles() -> void:
	var cands: Array = []
	for p in planets:
		if bool(p.get("isStarter", false)) or bool(p.get("isAlienRelic", false)):
			continue
		if int(p.get("population", 0)) <= 0 or int(p.starId) == home_star_id:
			continue
		cands.append(p)
	if cands.size() >= 1:
		cands[0]["isFaminePlanet"] = true
	if cands.size() >= 2:
		cands[1]["isOutbreakPlanet"] = true
	if cands.size() >= 4:
		cands[2]["isColonyTrainSource"] = true
		cands[2]["colonyTrainDestId"] = int(cands[3].id)
	# Flowers origin: a jungle/desert/resort candidate gets sustained flower supply.
	for p in cands:
		var bio := String(p.type.id)
		if bio in ["jungle", "desert", "resort"] and not p.get("isFaminePlanet", false) and not p.get("isOutbreakPlanet", false) and not p.get("isColonyTrainSource", false):
			p["isFlowersOrigin"] = true
			if not p.has("supplyRate"):
				p["supplyRate"] = {}
			p.supplyRate["flowers"] = 6.0
			break
	# Black-hole research planet: the planet nearest any black hole.
	if not black_holes.is_empty():
		var best := -1
		var best_d := INF
		for p in planets:
			if bool(p.get("isStarter", false)):
				continue
			for b in black_holes:
				var d: float = Vector2(float(p.x) - float(b.x), float(p.y) - float(b.y)).length()
				if d < best_d:
					best_d = d
					best = int(p.id)
		if best >= 0:
			planets[best]["isBhResearchPlanet"] = true

# Named world-space nebulas (build_game.py _genNebulas:8307): 16 colored regions
# placed around Orijen, declumped, each with a distinct name + colour pair.
func _gen_nebulas() -> void:
	if origen_id < 0 or origen_id >= planets.size():
		return
	var ox: float = planets[origen_id].x
	var oy: float = planets[origen_id].y
	var pal_n := NEBULA_PALETTE.size()
	var smnx := -Tuning.WORLD_W + 5000.0
	var smxx := Tuning.WORLD_W - 5000.0
	var smny := -Tuning.WORLD_H + 5000.0
	var smxy := Tuning.WORLD_H - 5000.0
	var pool := NEBULA_NAME_POOL.duplicate()
	for k in range(pool.size() - 1, 0, -1):
		var j := int(random() * (k + 1))
		var tmp = pool[k]; pool[k] = pool[j]; pool[j] = tmp
	var name_idx := 0
	while nebulas.size() < 16:
		var a := random() * TAU
		var r := 40000.0 + random() * 280000.0
		var pri := int(random() * pal_n)
		var sec := int(random() * (pal_n - 1))
		if sec >= pri:
			sec += 1
		var size_mult := 2.0 if random() < 0.5 else 1.0
		nebulas.append({
			"x": clampf(ox + cos(a) * r, smnx, smxx),
			"y": clampf(oy + sin(a) * r, smny, smxy),
			"rx": (7500.0 + random() * 17500.0) * size_mult,
			"ry": (7500.0 + random() * 17500.0) * size_mult,
			"rot": float(int(random() * 4)) * (PI * 0.5),
			"colorIdx": pri, "secColorIdx": sec,
			"seed": int(random() * 2147483646.0) + 1, "name": String(pool[name_idx % pool.size()]),
		})
		name_idx += 1
	# Light declump: relocate the most-crowded nebula a few times.
	var cluster_r := 70000.0
	for _pass in 6:
		var worst := -1
		var worst_n := 1
		for i in nebulas.size():
			var cnt := 0
			for jj in nebulas.size():
				if jj != i and Vector2(nebulas[jj].x - nebulas[i].x, nebulas[jj].y - nebulas[i].y).length() < cluster_r:
					cnt += 1
			if cnt > worst_n:
				worst_n = cnt; worst = i
		if worst < 0:
			break
		for _try in 50:
			var a2 := random() * TAU
			var r2 := 40000.0 + random() * 280000.0
			var nx := clampf(ox + cos(a2) * r2, smnx, smxx)
			var ny := clampf(oy + sin(a2) * r2, smny, smxy)
			var far := true
			for b in nebulas.size():
				if b != worst and Vector2(nebulas[b].x - nx, nebulas[b].y - ny).length() < cluster_r:
					far = false; break
			if far:
				nebulas[worst].x = nx; nebulas[worst].y = ny
				break

# Per-planet economy generation (build_game.py 8498-8534, JS RNG order:
# population → desert-fix → gold → diamond → devLevel → agri → supply/demand →
# non-agri pre-built upgrades). Cosmetic RNG (clouds/moons/ring) is skipped.
func _gen_planet_economy(p: Dictionary, isHome: bool, isStarter: bool, home_idx: int) -> void:
	if isStarter:
		p.population = int(round(1e6 + random() * 9e6))
	else:
		p.population = Economy.generate_population(p)
	if isHome and home_idx == 2 and p.type.id == "desert" and int(p.population) == 0:
		p.population = int(round(5e4 + random() * 2e6))
	var goldBiomes := ["rocky", "desert", "resort", "jungle", "ocean"]
	p.hasGold = (not isHome) and (p.type.id in goldBiomes) and random() < 0.05
	p.hasDiamond = (not isHome) and (p.type.id in goldBiomes) and random() < 0.02
	if isStarter:
		p.devLevel = 3
	elif isHome:
		p.devLevel = randInt(1, 2)
	else:
		p.devLevel = randInt(0, 3)
	if p.type.id == "agri":
		var aR := random()
		if aR < 0.333:
			p.grainUnlocked = true; p.upgrades = ["granary"]
		elif aR < 0.667:
			p.livestockUnlocked = true; p.upgrades = ["farm"]
		else:
			p.fruitUnlocked = true; p.upgrades = ["orchard"]
	p.supplyRate = Economy.compute_supply_rate(p)
	p.demandRate = Economy.compute_demand_rate(p)
	p.economicHealth = Economy.compute_economic_health(p)
	Economy.seed_cargo_planet(p)
	if p.type.id != "agri":
		# Only pumping_station has preBuiltBiomes (ocean) (build_game.py:1240).
		p.upgrades = ["pumping_station"] if p.type.id == "ocean" else []


# ── System-overlap correction + close-neighbour (build_game.py:8556-8652) ──
func _separate_systems() -> void:
	var W: float = Tuning.WORLD_W
	var H: float = Tuning.WORLD_H
	var n := stars.size()
	var sysR := []
	sysR.resize(n)
	sysR.fill(0.0)
	for p in planets:
		sysR[p.starId] = max(sysR[p.starId], p.orbitRadius + p.radius)

	var GAP: float = Tuning.SYS_GAP
	for _pass in 40:
		var anyOverlap := false
		for i in n:
			for j in range(i + 1, n):
				var si: Dictionary = stars[i]
				var sj: Dictionary = stars[j]
				var dx: float = sj.x - si.x
				var dy: float = sj.y - si.y
				var dist: float = max(Vector2(dx, dy).length(), 1.0)
				var need: float = sysR[i] + sysR[j] + GAP
				if dist >= need:
					continue
				anyOverlap = true
				var push := (need - dist) * 0.5 + 1.0
				var ux := dx / dist
				var uy := dy / dist
				si.x -= ux * push; si.y -= uy * push
				sj.x += ux * push; sj.y += uy * push
				var m: float = float(sysR[i]) + 200.0
				var mj: float = float(sysR[j]) + 200.0
				si.x = clamp(si.x, -W + m, W - m)
				si.y = clamp(si.y, -H + m, H - m)
				sj.x = clamp(sj.x, -W + mj, W - mj)
				sj.y = clamp(sj.y, -H + mj, H - mj)
		if not anyOverlap:
			break
	_resync_planets()

	# Close-neighbour "almost touching" (build_game.py:8598).
	var homeMaxOrbit: float = sysR[home_star_id]
	var home: Dictionary = stars[home_star_id]
	var nearIdx := -1
	var nearDist := INF
	for i in n:
		if i == home_star_id:
			continue
		var d: float = Vector2(stars[i].x - home.x, stars[i].y - home.y).length()
		if d < nearDist:
			nearDist = d
			nearIdx = i
	if nearIdx >= 0:
		var nb: Dictionary = stars[nearIdx]
		var nbSysR: float = sysR[nearIdx]
		var edgeGap := rand(300.0, 550.0)
		var targetDist := homeMaxOrbit + nbSysR + edgeGap
		var dx2: float = nb.x - home.x
		var dy2: float = nb.y - home.y
		var cur2: float = max(Vector2(dx2, dy2).length(), 1.0)
		nb.x = home.x + dx2 * (targetDist / cur2)
		nb.y = home.y + dy2 * (targetDist / cur2)
		nb.x = clamp(nb.x, -W + nbSysR + 400.0, W - nbSysR - 400.0)
		nb.y = clamp(nb.y, -H + nbSysR + 400.0, H - nbSysR - 400.0)
		for _pass2 in 30:
			var anyOverlap := false
			for i in n:
				for j in range(i + 1, n):
					if (i == home_star_id and j == nearIdx) or (i == nearIdx and j == home_star_id):
						continue
					var si: Dictionary = stars[i]
					var sj: Dictionary = stars[j]
					var ddx: float = sj.x - si.x
					var ddy: float = sj.y - si.y
					var dd: float = max(Vector2(ddx, ddy).length(), 1.0)
					var need: float = sysR[i] + sysR[j] + GAP
					if dd >= need:
						continue
					anyOverlap = true
					var push := (need - dd) * 0.5 + 1.0
					var ux := ddx / dd
					var uy := ddy / dd
					si.x -= ux * push; si.y -= uy * push
					sj.x += ux * push; sj.y += uy * push
					si.x = clamp(si.x, -W + sysR[i] + 200.0, W - sysR[i] - 200.0)
					si.y = clamp(si.y, -H + sysR[i] + 200.0, H - sysR[i] - 200.0)
					sj.x = clamp(sj.x, -W + sysR[j] + 200.0, W - sysR[j] - 200.0)
					sj.y = clamp(sj.y, -H + sysR[j] + 200.0, H - sysR[j] - 200.0)
			if not anyOverlap:
				break
		_resync_planets()

## Advance every planet along its orbit (build_game.py updatePlanetOrbits core,
## ~14467). The JS LOD/viewport-culling is a perf optimisation we don't need —
## a flat loop over ~1050 planets per tick is trivial. dtG = game-time delta.
func advance_orbits(dtG: float) -> void:
	for p in planets:
		p.orbitAngle += p.orbitSpeed * dtG
		var star: Dictionary = stars[p.starId]
		p.x = star.x + p.orbitRadius * cos(p.orbitAngle)
		p.y = star.y + p.orbitRadius * sin(p.orbitAngle)
		# TODO(Phase 5): station-angle / cloud-angle / moon spin (cosmetic).


func _resync_planets() -> void:
	for p in planets:
		var star: Dictionary = stars[p.starId]
		p.x = star.x + p.orbitRadius * cos(p.orbitAngle)
		p.y = star.y + p.orbitRadius * sin(p.orbitAngle)

# ── Alien relics: one per 4×4 sector (build_game.py:8657) ──────────────────
func _place_relics() -> void:
	var W: float = Tuning.WORLD_W
	var H: float = Tuning.WORLD_H
	var homePids := {}
	if not stars.is_empty():
		for id in stars[home_star_id].planetIds:
			homePids[id] = true
	var relicStarIds := {}
	for sc in 4:
		for sr in 4:
			var sxMin := -W + sc * (W / 2.0)
			var sxMax := -W + (sc + 1) * (W / 2.0)
			var syMin := -H + sr * (H / 2.0)
			var syMax := -H + (sr + 1) * (H / 2.0)
			var cands := []
			for p in planets:
				if p.isStarter or p.hasStation:
					continue
				if homePids.has(p.id) or relicStarIds.has(p.starId):
					continue
				if p.x >= sxMin and p.x < sxMax and p.y >= syMin and p.y < syMax:
					cands.append(p)
			if cands.is_empty():
				continue
			var rp: Dictionary = cands[int(floor(random() * cands.size()))]
			rp.hasStation = true
			rp.isAlienRelic = true
			relicStarIds[rp.starId] = true
