extends Node2D
## GalaxyContent — the world bodies, drawn in SCREEN space via view._w2s (mirrors
## the JS drawGalaxy body passes line-for-line). Z-order within this one _draw:
## stars → black holes → max-zoom-out dim orbits → selected-system orbits →
## planets → selection ring. Star/BH name labels live in the Labels layer.
##
## M1: stars (corona + 3-stop disc), black holes (annuli + lensing), orbit rings,
## planets (pre-glow halo + lit disc, flat biome colour).
## M2: planets are pre-baked shaded-sphere textures (one per biome, lit from +x)
## ROTATED per planet to point the terminator at the star — faithful to
## drawPlanet's radially-symmetric offset-gradient shading. Surface detail +
## clouds are M2 follow-ups (need cosmetic data the sim autoloads skipped).

const SkylineBaker := preload("res://world/SkylineBaker.gd")

var view: Node2D  # GalaxyView2D controller

# Bake-once cityscape / ancient-ruins textures (blitted scaled per planet).
var _cityscape_tex: Texture2D
var _ruins_tex: Texture2D

# One pre-baked 256px lit-sphere texture per biome id (lit from +x, NO night).
var _biome_tex: Dictionary = {}
var _night_tex: Texture2D  # shared night-side shadow overlay
const _SPHERE_TEX_N := 256
# View-side biome surface detail (resort islands / agri fields / oil bands).
var _surface: Dictionary = {}
var _neb_font: Font  # Exo 2 for nebula name labels (lazy-loaded)

# View-side cosmetic cloud data, generated lazily & seeded per planet id
# (decoupled from the sim, which skipped cosmetic RNG). {planet_id: Array}.
var _clouds: Dictionary = {}
var clouds_off := false  # dev: --no-clouds profiling toggle
# drawPlanetClouds tint per biome (build_game.py:13372).
const _CCOL := {
	"ocean": Color8(195, 222, 255), "agri": Color8(228, 244, 210),
	"chemical": Color8(180, 230, 80), "storm": Color8(210, 190, 255),
	"resort": Color8(242, 249, 255),
}


func biome_tex(id: String) -> Texture2D:
	return _biome_tex.get(id, null)

func _ready() -> void:
	for pt in Tuning.PTYPES:
		_biome_tex[String(pt.id)] = _bake_biome(pt)
	_night_tex = _bake_night()
	_bake_skylines()  # async (awaits frames); urban planets blit once ready

# Render the cityscape skyline once into a SubViewport, then keep the resulting
# texture (faithful to the JS bake-once cache).
func _bake_skylines() -> void:
	_cityscape_tex = await _bake_skyline("city")
	_ruins_tex = await _bake_skyline("ruins")

func _bake_skyline(mode: String) -> ImageTexture:
	var vp := SubViewport.new()
	vp.size = Vector2i(780, 780)  # halfW*2 = (280+110)*2
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var baker := SkylineBaker.new()
	baker.mode = mode
	vp.add_child(baker)
	add_child(vp)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	return ImageTexture.create_from_image(img)


func _draw() -> void:
	var gt: Texture2D = view.glow_tex
	var sc: float = view.sc
	var ts := float(Time.get_ticks_msec())

	# ── Named nebulas (world-space, behind everything) ──
	_draw_nebulas(gt, sc)

	# ── Stars (before planets so planets appear in front) ──
	for s in Galaxy.stars:
		var sp: Vector2 = view._w2s(Vector2(s.x, s.y))
		var sr := float(s.radius) * sc
		var sglow_r: float = max(sr * 2.8, 8.0)
		if sp.x + sglow_r < 0.0 or sp.x - sglow_r > Tuning.W or sp.y + sglow_r < 0.0 or sp.y - sglow_r > Tuning.GH:
			continue
		_draw_star(gt, sp, sr, s)
		if s.get("hasDysonSphere", false):
			_draw_dyson(sp, sr, sc)
		# High orbit ring (HazMat zone) — faint green DASHED ring (build_game.py
		# setLineDash([4,9])).
		var hor := sr * 1.6
		if hor > 6.0:
			_dashed_ring(sp, hor, Color(0.47, 0.86, 0.31, 0.12), 1.0)

	# ── Black holes ──
	for b in Galaxy.black_holes:
		var bp: Vector2 = view._w2s(Vector2(b.x, b.y))
		var bsr := float(b.radius) * sc
		var bg_glow := bsr * 4.2
		if bp.x + bg_glow < 0.0 or bp.x - bg_glow > Tuning.W or bp.y + bg_glow < 0.0 or bp.y - bg_glow > Tuning.GH:
			continue
		_draw_black_hole(gt, bp, bsr, ts)

	# ── Max zoom-out: dim orbit paths for all planets (build_game.py:28652) ──
	var zt := _zoom_t()
	if zt < 0.10:
		var or_a := (0.10 - zt) / 0.10
		for p in Galaxy.planets:
			var st: Dictionary = Galaxy.stars[int(p.starId)]
			var stp: Vector2 = view._w2s(Vector2(st.x, st.y))
			var orr := float(p.orbitRadius) * sc
			if orr < 6.0:
				continue  # sub-pixel orbit ring — invisible, skip
			if stp.x + orr < -20.0 or stp.x - orr > Tuning.W + 20.0 or stp.y + orr < -20.0 or stp.y - orr > Tuning.GH + 20.0:
				continue
			draw_arc(stp, orr, 0.0, TAU, clampi(int(orr * 0.4), 16, 96), Color(0.31, 0.41, 0.69, 0.22 * or_a), 0.7)

	# ── Selected-system orbit rings (build_game.py:28689) ──
	_draw_selected_orbits(sc)

	# ── Planets ──
	for p in Galaxy.planets:
		var pp: Vector2 = view._w2s(Vector2(p.x, p.y))
		var pr := float(p.radius) * sc
		var pglow_r: float = max(pr * 4.5, 9.0)
		if pp.x + pglow_r < -20.0 or pp.x - pglow_r > Tuning.W + 20.0 or pp.y + pglow_r < -20.0 or pp.y - pglow_r > Tuning.GH + 20.0:
			continue
		var psl: Dictionary = Galaxy.stars[int(p.starId)]
		var star_sp: Vector2 = view._w2s(Vector2(psl.x, psl.y))
		_draw_planet(gt, pp, pr, p, star_sp)

	# ── Selection ring (build_game.py:29643): blue planet / gold star / orange
	# train, at radius+5 with a soft glow. ──
	var wp: Vector2 = view.selected_world_pos()
	if wp != Vector2.INF:
		var sp2: Vector2 = view._w2s(wp)
		var rr := _selected_screen_radius(sc)
		var kind := String(GameState.selected.get("kind", ""))
		var rc := Color(0.267, 0.667, 1.0, 0.95)             # planet → #4af
		if kind == "star":
			rc = Color(1.0, 0.843, 0.0, 0.95)               # star → #ffd700
		elif kind == "train":
			rc = Color(1.0, 0.667, 0.533, 0.95)             # train → #fa8
		else:
			# Grey orbit ring for the selected planet (where its trains orbit —
			# the port has one orbit tier, not the JS LOW/MED/HIGH set).
			var pid := int(String(GameState.selected.get("id", "")).trim_prefix("planet_"))
			if pid >= 0 and pid < Galaxy.planets.size():
				var orb := Transit._orbit_radius_for(Galaxy.planets[pid]) * sc
				if orb > 6.0:
					draw_arc(sp2, orb, 0.0, TAU, 64, Color(0.627, 0.627, 0.647, 0.30), 0.8)
		var ring_r := maxf(9.0, rr) + 5.0
		draw_arc(sp2, ring_r, 0.0, TAU, 56, Color(rc.r, rc.g, rc.b, 0.22), 7.0)  # glow
		draw_arc(sp2, ring_r, 0.0, TAU, 56, rc, 2.0)


# drawStar (build_game.py:12374): corona glow + 3-stop disc (hi→core→edge).
func _draw_star(gt: Texture2D, c: Vector2, r: float, s: Dictionary) -> void:
	var pal: Dictionary = Tuning.STAR_COLORS.get(String(s.get("colorName", "yellow")), Tuning.STAR_COLORS["yellow"])
	var hi := _hex(String(pal["hi"]))
	var core := _hex(String(pal["core"]))
	var edge := _hex(String(pal["edge"]))
	var glow := _hex(String(pal.get("glow", pal["core"])))
	var glow_r: float = max(r * 2.8, 8.0)
	# Corona — 4-stop falloff (build_game.py 12376-12380: core→glow→glow→clear).
	# Approximated by a wide GLOW-coloured halo + a tighter CORE-coloured inner
	# corona, so the mid-corona reads as the palette's distinct glow hue (e.g. a
	# yellow star's amber halo) rather than a mono-core blur.
	_glow(gt, c, glow_r, Color(glow.r, glow.g, glow.b, 0.32))
	_glow(gt, c, glow_r * 0.55, Color(core.r, core.g, core.b, 0.7))
	# Stellar disc: edge base → core body → hi highlight.
	var pr: float = max(r, 1.5)
	draw_circle(c, pr, edge)
	_glow(gt, c, pr, core)
	_glow(gt, c - Vector2(pr * 0.25, pr * 0.25), pr * 0.7, hi)


# drawPlanet (build_game.py:12063): pre-glow halo + lit biome disc.
# Dashed ring (mirrors Canvas setLineDash): short arc dashes (~4px) with ~9px gaps.
func _dashed_ring(c: Vector2, radius: float, col: Color, width: float) -> void:
	var nd := clampi(int(TAU * radius / 13.0), 6, 80)
	var dash_ang: float = minf((4.0 / maxf(radius, 1.0)), TAU / nd * 0.6)
	for i in nd:
		var a0 := (float(i) / nd) * TAU
		draw_arc(c, radius, a0, a0 + dash_ang, 3, col, width)

