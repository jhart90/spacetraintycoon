extends Node2D
## Main — root of the faithful 2D recreation. Wires the 2D world (GalaxyView2D)
## and the 2D HUD CanvasLayer. Both are built in code and talk only through the
## autoloads. The sim autoloads are copied verbatim from the 3D port; this file
## also preserves the `--check-galaxy` parity harness so we can re-verify the
## copied sim still matches build_game.py after the move.

const GalaxyView2D := preload("res://world/GalaxyView2D.gd")
const HUD := preload("res://ui/HUD.gd")
const Screens := preload("res://ui/Screens.gd")

func _ready() -> void:
	# Sim re-verification harness: `godot --headless -- --check-galaxy`.
	if "--check-galaxy" in OS.get_cmdline_user_args():
		var failures := _run_galaxy_checks()
		get_tree().quit(failures)
		return
	var gv := GalaxyView2D.new()
	gv.name = "GalaxyView2D"
	add_child(gv)
	var hud := HUD.new()
	add_child(hud)
	# ── Frame-time profiler: `-- --profile` runs ~200 frames, prints avg/max ms.
	# Bisect with --no-content / --no-bg / --no-trains / --no-labels / --no-hud.
	var ua := OS.get_cmdline_user_args()
	if "--no-content" in ua: gv._content.visible = false
	if "--no-bg" in ua: gv._bg.visible = false
	if "--no-trains" in ua: gv._trains.visible = false
	if "--no-labels" in ua: gv._labels.visible = false
	if "--no-hud" in ua: hud.visible = false
	if "--no-fog" in ua: Fog.enabled = false
	if "--no-clouds" in ua: gv._content.set("clouds_off", true)
	if "--profile" in ua:
		_profiling = true
		set_process(true)
	# ── M6 front-end: title → corp setup → opponent select → galaxy. A normal boot
	# opens on the title; any dev flag boots straight into the galaxy (bare
	# --shot/--advance gets the faithful train-tracked start).
	var screens_layer := CanvasLayer.new()
	screens_layer.layer = 20
	var screens := Screens.new()
	screens.view = gv
	screens_layer.add_child(screens)
	add_child(screens_layer)
	var _force_screen := ""
	var _load_stt := ""
	for a in ua:
		if a.begins_with("--screen="):
			_force_screen = a.split("=")[1]
		elif a.begins_with("--load-stt="):
			_load_stt = a.split("=", true, 1)[1]
	var _roundtrip := ""
	for a in ua:
		if a.begins_with("--save-roundtrip="):
			_roundtrip = a.split("=", true, 1)[1]
	if _load_stt != "":
		# Load an original .stt save and boot straight into it (test / play path).
		var ok := SaveLoad.load_stt(_load_stt)
		print("LOAD-STT %s: %s | planets=%d stars=%d trains=%d credits=%d SD=%.1f" % [_load_stt, "OK" if ok else "FAIL", Galaxy.planets.size(), Galaxy.stars.size(), Transit.trains.size(), GameState.credits, GameState.stardate])
		if _roundtrip != "":
			var sok := SaveLoad.save_game(_roundtrip)
			var lok := SaveLoad.load_game(_roundtrip)
			print("ROUNDTRIP save=%s load=%s | planets=%d stars=%d trains=%d credits=%d SD=%.1f corp=%s" % ["OK" if sok else "FAIL", "OK" if lok else "FAIL", Galaxy.planets.size(), Galaxy.stars.size(), Transit.trains.size(), GameState.credits, GameState.stardate, GameState.corp_name])
		GameState.set_screen("galaxy")
		gv.enter_galaxy()
	elif ua.is_empty():
		GameState.set_screen("title")
	elif _force_screen != "":
		GameState.set_screen(_force_screen)  # dev: capture a front-end screen
	else:
		GameState.set_screen("galaxy")
		var _has_cam := false
		for a in ua:
			if a.begins_with("--scale") or a.begins_with("--center") or a.begins_with("--select"):
				_has_cam = true
		if not _has_cam:
			gv.enter_galaxy()
	# Dev screenshot mode: `--shot[=path]` renders a few frames then saves a PNG
	# and quits (used to validate _draw + capture milestone proof headless-style).
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--advance="):
			var n := int(a.split("=")[1])
			for _i in n:
				Galaxy.advance_orbits(20.0)
				Economy.accumulate(20.0 * Tuning.SD_PER_DTG)
				Transit.tick(20.0)
				AICorp.tick(20.0)
				Fog.update(20.0 * Tuning.SD_PER_DTG)
		elif a.begins_with("--test-unlock="):
			var uid := a.split("=", true, 1)[1]
			if uid.begins_with("engine_"): GameState.engine_unlocked.emit(uid)
			else: GameState.car_unlocked.emit(uid)
		elif a.begins_with("--test-reward="):
			Missions.mission_completed.emit("build_foundry", int(a.split("=", true, 1)[1]))
		elif a.begins_with("--test-mission="):
			Missions.mission_introduced.emit(a.split("=", true, 1)[1])
		elif a == "--test-firstdelivery":
			GameState.first_delivery.emit(Galaxy.origen_id, "passengers", "car_passenger", GameState.stardate)
		elif a == "--test-gold":
			Discovery.gold_discovered.emit(Galaxy.origen_id)
		elif a == "--test-diamond":
			Discovery.diamond_discovered.emit(Galaxy.origen_id)
		elif a.begins_with("--test-upgrade="):
			GameState.upgrade_unlocked.emit(a.split("=", true, 1)[1])
		elif a == "--test-ceohire":
			if GameState.ceo.is_empty():
				GameState.set_ceo(GameState._gen_ceo("Gigi", "ceo_gigi"))
			GameState.roll_ceo_candidates()
			GameState.popup_requested.emit("ceohire")
		elif a == "--expand":
			GameState.panel_expanded = true
		elif a == "--rival":
			AICorp.init_corp("normal")
		elif a == "--bigstation":
			Galaxy.planets[Galaxy.origen_id].hasStation = true
			Galaxy.planets[Galaxy.origen_id].hasTerminal = true
		elif a.begins_with("--popup="):
			GameState.popup_requested.emit(a.split("=")[1])
		elif a.begins_with("--select="):
			var what := a.split("=")[1]
			if what == "planet":
				GameState.select("planet", "planet_%d" % Galaxy.origen_id, "Orijen")
			elif what == "star":
				GameState.select("star", "star_%d" % Galaxy.home_star_id, "Gigi Prime")
			elif what == "train" and not Transit.trains.is_empty():
				GameState.select("train", "train_%d" % int(Transit.trains[0].id), "Train")
		elif a.begins_with("--click-test="):
			var xy := a.split("=", true, 1)[1].split(",")
			_click_test = Vector2(float(xy[0]), float(xy[1]))
			set_process(true)
		elif a.begins_with("--shot-wait="):
			_shot_min_frames = int(a.split("=")[1])
		elif a.begins_with("--shot"):
			_shot_path = a.split("=")[1] if "=" in a else "res://_shot.png"
			set_process(true)
		elif a.begins_with("--scale="):
			gv.sc = float(a.split("=")[1])
			var ctr: Dictionary = Galaxy.planets[Galaxy.origen_id]
			if "--center=star" in OS.get_cmdline_user_args():
				ctr = Galaxy.stars[Galaxy.home_star_id]
			elif "--center=train" in OS.get_cmdline_user_args() and not Transit.trains.is_empty():
				ctr = Transit.trains[0]
			elif "--center=relic" in OS.get_cmdline_user_args():
				for pp in Galaxy.planets:
					if bool(pp.get("isAlienRelic", false)):
						ctr = pp
						break
			elif "--center=lava" in OS.get_cmdline_user_args():
				for pid in Galaxy.stars[Galaxy.home_star_id].planetIds:
					if String(Galaxy.planets[pid].type.id) == "lava":
						ctr = Galaxy.planets[pid]
						break
			elif "--center=urban" in OS.get_cmdline_user_args():
				for pp in Galaxy.planets:
					if String(pp.type.id) == "urban" and int(pp.radius) >= 150:
						ctr = pp
						break
			elif "--center=ancient" in OS.get_cmdline_user_args():
				var best := -1.0
				for pp in Galaxy.planets:
					if String(pp.type.id) == "ancient" and float(pp.radius) > best:
						best = float(pp.radius)
						ctr = pp
			elif "--center=agri" in OS.get_cmdline_user_args():
				for pid in Galaxy.stars[Galaxy.home_star_id].planetIds:
					if String(Galaxy.planets[pid].type.id) == "agri":
						ctr = Galaxy.planets[pid]
						break
			elif "--center=oil" in OS.get_cmdline_user_args():
				var best := -1.0
				for pp in Galaxy.planets:
					if String(pp.type.id) == "oil" and float(pp.radius) > best:
						best = float(pp.radius)
						ctr = pp
			elif "--center=gold" in OS.get_cmdline_user_args():
				var best := -1.0
				for pp in Galaxy.planets:
					if bool(pp.get("hasGold", false)) and float(pp.radius) > best:
						best = float(pp.radius)
						ctr = pp
			elif "--center=bh" in OS.get_cmdline_user_args():
				if not Galaxy.black_holes.is_empty():
					ctr = Galaxy.black_holes[0]
			elif "--center=train" in OS.get_cmdline_user_args():
				if not Transit.trains.is_empty():
					ctr = {"x": Transit.trains[0].x, "y": Transit.trains[0].y}
			gv.cam = Vector2(ctr.x, ctr.y)
			gv._clamp_camera()


