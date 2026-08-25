extends Node3D
## Main — root of the running game. Wires together the two halves of the hybrid
## render target (PLAN §3): the 3D world and the 2D HUD CanvasLayer.
##
## Both are built in code (no fragile hand-authored .tscn sub-scenes) and talk
## only through the GameState autoload. Main itself is intentionally thin.

const GalaxyView := preload("res://world/GalaxyView.gd")
const HUD := preload("res://ui/HUD.gd")

func _ready() -> void:
	# Parity/invariant harness (PLAN §9): `godot --headless -- --check-galaxy`.
	if "--check-galaxy" in OS.get_cmdline_user_args():
		var failures := _run_galaxy_checks()
		get_tree().quit(failures)
		return
	# 3D world first so the HUD CanvasLayer composites on top (PLAN §3 z-order:
	# this replaces the old "HD text overlay composited last" hack entirely).
	add_child(GalaxyView.new())
	add_child(HUD.new())


## Generates the galaxy and asserts the structural invariants from
## build_game.py generateGalaxy(). Prints a report; returns the failure count
## (used as the process exit code so CI/shell can detect regressions).
func _run_galaxy_checks() -> int:
	var fails := 0
	var seed := 12345

	Galaxy.generate(seed)
	var stars: Array = Galaxy.stars
	var planets: Array = Galaxy.planets

	print("=== GALAXY INVARIANT CHECK (seed %d) ===" % seed)
	print("stars=%d  planets=%d  black_holes=%d" % [stars.size(), planets.size(), Galaxy.black_holes.size()])

	fails += _expect(not stars.is_empty(), "at least one star generated")

	# Home star: Gigi Prime, size M.
	var home: Dictionary = stars[Galaxy.home_star_id]
	fails += _expect(home.name == "Gigi Prime", "home star named 'Gigi Prime' (got '%s')" % home.name)
	fails += _expect(home.size == "M", "home star size M (got %s)" % home.size)

	# Home planets: exactly 6, biomes == HOME_BIOMES, Orijen at index 1 (L, starter).
	var home_planets := []
	for pid in home.planetIds:
		home_planets.append(planets[_find_planet_idx(planets, pid)])
	fails += _expect(home_planets.size() == 6, "home star has 6 planets (got %d)" % home_planets.size())
	if home_planets.size() == 6:
		var biomes := []
		for hp in home_planets:
			biomes.append(hp.type.id)
		fails += _expect(biomes == Tuning.HOME_BIOMES, "home biome sequence %s == %s" % [biomes, Tuning.HOME_BIOMES])
		var orijen: Dictionary = home_planets[1]
		fails += _expect(orijen.isStarter and orijen.name == "Orijen", "index-1 planet is starter 'Orijen'")
		fails += _expect(orijen.size == "L", "Orijen is size L (got %s)" % orijen.size)
		fails += _expect(orijen.id == Galaxy.origen_id, "origen_id points at Orijen")

	# Black holes: ≤4, each ≥35000 from origin.
	fails += _expect(Galaxy.black_holes.size() <= 4, "at most 4 black holes")
	for b in Galaxy.black_holes:
		fails += _expect(Vector2(b.x, b.y).length() >= 35000.0, "black hole clear of home region")

	# Alien relics: ≤16 (one per 4×4 sector), each hasStation + isAlienRelic.
	var relics := []
	for p in planets:
		if p.isAlienRelic:
			relics.append(p)
			fails += _expect(p.hasStation, "relic %d has a station" % p.id)
	fails += _expect(relics.size() <= 16, "at most 16 relics (got %d)" % relics.size())
	print("relics placed: %d" % relics.size())

	# System separation (excluding the home–neighbour pair, which is intentionally tight).
	var sysR := []
	sysR.resize(stars.size())
	sysR.fill(0.0)
	for p in planets:
		sysR[p.starId] = max(sysR[p.starId], p.orbitRadius + p.radius)
	var near_idx := _nearest_star_to_home(stars, sysR)
	var overlaps := 0
	for i in stars.size():
		for j in range(i + 1, stars.size()):
			if _is_home_neighbour_pair(i, j, near_idx):
				continue
			var d: float = Vector2(stars[j].x - stars[i].x, stars[j].y - stars[i].y).length()
			# Boundary clamping can leave small residual overlaps; allow 1% slack.
			if d < (sysR[i] + sysR[j] + Tuning.SYS_GAP) * 0.99:
				overlaps += 1
	print("residual system overlaps (excl. home-neighbour): %d" % overlaps)
	fails += _expect(overlaps == 0, "no residual system overlaps")

	# Economy generation (PLAN Phase 2, §5).
	var oi2 := _find_planet_idx(planets, Galaxy.origen_id)
	var orijenP: Dictionary = planets[oi2]
	var opop := int(orijenP.population)
	fails += _expect(opop >= 1000000 and opop <= 10000001, "Orijen population 1e6..1e7 (got %d)" % opop)
	fails += _expect(orijenP.get("supplyRate", {}).get("passengers", 0.0) > 0.0, "Orijen supplies passengers")
	var oeh: float = orijenP.get("economicHealth", 0.0)
	fails += _expect(oeh >= 0.3 and oeh <= 1.5, "Orijen economic health in [0.3,1.5] (got %.2f)" % oeh)
	var populated := 0
	var with_demand := 0
	for p in planets:
		if int(p.get("population", 0)) > 0:
			populated += 1
		if not (p.get("demandRate", {}) as Dictionary).is_empty():
			with_demand += 1
	print("economy: populated=%d/%d  with_demand=%d  (Orijen pop=%d, health=%.2f)" % [populated, planets.size(), with_demand, opop, oeh])
	fails += _expect(populated > 0 and with_demand > 0, "economy fields populated")

	# Discovery init + visit tracking (PLAN Phase 1, §10).
	Discovery.init_for_new_game()
	fails += _expect(Discovery.is_star_revealed(Galaxy.home_star_id), "home star revealed at init")
	fails += _expect(Discovery.planet_tier(Galaxy.origen_id) == Discovery.Tier.VISITED, "Orijen visited at init")
	var all_home_disc := true
	for pid in home.planetIds:
		if Discovery.planet_tier(pid) == Discovery.Tier.UNKNOWN:
			all_home_disc = false
	fails += _expect(all_home_disc, "all home-system planets discovered at init")
	var some_unrevealed := false
	for s in stars:
		if s.id != Galaxy.home_star_id and not Discovery.is_star_revealed(s.id):
			some_unrevealed = true
			break
	fails += _expect(some_unrevealed, "non-home stars start unrevealed (fog)")
	var other_pid := -1
	for p in planets:
		if p.starId != Galaxy.home_star_id:
			other_pid = p.id
			break
	if other_pid >= 0:
		Discovery.track_visit(other_pid)
		fails += _expect(Discovery.planet_tier(other_pid) == Discovery.Tier.VISITED, "track_visit marks planet visited")
		fails += _expect(Discovery.is_star_revealed(planets[_find_planet_idx(planets, other_pid)].starId), "track_visit reveals the star")

	# Transit + delivery (PLAN Phase 2 slice 3): build a train, route it between
	# two populated home planets, run the sim, and confirm credits increase from
	# real cargo revenue.
	GameState.start_new_game()
	Transit.reset()
	# Find a home planet (≠ Orijen) that DEMANDS passengers (some home biomes —
	# lava/chemical — are inhospitable and demand none).
	var pass_dest := -1
	for pid in home.planetIds:
		if pid == Galaxy.origen_id:
			continue
		if planets[_find_planet_idx(planets, pid)].get("demandRate", {}).has("passengers"):
			pass_dest = pid
			break
	if pass_dest >= 0:
		var t := Transit.build_train(Galaxy.origen_id, "engine_constellation", ["car_passenger"], true)
		Transit.assign_route(t, [Galaxy.origen_id, pass_dest])
		var credits_before := GameState.credits
		var dc := {"n": 0}  # Dictionary is a reference → lambda mutation is visible.
		var conn := func(_tid, _pid, _cargo, _rev): dc.n += 1
		Transit.train_delivered.connect(conn)
		for _i in 4000:
			Transit.tick(150.0)
			if dc.n >= 2:
				break
		Transit.train_delivered.disconnect(conn)
		print("transit: credits %d -> %d (%d deliveries)" % [credits_before, GameState.credits, dc.n])
		fails += _expect(GameState.credits > credits_before, "train delivery increases credits")
		fails += _expect(dc.n >= 1, "train completed at least one delivery")
	else:
		print("transit: no passenger-demanding home planet, skipping delivery check")

	# Missions (PLAN Phase 3): graph + lifecycle + chain + rewards + unlocks.
	GameState.start_new_game()
	Missions.start_new_game()
	fails += _expect(not Missions.def_for("build_foundry").is_empty(), "mission defs loaded")
	var mc0 := GameState.credits
	Missions.queue_intro("build_foundry")
	fails += _expect(Missions.is_active("build_foundry"), "build_foundry introduced (no car gate)")
	Missions.complete("build_foundry")
	fails += _expect(Missions.is_completed("build_foundry"), "build_foundry completed")
	fails += _expect(GameState.credits == mc0 + 10000, "build_foundry reward +10000 (got %d)" % (GameState.credits - mc0))
	fails += _expect(Missions.is_active("produce_iron"), "produce_iron chained (prereq build_foundry)")
	Missions.complete("produce_iron")
	fails += _expect(GameState.unlocked_upgrades.has("large_station"), "produce_iron unlocks large_station")
	fails += _expect(Missions.is_active("upgrade_station"), "upgrade_station chained (prereq produce_iron)")
	Missions.queue_intro("design_better_train")
	Missions.complete("design_better_train")
	fails += _expect(GameState.unlocked_engines.has("engine_classJ") and GameState.unlocked_engines.has("engine_classR"), "design_better_train unlocks Class J + R")
	Missions.queue_intro("dispose_hazmat")
	fails += _expect(not Missions.is_active("dispose_hazmat"), "dispose_hazmat car-gated (no hazmat car yet)")
	Missions.on_car_unlocked("car_hazmat")
	fails += _expect(Missions.is_active("dispose_hazmat"), "dispose_hazmat promotes after car_hazmat unlock")

	# AI rival corporation (PLAN Phase 3): builds trains, earns revenue, grows.
	GameState.start_new_game()
	Transit.reset()
	AICorp.init_corp("normal")
	fails += _expect(AICorp.home_star_id >= 0, "AI picked a home system")
	var ai_nw0 := AICorp.net_worth()
	for _i in 5000:
		Transit.tick(5000.0)
		AICorp.tick(5000.0)
	var ai_trains := 0
	for t in Transit.trains:
		if not t.isPlayer:
			ai_trains += 1
	print("AI: net_worth %d -> %d  trains=%d  revenue=%d" % [ai_nw0, AICorp.net_worth(), ai_trains, AICorp.total_revenue])
	fails += _expect(ai_trains > 0, "AI built trains")
	fails += _expect(AICorp.total_revenue > 0, "AI earned revenue")
	fails += _expect(AICorp.net_worth() > ai_nw0, "AI net worth grew")
	Transit.reset()

	# Save/Load round-trip (PLAN Phase 4 / §5).
	Galaxy.generate(seed)
	GameState.start_new_game()
	Missions.start_new_game()
	Transit.reset()
	AICorp.init_corp("normal")
	Missions.queue_intro("build_foundry")
	Missions.complete("build_foundry")
	GameState.credits = 777777  # set AFTER the mission reward so the target is exact
	GameState.stardate = 850.5
	Discovery.visited_planet_ids[Galaxy.origen_id] = true
	Galaxy.advance_orbits(500.0)
	var saved_angle: float = Galaxy.planets[Galaxy.origen_id].orbitAngle
	Transit.build_train(Galaxy.origen_id, "engine_galaxy", ["car_passenger"], true)
	var saved_seed := Galaxy._seed
	var spath := "user://test_save.json"
	fails += _expect(SaveLoad.save_game(spath), "save_game wrote file")
	GameState.credits = 0
	GameState.stardate = 0.0
	Transit.reset()
	Missions.start_new_game()
	Galaxy.generate(99999)
	fails += _expect(SaveLoad.load_game(spath), "load_game read file")
	fails += _expect(GameState.credits == 777777, "credits restored (got %d)" % GameState.credits)
	fails += _expect(absf(GameState.stardate - 850.5) < 0.001, "stardate restored")
	fails += _expect(Galaxy._seed == saved_seed, "galaxy seed restored")
	fails += _expect(Missions.is_completed("build_foundry"), "completed mission restored")
	fails += _expect(Discovery.visited_planet_ids.has(Galaxy.origen_id), "discovery restored")
	fails += _expect(Transit.trains.size() == 1, "trains restored (got %d)" % Transit.trains.size())
	fails += _expect(absf(Galaxy.planets[Galaxy.origen_id].orbitAngle - saved_angle) < 0.001, "planet orbit angle restored")
	print("saveload: credits=%d sd=%.2f trains=%d completed=%d" % [GameState.credits, GameState.stardate, Transit.trains.size(), Missions.completed.size()])
	Transit.reset()

	# Live mission trigger (Phase 4): 100 passenger deliveries → research_royal_car.
	Galaxy.generate(seed)
	GameState.start_new_game()
	Missions.start_new_game()
	Transit.reset()
	var rd := -1
	for pid in Galaxy.stars[Galaxy.home_star_id].planetIds:
		if pid != Galaxy.origen_id and Galaxy.planets[pid].get("demandRate", {}).has("passengers"):
			rd = pid
			break
	if rd >= 0:
		var pt := Transit.build_train(Galaxy.origen_id, "engine_N700", ["car_passenger"], true)
		Transit.assign_route(pt, [Galaxy.origen_id, rd])
		for _i in 30000:
			Transit.tick(300.0)
			if Missions.is_active("research_royal_car"):
				break
		print("live-mission: passengers=%d research_royal_car_active=%s" % [GameState.total_passengers_delivered, Missions.is_active("research_royal_car")])
		fails += _expect(GameState.total_passengers_delivered >= 100, "100+ passengers delivered")
		fails += _expect(Missions.is_active("research_royal_car"), "research_royal_car fired at 100 passengers")
	Transit.reset()

	# Interactive player actions (PLAN Phase 4): build station → foundry completes
	# build_foundry → chains produce_iron; train cost + engine-lock validation.
	Galaxy.generate(seed)
	GameState.start_new_game()
	Missions.start_new_game()
	Transit.reset()
	fails += _expect(Missions.is_active("build_foundry"), "build_foundry active at game start")
	var desert := -1
	for pid in Galaxy.stars[Galaxy.home_star_id].planetIds:
		if Galaxy.planets[pid].type.id == "desert":
			desert = pid
			break
	fails += _expect(desert >= 0, "home desert planet found")
	if desert >= 0:
		var pc0 := GameState.credits
		fails += _expect(Player.build_station(desert), "build_station succeeds")
		fails += _expect(Galaxy.planets[desert].hasStation, "desert has station after build")
		fails += _expect(GameState.credits == pc0 - 50000, "station cost deducted")
		fails += _expect(Player.build_upgrade(desert, "iron_foundry"), "build iron_foundry succeeds")
		fails += _expect(Missions.is_completed("build_foundry"), "build_foundry completed via station+foundry")
		fails += _expect(Missions.is_active("produce_iron"), "produce_iron chained after build_foundry")
		var tc0 := GameState.credits
		var tr := Player.build_train(Galaxy.origen_id, "engine_constellation", ["car_passenger"])
		fails += _expect(not tr.is_empty(), "build_train returns a train")
		fails += _expect(GameState.credits == tc0 - 11000, "train cost deducted (10000+1000)")
		var tr2 := Player.build_train(Galaxy.origen_id, "engine_N700", ["car_passenger"])
		fails += _expect(tr2.is_empty(), "locked engine (N700) rejected")
		print("player: credits=%d trains=%d" % [GameState.credits, Transit.trains.size()])
	Transit.reset()

	# UI popups smoke test (Phase 4): each builds without error.
	Galaxy.generate(seed)
	GameState.start_new_game()
	Missions.start_new_game()
	Transit.reset()
	GameState.select("planet", "planet_%d" % Galaxy.origen_id, "Orijen")
	Discovery.visited_planet_ids[Galaxy.origen_id] = true
	var pops := preload("res://ui/Popups.gd").new()
	add_child(pops)
	for nm in ["options", "routes", "stations", "finances", "planet_detail"]:
		pops.open_popup(nm)
		fails += _expect(pops.visible, "popup '%s' built+opened" % nm)
	pops.queue_free()
	var clog := preload("res://ui/ChatLog.gd").new()
	add_child(clog)
	clog.add("smoke test", "#fff")
	fails += _expect(true, "chat log built")
	clog.queue_free()
	# Tutorial: exercise its step checks without error (phase GALAXY).
	GameState.phase = GameState.Phase.GALAXY
	var tut := preload("res://ui/Tutorial.gd").new()
	add_child(tut)
	tut._process(0.1)
	tut._process(0.1)
	fails += _expect(true, "tutorial step checks ran")
	tut.queue_free()
	GameState.clear_selection()

	# Determinism: same seed → identical layout signature.
	var sig1 := _layout_signature()
	Galaxy.generate(seed)
	var sig2 := _layout_signature()
	fails += _expect(sig1 == sig2, "generation is deterministic for a fixed seed")

	# Orbital motion (Phase 2): planets advance deterministically.
	Galaxy.generate(seed)
	var oi := _find_planet_idx(Galaxy.planets, Galaxy.origen_id)
	var ox: float = Galaxy.planets[oi].x
	Galaxy.advance_orbits(1000.0)
	fails += _expect(absf(Galaxy.planets[oi].x - ox) > 0.001, "advance_orbits moves planets")
	Galaxy.generate(seed); Galaxy.advance_orbits(1000.0)
	var ax: float = Galaxy.planets[oi].x
	Galaxy.generate(seed); Galaxy.advance_orbits(1000.0)
	fails += _expect(absf(ax - Galaxy.planets[oi].x) < 1e-6, "advance_orbits deterministic")

	print("=== CHECK %s (%d failures) ===" % ["PASS" if fails == 0 else "FAIL", fails])
	return fails