func _draw_planet(gt: Texture2D, c: Vector2, r: float, p: Dictionary, star_sp: Vector2) -> void:
	var ty: Dictionary = p.get("type", {})
	var rim := _rim(ty.get("rim", [136, 136, 136]))
	var base := _hex(String(ty.get("base", "#888888")))
	var hi := _hex(String(ty.get("hi", "#aaaaaa")))
	if r < 1.2:
		# Tiny (the vast majority of planets when zoomed out): draw a cheap bright
		# dot instead of a large alpha glow quad. With hundreds on screen the glow
		# blits are the dominant overdraw cost; a 1.7px circle reads the same.
		draw_circle(c, 1.7, Color(hi.r, hi.g, hi.b, 0.92))
		return
	var glow_r: float = max(r * 4.5, 9.0)
	# Pre-glow rim halo (visible-size planets only).
	_glow(gt, c, glow_r, Color(rim.r, rim.g, rim.b, 0.48))
	# Bright-side direction (screen space) = TOWARD the star — matches the
	# ORIGINAL game's appearance (lit limb faces the star; feedback_planet_light_
	# direction). Sign note: the JS negates (build_game.py:12089) because its
	# Canvas eccentric two-circle radial gradient flips which side looks bright;
	# this port bakes a CONCENTRIC gradient (bright AT the focal point), so the
	# NON-negated vector is what yields the same lit-toward-star result.
	var d := star_sp - c
	var ln: float = d.length()
	var lv := Vector2(0.30, -0.35) if ln < 0.001 else (d / ln)
	if r < 3.0:
		# Too small for shaded detail to read — cheap flat disc + highlight.
		draw_circle(c, r, base)
		_glow(gt, c + lv * r * 0.42, r * 1.05, hi)
		return
	# Sphere: draw the biome's pre-baked (+x-lit) shaded disc, rotated so its
	# terminator points along lv (the shading is radially symmetric about the
	# light axis, so rotation reproduces drawPlanet's gradient for any lv).
	var tex: Texture2D = _biome_tex.get(String((p.get("type", {}) as Dictionary).get("id", "rocky")), null)
	if tex == null:
		draw_circle(c, r, base)
		return
	# Cosmetic ring + moons: back half / behind moons render BEHIND the sphere.
	var cos_data := _get_cosmetic(p)
	var ring = cos_data.ring
	var moons: Array = cos_data.moons
	if ring != null:
		_draw_ring(c, r, ring, false)
	if not moons.is_empty():
		_draw_moons(gt, c, view.sc, moons, false)
	# Sphere base (lit, no night; rotated so the terminator points along lv).
	var ang := atan2(lv.y, lv.x)
	draw_set_transform(c, ang, Vector2.ONE)
	draw_texture_rect(tex, Rect2(-r, -r, r * 2.0, r * 2.0), false)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Biome surface detail + gold/diamond — on the LIT base, before the night
	# overlay so the dark side darkens them too (build_game.py drawPlanet order).
	_draw_surface(c, r, p)
	_draw_gold_diamond(c, r, p)
	# Night-side shadow (rotated like the base) — darkens base + surface detail.
	if _night_tex != null:
		draw_set_transform(c, ang, Vector2.ONE)
		draw_texture_rect(_night_tex, Rect2(-r, -r, r * 2.0, r * 2.0), false)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Urban cityscape / ancient ruins (baked skyline, blitted scaled) — before
	# clouds (build_game.py:28782-28783).
	if r > 2.0:
		var pid := String((p.get("type", {}) as Dictionary).get("id", ""))
		var sky: Texture2D = null
		if pid == "urban":
			sky = _cityscape_tex
		elif pid == "ancient":
			sky = _ruins_tex
		if sky != null:
			var chalf := 390.0 * (r / 280.0)
			draw_texture_rect(sky, Rect2(c - Vector2(chalf, chalf), Vector2(chalf * 2.0, chalf * 2.0)), false)
	# Player-built upgrade buildings on the surface (foundry / granary / farm /
	# orchard), build_game.py:28828-28849.
	if r > 12.0:
		_draw_upgrade_buildings(c, r, p)
	# Clouds drift screen-aligned on top of the (rotated) sphere.
	_draw_clouds(gt, c, r, p)
	# Station (track ring + towers) when one is built / on alien relics.
	if bool(p.get("hasStation", false)):
		_draw_station(c, r, p)
	# Ring front half + front-hemisphere moons render IN FRONT of the sphere.
	if ring != null:
		_draw_ring(c, r, ring, true)
	if not moons.is_empty():
		_draw_moons(gt, c, view.sc, moons, true)


# drawBlackHole (build_game.py:28514): lensing glow + two-half accretion disk
# with the JS radial gradient (yellow → orange → dark red → transparent), tilted
# (rotate 0.22, scale-y 0.30). Back half behind the event horizon, front in front.
func _draw_black_hole(gt: Texture2D, c: Vector2, sr: float, ts: float) -> void:
	if sr < 0.5:
		return
	var disk_inner := sr * 1.08
	var disk_outer := sr * 1.58
	var pulse := 0.82 + 0.18 * sin(ts * 0.00072)
	# Gravitational lensing outer glow — 4-stop purple falloff (build_game.py
	# 28518: bright purple core → dim violet → near-clear). Two layered glows
	# approximate the radial gradient (was a single flat-alpha blob).
	_glow(gt, c, sr * 4.0, Color(0.314, 0.157, 0.471, 0.16))
	_glow(gt, c, sr * 2.0, Color(0.431, 0.216, 0.902, 0.26))
	# Back half of accretion disk (PI..TAU).
	_draw_disk_half(c, disk_inner, disk_outer, PI, TAU, pulse)
	# Event horizon — absolute black.
	draw_circle(c, sr, Color.BLACK)
	# Front half of accretion disk (0..PI).
	_draw_disk_half(c, disk_inner, disk_outer, 0.0, PI, pulse)
	# Photon ring.
	draw_arc(c, sr * 1.004, 0.0, TAU, 48, Color(0.78, 0.31, 0.04, 0.30 + 0.20 * pulse), maxf(0.5, sr * 0.012))

# One tilted half-annulus of the accretion disk as 3 radial gradient bands
# (build_game.py:28520 stops: 0→(255,200,55,.72) 0.30→(255,95,18,.52)
# 0.65→(160,28,5,.28) 1→(55,5,0,0)), pulse-scaled.
func _draw_disk_half(c: Vector2, r_in: float, r_out: float, a0: float, a1: float, pulse: float) -> void:
	var span := r_out - r_in
	var c0 := Color(1.0, 0.784, 0.215, 0.72 * pulse)
	var c1 := Color(1.0, 0.373, 0.071, 0.52 * pulse)
	var c2 := Color(0.627, 0.110, 0.020, 0.28 * pulse)
	var c3 := Color(0.215, 0.020, 0.0, 0.0)
	_disk_band(c, r_in, r_in + span * 0.30, a0, a1, c0, c1)
	_disk_band(c, r_in + span * 0.30, r_in + span * 0.65, a0, a1, c1, c2)
	_disk_band(c, r_in + span * 0.65, r_out, a0, a1, c2, c3)

func _disk_band(c: Vector2, r_in: float, r_out: float, a0: float, a1: float, col_in: Color, col_out: Color) -> void:
	# tilt: rotate 0.22, scale-y 0.30 baked into vertex positions.
	var cr := cos(0.22)
	var sr := sin(0.22)
	var segs := 28
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	for i in segs + 1:  # outer arc forward
		var t := lerpf(a0, a1, float(i) / float(segs))
		var x := r_out * cos(t)
		var y := r_out * 0.30 * sin(t)
		pts.append(c + Vector2(x * cr - y * sr, x * sr + y * cr))
		cols.append(col_out)
	for i in segs + 1:  # inner arc back
		var t := lerpf(a1, a0, float(i) / float(segs))
		var x := r_in * cos(t)
		var y := r_in * 0.30 * sin(t)
		pts.append(c + Vector2(x * cr - y * sr, x * sr + y * cr))
		cols.append(col_in)
	draw_polygon(pts, cols)


func _draw_selected_orbits(sc: float) -> void:
	var sel: Dictionary = GameState.selected
	var kind := String(sel.get("kind", ""))
	if kind != "planet" and kind != "star":
		return
	var id_str := String(sel.get("id", ""))
	var star_id := -1
	var sel_pid := -1
	if kind == "planet":
		sel_pid = int(id_str.trim_prefix("planet_"))
		for p in Galaxy.planets:
			if int(p.id) == sel_pid:
				star_id = int(p.starId)
				break
	else:
		star_id = int(id_str.trim_prefix("star_"))
	if star_id < 0:
		return
	var st: Dictionary = Galaxy.stars[star_id]
	var stp: Vector2 = view._w2s(Vector2(st.x, st.y))
	for p in Galaxy.planets:
		if int(p.starId) != star_id:
			continue
		var orr := float(p.orbitRadius) * sc
		if orr < 1.0:
			continue
		var segs := clampi(int(orr * 0.4), 24, 96)
		if int(p.id) == sel_pid:
			draw_arc(stp, orr, 0.0, TAU, segs, Color(1.0, 0.86, 0.24, 0.4), 1.5)
		else:
			draw_arc(stp, orr, 0.0, TAU, segs, Color(0.63, 0.63, 0.63, 0.25), 1.5)


func _selected_screen_radius(sc: float) -> float:
	var wp: Vector2 = view.selected_world_pos()
	var sel: Dictionary = GameState.selected
	var id_str := String(sel.get("id", ""))
	match String(sel.get("kind", "")):
		"planet":
			var pid := int(id_str.trim_prefix("planet_"))
			for p in Galaxy.planets:
				if int(p.id) == pid: return float(p.radius) * sc
		"star":
			var sid := int(id_str.trim_prefix("star_"))
			for s in Galaxy.stars:
				if int(s.id) == sid: return float(s.radius) * sc
		"blackhole":
			for b in Galaxy.black_holes:
				return float(b.radius) * sc
	return 12.0


func _zoom_t() -> float:
	return clampf((log(view.sc) - log(Tuning.MIN_SC)) / (log(Tuning.MAX_SC) - log(Tuning.MIN_SC)), 0.0, 1.0)

