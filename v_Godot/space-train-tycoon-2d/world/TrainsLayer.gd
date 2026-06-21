extends Node2D
## TrainsLayer — renders train consists in the galaxy (build_game.py §20 + the
## drawGalaxy train loop @29174). Each car is its real PNG sprite, sized so its
## SOLID body (alpha>30 bbox) is `_vf·28·scale·areaFactor` px tall, body-centred
## on its coupling point and bottom-aligned, rotated along the path, drawn
## back-to-front (tail first). Cars trail the engine at cumulative world offsets
## (`_carOffset`). Drawn in SCREEN space via view._w2s like the other layers.
##
## M3: orbit consists follow the arc faithfully; transit consists trail straight
## behind the engine (the §6 live-tangent per-car curve is deferred).

var view: Node2D  # GalaxyView2D controller

const _GAL_SCALE := 1.5
const _CAR_ORB_H := 28.0
const _GAL_REF_ASPECT := 2.07
const _GALAXY_CAR_GAP := 1.5
const _ENGINE_TIER := {
	"engine_constellation": 1.0, "engine_galaxy": 1.05, "engine_classJ": 1.10,
	"engine_classR": 1.06, "engine_N700": 1.16,
}

# Per-sprite metrics, computed lazily by scanning the PNG alpha (downsized).
# name -> {W,H, cx_frac, h_frac, bot_frac, aspect, tex}
var _metrics: Dictionary = {}

# Credit floats: "+N cr" that rises + fades at a player delivery (code_effects).
const _FLOAT_LIFE := 1.5
var _floats: Array = []  # {pos:Vector2(world), rev:int, age:float}
var _font: Font

# Cargo beam particles (build_game.py:7854 _spawnCargoBeam / _BEAM_COLS). While a
# car loads/unloads, particles stream between the planet surface and the car top,
# coloured by cargo, homing onto the live (orbiting) car each frame.
const _BEAM_LIFE := 30.0
var _cargo_particles: Array = []  # {tid,ci,loading,prog,f,life,col}
const _BEAM_COLS := {
	"passengers": "#ffe060", "royal": "#dd88ff", "livestock": "#cc8844", "water": "#44ccff",
	"mail": "#a8d8ff", "ice": "#aaeeff", "sand": "#e8c96a", "molten_ore": "#ff6010",
	"iron": "#ffcc44", "gold": "#ffe030", "diamond": "#80c0ff", "hazmat": "#80ff20",
	"oil": "#1a1a1a", "battery": "#fff230", "flowers": "#ff88cc", "medical": "#40eeaa",
	"grain": "#e8d840", "fruit": "#ff8822", "steel": "#c8d0e0", "glass": "#a8e6d8",
	"machinery": "#a8a890", "cargo": "#e8c898", "chemical": "#60d820",
}


func _ready() -> void:
	_font = ThemeDB.fallback_font
	Transit.train_delivered.connect(_on_delivered)
	# First-visit exploration reward float at the visited planet.
	Discovery.planet_visited.connect(func(pid: int, reward: int):
		if reward > 0:
			var p: Dictionary = Galaxy.planets[pid]
			_floats.append({"pos": Vector2(float(p.x), float(p.y)), "rev": reward, "age": 0.0}))

func _on_delivered(train_id: int, _pid: int, _cargo: String, rev: int) -> void:
	if rev <= 0:
		return
	for t in Transit.trains:
		if int(t.id) == train_id and bool(t.isPlayer):
			_floats.append({"pos": Vector2(float(t.x), float(t.y)), "rev": rev, "age": 0.0})
			return

func _process(delta: float) -> void:
	var i := _floats.size() - 1
	while i >= 0:
		_floats[i].age += delta
		if _floats[i].age >= _FLOAT_LIFE:
			_floats.remove_at(i)
		i -= 1
	_update_cargo_beams(delta)