var _shot_path := ""
var _shot_frames := 0
var _shot_min_frames := 30  # raised by --shot-wait for async (network) content
var _click_test := Vector2.INF
var _click_frames := 0
var _profiling := false
var _prof_frames := 0
var _prof_accum := 0.0
var _prof_max := 0.0
var _prof_last := 0

func _process(_delta: float) -> void:
	if _click_test != Vector2.INF:
		_click_frames += 1
		if _click_frames == 40:
			print("CLICK-TEST before: gs=%s" % GameState.gs)
			for pressed in [true, false]:
				var ev := InputEventMouseButton.new()
				ev.button_index = MOUSE_BUTTON_LEFT
				ev.pressed = pressed
				ev.position = _click_test
				Input.parse_input_event(ev)
		elif _click_frames == 45:
			print("CLICK-TEST after: gs=%s" % GameState.gs)
			get_tree().quit()
		return
	if _profiling:
		var now := Time.get_ticks_usec()
		if _prof_last > 0 and _prof_frames < 220:
			var ms := float(now - _prof_last) / 1000.0
			if _prof_frames >= 20:  # skip warmup
				_prof_accum += ms
				_prof_max = maxf(_prof_max, ms)
			_prof_frames += 1
		elif _prof_frames >= 220:
			var n := float(_prof_frames - 20)
			var avg := _prof_accum / n
			print("PROFILE: avg %.2f ms (%.1f fps), max %.2f ms over %d frames | window %dx%d" % [avg, 1000.0 / avg, _prof_max, int(n), get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y])
			get_tree().quit()
			return
		_prof_last = now
		return
	if _shot_path == "":
		return
	_shot_frames += 1
	if _shot_frames < _shot_min_frames:
		return
	var img := get_viewport().get_texture().get_image()
	img.save_png(_shot_path)
	print("SHOT saved: %s (%dx%d)" % [_shot_path, img.get_width(), img.get_height()])
	get_tree().quit()