# Bake a biome's shaded sphere (light from +x) — the exact drawPlanet gradient
# model (build_game.py:12100): offset radial gradient hi→base→shade(base,-55),
# night-side darkening, faint rim glow, soft disc-rim alpha.
func _bake_biome(pt: Dictionary) -> ImageTexture:
	var n := _SPHERE_TEX_N
	var hi := _hex(String(pt.get("hi", "#aaaaaa")))
	var base := _hex(String(pt.get("base", "#888888")))
	var shade := Color(maxf(base.r - 0.2157, 0.0), maxf(base.g - 0.2157, 0.0), maxf(base.b - 0.2157, 0.0))
	var rim := _rim(pt.get("rim", [136, 136, 136]))
	var data := PackedByteArray()
	data.resize(n * n * 4)
	var half := n * 0.5
	for y in n:
		for x in n:
			var px := (x + 0.5 - half) / half
			var py := (y + 0.5 - half) / half
			var d := sqrt(px * px + py * py)
			var a := 1.0 - smoothstep(0.985, 1.0, d)
			# Bright point at lv*0.46 with lv=(1,0).
			var tdx := px - 0.46
			var td := sqrt(tdx * tdx + py * py)
			var col := hi.lerp(base, smoothstep(0.0, 0.62, td))
			col = col.lerp(shade, smoothstep(0.62, 1.30, td))
			# NOTE: night-side darkening is NOT baked here — it's a separate overlay
			# (_bake_night) drawn after surface detail, so detail darkens correctly.
			var rimt := smoothstep(0.72, 1.0, d)
			var idx := (y * n + x) * 4
			data[idx] = int(clampf(col.r + rim.r * rimt * 0.18, 0.0, 1.0) * 255.0)
			data[idx + 1] = int(clampf(col.g + rim.g * rimt * 0.18, 0.0, 1.0) * 255.0)
			data[idx + 2] = int(clampf(col.b + rim.b * rimt * 0.18, 0.0, 1.0) * 255.0)
			data[idx + 3] = int(clampf(a, 0.0, 1.0) * 255.0)
	var img := Image.create_from_data(n, n, false, Image.FORMAT_RGBA8, data)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

# Shared night-side shadow: black, alpha fades 0 (lit, +x) → ~0.55 (dark, -x),
# clipped to the disc. Drawn rotated to lv over base+detail to darken the dark side.
func _bake_night() -> ImageTexture:
	var n := _SPHERE_TEX_N
	var data := PackedByteArray()
	data.resize(n * n * 4)
	var half := n * 0.5
	for y in n:
		for x in n:
			var px := (x + 0.5 - half) / half
			var py := (y + 0.5 - half) / half
			var d := sqrt(px * px + py * py)
			var a := 1.0 - smoothstep(0.985, 1.0, d)
			var night := 0.55 * smoothstep(0.0, 1.0, clampf(-px, 0.0, 1.0))
			var idx := (y * n + x) * 4
			data[idx] = 0
			data[idx + 1] = 0
			data[idx + 2] = 0
			data[idx + 3] = int(clampf(a * night, 0.0, 1.0) * 255.0)
	var img := Image.create_from_data(n, n, false, Image.FORMAT_RGBA8, data)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


# generatePlanetClouds (build_game.py:6848) — view-side, seeded per planet id.
func _get_clouds(p: Dictionary) -> Array:
	var pid := int(p.id)
	if _clouds.has(pid):
		return _clouds[pid]
	var arr := _gen_clouds(p, pid)
	_clouds[pid] = arr
	return arr

func _gen_clouds(p: Dictionary, pid: int) -> Array:
	var id := String((p.get("type", {}) as Dictionary).get("id", ""))
	if not ["ocean", "agri", "chemical", "storm", "resort"].has(id):
		return []
	var rng := RandomNumberGenerator.new()
	rng.seed = pid * 2654435761
	var is_gas := id == "storm"
	var nbase: int
	if is_gas: nbase = rng.randi_range(10, 16)
	elif id == "chemical": nbase = rng.randi_range(9, 14)
	elif id == "ocean": nbase = rng.randi_range(7, 11)
	elif id == "resort": nbase = rng.randi_range(6, 10)
	else: nbase = rng.randi_range(4, 8)
	var n := nbase * (8 if rng.randf() < 0.15 else 2)
	var clouds: Array = []
	for i in n:
		var c := {}
		c.a = rng.randf() * TAU
		if is_gas:
			c.lat = ((float(i) / float(max(1, n - 1))) * 1.6 - 0.8) + (rng.randf() * 0.10 - 0.05) if n > 1 else 0.0
			c.rw = rng.randf_range(0.70, 1.10); c.rh = rng.randf_range(0.08, 0.20); c.al = rng.randf_range(0.24, 0.56)
		else:
			c.lat = rng.randf_range(-0.62, 0.62)
			c.rw = rng.randf_range(0.15, 0.58); c.rh = rng.randf_range(0.14, 0.38); c.al = rng.randf_range(0.26, 0.80)
		c.dx = rng.randf_range(-0.38, 0.38); c.dy = rng.randf_range(-0.24, 0.24)
		c.sw = rng.randf_range(0.45, 0.82); c.sh = rng.randf_range(0.45, 0.78); c.sa = rng.randf_range(0.22, 0.60)
		clouds.append(c)
	return clouds

# drawPlanetClouds (build_game.py:13368) — sphere-projected puffs, back-hemi cull,
# limb compression, screen-aligned, slow drift. Atmosphere mask approximated by a
# per-puff limb taper (full inside r, fade to 0 by r*1.40) + depth cull.
func _draw_clouds(gt: Texture2D, c: Vector2, r: float, p: Dictionary) -> void:
	if clouds_off or r < 8.0:  # build_game.py:28791 gates the galaxy call at sr>8
		return
	var clouds := _get_clouds(p)
	if clouds.is_empty():
		return
	var id := String((p.get("type", {}) as Dictionary).get("id", ""))
	var ccol: Color = _CCOL.get(id, Color8(200, 220, 255))
	var shell := r * 1.07
	var ca: float = float(int(p.id) % 100) * 0.0628 + float(Time.get_ticks_msec()) * 0.0000042
	for cl in clouds:
		var theta: float = cl.a + ca
		var phi: float = cl.lat * PI * 0.44
		var depth := cos(theta) * cos(phi)
		if depth < 0.0:
			continue
		var sw: float = cl.rw * r * maxf(0.04, cos(theta))
		if sw < 0.6:
			continue
		var sh: float = cl.rh * r
		var al: float = cl.al * minf(1.0, depth * 5.0)
		if al < 0.018:
			continue
		var pos := c + Vector2(sin(theta) * shell * cos(phi), -sin(phi) * shell)
		# Atmosphere taper (build_game.py destination-in mask: full inside r, fade
		# to 0 by r*1.40) — approximated by fading puff alpha past the limb so
		# clouds thin toward the edge instead of spilling into space.
		var dc := pos.distance_to(c)
		if dc > r:
			al *= clampf((r * 1.40 - dc) / (r * 0.40), 0.0, 1.0)
			if al < 0.018:
				continue
		var col := ccol
		col.a = minf(1.0, al)
		draw_texture_rect(gt, Rect2(pos - Vector2(sw, sh), Vector2(sw * 2.0, sh * 2.0)), false, col)
		# Wispy secondary blob.
		var sw2: float = sw * cl.sw
		var sh2: float = sh * cl.sh
		var pos2 := pos + Vector2(cl.dx * sw, cl.dy * sh)
		var col2 := ccol
		col2.a = minf(1.0, al * cl.sa)
		draw_texture_rect(gt, Rect2(pos2 - Vector2(sw2, sh2), Vector2(sw2 * 2.0, sh2 * 2.0)), false, col2)


# View-side ring + moon cosmetic data, seeded per planet id (sim skipped it).
var _cosmetic: Dictionary = {}

func _get_cosmetic(p: Dictionary) -> Dictionary:
	var pid := int(p.id)
	if _cosmetic.has(pid):
		return _cosmetic[pid]
	var data := _gen_cosmetic(p, pid)
	_cosmetic[pid] = data
	return data