func _update_cargo_beams(delta: float) -> void:
	var dtg := delta * 60.0 * float(Tuning.SPEED_OPTS[GameState.game_speed_idx])
	# Spawn for each train currently loading/unloading its front-queue car.
	for t in Transit.trains:
		if String(t.cargoPhase) == "" or (t.cargoQueue as Array).is_empty():
			continue
		if _cargo_particles.size() > 600:
			break
		var ends := _beam_ends(t)
		if ends.is_empty():
			continue
		var ci: int = t.cargoQueue[0]
		var loading := String(t.cargoPhase) == "loading"
		var ctype = Tuning.CAR_CARGO_TYPE.get(String(t.cars[ci]), null) if loading else t.carCargo[ci]
		var col := Color.from_string(String(_BEAM_COLS.get(ctype, "#88ccff")), Color(0.5, 0.7, 1.0))
		for _k in maxi(1, int(ceil(delta * 60.0 * 3.0))):
			_cargo_particles.append({"tid": int(t.id), "ci": ci, "loading": loading,
				"prog": 0.0, "f": randf_range(-1.0, 1.0), "life": _BEAM_LIFE, "col": col})
	# Advance + cull.
	var j := _cargo_particles.size() - 1
	while j >= 0:
		_cargo_particles[j].life -= dtg
		_cargo_particles[j].prog += dtg / _BEAM_LIFE
		if _cargo_particles[j].life <= 0.0:
			_cargo_particles.remove_at(j)
		j -= 1


# Live beam endpoints for a train's active cargo car (build_game.py:7828):
# {src, dst, perp} in world coords, or {} if invalid.
func _beam_ends(t: Dictionary) -> Dictionary:
	if (t.cargoQueue as Array).is_empty():
		return {}
	var ci: int = t.cargoQueue[0]
	var p: Dictionary = Galaxy.planets[int(t.planetId)]
	var pc := Vector2(float(p.x), float(p.y))
	var car_pos: Vector2 = Transit.car_path_pos(t, _car_offset(t, ci + 1))[0]  # +1: skip engine
	var radial := (car_pos - pc)
	if radial.length() < 0.001:
		return {}
	radial = radial.normalized()
	var car_radial_h := _vf(String(t.cars[ci])) * _CAR_ORB_H
	var car_end := car_pos - radial * car_radial_h          # car top (toward planet)
	var plan_end := pc + radial * maxf(2.0, float(p.radius)) # surface beneath the car
	var loading := String(t.cargoPhase) == "loading"
	var src := plan_end if loading else car_end
	var dst := car_end if loading else plan_end
	return {"src": src, "dst": dst, "perp": Vector2(-(dst - src).normalized().y, (dst - src).normalized().x)}


func _car_offset(t: Dictionary, j: int) -> float:
	var consist: Array = [String(t.engine)]
	for cy in t.cars:
		consist.append(String(cy))
	var off := 0.0
	for i in range(1, mini(j + 1, consist.size())):
		off += _half_w_world(consist[i - 1]) + _half_w_world(consist[i]) + _GALAXY_CAR_GAP
	return off


func _draw() -> void:
	for t in Transit.trains:
		_draw_train_orbits(t)
	for t in Transit.trains:
		_draw_consist(t)
	_draw_cargo_particles()
	_draw_floats()


func _draw_cargo_particles() -> void:
	if _cargo_particles.is_empty():
		return
	# Cache live beam ends per train so we re-home particles onto the moving car.
	var ends_cache: Dictionary = {}
	for pt in _cargo_particles:
		var tid: int = pt.tid
		if not ends_cache.has(tid):
			var tr := _train_by_id(tid)
			ends_cache[tid] = _beam_ends(tr) if not tr.is_empty() else {}
		var ends: Dictionary = ends_cache[tid]
		if ends.is_empty():
			continue
		var prog: float = clampf(pt.prog, 0.0, 1.0)
		var src: Vector2 = ends.src
		var dst: Vector2 = ends.dst
		var perp: Vector2 = ends.perp
		var beam_len: float = src.distance_to(dst)
		var lat: float = pt.f * (beam_len * 0.22) * (1.0 - prog)  # funnel converges at the car
		var wp := src + (dst - src) * prog + perp * lat
		var sp: Vector2 = view._w2s(wp)
		if sp.x < -4.0 or sp.x > Tuning.W + 4.0 or sp.y < -4.0 or sp.y > Tuning.GH + 4.0:
			continue
		var t01: float = 1.0 - pt.life / _BEAM_LIFE
		var fa: float = (t01 / 0.15) if t01 < 0.15 else ((1.0 - t01) / 0.28 if t01 > 0.72 else 1.0)
		var col: Color = pt.col
		col.a = clampf(fa, 0.0, 1.0) * 0.85
		draw_circle(sp, 1.8, col)

