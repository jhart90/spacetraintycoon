extends Control
## Screens — the front-end M6 flow: TITLE → CORP SETUP → SELECT OPPONENT → galaxy.
## Drawn on a CanvasLayer above the HUD; visible only while GameState.gs != "galaxy"
## (the sim is paused meanwhile via phase=TITLE). Mirrors build_game.py drawTitle /
## drawCorpSetup / drawAISelect + the startGame → _doStartGame → galaxy transitions.

const W := 900.0
const H := 500.0

var view: Node2D  # GalaxyView2D (for biome_tex + the scrolling-train strip)
var f_exo: Font
var f_orb: Font
var f_orb_b: Font
var f_exo_b: Font    # bold Exo 2 (intro CAPS + closing line)
var f_exo_i: Font    # italic Exo 2
var f_exo_bi: Font   # bold italic Exo 2

var _rects: Dictionary = {}
var _mouse := Vector2(-1, -1)  # live cursor → hover states for title/menu buttons
var _t := 0.0
var _train_x := -260.0
var _stars: Array = []
var _btn_pulse := 0.0
# Title planet parade (build_game.py tPlanets / _genTitlePlanetData).
const _RAIL_Y := 392.0
const _TITLE_BIOMES := ["ocean", "lava", "rocky", "resort", "desert", "agri", "urban", "ancient", "chemical", "ice", "jungle", "storm"]
var _tplanets: Array = []
var _trng := RandomNumberGenerator.new()

const _DIFFS := [
	["none", "No Opponent", "Play solo — no rival corporation.", "#88a0c0"],
	["very_easy", "Very Easy", "A struggling startup.", "#7edd9a"],
	["easy", "Easy", "A small regional carrier.", "#9ed86a"],
	["normal", "Normal", "A solid mid-tier rival.", "#ffcc44"],
	["hard", "Hard", "An aggressive operator.", "#ff7a4a"],
	["very_hard", "Very Hard", "A fully optimized empire.", "#e0563c"],
]
# Per-difficulty card styling (build_game.py drawAISelect _dbg/_ddark/_dsprite/_dbord :6359).
const _AI_FILL := {
	"none": Color(0.608, 0.725, 0.980, 0.86), "very_easy": Color(0.647, 0.922, 0.686, 0.88),
	"easy": Color(0.196, 0.529, 0.275, 0.90), "normal": Color(0.933, 0.894, 0.204, 0.90),
	"hard": Color(0.843, 0.282, 0.282, 0.92), "very_hard": Color(0.055, 0.055, 0.078, 0.95),
}
const _AI_BORD := {
	"none": Color(0.333, 0.490, 0.882, 0.70), "very_easy": Color(0.294, 0.765, 0.392, 0.70),
	"easy": Color(0.255, 0.765, 0.353, 0.65), "normal": Color(0.765, 0.725, 0.110, 0.78),
	"hard": Color(0.902, 0.353, 0.353, 0.72), "very_hard": Color(0.569, 0.569, 0.686, 0.50),
}
const _AI_DARK := {"none": true, "very_easy": true, "easy": false, "normal": true, "hard": false, "very_hard": false}
const _AI_SPRITE := {
	"none": "engine_galaxy", "very_easy": "car_flowers", "easy": "car_water_tank",
	"normal": "car_sand", "hard": "car_ore", "very_hard": "car_hazmat",
}
const _CORP_PREFIX := ["DEIMOS", "TRANS-CONTINENTAL", "STELLAR", "ORION", "VEGA", "NOVA", "TITAN", "HELIOS", "ATLAS", "MERIDIAN", "PIONEER", "ZENITH"]
const _CORP_MID := ["FREIGHT", "SHIPPING", "TRANSIT", "CARGO", "RAIL", "STAR", "CROSSING", "HAULAGE", "LOGISTICS", "TRADE"]
const _CORP_SUFFIX := ["NETWORK", "CO.", "LINES", "CORP", "INTERSTELLAR", "WORKS", "GUILD", "SYNDICATE"]

var _ai_choice := "normal"

# Intro cinematic (build_game.py _INTRO_TEXT, ~24 ms/char typed).
const _INTRO_TEXT := [
	"STARDATE 829.\n\nThirty Stardates have passed since the sudden implosion of the Dutch East Earth Interstellar Trading Company (DEEITC), the once-dominant commercial power whose vast network of trade routes, orbital infrastructure, and wormhole technology bound 1,000s of planets together into a single galactic economy.\n\nIn the aftermath, entire star systems were cut off from one another, industries collapsed, and countless worlds have endured decades of economic isolation.",
	"Now, a new age of opportunity has begun.\n\nAcross the galaxy, ambitious CORPORATIONs are racing to fill the void left behind. As the newly appointed CEO of one such enterprise, your mission is to reconnect the stars through a new network of SPACE TRAINs...\n\nEstablish profitable trade ROUTEs.\n\nTransport CARGO from worlds of abundance to worlds in need.\n\nRe-BUILD the foundations of interstellar civilization, one star system at a time.",
	"But commerce alone is not enough. Hidden among the ruins of DEEITC's fallen empire lie the components and knowledge required to reconstruct the legendary WORMHOLE APPARATUS — a colossal device capable of bending space itself.\n\nThe Corporation that is able to re-build this ancient technology first will unlock access to\nTHE MULTI-VERSE...\n\n...and the secrets within that powered both DEEITC's inter-galactic domination, as well as its catastrophic demise!\n\nThe race has begun. The stars await.",
]
var _intro_para := 0
var _intro_chars := 0.0
var _intro_cam0 := Vector2.ZERO
var _intro_shots: Array = []  # cinematic camera shots (build_game.py _buildIntroShots)
var _intro_elapsed := 0.0