# generateMoons (build_game.py:6620) + ring (8491), per-planet seeded.
func _gen_cosmetic(p: Dictionary, pid: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = pid * 0x27D4EB2F + 17
	var size := String(p.get("size", "M"))
	var moons: Array = []
	if rng.randf() <= 0.5:
		var count := 1 if rng.randf() < 0.5 else rng.randi_range(2, 6)
		var max_tier: int = {"XS": 0, "S": 1, "M": 2, "L": 2, "XL": 2, "XXL": 2}.get(size, 0)
		var rads := [12.0, 24.0, 48.0]
		var tilts := [0.0, PI / 4.0, PI / 2.0, PI * 0.75]
		for i in count:
			var tier := rng.randi_range(0, max_tier)
			var very_close := rng.randf() < 0.5
			var orbit_mul := rng.randf_range(1.875, 2.325) if very_close else rng.randf_range(2.4, 3.15)
			var period := rng.randf_range(10.0, 40.0)
			var pocks: Array = []
			for j in rng.randi_range(2, 5):
				pocks.append(Vector3(rng.randf_range(-0.6, 0.6), rng.randf_range(-0.6, 0.6), rng.randf_range(0.15, 0.4)))
			moons.append({
				"r": rads[tier], "orbitR": float(p.radius) * orbit_mul,
				"angle": rng.randf_range(0.0, TAU), "speed": (1.0 if rng.randf() < 0.5 else -1.0) * TAU / (period * 60.0),
				"tilt": tilts[rng.randi_range(0, 3)], "incl": rng.randf_range(0.12, 0.38), "pocks": pocks,
			})
	var ring = null
	if not bool(p.get("isStarter", false)) and rng.randf() < 0.10:
		var rim: Array = (p.get("type", {}) as Dictionary).get("rim", [136, 136, 136])
		var rots := [0.0, PI / 8.0, PI / 4.0, PI * 3.0 / 8.0, PI / 2.0, PI * 5.0 / 8.0, PI * 3.0 / 4.0, PI * 7.0 / 8.0]
		ring = {
			"rot": rots[rng.randi_range(0, 7)], "outerFrac": rng.randf_range(2.0, 2.9),
			"innerFrac": rng.randf_range(1.35, 1.75), "incl": rng.randf_range(0.15, 0.42),
			"rgb": Color8(
				mini(255, int(round(float(rim[0]) * 0.5 + rng.randf_range(30, 70)))),
				mini(255, int(round(float(rim[1]) * 0.5 + rng.randf_range(30, 70)))),
				mini(255, int(round(float(rim[2]) * 0.5 + rng.randf_range(30, 70))))),
		}
	return {"moons": moons, "ring": ring}

# drawPlanetRing (build_game.py:12326) — a thick STROKE of the mid-ellipse
# (radii midR × ry2, rot), back (PI..TAU) or front (0..PI) half, lineWidth = ring
# width, uniform colour. A constant-width stroke perpendicular to the flat
# ellipse is a TUBE → the "puffy" voluminous ring (a filled annulus is flat).
# Built as a perpendicular-offset band whose half-width is clamped by the local
# curvature radius so it stays a SIMPLE polygon (no draw_polyline miter spikes)
# and naturally narrows at the ring tips (ansae), like a real tilted ring.
func _draw_ring(c: Vector2, r: float, ring: Dictionary, front: bool) -> void:
	if r < 1.5:
		return
	var mid_r := (float(ring.outerFrac) + float(ring.innerFrac)) * 0.5 * r
	var hw := maxf(0.8, (float(ring.outerFrac) - float(ring.innerFrac)) * r) * 0.5
	var ry2 := maxf(0.4, mid_r * float(ring.incl))
	var rot := float(ring.rot)
	var col: Color = ring.rgb
	col.a = 0.75 if front else 0.45
	var a0 := 0.0 if front else PI
	var a1 := PI if front else TAU
	var cr := cos(rot)
	var sr := sin(rot)
	var segs := 48
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	for i in segs + 1:
		var t := lerpf(a0, a1, float(i) / float(segs))
		var ct := cos(t)
		var st := sin(t)
		var px := mid_r * ct
		var py := ry2 * st
		# outward normal (perp to tangent), normalised.
		var nl := sqrt(ry2 * ry2 * ct * ct + mid_r * mid_r * st * st)
		if nl < 0.0001:
			nl = 1.0
		var nx := (ry2 * ct) / nl
		var ny := (mid_r * st) / nl
		# local curvature radius of the ellipse — clamp half-width below it so the
		# inner offset never crosses over (keeps the polygon simple).
		var rho := pow(mid_r * mid_r * st * st + ry2 * ry2 * ct * ct, 1.5) / maxf(0.001, mid_r * ry2)
		var hwl := minf(hw, 0.86 * rho)
		var ox := px + nx * hwl
		var oy := py + ny * hwl
		var ix := px - nx * hwl
		var iy := py - ny * hwl
		outer.append(c + Vector2(ox * cr - oy * sr, ox * sr + oy * cr))
		inner.append(c + Vector2(ix * cr - iy * sr, ix * sr + iy * cr))
	var poly := PackedVector2Array()
	poly.append_array(outer)
	for i in range(inner.size() - 1, -1, -1):
		poly.append(inner[i])
	draw_colored_polygon(poly, col)

# Moons on the `front` (or behind) hemisphere via getMoonScreenPos (12364).
func _draw_moons(gt: Texture2D, c: Vector2, sc: float, moons: Array, front: bool) -> void:
	var t := float(Time.get_ticks_msec()) * 0.001
	for mm in moons:
		var rx := float(mm.orbitR) * sc
		var ry := rx * float(mm.incl)
		var ang := float(mm.angle) + t * float(mm.speed) * 60.0
		var xl := rx * cos(ang)
		var yl := ry * sin(ang)
		var behind := yl < 0.0
		if behind == front:
			continue
		var tilt := float(mm.tilt)
		var mpos := c + Vector2(xl * cos(tilt) - yl * sin(tilt), xl * sin(tilt) + yl * cos(tilt))
		_draw_moon(gt, mpos, float(mm.r) * sc, mm.pocks)

func _draw_moon(gt: Texture2D, c: Vector2, mr: float, pocks: Array) -> void:
	if mr < 0.4:
		return
	if mr < 1.2:
		draw_circle(c, maxf(0.8, mr), Color(0.667, 0.667, 0.667))
		return
	draw_circle(c, mr, Color(0.28, 0.28, 0.28))
	_glow(gt, c, mr, Color(0.53, 0.53, 0.53))
	_glow(gt, c - Vector2(mr * 0.3, mr * 0.35), mr * 0.6, Color(0.78, 0.78, 0.78))
	if mr >= 2.0:
		for pk in pocks:
			var pr := float(pk.z) * mr
			if pr < 0.35:
				continue
			draw_circle(c + Vector2(float(pk.x) * mr * 0.65, float(pk.y) * mr * 0.65), pr, Color(0, 0, 0, 0.38))


# Stable cosmetic station angle (the sim skipped stationAngle RNG).
func _station_angle(p: Dictionary) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(p.id) * 0x9E3779B1 + 1
	return rng.randf() * TAU

# drawPlanetStation (build_game.py:13221) — equatorial track ring (ties + 2 rails
# + highlight) and 5 surface towers with windows. Basic station only for now
# (large/terminal dock-ring + tier-aware tower heights are a follow-up); alien
# relics use the green palette. ssz = SIZE_R['M']*scale (fixed M-size).
# ── On-planet upgrade buildings (build_game.py drawFoundry/Granary/Farm/Orchard) ──
const _FOUNDRY_KINDS := ["iron_foundry", "blast_furnace", "glassworks", "factory", "bakery", "juicery"]

func _draw_upgrade_buildings(c: Vector2, r: float, p: Dictionary) -> void:
	var ups: Array = p.get("upgrades", [])
	if ups.is_empty():
		return
	var ssz := r
	var base := _station_angle(p) + PI  # opposite the station's track marker
	# Agri buildings group together with a small spread; industrial sit apart.
	var agri: Array = []
	for u in ups:
		var us := String(u)
		if us == "granary" or us == "farm" or us == "orchard":
			agri.append(us)
	var spread: Array = [0.0]
	if agri.size() == 2:
		spread = [-0.55, 0.55]
	elif agri.size() >= 3:
		spread = [-1.15, 0.0, 1.15]
	for i in agri.size():
		var a: float = base + float(spread[i % spread.size()])
		match String(agri[i]):
			"granary": _bld_granary(c, r, a, ssz)
			"farm": _bld_farm(c, r, a, ssz)
			"orchard": _bld_orchard(c, r, a, ssz)
	# Industrial / processing buildings (foundry variants), spaced opposite agri.
	var ind_i := 0
	for u in ups:
		var us := String(u)
		if _FOUNDRY_KINDS.has(us):
			_bld_foundry(c, r, base + PI + ind_i * 0.5 - 0.25, ssz, us)
			ind_i += 1

func _bld_xform(c: Vector2, r: float, angle: float) -> void:
	draw_set_transform(c + Vector2(cos(angle) * r, sin(angle) * r), angle + PI * 0.5, Vector2.ONE)

func _bld_foundry(c: Vector2, r: float, angle: float, ssz: float, kind: String) -> void:
	_bld_xform(c, r, angle)
	var b1w := ssz * 0.14
	var b1h := ssz * 0.20
	draw_rect(Rect2(-b1w * 0.55, -b1h, b1w, b1h), Color(0.282, 0.298, 0.314, 0.95))
	var b2w := ssz * 0.09
	var b2h := ssz * 0.13
	draw_rect(Rect2(-b1w * 0.55 - b2w, -b2h, b2w, b2h), Color(0.4, 0.424, 0.439, 0.9))
	var stw := ssz * 0.04
	var sth := ssz * 0.11
	var stx := b1w * 0.35 - b1w * 0.55
	draw_rect(Rect2(stx, -b1h - sth, stw, sth), Color(0.188, 0.188, 0.204, 0.95))
	# Indicator light — alternating per-kind palette.
	var ph := int(Time.get_ticks_msec() / 500) % 2 == 1
	var puff_r := maxf(1.5, ssz * 0.028)
	var ca := Color(1.0, 0.251, 0.063)
	var cb := Color(0.92, 0.92, 0.92)
	match kind:
		"iron_foundry": ca = Color(1.0, 0.376, 0.063); cb = Color(0.267, 0.8, 1.0)
		"blast_furnace": ca = Color(0.784, 0.816, 0.863); cb = Color(0.376, 0.847, 0.125)
		"glassworks": ca = Color(0.910, 0.788, 0.416); cb = Color(0.376, 0.847, 0.125)
		"bakery": ca = Color(0.910, 0.627, 0.251); cb = Color(0.110, 0.102, 0.078)
		"juicery": ca = Color(0.235, 0.690, 0.329); cb = Color(0.110, 0.102, 0.078)
	draw_circle(Vector2(stx + stw * 0.5, -b1h - sth - puff_r), puff_r, ca if ph else cb)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _bld_granary(c: Vector2, r: float, angle: float, ssz: float) -> void:
	_bld_xform(c, r, angle)
	var bw := ssz * 0.13
	var bh := ssz * 0.19
	draw_rect(Rect2(-bw * 0.5, -bh, bw, bh), Color(0.686, 0.165, 0.118, 0.95))
	for i in range(1, 4):
		var ly := -bh * i / 4.0
		draw_line(Vector2(-bw * 0.5, ly), Vector2(bw * 0.5, ly), Color(0.51, 0.110, 0.071, 0.65), 0.5)
	var hw := bw * 1.2
	var hh := ssz * 0.15
	draw_colored_polygon(PackedVector2Array([Vector2(-hw * 0.5, -bh), Vector2(hw * 0.5, -bh), Vector2(0, -bh - hh)]), Color(0.086, 0.071, 0.071, 0.97))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _bld_farm(c: Vector2, r: float, angle: float, ssz: float) -> void:
	_bld_xform(c, r, angle)
	var bw := ssz * 0.17
	var bh := ssz * 0.16
	draw_rect(Rect2(-bw * 0.5, -bh, bw, bh), Color(0.659, 0.149, 0.110, 0.95))
	var rh := ssz * 0.09
	draw_colored_polygon(PackedVector2Array([Vector2(-bw * 0.56, -bh), Vector2(bw * 0.56, -bh), Vector2(0, -bh - rh)]), Color(0.071, 0.059, 0.059, 0.97))
	var dw := bw * 0.28
	var dh := bh * 0.44
	draw_rect(Rect2(-dw * 0.5, -dh, dw, dh), Color(0.910, 0.886, 0.843, 0.9))
	draw_line(Vector2(-dw * 0.5, -dh), Vector2(dw * 0.5, 0), Color(0.51, 0.110, 0.078, 0.7), 0.5)
	draw_line(Vector2(dw * 0.5, -dh), Vector2(-dw * 0.5, 0), Color(0.51, 0.110, 0.078, 0.7), 0.5)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _bld_orchard(c: Vector2, r: float, angle: float, ssz: float) -> void:
	_bld_xform(c, r, angle)
	var tree_w := ssz * 0.090
	var trunk_h := ssz * 0.084
	var trunk_w := ssz * 0.0264
	var spacing := tree_w * 2.05
	var total_w := 5.0 * spacing
	var start_x := -total_w * 0.5
	var fruit := [Color(1.0, 0.333, 0.2), Color(1.0, 0.6, 0.133), Color(1.0, 0.8, 0.067), Color(0.933, 0.2, 0.467), Color(0.867, 0.133, 0.267), Color(1.0, 0.467, 0.2)]
	for i in 6:
		var tx := start_x + i * spacing
		var canopy_y := -trunk_h - tree_w
		draw_rect(Rect2(tx - trunk_w * 0.5, -trunk_h, trunk_w, trunk_h), Color(0.353, 0.216, 0.078, 0.95))
		draw_circle(Vector2(tx, canopy_y), tree_w, Color(0.137, 0.51, 0.176, 0.95))
		var fc: Color = fruit[i % 6]
		var fr := ssz * 0.0216
		for off in [Vector2(-tree_w * 0.38, -tree_w * 0.22), Vector2(0, tree_w * 0.28), Vector2(tree_w * 0.38, -tree_w * 0.22)]:
			draw_circle(Vector2(tx, canopy_y) + off, fr, fc)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_station(c: Vector2, r: float, p: Dictionary) -> void:
	var is_relic := bool(p.get("isAlienRelic", false))
	# Rival (AI) stations are tinted ORANGE (build_game.py 28810 sepia+hue-rotate),
	# distinct from the player's blue and the alien relic's green.
	var is_ai := not is_relic and bool(p.get("aiHasStation", false)) and not bool(p.get("playerBuiltStation", false)) and not bool(p.get("isStarter", false))
	var sc: float = view.sc
	var ssz := 96.0 * sc
	var angle := _station_angle(p)
	var tie: Color
	var rail: Color
	var rail_hi: Color
	var bldg_fill: Color
	var bldg_str: Color
	var win: Color
	var dock_col: Color
	if is_relic:
		tie = Color("#1a3520"); rail = Color("#2a7a38"); rail_hi = Color("#60b865")
		bldg_fill = Color8(75, 210, 105, 224); bldg_str = Color8(35, 175, 75, 140); win = Color8(155, 255, 135, 217)
		dock_col = Color(0.235, 0.78, 0.392, 0.40)
	elif is_ai:
		tie = Color("#3a2a18"); rail = Color("#9a6a38"); rail_hi = Color("#d8a860")
		bldg_fill = Color8(255, 178, 105, 224); bldg_str = Color8(255, 140, 50, 150); win = Color8(255, 228, 165, 217)
		dock_col = Color(1.0, 0.627, 0.275, 0.40)
	else:
		tie = Color("#2a3a55"); rail = Color("#4a6a9a"); rail_hi = Color("#8ab0d0")
		bldg_fill = Color8(160, 220, 255, 224); bldg_str = Color8(70, 160, 255, 140); win = Color8(255, 255, 180, 217)
		dock_col = Color(0.235, 0.549, 0.941, 0.40)
	var spread := ssz / maxf(r, 0.1)
	# Equatorial track ring.
	if r >= 3.0:
		var gap := ssz * 0.06
		var r1 := r + gap
		var r2 := r1 + maxf(1.5, ssz * 0.08)
		var nties := clampi(int(round(r * 0.65)), 4, 96)
		var tie_out := maxf(0.5, ssz * 0.02)
		var tie_w := maxf(1.0, ssz * 0.05)
		for i in nties:
			var a := (float(i) / float(nties)) * TAU + angle
			var ca := cos(a)
			var sa := sin(a)
			draw_line(c + Vector2((r1 - tie_out) * ca, (r1 - tie_out) * sa), c + Vector2((r2 + tie_out) * ca, (r2 + tie_out) * sa), tie, tie_w)
		var rail_w := maxf(0.8, ssz * 0.035)
		var hi_w := maxf(0.3, ssz * 0.015)
		draw_arc(c, r1, 0.0, TAU, 64, rail, rail_w)
		draw_arc(c, r2, 0.0, TAU, 64, rail, rail_w)
		draw_arc(c, r1, 0.0, TAU, 64, rail_hi, hi_w)
		draw_arc(c, r2, 0.0, TAU, 64, rail_hi, hi_w)
		# Large Station / Terminal dock ring at an outer (MED / HIGH) orbit tier —
		# the commercial ring that distinguishes an upgraded station (build_game.py
		# 13262-13276). Terminal supersedes Large and sits further out.
		var is_terminal := bool(p.get("hasTerminal", false))
		var is_large := bool(p.get("hasLargeStation", false)) and not is_terminal
		if is_terminal or is_large:
			var dock_r := r * (2.3 if is_terminal else 1.8)
			if dock_r > r + 2.0:
				var o1 := dock_r * 0.97
				var o2 := o1 + maxf(1.0, ssz * 0.04)
				var nt2 := clampi(int(round(r * 0.45)), 4, 64)
				var t2w := maxf(0.4, ssz * 0.02)
				for i in nt2:
					var a2 := (float(i) / float(nt2)) * TAU + angle
					var c2 := cos(a2)
					var s2 := sin(a2)
					draw_line(c + Vector2((o1 - 0.5) * c2, (o1 - 0.5) * s2), c + Vector2((o2 + 0.5) * c2, (o2 + 0.5) * s2), Color(dock_col.r, dock_col.g, dock_col.b, 0.30), t2w)
				draw_arc(c, o1, 0.0, TAU, clampi(int(o1 * 0.4), 16, 64), dock_col, maxf(0.5, ssz * 0.018))
				draw_arc(c, o2, 0.0, TAU, clampi(int(o2 * 0.4), 16, 64), dock_col, maxf(0.5, ssz * 0.018))
				draw_arc(c, o1, 0.0, TAU, clampi(int(o1 * 0.4), 16, 64), Color(dock_col.r + 0.3, dock_col.g + 0.3, dock_col.b + 0.06, 0.22), maxf(0.2, ssz * 0.008))
	# Surface towers.
	if ssz >= 10.0:
		# {da, bh, bw} — basic station's 5 towers (build_game.py:13314).
		var buildings: Array[Vector3] = [
			Vector3(-0.24, 0.22, 0.065), Vector3(-0.11, 0.37, 0.058),
			Vector3(0.0, 0.45, 0.075), Vector3(0.12, 0.32, 0.058), Vector3(0.25, 0.19, 0.065),
		]
		var str_w := maxf(0.3, ssz * 0.014)
		for b in buildings:
			var ang := angle + b.x * spread
			var perp := ang + PI * 0.5
			var cosp := cos(perp)
			var sinp := sin(perp)
			var cosa := cos(ang)
			var sina := sin(ang)
			var hw := b.z * ssz
			var bh := b.y * ssz
			var b0 := c + Vector2(r * cosa, r * sina)
			var b1 := b0 + Vector2(bh * cosa, bh * sina)
			var quad := PackedVector2Array([
				b0 - Vector2(hw * cosp, hw * sinp), b0 + Vector2(hw * cosp, hw * sinp),
				b1 + Vector2(hw * cosp, hw * sinp), b1 - Vector2(hw * cosp, hw * sinp),
			])
			draw_colored_polygon(quad, bldg_fill)
			draw_polyline(PackedVector2Array([quad[0], quad[1], quad[2], quad[3], quad[0]]), bldg_str, str_w)
		# Windows.
		for b in buildings:
			if b.y < 0.3:
				continue
			var ang := angle + b.x * spread
			var cosa := cos(ang)
			var sina := sin(ang)
			var wsz := maxf(0.3, ssz * 0.025)
			var bh := b.y * ssz
			var w := c + Vector2(r * cosa + bh * 0.3 * cosa, r * sina + bh * 0.3 * sina)
			draw_rect(Rect2(w - Vector2(wsz * 0.5, wsz * 0.5), Vector2(wsz, wsz)), win)
			if b.y > 0.38 and ssz >= 16.0:
				var w2 := c + Vector2(r * cosa + bh * 0.65 * cosa, r * sina + bh * 0.65 * sina)
				draw_rect(Rect2(w2 - Vector2(wsz * 0.5, wsz * 0.5), Vector2(wsz, wsz)), win)

const _CROP_COLS := [
	Color8(210, 228, 68, 214), Color8(152, 202, 50, 214), Color8(228, 198, 44, 214),
	Color8(182, 218, 75, 214), Color8(248, 216, 65, 204), Color8(112, 178, 32, 214),
	Color8(240, 185, 48, 204), Color8(168, 212, 60, 214), Color8(198, 168, 50, 204),
]

# Biome surface detail (build_game.py drawPlanet inner passes 12107-12200), drawn
# planet-local on the lit base. Generated view-side, seeded per planet id.
const _MTN_BIOMES := ["rocky", "ice", "ancient"]

func _draw_surface(c: Vector2, r: float, p: Dictionary) -> void:
	if r < 5.0:
		return
	var id := String((p.get("type", {}) as Dictionary).get("id", ""))
	if not (["resort", "agri", "oil", "lava", "storm"].has(id) or _MTN_BIOMES.has(id)):
		return
	var s := _get_surface(p)
	if s.is_empty():
		return
	if id == "resort": _draw_resort(c, r, s)
	elif id == "agri": _draw_agri(c, r, s)
	elif id == "oil": _draw_oil(c, r, s)
	elif id == "lava": _draw_lava(c, r, s)
	elif id == "storm": _draw_storm(c, r, s)
	if _MTN_BIOMES.has(id) and s.has("mtn"):
		_draw_mtn(c, r, s.mtn)

func _get_surface(p: Dictionary) -> Dictionary:
	var pid := int(p.id)
	if _surface.has(pid):
		return _surface[pid]
	var rng := RandomNumberGenerator.new()
	rng.seed = pid * 0x85EBCA6B + 7
	var id := String((p.get("type", {}) as Dictionary).get("id", ""))
	var d: Dictionary = {}
	if id == "resort": d = _gen_resort(rng)
	elif id == "agri": d = _gen_agri(rng)
	elif id == "oil": d = _gen_oil(rng)
	elif id == "lava": d = _gen_lava(rng)
	elif id == "storm": d = _gen_storm(rng)
	elif _MTN_BIOMES.has(id): d = {"mtn": _gen_mtn(rng, id)}
	_surface[pid] = d
	return d

# ── Lava volcanoes (build_game.py drawPlanet :12396) ────────────────────────
# Wide cones extruding from the rim toward orbit, each with a glowing lava cap
# + crater bloom. Drawn outside the disc so they poke out.
func _gen_lava(rng: RandomNumberGenerator) -> Dictionary:
	var vols: Array = []
	for i in 2 + int(rng.randf() * 3.0):
		vols.append({"a": rng.randf() * TAU, "wHalf": 0.20 + rng.randf() * 0.20, "h": 0.22 + rng.randf() * 0.26, "phase": rng.randf() * TAU})
	return {"volcanoes": vols}

func _lava_vp(c: Vector2, a: float, wb: float, wt: float, base_r: float, top_r: float, rf: float, lf: float) -> Vector2:
	var rad := base_r + rf * (top_r - base_r)
	var w := wb + rf * (wt - wb)
	var ang := a + lf * w
	return c + Vector2(cos(ang), sin(ang)) * rad

func _draw_lava(c: Vector2, r: float, s: Dictionary) -> void:
	var t := Time.get_ticks_msec()
	for v in s.get("volcanoes", []):
		var a := float(v.a)
		var wb := float(v.wHalf)
		var wt := wb * 0.38
		var base_r := r
		var top_r := r + float(v.h) * r
		var pulse := 0.78 + 0.22 * sin(t * 0.0019 + float(v.phase))
		var b0 := _lava_vp(c, a, wb, wt, base_r, top_r, 0.0, -1.0)
		var b1 := _lava_vp(c, a, wb, wt, base_r, top_r, 0.0, 1.0)
		var t1 := _lava_vp(c, a, wb, wt, base_r, top_r, 1.0, 1.0)
		var t0 := _lava_vp(c, a, wb, wt, base_r, top_r, 1.0, -1.0)
		# Cone body (dark basalt, base→summit gradient via vertex colors).
		var body_lo := Color(0.118, 0.071, 0.059)
		var body_hi := Color(0.180, 0.078, 0.047)
		draw_polygon([b0, b1, t1, t0], [body_lo, body_lo, body_hi, body_hi])
		# Glowing lava cap (upper ~26%).
		var c0 := _lava_vp(c, a, wb, wt, base_r, top_r, 0.74, -1.0)
		var c1 := _lava_vp(c, a, wb, wt, base_r, top_r, 0.74, 1.0)
		var cap_lo := Color(0.745, 0.204, 0.031, 0.5 * pulse)
		var cap_hi := Color(1.0, 0.804, 0.412, 0.95 * pulse)
		draw_polygon([c0, c1, t1, t0], [cap_lo, cap_lo, cap_hi, cap_hi])
		# Crater bloom (concentric glow at the summit).
		var tc := _lava_vp(c, a, wb, wt, base_r, top_r, 1.0, 0.0)
		var crater := maxf(1.5, (t1 - t0).length() * 0.5)
		draw_circle(tc, crater * 1.5, Color(1.0, 0.275, 0.0, 0.18 * pulse))
		draw_circle(tc, crater * 0.9, Color(1.0, 0.588, 0.176, 0.5 * pulse))
		draw_circle(tc, crater * 0.45, Color(1.0, 0.961, 0.784, 0.85 * pulse))

# ── Storm lightning (build_game.py drawPlanet :12323) ───────────────────────
func _gen_storm(rng: RandomNumberGenerator) -> Dictionary:
	var bolts: Array = []
	for i in 3 + int(rng.randf() * 3.0):
		var pts: Array = []
		var a0 := rng.randf() * TAU
		var lat0 := -0.5 + rng.randf()
		var n := 3 + int(rng.randf() * 3.0)
		for j in n:
			pts.append({"a": a0 + (rng.randf() - 0.5) * 0.5, "lat": lat0 + (float(j) / n - 0.5) * (0.6 + rng.randf() * 0.5), "r": 0.2 + 0.8 * float(j) / n})
		bolts.append({"pts": pts, "phase": rng.randf() * 4000.0, "period": 2200.0 + rng.randf() * 2600.0, "dur": 110.0 + rng.randf() * 120.0})
	return {"bolts": bolts}

func _draw_storm(c: Vector2, r: float, s: Dictionary) -> void:
	if r <= 8.0:
		return
	var t := Time.get_ticks_msec()
	var any_active := false
	for bolt in s.get("bolts", []):
		var bt: float = fmod(t + float(bolt.phase), float(bolt.period))
		if bt >= float(bolt.dur):
			continue
		any_active = true
		var fa := (1.0 - (bt / float(bolt.dur)) * 0.4) * 0.92
		var poly: PackedVector2Array = []
		for bp in bolt.pts:
			var dep := cos(float(bp.a)) * cos(float(bp.lat) * PI * 0.45)
			if dep < 0.04:
				continue
			poly.append(c + Vector2(sin(float(bp.a)) * cos(float(bp.lat) * PI * 0.45) * float(bp.r) * r, -sin(float(bp.lat) * PI * 0.45) * float(bp.r) * r))
		if poly.size() >= 2:
			draw_polyline(poly, Color(0.902, 0.824, 1.0, fa), maxf(0.7, r * 0.022), true)
	if any_active:
		draw_circle(c, r, Color(0.784, 0.627, 1.0, 0.10))

# ── Mountains (build_game.py drawPlanet :12370) ─────────────────────────────
func _gen_mtn(rng: RandomNumberGenerator, id: String) -> Array:
	var ms: Array = []
	var base_col := Color(0.40, 0.36, 0.34) if id == "rocky" else (Color(0.78, 0.85, 0.92) if id == "ice" else Color(0.50, 0.44, 0.34))
	for i in 3 + int(rng.randf() * 4.0):
		var h := 0.05 + rng.randf() * 0.10
		var tall := rng.randf() < 0.45
		ms.append({"a": rng.randf() * TAU, "wHalf": 0.09 + rng.randf() * 0.11, "h": h, "tall": tall, "tipH": h * (0.3 + rng.randf() * 0.3) if tall else 0.0,
			"col": Color(base_col.r * (0.8 + rng.randf() * 0.3), base_col.g * (0.8 + rng.randf() * 0.3), base_col.b * (0.8 + rng.randf() * 0.3))})
	return ms

func _draw_mtn(c: Vector2, r: float, ms: Array) -> void:
	for m in ms:
		var a := float(m.a)
		var wh := float(m.wHalf)
		var peak_r := r + float(m.h) * r
		var bl := c + Vector2(cos(a - wh), sin(a - wh)) * r
		var br := c + Vector2(cos(a + wh), sin(a + wh)) * r
		var pk := c + Vector2(cos(a), sin(a)) * peak_r
		draw_colored_polygon([bl, br, pk], m.col)
		if bool(m.tall) and float(m.tipH) > 0.0:
			var tt := 1.0 - float(m.tipH) / float(m.h)
			var sn_r := r + tt * float(m.h) * r
			var sn_w := wh * (1.0 - tt)
			var sl := c + Vector2(cos(a - sn_w), sin(a - sn_w)) * sn_r
			var sr := c + Vector2(cos(a + sn_w), sin(a + sn_w)) * sn_r
			draw_colored_polygon([sl, sr, pk], Color(0.894, 0.957, 1.0, 0.88))

# ── Dyson sphere (build_game.py drawDysonSphere:12622) ──────────────────────
# A Fibonacci-distributed shell of 220 lit hexagonal panels rotating slowly
# around the Y axis. Back panels behind the star disc are culled (the JS uses an
# even-odd clip; centre-cull is a close approximation).
const _DYSON_PANELS := 220

func _draw_dyson(c: Vector2, r: float, sc: float) -> void:
	if r < 4.0:
		return
	var train_h := maxf(2.0, 28.0 * sc)
	var sphere_r := maxf(r * 1.05, r * 1.40 - 1.5 * train_h)
	var hex_r := sphere_r * 0.072
	var rot := Time.get_ticks_msec() * 0.00006
	var c_r := cos(rot)
	var s_r := sin(rot)
	var phi := PI * (3.0 - sqrt(5.0))  # golden angle
	# Build + Y-rotate the panel normals.
	var panels: Array = []
	for i in _DYSON_PANELS:
		var y0 := 1.0 - (float(i) / float(_DYSON_PANELS - 1)) * 2.0
		var rd := sqrt(maxf(0.0, 1.0 - y0 * y0))
		var theta := phi * i
		var px := cos(theta) * rd
		var pz := sin(theta) * rd
		panels.append({"nx": px * c_r + pz * s_r, "ny": y0, "nz": -px * s_r + pz * c_r})
	panels.sort_custom(func(a, b): return a.nz < b.nz)  # painter order
	var stroke_w := maxf(0.5, hex_r * 0.09)
	for p in panels:
		var nx: float = p.nx
		var ny: float = p.ny
		var nz: float = p.nz
		var cxn := nx * sphere_r
		var cyn := ny * sphere_r
		# Back panels behind the star disc → cull (approximates the even-odd clip).
		if nz < 0.0 and Vector2(cxn, cyn).length() < r:
			continue
		# Tangent basis at the panel centre.
		var ux := 0.0
		var uy := 1.0
		var uz := 0.0
		if absf(ny) > 0.96:
			ux = 1.0; uy = 0.0; uz = 0.0
		var up_dot := ux * nx + uy * ny + uz * nz
		var tx := ux - up_dot * nx
		var ty := uy - up_dot * ny
		var tz := uz - up_dot * nz
		var t_len := maxf(0.0001, sqrt(tx * tx + ty * ty + tz * tz))
		tx /= t_len; ty /= t_len; tz /= t_len
		var bx := ny * tz - nz * ty
		var by := nz * tx - nx * tz
		var hex: PackedVector2Array = []
		for v in 6:
			var ang := v * (PI / 3.0)
			var ca := cos(ang) * hex_r
			var sa := sin(ang) * hex_r
			hex.append(c + Vector2(cxn + ca * tx + sa * bx, cyn + ca * ty + sa * by))
		var diffuse := maxf(0.0, nz)
		var bright := (0.32 + 0.55 * diffuse) if nz > 0.0 else (0.20 + 0.20 * (1.0 + nz))
		draw_colored_polygon(hex, Color((58.0 + 110.0 * bright) / 255.0, (78.0 + 110.0 * bright) / 255.0, (108.0 + 105.0 * bright) / 255.0, 0.93))
		var outline := hex.duplicate()
		outline.append(hex[0])
		draw_polyline(outline, Color(0.882, 0.922, 1.0, 0.5 * bright + 0.18), stroke_w, true)
		if diffuse > 0.86:
			draw_colored_polygon(hex, Color(1, 1, 1, 0.42 * (diffuse - 0.86) / 0.14))

# ── Named world-space nebulas (build_game.py _drawNebulas:8443 + names:8408) ──
# Each nebula is a cluster of soft tinted radial blobs (the JS bakes these into a
# canvas; here they're drawn live with the shared glow texture). Overall 0.55
# translucency so they read as background atmosphere. Name labels above ~150px.
func _draw_nebulas(gt: Texture2D, sc: float) -> void:
	if Galaxy.nebulas.is_empty():
		return
	if _neb_font == null:
		_neb_font = load("res://assets/fonts/Exo2-Variable.woff2")
	for n in Galaxy.nebulas:
		var sp: Vector2 = view._w2s(Vector2(n.x, n.y))
		var sw := float(n.rx) * 2.0 * sc
		var sh := float(n.ry) * 2.0 * sc
		if sw < 2.0 or sh < 2.0:
			continue
		var bmax := Vector2(sw, sh).length() * 0.5
		if sp.x + bmax < 0.0 or sp.x - bmax > Tuning.W or sp.y + bmax < 0.0 or sp.y - bmax > Tuning.GH:
			continue
		if not n.has("_blobs"):
			n["_blobs"] = _gen_nebula_blobs(n)
		var rot: float = round(float(n.rot) / (PI * 0.5)) * (PI * 0.5)
		var cosr := cos(rot)
		var sinr := sin(rot)
		for bl in n._blobs:
			var lx: float = float(bl.x) * float(n.rx)
			var ly: float = float(bl.y) * float(n.ry)
			var bsp: Vector2 = view._w2s(Vector2(float(n.x) + lx * cosr - ly * sinr, float(n.y) + lx * sinr + ly * cosr))
			var br: float = float(bl.r) * float(n.rx) * sc
			if br < 0.5:
				continue
			var col: Color = bl.col
			col.a = col.a * 0.55
			draw_texture_rect(gt, Rect2(bsp - Vector2(br, br), Vector2(br * 2.0, br * 2.0)), false, col)
		# Name label.
		var min_dim := minf(sw, sh)
		if min_dim >= 150.0 and sp.x > -100.0 and sp.x < Tuning.W + 100.0 and sp.y > -40.0 and sp.y < Tuning.GH + 40.0:
			var fa := clampf((min_dim - 150.0) / 110.0, 0.0, 1.0)
			var fs := int(clampf(min_dim * 0.03, 7.0, 12.0))
			var label := (String(n.name) + " Nebula").to_upper()
			var lw := _neb_font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(_neb_font, Vector2(sp.x - lw * 0.5, sp.y + fs * 0.35), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.804, 0.804, 0.824, 0.62 * fa))

