extends Node2D
## GalaxyView2D — faithful 2D galaxy renderer + camera.
##
## The JS world↔screen map (build_game.py:3967) is a plain affine. Rather than
## carry it on a node Transform2D, each draw layer computes `w2s` per body and
## draws in SCREEN space — this mirrors the JS `[sx,sy]=w2s(p.x,p.y)` draw loops
## line-for-line, keeps fonts crisp, and makes per-body screen-radius culling
## identical to the JS. Picking is point-in-radius via `_s2w` (build_game.py §8).
##
## M0: camera + picking (placeholder dots).
## M1: real layered bodies — ScreenBackground (bg/nebula/parallax) → GalaxyContent
##     (stars, black holes, orbit rings, planets) → Labels (screen-space names).
##     Fog-of-war overlay is a separate follow-up task.

const ScreenBackground := preload("res://world/ScreenBackground.gd")
const GalaxyContent := preload("res://world/GalaxyContent.gd")
const TrainsLayer := preload("res://world/TrainsLayer.gd")
const Labels := preload("res://world/Labels.gd")
const FogLayer := preload("res://world/FogLayer.gd")

# --- Camera state (the JS `cam = {x,y,scale}`) ---
var cam := Vector2.ZERO
var sc: float = Tuning.MIN_SC
var star_pan := Vector2.ZERO

# --- Drag state ---
var _dragging := false
var _drag_last := Vector2.ZERO
var _drag_moved := false

# --- Camera tracking (build_game.py: starts at MAX_SC following the player's
# train; any manual pan releases it, mirroring `tracking`/`trackingOffset`). ---
var tracking := false
var _track_idx := 0

# --- Shared radial-alpha glow texture (white core → transparent edge) ---
var glow_tex: Texture2D

# --- Draw layers (screen-space; ordered back→front) ---
var _bg: Node2D
var _content: Node2D
var _trains: Node2D
var _labels: Node2D
var _fog: Node2D


func _ready() -> void:
	# Crisp glow upscale: linear + mipmaps so big star coronas don't pixelate.
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	glow_tex = _make_glow_texture(256)
	# M0/M1 bootstrap: ensure there's a generated galaxy to look at and click.
	if Galaxy.stars.is_empty():
		Galaxy.generate(12345)
		GameState.start_new_game()
		Missions.start_new_game()  # so the mission tracker has an active objective
		Discovery.init_for_new_game()
	# M3 bootstrap: a demo player consist so trains are visible until the build
	# UI exists. Routes Orijen ⇄ a passenger-demanding home planet so it moves.
	if Transit.trains.is_empty():
		var t := Transit.build_train(Galaxy.origen_id, "engine_galaxy", ["car_passenger", "car_passenger", "car_passenger", "caboose"], true)
		var home: Dictionary = Galaxy.stars[Galaxy.home_star_id]
		Galaxy.planets[Galaxy.origen_id].hasStation = true  # demo: stations so cargo ops run
		Galaxy.planets[Galaxy.origen_id].supply["passengers"] = 12.0  # demo: ensure visible loading
		for pid in home.planetIds:
			if int(pid) != Galaxy.origen_id and (Galaxy.planets[pid].get("demandRate", {}) as Dictionary).has("passengers"):
				Galaxy.planets[pid].hasStation = true
				Transit.assign_route(t, [Galaxy.origen_id, int(pid)])
				break
	# Layers (drawn in child order: bg first, content, trains, labels last).
	_bg = ScreenBackground.new(); _bg.view = self; add_child(_bg)
	_content = GalaxyContent.new(); _content.view = self; add_child(_content)
	_trains = TrainsLayer.new(); _trains.view = self; add_child(_trains)
	_labels = Labels.new(); _labels.view = self; add_child(_labels)
	_fog = FogLayer.new(); _fog.view = self; add_child(_fog)
	# Neutral home-system overview until the player enters the galaxy via the title
	# flow (enter_galaxy()); the title screen covers the world meanwhile, and dev
	# --shot/--scale flags rely on this default framing.
	var home: Dictionary = Galaxy.stars[Galaxy.home_star_id]
	cam = Vector2(home.x, home.y)
	sc = clampf(Tuning.W / 12000.0, Tuning.MIN_SC, Tuning.MAX_SC)
	_clamp_camera()