# CEO candidates (build_game.py CEO_ROSTER + _genCeoCandidate).
const _CEO_ROSTER := [["Gigi", "ceo_gigi"], ["Jaemin", "ceo_jaemin"], ["Keonho", "ceo_keonho"], ["Mega", "ceo_mega"]]
const _PERK_CARGO := [["Sand", "sand"], ["Water", "water"], ["Molten Ore", "molten_ore"], ["Iron", "iron"], ["Livestock", "livestock"], ["Mail", "mail"], ["Oil", "oil"], ["Battery", "battery"], ["Chemical", "chemical"], ["Passenger", "passengers"], ["Grain", "grain"], ["Fruit", "fruit"]]
var _ceos: Array = []
var _ceo_sel := 0
var _ceo_tex: Dictionary = {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	f_exo = load("res://assets/fonts/Exo2-Variable.woff2")
	f_orb = load("res://assets/fonts/Orbitron-Variable.woff2")
	f_orb_b = _weight(f_orb, 700)
	f_exo_b = _weight(f_exo, 700)
	f_exo_i = _italic(f_exo, false)
	f_exo_bi = _italic(f_exo, true)
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xA17E
	for i in 140:
		_stars.append(Vector3(rng.randf_range(0, W), rng.randf_range(0, H), rng.randf_range(0.4, 1.8)))
	_trng.seed = 0x71717
	var px := 60.0
	for i in 7:
		px += _trng.randf_range(130.0, 250.0)
		_tplanets.append(_make_title_planet(px))
	GameState.corp_name = _gen_corp_name(rng)
	# 3 random CEO candidates, each with a salary + two revenue perks.
	var pool := _CEO_ROSTER.duplicate()
	for k in range(pool.size() - 1, 0, -1):
		var j := rng.randi() % (k + 1)
		var tmp = pool[k]; pool[k] = pool[j]; pool[j] = tmp
	for ci in 3:
		var entry: Array = pool[ci]
		_ceo_tex[entry[1]] = load("res://assets/sprites/%s.png" % entry[1])
		var c1: Array = _PERK_CARGO[rng.randi() % _PERK_CARGO.size()]
		var c2: Array = _PERK_CARGO[rng.randi() % _PERK_CARGO.size()]
		var v1 := 5 + rng.randi() % 20
		var v2 := 5 + rng.randi() % 15
		_ceos.append({
			"name": entry[0], "sprite": entry[1], "salary": 40000 + (rng.randi() % 30) * 10000,
			"perks": ["+%d%% %s Revenue" % [v1, c1[0]], "+%d%% %s Revenue" % [v2, c2[0]]],
			"mult": {String(c1[1]): 1.0 + v1 / 100.0, String(c2[1]): 1.0 + v2 / 100.0},
			"nickname": String(GameState._CEO_NICKNAMES.get(String(c1[1]), "\"The Executive\"")),
		})
	GameState.screen_changed.connect(func(_s): queue_redraw())
	Leaderboard.changed.connect(func(): if GameState.gs == "leaderboard": queue_redraw())


func _weight(base: Font, w: int) -> Font:
	var fv := FontVariation.new()
	fv.base_font = base
	fv.variation_opentype = {"wght": w}
	return fv

# Synthetic italic via a glyph shear (the variable Exo 2 has no italic axis).
func _italic(base: Font, bold: bool) -> Font:
	var fv := FontVariation.new()
	fv.base_font = base
	if bold:
		fv.variation_opentype = {"wght": 700}
	fv.variation_transform = Transform2D(Vector2(1.0, 0.0), Vector2(0.20, 1.0), Vector2.ZERO)
	return fv

func _gen_corp_name(rng: RandomNumberGenerator) -> String:
	var p: String = _CORP_PREFIX[rng.randi() % _CORP_PREFIX.size()]
	var m: String = _CORP_MID[rng.randi() % _CORP_MID.size()]
	var s: String = _CORP_SUFFIX[rng.randi() % _CORP_SUFFIX.size()]
	return "%s %s %s" % [p, m, s]


func _process(delta: float) -> void:
	var active := GameState.gs != "galaxy"
	visible = active
	if not active:
		return
	_t += delta
	_btn_pulse = fmod(_btn_pulse + delta * 1.5, TAU)
	if GameState.gs == "intro":
		_process_intro(delta)
	else:
		_train_x += delta * 70.0
		if _train_x > W + 280.0:
			_train_x = -300.0
		# Scroll + recycle the title planet parade (build_game.py tPlanets loop).
		for p in _tplanets:
			p.x -= p.sp * delta
			if p.x + p.R * 2.4 < 0.0:
				var np := _make_title_planet(W + p.R + _trng.randf_range(60.0, 220.0))
				for k in np:
					p[k] = np[k]
	queue_redraw()

func _make_title_planet(x: float) -> Dictionary:
	var R := _trng.randf_range(42.0, 92.0)
	var moons: Array = []
	for j in (_trng.randi() % 3):
		moons.append({"orb": R + _trng.randf_range(12.0, 28.0), "r": _trng.randf_range(3.0, 6.0), "spd": _trng.randf_range(0.4, 1.0) * (1.0 if _trng.randf() < 0.5 else -1.0), "phase": _trng.randf() * TAU, "tilt": _trng.randf_range(0.0, 1.0)})
	return {
		"x": x, "y": _trng.randf_range(R + 25.0, _RAIL_Y - R - 30.0), "R": R,
		"biome": _TITLE_BIOMES[_trng.randi() % _TITLE_BIOMES.size()],
		"ring": _trng.randf() < 0.35, "sp": _trng.randf_range(8.0, 18.0), "moons": moons,
	}


func _process_intro(delta: float) -> void:
	if OS.get_cmdline_user_args().has("--introshot"):
		return  # dev: freeze on a fully-typed paragraph for a screenshot
	_intro_chars += delta * (1000.0 / 24.0)  # ~24 ms/char (build_game.py)
	var para: String = _INTRO_TEXT[_intro_para]
	if _intro_chars >= float(para.length()) + 110.0:  # ~2.6 s linger after typed
		_intro_para += 1
		_intro_chars = 0.0
		if _intro_para >= _INTRO_TEXT.size():
			_finish_intro()
			return
	# Cinematic CAMERA: a sequence of distinct shots over the real galaxy
	# (build_game.py _buildIntroShots) — Orijen zoom-out opener, planet portrait,
	# home-system, a pan to a distant system, then a galaxy zoom-out. Replaces the
	# old sinusoidal wobble.
	if view:
		if _intro_shots.is_empty():
			_build_intro_shots()
		_intro_elapsed += delta
		var t := _intro_elapsed
		var acc := 0.0
		var shot: Dictionary = _intro_shots[-1] if not _intro_shots.is_empty() else {}
		var t_in := 1.0
		for sh in _intro_shots:
			if t < acc + float(sh.dur):
				shot = sh
				t_in = (t - acc) / float(sh.dur)
				break
			acc += float(sh.dur)
		if not shot.is_empty():
			var e := _ease_io(clampf(t_in, 0.0, 1.0))
			view.cam = (shot.p0 as Vector2).lerp(shot.p1 as Vector2, e)
			view.sc = clampf(lerpf(float(shot.s0), float(shot.s1), e), Tuning.MIN_SC, Tuning.MAX_SC)

func _ease_io(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)  # smoothstep

# Build the cinematic: a 22-second Orijen zoom-out opener (build_game.py:4512)
# followed by a SHUFFLED pool of portrait pans / star pans / nebula zoom-out /
# black-hole zoom-in (build_game.py _buildIntroShots:4474). Narration drives the
# overall length, so the pool is sized to comfortably outlast it.
const _INTRO_DIRS := [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1), Vector2(0.7, 0.7), Vector2(-0.7, 0.7), Vector2(0.7, -0.7), Vector2(-0.7, -0.7)]