func _train_by_id(tid: int) -> Dictionary:
	for t in Transit.trains:
		if int(t.id) == tid:
			return t
	return {}

func _draw_floats() -> void:
	for f in _floats:
		var frac: float = float(f.age) / _FLOAT_LIFE
		var sp: Vector2 = view._w2s(f.pos)
		sp.y -= 45.0 * frac  # rise
		var a := 1.0 if frac < 0.55 else (1.0 - (frac - 0.55) / 0.45)
		var txt := "+%s cr" % _commas(int(f.rev))
		draw_string(_font, Vector2(sp.x - 60.0, sp.y), txt, HORIZONTAL_ALIGNMENT_CENTER, 120.0, 13, Color(0.4, 1.0, 0.5, a))

func _commas(n: int) -> String:
	var s := str(n)
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return out


# Train orbit dashes + current-segment route line (build_game.py:29180-29211).
func _draw_train_orbits(t: Dictionary) -> void:
	var sc: float = view.sc
	var is_player := bool(t.isPlayer)
	var col := Color(0.31, 0.63, 1.0, 0.15) if is_player else Color(1.0, 0.63, 0.24, 0.15)
	# Departure-planet orbit ring.
	var p: Dictionary = Galaxy.planets[int(t.planetId)]
	var dp: Vector2 = view._w2s(Vector2(p.x, p.y))
	_dashed_circle(dp, float(t.orbitR) * sc, col)
	# Arrival-planet orbit ring + the actual tangent segment while transiting.
	if int(t.phase) == Transit.Phase.TRANSIT and int(t.targetId) >= 0:
		var tp: Dictionary = Galaxy.planets[int(t.targetId)]
		var tdp: Vector2 = view._w2s(Vector2(tp.x, tp.y))
		_dashed_circle(tdp, float(t.arrivalOrbitR) * sc, Color(col.r, col.g, col.b, 0.10))
		# Route line = the external tangent the train actually travels (ax→bx).
		var lt: Dictionary = Transit.segment_tangent(t)
		if not lt.is_empty():
			var a: Vector2 = view._w2s(Vector2(lt.ax, lt.ay))
			var b: Vector2 = view._w2s(Vector2(lt.bx, lt.by))
			draw_line(a, b, Color(col.r, col.g, col.b, 0.22), 1.0)

func _orbit_r(p: Dictionary) -> float:
	return maxf(float(p.radius) * 3.0, 200.0)

func _dashed_circle(center: Vector2, radius: float, col: Color) -> void:
	if radius < 3.0 or radius > Tuning.W * 2.0:
		return
	var seg := 0.13  # radians per dash+gap cell
	var t := 0.0
	while t < TAU:
		draw_arc(center, radius, t, t + seg * 0.45, 4, col, 1.0)
		t += seg


func _draw_consist(t: Dictionary) -> void:
	var consist: Array = [String(t.engine)]
	for cy in t.cars:
		consist.append(String(cy))
	var full: Array = [true]  # engine always "full" (its own sprite)
	var car_cargo: Array = t.get("carCargo", [])
	for j in t.cars.size():
		full.append(j < car_cargo.size() and car_cargo[j] != null)
	# Cumulative world offsets along the path (each coupling = halfW+halfW+gap).
	var offs: Array = [0.0]
	for i in range(1, consist.size()):
		offs.append(float(offs[i - 1]) + _half_w_world(consist[i - 1]) + _half_w_world(consist[i]) + _GALAXY_CAR_GAP)
	# Hand the sim the consist's world length (last car's centre offset) so it can
	# wait for the WHOLE train to slide onto the arrival orbit before docking — no
	# tail-car snap on arrival (Transit._tick_train TRANSIT branch).
	t.consist_len = float(offs[consist.size() - 1])
	var sc: float = view.sc
	var ch := maxf(2.0, _CAR_ORB_H * sc)
	# Draw back-to-front: tail first so the engine ends up on top.
	for i in range(consist.size() - 1, -1, -1):
		var pr := _car_path_pos(t, float(offs[i]))
		_draw_car(String(consist[i]), bool(full[i]), pr[0], pr[1], ch, sc)


