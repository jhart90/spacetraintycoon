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
	["very_hard", "Very Hard", "A fully optimised empire.", "#e0563c"],
]
const _CORP_PREFIX := ["DEIMOS", "TRANS-CONTINENTAL", "STELLAR", "ORION", "VEGA", "NOVA", "TITAN", "HELIOS", "ATLAS", "MERIDIAN", "PIONEER", "ZENITH"]
const _CORP_MID := ["FREIGHT", "SHIPPING", "TRANSIT", "CARGO", "RAIL", "STAR", "CROSSING", "HAULAGE", "LOGISTICS", "TRADE"]
const _CORP_SUFFIX := ["NETWORK", "CO.", "LINES", "CORP", "INTERSTELLAR", "WORKS", "GUILD", "SYNDICATE"]

var _ai_choice := "normal"

# Intro cinematic (build_game.py _INTRO_TEXT, ~24 ms/char typed).
const _INTRO_TEXT := [
	"STARDATE 829.\n\nThirty Stardates have passed since the sudden implosion of the Dutch East Earth Interstellar Trading Company (DEEITC), the once-dominant commercial power whose vast network of trade routes, orbital infrastructure, and wormhole technology bound 1,000s of planets together into a single galactic economy.\n\nIn the aftermath, entire star systems were cut off from one another, industries collapsed, and countless worlds have endured decades of economic isolation.",
	"Now, a new age of opportunity has begun.\n\nAcross the galaxy, ambitious CORPORATIONs are racing to fill the void left behind. As the newly appointed CEO of one such enterprise, your mission is to reconnect the stars through a new network of SPACE TRAINs...\n\nEstablish profitable trade ROUTEs.\n\nTransport CARGO from worlds of abundance to worlds in need.\n\nRe-BUILD the foundations of interstellar civilization, one star system at a time.",
	"But commerce alone is not enough. Hidden among the ruins of DEEITC's fallen empire lie the components and knowledge required to reconstruct the legendary WORMHOLE APPARATUS — a colossal device capable of bending space itself.\n\nThe Corporation that re-builds this ancient technology first will unlock access to THE MULTI-VERSE...\n\n...and the secrets within that powered both DEEITC's inter-galactic domination, as well as its catastrophic demise!\n\nThe race has begun. The stars await.",
]
var _intro_para := 0
var _intro_chars := 0.0
var _intro_cam0 := Vector2.ZERO

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
		})
	GameState.screen_changed.connect(func(_s): queue_redraw())
	Leaderboard.changed.connect(func(): if GameState.gs == "leaderboard": queue_redraw())


func _weight(base: Font, w: int) -> Font:
	var fv := FontVariation.new()
	fv.base_font = base
	fv.variation_opentype = {"wght": w}
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
	_intro_chars += delta * (1000.0 / 24.0)  # ~24 ms/char (build_game.py)
	var para: String = _INTRO_TEXT[_intro_para]
	if _intro_chars >= float(para.length()) + 110.0:  # ~2.6 s linger after typed
		_intro_para += 1
		_intro_chars = 0.0
		if _intro_para >= _INTRO_TEXT.size():
			_finish_intro()
			return
	# Cinematic slow zoom-out drift across the home system behind the text.
	if view:
		var total := 0.0
		for p in _INTRO_TEXT:
			total += float(p.length()) + 110.0
		var done := 0.0
		for i in _intro_para:
			done += float(_INTRO_TEXT[i].length()) + 110.0
		var prog := clampf((done + _intro_chars) / total, 0.0, 1.0)
		view.sc = lerpf(Tuning.MAX_SC * 0.5, 0.05, prog)
		var hs: Dictionary = Galaxy.stars[Galaxy.home_star_id]
		view.cam = Vector2(float(hs.x) + sin(_t * 0.12) * 900.0, float(hs.y) + cos(_t * 0.09) * 560.0)
		view._clamp_camera()


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
	draw_rect(Rect2(0, 0, W, H), Color(0.01, 0.02, 0.05, 0.55))  # cinematic dim
	# Narration band.
	draw_rect(Rect2(0, 300.0, W, 150.0), Color(0.01, 0.02, 0.06, 0.55))
	var para: String = _INTRO_TEXT[_intro_para]
	var n: int = clampi(int(_intro_chars), 0, para.length())
	var shown: String = para.substr(0, n)
	draw_multiline_string(f_exo, Vector2(W * 0.15, 322.0), shown, HORIZONTAL_ALIGNMENT_CENTER, W * 0.70, 13, -1, Color(0.85, 0.93, 1.0, 0.96))
	# Paragraph dots.
	for i in _INTRO_TEXT.size():
		draw_circle(Vector2(W * 0.5 - 12.0 + i * 12.0, 466.0), 3.0, Color(0.6, 0.82, 1.0, 0.95) if i == _intro_para else Color(0.3, 0.42, 0.62, 0.6))
	# Skip.
	var sk := Rect2(W - 110.0, H - 42.0, 92.0, 26.0)
	_round_rect(sk, 4.0, Color(0.08, 0.16, 0.32, 0.85))
	draw_rect(sk, Color(0.4, 0.55, 0.82, 0.6), false, 1.0)
	_ctr(f_exo, sk.position.x + sk.size.x * 0.5, sk.position.y + 17.0, "SKIP  ›", 11, Color(0.8, 0.9, 1.0, 0.92), sk.size.x)
	_rects["intro_skip"] = sk


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