func _expect(cond: bool, label: String) -> int:
	print(("  [OK] " if cond else "  [XX] ") + label)
	return 0 if cond else 1


func _find_planet_idx(planets: Array, pid: int) -> int:
	for i in planets.size():
		if planets[i].id == pid:
			return i
	return -1


func _nearest_star_to_home(stars: Array, _sysR: Array) -> int:
	var home: Dictionary = stars[Galaxy.home_star_id]
	var near_idx := -1
	var near_d := INF
	for i in stars.size():
		if i == Galaxy.home_star_id:
			continue
		var d: float = Vector2(stars[i].x - home.x, stars[i].y - home.y).length()
		if d < near_d:
			near_d = d
			near_idx = i
	return near_idx


func _is_home_neighbour_pair(i: int, j: int, near_idx: int) -> bool:
	var h := Galaxy.home_star_id
	return (i == h and j == near_idx) or (i == near_idx and j == h)


func _layout_signature() -> String:
	var acc := 0.0
	for s in Galaxy.stars:
		acc += s.x * 0.5 + s.y * 0.25 + s.radius
	for p in Galaxy.planets:
		acc += p.x * 0.125 + p.y * 0.0625
	return "%d/%d/%.3f" % [Galaxy.stars.size(), Galaxy.planets.size(), acc]