## Generates the galaxy and asserts the structural invariants from
## build_game.py generateGalaxy(). Returns the failure count (process exit code).
func _run_galaxy_checks() -> int:
	var fails := 0
	var seed := 12345

	Galaxy.generate(seed)
	var stars: Array = Galaxy.stars
	var planets: Array = Galaxy.planets

	print("=== GALAXY INVARIANT CHECK (seed %d) ===" % seed)
	print("stars=%d  planets=%d  black_holes=%d" % [stars.size(), planets.size(), Galaxy.black_holes.size()])

	fails += _expect(not stars.is_empty(), "at least one star generated")

	var home: Dictionary = stars[Galaxy.home_star_id]
	fails += _expect(home.name == "Gigi Prime", "home star named 'Gigi Prime' (got '%s')" % home.name)
	fails += _expect(home.size == "M", "home star size M (got %s)" % home.size)

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

	fails += _expect(Galaxy.black_holes.size() <= 4, "at most 4 black holes")
	for b in Galaxy.black_holes:
		fails += _expect(Vector2(b.x, b.y).length() >= 35000.0, "black hole clear of home region")

	var relics := []
	for p in planets:
		if p.isAlienRelic:
			relics.append(p)
			fails += _expect(p.hasStation, "relic %d has a station" % p.id)
	fails += _expect(relics.size() <= 16, "at most 16 relics (got %d)" % relics.size())
	print("relics placed: %d" % relics.size())

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
			if d < (sysR[i] + sysR[j] + Tuning.SYS_GAP) * 0.99:
				overlaps += 1
	print("residual system overlaps (excl. home-neighbour): %d" % overlaps)
	fails += _expect(overlaps == 0, "no residual system overlaps")

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

	# Transit + delivery.
	GameState.start_new_game()
	Transit.reset()
	var pass_dest := -1
	for pid in home.planetIds:
		if pid == Galaxy.origen_id:
			continue
		if planets[_find_planet_idx(planets, pid)].get("demandRate", {}).has("passengers"):
			pass_dest = pid
			break
	if pass_dest >= 0:
		# Stations required for car-by-car cargo ops (build_game.py gating).
		Galaxy.planets[_find_planet_idx(planets, Galaxy.origen_id)].hasStation = true
		Galaxy.planets[_find_planet_idx(planets, pass_dest)].hasStation = true
		var t := Transit.build_train(Galaxy.origen_id, "engine_constellation", ["car_passenger"], true)
		Transit.assign_route(t, [Galaxy.origen_id, pass_dest])
		var credits_before := GameState.credits
		var dc := {"n": 0}
		var conn := func(_tid, _pid, _cargo, _rev): dc.n += 1
		Transit.train_delivered.connect(conn)
		for _i in 4000:
			Economy.accumulate(150.0 * Tuning.SD_PER_DTG)  # refill supply/demand pools
			Transit.tick(150.0)
			if dc.n >= 2:
				break
		Transit.train_delivered.disconnect(conn)
		print("transit: credits %d -> %d (%d deliveries)" % [credits_before, GameState.credits, dc.n])
		fails += _expect(GameState.credits > credits_before, "train delivery increases credits")
		fails += _expect(dc.n >= 1, "train completed at least one delivery")

	# Missions: graph + lifecycle + chain + rewards + unlocks.
	GameState.start_new_game()
	Missions.start_new_game()
	fails += _expect(not Missions.def_for("build_foundry").is_empty(), "mission defs loaded")
	var mc0 := GameState.credits
	Missions.queue_intro("build_foundry")
	fails += _expect(Missions.is_active("build_foundry"), "build_foundry introduced")
	Missions.complete("build_foundry")
	fails += _expect(Missions.is_completed("build_foundry"), "build_foundry completed")
	fails += _expect(GameState.credits == mc0 + 10000, "build_foundry reward +10000")
	fails += _expect(Missions.is_active("produce_iron"), "produce_iron chained")
	Missions.complete("produce_iron")
	fails += _expect(GameState.unlocked_upgrades.has("large_station"), "produce_iron unlocks large_station")
	Missions.queue_intro("design_better_train")
	Missions.complete("design_better_train")
	fails += _expect(GameState.unlocked_engines.has("engine_classJ") and GameState.unlocked_engines.has("engine_classR"), "design_better_train unlocks Class J + R")

	# AI rival corporation.
	GameState.start_new_game()
	Transit.reset()
	AICorp.init_corp("normal")
	fails += _expect(AICorp.home_star_id >= 0, "AI picked a home system")
	var ai_nw0 := AICorp.net_worth()
	for _i in 5000:
		Economy.accumulate(5000.0 * Tuning.SD_PER_DTG)
		Transit.tick(5000.0)
		AICorp.tick(5000.0)
	var ai_trains := 0
	for t in Transit.trains:
		if not t.isPlayer:
			ai_trains += 1
	print("AI: net_worth %d -> %d  trains=%d  revenue=%d" % [ai_nw0, AICorp.net_worth(), ai_trains, AICorp.total_revenue])
	fails += _expect(ai_trains > 0, "AI built trains")
	fails += _expect(AICorp.net_worth() > ai_nw0, "AI net worth grew")
	Transit.reset()

	# Save/Load round-trip.
	Galaxy.generate(seed)
	GameState.start_new_game()
	Missions.start_new_game()
	Transit.reset()
	Missions.queue_intro("build_foundry")
	Missions.complete("build_foundry")
	GameState.credits = 777777
	GameState.stardate = 850.5
	Discovery.visited_planet_ids[Galaxy.origen_id] = true
	Galaxy.advance_orbits(500.0)
	var saved_angle: float = Galaxy.planets[Galaxy.origen_id].orbitAngle
	Transit.build_train(Galaxy.origen_id, "engine_galaxy", ["car_passenger"], true)
	var saved_seed := Galaxy._seed
	var spath := "user://test_save.json"
	fails += _expect(SaveLoad.save_game(spath), "save_game wrote file")
	GameState.credits = 0
	Transit.reset()
	Missions.start_new_game()
	Galaxy.generate(99999)
	fails += _expect(SaveLoad.load_game(spath), "load_game read file")
	fails += _expect(GameState.credits == 777777, "credits restored")
	fails += _expect(Galaxy._seed == saved_seed, "galaxy seed restored")
	fails += _expect(Missions.is_completed("build_foundry"), "completed mission restored")
	fails += _expect(Transit.trains.size() == 1, "trains restored")
	fails += _expect(absf(Galaxy.planets[Galaxy.origen_id].orbitAngle - saved_angle) < 0.001, "planet orbit angle restored")
	Transit.reset()

	# Determinism: same seed → identical layout signature (fresh generate for both).
	Galaxy.generate(seed)
	var sig1 := _layout_signature()
	Galaxy.generate(seed)
	var sig2 := _layout_signature()
	fails += _expect(sig1 == sig2, "generation is deterministic for a fixed seed")

	# Orbital motion.
	Galaxy.generate(seed)
	var oi := _find_planet_idx(Galaxy.planets, Galaxy.origen_id)
	var ox: float = Galaxy.planets[oi].x
	Galaxy.advance_orbits(1000.0)
	fails += _expect(absf(Galaxy.planets[oi].x - ox) > 0.001, "advance_orbits moves planets")

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