# ── CORP SETUP (build_game.py drawCorpSetup) ────────────────────────────────
func _draw_corpsetup() -> void:
	_ctr(f_orb_b, W * 0.5, 44.0, "FOUND YOUR CORPORATION", 16, Color(1.0, 0.82, 0.31))
	# Corp name field.
	var fr := Rect2(W * 0.5 - 220.0, 60.0, 440.0, 32.0)
	_round_rect(fr, 5.0, Color(0.039, 0.078, 0.196, 0.9))
	draw_rect(fr, Color(0.314, 0.588, 1.0, 0.6), false, 1.5)
	_ctr(f_orb_b, W * 0.5, 82.0, GameState.corp_name, 13, Color(0.78, 0.88, 1.0))
	# Regenerate-name button.
	var rg := Rect2(W * 0.5 - 65.0, 98.0, 130.0, 20.0)
	_round_rect(rg, 4.0, Color(0.08, 0.16, 0.34, 0.85))
	draw_rect(rg, Color(0.314, 0.549, 0.9, 0.5), false, 1.0)
	_ctr(f_exo, W * 0.5, 112.0, "↻ NEW NAME", 9, Color(0.6, 0.78, 1.0, 0.9), 130.0)
	_rects["regen"] = rg
	# CEO picker.
	_ctr(f_orb_b, W * 0.5, 142.0, "CHOOSE YOUR CEO", 11, Color(1.0, 0.82, 0.31, 0.9))
	var cw := 220.0
	var gap := 18.0
	var total := 3.0 * cw + 2.0 * gap
	var x0 := (W - total) * 0.5
	var cy := 152.0
	var ch := 232.0
	for ci in _ceos.size():
		var ceo: Dictionary = _ceos[ci]
		var cx := x0 + ci * (cw + gap)
		var sel := ci == _ceo_sel
		var chov := _hov(Rect2(cx, cy, cw, ch)) and not sel
		_round_rect(Rect2(cx, cy, cw, ch), 6.0, Color(0.078, 0.157, 0.314, 0.85) if sel else (Color(0.059, 0.122, 0.275, 0.85) if chov else Color(0.039, 0.086, 0.196, 0.7)))
		draw_rect(Rect2(cx, cy, cw, ch), Color(1.0, 0.82, 0.31, 0.9) if sel else (Color(0.392, 0.549, 0.824, 0.7) if chov else Color(0.196, 0.314, 0.549, 0.4)), false, 2.0 if sel else 1.0)
		var tex: Texture2D = _ceo_tex.get(String(ceo.sprite), null)
		if tex != null:
			draw_texture_rect(tex, Rect2(cx + cw * 0.5 - 44.0, cy + 12.0, 88.0, 88.0), false)
		_ctr(f_orb_b, cx + cw * 0.5, cy + 122.0, String(ceo.name).to_upper(), 13, Color(0.78, 0.9, 1.0) if sel else Color(0.6, 0.74, 0.95, 0.85))
		_ctr(f_exo, cx + cw * 0.5, cy + 142.0, "Salary: %s cr / SD" % _fmt(int(ceo.salary)), 9, Color(1.0, 0.7, 0.45, 0.8), cw)
		var perks: Array = ceo.perks
		_ctr(f_exo, cx + cw * 0.5, cy + 168.0, "• " + String(perks[0]), 9, Color(0.55, 0.86, 0.6, 0.9), cw - 16.0)
		_ctr(f_exo, cx + cw * 0.5, cy + 186.0, "• " + String(perks[1]), 9, Color(0.55, 0.86, 0.6, 0.9), cw - 16.0)
		if sel:
			_ctr(f_orb_b, cx + cw * 0.5, cy + 218.0, "✓ SELECTED", 9, Color(1.0, 0.82, 0.31))
		_rects["ceo_pick_" + str(ci)] = Rect2(cx, cy, cw, ch)
	# BACK / CONTINUE.
	_title_btn(Rect2(40.0, H - 50.0, 90.0, 28.0), "← BACK", Color(0.08, 0.14, 0.28, 0.85), Color(0.4, 0.55, 0.8, 0.6), Color(0.7, 0.82, 1.0), "back_title")
	_title_btn(Rect2(W - 240.0, H - 50.0, 200.0, 28.0), "CONTINUE →", Color(0.086, 0.424, 0.204, 0.92), Color(0.275, 0.706, 0.392, 0.8), Color(0.7, 1.0, 0.78), "to_aiselect")

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