# Entering the galaxy from the title flow (or a dev flag): start fully zoomed in
# on the player's train, tracking it (build_game.py:5535 _introToCorpSetup).
func enter_galaxy() -> void:
	# A loaded save restores its exact camera (build_game.py cam{x,y,scale}).
	if not GameState.pending_cam.is_empty():
		var pc: Dictionary = GameState.pending_cam
		cam = Vector2(float(pc.x), float(pc.y))
		sc = clampf(float(pc.scale), Tuning.MIN_SC, Tuning.MAX_SC)
		GameState.pending_cam = {}
		tracking = false
		_clamp_camera()
		return
	sc = Tuning.MAX_SC
	var pt := _player_train_idx()
	if pt >= 0:
		_track_idx = pt
		tracking = true
		var t: Dictionary = Transit.trains[pt]
		cam = Vector2(float(t.x) + GameState.panel_w() / (2.0 * sc), float(t.y))
	else:
		var hs: Dictionary = Galaxy.stars[Galaxy.home_star_id]
		cam = Vector2(hs.x, hs.y)
	_clamp_camera()

func _player_train_idx() -> int:
	for i in Transit.trains.size():
		if bool(Transit.trains[i].get("isPlayer", false)):
			return i
	return -1


func _process(delta: float) -> void:
	_handle_wasd_pan(delta)
	GameState.view_cam = {"x": cam.x, "y": cam.y, "scale": sc}  # expose for save
	# Camera follows the tracked train (engine), nudged so it sits left of the panel.
	if tracking and _track_idx >= 0 and _track_idx < Transit.trains.size():
		var t: Dictionary = Transit.trains[_track_idx]
		cam = Vector2(float(t.x) + GameState.panel_w() / (2.0 * sc), float(t.y))
		_clamp_camera()
	elif tracking:
		tracking = false
	_push_selected_screen_pos()
	_bg.queue_redraw()
	_content.queue_redraw()
	_trains.queue_redraw()
	_labels.queue_redraw()


# ── Camera transform (build_game.py:3967-3968) ───────────────────────────────
func _w2s(w: Vector2) -> Vector2:
	return Vector2((w.x - cam.x) * sc + Tuning.W * 0.5, (w.y - cam.y) * sc + Tuning.GH * 0.5)

func _s2w(s: Vector2) -> Vector2:
	return Vector2((s.x - Tuning.W * 0.5) / sc + cam.x, (s.y - Tuning.GH * 0.5) / sc + cam.y)

# clampCamera (build_game.py:3970) — asymmetric right clamp lets the galaxy scroll
# until its right edge meets the panel's left edge.
func _clamp_camera() -> void:
	var panel_w := GameState.panel_w()
	var hw := Tuning.W / (2.0 * sc)
	var hh := Tuning.GH / (2.0 * sc)
	cam.x = clampf(cam.x, -Tuning.WORLD_W + hw, Tuning.WORLD_W - hw + panel_w / sc)
	cam.y = clampf(cam.y, -Tuning.WORLD_H + hh, Tuning.WORLD_H - hh)