func _build_intro_shots() -> void:
	_intro_shots = []
	_intro_elapsed = 0.0
	if Galaxy.planets.is_empty():
		return
	var orijen: Dictionary = Galaxy.planets[Galaxy.origen_id]
	var op := Vector2(float(orijen.x), float(orijen.y))
	var hs: Dictionary = Galaxy.stars[Galaxy.home_star_id]
	var hp := Vector2(float(hs.x), float(hs.y))
	var ss := clampf(220.0 / maxf(float(hs.radius), 50.0), Tuning.MIN_SC, Tuning.MAX_SC * 0.5)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	# ── Opening (NOT shuffled): Orijen MAX_SC → deep zoom-out over 22 s. ──
	_intro_shots.append({"p0": op, "p1": op, "s0": Tuning.MAX_SC, "s1": Tuning.MIN_SC, "dur": 22.0})
	# ── Shuffled pool. ──
	var pool: Array = []
	# Planet portraits — partial-on-screen → opposite-edge pan in a random dir.
	for want in ["lava", "ocean", "urban", "ancient", "resort", "ice"]:
		var pl := _intro_find_planet(want)
		if pl.is_empty():
			continue
		var ppos := Vector2(float(pl.x), float(pl.y))
		var psc := clampf(110.0 / maxf(float(pl.radius), 20.0), Tuning.MIN_SC, Tuning.MAX_SC)
		var half := (Tuning.W * 0.32) / psc
		var d: Vector2 = _INTRO_DIRS[rng.randi() % _INTRO_DIRS.size()]
		pool.append({"p0": ppos - d * half, "p1": ppos + d * half, "s0": psc, "s1": psc, "dur": 5.0})
	# Home system zoom-out.
	pool.append({"p0": hp, "p1": hp, "s0": ss, "s1": ss * 0.5, "dur": 4.5})
	# Distant / Dyson star pan.
	var ds := _intro_dyson_or_distant(hp)
	if not ds.is_empty():
		var dsp := Vector2(float(ds.x), float(ds.y))
		var dsc := clampf(200.0 / maxf(float(ds.radius), 50.0), Tuning.MIN_SC, Tuning.MAX_SC * 0.4)
		var dpan := (Tuning.W * 0.25) / dsc
		pool.append({"p0": dsp - Vector2(dpan, dpan * 0.4), "p1": dsp + Vector2(dpan, dpan * 0.4), "s0": dsc, "s1": dsc, "dur": 5.5})
	# Nebula zoom-out (now that nebulas exist).
	if not Galaxy.nebulas.is_empty():
		var nb := _intro_best_nebula()
		var nbp := Vector2(float(nb.x), float(nb.y))
		var nsc := clampf((Tuning.W * 0.45) / maxf(float(nb.rx), 5000.0), Tuning.MIN_SC, Tuning.MAX_SC * 0.2)
		pool.append({"p0": nbp, "p1": nbp, "s0": nsc, "s1": nsc * 0.5, "dur": 5.0})
	# Black-hole zoom-in.
	if not Galaxy.black_holes.is_empty():
		var bh: Dictionary = Galaxy.black_holes[rng.randi() % Galaxy.black_holes.size()]
		var bhp := Vector2(float(bh.x), float(bh.y))
		var bclose := clampf(150.0 / maxf(float(bh.radius), 500.0), Tuning.MIN_SC, Tuning.MAX_SC * 0.5)
		pool.append({"p0": bhp, "p1": bhp, "s0": bclose * 0.4, "s1": bclose, "dur": 5.0})
	# Fisher-Yates shuffle (random order each playthrough, like the JS).
	for i in range(pool.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var tmp = pool[i]; pool[i] = pool[j]; pool[j] = tmp
	for sh in pool:
		_intro_shots.append(sh)

func _intro_find_planet(biome: String) -> Dictionary:
	for p in Galaxy.planets:
		if String((p.get("type", {}) as Dictionary).get("id", "")) == biome:
			return p
	return {}

func _intro_dyson_or_distant(from: Vector2) -> Dictionary:
	for s in Galaxy.stars:
		if s.get("hasDysonSphere", false):
			return s
	var best: Dictionary = {}
	var best_d := 0.0
	var n := 0
	for s in Galaxy.stars:
		var d := from.distance_squared_to(Vector2(float(s.x), float(s.y)))
		if d > best_d and d < 9.0e9:
			best_d = d
			best = s
		n += 1
		if n > 120:
			break
	return best

func _intro_best_nebula() -> Dictionary:
	# The largest nebula closest to the world centre (build_game.py:4846).
	var best: Dictionary = {}
	var best_score := -INF
	for nb in Galaxy.nebulas:
		var size: float = float(nb.rx) + float(nb.ry)
		var dist: float = Vector2(float(nb.x), float(nb.y)).length()
		var score := size - dist * 0.02
		if score > best_score:
			best_score = score
			best = nb
	return best


func _finish_intro() -> void:
	if view:
		var hs: Dictionary = Galaxy.stars[Galaxy.home_star_id]
		view.cam = Vector2(float(hs.x), float(hs.y))
		view.sc = clampf(Tuning.W / 12000.0, Tuning.MIN_SC, Tuning.MAX_SC)
		view._clamp_camera()
	GameState.set_screen("corpsetup")


func _draw() -> void:
	_rects.clear()
	if GameState.gs == "intro":
		_draw_intro()
		return
	# Shared opaque starfield backdrop for the menus.
	draw_rect(Rect2(0, 0, W, H), Color8(4, 7, 18))
	for s in _stars:
		var a: float = 0.35 + 0.45 * sin(_t * 0.8 + s.x * 0.05)
		draw_circle(Vector2(s.x, s.y), s.z * 0.8, Color(1, 1, 1, clampf(a, 0.15, 0.85)))
	match GameState.gs:
		"title": _draw_title()
		"corpsetup": _draw_corpsetup()
		"aiselect": _draw_aiselect()
		"leaderboard": _draw_leaderboard_screen()


# ── INTRO CINEMATIC (build_game.py drawHowToPlay §13) — typed narration over the
#    galaxy (which renders behind, dimmed), with a SKIP button. ────────────────
func _draw_intro() -> void:
	if OS.get_cmdline_user_args().has("--introshot"):
		_intro_para = 2; _intro_chars = 99999.0
	draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, 0.42))  # single cinematic dim (build_game.py 5065)
	var para: String = _INTRO_TEXT[_intro_para]
	var n: int = clampi(int(_intro_chars), 0, para.length())
	# Styled narration — 15px Exo 2, vertically centred, CAPS bold + italics +
	# bold closing line (build_game.py _introRenderText 5080).
	_draw_styled_intro(para.substr(0, n), W * 0.5, H * 0.5, 640.0, 22.0, Color(0.910, 0.933, 0.980, 0.97), _intro_para)
	# Proximity-faded controls (baseline 0.25 → 1.0 within 60 px of the cursor).
	var sk := Rect2(W - 132.0, H - 46.0, 110.0, 28.0)
	_intro_btn(sk, "SKIP  ▶▶", Color(0.039, 0.094, 0.196), Color(0.314, 0.549, 0.824), Color(0.784, 0.882, 1.0), "intro_skip")
	var qt := Rect2(22.0, H - 46.0, 90.0, 28.0)
	_intro_btn(qt, "◀ QUIT", Color(0.078, 0.118, 0.275), Color(0.275, 0.392, 0.627), Color(0.706, 0.804, 1.0), "intro_quit")
	var mu := Rect2(120.0, H - 46.0, 28.0, 28.0)
	_intro_btn(mu, "♪" if not _sfx_muted_intro() else "✕", Color(0.078, 0.118, 0.275), Color(0.275, 0.392, 0.627), Color(0.706, 0.804, 1.0), "intro_mute")

func _sfx_muted_intro() -> bool:
	return Audio.music_vol <= 0.0 if "music_vol" in Audio else false

# Proximity-faded intro button (alpha 0.25 baseline, 1.0 within 60 px).
func _intro_btn(r: Rect2, label: String, fill: Color, border: Color, text_col: Color, key: String) -> void:
	var d := r.get_center().distance_to(_mouse)
	var a := clampf(remap(d, 60.0, 200.0, 1.0, 0.25), 0.25, 1.0)
	var hov := r.has_point(_mouse)
	_round_rect(r, 5.0, Color(fill.r, fill.g, fill.b, fill.a * a + (0.15 if hov else 0.0)))
	draw_rect(r, Color(border.r, border.g, border.b, (0.95 if hov else 0.55) * a), false, 1.0)
	_ctr(f_orb_b, r.position.x + r.size.x * 0.5, r.position.y + r.size.y * 0.5 + 4.0, label, 11, Color(text_col.r, text_col.g, text_col.b, text_col.a * a), r.size.x)
	_rects[key] = r

# Render styled intro text: word-wrap, CAPS runs bold, screen-2 italic targets,
# bold closing line; vertically centred at y_center.
func _draw_styled_intro(shown: String, cx: float, y_center: float, max_w: float, lh: float, base_col: Color, para_idx: int) -> void:
	var lines: Array = []
	for seg in shown.split("\n"):
		var line := ""
		for w in seg.split(" "):
			var t := w if line == "" else line + " " + w
			if f_exo.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x <= max_w:
				line = t
			else:
				lines.append(line)
				line = w
		lines.append(line)
	var y := y_center - lines.size() * lh * 0.5 + lh
	for ln in lines:
		_draw_styled_line(String(ln), cx, y, base_col, para_idx)
		y += lh