# Per-car world position + rotation — the faithful path geometry (departure
# orbit → tangent → arrival orbit) lives in Transit (which owns the motion).
func _car_path_pos(t: Dictionary, off: float) -> Array:
	return Transit.car_path_pos(t, off)


# Public: draw a consist as a SCREEN-SPACE strip fitted into `rect` (for the
# HUD panel rows / info bar / train builder — §20.4). `cars` includes the engine
# at [0]; `full` is per-car loaded state. Draws onto the passed CanvasItem.
func draw_car_strip(canvas: CanvasItem, rect: Rect2, cars: Array, full: Array) -> void:
	if cars.is_empty():
		return
	var ch := rect.size.y / 1.7
	var draws: Array = []
	var total := 0.0
	for i in cars.size():
		var type := String(cars[i])
		var sprite := type if (i < full.size() and bool(full[i])) else _empty_sprite(type)
		var m := _get_metric(sprite)
		if m.tex == null:
			continue
		var vis_h := _vf(type) * ch * _area_factor(type, m)
		var sd := vis_h / maxf(0.001, float(m.h_frac) * float(m.H))
		var dw := float(m.W) * sd
		var dh := float(m.H) * sd
		draws.append({"tex": m.tex, "dw": dw, "dh": dh, "bot": float(m.bot_frac), "adv": dw * 0.72 + 2.0})
		total += dw * 0.72 + 2.0
	if total <= 0.0:
		return
	var s := minf(1.0, rect.size.x / total)
	var baseline := rect.position.y + rect.size.y * 0.86
	var x := rect.position.x + 2.0
	for d in draws:
		var dw: float = d.dw * s
		var dh: float = d.dh * s
		canvas.draw_texture_rect(d.tex, Rect2(x, baseline - d.bot * dh, dw, dh), false)
		x += d.adv * s


# Public: draw a cargo's car-icon strip for supply/demand displays
# (build_game.py:25428 _drawCargoStrip). Draws floor(amount) car sprites (cap-
# limited) at cell_w spacing, bottom-aligned in the row, then a left-clipped
# partial sprite for the fractional car. Returns the x for the "×N" label.
func draw_cargo_strip(canvas: CanvasItem, x: float, y: float, cell_w: float, cell_h: float, cargo: String, amount: float, cap: int) -> float:
	var car := String(Tuning.CARGO_CAR_SPRITE.get(cargo, ""))
	if car == "":
		return x
	var m := _get_metric(car)
	if m.tex == null:
		return x
	var tenth := floorf(amount * 10.0) / 10.0
	var overflow := tenth > float(cap) + 0.000001
	var shown: float = float(cap) if overflow else tenth
	var full_n := int(floorf(shown + 0.000001))
	var frac := maxf(0.0, roundf((shown - float(full_n)) * 10.0) / 10.0)
	# Contain-fit the sprite into the cell, bottom-aligned.
	var s := minf((cell_w * 0.94) / float(m.W), (cell_h * 0.88) / float(m.H))
	var dw := float(m.W) * s
	var dh := float(m.H) * s
	var baseline := y + cell_h
	var sx := x
	for _i in full_n:
		canvas.draw_texture_rect(m.tex, Rect2(sx + (cell_w - dw) * 0.5, baseline - dh, dw, dh), false)
		sx += cell_w
	if frac > 0.001:
		var src := Rect2(0.0, 0.0, float(m.W) * frac, float(m.H))
		canvas.draw_texture_rect_region(m.tex, Rect2(sx + (cell_w - dw) * 0.5, baseline - dh, dw * frac, dh), src)
		sx += cell_w * frac
	return sx + 3.0