# ── SELECT OPPONENT (build_game.py drawAISelect) ────────────────────────────
func _draw_aiselect() -> void:
	_ctr(f_orb_b, W * 0.5, 70.0, "SELECT YOUR OPPONENT", 18, Color(1.0, 0.82, 0.31))
	# Corp name banner.
	var fr := Rect2(W * 0.5 - 240.0, 96.0, 480.0, 30.0)
	_round_rect(fr, 4.0, Color(0.039, 0.078, 0.196, 0.85))
	draw_rect(fr, Color(0.314, 0.588, 1.0, 0.45), false, 1.0)
	_ctr(f_exo, W * 0.5, 116.0, GameState.corp_name, 11, Color(0.6, 0.76, 1.0, 0.85))
	# 6 difficulty cards.
	var cw := 122.0
	var gap := 8.0
	var total := 6 * cw + 5 * gap
	var x0 := (W - total) * 0.5
	var cy := 150.0
	var ch := 130.0
	for i in _DIFFS.size():
		var d: Array = _DIFFS[i]
		var cx := x0 + i * (cw + gap)
		var sel := String(d[0]) == _ai_choice
		var col := Color.from_string(String(d[3]), Color.WHITE)
		var dhov := _hov(Rect2(cx, cy, cw, ch)) and not sel
		_round_rect(Rect2(cx, cy, cw, ch), 6.0, Color(0.078, 0.157, 0.314, 0.85) if sel else (Color(0.059, 0.122, 0.275, 0.85) if dhov else Color(0.039, 0.086, 0.196, 0.7)))
		draw_rect(Rect2(cx, cy, cw, ch), col if sel else (Color(col.r, col.g, col.b, 0.6) if dhov else Color(0.196, 0.314, 0.549, 0.4)), false, 2.0 if sel else 1.0)
		# Mini train/engine icon as the card art.
		if view and view.get("_trains"):
			view._trains.draw_car_strip(self, Rect2(cx + 10.0, cy + 14.0, cw - 20.0, 40.0), [_diff_car(i)], [true])
		_ctr(f_orb_b, cx + cw * 0.5, cy + 78.0, String(d[1]), 11, col)
		draw_string(f_exo, Vector2(cx + 8.0, cy + 94.0), String(d[2]), HORIZONTAL_ALIGNMENT_CENTER, cw - 16.0, 8, Color(0.6, 0.72, 0.92, 0.7))
		if sel:
			_ctr(f_orb_b, cx + cw * 0.5, cy + 122.0, "✓", 12, col)
		_rects["diff_" + String(d[0])] = Rect2(cx, cy, cw, ch)
	# BACK / START GAME.
	_title_btn(Rect2(40.0, H - 56.0, 90.0, 28.0), "← BACK", Color(0.08, 0.14, 0.28, 0.85), Color(0.4, 0.55, 0.8, 0.6), Color(0.7, 0.82, 1.0), "back_corp")
	_title_btn(Rect2(W - 240.0, H - 56.0, 200.0, 28.0), "START GAME →", Color(0.086, 0.424, 0.204, 0.92), Color(0.275, 0.706, 0.392, 0.85), Color(0.7, 1.0, 0.78), "start_game")


func _diff_car(i: int) -> String:
	return ["engine_constellation", "car_livestock", "car_water_tank", "car_ore", "car_iron", "car_hazmat"][i]


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

func _hov(r: Rect2) -> bool:
	return r.has_point(_mouse)

func _on_click(key: String) -> void:
	Audio.play("button")
	match key:
		"play":
			_intro_para = 0; _intro_chars = 0.0; GameState.set_screen("intro")
		"intro_skip": _finish_intro()
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
				GameState.ceo_name = String(ceo.name)
				GameState.ceo_revenue_mult = (ceo.mult as Dictionary).duplicate()
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