func _gen_nebula_blobs(n: Dictionary) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(n.seed)
	var pal: Array = Galaxy.NEBULA_PALETTE
	var pri: Array = pal[int(n.colorIdx) % pal.size()]
	var sec: Array = pal[int(n.secColorIdx) % pal.size()]
	var blobs: Array = []
	# Secondary halo (broad central wash).
	blobs.append({"x": 0.0, "y": 0.0, "r": 0.95, "col": _hsl(sec[0], sec[1], sec[2] + 8, 0.22)})
	# Secondary cloud.
	for i in 8 + int(rng.randf() * 7.0):
		blobs.append({"x": (rng.randf() - 0.5) * 0.85, "y": (rng.randf() - 0.5) * 0.85, "r": 0.18 + rng.randf() * 0.45,
			"col": _hsl(sec[0] + (rng.randf() - 0.5) * 36.0, clampf(sec[1] + (rng.randf() - 0.5) * 18.0, 20, 92), clampf(sec[2] + (rng.randf() - 0.5) * 18.0 + 8.0, 14, 60), 0.16 + rng.randf() * 0.18)})
	# Main cloud.
	for i in 14 + int(rng.randf() * 9.0):
		blobs.append({"x": (rng.randf() - 0.5) * 0.70, "y": (rng.randf() - 0.5) * 0.70, "r": 0.12 + rng.randf() * 0.46,
			"col": _hsl(pri[0] + (rng.randf() - 0.5) * 36.0, clampf(pri[1] + (rng.randf() - 0.5) * 18.0, 20, 92), clampf(pri[2] + (rng.randf() - 0.5) * 18.0 + 10.0, 14, 60), 0.16 + rng.randf() * 0.24)})
	# Bright knots.
	for i in 3 + int(rng.randf() * 4.0):
		blobs.append({"x": (rng.randf() - 0.5) * 0.50, "y": (rng.randf() - 0.5) * 0.50, "r": 0.05 + rng.randf() * 0.12,
			"col": _hsl(pri[0] + (rng.randf() - 0.5) * 30.0, 75, 78, 0.42)})
	# Dark dust lanes (approximate via dark over-blobs).
	for i in 1 + int(rng.randf() * 3.0):
		blobs.append({"x": (rng.randf() - 0.5) * 0.60, "y": (rng.randf() - 0.5) * 0.60, "r": 0.14 + rng.randf() * 0.18, "col": Color(0.035, 0.020, 0.055, 0.30)})
	return blobs