# ── WASD pan (build_game.py:36285) ──────────────────────────────────────────
func _handle_wasd_pan(delta: float) -> void:
	if _dragging:
		return
	var dx := 0.0
	var dy := 0.0
	if Input.is_key_pressed(KEY_A): dx -= 1.0
	if Input.is_key_pressed(KEY_D): dx += 1.0
	if Input.is_key_pressed(KEY_W): dy -= 1.0
	if Input.is_key_pressed(KEY_S): dy += 1.0
	if dx == 0.0 and dy == 0.0:
		return
	tracking = false  # manual pan takes the wheel
	if dx != 0.0 and dy != 0.0:
		dx *= 0.7071
		dy *= 0.7071
	var old := cam
	var dt_frames := delta * 60.0
	cam.x += dx * Tuning.PAN_PX_FRAME * dt_frames / sc
	cam.y += dy * Tuning.PAN_PX_FRAME * dt_frames / sc
	_clamp_camera()
	star_pan.x -= (old.x - cam.x) * sc
	star_pan.y -= (old.y - cam.y) * sc


# ── Input: wheel zoom, drag-pan, click-select ───────────────────────────────
func _unhandled_input(event: InputEvent) -> void:
	if GameState.gs != "galaxy":
		return  # front-end screens own input; the cinematic drives the camera
	if GameState.popup_active:
		return  # a modal popup is open — it owns input
	if event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).keycode
		if k == KEY_BRACKETLEFT:
			GameState.set_speed_idx(GameState.game_speed_idx - 1)
		elif k == KEY_BRACKETRIGHT:
			GameState.set_speed_idx(GameState.game_speed_idx + 1)
		elif (k == KEY_ESCAPE or k == KEY_X) and not GameState.route_stops.is_empty():
			GameState.route_stops = []  # cancel a building route
		elif k == KEY_G:
			Fog.enabled = not Fog.enabled  # toggle fog-of-war (perf/debug, like the JS [fog] toggle)
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_at(mb.position, true)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_at(mb.position, false)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				if mb.double_click:
					_dbl_at(mb.position)  # double-click → open the body's detail popup
				else:
					_dragging = true
					_drag_moved = false
					_drag_last = mb.position
			else:
				_dragging = false
				if not _drag_moved:
					_pick_at(mb.position, mb.shift_pressed)
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		var d := mm.position - _drag_last
		_drag_last = mm.position
		if d.length() > 0.0:
			_drag_moved = true
			tracking = false  # manual drag releases train-follow
		cam.x -= d.x / sc
		cam.y -= d.y / sc
		_clamp_camera()
		# build_game.py:32074 — starPan = dragStarPan - dx (MINUS): keeps the
		# background drifting the SAME way as the world during a drag.
		star_pan -= d


func _zoom_at(screen_pos: Vector2, zoom_in: bool) -> void:
	var w_before := _s2w(screen_pos)
	var factor := Tuning.ZOOM_IN_FACTOR if zoom_in else Tuning.ZOOM_OUT_FACTOR
	sc = clampf(sc * factor, Tuning.MIN_SC, Tuning.MAX_SC)
	cam.x = w_before.x - (screen_pos.x - Tuning.W * 0.5) / sc
	cam.y = w_before.y - (screen_pos.y - Tuning.GH * 0.5) / sc
	_clamp_camera()