func _draw_styled_line(text: String, cx: float, y: float, base_col: Color, para_idx: int) -> void:
	if text == "":
		return
	var caps := _find_caps_ranges(text)
	var ital: Array = []
	var whole_bold := para_idx == 2 and text.begins_with("The race")
	if para_idx == 2:
		for tgt in ["inter-galactic domination", "catastrophic demise!"]:
			var idx := text.find(tgt)
			if idx >= 0:
				ital.append([idx, idx + tgt.length()])
	# Group consecutive chars sharing a style into segments.
	var segs: Array = []
	var i := 0
	while i < text.length():
		var b := whole_bold or _in_ranges(i, caps)
		var it := _in_ranges(i, ital)
		var j := i + 1
		while j < text.length() and (whole_bold or _in_ranges(j, caps)) == b and _in_ranges(j, ital) == it:
			j += 1
		segs.append([text.substr(i, j - i), b, it])
		i = j
	var total := 0.0
	for s in segs:
		total += _intro_font(s[1], s[2]).get_string_size(String(s[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	var x := cx - total * 0.5
	for s in segs:
		var fnt := _intro_font(s[1], s[2])
		draw_string(fnt, Vector2(x, y), String(s[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, base_col)
		x += fnt.get_string_size(String(s[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x

func _intro_font(bold: bool, ital: bool) -> Font:
	if bold and ital: return f_exo_bi
	if ital: return f_exo_i
	if bold: return f_exo_b
	return f_exo

func _in_ranges(i: int, ranges: Array) -> bool:
	for r in ranges:
		if i >= int(r[0]) and i < int(r[1]):
			return true
	return false

# All-caps runs ≥2 chars, joining across single space/hyphen before another
# upper/digit, digits allowed inside (build_game.py _findAllCapsRanges 5161).
func _find_caps_ranges(text: String) -> Array:
	var out: Array = []
	var i := 0
	var n := text.length()
	while i < n:
		if _is_upper(text[i]):
			var j := i
			var has_upper := false
			while j < n:
				var ch := text[j]
				if _is_upper(ch):
					has_upper = true; j += 1; continue
				if ch >= "0" and ch <= "9":
					j += 1; continue
				if ch == " " or ch == "-":
					if j + 1 < n and (_is_upper(text[j + 1]) or (text[j + 1] >= "0" and text[j + 1] <= "9")):
						j += 1; continue
					break
				break
			while j > i and (text[j - 1] == " " or text[j - 1] == "-"):
				j -= 1
			if has_upper and (j - i) >= 2:
				out.append([i, j])
			i = maxi(j, i + 1)
		else:
			i += 1
	return out

func _is_upper(c: String) -> bool:
	return c >= "A" and c <= "Z"


# ── TITLE (build_game.py drawTitleScreen 4152) ──────────────────────────────
func _draw_title() -> void:
	# Scrolling planet parade behind the wordmark (build_game.py tPlanets).
	for p in _tplanets:
		_draw_title_planet(p)
	# Rail + sleepers (tsp=28) + the scrolling train consist (build_game.py 4214).
	var rt := _RAIL_Y
	var tx := -fmod(_t * 38.0, 28.0)
	while tx < W:
		draw_rect(Rect2(tx - 4.0, rt - 3.0, 10.0, 16.0), Color(0.165, 0.227, 0.333))
		tx += 28.0
	draw_line(Vector2(0, rt + 1.0), Vector2(W, rt + 1.0), Color(0.290, 0.416, 0.604), 3.0)
	draw_line(Vector2(0, rt + 11.0), Vector2(W, rt + 11.0), Color(0.290, 0.416, 0.604), 3.0)
	draw_line(Vector2(0, rt), Vector2(W, rt), Color(0.541, 0.690, 0.816), 1.0)
	draw_line(Vector2(0, rt + 10.0), Vector2(W, rt + 10.0), Color(0.541, 0.690, 0.816), 1.0)
	if view and view.get("_trains"):
		view._trains.draw_car_strip(self, Rect2(_train_x, rt - 34.0, 250.0, 36.0), ["engine_galaxy", "car_passenger", "car_ore", "caboose"], [true, true, true, true])
	# Wordmark — TWO lines, 75px, cyan-gradient face + doubled glow, NO stroke.
	_wordmark(W * 0.5, 82.0, "SPACE TRAIN", 75)
	_wordmark(W * 0.5, 151.0, "TYCOON", 75)
	# Subtitle — auto-fit to ~0.62× the "SPACE TRAIN" width.
	var st_w := f_orb_b.get_string_size("SPACE TRAIN", HORIZONTAL_ALIGNMENT_LEFT, -1, 75).x
	var sub := "INTERSTELLAR SHIPPING CORPORATION SIMULATOR"
	var sub_px: int = clampi(int(round(18.0 * (st_w * 0.62) / f_exo.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x)), 8, 18)
	_ctr(f_exo, W * 0.5, 187.0, sub, sub_px, Color(0.537, 0.706, 0.847))
	# Buttons — PLAY 190×46 (pulsing cyan); LOAD/LEADERBOARD 2/3 size (amber/purple).
	var pulse := 0.6 + 0.4 * sin(_btn_pulse)
	var bw := 190.0
	var bh := 46.0
	var bx := W * 0.5 - bw * 0.5
	var by := 217.0
	_title_action_btn(Rect2(bx, by, bw, bh), "PLAY GAME", 17, Color(0.27, 0.63, 1.0), Color(0.031, 0.086, 0.227, 0.72 + 0.2 * pulse), Color(0.235, 0.627, 1.0, 0.55 + 0.45 * pulse), Color(0.667, 0.863, 1.0), "play", pulse)
	var lbw := roundf(bw * 2.0 / 3.0)
	var lbh := roundf(bh * 2.0 / 3.0)
	var lby := by + bh + 14.0
	_title_action_btn(Rect2(W * 0.5 - lbw * 0.5, lby, lbw, lbh), "LOAD GAME", 12, Color(1.0, 0.667, 0.267), Color(0.149, 0.086, 0.008, 0.82), Color(0.784, 0.608, 0.196, 0.65), Color(0.824, 0.667, 0.314), "load", 1.0)
	var lby2 := lby + lbh + 14.0
	_title_action_btn(Rect2(W * 0.5 - lbw * 0.5, lby2, lbw, lbh), "LEADERBOARD", 12, Color(0.655, 0.424, 1.0), Color(0.102, 0.055, 0.165, 0.82), Color(0.588, 0.392, 0.824, 0.6), Color(0.745, 0.627, 0.902), "leaderboard", 1.0)
	# Version (bottom-left) + gear (bottom-right).
	draw_string(f_exo, Vector2(12.0, H - 12.0), "v0.4.5", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.373, 0.392, 0.439, 0.8))
	_gear_btn(Rect2(W - 46.0, H - 46.0, 32.0, 32.0))

func _draw_title_planet(p: Dictionary) -> void:
	var c := Vector2(p.x, p.y)
	var R: float = p.R
	if p.ring:
		_title_ring(c, R, false)
	var bt: Texture2D = view._content.biome_tex(String(p.biome)) if (view and view.get("_content")) else null
	if bt != null:
		draw_texture_rect(bt, Rect2(c - Vector2(R, R), Vector2(R * 2.0, R * 2.0)), false)
	else:
		draw_circle(c, R, Color(0.4, 0.4, 0.5))
	if p.ring:
		_title_ring(c, R, true)
	for m in p.moons:
		var a: float = _t * float(m.spd) + float(m.phase)
		var mc := c + Vector2(cos(a) * float(m.orb), sin(a) * float(m.orb) * absf(cos(float(m.tilt))))
		draw_circle(mc, float(m.r), Color(0.706, 0.722, 0.78))
		draw_arc(mc, float(m.r), 0.0, TAU, 10, Color(0.5, 0.52, 0.58, 0.6), 1.0)

func _title_ring(c: Vector2, R: float, front: bool) -> void:
	var rr := R * 1.5
	var ry := R * 0.42
	var pts := PackedVector2Array()
	var a0 := 0.0 if front else PI
	for i in 33:
		var a := a0 + PI * i / 32.0
		pts.append(c + Vector2(cos(a) * rr, sin(a) * ry))
	draw_polyline(pts, Color(0.667, 0.733, 0.882, 0.5), 2.5)


# ── FULL-SCREEN LEADERBOARD (build_game.py drawLeaderboardScreen) ────────────
# Reads the REAL online top-100 from Leaderboard.rows. 9 columns (rank, name,
# 7 metrics); clicking a metric header refetches sorted by it; page arrows.
func _draw_leaderboard_screen() -> void:
	if Leaderboard.status == "":
		Leaderboard.fetch_top("corp_value")  # entered without a fetch (dev --screen path)
	draw_rect(Rect2(0, 0, W, H), Color8(10, 8, 32))
	_wordmark(W * 0.5, 56.0, "ALL-TIME HIGH SCORES", 26.0)
	_ctr(f_exo, W * 0.5, 82.0, "Space Train Tycoon — Top 100 Corporations", 11, Color(0.706, 0.667, 0.824, 0.7))
	var margin: float = maxf(40.0, W * 0.035)
	var table_x := margin
	var table_w := W - 2.0 * margin
	var weights := [0.8, 2.8, 1.35, 1.0, 1.0, 1.15, 1.15, 1.1, 1.0]
	var wsum := 0.0
	for w in weights:
		wsum += w
	var col_x: Array = []
	var cx := table_x
	for w in weights:
		col_x.append(cx)
		cx += w / wsum * table_w
	col_x.append(table_x + table_w)
	var head_y := 126.0
	var table_top := head_y + 30.0
	var row_h: float = clampf((H - table_top - 110.0) / 10.0, 28.0, 46.0)
	# Header row.
	_ctr(f_orb_b, (col_x[0] + col_x[1]) * 0.5, head_y + 8.0, "#", 10, Color(0.588, 0.627, 0.725, 0.85))
	draw_string(f_orb_b, Vector2(col_x[1] + 6.0, head_y + 12.0), "CORPORATION", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.588, 0.627, 0.725, 0.85))
	for m in Leaderboard.METRICS.size():
		var md: Dictionary = Leaderboard.METRICS[m]
		var ci := 2 + m
		var lx: float = col_x[ci]
		var rx: float = col_x[ci + 1]
		var active_col := Leaderboard.metric == String(md.col)
		var hh := _hov(Rect2(lx, head_y - 12.0, rx - lx, 30.0)) and not active_col
		if active_col:
			draw_rect(Rect2(lx, head_y - 12.0, rx - lx, 30.0), Color(0.471, 0.353, 0.784, 0.32))
		elif hh:
			draw_rect(Rect2(lx, head_y - 12.0, rx - lx, 30.0), Color(0.392, 0.294, 0.627, 0.20))
		_ctr(f_orb_b, (lx + rx) * 0.5, head_y + 8.0, String(md.label) + (" v" if active_col else ""), 10, Color(0.902, 0.812, 1.0) if active_col else (Color(0.831, 0.804, 0.937) if hh else Color(0.608, 0.647, 0.745, 0.88)))
		_rects["lbhdr_%s" % String(md.col)] = Rect2(lx, head_y - 12.0, rx - lx, 30.0)
	draw_line(Vector2(table_x, head_y + 22.0), Vector2(table_x + table_w, head_y + 22.0), Color(0.471, 0.431, 0.667, 0.5), 1.5)
	# Body.
	if Leaderboard.status != "ok":
		var msg := "Loading leaderboard…"
		var col := Color(0.784, 0.784, 0.863, 0.85)
		if Leaderboard.status == "error":
			msg = "Could not reach the leaderboard — check your connection and try again."; col = Color(1.0, 0.549, 0.549, 0.9)
		elif Leaderboard.status == "empty":
			msg = "No entries yet — be the first to make the board!"
		_ctr(f_exo, W * 0.5, table_top + 90.0, msg, 14, col)
	else:
		var start := Leaderboard.page * 10
		for r in 10:
			var idx := start + r
			if idx >= Leaderboard.rows.size():
				break
			var row: Dictionary = Leaderboard.rows[idx]
			var ry := table_top + r * row_h
			var ty := ry + row_h * 0.5 + 5.0
			var mine: bool = Leaderboard.corp_id != "" and String(row.get("corp_id", "")) == Leaderboard.corp_id
			draw_rect(Rect2(table_x, ry, table_w, row_h), Color(0.373, 0.275, 0.667, 0.38) if mine else (Color(1, 1, 1, 0.025) if r % 2 == 0 else Color(1, 1, 1, 0.06)))
			var rankcol := Color(0.745, 0.765, 0.843, 0.9)
			if idx == 0: rankcol = Color(1.0, 0.835, 0.290)
			elif idx == 1: rankcol = Color(0.812, 0.847, 0.902)
			elif idx == 2: rankcol = Color(0.847, 0.627, 0.416)
			_ctr(f_orb_b, (col_x[0] + col_x[1]) * 0.5, ty, "#%d" % (idx + 1), 13, rankcol)
			draw_string(f_orb_b if mine else f_orb, Vector2(col_x[1] + 6.0, ty), String(row.get("corp_name", "?")), HORIZONTAL_ALIGNMENT_LEFT, col_x[2] - col_x[1] - 12.0, 13, Color.WHITE if mine else Color(0.894, 0.894, 0.949, 0.95))
			for m2 in Leaderboard.METRICS.size():
				var md2: Dictionary = Leaderboard.METRICS[m2]
				var ci2 := 2 + m2
				var act2 := Leaderboard.metric == String(md2.col)
				_ctr(f_orb_b if act2 else f_exo, (col_x[ci2] + col_x[ci2 + 1]) * 0.5, ty, Leaderboard.fmt_cell(row, String(md2.col)), 12, Color(0.918, 0.847, 1.0) if act2 else Color(0.792, 0.812, 0.890, 0.85))
	# Footer: BACK + page label with prev/next triangles.
	var table_bot := table_top + 10.0 * row_h
	var foot_cy: float = clampf(table_bot + 30.0, H - 56.0, H - 26.0)
	var btn := Rect2(table_x, foot_cy - 14.0, 104.0, 28.0)
	var bhov := _hov(btn)
	_round_rect(btn, 8.0, Color(0.275, 0.216, 0.471, 0.95) if bhov else Color(0.176, 0.137, 0.314, 0.85))
	draw_rect(btn, Color(0.667, 0.561, 0.945, 0.85) if bhov else Color(0.471, 0.392, 0.745, 0.6), false, 2.0 if bhov else 1.5)
	_ctr(f_orb_b, btn.position.x + btn.size.x * 0.5, foot_cy + 4.0, "< BACK", 11, Color(0.871, 0.831, 1.0, 0.96), btn.size.x)
	_rects["lb_back"] = btn
	if Leaderboard.status == "ok":
		var lo := Leaderboard.page * 10 + 1
		var hi: int = mini(Leaderboard.rows.size(), Leaderboard.page * 10 + 10)
		var rk_txt := "Ranks %d-%d of %d" % [lo, hi, Leaderboard.rows.size()]
		_ctr(f_exo, W * 0.5, foot_cy + 4.0, rk_txt, 12, Color(0.745, 0.765, 0.863, 0.82))
		var rk_half := f_exo.get_string_size(rk_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x * 0.5
		var prev_en := Leaderboard.page > 0
		var next_en := Leaderboard.page < Leaderboard.max_page()
		var pcx := W * 0.5 - rk_half - 18.0
		_lbs_tri(pcx, foot_cy, false, prev_en)
		if prev_en: _rects["lb_prev"] = Rect2(pcx - 15.0, foot_cy - 15.0, 30.0, 30.0)
		var ncx := W * 0.5 + rk_half + 18.0
		_lbs_tri(ncx, foot_cy, true, next_en)
		if next_en: _rects["lb_next"] = Rect2(ncx - 15.0, foot_cy - 15.0, 30.0, 30.0)

func _lbs_tri(cx: float, cy: float, right: bool, enabled: bool) -> void:
	var s := 8.0
	var hov := enabled and _hov(Rect2(cx - 15.0, cy - 15.0, 30.0, 30.0))
	var col := (Color(0.85, 0.78, 1.0, 1.0) if hov else Color(0.627, 0.549, 0.882, 0.85)) if enabled else Color(0.431, 0.431, 0.510, 0.38)
	var pts: PackedVector2Array
	if right:
		pts = PackedVector2Array([Vector2(cx - s * 0.5, cy - s), Vector2(cx + s * 0.5, cy), Vector2(cx - s * 0.5, cy + s)])
	else:
		pts = PackedVector2Array([Vector2(cx + s * 0.5, cy - s), Vector2(cx - s * 0.5, cy), Vector2(cx + s * 0.5, cy + s)])
	draw_colored_polygon(pts, col)


func _wordmark(cx: float, baseline: float, text: String, size: int) -> void:
	# Faithful to wordmark2.png: cyan-gradient face + DOUBLED cyan glow, NO dark
	# stroke (build_game.py 4244-4257). Godot _draw has no shadowBlur/gradient, so
	# the glow is simulated by many low-alpha offset passes and the gradient by a
	# bright cyan-white face (the #fff centre dominates).
	var w := f_orb_b.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var x := cx - w * 0.5
	var glow := Color(0.27, 0.67, 1.0)
	for rad in [13.0, 9.0, 6.0, 3.5]:
		for ai in 10:
			var off := Vector2(cos(ai * TAU / 10.0) * rad, sin(ai * TAU / 10.0) * rad)
			draw_string(f_orb_b, Vector2(x + off.x, baseline + off.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(glow.r, glow.g, glow.b, 0.05))
	# Bright face — two passes for the wordmark's "punch".
	var face := Color(0.831, 0.949, 1.0)
	draw_string(f_orb_b, Vector2(x, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, face)
	draw_string(f_orb_b, Vector2(x, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, face)

# Pulsing, glowing, rounded title button (build_game.py 4271-4307).
func _title_action_btn(r: Rect2, label: String, fsize: int, glow_col: Color, fill: Color, border: Color, text_col: Color, key: String, pulse: float) -> void:
	var hov := _hov(r)
	# Glow — expanding low-alpha rounded outlines.
	for i in range(5, 0, -1):
		var ga := (0.07 if hov else 0.05 * pulse) * (float(i) / 5.0)
		_round_rect_outline(r.grow(i * 2.0), 8.0, Color(glow_col.r, glow_col.g, glow_col.b, ga), 2.0)
	_filled_round_rect(r, 8.0, fill.lightened(0.18) if hov else fill)
	_round_rect_outline(r, 8.0, border.lightened(0.25) if hov else border, 2.5 if hov else 2.0)
	_ctr(f_orb_b, r.position.x + r.size.x * 0.5, r.position.y + r.size.y * 0.5 + fsize * 0.36, label, fsize, text_col.lightened(0.18) if hov else text_col, r.size.x)
	_rects[key] = r

func _filled_round_rect(r: Rect2, rad: float, col: Color) -> void:
	rad = minf(rad, minf(r.size.x, r.size.y) * 0.5)
	draw_rect(Rect2(r.position.x + rad, r.position.y, r.size.x - 2.0 * rad, r.size.y), col)
	draw_rect(Rect2(r.position.x, r.position.y + rad, r.size.x, r.size.y - 2.0 * rad), col)
	draw_circle(r.position + Vector2(rad, rad), rad, col)
	draw_circle(r.position + Vector2(r.size.x - rad, rad), rad, col)
	draw_circle(r.position + Vector2(rad, r.size.y - rad), rad, col)
	draw_circle(r.position + Vector2(r.size.x - rad, r.size.y - rad), rad, col)

func _round_rect_outline(r: Rect2, rad: float, col: Color, w: float) -> void:
	rad = minf(rad, minf(r.size.x, r.size.y) * 0.5)
	var p := r.position
	var s := r.size
	draw_line(Vector2(p.x + rad, p.y), Vector2(p.x + s.x - rad, p.y), col, w)
	draw_line(Vector2(p.x + rad, p.y + s.y), Vector2(p.x + s.x - rad, p.y + s.y), col, w)
	draw_line(Vector2(p.x, p.y + rad), Vector2(p.x, p.y + s.y - rad), col, w)
	draw_line(Vector2(p.x + s.x, p.y + rad), Vector2(p.x + s.x, p.y + s.y - rad), col, w)
	draw_arc(p + Vector2(rad, rad), rad, PI, PI * 1.5, 8, col, w)
	draw_arc(p + Vector2(s.x - rad, rad), rad, PI * 1.5, TAU, 8, col, w)
	draw_arc(p + Vector2(rad, s.y - rad), rad, PI * 0.5, PI, 8, col, w)
	draw_arc(p + Vector2(s.x - rad, s.y - rad), rad, 0.0, PI * 0.5, 8, col, w)


func _title_btn(r: Rect2, label: String, fill: Color, border: Color, text_col: Color, key: String) -> void:
	var hov := _hov(r)
	_round_rect(r, 5.0, fill.lightened(0.2) if hov else fill)
	draw_rect(r, border.lightened(0.3) if hov else border, false, 2.5 if hov else 1.5)
	_ctr(f_orb_b, r.position.x + r.size.x * 0.5, r.position.y + r.size.y * 0.5 + 4.0, label, 12, text_col.lightened(0.2) if hov else text_col, r.size.x)
	_rects[key] = r


# Full-screen bordered setup panel shared by corp-setup + AI-select.
func _setup_panel(border: Color) -> Rect2:
	var r := Rect2(32.0, 24.0, W - 64.0, H - 80.0)
	_round_rect(r, 8.0, Color(0.024, 0.039, 0.118, 0.94))
	draw_rect(r, border, false, 1.5)
	return r

# Glowing gradient-ish title (the original uses a horizontal canvas gradient;
# approximated with a colored glow halo + bright core).
func _glow_title(cx: float, y: float, text: String, size: int, glow: Color, core: Color) -> void:
	for off in [Vector2(-2, 0), Vector2(2, 0), Vector2(0, -2), Vector2(0, 2), Vector2(-1.5, -1.5), Vector2(1.5, 1.5)]:
		_ctr(f_orb_b, cx + off.x, y + off.y, text, size, Color(glow.r, glow.g, glow.b, 0.30))
	_ctr(f_orb_b, cx, y, text, size, core)

# ── CORP SETUP (build_game.py drawCorpSetup :6162) ──────────────────────────
func _draw_corpsetup() -> void:
	var pr := _setup_panel(Color(0.235, 0.392, 0.784, 0.48))
	var px := pr.position.x
	var py := pr.position.y
	_glow_title(W * 0.5, py + 42.0, "ESTABLISH YOUR CORPORATION", 26, Color(0.533, 0.667, 1.0), Color(0.882, 0.945, 1.0))
	draw_line(Vector2(px + 20.0, py + 62.0), Vector2(px + pr.size.x - 20.0, py + 62.0), Color(0.235, 0.392, 0.784, 0.30), 1.0)
	# Corp name label + field + regenerate.
	_ctr(f_orb_b, W * 0.5, py + 81.0, "NAME YOUR CORPORATION:", 10, Color(0.510, 0.667, 0.902, 0.82))
	var fr := Rect2(W * 0.5 - 230.0, py + 88.0, 460.0, 38.0)
	var fhov := _hov(fr)
	_round_rect(fr, 5.0, Color(0.110, 0.188, 0.431, 0.90) if fhov else Color(0.047, 0.086, 0.259, 0.90))
	draw_rect(fr, Color(0.431, 0.667, 1.0, 0.90) if fhov else Color(0.216, 0.373, 0.784, 0.50), false, 1.2)
	_ctr(f_exo, W * 0.5, py + 113.0, String(GameState.corp_name), 18, Color(0.510, 0.725, 1.0, 0.97))
	if fhov:
		var hint := "click to rename"
		var hw := f_exo.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		draw_string(f_exo, Vector2(fr.position.x + fr.size.x - 10.0 - hw, fr.position.y + fr.size.y - 10.0), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.392, 0.627, 1.0, 0.55))
	_rects["regen"] = fr  # click the name field to roll a new corp name
	# CEO selection (left-aligned label).
	draw_string(f_orb_b, Vector2(px + 30.0, py + 145.0), "SELECT YOUR CEO:", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.510, 0.667, 0.902, 0.82))
	var cw := 242.0
	var gap := 22.0
	var x0 := (W - (3.0 * cw + 2.0 * gap)) * 0.5
	var cy := py + 150.0
	var ch := 240.0
	var sal_bg := [Color(0.333, 0.282, 0.031, 0.68), Color(0.345, 0.216, 0.020, 0.68), Color(0.345, 0.141, 0.016, 0.68)]
	var sal_tc := [Color(1.0, 0.902, 0.196, 0.97), Color(1.0, 0.745, 0.141, 0.97), Color(1.0, 0.541, 0.086, 0.97)]
	for ci in _ceos.size():
		var ceo: Dictionary = _ceos[ci]
		var cx := x0 + ci * (cw + gap)
		var cc := cx + cw * 0.5
		var sel := ci == _ceo_sel
		var chov := _hov(Rect2(cx, cy, cw, ch)) and not sel
		_round_rect(Rect2(cx, cy, cw, ch), 8.0, Color(0.039, 0.118, 0.255, 0.90) if sel else (Color(0.055, 0.110, 0.267, 0.82) if chov else Color(0.031, 0.071, 0.196, 0.78)))
		draw_rect(Rect2(cx, cy, cw, ch), Color(0.216, 0.824, 0.451, 0.85) if sel else (Color(0.314, 0.471, 0.863, 0.65) if chov else Color(0.196, 0.294, 0.627, 0.38)), false, 2.0 if sel else 1.0)
		# Portrait.
		var p_y := cy + 12.0
		var tex: Texture2D = _ceo_tex.get(String(ceo.sprite), null)
		if tex != null:
			draw_texture_rect(tex, Rect2(cc - 40.0, p_y, 80.0, 80.0), false)
		draw_rect(Rect2(cc - 40.0, p_y, 80.0, 80.0), Color(0.216, 0.824, 0.451, 0.55) if sel else Color(0.314, 0.510, 0.863, 0.48), false, 1.0)
		# Name + nickname.
		_ctr(f_orb_b, cc, p_y + 97.0, String(ceo.name), 11, Color(0.765, 0.863, 1.0, 0.97))
		_ctr(f_exo, cc, p_y + 111.0, String(ceo.get("nickname", "")), 10, Color(0.580, 0.686, 0.933, 0.70))
		# 3 labelled pill rows: SALARY / ABILITY / STARTING CREDITS.
		_cs_pill_row(cx, cw, p_y + 130.0, "SALARY", "-%s cr/Stardate" % _fmt(int(ceo.salary)), sal_bg[ci], sal_tc[ci])
		_cs_pill_row(cx, cw, p_y + 160.0, "ABILITY", String((ceo.perks as Array)[0]), Color(0.098, 0.608, 1.0, 0.97), Color(0, 0, 0))
		_cs_pill_row(cx, cw, p_y + 190.0, "STARTING CREDITS", "+%s cr" % _fmt(Tuning.PLAYER_START_CREDITS), Color(0.063, 0.275, 0.165, 0.72), Color(0.471, 0.941, 0.647, 0.97))
		if sel:
			_ctr(f_orb_b, cc, cy + ch - 9.0, "✓ SELECTED", 8, Color(0.216, 0.824, 0.451, 0.92))
		_rects["ceo_pick_" + str(ci)] = Rect2(cx, cy, cw, ch)
	# NEXT (pulsing blue) + BACK.
	var pulse := 0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.003)
	var nb := Rect2(W - 172.0, H - 68.0, 140.0, 40.0)
	var nhov := _hov(nb)
	_round_rect(nb, 6.0, Color(0.047, 0.118, 0.314, 0.97) if nhov else Color(0.031, 0.086, 0.227, 0.78 + 0.15 * pulse))
	draw_rect(nb, Color(0.471, 0.784, 1.0, 0.98) if nhov else Color(0.235, 0.627, 1.0, 0.55 + 0.45 * pulse), false, 2.5 if nhov else 2.0)
	_ctr(f_orb_b, nb.position.x + 70.0, nb.position.y + 26.0, "NEXT  ▶", 14, Color(0.784, 0.918, 1.0) if nhov else Color(0.667, 0.863, 1.0))
	_rects["to_aiselect"] = nb
	_title_btn(Rect2(px + 20.0, H - 64.0, 100.0, 36.0), "← BACK", Color(0.078, 0.118, 0.275, 0.70), Color(0.196, 0.294, 0.627, 0.35), Color(0.7, 0.82, 1.0), "back_title")

# One CEO-card pill row: left header + right-anchored truncated pill.
func _cs_pill_row(cx: float, cw: float, row_cy: float, label: String, pill_text: String, bg: Color, tc: Color) -> void:
	var pad := 14.0
	draw_string(f_orb_b, Vector2(cx + pad, row_cy + 3.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(0.478, 0.596, 0.816, 0.72))
	var hdr_w := f_orb_b.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 7).x
	var right_x := cx + cw - pad
	var max_pw := right_x - (cx + pad + hdr_w + 8.0)
	var txt := pill_text
	var pwid := f_exo.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 14.0
	while txt.length() > 2 and pwid > max_pw:
		txt = txt.substr(0, txt.length() - 1)
		pwid = f_exo.get_string_size(txt + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 14.0
	if txt != pill_text:
		txt += "…"
	var pill_x := right_x - pwid
	_round_rect(Rect2(pill_x, row_cy - 10.0, pwid, 20.0), 4.0, bg)
	_ctr(f_exo, pill_x + pwid * 0.5, row_cy + 4.0, txt, 11, tc, pwid)

func _fmt(n: int) -> String:
	var s := str(n)
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return out


# ── SELECT OPPONENT (build_game.py drawAISelect :6335) ──────────────────────
func _draw_aiselect() -> void:
	var pr := _setup_panel(Color(0.784, 0.471, 0.118, 0.48))
	var px := pr.position.x
	var py := pr.position.y
	var pwid := pr.size.x
	_glow_title(W * 0.5, py + 42.0, "SELECT YOUR OPPONENT", 26, Color(1.0, 0.667, 0.196), Color(1.0, 0.937, 0.745))
	draw_line(Vector2(px + 20.0, py + 62.0), Vector2(px + pwid - 20.0, py + 62.0), Color(0.784, 0.471, 0.118, 0.30), 1.0)
	# 6 cards filling the panel, sprites straddling each card's top edge.
	var inner_pad := 44.0
	var avail := pwid - inner_pad * 2.0
	var gap := maxf(10.0, roundf(avail * 0.014))
	var btn_w := floorf((avail - 5.0 * gap) / 6.0)
	var sp_h := 64.0
	var btn_h := 96.0
	var x0 := (W - (6.0 * btn_w + 5.0 * gap)) * 0.5
	var cy := py + 150.0
	for i in _DIFFS.size():
		var d: Array = _DIFFS[i]
		var did := String(d[0])
		var bx := x0 + i * (btn_w + gap)
		var sel := did == _ai_choice
		var dhov := _hov(Rect2(bx, cy, btn_w, btn_h)) and not sel
		var fill: Color = _AI_FILL[did]
		var bord: Color = _AI_BORD[did]
		_round_rect(Rect2(bx, cy, btn_w, btn_h), 7.0, fill if sel else (Color(fill.r, fill.g, fill.b, fill.a * 1.08) if dhov else fill))
		draw_rect(Rect2(bx, cy, btn_w, btn_h), bord.lightened(0.2) if sel else bord, false, 2.5 if sel else 1.2)
		# Per-difficulty text color (dark on light cards, light on dark cards).
		var dark: bool = _AI_DARK[did]
		var tc := Color(0.031, 0.047, 0.094, 0.95) if dark else Color(0.933, 0.973, 1.0, 0.97)
		var tcd := Color(0.031, 0.055, 0.125, 0.60) if dark else Color(0.824, 0.902, 1.0, 0.62)
		# Sprite straddling the top edge.
		if view and view.get("_trains"):
			view._trains.draw_car_strip(self, Rect2(bx + 4.0, cy - sp_h * 0.5, btn_w - 8.0, sp_h), [String(_AI_SPRITE[did])], [true])
		var lbl_y := cy + sp_h * 0.5 + 15.0
		_ctr(f_orb_b, bx + btn_w * 0.5, lbl_y, String(d[1]), 11, tc, btn_w)
		draw_string(f_exo, Vector2(bx + 7.0, lbl_y + 16.0), String(d[2]), HORIZONTAL_ALIGNMENT_CENTER, btn_w - 14.0, 8, tcd)
		# Selected checkmark bleeding off the top-right corner.
		if sel:
			draw_string(f_orb_b, Vector2(bx + btn_w - 18.0, cy + 4.0), "✓", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(1, 1, 1, 0.95))
		_rects["diff_" + did] = Rect2(bx, cy, btn_w, btn_h)
	# START GAME (green) + BACK.
	var cb := Rect2(W - 222.0, H - 64.0, 190.0, 36.0)
	var chov := _hov(cb)
	_round_rect(cb, 7.0, Color(0.176, 0.725, 0.392, 0.98) if chov else Color(0.098, 0.569, 0.282, 0.90))
	draw_rect(cb, Color(0.392, 1.0, 0.647, 0.75) if chov else Color(0.196, 0.784, 0.431, 0.48), false, 1.5)
	_ctr(f_orb_b, cb.position.x + 95.0, cb.position.y + 23.0, "START GAME", 14, Color(0.863, 1.0, 0.902, 0.98))
	_rects["start_game"] = cb
	_title_btn(Rect2(px + 20.0, H - 64.0, 100.0, 36.0), "← BACK", Color(0.078, 0.118, 0.275, 0.70), Color(0.196, 0.294, 0.627, 0.35), Color(0.7, 0.82, 1.0), "back_corp")


# ── Input ───────────────────────────────────────────────────────────────────
# Global input (not _gui_input): a Control parented to a CanvasLayer doesn't get a
# viewport-sized rect, so _gui_input never fires. _input is rect-independent — we
# hit-test the cursor against our own _rects (logical 900×500 coords). Matches Chrome.
func _input(event: InputEvent) -> void:
	if GameState.gs == "galaxy":
		return  # the galaxy view + HUD own input in-game
	if event is InputEventMouseMotion:
		_mouse = (event as InputEventMouseMotion).position
		var over := false
		for k in _rects.keys():
			if (_rects[k] as Rect2).has_point(_mouse):
				over = true
				break
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if over else Control.CURSOR_ARROW
		queue_redraw()
		return
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not (mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT):
		return
	var p := mb.position
	for k in _rects.keys():
		if (_rects[k] as Rect2).has_point(p):
			_on_click(String(k)); get_viewport().set_input_as_handled(); return
	# Click anywhere during the intro (not on a button) snap-finishes the typed
	# paragraph, then advances (build_game.py _introAdvance).
	if GameState.gs == "intro":
		_intro_advance(); get_viewport().set_input_as_handled()

func _intro_advance() -> void:
	var para: String = _INTRO_TEXT[_intro_para]
	if _intro_chars < float(para.length()):
		_intro_chars = float(para.length())  # snap-finish typing this paragraph
	else:
		_intro_para += 1
		_intro_chars = 0.0
		if _intro_para >= _INTRO_TEXT.size():
			_finish_intro()

func _hov(r: Rect2) -> bool:
	return r.has_point(_mouse)

func _on_click(key: String) -> void:
	Audio.play("button")
	match key:
		"play":
			_intro_para = 0; _intro_chars = 0.0; _intro_shots = []; _intro_elapsed = 0.0; GameState.set_screen("intro")
		"intro_skip": _finish_intro()
		"intro_quit": GameState.set_screen("title")
		"intro_mute": Audio.toggle_music_mute()
		"load":
			if SaveLoad.load_game():
				_enter_galaxy()
		"regen":
			var rng := RandomNumberGenerator.new(); rng.randomize(); GameState.corp_name = _gen_corp_name(rng); queue_redraw()
		"leaderboard":
			GameState.set_screen("leaderboard"); Leaderboard.fetch_top("corp_value")
		"lb_back": GameState.set_screen("title")
		"lb_prev":
			if Leaderboard.page > 0:
				Leaderboard.page -= 1; queue_redraw()
		"lb_next":
			if Leaderboard.page < Leaderboard.max_page():
				Leaderboard.page += 1; queue_redraw()
		"back_title": GameState.set_screen("title")
		"to_aiselect": GameState.set_screen("aiselect")
		"back_corp": GameState.set_screen("corpsetup")
		"start_game":
			GameState.ai_difficulty = _ai_choice
			if _ceo_sel < _ceos.size():
				var ceo: Dictionary = _ceos[_ceo_sel]
				GameState.set_ceo(ceo)        # installs name + revenue mult + nickname
				GameState.roll_ceo_candidates()  # seed the hire bench
			if _ai_choice != "none":
				AICorp.init_corp(_ai_choice)
			_enter_galaxy()
		_:
			if key.begins_with("diff_"):
				_ai_choice = key.trim_prefix("diff_"); queue_redraw()
			elif key.begins_with("ceo_pick_"):
				_ceo_sel = int(key.trim_prefix("ceo_pick_")); queue_redraw()
			elif key.begins_with("lbhdr_"):
				var col := key.trim_prefix("lbhdr_")
				if Leaderboard.metric != col:
					Leaderboard.fetch_top(col)

func _enter_galaxy() -> void:
	GameState.set_screen("galaxy")
	if view and view.has_method("enter_galaxy"):
		view.enter_galaxy()


# ── helpers ─────────────────────────────────────────────────────────────────
func _logical(screen_pos: Vector2) -> Vector2:
	# The CanvasLayer/Control is in the 900×500 logical space already.
	return screen_pos

func _round_rect(r: Rect2, rad: float, col: Color) -> void:
	_filled_round_rect(r, rad, col)

func _ctr(font: Font, cx: float, cy: float, text: String, size: int, col: Color, width: float = 900.0) -> void:
	draw_string(font, Vector2(cx - width * 0.5, cy), text, HORIZONTAL_ALIGNMENT_CENTER, width, size, col)

func _gear_btn(r: Rect2) -> void:
	var hov := _hov(r)
	_round_rect(r, 4.0, Color(0.353, 0.569, 0.961, 0.92) if hov else Color(0.235, 0.431, 0.784, 0.75))
	draw_rect(r, Color(0.55, 0.82, 1.0, 0.9) if hov else Color(0.392, 0.706, 1.0, 0.7), false, 1.5 if hov else 1.0)
	var c := r.position + r.size * 0.5
	var gc := Color(0.85, 0.94, 1.0, 1.0) if hov else Color(0.7, 0.86, 1.0, 0.95)
	draw_arc(c, 6.0, 0.0, TAU, 16, gc, 2.0)
	draw_circle(c, 2.5, gc)
	# TODO(audit): wire to Options-on-title (PopupManager gates options to galaxy).
	for i in 8:
		var a := i * TAU / 8.0
		draw_line(c + Vector2(cos(a), sin(a)) * 5.0, c + Vector2(cos(a), sin(a)) * 8.5, Color(0.7, 0.86, 1.0, 0.95), 1.5)
	_rects["options"] = r