# HSL (h 0-360, s/l 0-100) → Color. Godot has from_hsv but not from_hsl.
func _hsl(h: float, s: float, l: float, a: float) -> Color:
	h = fmod(h, 360.0)
	if h < 0.0:
		h += 360.0
	s = clampf(s, 0.0, 100.0) / 100.0
	l = clampf(l, 0.0, 100.0) / 100.0
	var cc := (1.0 - absf(2.0 * l - 1.0)) * s
	var hp := h / 60.0
	var x := cc * (1.0 - absf(fmod(hp, 2.0) - 1.0))
	var m := l - cc * 0.5
	var rr := 0.0
	var gg := 0.0
	var bb := 0.0
	if hp < 1.0: rr = cc; gg = x
	elif hp < 2.0: rr = x; gg = cc
	elif hp < 3.0: gg = cc; bb = x
	elif hp < 4.0: gg = x; bb = cc
	elif hp < 5.0: rr = x; bb = cc
	else: rr = cc; bb = x
	return Color(rr + m, gg + m, bb + m, a)

func _blob_pts(rng: RandomNumberGenerator, rx: float, ry: float, rot: float, n: int, rough: float) -> Array:
	var pts: Array = []
	for i in n:
		var a := (float(i) / float(n)) * TAU + rot
		var pp := 1.0 - rough * 0.5 + rng.randf() * rough
		pts.append(Vector2(cos(a) * rx * pp, sin(a) * ry * pp))
	return pts