func _draw_car(type: String, is_full: bool, world_pos: Vector2, rot: float, ch: float, sc: float) -> void:
	var sprite := type if is_full else _empty_sprite(type)
	var m := _get_metric(sprite)
	var tex: Texture2D = m.tex
	if tex == null:
		return
	var vf := _vf(type)
	var af := _area_factor(type, m)
	var vis_h := vf * ch * af                       # visible body height (screen px)
	var scale_draw := vis_h / maxf(1.0, float(m.h_frac) * float(m.H))
	var dw := float(m.W) * scale_draw
	var dh := float(m.H) * scale_draw
	var draw_x := -float(m.cx_frac) * dw            # body centre → coupling x=0
	var draw_y := -float(m.bot_frac) * dh           # body bottom → y=0
	var sp: Vector2 = view._w2s(world_pos)
	if sp.x < -dw or sp.x > Tuning.W + dw or sp.y < -dh or sp.y > Tuning.GH + dh:
		return
	draw_set_transform(sp, rot, Vector2(-1.0, 1.0))  # flip x (sprites face +x)
	draw_texture_rect(tex, Rect2(draw_x, draw_y, dw, dh), false)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _vf(type: String) -> float:
	if type == "caboose":
		return 0.66 * _GAL_SCALE
	if type.begins_with("engine_"):
		return 0.66 * float(_ENGINE_TIER.get(type, 1.0)) * _GAL_SCALE
	return 0.60 * _GAL_SCALE

func _area_factor(type: String, m: Dictionary) -> float:
	if type == "caboose" or type.begins_with("engine_"):
		return 1.0
	return sqrt(_GAL_REF_ASPECT / maxf(0.5, float(m.aspect)))

func _half_w_world(type: String) -> float:
	var m := _get_metric(type if not _has_empty_default(type) else type)
	return _vf(type) * _CAR_ORB_H * _area_factor(type, m) * float(m.aspect) / 2.0

func _has_empty_default(_type: String) -> bool:
	return false  # spacing uses the loaded sprite's aspect (full)

func _empty_sprite(type: String) -> String:
	if type == "caboose" or type.begins_with("engine_"):
		return type
	var e := type + "_empty"
	if ResourceLoader.exists("res://assets/sprites/%s.png" % e):
		return e
	return type


# Compute a sprite's solid-body metrics by scanning a downsized copy's alpha>30.
func _get_metric(name: String) -> Dictionary:
	if _metrics.has(name):
		return _metrics[name]
	var m: Dictionary
	var tex: Texture2D = load("res://assets/sprites/%s.png" % name) as Texture2D
	if tex == null:
		m = {"W": 160.0, "H": 160.0, "cx_frac": 0.5, "h_frac": 0.5, "bot_frac": 0.95, "aspect": 2.0, "tex": null}
	else:
		var img := tex.get_image()
		var w0 := img.get_width()
		var h0 := img.get_height()
		var sf := 160.0 / float(maxi(w0, h0))
		var sw := maxi(1, int(w0 * sf))
		var sh := maxi(1, int(h0 * sf))
		img.resize(sw, sh)
		var minx := sw
		var miny := sh
		var maxx := 0
		var maxy := 0
		var found := false
		for y in sh:
			for x in sw:
				if img.get_pixel(x, y).a > 0.118:  # alpha > ~30/255
					found = true
					minx = mini(minx, x); maxx = maxi(maxx, x)
					miny = mini(miny, y); maxy = maxi(maxy, y)
		if not found:
			minx = 0; miny = 0; maxx = sw - 1; maxy = sh - 1
		var bw := float(maxx - minx + 1)
		var bh := float(maxy - miny + 1)
		m = {
			"W": float(w0), "H": float(h0), "tex": tex,
			"cx_frac": (float(minx) + bw * 0.5) / float(sw),
			"h_frac": bh / float(sh),
			"bot_frac": float(maxy + 1) / float(sh),
			"aspect": bw / bh,
		}
	_metrics[name] = m
	return m