# galaxyClick picking (build_game.py §8): trains → planets → stars → black holes.
# SHIFT+click a stationed planet appends it to the building route (multi-stop
# route construction, build_game.py:30551). Then click a train to assign.
func _pick_at(screen_pos: Vector2, shift := false) -> void:
	var w := _s2w(screen_pos)
	if shift:
		var best := -1
		var best_d := INF
		for p in Galaxy.planets:
			var d := w.distance_to(Vector2(p.x, p.y))
			# snap to the nearest planet within a generous radius (72px screen)
			if d <= maxf(float(p.radius), 72.0 / sc) and d < best_d:
				best_d = d
				best = int(p.id)
		if best >= 0 and best < Galaxy.planets.size() and bool(Galaxy.planets[best].get("hasStation", false)):
			if GameState.route_stops.is_empty() or int(GameState.route_stops[-1]) != best:
				GameState.route_stops.append(best)
				Audio.play("button")
		return
	for t in Transit.trains:
		var tr: float = max(120.0 / sc, 200.0)
		if w.distance_to(Vector2(t.x, t.y)) <= tr:
			# If a multi-stop route is being built, assign it to THIS train.
			if not GameState.route_stops.is_empty() and bool(t.isPlayer):
				var stops: Array = GameState.route_stops.duplicate()
				if stops.is_empty() or int(stops[0]) != int(t.planetId):
					stops.push_front(int(t.planetId))  # so the train starts where it is
				Player.assign_route(int(t.id), stops)
				GameState.route_stops = []
				Audio.play("button")
			GameState.select("train", "train_%d" % int(t.id), _train_name(t))
			return
	for p in Galaxy.planets:
		if w.distance_to(Vector2(p.x, p.y)) <= float(p.radius):
			GameState.select("planet", "planet_%d" % int(p.id), String(p.name))
			return
	for s in Galaxy.stars:
		if w.distance_to(Vector2(s.x, s.y)) <= float(s.radius):
			GameState.select("star", "star_%d" % int(s.id), String(s.name))
			if Discovery.is_star_revealed(int(s.id)):
				GameState.popup_requested.emit("star")  # build_game.py:32360
			return
	for b in Galaxy.black_holes:
		if w.distance_to(Vector2(b.x, b.y)) <= float(b.radius):
			GameState.select("blackhole", "blackhole", "Black Hole")
			return
	GameState.route_stops = []  # clicking empty space cancels a building route
	GameState.clear_selection()


# Double-click (build_game.py panelDblClick / galaxy dbl): a planet opens its
# detail popup, a train opens its details. Picks trains → planets (stars/black
# holes have no dbl action).
func _dbl_at(screen_pos: Vector2) -> void:
	var w := _s2w(screen_pos)
	for t in Transit.trains:
		var tr: float = max(120.0 / sc, 200.0)
		if w.distance_to(Vector2(t.x, t.y)) <= tr:
			GameState.select("train", "train_%d" % int(t.id), _train_name(t))
			GameState.popup_requested.emit("train")
			Audio.play("button")
			return
	for p in Galaxy.planets:
		if w.distance_to(Vector2(p.x, p.y)) <= float(p.radius):
			GameState.select("planet", "planet_%d" % int(p.id), String(p.name))
			GameState.popup_requested.emit("planet_detail")
			Audio.play("button")
			return

func _train_name(t: Dictionary) -> String:
	return String(t.get("name", "Train %d" % int(t.id)))


func _push_selected_screen_pos() -> void:
	if GameState.selected.is_empty():
		GameState.selected_screen_pos = Vector2.INF
		return
	var wp := selected_world_pos()
	GameState.selected_screen_pos = _w2s(wp) if wp != Vector2.INF else Vector2.INF


func selected_world_pos() -> Vector2:
	var sel: Dictionary = GameState.selected
	var id_str := String(sel.get("id", ""))
	match String(sel.get("kind", "")):
		"planet":
			var pid := int(id_str.trim_prefix("planet_"))
			for p in Galaxy.planets:
				if int(p.id) == pid: return Vector2(p.x, p.y)
		"star":
			var sid := int(id_str.trim_prefix("star_"))
			for s in Galaxy.stars:
				if int(s.id) == sid: return Vector2(s.x, s.y)
		"train":
			var tid := int(id_str.trim_prefix("train_"))
			for t in Transit.trains:
				if int(t.id) == tid: return Vector2(t.x, t.y)
	return Vector2.INF


# Build a 128px radial-alpha texture: white RGB, alpha falls off from 1 at the
# centre to 0 at the half-width edge (soft^2). Modulated by colour when drawn,
# this stands in for every Canvas2D createRadialGradient glow.
func _make_glow_texture(n: int) -> Texture2D:
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var half := n * 0.5
	for y in n:
		for x in n:
			var d := Vector2(x + 0.5 - half, y + 0.5 - half).length() / half
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = a * a  # softer falloff
			img.set_pixel(x, y, Color(1, 1, 1, a))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