func _gen_resort(rng: RandomNumberGenerator) -> Dictionary:
	var lms: Array = []
	var ba := rng.randf() * TAU
	var bd := 0.56 + rng.randf() * 0.28
	var brx := 0.44 + rng.randf() * 0.30
	var bry := 0.24 + rng.randf() * 0.22
	var brot := rng.randf() * PI
	lms.append({"cx": cos(ba) * bd, "cy": sin(ba) * bd, "isLarge": true, "rx": brx, "ry": bry, "rot": brot,
		"pts": _blob_pts(rng, brx, bry, brot, 14, 0.72),
		"sand": Color8(218 + int(rng.randf() * 24), 194 + int(rng.randf() * 20), 114 + int(rng.randf() * 30), 237),
		"veg": Color8(44 + int(rng.randf() * 30), 124 + int(rng.randf() * 34), 40 + int(rng.randf() * 24), 237),
		"deep": Color8(14 + int(rng.randf() * 16), 64 + int(rng.randf() * 24), 14 + int(rng.randf() * 18), 237)})
	for i in 6 + int(rng.randf() * 7):
		var a := rng.randf() * TAU
		var dd := rng.randf() * 0.84
		var rx := 0.024 + rng.randf() * 0.068
		var ry := 0.016 + rng.randf() * 0.044
		var rot := rng.randf() * PI
		lms.append({"cx": cos(a) * dd, "cy": sin(a) * dd, "isLarge": false, "rx": rx, "ry": ry, "rot": rot,
			"pts": _blob_pts(rng, rx, ry, rot, 6, 0.54),
			"sand": Color8(194 + int(rng.randf() * 36), 168 + int(rng.randf() * 28), 96 + int(rng.randf() * 36), 235),
			"veg": Color8(40 + int(rng.randf() * 36), 108 + int(rng.randf() * 40), 36 + int(rng.randf() * 28), 227), "deep": null})
	var sws: Array = []
	for i in 2 + int(rng.randf() * 4):
		var a := rng.randf() * TAU
		var dd := rng.randf() * 0.72
		sws.append({"cx": cos(a) * dd, "cy": sin(a) * dd, "rx": 0.05 + rng.randf() * 0.11, "ry": 0.04 + rng.randf() * 0.08, "rot": rng.randf() * PI})
	return {"lms": lms, "sws": sws}

func _gen_agri(rng: RandomNumberGenerator) -> Dictionary:
	var fields: Array = []
	var clusters: Array = []
	for i in 5 + int(rng.randf() * 16):
		clusters.append({"cx": cos(rng.randf() * TAU) * (rng.randf() * 0.62), "cy": sin(rng.randf() * TAU) * (rng.randf() * 0.62), "spread": 0.13 + rng.randf() * 0.10, "n": 8 + int(rng.randf() * 10)})
	for i in 25 + int(rng.randf() * 26):
		clusters.append({"cx": cos(rng.randf() * TAU) * (rng.randf() * 0.80), "cy": sin(rng.randf() * TAU) * (rng.randf() * 0.80), "spread": 0.04 + rng.randf() * 0.06, "n": 3 + int(rng.randf() * 5)})
	for cl in clusters:
		for fi in int(cl.n):
			var fa := rng.randf() * TAU
			var fd := rng.randf() * float(cl.spread)
			var nx := float(cl.cx) + cos(fa) * fd
			var ny := float(cl.cy) + sin(fa) * fd
			if nx * nx + ny * ny > 0.84:
				continue
			fields.append({"x": nx, "y": ny, "w": 0.044 + rng.randf() * 0.055, "h": 0.018 + rng.randf() * 0.028, "rot": rng.randf() * PI, "col": _CROP_COLS[int(rng.randf() * _CROP_COLS.size())]})
	return {"fields": fields}

func _gen_oil(rng: RandomNumberGenerator) -> Dictionary:
	var bands: Array = []
	for i in 5 + int(rng.randf() * 5):
		bands.append({"angle": rng.randf() * TAU, "spread": 0.18 + rng.randf() * 0.30, "phase": rng.randf() * TAU, "alpha": 0.30 + rng.randf() * 0.28})
	var glints: Array = []
	for i in 3 + int(rng.randf() * 4):
		var a := rng.randf() * TAU
		var dd := rng.randf() * 0.8
		glints.append({"cx": cos(a) * dd, "cy": sin(a) * dd, "r": 0.02 + rng.randf() * 0.05, "phase": rng.randf() * TAU})
	return {"bands": bands, "glints": glints}

func _draw_resort(c: Vector2, r: float, s: Dictionary) -> void:
	for sw in s.sws:
		_draw_ellipse(c + Vector2(float(sw.cx), float(sw.cy)) * r, float(sw.rx) * r, float(sw.ry) * r, float(sw.rot), Color8(92, 208, 244, 66))
	var lms: Array = s.lms.duplicate()
	lms.sort_custom(func(a, b): return bool(a.isLarge) and not bool(b.isLarge))
	for lm in lms:
		var pts: Array = lm.pts
		if pts.is_empty():
			continue
		_draw_land_blob(c, r, float(lm.cx), float(lm.cy), pts, 1.0, lm.sand)
		_draw_land_blob(c, r, float(lm.cx), float(lm.cy), pts, 0.83, lm.veg)
		if lm.deep != null and bool(lm.isLarge):
			_draw_ellipse(c + Vector2(float(lm.cx), float(lm.cy)) * r, float(lm.rx) * r * 0.40, float(lm.ry) * r * 0.40, float(lm.rot), lm.deep)

func _draw_agri(c: Vector2, r: float, s: Dictionary) -> void:
	for f in s.fields:
		var fx := float(f.x)
		var fy := float(f.y)
		var depth := sqrt(maxf(0.0, 1.0 - fx * fx - fy * fy))
		if depth < 0.10:
			continue
		var fw := float(f.w) * r * depth
		var fh := float(f.h) * r * depth
		if fw < 0.7 or fh < 0.35:
			continue
		var fc := c + Vector2(fx, fy) * r
		var rot := float(f.rot)
		var cr := cos(rot)
		var sr := sin(rot)
		var hw := fw * 0.5
		var hh := fh * 0.5
		var quad := PackedVector2Array()
		for co in [Vector2(-hw, -hh), Vector2(hw, -hh), Vector2(hw, hh), Vector2(-hw, hh)]:
			quad.append(fc + Vector2(co.x * cr - co.y * sr, co.x * sr + co.y * cr))
		draw_colored_polygon(quad, f.col)

func _draw_oil(c: Vector2, r: float, s: Dictionary) -> void:
	for band in s.bands:
		var a0 := float(band.angle) - float(band.spread) * 0.5
		var a1 := float(band.angle) + float(band.spread) * 0.5
		var col := _oil_hue(float(band.phase))
		# Per-vertex fade (centre translucent → transparent at the limb) emulates
		# the JS radial-gradient band — soft iridescent shimmer, not a hard wedge.
		var mid := Color(col.r, col.g, col.b, float(band.alpha) * 0.5)
		var edge := Color(col.r, col.g, col.b, 0.0)
		var poly := PackedVector2Array([c])
		var cols := PackedColorArray([mid])
		for i in 9:
			var t := lerpf(a0, a1, float(i) / 8.0)
			poly.append(c + Vector2(cos(t), sin(t)) * r * 0.98)
			cols.append(edge)
		draw_polygon(poly, cols)
	for gl in s.glints:
		var gcol := _oil_hue(float(gl.phase))
		gcol.a = 0.5
		draw_circle(c + Vector2(float(gl.cx), float(gl.cy)) * r, float(gl.r) * r, gcol)

func _oil_hue(ph: float) -> Color:
	var h6 := fposmod(ph, TAU) / TAU * 6.0
	var x := 1.0 - absf(fmod(h6, 2.0) - 1.0)
	if h6 < 1.0: return Color(1, x, 0)
	elif h6 < 2.0: return Color(x, 1, 0)
	elif h6 < 3.0: return Color(0, 1, x)
	elif h6 < 4.0: return Color(0, x, 1)
	elif h6 < 5.0: return Color(x, 0, 1)
	return Color(1, 0, x)

func _draw_land_blob(c: Vector2, r: float, cx: float, cy: float, pts: Array, scale: float, col: Color) -> void:
	# Uniformly shrink the whole blob to fit inside the disc (keeps it a simple,
	# triangulable polygon — per-point clamping self-intersects).
	var maxd := 0.0
	for pt in pts:
		maxd = maxf(maxd, Vector2(cx + pt.x * scale, cy + pt.y * scale).length())
	var fit := 1.0 if maxd < 0.95 else 0.95 / maxd
	var poly := PackedVector2Array()
	for pt in pts:
		poly.append(c + Vector2(cx + pt.x * scale, cy + pt.y * scale) * fit * r)
	draw_colored_polygon(poly, col)

func _draw_ellipse(center: Vector2, rx: float, ry: float, rot: float, col: Color) -> void:
	var poly := PackedVector2Array()
	var cr := cos(rot)
	var sr := sin(rot)
	for i in 20:
		var t := (float(i) / 20.0) * TAU
		var x := rx * cos(t)
		var y := ry * sin(t)
		poly.append(center + Vector2(x * cr - y * sr, x * sr + y * cr))
	draw_colored_polygon(poly, col)

# Gold/diamond deposit patches (build_game.py:11928/11990). Reveal-gating isn't
# in the 2D port's gameplay layer yet, so shown whenever hasGold/hasDiamond.
func _draw_gold_diamond(c: Vector2, r: float, p: Dictionary) -> void:
	if r < 2.0:
		return
	if bool(p.get("hasGold", false)):
		_draw_patch(c, r, _patch_angle(p, 11), PI * 0.25, Color8(255, 200, 0, 205), Color8(255, 255, 180, 230))
	if bool(p.get("hasDiamond", false)):
		_draw_patch(c, r, _patch_angle(p, 23), PI * 0.22, Color8(150, 230, 255, 205), Color8(220, 250, 255, 235))

func _patch_angle(p: Dictionary, salt: int) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(p.id) * salt + 3
	return rng.randf() * TAU

func _draw_patch(c: Vector2, r: float, a0: float, arc: float, fill: Color, glint: Color) -> void:
	var inner := r * 0.6
	var outer := r * 0.98
	var poly := PackedVector2Array()
	for i in 11:
		var t := lerpf(a0, a0 + arc, float(i) / 10.0)
		poly.append(c + Vector2(cos(t), sin(t)) * outer)
	for i in 11:
		var t := lerpf(a0 + arc, a0, float(i) / 10.0)
		poly.append(c + Vector2(cos(t), sin(t)) * inner)
	draw_colored_polygon(poly, fill)
	var gc := maxi(2, int(round(r * 0.18)))
	for gi in gc:
		var ga := a0 + arc * (gi + 0.5) / float(gc)
		var gr := inner + (0.2 if gi % 2 == 0 else 0.5) * (outer - inner)
		draw_circle(c + Vector2(cos(ga), sin(ga)) * gr, maxf(0.5, r * 0.04), glint)

func _glow(gt: Texture2D, c: Vector2, radius: float, color: Color) -> void:
	draw_texture_rect(gt, Rect2(c - Vector2(radius, radius), Vector2(radius * 2.0, radius * 2.0)), false, color)

func _hex(s: String) -> Color:
	return Color.from_string(s, Color(0.5, 0.5, 0.5))

func _rim(arr) -> Color:
	var a: Array = arr
	return Color(float(a[0]) / 255.0, float(a[1]) / 255.0, float(a[2]) / 255.0)
