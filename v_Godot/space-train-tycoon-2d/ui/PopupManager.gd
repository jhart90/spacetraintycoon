extends Control
## PopupManager — the modal popup system (build_game.py §10/§17). Owns the single
## active popup + its state, opened via GameState.popup_requested + hotkeys, closed
## on X/Escape or clicking outside. Draws a shared base (drawPopupBase:16395) then
## the active popup. Immediate-mode in logical 900×500.
##
## M5 (this pass): the framework + OPTIONS (CONTROLS button, SFX/Music sliders →
## Audio, mutes) + CONTROLS reference. TrainBuilder/PlanetDetail/Routes/Stations/
## Finances/Registry are follow-ups (each is its own _draw + hit-rects).

const W := 900.0
const H := 500.0

var active := ""
var state: Dictionary = {}
var _drag := ""          # slider currently being dragged ("sfx"|"music"|"")
var _event_queue: Array = []  # queued event-popup states (gold/diamond etc.) shown one-at-a-time
var view: Node2D         # GalaxyView2D (for consist sprite strips)

# Train builder state.
const _ENGINES := ["engine_constellation", "engine_galaxy", "engine_classJ", "engine_classR", "engine_N700"]
var tb_engine := "engine_constellation"
var tb_cars: Array = []

var f_exo: Font
var f_orb: Font
var f_orb_b: Font

# hit-rects registered during _draw, consumed by input.
var _rects: Dictionary = {}
# Live cursor pos (logical 900×500), updated on mouse-motion → drives hover states.
var _mouse := Vector2(-1, -1)

# Finances popup state (build_game.py _financeBreakdown / _financeScrollY).
var _fin_breakdown := "stardate"
var _fin_dd_open := false
var _fin_scroll := 0.0
# Registry / Pokedex state (build_game.py pokedexDiscoveredOnly / starRegistryVisitedOnly).
var _reg_visited_only := false
var _reg_scroll := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	f_exo = load("res://assets/fonts/Exo2-Variable.woff2")
	f_orb = load("res://assets/fonts/Orbitron-Variable.woff2")
	var fv := FontVariation.new()
	fv.base_font = f_orb
	fv.variation_opentype = {"wght": 700}
	f_orb_b = fv
	GameState.popup_requested.connect(_on_popup_requested)
	Leaderboard.changed.connect(func(): if active == "leaderboard": queue_redraw())
	# Auto event popups (build_game.py new_mission etc.). Connected after the
	# bootstrap mission fires, so the first mission doesn't cover the screen.
	Missions.mission_introduced.connect(_on_mission_intro)
	GameState.engine_unlocked.connect(func(id: String): _open_unlock("NEW ENGINE UNLOCKED", _disp_name(id), id, true))
	GameState.car_unlocked.connect(func(id: String): _open_unlock("NEW CAR UNLOCKED", _disp_name(id), id, false))
	Missions.mission_completed.connect(_on_mission_completed)
	GameState.first_delivery.connect(_on_first_delivery)
	Discovery.star_revealed.connect(func(sid: int): _open_event("STAR DISCOVERED", String(Galaxy.stars[sid].name), "Added to the Star Registry [Y]."))
	Discovery.gold_discovered.connect(func(pid: int): _present_event({"kind": "gold", "planet_id": pid}))
	Discovery.diamond_discovered.connect(func(pid: int): _present_event({"kind": "diamond", "planet_id": pid}))
	GameState.upgrade_unlocked.connect(func(uid: String): _present_event({"kind": "upgrade", "upgrade": uid}))

func _disp_name(id: String) -> String:
	return String(_TT_NAMES.get(id, id.trim_prefix("engine_").trim_prefix("car_").to_upper().replace("_", " ")))

func _open_unlock(label: String, disp: String, sprite: String, is_engine: bool) -> void:
	if active != "":
		return
	_open("event")
	state = {"kind": "unlock", "label": label, "name": disp, "sprite": sprite, "is_engine": is_engine}

func _on_mission_completed(id: String, reward: int) -> void:
	if active != "" or reward <= 0:
		return
	var def: Dictionary = Missions.def_for(id)
	_open("event")
	state = {"kind": "reward", "name": String(def.get("name", "Mission complete")), "reward": reward}

func _open_event(title: String, head: String, body: String) -> void:
	if active != "":
		return  # don't cover an open popup
	_open("event")
	state = {"title": title, "head": head, "body": body}

func _on_mission_intro(id: String) -> void:
	if active != "":
		return
	_open("event")
	state = {"kind": "new_mission", "id": id}

func _on_popup_requested(name: String) -> void:
	_open(name)

func _open(name: String) -> void:
	active = name
	state = {}
	_drag = ""
	if name == "trainbuilder":
		tb_engine = "engine_constellation"
		tb_cars = []
	if name == "leaderboard":
		Leaderboard.fetch_top(Leaderboard.metric if Leaderboard.metric != "" else "corp_value")
	GameState.popup_active = true  # HUD/galaxy skip input while modal
	queue_redraw()

func _close() -> void:
	active = ""
	_drag = ""
	GameState.popup_active = false
	Audio.play("button")
	queue_redraw()

func _toggle(name: String) -> void:
	if active == name:
		_close()
	else:
		_open(name)
		Audio.play("button")


# ── Input ───────────────────────────────────────────────────────────────────
# Keys are global (popups open/close); mouse is modal (only when a popup captures
# it via mouse_filter=STOP → _gui_input, in logical 900×500 coords).
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).keycode
		if (k == KEY_ESCAPE or k == KEY_X) and active != "":
			if active == "event":
				_dismiss_event()
			else:
				_close()
			get_viewport().set_input_as_handled(); return
		if GameState.gs != "galaxy":
			return  # popups are galaxy-only; the front-end owns input otherwise
		var map := {KEY_O: "options", KEY_T: "trains", KEY_R: "routes", KEY_U: "stations", KEY_Y: "registry", KEY_P: "pokedex", KEY_F: "finances", KEY_M: "missions", KEY_L: "leaderboard", KEY_I: "techtree"}
		if map.has(k):
			_toggle(map[k]); get_viewport().set_input_as_handled()
		elif k == KEY_C and (active == "" or active == "options"):
			_toggle("controls"); get_viewport().set_input_as_handled()

# Global _input (a CanvasLayer-parented Control gets no rect, so _gui_input never
# fires). Modal: while a popup is open we consume mouse events so the HUD/galaxy
# (which gate on GameState.popup_active) don't also react.
func _input(event: InputEvent) -> void:
	if active == "":
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_on_click(mb.position)
			else:
				_drag = ""
		elif mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			var dir := -1.0 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0
			if active == "registry" or active == "pokedex":
				_reg_scroll = maxf(0.0, _reg_scroll + dir * 40.0); queue_redraw()
			elif active == "finances":
				_fin_scroll = maxf(0.0, _fin_scroll + dir * 36.0); queue_redraw()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _drag != "":
			_drag_slider(mm.position)
			get_viewport().set_input_as_handled()
		else:
			_mouse = mm.position
			# Pointing-hand cursor over any registered clickable (matches the JS
			# canvas.style.cursor='pointer' behavior).
			var over := false
			for k in _rects.keys():
				if k != "_panel" and (_rects[k] as Rect2).has_point(_mouse):
					over = true
					break
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if over else Control.CURSOR_ARROW
			queue_redraw()  # repaint so hover states update

# True when the cursor is inside r — every draw helper uses this to pick its
# hovered visual state (the port previously had NO hover states at all).
func _hov(r: Rect2) -> bool:
	return r.has_point(_mouse)

func _on_click(p: Vector2) -> void:
	# Close if outside the panel.
	var panel: Rect2 = _rects.get("_panel", Rect2())
	if panel.size != Vector2.ZERO and not panel.has_point(p):
		_close()
		return
	if _rects.has("esc") and (_rects["esc"] as Rect2).has_point(p):
		_close(); return
	if active == "options":
		if _hit("ctl", p):
			_open("controls"); Audio.play("button"); return
		if _hit("opt_fs", p):
			var fm := DisplayServer.window_get_mode()
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fm == DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN)
			Audio.play("button"); queue_redraw(); return
		if _hit("opt_autosave", p):
			GameState.autosave_enabled = not GameState.autosave_enabled; Audio.play("button"); queue_redraw(); return
		if _hit("opt_tracker", p):
			GameState.mission_tracker_enabled = not GameState.mission_tracker_enabled; Audio.play("button"); queue_redraw(); return
		if _hit("sfx_mute", p):
			Audio.set_sfx_muted(not Audio.sfx_muted); Audio.play("button"); return
		if _hit("music_mute", p):
			Audio.music_vol = 0.0 if Audio.music_vol > 0.0 else 0.5
			Audio._apply_volume(); Audio.play("button"); return
		if _on_slider("sfx", p):
			_drag = "sfx"; _drag_slider(p); return
		if _on_slider("music", p):
			_drag = "music"; _drag_slider(p); return
		if _hit("savemgr", p):
			state["save_msg"] = ""; _open("savemanager"); Audio.play("button"); return
		if _hit("quit_title", p):
			_open("quitconfirm"); Audio.play("button"); return
	elif active == "quitconfirm":
		if _hit("quit_yes", p):
			_close(); GameState.set_screen("title"); Audio.play("button"); return
		if _hit("quit_save", p):
			SaveLoad.save_game(); Audio.play("button"); return
		if _hit("quit_no", p):
			_close(); Audio.play("button"); return
	elif active == "savemanager":
		if _hit("sg_new", p):
			state["save_msg"] = "Saved." if SaveLoad.save_to_new_slot() else "Save failed."
			Audio.play("button"); queue_redraw(); return
		if _hit("sg_back", p):
			_open("options"); Audio.play("button"); return
		var saves := SaveLoad.list_saves()
		for i in saves.size():
			if _hit("sgload_%d" % i, p):
				if SaveLoad.load_game(String(saves[i].path)):
					Audio.play("button"); _close(); return
				state["save_msg"] = "Load failed."; queue_redraw(); return
			if _hit("sgdel_%d" % i, p):
				SaveLoad.delete_save(String(saves[i].path))
				state["save_msg"] = "Deleted."; Audio.play("button"); queue_redraw(); return
	elif active == "controls":
		if _hit("back", p):
			_open("options"); Audio.play("button"); return
	elif active == "finances":
		if _fin_dd_open:
			for ka in _FIN_BD_KEYS:
				if _hit("fin_opt_%s" % ka, p):
					_fin_breakdown = ka; _fin_scroll = 0.0; _fin_dd_open = false; Audio.play("button"); queue_redraw(); return
			_fin_dd_open = false; queue_redraw(); return
		if _hit("fin_dd", p):
			_fin_dd_open = true; Audio.play("button"); queue_redraw(); return
	elif active == "leaderboard":
		for md in Leaderboard.METRICS:
			if _hit("lbhdr_%s" % String(md.col), p):
				if Leaderboard.metric != String(md.col):
					Leaderboard.fetch_top(String(md.col))
				Audio.play("button"); return
		if _hit("lb_prev", p):
			if Leaderboard.page > 0:
				Leaderboard.page -= 1; queue_redraw()
			Audio.play("button"); return
		if _hit("lb_next", p):
			if Leaderboard.page < Leaderboard.max_page():
				Leaderboard.page += 1; queue_redraw()
			Audio.play("button"); return
	elif active == "planet_detail":
		var pid := _pd_pid()
		if pid >= 0:
			if _hit("pdtab_station", p):
				state["planetTab"] = "station"; Audio.play("button"); queue_redraw(); return
			if _hit("pdtab_stats", p):
				state["planetTab"] = "stats"; Audio.play("button"); queue_redraw(); return
			if _hit("build_station", p):
				Player.build_station(pid); return
			for k in _rects.keys():
				if String(k).begins_with("upgrade_") and _hit(String(k), p):
					Player.build_upgrade(pid, String(k).trim_prefix("upgrade_")); return
	elif active == "trains" or active == "routes" or active == "stations":
		# Tab switching.
		for tab in ["trains", "routes", "stations"]:
			if _hit("wintab_" + tab, p):
				_open(tab); Audio.play("button"); return
		if _hit("win_new", p):
			if active == "stations":
				return
			_open("trainbuilder"); Audio.play("button"); return
		for k in _rects.keys():
			if String(k).begins_with("winstop_") and _hit(String(k), p):
				var stpid := int(String(k).trim_prefix("winstop_"))
				GameState.select("planet", "planet_%d" % stpid, String(_planet_by_id(stpid).get("name", "?")))
				_open("planet_detail"); Audio.play("button"); return
			if String(k).begins_with("winrow_train_") and _hit(String(k), p):
				_open("train"); state["trainIdx"] = int(String(k).trim_prefix("winrow_train_")); Audio.play("button"); return
			if String(k).begins_with("winrow_station_") and _hit(String(k), p):
				var spid := int(String(k).trim_prefix("winrow_station_"))
				GameState.select("planet", "planet_%d" % spid, String(_planet_by_id(spid).get("name", "?")))
				_open("planet_detail"); Audio.play("button"); return
	elif active == "techtree":
		_close(); return
	elif active == "corp":
		if _hit("corp_ceo_portrait", p):
			_open("ceohire"); Audio.play("button"); return
	elif active == "ceohire":
		for k in _rects.keys():
			if String(k).begins_with("hire_") and _hit(String(k), p):
				GameState.hire_ceo(int(String(k).trim_prefix("hire_"))); Audio.play("button"); queue_redraw(); return
	elif active == "registry" or active == "pokedex":
		if _hit("regtab_planets", p):
			_reg_scroll = 0.0; _open("pokedex"); Audio.play("button"); return
		if _hit("regtab_stars", p):
			_reg_scroll = 0.0; _open("registry"); Audio.play("button"); return
		if _hit("reg_visited", p):
			_reg_visited_only = not _reg_visited_only; _reg_scroll = 0.0; Audio.play("button"); queue_redraw(); return
	elif active == "star":
		for k in _rects.keys():
			if String(k).begins_with("starplanet_") and _hit(String(k), p):
				var ppid := int(String(k).trim_prefix("starplanet_"))
				GameState.select("planet", "planet_%d" % ppid, String(_planet_by_id(ppid).get("name", "?")))
				_open("planet_detail"); Audio.play("button"); return
	elif active == "train":
		if _hit("td_edit", p):
			_open("trainbuilder"); Audio.play("button"); return
	elif active == "event":
		_dismiss_event()  # any click dismisses; show next queued event if any
	elif active == "trainbuilder":
		for k in _rects.keys():
			if String(k).begins_with("eng_") and _hit(String(k), p):
				tb_engine = String(k).trim_prefix("eng_"); Audio.play("button"); return
			if String(k).begins_with("addcar_") and _hit(String(k), p):
				tb_cars.append(String(k).trim_prefix("addcar_")); Audio.play("button"); return
		if _hit("tb_remove_last", p) and not tb_cars.is_empty():
			tb_cars.pop_back(); Audio.play("button"); return
		if _hit("tb_cancel", p):
			_close(); return
		if _hit("tb_build", p):
			var bp := _build_planet()
			if not bp.is_empty() and not tb_cars.is_empty():
				if not Player.build_train(int(bp.id), tb_engine, tb_cars.duplicate()).is_empty():
					_close()
			return

func _hit(key: String, p: Vector2) -> bool:
	return _rects.has(key) and (_rects[key] as Rect2).has_point(p)

func _on_slider(key: String, p: Vector2) -> bool:
	if not _rects.has(key):
		return false
	var r: Rect2 = _rects[key]
	return p.x >= r.position.x - 8 and p.x <= r.position.x + r.size.x + 8 and p.y >= r.position.y - 8 and p.y <= r.position.y + r.size.y + 8

func _drag_slider(p: Vector2) -> void:
	if _drag == "" or not _rects.has(_drag):
		return
	var r: Rect2 = _rects[_drag]
	var v := clampf((p.x - r.position.x) / r.size.x, 0.0, 1.0)
	if _drag == "sfx":
		Audio.set_sfx_volume(v)
	else:
		Audio.music_vol = v
		Audio._apply_volume()
	queue_redraw()


# ── Draw ────────────────────────────────────────────────────────────────────
func _draw() -> void:
	_rects.clear()
	if active == "":
		return
	# Dim the world for focus (the JS popup is opaque; a faint dim reads cleaner).
	draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, 0.45))
	match active:
		"options": _draw_options()
		"controls": _draw_controls()
		"planet_detail": _draw_planet_detail()
		"trainbuilder": _draw_trainbuilder()
		"trains": _draw_window("trains")
		"routes": _draw_window("routes")
		"stations": _draw_window("stations")
		"train": _draw_train_detail()
		"missions": _draw_missions()
		"leaderboard": _draw_leaderboard()
		"star": _draw_star_popup()
		"quitconfirm": _draw_quitconfirm()
		"registry": _draw_registry()
		"pokedex": _draw_pokedex()
		"techtree": _draw_tech_tree()
		"corp": _draw_corp()
		"ceohire": _draw_ceohire()
		"finances": _draw_finances()
		"savemanager": _draw_savemanager()
		"event": _draw_event()

# Rounded-rect helpers (the original's drawPopupBase / buttons all use roundRect).
func _fill_round(r: Rect2, rad: float, col: Color) -> void:
	rad = minf(rad, minf(r.size.x, r.size.y) * 0.5)
	draw_rect(Rect2(r.position.x + rad, r.position.y, r.size.x - 2.0 * rad, r.size.y), col)
	draw_rect(Rect2(r.position.x, r.position.y + rad, r.size.x, r.size.y - 2.0 * rad), col)
	draw_circle(r.position + Vector2(rad, rad), rad, col)
	draw_circle(r.position + Vector2(r.size.x - rad, rad), rad, col)
	draw_circle(r.position + Vector2(rad, r.size.y - rad), rad, col)
	draw_circle(r.position + Vector2(r.size.x - rad, r.size.y - rad), rad, col)

func _stroke_round(r: Rect2, rad: float, col: Color, w: float) -> void:
	rad = minf(rad, minf(r.size.x, r.size.y) * 0.5)
	var p := r.position
	var s := r.size
	draw_line(Vector2(p.x + rad, p.y), Vector2(p.x + s.x - rad, p.y), col, w)
	draw_line(Vector2(p.x + rad, p.y + s.y), Vector2(p.x + s.x - rad, p.y + s.y), col, w)
	draw_line(Vector2(p.x, p.y + rad), Vector2(p.x, p.y + s.y - rad), col, w)
	draw_line(Vector2(p.x + s.x, p.y + rad), Vector2(p.x + s.x, p.y + s.y - rad), col, w)
	draw_arc(p + Vector2(rad, rad), rad, PI, PI * 1.5, 7, col, w)
	draw_arc(p + Vector2(s.x - rad, rad), rad, PI * 1.5, TAU, 7, col, w)
	draw_arc(p + Vector2(rad, s.y - rad), rad, PI * 0.5, PI, 7, col, w)
	draw_arc(p + Vector2(s.x - rad, s.y - rad), rad, 0.0, PI * 0.5, 7, col, w)

func _base(pw: float, ph: float, border: Color) -> Vector2:
	var px := (W - pw) * 0.5
	var py := (H - ph) * 0.5
	_rects["_panel"] = Rect2(px, py, pw, ph)
	_fill_round(Rect2(px, py, pw, ph), 8.0, Color(0.012, 0.024, 0.078, 0.98))
	_stroke_round(Rect2(px, py, pw, ph), 8.0, border, 2.0)
	return Vector2(px, py)

func _esc_hint(px: float, py: float, pw: float) -> void:
	var txt := "[ESC] close"
	var tw := f_exo.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	var ex := px + pw - 10 - tw
	var r := Rect2(ex - 2, py + 4, tw + 6, 14)
	_rects["esc"] = r
	draw_string(f_exo, Vector2(ex, py + 15), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.92) if _hov(r) else Color(0.353, 0.51, 0.745, 0.6))


func _draw_options() -> void:
	var pw := 300.0
	var ph := 452.0
	var o := _base(pw, ph, Color(0.314, 0.627, 1.0, 0.7))
	var px := o.x
	var py := o.y
	_ctr(f_orb_b, px + pw * 0.5, py + 21, "OPTIONS", 11, Color(0.267, 0.667, 1.0))
	_esc_hint(px, py, pw)
	draw_line(Vector2(px, py + 28), Vector2(px + pw, py + 28), Color(0.157, 0.353, 0.706, 0.35), 1.0)
	# CONTROLS / HOW TO PLAY button.
	var cx := px + 18
	var cw := pw - 36
	_btn(cx, py + 40, cw, 28, "CONTROLS / HOW TO PLAY", Color(0.078, 0.235, 0.588, 0.92), Color(0.667, 0.863, 1.0, 0.95))
	_rects["ctl"] = Rect2(cx, py + 40, cw, 28)
	# Toggle rows (build_game.py 22210-22266): Fullscreen / Autosave / Mission Tracker.
	var fs_on := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	_opt_toggle(px, pw, py + 92, "Fullscreen", "", fs_on, "opt_fs")
	_opt_toggle(px, pw, py + 124, "Autosave", "Prompts a game save once per stardate", GameState.autosave_enabled, "opt_autosave")
	_opt_toggle(px, pw, py + 166, "Mission Objectives Tracker", "Floating list of active missions (upper-left)", GameState.mission_tracker_enabled, "opt_tracker")
	# SOUND EFFECTS + MUSIC panes.
	_audio_pane(px, py + 212, pw, "SOUND EFFECTS", "sfx", Audio.sfx_vol, Audio.sfx_muted, Color(0.314, 0.784, 1.0))
	_audio_pane(px, py + 286, pw, "MUSIC", "music", Audio.music_vol, Audio.music_vol <= 0.0, Color(0.706, 0.471, 1.0))
	# SAVE / LOAD GAME button.
	var sgy := py + ph - 72.0
	_btn(px + 18, sgy, pw - 36, 28, "SAVE / LOAD GAME", Color(0.078, 0.235, 0.588, 0.92), Color(0.667, 0.863, 1.0, 0.95))
	_rects["savemgr"] = Rect2(px + 18, sgy, pw - 36, 28)
	# QUIT TO TITLE.
	var qy := py + ph - 38.0
	_btn(px + 18, qy, pw - 36, 28, "QUIT TO TITLE", Color(0.392, 0.110, 0.110, 0.85), Color(1.0, 0.72, 0.66, 0.95))
	_rects["quit_title"] = Rect2(px + 18, qy, pw - 36, 28)

# Options toggle row: label (+ optional subtitle) with a right-aligned ON/OFF pill.
func _opt_toggle(px: float, pw: float, y: float, label: String, subtitle: String, on: bool, key: String) -> void:
	draw_string(f_exo, Vector2(px + 18, y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.627, 0.784, 1.0, 0.9))
	if subtitle != "":
		draw_string(f_exo, Vector2(px + 18, y + 15.0), subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.392, 0.510, 0.706, 0.6))
	var tw := 48.0
	var th := 22.0
	var tx := px + pw - 18.0 - tw
	var tt := y - 16.0
	var r := Rect2(tx, tt, tw, th)
	var hov := _hov(r)
	if on:
		draw_rect(r, Color(0.176, 0.784, 0.353, 0.97) if hov else Color(0.118, 0.627, 0.275, 0.85))
		draw_rect(r, Color(0.196, 0.863, 0.353, 0.7), false, 1.0)
	else:
		draw_rect(r, Color(0.275, 0.275, 0.412, 0.9) if hov else Color(0.196, 0.196, 0.294, 0.75))
		draw_rect(r, Color(0.392, 0.392, 0.569, 0.6), false, 1.0)
	_ctr(f_orb_b, tx + tw * 0.5, tt + th * 0.5 + 4.0, "ON" if on else "OFF", 9, Color.WHITE, tw)
	_rects[key] = r

func _audio_pane(px: float, y: float, pw: float, label: String, key: String, val: float, muted: bool, accent: Color) -> void:
	draw_string(f_orb_b, Vector2(px + 18, y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.627, 0.784, 1.0, 0.9))
	# Mute toggle (right).
	var mw := 48.0
	var mx := px + pw - 18 - mw
	var mlabel := "MUTED" if muted else "ON"
	var mcol := Color(0.8, 0.3, 0.3, 0.9) if muted else Color(0.3, 0.7, 0.45, 0.9)
	_btn(mx, y - 14, mw, 18, mlabel, Color(0.08, 0.14, 0.28, 0.9), mcol, 8)
	_rects[key + "_mute"] = Rect2(mx, y - 14, mw, 18)
	# Slider.
	var sx := px + 18
	var sw := pw - 36 - 30
	var smid := y + 22
	var sh := 6.0
	draw_rect(Rect2(sx, smid - sh * 0.5, sw, sh), Color(0, 0, 0, 0.82))
	if not muted:
		var a := accent
		draw_rect(Rect2(sx, smid - sh * 0.5, maxf(2.0, sw * val), sh), a)
	draw_rect(Rect2(sx, smid - sh * 0.5, sw, sh), Color(0.314, 0.549, 0.824, 0.55), false, 1.0)
	var hx := sx + sw * clampf(val, 0.0, 1.0)
	draw_circle(Vector2(hx, smid), 5.5, Color(0.741, 0.902, 1.0))
	draw_string(f_orb_b, Vector2(sx + sw + 6, smid + 4), str(int(round(val * 100.0))), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.667, 0.824, 0.961, 0.92))
	_rects[key] = Rect2(sx, smid - 8, sw, 16)


# Faithful to build_game.py drawControlsPopup (620×300, 4 columns).
const _CTL_TITLES := ["REPEATING ROUTES", "BUY / EDIT TRAINS", "UPGRADE PLANETS", "CAMERA & SPEED"]
const _CTL_BULLETS := [
	["CLICK a PLANET to set the start", "SHIFT+CLICK more planets to add stops", "\"ASSIGN TO TRAIN\" then pick a train"],
	["Press \"T\" to open the Trains panel", "Click \"+\" to buy a new train", "Double-click a train to edit its cars"],
	["Double-click a planet for details", "Build a STATION, then add UPGRADES", "Load and Unload cargo from/to a planet to boost it's DEVELOPMENT LEVEL & cargo output"],
	["ZOOM IN/OUT with the Mouse Wheel or Arrow Keys", "PAN THE CAMERA by clicking & dragging or by using the W/A/S/D keys", "Adjust GAME SPEED with +/- keys, or SPACE to pause"],
]

func _draw_controls() -> void:
	var pw := 620.0
	var ph := 300.0
	var o := _base(pw, ph, Color(0.314, 0.627, 1.0, 0.7))
	var px := o.x
	var py := o.y
	_ctr(f_orb_b, px + pw * 0.5, py + 24.0, "CONTROLS / HOW TO PLAY", 13, Color(0.467, 0.867, 1.0))
	_esc_hint(px, py, pw)
	draw_line(Vector2(px, py + 34.0), Vector2(px + pw, py + 34.0), Color(0.157, 0.353, 0.706, 0.35), 1.0)
	var colw := floorf((pw - 32.0) / 4.0)
	var col_start_y := py + 74.0
	for ci in 4:
		var cx := px + 16.0 + ci * colw
		draw_string(f_orb_b, Vector2(cx, col_start_y), _CTL_TITLES[ci], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.588, 0.784, 1.0, 0.92))
		var ulw := minf(f_orb_b.get_string_size(_CTL_TITLES[ci], HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x, colw - 12.0)
		draw_line(Vector2(cx, col_start_y + 5.0), Vector2(cx + ulw, col_start_y + 5.0), Color(0.314, 0.627, 1.0, 0.45), 1.0)
		var by := col_start_y + 24.0
		for bullet in _CTL_BULLETS[ci]:
			var wrapped := _wrap_text("• " + String(bullet), f_exo, 11, colw - 12.0)
			for li in wrapped.size():
				draw_string(f_exo, Vector2(cx + (0.0 if li == 0 else 8.0), by), String(wrapped[li]), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.667, 0.824, 0.941, 0.82))
				by += 14.0
			by += 8.0
	# Back-to-Options button (the original's [ESC] returns to Options).
	var bw := 90.0
	var bx := px + pw * 0.5 - bw * 0.5
	var bb := py + ph - 34.0
	_btn(bx, bb, bw, 24.0, "BACK", Color(0.078, 0.235, 0.588, 0.92), Color(0.667, 0.863, 1.0, 0.95))
	_rects["back"] = Rect2(bx, bb, bw, 24.0)


# ── PlanetDetail (build_game.py drawPlanetDetailPopup §15) — supply/demand +
#    Build Station / upgrades wired to Player actions. ────────────────────────
func _pd_pid() -> int:
	var sel: Dictionary = GameState.selected
	if String(sel.get("kind", "")) != "planet":
		return -1
	return int(String(sel.get("id", "")).trim_prefix("planet_"))

func _planet_by_id(pid: int) -> Dictionary:
	if pid >= 0 and pid < Galaxy.planets.size() and int(Galaxy.planets[pid].id) == pid:
		return Galaxy.planets[pid]
	for p in Galaxy.planets:
		if int(p.id) == pid:
			return p
	return {}

const _PD_C8BC := Color(0.533, 0.733, 0.8)
const _CARGO_SHORT := {
	"passengers": "PSNGR", "livestock": "LVSTK", "mail": "MAIL", "water": "WATER",
	"ice": "ICE", "sand": "SAND", "molten_ore": "ORE", "iron": "IRON", "gold": "GOLD",
	"diamond": "DMND", "hazmat": "HAZMT", "oil": "OIL", "battery": "BATT",
	"chemical": "CHEM", "flowers": "FLWRS", "medical": "MEDCL", "grain": "GRAIN",
	"fruit": "FRUIT", "steel": "STEEL", "glass": "GLASS", "machinery": "MACH",
}

func _draw_planet_detail() -> void:
	var p := _planet_by_id(_pd_pid())
	if p.is_empty():
		return
	var pw := 470.0
	var ph := 416.0
	var o := _base(pw, ph, Color(0.314, 0.627, 1.0, 0.7))
	var px := o.x
	var py := o.y
	var ty: Dictionary = p.get("type", {})
	var hi := Color.from_string(String(ty.get("hi", "#aaccff")), Color(0.7, 0.8, 1.0))
	var pid := int(p.get("id", -1))
	var vis := Discovery.planet_tier(pid) == Discovery.Tier.VISITED or bool(p.get("aiHasStation", false))
	# Title (left) + [ESC] close.
	draw_string(f_orb_b, Vector2(px + 14.0, py + 24.0), String(p.get("name", "?")) + (" [HOME]" if bool(p.get("isStarter", false)) else ""), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, hi if vis else Color(0.314, 0.431, 0.706, 0.55))
	_esc_hint(px, py, pw)
	# Dev-level bar — 10 chevron cells.
	var dl := int(p.get("devLevel", 0))
	var n := 10
	var gp := 3.0
	var cw := (pw - 16.0 - gp * (n - 1)) / n
	for i in n:
		var cx0 := px + 8.0 + i * (cw + gp)
		var lit := i < dl
		draw_rect(Rect2(cx0, py + 38.0, cw, 8.0), Color(0.43, 0.78, 0.96, 0.92) if lit else Color(0.071, 0.141, 0.298, 0.6))
	# Planet portrait (left).
	var pr := 44.0 if String(p.get("size", "M")) == "XS" else 62.0
	var pcx := px + 76.0
	var pcy := py + 127.0
	if vis:
		var bt: Texture2D = view._content.biome_tex(String(ty.get("id", ""))) if (view and view.get("_content")) else null
		if bt != null:
			draw_texture_rect(bt, Rect2(Vector2(pcx - pr, pcy - pr), Vector2(pr * 2.0, pr * 2.0)), false)
		else:
			draw_circle(Vector2(pcx, pcy), pr, Color.from_string(String(ty.get("base", "#888888")), Color(0.5, 0.5, 0.5)))
		if bool(p.get("hasStation", false)):
			draw_arc(Vector2(pcx, pcy), pr + 6.0, 0.0, TAU, 56, Color(0.42, 0.68, 0.9, 0.55), 1.5)
	else:
		draw_circle(Vector2(pcx, pcy), pr, Color(0.016, 0.024, 0.063, 0.97))
		draw_arc(Vector2(pcx, pcy), pr, 0.0, TAU, 56, Color(0.196, 0.314, 0.549, 0.35), 1.0)
	# Detail column (right of portrait).
	var lx := px + 155.0
	var ls := py + 72.0
	if vis:
		draw_string(f_exo, Vector2(lx, ls), "BIOME:  " + String(ty.get("id", "")).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, _PD_C8BC)
		draw_string(f_exo, Vector2(lx, ls + 16.0), "SIZE:  %s  ·  RADIUS:  %d SU" % [String(p.get("size", "M")), int(p.get("radius", 0))], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, _PD_C8BC)
		var sid := int(p.get("starId", -1))
		var star: Dictionary = Galaxy.stars[sid] if sid >= 0 and sid < Galaxy.stars.size() else {}
		draw_string(f_exo, Vector2(lx, ls + 32.0), "ORBIT:  %d SU from %s" % [int(round(float(p.get("orbitRadius", 0.0)))), String(star.get("name", "?"))], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, _PD_C8BC)
		draw_string(f_exo, Vector2(lx, ls + 48.0), "POPULATION:  %s" % _fmt_cr(int(p.get("population", 0))), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, _PD_C8BC)
		draw_string(f_exo, Vector2(lx, ls + 64.0), "COORDS:  (%d, %d)" % [int(round(float(p.get("x", 0.0)) / 100.0)), int(round(float(p.get("y", 0.0)) / 100.0))], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, _PD_C8BC)
		if bool(p.get("isStarter", false)):
			draw_string(f_orb_b, Vector2(lx, ls + 84.0), "HOME WORLD", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1.0, 0.824, 0.314, 0.8))
		var cphrase := String(p.get("catchphrase", ""))
		if cphrase != "":
			draw_string(f_exo, Vector2(lx, py + 200.0), '"' + cphrase + '"', HORIZONTAL_ALIGNMENT_LEFT, pw - (lx - px) - 14.0, 9, Color(0.392, 0.549, 0.745, 0.62))
	else:
		var dimc := Color(0.235, 0.314, 0.51, 0.55)
		draw_string(f_exo, Vector2(lx, ls), "Type: ???", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, dimc)
		draw_string(f_exo, Vector2(lx, ls + 16.0), "Size: ???  ·  Radius: ???", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, dimc)
		draw_string(f_exo, Vector2(lx, ls + 32.0), "Orbit: ???", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, dimc)
		draw_string(f_exo, Vector2(lx, ls + 48.0), "Population: ???", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, dimc)
		draw_string(f_exo, Vector2(lx, ls + 64.0), "Coords: ???", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, dimc)
	# STATION / STATS tabs.
	var cur_tab := String(state.get("planetTab", "station"))
	var tab_y := py + 218.0
	_pd_tab(px, tab_y, pw * 0.5, "STATION", cur_tab == "station")
	_pd_tab(px + pw * 0.5, tab_y, pw * 0.5, "STATS", cur_tab == "stats")
	_rects["pdtab_station"] = Rect2(px, tab_y, pw * 0.5, 22.0)
	_rects["pdtab_stats"] = Rect2(px + pw * 0.5, tab_y, pw * 0.5, 22.0)
	# Tab content background.
	var tcy := py + 240.0
	draw_rect(Rect2(px + 1.0, tcy, pw - 2.0, py + ph - tcy - 1.0), Color8(6, 9, 22))
	if cur_tab == "stats":
		_pd_stats_tab(p, px, pw, tcy)
	else:
		_pd_station_tab(p, px, pw, py, ph, tcy)
	# Upgrades sidebar (left of the popup) — only for visited, stationed planets.
	if vis and bool(p.get("hasStation", false)):
		_pd_upgrades_sidebar(p, px, py, ph)

func _pd_tab(x: float, y: float, w: float, label: String, active: bool) -> void:
	var hov := _hov(Rect2(x, y, w, 22.0)) and not active
	if active:
		draw_rect(Rect2(x, y, w, 22.0), Color(0.118, 0.275, 0.627, 1.0))
		draw_rect(Rect2(x, y, w, 22.0), Color(0.314, 0.549, 1.0, 0.8), false, 1.0)
	else:
		draw_rect(Rect2(x, y, w, 22.0), Color(0.071, 0.137, 0.314, 1.0) if hov else Color(0.039, 0.078, 0.196, 1.0))
		draw_rect(Rect2(x, y, w, 22.0), Color(0.314, 0.471, 0.745, 0.7) if hov else Color(0.157, 0.275, 0.51, 0.5), false, 1.0)
	_ctr(f_orb_b, x + w * 0.5, y + 14.5, label, 9, Color(0.549, 0.784, 1.0, 0.95) if active else (Color(0.51, 0.65, 0.88, 0.9) if hov else Color(0.314, 0.471, 0.706, 0.7)))

func _pd_station_tab(p: Dictionary, px: float, pw: float, py: float, ph: float, tcy: float) -> void:
	if not bool(p.get("hasStation", false)):
		# BUILD STATION overlay centred in the content pane.
		var bw := 150.0
		var bh := 40.0
		var bx := px + (pw - bw) * 0.5
		var by := tcy + (py + ph - tcy - bh) * 0.5
		var afford := GameState.credits >= Tuning.STATION_COST
		if afford:
			var cpw := 70.0
			draw_rect(Rect2(bx + (bw - cpw) * 0.5, by - 16.0, cpw, 13.0), Color(0.431, 0.071, 0.071, 0.92))
			_ctr(f_exo, bx + bw * 0.5, by - 6.0, "-%s cr" % _fmt_cr(Tuning.STATION_COST), 8, Color.WHITE)
		_btn(bx, by, bw, bh, "BUILD STATION", Color(0.078, 0.275, 0.706, 0.94) if afford else Color(0.078, 0.078, 0.157, 0.72), Color(0.706, 0.863, 1.0, 0.97) if afford else Color(0.314, 0.314, 0.431, 0.72), 10)
		if afford:
			_rects["build_station"] = Rect2(bx, by, bw, bh)
		return
	# SUPPLY / DEMAND grid.
	draw_string(f_orb_b, Vector2(px + 10.0, tcy + 14.0), "SUPPLY", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.392, 0.667, 1.0, 0.85))
	draw_string(f_orb_b, Vector2(px + pw * 0.5 + 10.0, tcy + 14.0), "DEMAND", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1.0, 0.608, 0.275, 0.85))
	draw_line(Vector2(px + pw * 0.5, tcy + 22.0), Vector2(px + pw * 0.5, py + ph - 8.0), Color(0.196, 0.314, 0.549, 0.4), 0.8)
	var sup := _pd_sorted_cargo(p, "supply")
	var dem := _pd_sorted_cargo(p, "demand")
	# Car-icon strips per cargo (build_game.py _drawCargoStrip), capped at 3 cars.
	var row_h := 26.0
	var ry := tcy + 22.0
	for e in sup.slice(0, 5):
		var lx: float = view._trains.draw_cargo_strip(self, px + 12.0, ry, 26.0, 22.0, e[0], e[1], 3)
		draw_string(f_orb_b, Vector2(lx, ry + 16.0), "×%s" % _fmt_tenth(e[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.549, 0.784, 1.0, 0.9))
		ry += row_h
	ry = tcy + 22.0
	for e in dem.slice(0, 5):
		var lx2: float = view._trains.draw_cargo_strip(self, px + pw * 0.5 + 12.0, ry, 26.0, 22.0, e[0], e[1], 3)
		draw_string(f_orb_b, Vector2(lx2, ry + 16.0), "×%s" % _fmt_tenth(e[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1.0, 0.667, 0.353, 0.9))
		ry += 20.0

func _pd_sorted_cargo(p: Dictionary, which: String) -> Array:
	var pool: Dictionary = p.get("supply" if which == "supply" else "demand", {})
	var rate: Dictionary = p.get("supplyRate" if which == "supply" else "demandRate", {})
	var out: Array = []
	for k in rate.keys():
		var amt := float(pool.get(k, 0.0))
		if amt >= 0.05:
			out.append([String(k), amt])
	out.sort_custom(func(a, b): return a[1] > b[1])
	return out

func _pd_stats_tab(p: Dictionary, px: float, pw: float, tcy: float) -> void:
	draw_string(f_orb_b, Vector2(px + 14.0, tcy + 14.0), "PLANET ACTIVITY", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.392, 0.627, 1.0, 0.7))
	var rows := [
		["DEV LEVEL", "%d / 10" % int(p.get("devLevel", 0))],
		["POPULATION", _fmt_cr(int(p.get("population", 0)))],
		["DELIVERIES", str(int(p.get("passengerDeliveries", 0)))],
		["ECON HEALTH", "%.0f%%" % (float(p.get("economicHealth", 1.0)) * 100.0)],
	]
	var yy := tcy + 32.0
	for r in rows:
		draw_string(f_exo, Vector2(px + 14.0, yy), String(r[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.392, 0.569, 0.843, 0.55))
		_rt(f_exo, px + pw - 14.0, yy, String(r[1]), 9, Color(0.706, 0.863, 1.0, 0.92))
		yy += 16.0

func _pd_upgrades_sidebar(p: Dictionary, px: float, py: float, ph: float) -> void:
	var up_w := 196.0
	var up_x := px - up_w + 2.0
	draw_rect(Rect2(up_x, py, up_w, ph), Color(0.012, 0.02, 0.063, 0.96))
	draw_rect(Rect2(up_x, py, up_w, ph), Color(0.235, 0.471, 0.863, 0.38), false, 1.0)
	_ctr(f_orb_b, up_x + up_w * 0.5, py + 18.0, "UPGRADES", 9, Color(0.549, 0.784, 1.0, 0.88))
	draw_line(Vector2(up_x, py + 28.0), Vector2(up_x + up_w, py + 28.0), Color(0.157, 0.314, 0.627, 0.35), 1.0)
	var ups: Array = p.get("upgrades", [])
	var ty_id := String((p.get("type", {}) as Dictionary).get("id", ""))
	var uy := py + 38.0
	for up in Tuning.UPGRADE_BIOME.keys():
		if String(Tuning.UPGRADE_BIOME[up]) != ty_id:
			continue
		var built: bool = up in ups
		var cost := int(Tuning.UPGRADE_COST.get(up, 10000))
		var card := Rect2(up_x + 6.0, uy, up_w - 12.0, 58.0)
		draw_rect(card, Color(0.059, 0.196, 0.098, 0.65) if built else Color(0.031, 0.071, 0.188, 0.65))
		draw_rect(card, Color(0.157, 0.627, 0.275, 0.38) if built else Color(0.196, 0.353, 0.745, 0.32), false, 1.0)
		draw_string(f_orb_b, Vector2(up_x + 14.0, uy + 16.0), String(up).to_upper().replace("_", " "), HORIZONTAL_ALIGNMENT_LEFT, up_w - 24.0, 9, Color(0.275, 0.784, 0.392, 0.9) if built else Color(0.51, 0.686, 0.941, 0.9))
		if built:
			draw_string(f_exo, Vector2(up_x + 14.0, uy + 34.0), "BUILT", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.392, 0.706, 0.471, 0.7))
		else:
			var bbtn := Rect2(up_x + up_w * 0.5 - 43.0, uy + 32.0, 86.0, 20.0)
			# Cost pill.
			draw_rect(Rect2(bbtn.position.x + 13.0, uy + 22.0, 60.0, 11.0), Color(0.431, 0.071, 0.071, 0.92))
			_ctr(f_exo, bbtn.position.x + 43.0, uy + 30.5, "-%s cr" % _fmt_cr(cost), 8, Color.WHITE)
			_btn(bbtn.position.x, bbtn.position.y, 86.0, 20.0, "PURCHASE", Color(0.078, 0.275, 0.706, 0.92), Color(0.667, 0.867, 1.0, 0.95), 9)
			_rects["upgrade_" + up] = bbtn
		uy += 64.0

func _fmt_tenth(v: float) -> String:
	var t := floorf(v * 10.0) / 10.0
	return ("%d" % int(t)) if is_equal_approx(t, floorf(t)) else ("%.1f" % t)

func _rt(font: Font, right_x: float, y: float, text: String, size: int, col: Color) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(font, Vector2(right_x - w, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)

# Save / load manager (build_game.py save UI).
# Multi-slot save manager (build_game.py drawSaveManagerPopup): lists every saved
# .stt slot with Load / Delete, plus a New-Save button.
func _draw_savemanager() -> void:
	var pw := 460.0
	var ph := 380.0
	var o := _base(pw, ph, Color(0.314, 0.627, 1.0, 0.7))
	var px := o.x
	var py := o.y
	_ctr(f_orb_b, px + pw * 0.5, py + 22.0, "SAVE MANAGER", 13, Color(0.467, 0.745, 1.0))
	_esc_hint(px, py, pw)
	draw_line(Vector2(px, py + 30.0), Vector2(px + pw, py + 30.0), Color(0.157, 0.353, 0.706, 0.35), 1.0)
	# NEW SAVE button (top).
	_btn(px + 16.0, py + 40.0, pw - 32.0, 26.0, "+ NEW SAVE  (current game)", Color(0.071, 0.353, 0.196, 0.9), Color(0.706, 1.0, 0.784, 0.95), 10)
	_rects["sg_new"] = Rect2(px + 16.0, py + 40.0, pw - 32.0, 26.0)
	# Slot list.
	var saves := SaveLoad.list_saves()
	var ly := py + 76.0
	var row_h := 32.0
	if saves.is_empty():
		_ctr(f_exo, px + pw * 0.5, ly + 30.0, "No saved games yet — click NEW SAVE above.", 11, Color(0.55, 0.65, 0.8, 0.7))
	for i in saves.size():
		var sv: Dictionary = saves[i]
		if ly + row_h > py + ph - 44.0:
			break
		var r := Rect2(px + 16.0, ly, pw - 32.0, row_h - 4.0)
		if _hov(r):
			draw_rect(r, Color(0.157, 0.314, 0.627, 0.18))
		elif i % 2 == 0:
			draw_rect(r, Color(0.059, 0.098, 0.216, 0.4))
		draw_string(f_exo, Vector2(px + 24.0, ly + 18.0), String(sv.name), HORIZONTAL_ALIGNMENT_LEFT, pw - 180.0, 11, Color(0.78, 0.86, 1.0, 0.92))
		var ld := Rect2(px + pw - 150.0, ly + 3.0, 66.0, row_h - 10.0)
		_btn(ld.position.x, ld.position.y, ld.size.x, ld.size.y, "LOAD", Color(0.078, 0.235, 0.588, 0.92), Color(0.706, 0.902, 1.0, 0.95), 9)
		_rects["sgload_%d" % i] = ld
		var dl := Rect2(px + pw - 78.0, ly + 3.0, 62.0, row_h - 10.0)
		_btn(dl.position.x, dl.position.y, dl.size.x, dl.size.y, "DELETE", Color(0.353, 0.094, 0.094, 0.9), Color(1.0, 0.706, 0.706, 0.95), 9)
		_rects["sgdel_%d" % i] = dl
		ly += row_h
	# BACK + status message.
	_btn(px + pw * 0.5 - 50.0, py + ph - 36.0, 100.0, 26.0, "BACK", Color(0.08, 0.14, 0.28, 0.85), Color(0.6, 0.75, 0.95, 0.9))
	_rects["sg_back"] = Rect2(px + pw * 0.5 - 50.0, py + ph - 36.0, 100.0, 26.0)
	var msg := String(state.get("save_msg", ""))
	if msg != "":
		_ctr(f_exo, px + pw * 0.5, py + ph - 44.0, msg, 9, Color(0.9, 0.85, 0.5, 0.9))

# Generic event popup (NEW MISSION / unlocks / discoveries) — title + body + OK.
func _on_first_delivery(planet_id: int, cargo: String, car_type: String, sd: float) -> void:
	_present_event({"kind": "first_delivery", "planet_id": planet_id, "cargo": cargo, "car": car_type, "sd": sd})

# Present an event popup now if nothing is open, else queue it (build_game.py
# uses per-kind pending queues; one shared FIFO is faithful to the one-at-a-time
# UX). Dismissing an event drains the next via _dismiss_event().
func _present_event(st: Dictionary) -> void:
	if active != "":
		_event_queue.append(st)
		return
	_open("event")
	state = st

func _dismiss_event() -> void:
	_close()
	if not _event_queue.is_empty():
		_open("event")
		state = _event_queue.pop_front()

func _draw_event() -> void:
	match String(state.get("kind", "")):
		"unlock": _draw_event_unlock()
		"reward": _draw_event_reward()
		"new_mission": _draw_event_mission()
		"first_delivery": _draw_event_first_delivery()
		"gold": _draw_event_deposit(true)
		"diamond": _draw_event_deposit(false)
		"upgrade": _draw_event_upgrade()
		_: _draw_event_generic()

# First-delivery popup (build_game.py drawFirstDeliveryPopup 17278): blue, title +
# loaded car sprite over a rail + flavour line.
func _draw_event_first_delivery() -> void:
	var p := _planet_by_id(int(state.get("planet_id", -1)))
	var pname := String(p.get("name", "the planet"))
	var inhabited := float(p.get("population", 0.0)) > 0.0
	var pw := 400.0
	var ph := 232.0
	var o := _base(pw, ph, Color(0.353, 0.706, 1.0, 0.78))
	var px := o.x
	var py := o.y
	var cx := px + pw * 0.5
	# Title (glowing blue).
	for off in [Vector2(-1.5, 0), Vector2(1.5, 0), Vector2(0, -1.5), Vector2(0, 1.5)]:
		_ctr(f_orb_b, cx + off.x, py + 30.0 + off.y, "First Delivery arrives at " + pname, 14, Color(0.165, 0.471, 0.816, 0.5), pw - 30.0)
	_ctr(f_orb_b, cx, py + 30.0, "First Delivery arrives at " + pname, 14, Color(0.604, 0.839, 1.0), pw - 30.0)
	# Loaded car sprite over a rail line.
	var rail_y := py + 130.0
	draw_line(Vector2(cx - 90.0, rail_y + 2.0), Vector2(cx + 90.0, rail_y + 2.0), Color(0.275, 0.510, 0.824, 0.35), 1.0)
	if view and view.get("_trains"):
		view._trains.draw_car_strip(self, Rect2(cx - 75.0, rail_y - 64.0, 150.0, 66.0), [String(state.get("car", "car_passenger"))], [true])
	# Flavour line.
	var who := "Citizens" if inhabited else String(GameState.corp_name) + " investors"
	var cargo_lbl := String(state.get("cargo", "cargo")).replace("_", " ").to_upper()
	var flavour := "%s rejoice as the first-ever shipment of %s arrives at %s. S.D. %.1f" % [who, cargo_lbl, pname, float(state.get("sd", 0.0))]
	draw_multiline_string(f_exo, Vector2(px + 22.0, rail_y + 26.0), flavour, HORIZONTAL_ALIGNMENT_CENTER, pw - 44.0, 12, 3, Color(0.808, 0.886, 0.980, 0.92))
	var ok := Rect2(cx - 55.0, py + ph - 40.0, 110.0, 27.0)
	_btn(ok.position.x, ok.position.y, 110.0, 27.0, "OKAY!", Color(0.094, 0.314, 0.667, 0.9), Color(0.922, 0.961, 1.0, 0.97), 9)
	_rects["event_ok"] = ok

# New-mission popup (build_game.py drawNewMissionPopup 16657): green, name +
# objectives (○) + reward pill + ACCEPT.
func _draw_event_mission() -> void:
	var def: Dictionary = Missions.def_for(String(state.get("id", "")))
	var objs: Array = def.get("objectives", [])
	var pw := 440.0
	var ph := 132.0 + objs.size() * 18.0 + (28.0 if int(def.get("reward", 0)) > 0 else 0.0)
	var o := _base(pw, ph, Color(0.314, 0.784, 0.510, 0.7))
	var px := o.x
	var py := o.y
	var cx := px + pw * 0.5
	_ctr(f_orb_b, cx, py + 22.0, "NEW MISSION", 10, Color(0.490, 1.0, 0.690, 0.78))
	# Glowing mission name.
	for off in [Vector2(-1.5, 0), Vector2(1.5, 0), Vector2(0, -1.5), Vector2(0, 1.5)]:
		_ctr(f_orb_b, cx + off.x, py + 44.0 + off.y, String(def.get("name", "?")), 14, Color(1.0, 0.878, 0.502, 0.45))
	_ctr(f_orb_b, cx, py + 44.0, String(def.get("name", "?")), 14, Color(1.0, 0.878, 0.502))
	draw_line(Vector2(px + 20.0, py + 56.0), Vector2(px + pw - 20.0, py + 56.0), Color(0.235, 0.627, 0.392, 0.4), 1.0)
	_ctr(f_exo, cx, py + 74.0, "OBJECTIVES", 9, Color(0.471, 0.745, 0.588, 0.7))
	var oy := py + 92.0
	for ob in objs:
		draw_arc(Vector2(px + 36.0, oy - 2.0), 5.0, 0.0, TAU, 14, Color(0.471, 0.627, 0.549, 0.85), 1.2)
		draw_string(f_exo, Vector2(px + 48.0, oy + 2.0), String(ob.get("text", "")), HORIZONTAL_ALIGNMENT_LEFT, pw - 70.0, 10, Color(0.784, 0.882, 0.824, 0.9))
		oy += 18.0
	var rw := int(def.get("reward", 0))
	if rw > 0:
		var pill := Rect2(cx - 90.0, oy + 2.0, 180.0, 22.0)
		_fill_round(pill, 5.0, Color(0.078, 0.353, 0.196, 0.9))
		_ctr(f_orb_b, cx, oy + 17.0, "REWARD:  + %s CR" % _fmt_cr(rw), 10, Color(0.549, 1.0, 0.706))
		oy += 28.0
	var ok := Rect2(cx - 60.0, py + ph - 38.0, 120.0, 28.0)
	_btn(ok.position.x, ok.position.y, 120.0, 28.0, "ACCEPT", Color(0.071, 0.431, 0.255, 0.88), Color(0.706, 1.0, 0.843, 0.95), 10)
	_rects["event_ok"] = ok

func _draw_event_generic() -> void:
	var pw := 420.0
	var ph := 220.0
	var o := _base(pw, ph, Color(1.0, 0.78, 0.24, 0.8))
	var px := o.x
	var py := o.y
	_ctr(f_orb_b, px + pw * 0.5, py + 24.0, String(state.get("title", "")), 12, Color(1.0, 0.82, 0.31))
	draw_line(Vector2(px, py + 34.0), Vector2(px + pw, py + 34.0), Color(0.5, 0.4, 0.1, 0.4), 1.0)
	_ctr(f_orb_b, px + pw * 0.5, py + 60.0, String(state.get("head", "")), 13, Color(0.9, 0.95, 1.0, 0.97))
	draw_multiline_string(f_exo, Vector2(px + 30.0, py + 84.0), String(state.get("body", "")), HORIZONTAL_ALIGNMENT_CENTER, pw - 60.0, 11, 4, Color(0.75, 0.84, 1.0, 0.88))
	var bw := 120.0
	var ok := Rect2(px + pw * 0.5 - bw * 0.5, py + ph - 44.0, bw, 28.0)
	_btn(ok.position.x, ok.position.y, bw, 28.0, "OK", Color(0.1, 0.42, 0.22, 0.9), Color(0.7, 1.0, 0.78, 0.95))
	_rects["event_ok"] = ok

# Engine/car unlock — sprite-hero popup (build_game.py drawEngineUnlockPopup 16886
# / drawCarUnlockPopup 16934): 320×360, green, glowing name, big sprite, OKAY.
func _draw_event_unlock() -> void:
	var pw := 320.0
	var ph := 360.0
	var o := _base(pw, ph, Color(0.235, 0.784, 0.549, 0.7))
	var px := o.x
	var py := o.y
	var cx := px + pw * 0.5
	_ctr(f_orb_b, cx, py + 22.0, String(state.get("label", "")), 10, Color(0.608, 1.0, 0.804, 0.70))
	# Glowing name.
	for off in [Vector2(-1.5, 0), Vector2(1.5, 0), Vector2(0, -1.5), Vector2(0, 1.5)]:
		_ctr(f_orb_b, cx + off.x, py + 40.0 + off.y, String(state.get("name", "")), 14, Color(0.0, 0.8, 0.533, 0.5))
	_ctr(f_orb_b, cx, py + 40.0, String(state.get("name", "")), 14, Color(0.502, 1.0, 0.784))
	var noun := "engine" if bool(state.get("is_engine", false)) else "car"
	_ctr(f_exo, cx, py + 56.0, "This %s type is now available" % noun, 9, Color(0.784, 0.941, 0.863, 0.82))
	_ctr(f_exo, cx, py + 68.0, "in the Train Builder.", 9, Color(0.784, 0.941, 0.863, 0.82))
	# Big sprite (centred in the 80→320 area).
	if view and view.get("_trains"):
		view._trains.draw_car_strip(self, Rect2(px + 30.0, py + 90.0, pw - 60.0, 150.0), [String(state.get("sprite", ""))], [true])
	# OKAY button.
	var ok := Rect2(px + (pw - 100.0) * 0.5, py + ph - 40.0, 100.0, 26.0)
	_btn(ok.position.x, ok.position.y, 100.0, 26.0, "OKAY!", Color(0.071, 0.431, 0.255, 0.88), Color(0.706, 1.0, 0.843, 0.95), 9)
	_rects["event_ok"] = ok

# Gold/diamond deposit discovery (build_game.py drawGoldDiscoveryPopup 16469 /
# drawDiamondDiscoveryPopup 16501): 320×340, amber/blue border, EUREKA! / FOR REAL?
# title, 2-line sensor message, big car sprite, OKAY.
func _draw_event_deposit(is_gold: bool) -> void:
	var pw := 320.0
	var ph := 340.0
	var border := Color(1.0, 0.784, 0.118, 0.7) if is_gold else Color(0.314, 0.784, 1.0, 0.7)
	var o := _base(pw, ph, border)
	var px := o.x
	var py := o.y
	var cx := px + pw * 0.5
	var title := "EUREKA!" if is_gold else "FOR REAL?"
	var title_col := Color(1.0, 0.878, 0.251) if is_gold else Color(0.753, 0.941, 1.0)
	var glow := Color(1.0, 0.667, 0.0, 0.5) if is_gold else Color(0.251, 0.784, 1.0, 0.5)
	# Glowing title.
	for off in [Vector2(-1.5, 0), Vector2(1.5, 0), Vector2(0, -1.5), Vector2(0, 1.5)]:
		_ctr(f_orb_b, cx + off.x, py + 26.0 + off.y, title, 13, glow)
	_ctr(f_orb_b, cx, py + 26.0, title, 13, title_col)
	# 2-line sensor message.
	var lines := ["Your train's sensors have detected a", "significant gold deposit on this planet."] if is_gold else ["Your sensors detected actual diamonds", "buried on this planet. No joke."]
	for i in lines.size():
		_ctr(f_exo, cx, py + 44.0 + i * 14.0, String(lines[i]), 9, Color(0.784, 0.863, 1.0, 0.85))
	# Big car sprite.
	if view and view.get("_trains"):
		var spr := "car_gold" if is_gold else "car_diamond"
		view._trains.draw_car_strip(self, Rect2(px + 30.0, py + 86.0, pw - 60.0, 150.0), [spr], [true])
	# OKAY button.
	var fill := Color(0.706, 0.549, 0.039, 0.85) if is_gold else Color(0.078, 0.392, 0.627, 0.85)
	var txt := Color(1.0, 0.941, 0.627, 0.95) if is_gold else Color(0.784, 0.961, 1.0, 0.95)
	var ok := Rect2(px + (pw - 100.0) * 0.5, py + ph - 40.0, 100.0, 26.0)
	_btn(ok.position.x, ok.position.y, 100.0, 26.0, "OKAY!", fill, txt, 9)
	_rects["event_ok"] = ok

# Per-upgrade copy (build_game.py _UPGRADE_UNLOCK_INFO 17037). Keyed on the port's
# upgrade ids. station-kind = orbit rings; building-kind = planet + foundry.
const _UPGRADE_UNLOCK_INFO := {
	"iron_foundry": {"name": "IRON FOUNDRY", "kind": "iron_foundry", "biome": Color(0.788, 0.647, 0.353),
		"cost": "10,000 cr", "build_on": "DESERT planets", "build_on_col": Color(0.941, 0.627, 0.251),
		"enables": "Enables this planet to smelt delivered [Molten Ore] + [Water]\ninto [Iron].",
		"formula": "1 [Molten Ore]  +  1 [Water]   →   1 [Iron]", "time": "~40 seconds"},
	"bakery": {"name": "BAKERY", "kind": "bakery", "biome": Color(0.227, 0.624, 0.761),
		"cost": "15,000 cr", "build_on": "RESORT planets", "build_on_col": Color(0.219, 0.667, 0.941),
		"enables": "Enables this planet to bake delivered [Grain] into [Cargo].",
		"formula": "1 [Grain]   →   1 [Cargo]", "time": "~40 seconds"},
	"glassworks": {"name": "GLASSWORKS", "kind": "glassworks", "biome": Color(0.227, 0.624, 0.761),
		"cost": "25,000 cr", "build_on": "RESORT planets", "build_on_col": Color(0.219, 0.667, 0.941),
		"enables": "Enables this planet to melt delivered [Sand] + [Chemical] into [Glass].",
		"formula": "1 [Sand]  +  1 [Chemical]   →   1 [Glass]", "time": "~40 seconds"},
	"large_station": {"name": "LARGE STATION", "kind": "station", "rings": 2, "biome": Color(0.533, 0.576, 0.639),
		"cost": "50,000 cr  +  4 Iron", "build_on": "any planet where a STATION has already been built",
		"enables": "Enables TRAINS in both LOW and MEDIUM orbits\nto LOAD/UNLOAD simultaneously."},
	"terminal": {"name": "TERMINAL", "kind": "station", "rings": 3, "biome": Color(0.533, 0.576, 0.639),
		"cost": "75,000 cr  +  6 Steel", "build_on": "any planet where a LARGE STATION has already been built",
		"enables": "Enables TRAINS in LOW, MEDIUM, and HIGH orbits to LOAD/UNLOAD simultaneously."},
}

# Cargo text colour (build_game.py CARGO_TEXT_COLORS 1134), keyed on display name.
const _CARGO_TEXT_COLORS := {
	"passengers": Color(0.765, 0.0, 0.063), "livestock": Color(0.714, 0.506, 0.361),
	"mail": Color(1, 1, 1), "water": Color(0.259, 0.659, 1.0), "ice": Color(0.643, 0.863, 1.0),
	"sand": Color(0.733, 0.518, 0.349), "molten ore": Color(1.0, 0.353, 0.157),
	"iron": Color(0.369, 0.384, 0.420), "gold": Color(1.0, 0.820, 0.282),
	"diamond": Color(0.643, 0.941, 1.0), "hazmat": Color(0.863, 1.0, 0.282),
	"oil": Color(0.604, 0.659, 0.227), "battery": Color(1.0, 0.843, 0.267),
	"chemical": Color(0.502, 0.910, 0.376), "flowers": Color(1.0, 0.478, 0.800),
	"medical": Color(1.0, 0.353, 0.471), "grain": Color(0.831, 0.655, 0.416),
	"fruit": Color(1.0, 0.478, 0.282), "steel": Color(0.580, 0.659, 0.737),
	"glass": Color(0.690, 0.910, 0.941), "machinery": Color(0.643, 0.675, 0.706),
	"cargo": Color(0.690, 0.533, 0.345),
}

# Upgrade-unlock popup (build_game.py drawUpgradeUnlockPopup 17097): amber, label +
# glowing name + visual + COST/BUILDABLE ON/ENABLES/formula, OKAY.
func _draw_event_upgrade() -> void:
	var info: Dictionary = _UPGRADE_UNLOCK_INFO.get(String(state.get("upgrade", "")), {})
	if info.is_empty():
		_draw_event_generic(); return
	var pw := 340.0
	var is_station := String(info.get("kind", "")) == "station"
	# Size to content: count wrapped lines per section (mirrors the draw below).
	var n_build := _count_lines(f_exo, String(info.get("build_on", "")), 11, pw - 36.0)
	var n_en := _count_lines(f_exo, String(info.get("enables", "")), 10, pw - 36.0)
	var n_form := _count_lines(f_exo, String(info.get("formula", "")), 11, pw - 36.0) if info.has("formula") else 0
	var be := 196.0
	be += 15.0 + 15.0 + 24.0                 # COST: caption + pill + gap
	be += 15.0 + 14.0 * n_build + 9.0        # BUILDABLE ON
	be += 15.0 + 14.0 * n_en                 # ENABLES
	if info.has("formula"):
		be += 8.0 + 15.0 * n_form + 13.0     # formula + processing time
	var ph := be + 64.0
	var o := _base(pw, ph, Color(0.961, 0.784, 0.157, 0.7))
	var px := o.x
	var py := o.y
	var cx := px + pw * 0.5
	# Label + glowing name.
	_ctr(f_orb_b, cx, py + 22.0, "NEW PLANET UPGRADE UNLOCKED", 10, Color(1.0, 0.882, 0.510, 0.78))
	for off in [Vector2(-1.5, 0), Vector2(1.5, 0), Vector2(0, -1.5), Vector2(0, 1.5)]:
		_ctr(f_orb_b, cx + off.x, py + 44.0 + off.y, String(info.get("name", "")), 15, Color(1.0, 0.667, 0.125, 0.45))
	_ctr(f_orb_b, cx, py + 44.0, String(info.get("name", "")), 15, Color(1.0, 0.878, 0.502))
	# Visual.
	_draw_upgrade_visual(cx, py + (108.0 if is_station else 125.0), info)
	# Body sections.
	var ly := py + 196.0
	_cap(cx, ly, "COST"); ly += 15.0
	var ctxt := String(info.get("cost", "-"))
	var cpw := f_exo.get_string_size(ctxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 16.0
	_fill_round(Rect2(cx - cpw * 0.5, ly - 13.0, cpw, 17.0), 4.0, Color(0.431, 0.071, 0.071, 0.92))
	_ctr(f_exo, cx, ly - 0.5, ctxt, 11, Color(1, 1, 1, 0.97))
	ly += 24.0
	_cap(cx, ly, "BUILDABLE ON"); ly += 15.0
	ly = _draw_tok_text(cx, ly, String(info.get("build_on", "-")), 11, info.get("build_on_col", Color(0.745, 0.882, 1.0, 0.95)), pw - 36.0, 14.0) + 9.0
	_cap(cx, ly, "ENABLES"); ly += 15.0
	ly = _draw_tok_text(cx, ly, String(info.get("enables", "")), 10, Color(0.894, 0.894, 0.914, 0.9), pw - 36.0, 14.0)
	if info.has("formula"):
		ly += 8.0
		ly = _draw_tok_text(cx, ly, String(info.get("formula", "")), 11, Color(1.0, 0.922, 0.627, 0.97), pw - 36.0, 15.0)
		ly = _draw_tok_text(cx, ly, "Processing time: " + String(info.get("time", "")), 9, Color(0.784, 0.804, 0.843, 0.78), pw - 36.0, 13.0)
	draw_string(f_exo, Vector2(px + 18.0, ly + 14.0), "Available in the planet UPGRADES panel.", HORIZONTAL_ALIGNMENT_CENTER, pw - 36.0, 9, Color(0.706, 0.725, 0.765, 0.6))
	var ok := Rect2(cx - 50.0, ly + 24.0, 100.0, 26.0)
	_btn(ok.position.x, ok.position.y, 100.0, 26.0, "OKAY!", Color(0.588, 0.451, 0.078, 0.9), Color(1.0, 0.961, 0.824, 0.97), 9)
	_rects["event_ok"] = ok

func _cap(cx: float, y: float, txt: String) -> void:
	_ctr(f_orb, cx, y, txt, 9, Color(0.588, 0.784, 1.0, 0.65))

# Small upgrade visual: station orbit-rings, or a planet with a foundry building.
func _draw_upgrade_visual(cx: float, cy: float, info: Dictionary) -> void:
	var r := 42.0
	if String(info.get("kind", "")) == "station":
		var ring_r := [r * 1.3, r * 1.7, r * 2.1]
		var rings := int(info.get("rings", 2))
		for i in rings:
			draw_arc(Vector2(cx, cy), ring_r[i], 0.0, TAU, 48, Color(0.471, 0.706, 1.0, 0.5 - i * 0.12), 1.5)
		draw_circle(Vector2(cx, cy), r, Color(0.667, 0.706, 0.769))
		draw_circle(Vector2(cx, cy - r * 0.3), r * 0.55, Color(0.733, 0.769, 0.831, 0.5))
		draw_arc(Vector2(cx, cy), r, 0.0, TAU, 48, Color(1, 1, 1, 0.12), 1.0)
		# Station module on top.
		var my := cy - r
		draw_rect(Rect2(cx - 7.0, my - 5.0, 14.0, 6.0), Color(0.353, 0.588, 0.902, 0.95))
		draw_rect(Rect2(cx - 2.5, my - 10.0, 5.0, 5.0), Color(0.588, 0.784, 1.0, 0.95))
	else:
		var pr := r * 0.6
		draw_circle(Vector2(cx, cy), pr, info.get("biome", Color(0.6, 0.6, 0.6)))
		draw_circle(Vector2(cx, cy), pr * 0.45, Color(0.08, 0.086, 0.110, 0.5))
		draw_arc(Vector2(cx, cy), pr, 0.0, TAU, 40, Color(1, 1, 1, 0.12), 1.0)
		# A simple building seated on the surface (the focal element).
		var bw := 30.0
		var bx := cx - bw * 0.5
		var by := cy - pr - 26.0
		draw_rect(Rect2(bx, by, bw, 28.0), Color(0.235, 0.247, 0.290))
		draw_rect(Rect2(bx + 5.0, by - 14.0, 7.0, 16.0), Color(0.310, 0.325, 0.376))  # chimney
		draw_rect(Rect2(bx, by, bw, 28.0), Color(0.490, 0.604, 0.722, 0.7), false, 1.0)
		# Warm glow at the building mouth (foundry).
		draw_rect(Rect2(bx + bw * 0.5 - 4.0, by + 14.0, 8.0, 10.0), Color(1.0, 0.557, 0.157, 0.85))

# ── Token-aware centred text (build_game.py _wrapTokC) ───────────────────────
# Counts wrapped lines of `text` at `maxw` (honours explicit \n).
func _count_lines(font: Font, text: String, size: int, maxw: float) -> int:
	var n := 0
	for seg in text.split("\n"):
		var line := ""
		for w in seg.split(" ", false):
			var t := w if line == "" else line + " " + w
			if font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= maxw:
				line = t
			else:
				if line != "": n += 1
				line = w
		if line != "": n += 1
	return maxi(1, n)

# Draws `text` centred at cx, wrapping at maxw, colouring [Cargo] tokens. Returns
# the y after the block.
func _draw_tok_text(cx: float, start_y: float, text: String, size: int, base: Color, maxw: float, lh: float) -> float:
	var y := start_y
	var space_w := f_exo.get_string_size(" ", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	for seg in text.split("\n"):
		var words := _tok_words(seg, base)
		var line: Array = []
		var line_w := 0.0
		for item in words:
			var ww := f_exo.get_string_size(String(item.w), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
			var add := ww + (space_w if not line.is_empty() else 0.0)
			if line_w + add > maxw and not line.is_empty():
				_flush_tok_line(cx, y, line, line_w, size, space_w)
				y += lh; line = []; line_w = 0.0; add = ww
			line.append(item)
			line_w += add
		if not line.is_empty():
			_flush_tok_line(cx, y, line, line_w, size, space_w)
			y += lh
	return y

func _flush_tok_line(cx: float, y: float, line: Array, line_w: float, size: int, space_w: float) -> void:
	var x := cx - line_w * 0.5
	for item in line:
		var w := String(item.w)
		draw_string(f_exo, Vector2(x, y), w, HORIZONTAL_ALIGNMENT_LEFT, -1, size, item.c)
		x += f_exo.get_string_size(w, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + space_w

# Splits text into (word, colour) items, colouring [Cargo] refs by CARGO_TEXT_COLORS.
func _tok_words(text: String, base: Color) -> Array:
	var out: Array = []
	var i := 0
	var n := text.length()
	var cur := ""
	while i < n:
		var ch := text[i]
		if ch == "[":
			for w in cur.split(" ", false):
				out.append({"w": w, "c": base})
			cur = ""
			var j := text.find("]", i)
			if j < 0: j = n
			var inner := text.substr(i + 1, j - i - 1)
			var col: Color = _CARGO_TEXT_COLORS.get(inner.to_lower(), base)
			for w in inner.split(" ", false):
				out.append({"w": w, "c": col})
			i = j + 1
		else:
			cur += ch
			i += 1
	for w in cur.split(" ", false):
		out.append({"w": w, "c": base})
	return out

# Mission reward (build_game.py drawMissionRewardPopup 17185): green, name + reward pill.
func _draw_event_reward() -> void:
	var pw := 380.0
	var ph := 220.0
	var o := _base(pw, ph, Color(0.235, 0.824, 0.510, 0.75))
	var px := o.x
	var py := o.y
	var cx := px + pw * 0.5
	_ctr(f_orb_b, cx, py + 26.0, "MISSION COMPLETED", 10, Color(0.490, 1.0, 0.690, 0.85))
	draw_multiline_string(f_exo, Vector2(px + 24.0, py + 50.0), String(state.get("name", "")), HORIZONTAL_ALIGNMENT_CENTER, pw - 48.0, 15, 2, Color(0.490, 1.0, 0.690))
	# Reward pill.
	var rw := int(state.get("reward", 0))
	if rw > 0:
		var pill_w := 180.0
		var pr := Rect2(cx - pill_w * 0.5, py + 108.0, pill_w, 38.0)
		draw_rect(pr, Color(0.078, 0.353, 0.196, 0.9))
		draw_rect(pr, Color(0.314, 0.824, 0.510, 0.7), false, 1.5)
		_ctr(f_orb_b, cx, py + 133.0, "+ %s CR" % _fmt_cr(rw), 18, Color(0.549, 1.0, 0.706))
	var ok := Rect2(cx - 55.0, py + ph - 40.0, 110.0, 26.0)
	_btn(ok.position.x, ok.position.y, 110.0, 26.0, "OKAY!", Color(0.071, 0.431, 0.255, 0.88), Color(0.706, 1.0, 0.843, 0.95), 9)
	_rects["event_ok"] = ok

# ── TrainBuilder (build_game.py §17) — engine + car picker → Player.build_train ─
func _build_planet() -> Dictionary:
	var sel: Dictionary = GameState.selected
	if String(sel.get("kind", "")) == "planet":
		var p := _planet_by_id(int(String(sel.get("id", "")).trim_prefix("planet_")))
		if not p.is_empty() and bool(p.get("hasStation", false)):
			return p
	for p in Galaxy.planets:
		if bool(p.get("playerBuiltStation", false)):
			return p
	var o := _planet_by_id(Galaxy.origen_id)
	if not o.is_empty() and bool(o.get("hasStation", false)):
		return o
	return {}

func _draw_trainbuilder() -> void:
	var pw := 620.0
	var ph := 444.0
	var o := _base(pw, ph, Color(0.275, 0.745, 1.0, 0.55))
	var px := o.x
	var py := o.y
	var bp := _build_planet()
	var BTN_W := 76.0
	var BTN_H := 60.0
	var GAP := 6.0
	# Title + [ESC] cancel.
	var title := "BUILD TRAIN"
	if not bp.is_empty():
		title += "   ·   AT " + String(bp.get("name", "?")).to_upper()
	draw_string(f_orb_b, Vector2(px + 12.0, py + 22.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.467, 0.867, 1.0))
	_esc_hint(px, py, pw)
	draw_line(Vector2(px, py + 26.0), Vector2(px + pw, py + 26.0), Color(0.216, 0.333, 0.549, 0.45), 1.0)
	# ENGINE label + counter.
	draw_string(f_orb_b, Vector2(px + 12.0, py + 47.0), "ENGINE", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.549, 0.784, 1.0, 0.8))
	draw_string(f_exo, Vector2(px + 70.0, py + 47.0), "(1/5)", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.275, 0.784, 0.431, 0.8))
	var ex := px + 12.0
	for e in _ENGINES:
		var unlocked: bool = GameState.unlocked_engines.has(e)
		_tb_car_btn(ex, py + 53.0, BTN_W, BTN_H, e, e == tb_engine, unlocked)
		if unlocked:
			_rects["eng_" + e] = Rect2(ex, py + 53.0, BTN_W, BTN_H)
		ex += BTN_W + GAP
	# Caboose button (right).
	var has_caboose := "caboose" in tb_cars
	var cab_x := px + pw - 12.0 - BTN_W
	draw_string(f_orb_b, Vector2(cab_x, py + 47.0), "CABOOSE", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.549, 0.784, 1.0, 0.8))
	_tb_car_btn(cab_x, py + 53.0, BTN_W, BTN_H, "caboose", has_caboose, true)
	_rects["addcar_caboose"] = Rect2(cab_x, py + 53.0, BTN_W, BTN_H)
	# Vertical dashed divider between engines and caboose.
	var dvx := ex + 12.0
	var dy := py + 53.0
	while dy < py + 113.0:
		draw_line(Vector2(dvx, dy), Vector2(dvx, dy + 3.0), Color(0.216, 0.333, 0.549, 0.35), 1.0)
		dy += 7.0
	draw_line(Vector2(px + 12.0, py + 120.0), Vector2(px + pw - 12.0, py + 120.0), Color(0.216, 0.333, 0.549, 0.35), 1.0)
	# CARS section.
	var car_cap := 10
	draw_string(f_orb_b, Vector2(px + 12.0, py + 130.0), "CARS", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.549, 0.784, 1.0, 0.8))
	var at_cap := tb_cars.size() >= car_cap
	draw_string(f_exo, Vector2(px + 48.0, py + 130.0), "(%d / %d)" % [tb_cars.size(), car_cap], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1.0, 0.588, 0.235, 0.9) if at_cap else Color(0.471, 0.647, 0.863, 0.7))
	var cars: Array = []
	for ct in GameState.unlocked_cars.keys():
		if String(ct) != "caboose":
			cars.append(String(ct))
	for i in cars.size():
		var ccol := i % 6
		var crow := i / 6
		if crow > 1:
			break
		var bx := px + 12.0 + ccol * (BTN_W + GAP)
		var by := py + 136.0 + crow * (BTN_H + GAP)
		_tb_car_btn(bx, by, BTN_W, BTN_H, cars[i], false, not at_cap)
		if not at_cap:
			_rects["addcar_" + cars[i]] = Rect2(bx, by, BTN_W, BTN_H)
	draw_line(Vector2(px + 12.0, py + 286.0), Vector2(px + pw - 12.0, py + 286.0), Color(0.216, 0.333, 0.549, 0.45), 1.0)
	# TRAIN PREVIEW.
	draw_string(f_orb_b, Vector2(px + 12.0, py + 296.0), "TRAIN PREVIEW  ·  click any car to remove it", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.353, 0.529, 0.765, 0.65))
	var viz := Rect2(px + 12.0, py + 300.0, pw - 24.0, 90.0)
	draw_rect(viz, Color(0.016, 0.035, 0.086, 0.6))
	draw_rect(viz, Color(0.157, 0.255, 0.471, 0.45), false, 1.0)
	if tb_cars.is_empty():
		_ctr(f_exo, px + pw * 0.5, py + 332.0, "Select an engine to begin building your train", 11, Color(0.235, 0.353, 0.549, 0.6))
	var consist: Array = [tb_engine]
	for c in tb_cars:
		consist.append(c)
	var full: Array = []
	for i in consist.size():
		full.append(true)
	if view and view.get("_trains"):
		view._trains.draw_car_strip(self, Rect2(viz.position.x + 8.0, viz.position.y + 8.0, viz.size.x - 16.0, viz.size.y - 16.0), consist, full)
	if not tb_cars.is_empty():
		_rects["tb_remove_last"] = viz
	# Action buttons.
	var cost := int(Tuning.ENGINE_COSTS.get(tb_engine, 10000)) + tb_cars.size() * Tuning.CAR_COST
	var afford := GameState.credits >= cost and not bp.is_empty() and not tb_cars.is_empty() and has_caboose
	var conf := Rect2(px + 12.0, py + 405.0, 110.0, 26.0)
	_btn(conf.position.x, conf.position.y, 110.0, 26.0, "PURCHASE" if cost > 0 else "CONFIRM", Color(0.086, 0.424, 0.204, 0.88) if afford else Color(0.071, 0.149, 0.102, 0.55), Color(0.667, 1.0, 0.667, 0.95) if afford else Color(0.255, 0.412, 0.294, 0.5), 9)
	if afford:
		_rects["tb_build"] = conf
	# Hint / cost pill (right of confirm).
	var hx := px + 12.0 + 110.0 + 12.0
	if tb_cars.is_empty():
		draw_string(f_exo, Vector2(hx, py + 421.0), "Add cars and a CABOOSE to continue", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.431, 0.549, 0.706, 0.55))
	elif not has_caboose:
		draw_string(f_exo, Vector2(hx, py + 421.0), "Add a CABOOSE to continue", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.863, 0.314, 0.235, 0.75))
	elif GameState.credits < cost:
		draw_string(f_exo, Vector2(hx, py + 421.0), "Need %s more credits" % _fmt_cr(cost - GameState.credits), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.863, 0.314, 0.235, 0.75))
	else:
		draw_rect(Rect2(hx, py + 411.0, 70.0, 13.0), Color(0.431, 0.071, 0.071, 0.92))
		_ctr(f_exo, hx + 35.0, py + 420.0, "-%s cr" % _fmt_cr(cost), 8, Color.WHITE)
	# CANCEL (right).
	var cancel := Rect2(px + pw - 12.0 - 90.0, py + 405.0, 90.0, 26.0)
	_btn(cancel.position.x, cancel.position.y, 90.0, 26.0, "CANCEL", Color(0.392, 0.110, 0.110, 0.82), Color(1.0, 0.667, 0.667, 0.9), 9)
	_rects["tb_cancel"] = cancel
	# Engine-details side panel (left).
	_tb_engine_panel(px, py, ph)

func _tb_car_btn(x: float, y: float, w: float, h: float, type: String, selected: bool, unlocked: bool) -> void:
	var hov := unlocked and not selected and _hov(Rect2(x, y, w, h))
	var bg := Color(0.157, 0.392, 0.824, 0.35) if selected else (Color(0.078, 0.196, 0.431, 0.7) if hov else (Color(0.047, 0.125, 0.294, 0.6) if unlocked else Color(0.047, 0.071, 0.125, 0.55)))
	draw_rect(Rect2(x, y, w, h), bg)
	if selected:
		draw_rect(Rect2(x, y, w, h), Color(0.314, 0.627, 1.0, 0.95), false, 2.0)
	elif hov:
		draw_rect(Rect2(x, y, w, h), Color(0.471, 0.706, 1.0, 0.85), false, 1.5)
	elif unlocked:
		draw_rect(Rect2(x, y, w, h), Color(0.216, 0.353, 0.686, 0.5), false, 1.0)
	# Sprite.
	if view and view.get("_trains"):
		view._trains.draw_car_strip(self, Rect2(x + 4.0, y + 4.0, w - 8.0, h - 18.0), [type], [true])
	if not unlocked:
		draw_rect(Rect2(x, y, w, h), Color(0.024, 0.039, 0.071, 0.6))
		_ctr(f_orb_b, x + w * 0.5, y + h * 0.54, "LOCKED", 7, Color(0.667, 0.686, 0.725, 0.8))
	var lbl := String(type).trim_prefix("engine_").trim_prefix("car_").to_upper().replace("_", " ")
	_ctr(f_exo, x + w * 0.5, y + h - 3.0, lbl, 8, Color(0.784, 0.863, 1.0, 0.95) if (unlocked or selected) else Color(0.392, 0.431, 0.51, 0.6), w)

func _tb_engine_panel(px: float, py: float, ph: float) -> void:
	var up_w := 140.0
	var up_x := px - up_w + 2.0
	draw_rect(Rect2(up_x, py, up_w, ph), Color(0.012, 0.02, 0.063, 0.96))
	draw_rect(Rect2(up_x, py, up_w, ph), Color(0.235, 0.471, 0.863, 0.38), false, 1.0)
	_ctr(f_orb_b, up_x + up_w * 0.5, py + 18.0, "ENGINE", 9, Color(0.549, 0.784, 1.0, 0.88))
	draw_line(Vector2(up_x, py + 25.0), Vector2(up_x + up_w, py + 25.0), Color(0.157, 0.314, 0.627, 0.35), 1.0)
	# Engine sprite.
	if view and view.get("_trains"):
		view._trains.draw_car_strip(self, Rect2(up_x + 20.0, py + 32.0, up_w - 40.0, 66.0), [tb_engine], [true])
	_ctr(f_orb_b, up_x + up_w * 0.5, py + 116.0, String(tb_engine).trim_prefix("engine_").to_upper(), 8, Color(0.706, 0.863, 1.0, 0.92))
	draw_line(Vector2(up_x + 12.0, py + 124.0), Vector2(up_x + up_w - 12.0, py + 124.0), Color(0.157, 0.314, 0.627, 0.25), 1.0)
	# Stats — incl. MAINT (relative wear, lower = better) + REPAIR (cost mult).
	var wear := int(round(float(Tuning.ENGINE_MAINT_DECAY.get(tb_engine, Tuning.MAINT_DECAY_PER_AU)) / Tuning.MAINT_DECAY_PER_AU * 100.0))
	var stats := [
		["SPD", str(int(Tuning.ENGINE_MAX_SPD.get(tb_engine, 4.0))), Color(0.314, 0.863, 1.0, 0.92)],
		["COST", _fmt_cr(int(Tuning.ENGINE_COSTS.get(tb_engine, 10000))), Color(1.0, 0.627, 0.314, 0.92)],
		["MAINT", "%d%% wear" % wear, Color(0.392, 0.863, 0.549, 0.92) if wear <= 60 else Color(1.0, 0.784, 0.314, 0.92)],
		["REPAIR", "x%.1f" % float(Tuning.ENGINE_REPAIR_MULT.get(tb_engine, 1.0)), Color(0.706, 0.784, 0.941, 0.92)],
	]
	var sy := py + 140.0
	for s in stats:
		draw_string(f_orb_b, Vector2(up_x + 14.0, sy), String(s[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(0.392, 0.588, 0.824, 0.75))
		_rt(f_exo, up_x + up_w - 14.0, sy, String(s[1]), 8, s[2])
		sy += 16.0

func _train_status_text(t: Dictionary) -> String:
	if String(t.cargoPhase) == "unloading": return "UNLOADING"
	if String(t.cargoPhase) == "loading": return "LOADING"
	if int(t.phase) == Transit.Phase.TRANSIT: return "IN TRANSIT"
	return "IN ORBIT"

func _train_status(t: Dictionary) -> Array:
	if String(t.cargoPhase) == "unloading": return ["UNLOADING", Color(1.0, 0.65, 0.16, 0.92)]
	if String(t.cargoPhase) == "loading": return ["LOADING", Color(0.24, 0.82, 0.71, 0.92)]
	if int(t.phase) == Transit.Phase.TRANSIT: return ["IN TRANSIT", Color(1.0, 0.78, 0.24, 0.85)]
	return ["IN ORBIT", Color(0.24, 0.86, 0.47, 0.85)]

# ── Simple list popups (Routes / Stations / Registry / Pokedex) ─────────────
func _simple_list(title: String, items: Array) -> void:
	var pw := 446.0
	var ph := 400.0
	var o := _base(pw, ph, Color(0.314, 0.627, 1.0, 0.7))
	var px := o.x
	var py := o.y
	_ctr(f_orb_b, px + pw * 0.5, py + 22.0, title, 13, Color(0.267, 0.667, 1.0))
	_esc_hint(px, py, pw)
	draw_line(Vector2(px, py + 30.0), Vector2(px + pw, py + 30.0), Color(0.157, 0.353, 0.706, 0.35), 1.0)
	if items.is_empty():
		_ctr(f_exo, px + pw * 0.5, py + ph * 0.5, "(none)", 11, Color(0.5, 0.6, 0.8, 0.7))
		return
	var yy := py + 50.0
	for it in items.slice(0, 17):
		draw_string(f_exo, Vector2(px + 24.0, yy), String(it), HORIZONTAL_ALIGNMENT_LEFT, pw - 48.0, 11, Color(0.78, 0.86, 1.0, 0.88))
		yy += 18.5
	if items.size() > 17:
		_ctr(f_exo, px + pw * 0.5, py + ph - 14.0, "+%d more" % (items.size() - 17), 9, Color(0.5, 0.6, 0.8, 0.6))

# ── Unified TRAINS / ROUTES / STATIONS window (build_game.py _drawWindowTabs) ──
const _WIN_TABS := [["trains", "TRAINS", "#ffaa80"], ["routes", "ROUTES", "#7eddc8"], ["stations", "STATIONS", "#7ab8ff"]]

func _win_size(_tab: String) -> Vector2:
	# All three tabs (TRAINS / ROUTES / STATIONS) share ONE size, like the
	# original's WIN_PW=648 / WIN_PH=476 — so switching tabs doesn't resize.
	return Vector2(648.0, 476.0)

func _win_border(tab: String) -> Color:
	match tab:
		"trains": return Color(1.0, 0.627, 0.314, 0.6)
		"routes": return Color(0.392, 0.824, 0.667, 0.6)
		_: return Color(0.471, 0.706, 1.0, 0.6)

func _draw_window(tab: String) -> void:
	var sz := _win_size(tab)
	var pw := sz.x
	var ph := sz.y
	var o := _base(pw, ph, _win_border(tab))
	var px := o.x
	var py := o.y
	# Shared tab row.
	var tw := 96.0
	var th := 22.0
	var ty := py + 5.0
	var tx := px + 12.0
	for entry in _WIN_TABS:
		var tid: String = entry[0]
		var tcol := Color.from_string(String(entry[2]), Color.WHITE)
		var act := tid == tab
		var thov := _hov(Rect2(tx, ty, tw, th)) and not act
		draw_rect(Rect2(tx, ty, tw, th), Color(0.110, 0.204, 0.455, 0.96) if act else (Color(0.071, 0.137, 0.314, 0.9) if thov else Color(0.035, 0.071, 0.180, 0.85)))
		draw_rect(Rect2(tx, ty, tw, th), tcol if act else (Color(0.353, 0.471, 0.706, 0.7) if thov else Color(0.176, 0.294, 0.549, 0.45)), false, 1.6 if act else 1.0)
		_ctr(f_orb_b, tx + tw * 0.5, ty + th * 0.5 + 3.5, String(entry[1]), 10, tcol if act else (Color(0.659, 0.745, 0.902, 0.9) if thov else Color(0.471, 0.588, 0.784, 0.7)))
		_rects["wintab_" + tid] = Rect2(tx, ty, tw, th)
		tx += tw + 4.0
	_esc_hint(px, py, pw)
	# +NEW button (trains / routes).
	if tab == "trains" or tab == "routes":
		var blabel := "+ NEW TRAIN" if tab == "trains" else "+ NEW ROUTE"
		var abw := roundf(f_orb_b.get_string_size(blabel, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x) + 16.0
		var esc_left := px + pw - 10.0 - f_exo.get_string_size("[ESC] close", HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		var abx := esc_left - 7.0 - abw
		_btn(abx, py + 6.0, abw, 18.0, blabel, Color(0.118, 0.627, 0.275, 0.85), Color.WHITE, 9)
		_rects["win_new"] = Rect2(abx, py + 6.0, abw, 18.0)
	draw_line(Vector2(px, py + 30.0), Vector2(px + pw, py + 30.0), Color(_win_border(tab).r, _win_border(tab).g, _win_border(tab).b, 0.4), 1.0)
	match tab:
		"trains": _win_trains(px, py, pw, ph)
		"routes": _win_routes(px, py, pw, ph)
		"stations": _win_stations(px, py, pw, ph)

func _player_trains() -> Array:
	var out: Array = []
	for t in Transit.trains:
		if bool(t.isPlayer):
			out.append(t)
	return out

func _win_trains(px: float, py: float, pw: float, ph: float) -> void:
	var trains := _player_trains()
	var ROW := 162.0
	var ry := py + 34.0
	for i in trains.size():
		var t: Dictionary = trains[i]
		if ry + 40.0 > py + ph:
			break
		if i % 2 == 0:
			draw_rect(Rect2(px + 2.0, ry, pw - 4.0, ROW), Color(0.059, 0.086, 0.196, 0.35))
		if _hov(Rect2(px, ry, pw, ROW)):
			draw_rect(Rect2(px + 2.0, ry, pw - 4.0, ROW), Color(0.157, 0.275, 0.51, 0.28))
		# Name + status badge.
		draw_string(f_orb_b, Vector2(px + 10.0, ry + 24.0), String(t.get("name", "TRAIN %d" % int(t.id))), HORIZONTAL_ALIGNMENT_LEFT, pw - 130.0, 12, Color(1.0, 0.667, 0.533))
		var st := _train_status(t)
		var stw := f_orb_b.get_string_size(st[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
		draw_string(f_orb_b, Vector2(px + pw - 10.0 - stw, ry + 24.0), st[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, st[1])
		# Consist strip.
		var consist: Array = [String(t.engine)]
		for c in t.cars:
			consist.append(String(c))
		var full: Array = [true]
		for c in t.get("carCargo", []):
			full.append(c != null)
		view._trains.draw_car_strip(self, Rect2(px + 10.0, ry + 32.0, pw - 20.0, 50.0), consist, full)
		# Location + car count.
		var loc := "in transit"
		if int(t.get("planetId", -1)) >= 0:
			var lp := _planet_by_id(int(t.planetId))
			var lsid := int(lp.get("starId", -1))
			var ls: Dictionary = Galaxy.stars[lsid] if lsid >= 0 and lsid < Galaxy.stars.size() else {}
			loc = "%s · %s" % [String(lp.get("name", "?")), String(ls.get("name", "?"))]
		draw_string(f_exo, Vector2(px + 10.0, ry + 96.0), loc, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.627, 0.784, 1.0, 0.85))
		draw_string(f_exo, Vector2(px + 10.0, ry + 112.0), "%d cars" % int(t.cars.size()), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.392, 0.588, 0.784, 0.6))
		# Route chain.
		var route := "no route assigned"
		if t.route != null:
			var names: Array = []
			for sid in t.route.stops:
				names.append(String(_planet_by_id(int(sid)).get("name", "?")).to_upper())
			route = "  →  ".join(names)
		draw_string(f_exo, Vector2(px + 10.0, ry + 140.0), route, HORIZONTAL_ALIGNMENT_LEFT, pw - 20.0, 10, Color(0.51, 0.667, 0.882, 0.8))
		_rects["winrow_train_%d" % int(t.id)] = Rect2(px, ry, pw, ROW)
		if i < trains.size() - 1:
			draw_line(Vector2(px, ry + ROW - 2.0), Vector2(px + pw, ry + ROW - 2.0), Color(0.314, 0.196, 0.078, 0.3), 1.0)
		ry += ROW
	# + Add new train pseudo-row.
	if ry + 30.0 < py + ph:
		_ctr(f_orb_b, px + pw * 0.5, ry + 30.0, "+ Add new train", 13, Color(0.51, 0.706, 0.941, 0.80))
		_rects["win_new"] = Rect2(px + 2.0, ry, pw - 4.0, ROW - 2.0)

func _win_routes(px: float, py: float, pw: float, ph: float) -> void:
	var trains: Array = []
	for t in _player_trains():
		if t.route != null and (t.route.stops as Array).size() >= 2:
			trains.append(t)
	if trains.is_empty():
		_ctr(f_exo, px + pw * 0.5, py + 120.0, "No trains assigned to a repeating route yet.", 12, Color(0.6, 0.72, 0.9, 0.8))
		_ctr(f_exo, px + pw * 0.5, py + 142.0, "Plan a route on the map, then ASSIGN TO TRAIN.", 10, Color(0.45, 0.58, 0.78, 0.7))
		return
	# Faithful layout (build_game.py drawRoutesPopup): per-train row with a name
	# column + viz strip up top, then a chain of planet PANES separated by
	# direction arrows, each pane carrying SUPPLY/DEMAND sub-columns (top-8).
	var list_y := py + 34.0
	var list_h := ph - 44.0
	var ROW := 224.0
	var ri := 0
	for t in trains:
		var ry := list_y + ri * ROW
		if ry + 60.0 > list_y + list_h:
			break
		if ri % 2 == 0:
			draw_rect(Rect2(px + 2.0, ry, pw - 4.0, ROW), Color(0.055, 0.118, 0.110, 0.30))
		# Name + status (left column, px+10 .. px+150).
		var tcol := Color.from_string(String(t.get("color", "#7eddc8")), Color(0.494, 0.867, 0.784))
		draw_string(f_orb_b, Vector2(px + 10.0, ry + 24.0), String(t.get("name", "TRAIN %d" % int(t.id))), HORIZONTAL_ALIGNMENT_LEFT, 126.0, 12, tcol)
		var st := _train_status(t)
		draw_string(f_exo, Vector2(px + 10.0, ry + 38.0), st[0], HORIZONTAL_ALIGNMENT_LEFT, 126.0, 9, st[1])
		# Viz strip (top-right).
		var consist: Array = [String(t.engine)]
		for c in t.cars:
			consist.append(String(c))
		var full: Array = [true]
		for c in t.get("carCargo", []):
			full.append(c != null)
		var viz_x0 := px + 150.0
		view._trains.draw_car_strip(self, Rect2(viz_x0, ry + 6.0, (px + pw - 10.0) - viz_x0, 28.0), consist, full)
		# Which stop is the train currently AT (orbit only; mid-transit = none).
		var at_pid := int(t.planetId) if int(t.phase) == 0 else -1
		# Planet panes + arrows.
		var stops: Array = t.route.stops
		var n := stops.size()
		var row_w := pw - 20.0
		var row_x0 := px + 10.0
		var arrow_w := 18.0
		var n4_block_w: float = maxf(40.0, floorf((row_w - 3.0 * arrow_w) / 4.0))
		var n5_block_w: float = maxf(40.0, floorf((row_w - 4.0 * arrow_w) / 5.0))
		var nat_block_w: float = maxf(40.0, floorf((row_w - (n - 1) * arrow_w) / n))
		var block_w: float = maxf(n5_block_w, nat_block_w)
		var sep: String = ">" if (t.route.get("dir", 1) != -1 or bool(t.route.get("isLoop", false))) else "<"
		var badge_y := ry + 62.0
		var stops_y := ry + 82.0
		var pane_top := ry + 67.0
		var pane_h := 127.0
		for bi in n:
			var sp := _planet_by_id(int(stops[bi]))
			if sp.is_empty():
				continue
			var bx := row_x0 + bi * (block_w + arrow_w)
			var is_at := int(sp.id) == at_pid
			# Pane outline.
			draw_rect(Rect2(bx, pane_top, block_w, pane_h), Color(0.235, 0.706, 0.588, 0.22), false, 1.0)
			_rects["winstop_%d" % int(sp.id)] = Rect2(bx, pane_top, block_w, pane_h)
			if is_at:
				_ctr(f_orb_b, bx + block_w * 0.5, badge_y, "IN ORBIT", 7, Color(0.314, 0.863, 0.471, 0.92))
			var pn := String(sp.get("name", "?")).to_upper()
			_ctr(f_exo, bx + block_w * 0.5, stops_y, pn, 11, Color(1.0, 0.863, 0.314, 0.95) if is_at else Color(0.667, 0.863, 0.824, 0.85))
			# SUPPLY / DEMAND sub-columns (top-8).
			var sub_block_w: float = minf(block_w, n4_block_w)
			var inner_w := sub_block_w - 16.0
			var sub_w := floorf((inner_w - 4.0) / 2.0)
			var cluster_x0 := bx + floorf((block_w - sub_block_w) / 2.0)
			var sup_x := cluster_x0 + 8.0
			var dem_x := sup_x + sub_w + 4.0
			var hdr_y := stops_y + 16.0
			var col_y0 := hdr_y + 10.0
			draw_string(f_orb_b, Vector2(sup_x, hdr_y), "SUPPLY", HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(0.314, 0.784, 1.0, 0.70))
			draw_string(f_orb_b, Vector2(dem_x, hdr_y), "DEMAND", HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(1.0, 0.667, 0.235, 0.70))
			var sup_xmark := sup_x + f_orb_b.get_string_size("SUPPL", HORIZONTAL_ALIGNMENT_LEFT, -1, 7).x
			var dem_xmark := dem_x + f_orb_b.get_string_size("DEMAN", HORIZONTAL_ALIGNMENT_LEFT, -1, 7).x
			var sup_e := _pd_sorted_cargo(sp, "supply")
			var dem_e := _pd_sorted_cargo(sp, "demand")
			for ei in mini(8, sup_e.size()):
				var e: Array = sup_e[ei]
				var ey := col_y0 + ei * 10.0
				draw_string(f_exo, Vector2(sup_x, ey), String(_CARGO_SHORT.get(e[0], String(e[0]).substr(0, 5).to_upper())), HORIZONTAL_ALIGNMENT_LEFT, sup_xmark - sup_x - 2.0, 8, Color(0.314, 0.784, 1.0, 0.85))
				draw_string(f_exo, Vector2(sup_xmark, ey), "x%d" % int(floorf(e[1])), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.314, 0.784, 1.0, 0.85))
			if sup_e.is_empty():
				draw_string(f_exo, Vector2(sup_x, col_y0), "none", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.314, 0.588, 0.784, 0.35))
			for ei in mini(8, dem_e.size()):
				var e2: Array = dem_e[ei]
				var ey2 := col_y0 + ei * 10.0
				draw_string(f_exo, Vector2(dem_x, ey2), String(_CARGO_SHORT.get(e2[0], String(e2[0]).substr(0, 5).to_upper())), HORIZONTAL_ALIGNMENT_LEFT, dem_xmark - dem_x - 2.0, 8, Color(1.0, 0.667, 0.235, 0.85))
				draw_string(f_exo, Vector2(dem_xmark, ey2), "x%d" % int(floorf(e2[1])), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1.0, 0.667, 0.235, 0.85))
			if dem_e.is_empty():
				draw_string(f_exo, Vector2(dem_x, col_y0), "none", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.784, 0.510, 0.157, 0.35))
		# Direction arrows between panes.
		var en_route := (at_pid == -1 and int(t.phase) == 1)
		for bi in n - 1:
			var ax := row_x0 + bi * (block_w + arrow_w) + block_w
			if en_route:
				_ctr(f_orb_b, ax + arrow_w * 0.5, badge_y, "EN ROUTE", 7, Color(0.314, 0.863, 0.471, 0.92))
			_ctr(f_orb_b, ax + arrow_w * 0.5, stops_y, sep, 13, Color(0.471, 0.706, 0.627, 0.65))
		# Whole-row click → train details (panes intercept first via winstop_).
		_rects["winrow_train_%d" % int(t.id)] = Rect2(px, ry, pw, ROW)
		if ri > 0:
			draw_line(Vector2(px, ry), Vector2(px + pw, ry), Color(0.157, 0.392, 0.353, 0.25), 1.0)
		ri += 1

func _win_stations(px: float, py: float, pw: float, ph: float) -> void:
	var stations: Array = []
	for p in Galaxy.planets:
		if not bool(p.get("hasStation", false)):
			continue
		if bool(p.get("isAlienRelic", false)) and Discovery.planet_tier(int(p.id)) != Discovery.Tier.VISITED:
			continue
		stations.append(p)
	if stations.is_empty():
		_ctr(f_exo, px + pw * 0.5, py + 120.0, "No stations built yet.", 12, Color(0.6, 0.72, 0.9, 0.8))
		return
	var PANE := 136.0  # original: room for up to 5 supply/5 demand rows
	var ry := py + 36.0
	for i in stations.size():
		var p: Dictionary = stations[i]
		if ry + 30.0 > py + ph:
			break
		if i % 2 == 0:
			draw_rect(Rect2(px + 2.0, ry, pw - 4.0, PANE), Color(0.055, 0.094, 0.212, 0.30))
		var ty2: Dictionary = p.get("type", {})
		# Planet disc (left).
		var dc := Vector2(px + 50.0, ry + PANE * 0.5)
		var bt: Texture2D = view._content.biome_tex(String(ty2.get("id", ""))) if (view and view.get("_content")) else null
		if bt != null:
			draw_texture_rect(bt, Rect2(dc - Vector2(38.0, 38.0), Vector2(76.0, 76.0)), false)
		else:
			draw_circle(dc, 34.0, Color.from_string(String(ty2.get("base", "#888")), Color(0.5, 0.5, 0.5)))
		draw_arc(dc, 42.0, 0.0, TAU, 40, Color(0.42, 0.68, 0.9, 0.5), 1.0)
		# Name · star · tier.
		var nx := px + 104.0
		var rival := bool(p.get("aiHasStation", false))
		var nm := String(p.get("name", "?")) + (" [HOME]" if bool(p.get("isStarter", false)) else "")
		draw_string(f_orb_b, Vector2(nx, ry + 22.0), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.667, 0.843, 1.0, 0.95) if not rival else Color(1.0, 0.66, 0.36, 0.95))
		var sid := int(p.get("starId", -1))
		var star: Dictionary = Galaxy.stars[sid] if sid >= 0 and sid < Galaxy.stars.size() else {}
		var tier_lbl := "TERMINAL" if bool(p.get("hasTerminal", false)) else ("LARGE STATION" if bool(p.get("hasLargeStation", false)) else "STATION")
		draw_string(f_exo, Vector2(nx + f_orb_b.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 8.0, ry + 22.0), "· %s · %s" % [String(star.get("name", "?")), tier_lbl], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.431, 0.608, 0.863, 0.6))
		# SUPPLY / DEMAND.
		draw_string(f_orb_b, Vector2(nx, ry + 42.0), "SUPPLY", HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(0.353, 0.784, 1.0, 0.78))
		draw_string(f_orb_b, Vector2(nx + 220.0, ry + 42.0), "DEMAND", HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(1.0, 0.667, 0.235, 0.78))
		var syy := ry + 48.0
		for e in _pd_sorted_cargo(p, "supply").slice(0, 5):
			var slx: float = view._trains.draw_cargo_strip(self, nx, syy, 22.0, 17.0, e[0], e[1], 3)
			draw_string(f_orb_b, Vector2(slx, syy + 12.0), "×%s" % _fmt_tenth(e[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.588, 0.843, 1.0, 0.92)); syy += 17.0
		syy = ry + 48.0
		for e in _pd_sorted_cargo(p, "demand").slice(0, 5):
			var dlx: float = view._trains.draw_cargo_strip(self, nx + 220.0, syy, 22.0, 17.0, e[0], e[1], 3)
			draw_string(f_orb_b, Vector2(dlx, syy + 12.0), "×%s" % _fmt_tenth(e[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1.0, 0.745, 0.431, 0.92)); syy += 17.0
		_rects["winrow_station_%d" % int(p.id)] = Rect2(px, ry, pw, PANE)
		if i < stations.size() - 1:
			draw_line(Vector2(px, ry + PANE - 1.0), Vector2(px + pw, ry + PANE - 1.0), Color(0.157, 0.314, 0.627, 0.25), 1.0)
		ry += PANE

# ── Train details popup (build_game.py drawTrainPopup) ───────────────────────
func _draw_train_detail() -> void:
	var tid := int(state.get("trainIdx", -1))
	if tid < 0:
		# Opened via double-click / galaxy — derive from the current selection.
		var sel: Dictionary = GameState.selected
		if String(sel.get("kind", "")) == "train":
			tid = int(String(sel.get("id", "")).trim_prefix("train_"))
	var t: Dictionary = {}
	for tt in Transit.trains:
		if int(tt.id) == tid:
			t = tt; break
	if t.is_empty():
		_close(); return
	var pw := 430.0
	var ph := 430.0
	var o := _base(pw, ph, Color(1.0, 0.627, 0.314, 0.6))
	var px := o.x
	var py := o.y
	# Colour square + name.
	draw_rect(Rect2(px + 14.0, py + 10.0, 16.0, 16.0), Color.from_string(String(t.get("color", "#44aaff")), Color(0.27, 0.67, 1.0)))
	draw_rect(Rect2(px + 14.0, py + 10.0, 16.0, 16.0), Color(1, 1, 1, 0.35), false, 1.5)
	draw_string(f_orb_b, Vector2(px + 38.0, py + 23.0), String(t.get("name", "TRAIN %d" % tid)), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 0.667, 0.533))
	_esc_hint(px, py, pw)
	draw_line(Vector2(px, py + 44.0), Vector2(px + pw, py + 44.0), Color(0.216, 0.333, 0.549, 0.45), 1.0)
	# Consist strip + EDIT TRAIN.
	var consist: Array = [String(t.engine)]
	for c in t.cars:
		consist.append(String(c))
	var full: Array = [true]
	for c in t.get("carCargo", []):
		full.append(c != null)
	view._trains.draw_car_strip(self, Rect2(px + 14.0, py + 52.0, pw - 28.0, 42.0), consist, full)
	_rt(f_orb_b, px + pw - 16.0, py + 90.0, "EDIT TRAIN", 9, Color(0.588, 0.765, 0.922, 0.72))
	_rects["td_edit"] = Rect2(px + 14.0, py + 52.0, pw - 28.0, 42.0)
	draw_line(Vector2(px, py + 104.0), Vector2(px + pw, py + 104.0), Color(0.216, 0.333, 0.549, 0.45), 1.0)
	# AT A GLANCE.
	draw_string(f_orb_b, Vector2(px + 16.0, py + 124.0), "AT A GLANCE", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.431, 0.667, 0.902, 0.92))
	var loc := "in transit"
	if int(t.get("planetId", -1)) >= 0:
		var lp := _planet_by_id(int(t.planetId))
		var lsid := int(lp.get("starId", -1))
		var ls: Dictionary = Galaxy.stars[lsid] if lsid >= 0 and lsid < Galaxy.stars.size() else {}
		loc = "%s · %s" % [String(lp.get("name", "?")), String(ls.get("name", "?"))]
	draw_string(f_exo, Vector2(px + 16.0, py + 146.0), "LOCATION", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.431, 0.667, 0.902, 0.92))
	draw_string(f_exo, Vector2(px + 80.0, py + 146.0), loc, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.588, 0.706, 0.863, 0.85))
	draw_string(f_exo, Vector2(px + 16.0, py + 166.0), "CARS", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.431, 0.667, 0.902, 0.92))
	draw_string(f_exo, Vector2(px + 80.0, py + 166.0), str(int(t.cars.size())), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.871, 0.894, 0.941, 0.96))
	var st := _train_status(t)
	draw_string(f_exo, Vector2(px + 16.0, py + 186.0), "STATUS", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.431, 0.667, 0.902, 0.92))
	draw_string(f_exo, Vector2(px + 80.0, py + 186.0), st[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, st[1])
	var div := Color(0.216, 0.333, 0.549, 0.45)
	var bar_x := px + 16.0
	var bar_w := 200.0
	# ── MAINTENANCE bar (build_game.py:23247) ──
	draw_line(Vector2(px, py + 210.0), Vector2(px + pw, py + 210.0), div, 1.0)
	var maint: float = float(t.get("maintenance", 1.0))
	var mcol := Color(0.314, 0.863, 0.471) if maint >= 0.75 else (Color(1.0, 0.784, 0.235) if maint >= 0.40 else Color(0.863, 0.314, 0.314))
	draw_string(f_orb_b, Vector2(px + 16.0, py + 228.0), "MAINTENANCE", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.471, 0.706, 0.902, 0.85))
	draw_rect(Rect2(bar_x, py + 234.0, bar_w, 8.0), Color(0.039, 0.078, 0.176, 0.8))
	draw_rect(Rect2(bar_x, py + 234.0, bar_w * maint, 8.0), mcol)
	draw_string(f_exo, Vector2(bar_x + bar_w + 10.0, py + 242.0), "%d%% · %d SU since service" % [int(round(maint * 100.0)), int(round(float(t.get("distSinceMaint", 0.0))))], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.6, 0.72, 0.85, 0.8))
	# ── ENGINE AGE bar (build_game.py:23262) ──
	var failed := bool(t.get("_engineFailed", false))
	var born: float = float(t.get("_engineBornSd", GameState.stardate - 15.0))
	var fail_sd: float = float(t.get("_engineFailureSd", GameState.stardate + 15.0))
	var life: float = maxf(0.0001, fail_sd - born)
	var age_frac: float = clampf((fail_sd - GameState.stardate) / life, 0.0, 1.0)
	var sd_left: float = maxf(0.0, fail_sd - GameState.stardate)
	var acol := Color(0.314, 0.863, 0.471) if age_frac >= 0.5 else (Color(1.0, 0.784, 0.235) if age_frac >= 0.2 else Color(0.863, 0.314, 0.314))
	draw_string(f_orb_b, Vector2(px + 16.0, py + 262.0), "ENGINE AGE", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.471, 0.706, 0.902, 0.85))
	draw_rect(Rect2(bar_x, py + 268.0, bar_w, 8.0), Color(0.039, 0.078, 0.176, 0.8))
	draw_rect(Rect2(bar_x, py + 268.0, bar_w * age_frac, 8.0), acol)
	draw_string(f_exo, Vector2(bar_x + bar_w + 10.0, py + 276.0), "engine failed — replace" if failed else "%.1f SD until breakdown" % sd_left, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.863, 0.314, 0.314, 0.9) if failed else Color(0.6, 0.72, 0.85, 0.8))
	# ── FINANCIAL PERFORMANCE (build_game.py:23080) ──
	draw_line(Vector2(px, py + 290.0), Vector2(px + pw, py + 290.0), div, 1.0)
	draw_string(f_orb_b, Vector2(px + 16.0, py + 310.0), "FINANCIAL PERFORMANCE", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.471, 0.706, 0.902, 0.85))
	var rev := int(t.get("totalRevenue", 0))
	var cost := int(t.get("totalCosts", 0))
	var profit := rev - cost
	var fin := [
		["REVENUE", "+ %s cr" % _fmt_cr(rev), Color(0.392, 0.863, 0.549)],
		["COSTS", "- %s cr" % _fmt_cr(cost), Color(0.863, 0.392, 0.392)],
		["PROFIT", ("- " if profit < 0 else "+ ") + "%s cr" % _fmt_cr(abs(profit)), Color(0.392, 0.902, 0.588) if profit >= 0 else Color(0.902, 0.353, 0.353)],
	]
	var fy := py + 332.0
	for f in fin:
		draw_string(f_exo, Vector2(px + 24.0, fy), String(f[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.55, 0.68, 0.85, 0.8))
		_rt(f_orb_b, px + pw - 24.0, fy, String(f[1]), 11, f[2])
		fy += 22.0

# ── Missions popup ([M], build_game.py drawMissionsPopup) ────────────────────
# Faithful to build_game.py drawMissionsPopup (480×360, green): glow title +
# status line + active-first cards w/ ○/✓ checkboxes + reward pill, then completed.
func _draw_missions() -> void:
	var pw := 480.0
	var ph := 360.0
	var o := _base(pw, ph, Color(0.314, 0.784, 0.510, 0.7))
	var px := o.x
	var py := o.y
	# Green glow title.
	for off in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
		_ctr(f_orb_b, px + pw * 0.5 + off.x, py + 23.0 + off.y, "MISSIONS", 12, Color(0.157, 0.784, 0.471, 0.5))
	_ctr(f_orb_b, px + pw * 0.5, py + 23.0, "MISSIONS", 12, Color(0.549, 0.961, 0.745))
	_esc_hint(px, py, pw)
	# Status line.
	var n_act := Missions.active.size()
	var n_done := Missions.completed.size()
	draw_string(f_exo, Vector2(px + 10.0, py + 23.0), "%d active" % n_act, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.392, 0.843, 0.588, 0.75))
	var aw := f_exo.get_string_size("%d active" % n_act, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
	draw_string(f_exo, Vector2(px + 10.0 + aw, py + 23.0), " · %d completed" % n_done, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.431, 0.439, 0.463, 0.65))
	draw_line(Vector2(px, py + 32.0), Vector2(px + pw, py + 32.0), Color(0.314, 0.784, 0.510, 0.28), 1.0)
	var yy := py + 42.0
	if n_act == 0 and n_done == 0:
		_ctr(f_exo, px + pw * 0.5, yy + 20.0, "No missions yet.", 11, Color(0.6, 0.72, 0.65, 0.8))
	# Active cards.
	for m in Missions.active:
		var def := Missions.def_for(String(m.id))
		var objs: Array = m.objectives
		var card_h := 38.0 + objs.size() * 16.0
		if yy + card_h > py + ph - 24.0:
			break
		draw_rect(Rect2(px + 14.0, yy, pw - 28.0, card_h), Color(0.027, 0.094, 0.055, 0.6))
		draw_rect(Rect2(px + 14.0, yy, pw - 28.0, card_h), Color(0.235, 0.627, 0.392, 0.4), false, 1.0)
		draw_string(f_orb_b, Vector2(px + 24.0, yy + 18.0), String(def.get("name", String(m.id))), HORIZONTAL_ALIGNMENT_LEFT, pw - 130.0, 11, Color(1.0, 0.878, 0.502))
		var rw := int(def.get("reward", 0))
		if rw > 0:
			_rt(f_orb_b, px + pw - 24.0, yy + 18.0, "+ %s cr" % _fmt_cr(rw), 9, Color(0.392, 0.863, 0.510))
		var def_objs: Array = def.get("objectives", [])
		var oy := yy + 36.0
		for ob in objs:
			var done := bool(ob.get("done", false))
			var otext := ""
			for d in def_objs:
				if String(d.get("id", "")) == String(ob.get("id", "")):
					otext = String(d.get("text", "")); break
			# ○ / ✓ checkbox glyph.
			var gc := Color(0.314, 0.863, 0.471, 0.95) if done else Color(0.471, 0.549, 0.627, 0.8)
			draw_arc(Vector2(px + 31.0, oy + 4.0), 5.0, 0.0, TAU, 14, gc, 1.2)
			if done:
				draw_line(Vector2(px + 28.5, oy + 4.0), Vector2(px + 30.5, oy + 6.5), gc, 1.6)
				draw_line(Vector2(px + 30.5, oy + 6.5), Vector2(px + 34.0, oy + 1.0), gc, 1.6)
			draw_string(f_exo, Vector2(px + 42.0, oy + 8.0), otext, HORIZONTAL_ALIGNMENT_LEFT, pw - 70.0, 10, Color(0.471, 0.627, 0.510, 0.7) if done else Color(0.745, 0.824, 0.784, 0.88))
			oy += 16.0
		yy += card_h + 8.0
	# Completed section (dimmed) — the port tracks completed as a set of ids.
	if n_done > 0 and yy < py + ph - 30.0:
		draw_line(Vector2(px + 14.0, yy), Vector2(px + pw - 14.0, yy), Color(0.235, 0.471, 0.353, 0.3), 1.0)
		yy += 14.0
		for cid in Missions.completed.keys():
			if yy > py + ph - 18.0:
				break
			var cd := Missions.def_for(String(cid))
			draw_arc(Vector2(px + 24.0, yy + 1.0), 5.0, 0.0, TAU, 14, Color(0.314, 0.706, 0.431, 0.7), 1.2)
			draw_line(Vector2(px + 21.5, yy + 1.0), Vector2(px + 23.5, yy + 3.5), Color(0.314, 0.706, 0.431, 0.7), 1.4)
			draw_line(Vector2(px + 23.5, yy + 3.5), Vector2(px + 27.0, yy - 2.0), Color(0.314, 0.706, 0.431, 0.7), 1.4)
			draw_string(f_exo, Vector2(px + 36.0, yy + 5.0), String(cd.get("name", String(cid))), HORIZONTAL_ALIGNMENT_LEFT, pw - 60.0, 10, Color(0.471, 0.549, 0.510, 0.6))
			yy += 18.0

# ── Leaderboard ([L], build_game.py drawLeaderboardPopup §2819) ──────────────
# Faithful port of build_game.py drawLeaderboardPopup (624×414). Renders the
# REAL online top-100 from Leaderboard.rows for the current sort metric, with
# clickable metric headers (re-sort = refetch) + page arrows.
const _LB_PW := 624.0
const _LB_PH := 414.0
const _LB_WEIGHTS := [0.7, 2.35, 1.4, 0.98, 0.98, 1.05, 0.85, 1.0, 0.95]

func _lb_col_x(px: float) -> Array:
	var table_x := px + 12.0
	var table_w := _LB_PW - 24.0
	var wsum := 0.0
	for w in _LB_WEIGHTS:
		wsum += w
	var col_x: Array = []
	var cx := table_x
	for w in _LB_WEIGHTS:
		col_x.append(cx)
		cx += w / wsum * table_w
	col_x.append(table_x + table_w)
	return col_x

func _draw_leaderboard() -> void:
	var pw := _LB_PW
	var ph := _LB_PH
	var o := _base(pw, ph, Color(0.667, 0.471, 1.0, 0.7))
	var px := o.x
	var py := o.y
	_ctr(f_orb_b, px + pw * 0.5, py + 22.0, "ALL-TIME HIGH SCORES", 12, Color(0.831, 0.753, 1.0, 0.97))
	draw_string(f_exo, Vector2(px + 12.0, py + 22.0), "sorted by " + Leaderboard.metric_label(Leaderboard.metric), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.667, 0.627, 0.804, 0.7))
	_esc_hint(px, py, pw)
	var table_x := px + 12.0
	var table_w := pw - 24.0
	var col_x := _lb_col_x(px)
	var head_y := py + 44.0
	var table_top := head_y + 20.0
	var row_h: float = minf(26.0, (ph - 100.0 - (head_y - py)) / 10.0)
	# Header row: rank, CORPORATION, then the 7 metric columns (clickable).
	draw_string(f_orb_b, Vector2((col_x[0] + col_x[1]) * 0.5 - 4.0, head_y + 10.0), "#", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.627, 0.647, 0.765, 0.85))
	draw_string(f_orb_b, Vector2(col_x[1] + 4.0, head_y + 10.0), "CORPORATION", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.627, 0.647, 0.765, 0.85))
	for m in Leaderboard.METRICS.size():
		var md: Dictionary = Leaderboard.METRICS[m]
		var ci := 2 + m
		var lx: float = col_x[ci]
		var rx: float = col_x[ci + 1]
		var active_col := Leaderboard.metric == String(md.col)
		var hhov := _hov(Rect2(lx, head_y - 10.0, rx - lx, 24.0)) and not active_col
		if active_col:
			draw_rect(Rect2(lx, head_y - 10.0, rx - lx, 24.0), Color(0.510, 0.373, 0.824, 0.34))
		elif hhov:
			draw_rect(Rect2(lx, head_y - 10.0, rx - lx, 24.0), Color(0.392, 0.294, 0.627, 0.22))
		_ctr(f_orb_b, (lx + rx) * 0.5, head_y + 10.0, String(md.short) + (" v" if active_col else ""), 9, Color(0.902, 0.812, 1.0) if active_col else (Color(0.847, 0.816, 0.953) if hhov else Color(0.627, 0.647, 0.765, 0.85)))
		_rects["lbhdr_%s" % String(md.col)] = Rect2(lx, head_y - 10.0, rx - lx, 24.0)
	draw_line(Vector2(table_x, head_y + 18.0), Vector2(table_x + table_w, head_y + 18.0), Color(0.510, 0.431, 0.745, 0.5), 1.0)
	# Body: status message or the 10-row page.
	if Leaderboard.status != "ok":
		var msg := "Loading leaderboard…"
		var col := Color(0.804, 0.804, 0.882, 0.85)
		if Leaderboard.status == "error":
			msg = "Could not reach the leaderboard."; col = Color(1.0, 0.588, 0.588, 0.9)
		elif Leaderboard.status == "empty":
			msg = "No entries yet — be the first!"
		_ctr(f_exo, px + pw * 0.5, table_top + 70.0, msg, 12, col)
	else:
		var start := Leaderboard.page * 10
		for r in 10:
			var idx := start + r
			if idx >= Leaderboard.rows.size():
				break
			var row: Dictionary = Leaderboard.rows[idx]
			var ry := table_top + r * row_h
			var ty := ry + row_h * 0.5 + 4.0
			var mine: bool = Leaderboard.corp_id != "" and String(row.get("corp_id", "")) == Leaderboard.corp_id
			draw_rect(Rect2(table_x, ry, table_w, row_h), Color(0.392, 0.282, 0.706, 0.42) if mine else (Color(1, 1, 1, 0.025) if r % 2 == 0 else Color(1, 1, 1, 0.06)))
			var rankcol := Color(0.745, 0.765, 0.843, 0.9)
			if idx == 0: rankcol = Color(1.0, 0.835, 0.290)
			elif idx == 1: rankcol = Color(0.812, 0.847, 0.902)
			elif idx == 2: rankcol = Color(0.847, 0.627, 0.416)
			_ctr(f_orb_b, (col_x[0] + col_x[1]) * 0.5 - 4.0, ty, "#%d" % (idx + 1), 11, rankcol)
			var nm := String(row.get("corp_name", "?"))
			draw_string(f_orb_b if mine else f_orb, Vector2(col_x[1] + 4.0, ty), nm, HORIZONTAL_ALIGNMENT_LEFT, col_x[2] - col_x[1] - 8.0, 11, Color.WHITE if mine else Color(0.894, 0.894, 0.949, 0.95))
			for m2 in Leaderboard.METRICS.size():
				var md2: Dictionary = Leaderboard.METRICS[m2]
				var ci2 := 2 + m2
				var act2 := Leaderboard.metric == String(md2.col)
				_ctr(f_orb_b if act2 else f_exo, (col_x[ci2] + col_x[ci2 + 1]) * 0.5, ty, Leaderboard.fmt_cell(row, String(md2.col)), 10, Color(0.918, 0.847, 1.0) if act2 else Color(0.792, 0.812, 0.890, 0.85))
	# Footer: "Ranks X–Y of Z" with bare-triangle prev/next page arrows.
	if Leaderboard.status == "ok":
		var rk_y := py + ph - 30.0
		var lo := Leaderboard.page * 10 + 1
		var hi: int = mini(Leaderboard.rows.size(), Leaderboard.page * 10 + 10)
		var rk_txt := "Ranks %d-%d of %d" % [lo, hi, Leaderboard.rows.size()]
		_ctr(f_exo, px + pw * 0.5, rk_y + 4.0, rk_txt, 11, Color(0.745, 0.765, 0.863, 0.82))
		var rk_half := f_exo.get_string_size(rk_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x * 0.5
		var cy := rk_y
		var prev_en := Leaderboard.page > 0
		var next_en := Leaderboard.page < Leaderboard.max_page()
		var pcx := px + pw * 0.5 - rk_half - 18.0
		_lb_tri(pcx, cy, false, prev_en)
		if prev_en: _rects["lb_prev"] = Rect2(pcx - 15.0, cy - 15.0, 30.0, 30.0)
		var ncx := px + pw * 0.5 + rk_half + 18.0
		_lb_tri(ncx, cy, true, next_en)
		if next_en: _rects["lb_next"] = Rect2(ncx - 15.0, cy - 15.0, 30.0, 30.0)

func _lb_tri(cx: float, cy: float, right: bool, enabled: bool) -> void:
	var s := 8.0
	var hov := enabled and _hov(Rect2(cx - 15.0, cy - 15.0, 30.0, 30.0))
	var col := (Color(0.85, 0.78, 1.0, 1.0) if hov else Color(0.627, 0.549, 0.882, 0.85)) if enabled else Color(0.431, 0.431, 0.510, 0.38)
	var pts: PackedVector2Array
	if right:
		pts = PackedVector2Array([Vector2(cx - s * 0.5, cy - s), Vector2(cx + s * 0.5, cy), Vector2(cx - s * 0.5, cy + s)])
	else:
		pts = PackedVector2Array([Vector2(cx + s * 0.5, cy - s), Vector2(cx - s * 0.5, cy), Vector2(cx + s * 0.5, cy + s)])
	draw_colored_polygon(pts, col)

# ── Star detail popup (build_game.py activePopup==='star') ───────────────────
func _draw_star_popup() -> void:
	var sel: Dictionary = GameState.selected
	var sid := int(String(sel.get("id", "")).trim_prefix("star_")) if String(sel.get("kind", "")) == "star" else -1
	if sid < 0 or sid >= Galaxy.stars.size():
		_close(); return
	var s: Dictionary = Galaxy.stars[sid]
	var pal: Dictionary = Tuning.STAR_COLORS.get(String(s.get("colorName", "yellow")), Tuning.STAR_COLORS["yellow"])
	var core := Color.from_string(String(pal["core"]), Color.WHITE)
	var pw := 440.0
	var ph := 320.0
	var o := _base(pw, ph, core)
	var px := o.x
	var py := o.y
	draw_string(f_orb_b, Vector2(px + 16.0, py + 24.0), String(s.get("name", "?")), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, core)
	_esc_hint(px, py, pw)
	draw_line(Vector2(px, py + 32.0), Vector2(px + pw, py + 32.0), Color(0.3, 0.3, 0.4, 0.4), 1.0)
	# Star disc.
	draw_circle(Vector2(px + 64.0, py + 96.0), 40.0, core)
	draw_arc(Vector2(px + 64.0, py + 96.0), 48.0, 0.0, TAU, 40, Color(core.r, core.g, core.b, 0.3), 6.0)
	# Stats.
	var lx := px + 130.0
	var c8 := Color(0.533, 0.733, 0.8)
	draw_string(f_exo, Vector2(lx, py + 60.0), "Type: %s STAR" % String(s.get("colorName", "")).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, c8)
	draw_string(f_exo, Vector2(lx, py + 80.0), "Coords: (%d, %d)" % [int(round(float(s.get("x", 0.0)) / 100.0)), int(round(float(s.get("y", 0.0)) / 100.0))], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, c8)
	draw_string(f_exo, Vector2(lx, py + 100.0), "Radius: %d SU" % int(s.get("radius", 0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, c8)
	var pids: Array = s.get("planetIds", [])
	draw_string(f_exo, Vector2(lx, py + 120.0), "%d planet%s in system" % [pids.size(), "" if pids.size() == 1 else "s"], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, c8)
	# Planet strip.
	draw_string(f_orb_b, Vector2(px + 16.0, py + 160.0), "PLANETS", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.5, 0.7, 0.95, 0.8))
	var stx := px + 24.0
	for pid in pids:
		if stx + 30.0 > px + pw - 16.0:
			break
		var pp: Dictionary = Galaxy.planets[int(pid)] if int(pid) < Galaxy.planets.size() else {}
		if pp.is_empty():
			continue
		# Each disc is clickable → opens that planet's detail (build_game.py star popup).
		var pr := Rect2(stx - 16.0, py + 174.0, 32.0, 32.0)
		_rects["starplanet_%d" % int(pid)] = pr
		if _hov(pr):
			draw_arc(Vector2(stx, py + 190.0), 17.0, 0.0, TAU, 20, Color(1.0, 0.9, 0.5, 0.85), 1.5)
		if Discovery.planet_tier(int(pid)) == Discovery.Tier.UNKNOWN:
			draw_circle(Vector2(stx, py + 190.0), 14.0, Color(0.12, 0.16, 0.26, 0.85))
			_ctr(f_exo, stx, py + 195.0, "?", 12, Color(0.55, 0.65, 0.85, 0.8), 28.0)
		else:
			var bt: Texture2D = view._content.biome_tex(String((pp.get("type", {}) as Dictionary).get("id", ""))) if (view and view.get("_content")) else null
			if bt != null:
				draw_texture_rect(bt, Rect2(Vector2(stx - 14.0, py + 176.0), Vector2(28.0, 28.0)), false)
			_ctr(f_exo, stx, py + 218.0, String(pp.get("name", "?")).substr(0, 8), 8, Color(0.7, 0.82, 1.0, 0.75), 56.0)
		stx += 58.0

# ── Quit confirm (build_game.py drawQuitConfirmPopup 17512): 390×110, 3 buttons.
func _draw_quitconfirm() -> void:
	var pw := 390.0
	var ph := 110.0
	var o := _base(pw, ph, Color(0.88, 0.4, 0.3, 0.8))
	var px := o.x
	var py := o.y
	_ctr(f_orb_b, px + pw * 0.5, py + 26.0, "QUIT TO MAIN MENU?", 11, Color(1.0, 0.706, 0.706))
	_ctr(f_exo, px + pw * 0.5, py + 46.0, "Save first, or your progress will be lost.", 10, Color(0.7, 0.75, 0.85, 0.85))
	# Three buttons: YES, QUIT (red) | SAVE GAME (green) | NO, STAY (blue).
	var bw := 100.0
	var bh := 26.0
	var gap := 10.0
	var total := bw * 3.0 + gap * 2.0
	var bx := px + (pw - total) * 0.5
	var by := py + ph - bh - 14.0
	_btn(bx, by, bw, bh, "YES, QUIT", Color(0.392, 0.110, 0.110, 0.9), Color(1.0, 0.7, 0.66, 0.95), 9)
	_rects["quit_yes"] = Rect2(bx, by, bw, bh)
	_btn(bx + bw + gap, by, bw, bh, "SAVE GAME", Color(0.071, 0.353, 0.196, 0.9), Color(0.706, 1.0, 0.784, 0.95), 9)
	_rects["quit_save"] = Rect2(bx + bw + gap, by, bw, bh)
	_btn(bx + (bw + gap) * 2.0, by, bw, bh, "NO, STAY", Color(0.08, 0.18, 0.34, 0.9), Color(0.7, 0.85, 1.0, 0.95), 9)
	_rects["quit_no"] = Rect2(bx + (bw + gap) * 2.0, by, bw, bh)

func _draw_registry() -> void:
	_registry_window(true)

func _draw_pokedex() -> void:
	_registry_window(false)

# Faithful PLANETS/STARS registry (build_game.py drawPokedex 21890 / drawStarRegistry 22007).
# Shared 460×390 window with a PLANETS/STARS tab bar; blue for planets, amber for stars.
func _registry_window(is_stars: bool) -> void:
	var pw := 460.0
	var ph := 390.0
	var border := Color(1.0, 0.706, 0.235, 0.7) if is_stars else Color(0.314, 0.627, 1.0, 0.7)
	var accent := Color(1.0, 0.706, 0.235) if is_stars else Color(0.314, 0.627, 1.0)
	var o := _base(pw, ph, border)
	var px := o.x
	var py := o.y
	# Tab bar PLANETS / STARS.
	var tw := 92.0
	var th := 22.0
	var ty := py + 6.0
	_reg_tab(px + 14.0, ty, tw, th, "PLANETS", not is_stars, "regtab_planets")
	_reg_tab(px + 14.0 + tw + 4.0, ty, tw, th, "STARS", is_stars, "regtab_stars")
	_esc_hint(px, py, pw)
	# VISITED ONLY checkbox (right of the tabs).
	var cb := Rect2(px + pw - 132.0, ty + 5.0, 12.0, 12.0)
	var cb_hov := _hov(Rect2(cb.position.x - 4.0, cb.position.y - 2.0, 124.0, 16.0))
	draw_rect(cb, Color(0.039, 0.063, 0.118, 0.9))
	draw_rect(cb, Color(accent.r, accent.g, accent.b, 0.85 if cb_hov else 0.55), false, 1.0)
	if _reg_visited_only:
		draw_line(cb.position + Vector2(2.0, 6.0), cb.position + Vector2(5.0, 9.5), accent, 1.6)
		draw_line(cb.position + Vector2(5.0, 9.5), cb.position + Vector2(10.0, 2.5), accent, 1.6)
	draw_string(f_exo, Vector2(px + pw - 116.0, ty + 15.0), "VISITED ONLY", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(accent.r, accent.g, accent.b, 0.95 if cb_hov else 0.7))
	_rects["reg_visited"] = Rect2(cb.position.x - 4.0, cb.position.y - 2.0, 124.0, 16.0)
	draw_line(Vector2(px, py + 34.0), Vector2(px + pw, py + 34.0), Color(accent.r, accent.g, accent.b, 0.35), 1.0)
	# Build the row list.
	var rows: Array = []
	if is_stars:
		for s in Galaxy.stars:
			if _reg_visited_only and not Discovery.is_star_revealed(int(s.id)):
				continue
			rows.append(s)
		# Discovered first (registry of what you've found), then by size.
		rows.sort_custom(func(a, b):
			var ra := Discovery.is_star_revealed(int(a.id))
			var rb := Discovery.is_star_revealed(int(b.id))
			if ra != rb: return ra
			return int(b.get("radius", 0)) < int(a.get("radius", 0)))
	else:
		for p in Galaxy.planets:
			if bool(p.get("isAlienRelic", false)) and Discovery.planet_tier(int(p.id)) != Discovery.Tier.VISITED:
				continue
			if _reg_visited_only and Discovery.planet_tier(int(p.id)) != Discovery.Tier.VISITED:
				continue
			rows.append(p)
		rows.sort_custom(func(a, b):
			var va := Discovery.planet_tier(int(a.id)) == Discovery.Tier.VISITED
			var vb := Discovery.planet_tier(int(b.id)) == Discovery.Tier.VISITED
			if va != vb: return va
			return int(b.get("radius", 0)) < int(a.get("radius", 0)))
	var list_y := py + 40.0
	var list_h := ph - 50.0
	var row_h := 38.0 if is_stars else 35.0
	var max_scroll: float = maxf(0.0, rows.size() * row_h - list_h)
	_reg_scroll = clampf(_reg_scroll, 0.0, max_scroll)
	if rows.is_empty():
		_ctr(f_exo, px + pw * 0.5, list_y + list_h * 0.5, "Nothing discovered yet.", 12, Color(0.5, 0.6, 0.8, 0.6))
	for ri in rows.size():
		var ry := list_y + ri * row_h - _reg_scroll
		if ry + row_h < list_y or ry > list_y + list_h:
			continue
		var item: Dictionary = rows[ri]
		var rr := Rect2(px + 4.0, ry, pw - 8.0, row_h - 2.0)
		var hovr := _hov(rr)
		if hovr:
			draw_rect(rr, Color(accent.r, accent.g, accent.b, 0.14))
		elif ri % 2 == 0:
			draw_rect(rr, Color(0.059, 0.098, 0.216, 0.4))
		# Rank.
		draw_string(f_orb_b, Vector2(px + 14.0, ry + row_h * 0.5 + 4.0), "#%d" % (ri + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.6, 0.65, 0.8, 0.85))
		var dc := Vector2(px + 56.0, ry + row_h * 0.5)
		var nx := px + 76.0
		if is_stars:
			var revealed := Discovery.is_star_revealed(int(item.id))
			var pal: Dictionary = Tuning.STAR_COLORS.get(String(item.get("colorName", "yellow")), Tuning.STAR_COLORS["yellow"])
			var core := Color.from_string(String(pal["core"]), Color.WHITE)
			if revealed:
				draw_circle(dc, 9.0, core)
				draw_arc(dc, 12.0, 0.0, TAU, 16, Color(core.r, core.g, core.b, 0.4), 2.0)
				var nm := String(item.get("name", "?")) + (" [HOME]" if int(item.id) == Galaxy.home_star_id else "")
				draw_string(f_orb_b, Vector2(nx, ry + 15.0), nm, HORIZONTAL_ALIGNMENT_LEFT, pw - 100.0, 11, Color(1.0, 0.816, 0.502))
				draw_string(f_exo, Vector2(nx, ry + 29.0), "%s · %d planet%s" % [String(item.get("colorName", "")).to_upper(), (item.get("planetIds", []) as Array).size(), "" if (item.get("planetIds", []) as Array).size() == 1 else "s"], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.533, 0.733, 0.8))
			else:
				draw_circle(dc, 9.0, Color(0.12, 0.16, 0.26, 0.9))
				draw_string(f_orb_b, Vector2(nx, ry + 22.0), "??? UNKNOWN ???", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.4, 0.45, 0.6, 0.7))
		else:
			var visited := Discovery.planet_tier(int(item.id)) == Discovery.Tier.VISITED
			if visited:
				var bt: Texture2D = view._content.biome_tex(String((item.get("type", {}) as Dictionary).get("id", ""))) if (view and view.get("_content")) else null
				if bt != null:
					draw_texture_rect(bt, Rect2(dc - Vector2(10.0, 10.0), Vector2(20.0, 20.0)), false)
				else:
					draw_circle(dc, 10.0, Color.from_string(String((item.get("type", {}) as Dictionary).get("base", "#888")), Color(0.5, 0.5, 0.5)))
				var sid := int(item.get("starId", -1))
				var star: Dictionary = Galaxy.stars[sid] if sid >= 0 and sid < Galaxy.stars.size() else {}
				var nm := String(item.get("name", "?")) + (" [HOME]" if bool(item.get("isStarter", false)) else "")
				draw_string(f_orb_b, Vector2(nx, ry + 15.0), nm, HORIZONTAL_ALIGNMENT_LEFT, pw - 100.0, 11, Color(0.667, 0.8, 1.0))
				draw_string(f_exo, Vector2(nx, ry + 29.0), "%s · %s · %s" % [String((item.get("type", {}) as Dictionary).get("id", "")).to_upper(), String(item.get("size", "M")), String(star.get("name", "?"))], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.533, 0.733, 0.8))
			else:
				draw_circle(dc, 10.0, Color(0.016, 0.024, 0.063, 0.95))
				draw_string(f_orb_b, Vector2(nx, ry + 22.0), "??? UNKNOWN ???", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.4, 0.45, 0.6, 0.7))
	# Scrollbar.
	if max_scroll > 0.0:
		var sb_x := px + pw - 7.0
		var thumb_h: float = maxf(20.0, list_h * (list_h / (rows.size() * row_h)))
		var thumb_y := list_y + (_reg_scroll / max_scroll) * (list_h - thumb_h)
		draw_rect(Rect2(sb_x, list_y, 5.0, list_h), Color(accent.r, accent.g, accent.b, 0.12))
		draw_rect(Rect2(sb_x, thumb_y, 5.0, thumb_h), Color(accent.r, accent.g, accent.b, 0.5))

func _reg_tab(x: float, y: float, w: float, h: float, label: String, active: bool, key: String) -> void:
	var hov := _hov(Rect2(x, y, w, h)) and not active
	draw_rect(Rect2(x, y, w, h), Color(0.110, 0.204, 0.455, 0.96) if active else (Color(0.071, 0.137, 0.314, 0.9) if hov else Color(0.035, 0.071, 0.180, 0.85)))
	draw_rect(Rect2(x, y, w, h), Color(0.471, 0.706, 1.0, 0.8) if active else Color(0.176, 0.294, 0.549, 0.45), false, 1.4 if active else 1.0)
	_ctr(f_orb_b, x + w * 0.5, y + h * 0.5 + 3.5, label, 9, Color(0.78, 0.88, 1.0) if active else (Color(0.6, 0.7, 0.86, 0.9) if hov else Color(0.471, 0.588, 0.784, 0.7)))
	_rects[key] = Rect2(x, y, w, h)

# ── Tech tree [I] (build_game.py drawTechTreePopup 26374) ────────────────────
const _TT_ENGINES := ["engine_constellation", "engine_galaxy", "engine_classJ", "engine_classR", "engine_N700"]
const _TT_CAR_ROWS := [
	["car_passenger", "car_mail", "car_water_tank", "car_ore", "car_grain"],
	["car_royal", "car_chemical", "car_sand", "car_oil", "car_livestock", "car_fruit"],
	["car_glass", "car_iron", "car_cargo"],
	["car_steel", "car_hazmat", "car_machinery"],
]
const _TT_MYSTERY := ["car_ice", "car_gold", "car_diamond", "car_battery", "car_medical", "car_flowers"]
const _TT_NAMES := {
	"engine_constellation": "CONSTELLATION", "engine_galaxy": "GALAXY", "engine_classJ": "CLASS J", "engine_classR": "CLASS R", "engine_N700": "N700",
	"car_passenger": "PASSENGER CAR", "car_mail": "MAIL CAR", "car_water_tank": "WATER TANK", "car_ore": "MOLTEN ORE CAR", "car_livestock": "LIVESTOCK CAR",
	"car_royal": "ROYAL CAR", "car_sand": "SAND CAR", "car_chemical": "CHEMICAL CAR", "car_oil": "OIL CAR", "car_grain": "GRAIN CAR", "car_fruit": "FRUIT CAR",
	"car_ice": "ICE CAR", "car_iron": "IRON CAR", "car_steel": "STEEL CAR", "car_hazmat": "HAZMAT CAR", "car_machinery": "MACHINERY CAR", "car_glass": "GLASS CAR",
	"car_gold": "GOLD CAR", "car_diamond": "DIAMOND CAR", "car_battery": "BATTERY CAR", "car_medical": "MEDICAL CAR", "car_flowers": "FLOWERS CAR", "car_cargo": "CARGO CAR",
}
const _TT_HINTS := {
	"engine_classJ": "Earn $400K rolling revenue OR grow corp value to $2.4M", "engine_classR": "Complete the \"Designing a better space TRAIN\" mission",
	"car_livestock": "VISIT an AGRICULTURAL PLANET with a Farm structure", "car_royal": "Complete the ROYAL CAR research mission",
	"car_sand": "VISIT a DESERT PLANET", "car_chemical": "VISIT a CHEMICAL PLANET", "car_oil": "VISIT an OIL PLANET",
	"car_grain": "VISIT an AGRICULTURAL PLANET with a Granary structure", "car_fruit": "VISIT an AGRICULTURAL PLANET with an Orchard structure",
	"car_ice": "VISIT an ICE PLANET", "car_iron": "Produce IRON by running a FOUNDRY", "car_steel": "Produce STEEL by running a BLAST FURNACE",
	"car_hazmat": "Produce HAZMAT as a FOUNDRY byproduct", "car_machinery": "Produce MACHINERY by running a FACTORY",
	"car_glass": "Produce GLASS by running a GLASSWORKS", "car_cargo": "Produce CARGO by running a BAKERY or JUICERY",
}
const _TT_SUPPLY := {
	"car_passenger": "Any inhabited planet (scales w/ population)", "car_mail": "Any inhabited planet (scales w/ population)",
	"car_water_tank": "Ocean & Resort planets; Ice (high dev)", "car_ice": "Ice planets; Ocean (high dev)", "car_sand": "Desert, Rocky, & Ancient planets",
	"car_ore": "Lava planets", "car_oil": "Oil planets", "car_battery": "Storm planets", "car_chemical": "Chemical planets", "car_medical": "Jungle planets",
	"car_gold": "Planets w/ revealed gold deposits", "car_diamond": "Planets w/ revealed diamond deposits", "car_livestock": "Agri planets w/ a Farm",
	"car_grain": "Agri planets w/ a Granary", "car_fruit": "Agri planets w/ an Orchard", "car_flowers": "Jungle/Desert/Resort w/ flower origin",
	"car_iron": "FOUNDRY upgrades (Molten Ore + Water)", "car_steel": "BLAST FURNACE upgrades (Iron + Chemical)", "car_glass": "GLASSWORKS upgrades (Sand + Chemical)",
	"car_machinery": "FACTORY upgrades (Iron + Oil)", "car_hazmat": "FOUNDRY byproduct", "car_cargo": "BAKERY (Grain) or JUICERY (Fruit)", "car_royal": "Any inhabited planet (premium variant)",
}
const _TT_DEMAND := {
	"car_passenger": "Inhabited planets (Resort & Urban most)", "car_mail": "Inhabited planets (Resort & Urban most)",
	"car_water_tank": "Desert, Lava, Agri, Urban; FOUNDRY input", "car_ice": "Lava, Desert, Urban, Chemical", "car_sand": "Resort, Urban, Ocean, Agri; GLASSWORKS input",
	"car_ore": "Rocky, Urban, Desert; FOUNDRY input", "car_oil": "Urban, Lava, Rocky, Storm; FACTORY input", "car_battery": "Urban, Resort, Ocean, Jungle, Agri, Rocky",
	"car_chemical": "Any planet w/ upgrades; BLAST FURNACE & GLASSWORKS", "car_medical": "All inhabited planets", "car_gold": "Resort, Urban, Ocean (luxury markets)",
	"car_diamond": "Resort, Urban, Ocean (luxury markets)", "car_livestock": "All inhabited habitable planets", "car_grain": "BAKERY input", "car_fruit": "JUICERY input",
	"car_flowers": "Jungle, Desert, Resort, Urban", "car_iron": "Urban, Rocky; BLAST FURNACE & FACTORY inputs", "car_steel": "\"Designing a better TRAIN\" mission",
	"car_glass": "Urban planets; FACTORY input", "car_machinery": "Urban planets", "car_hazmat": "EJECT into a STAR for disposal", "car_cargo": "Generic shipping demand", "car_royal": "Resort & Urban planets",
}
var _TT_POS := {
	"engine_constellation": Vector2(75, 115), "engine_galaxy": Vector2(75, 187.5), "engine_classJ": Vector2(75, 260), "engine_classR": Vector2(75, 332.5), "engine_N700": Vector2(75, 405),
	"car_passenger": Vector2(212.5, 115), "car_mail": Vector2(317.5, 115), "car_water_tank": Vector2(422.5, 115), "car_ore": Vector2(580, 115), "car_grain": Vector2(790, 115),
	"car_royal": Vector2(265, 187.5), "car_chemical": Vector2(422.5, 187.5), "car_sand": Vector2(527.5, 187.5), "car_oil": Vector2(632.5, 187.5), "car_livestock": Vector2(737.5, 187.5), "car_fruit": Vector2(842.5, 187.5),
	"car_glass": Vector2(370, 260), "car_iron": Vector2(527.5, 260), "car_cargo": Vector2(790, 260),
	"car_steel": Vector2(422.5, 332.5), "car_hazmat": Vector2(527.5, 332.5), "car_machinery": Vector2(632.5, 332.5),
	"car_ice": Vector2(265, 405), "car_gold": Vector2(370, 405), "car_diamond": Vector2(475, 405), "car_battery": Vector2(580, 405), "car_medical": Vector2(685, 405), "car_flowers": Vector2(790, 405),
}
const _TT_EDGES := [
	["engine_constellation", "engine_galaxy"], ["engine_galaxy", "engine_classJ"], ["engine_classJ", "engine_classR"],
	["car_water_tank", "car_chemical"], ["car_ore", "car_sand"], ["car_ore", "car_oil"], ["car_grain", "car_livestock"], ["car_grain", "car_fruit"], ["car_grain", "car_cargo"],
	["car_passenger", "car_royal"], ["car_mail", "car_royal"], ["car_chemical", "car_glass"], ["car_sand", "car_glass"], ["car_sand", "car_iron"],
	["car_iron", "car_steel"], ["car_iron", "car_hazmat"], ["car_iron", "car_machinery"], ["car_oil", "car_machinery"],
]
var _tt_hover := ""

func _tt_size(t: String) -> Vector2:
	return Vector2(110, 62) if t.begins_with("engine_") else Vector2(90, 60)

func _tt_is_mystery(t: String) -> bool:
	return t == "engine_N700" or _TT_MYSTERY.has(t)

func _tt_locked(t: String, vis: Dictionary, gold: bool, diamond: bool) -> bool:
	if t == "engine_constellation" or t == "engine_galaxy":
		return false
	if t.begins_with("engine_"):
		return not GameState.unlocked_engines.has(t)
	if t == "car_passenger" or t == "car_mail" or t == "car_water_tank" or t == "car_ore":
		return false
	match t:
		"car_sand": return not vis.has("desert")
		"car_chemical": return not vis.has("chemical")
		"car_oil": return not vis.has("oil")
		"car_battery": return not vis.has("storm")
		"car_ice": return not vis.has("ice")
		"car_gold": return not gold
		"car_diamond": return not diamond
	return not GameState.unlocked_cars.has(t)

func _draw_tech_tree() -> void:
	draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, 0.65))
	var win_top := 36.0
	var win_bot := 440.0
	draw_rect(Rect2(0, win_top, W, win_bot - win_top), Color(0.016, 0.027, 0.071, 0.97))
	draw_rect(Rect2(3, win_top + 3, W - 6, win_bot - win_top - 6), Color(0.275, 0.549, 0.863, 0.55), false, 2.0)
	# Header strip.
	var hy := win_top + 6.0
	var hh := 26.0
	draw_rect(Rect2(6, hy, W - 12, hh), Color(0.157, 0.510, 0.863, 0.92))
	draw_string(f_orb_b, Vector2(18, hy + hh * 0.5 + 4.0), "ENGINES", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
	_ctr(f_orb_b, 540, hy + hh * 0.5 + 4.0, "CARS", 12, Color.WHITE)
	var esc := "[ESC] close"
	var esc_w := f_exo.get_string_size(esc, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	draw_string(f_exo, Vector2(W - 14 - esc_w, hy + hh * 0.5 + 4.0), esc, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.902, 0.941, 1.0, 0.85))
	draw_line(Vector2(150, hy + hh), Vector2(150, win_bot - 6), Color(0.157, 0.510, 0.863, 0.45), 1.0)
	# Precompute unlock state.
	var vis := {}
	var gold := false
	var diamond := false
	for p in Galaxy.planets:
		if Discovery.visited_planet_ids.has(int(p.id)):
			vis[String((p.get("type", {}) as Dictionary).get("id", ""))] = true
		if bool(p.get("hasGold", false)) and bool(p.get("goldRevealed", false)):
			gold = true
		if bool(p.get("hasDiamond", false)) and bool(p.get("diamondRevealed", false)):
			diamond = true
	# Hover detection (scan all nodes).
	_tt_hover = ""
	var hover_myst := false
	for entry in _tt_all_nodes():
		var pos: Vector2 = _TT_POS[entry[0]]
		var sz := _tt_size(entry[0])
		if Rect2(pos - sz * 0.5, sz).has_point(_mouse):
			_tt_hover = entry[0]
			hover_myst = entry[1]
	# Edges, then non-mystery nodes, then mystery nodes.
	for e in _TT_EDGES:
		_tt_edge(e[0], e[1], vis, gold, diamond)
	for eng in _TT_ENGINES:
		if eng != "engine_N700":
			_tt_node(eng, false, vis, gold, diamond)
	for row in _TT_CAR_ROWS:
		for c in row:
			_tt_node(c, false, vis, gold, diamond)
	_tt_node("engine_N700", true, vis, gold, diamond)
	for c in _TT_MYSTERY:
		_tt_node(c, true, vis, gold, diamond)
	if _tt_hover != "":
		_tt_tooltip(_tt_hover, hover_myst, vis, gold, diamond)

func _tt_all_nodes() -> Array:
	var out: Array = []
	for e in _TT_ENGINES:
		out.append([e, e == "engine_N700"])
	for row in _TT_CAR_ROWS:
		for c in row:
			out.append([c, false])
	for c in _TT_MYSTERY:
		out.append([c, true])
	return out

func _tt_node(t: String, mystery: bool, vis: Dictionary, gold: bool, diamond: bool) -> void:
	var pos: Vector2 = _TT_POS[t]
	var sz := _tt_size(t)
	var cell := Rect2(pos - sz * 0.5, sz)
	var hov := _tt_hover == t
	if mystery:
		var inner := Rect2(cell.position.x + 6.0, cell.position.y + 4.0, sz.x - 12.0, sz.y - 8.0)
		draw_rect(inner, Color(0.055, 0.063, 0.094, 0.92))
		draw_rect(inner, Color(0.471, 0.529, 0.667, 0.7) if hov else Color(0.157, 0.180, 0.243, 0.55), false, 1.0)
		_ctr(f_orb_b, pos.x, pos.y + 5.0, "???", 14, Color(0.627, 0.706, 0.863, 0.95) if hov else Color(0.314, 0.361, 0.471, 0.82))
	else:
		if view and view.get("_trains"):
			view._trains.draw_car_strip(self, cell, [t], [true])
		if _tt_locked(t, vis, gold, diamond):
			draw_rect(cell, Color(0.055, 0.071, 0.118, 0.55))  # dim (≈ greyscale+0.55 brightness)
		if hov:
			draw_rect(cell, Color(0.471, 0.784, 1.0, 0.55), false, 1.5)

func _tt_edge(a: String, b: String, vis: Dictionary, gold: bool, diamond: bool) -> void:
	if _tt_is_mystery(a) or _tt_is_mystery(b):
		return
	var p: Vector2 = _TT_POS[a]
	var c: Vector2 = _TT_POS[b]
	var y1 := p.y + _tt_size(a).y * 0.5
	var y2 := c.y - _tt_size(b).y * 0.5
	var col := Color(0.333, 0.412, 0.569, 0.32) if _tt_locked(a, vis, gold, diamond) else Color(0.549, 0.784, 0.922, 0.55)
	if absf(p.x - c.x) < 2.0:
		draw_line(Vector2(p.x, y1), Vector2(c.x, y2), col, 1.4)
	else:
		var mid := (y1 + y2) * 0.5
		draw_line(Vector2(p.x, y1), Vector2(p.x, mid), col, 1.4)
		draw_line(Vector2(p.x, mid), Vector2(c.x, mid), col, 1.4)
		draw_line(Vector2(c.x, mid), Vector2(c.x, y2), col, 1.4)

func _tt_tooltip(t: String, mystery: bool, vis: Dictionary, gold: bool, diamond: bool) -> void:
	var locked := mystery or _tt_locked(t, vis, gold, diamond)
	var is_car := t.begins_with("car_")
	var amber := Color(0.902, 0.784, 0.549, 0.97)
	var green := Color(0.667, 0.922, 0.745, 0.97)
	var body := Color(0.784, 0.843, 0.941, 0.88)
	var dim := Color(0.667, 0.745, 0.863, 0.78)
	# Lines: [text, color, is_name].
	var lines: Array = []
	lines.append(["???" if mystery else String(_TT_NAMES.get(t, t)), amber if (mystery or locked) else green, true])
	if mystery:
		lines.append(["Unknown — keep exploring", amber, false])
	elif locked:
		lines.append(["Status: Locked", amber, false])
		lines.append([String(_TT_HINTS.get(t, "Locked")), body, false])
	else:
		lines.append(["Status: Unlocked", green, false])
		if is_car and _TT_SUPPLY.has(t):
			lines.append(["Supplied by: " + String(_TT_SUPPLY[t]), body, false])
		if is_car and _TT_DEMAND.has(t):
			lines.append(["Demanded by: " + String(_TT_DEMAND[t]), body, false])
	# Wrap to ~300px and measure.
	var max_w := 300.0
	var vis_lines: Array = []
	var widest := 80.0
	for ln in lines:
		var fnt: Font = f_orb_b if ln[2] else f_exo
		var fsz: int = 11 if ln[2] else 10
		for seg in _wrap_text(String(ln[0]), fnt, fsz, max_w - 20.0):
			vis_lines.append([seg, ln[1], ln[2]])
			widest = maxf(widest, fnt.get_string_size(seg, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz).x)
	var tw := minf(max_w, widest + 20.0)
	var th := 16.0 + vis_lines.size() * 14.0
	var pos: Vector2 = _TT_POS[t]
	var tx := clampf(pos.x - tw * 0.5, 6.0, W - 6.0 - tw)
	var ty := pos.y - _tt_size(t).y * 0.5 - th - 8.0
	if ty < 68.0:
		ty = pos.y + _tt_size(t).y * 0.5 + 8.0
	draw_rect(Rect2(tx, ty, tw, th), Color(0.059, 0.098, 0.216, 0.97))
	draw_rect(Rect2(tx, ty, tw, th), Color(0.784, 0.627, 0.314, 0.85) if locked else Color(0.314, 0.784, 0.549, 0.85), false, 1.2)
	var cy := ty + 18.0
	for vl in vis_lines:
		_ctr(f_orb_b if vl[2] else f_exo, tx + tw * 0.5, cy, String(vl[0]), 11 if vl[2] else 10, vl[1], tw - 8.0)
		cy += 14.0

func _wrap_text(txt: String, fnt: Font, sz: int, max_w: float) -> Array:
	if txt == "":
		return [""]
	var out: Array = []
	var cur := ""
	for w in txt.split(" "):
		var trial := (cur + " " + w) if cur != "" else w
		if fnt.get_string_size(trial, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x <= max_w:
			cur = trial
		else:
			if cur != "":
				out.append(cur)
			cur = w
	if cur != "":
		out.append(cur)
	return out

const _FIN_BD_KEYS := ["stardate", "cargo", "train", "planet", "system"]
const _FIN_BD_LABELS := {"stardate": "STARDATE", "cargo": "CARGO TYPE", "train": "TRAIN", "planet": "PLANET", "system": "STAR SYSTEM"}

func _fin_cargo_label(c: String) -> String:
	return c.replace("_", " ").capitalize()

# Faithful FINANCIALS tab of build_game.py drawFinancesPopup (580×400). Reads the
# real GameState.finance_ledger / purchase_ledger. (LOANS + VS-RIVAL tabs are
# their own subsystems — deferred; this renders the FINANCIALS tab only.)
func _draw_finances() -> void:
	var pw := 580.0
	var ph := 400.0
	var o := _base(pw, ph, Color(0.235, 0.706, 0.392, 0.7))
	var px := o.x
	var py := o.y
	_ctr(f_orb_b, px + pw * 0.5, py + 22.0, "CORPORATE FINANCES", 12, Color(0.502, 1.0, 0.690))
	_esc_hint(px, py, pw)
	draw_line(Vector2(px, py + 32.0), Vector2(px + pw, py + 32.0), Color(0.235, 0.706, 0.392, 0.35), 1.0)
	# Single FINANCIALS folder-tab (LOANS/VS-RIVAL deferred).
	var tab_y := py + 40.0
	var tab_h := 22.0
	var tab_base := tab_y + tab_h
	draw_rect(Rect2(px + 14.0, tab_y, 110.0, tab_h), Color(0.071, 0.204, 0.125, 0.95))
	draw_rect(Rect2(px + 14.0, tab_y, 110.0, tab_h), Color(0.471, 0.863, 0.627, 0.85), false, 1.0)
	_ctr(f_orb_b, px + 69.0, tab_y + 14.0, "FINANCIALS", 10, Color(0.659, 1.0, 0.808))
	draw_line(Vector2(px + 12.0, tab_base), Vector2(px + pw - 12.0, tab_base), Color(0.471, 0.863, 0.627, 0.55), 1.0)
	var is_sd := _fin_breakdown == "stardate"
	# BREAKDOWN BY dropdown.
	var db_x := px + 12.0
	var db_y := tab_base + 10.0
	var db_w := 160.0
	var db_h := 20.0
	draw_string(f_exo, Vector2(db_x, db_y + 13.0), "BREAKDOWN BY", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.392, 0.608, 0.471, 0.65))
	var lbl_w := f_exo.get_string_size("BREAKDOWN BY", HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x + 8.0
	var dd_hov := _hov(Rect2(db_x + lbl_w, db_y, db_w, db_h))
	draw_rect(Rect2(db_x + lbl_w, db_y, db_w, db_h), Color(0.110, 0.235, 0.157, 0.95) if dd_hov else Color(0.071, 0.157, 0.102, 0.9))
	draw_rect(Rect2(db_x + lbl_w, db_y, db_w, db_h), Color(0.392, 0.902, 0.549, 0.7) if dd_hov else Color(0.235, 0.784, 0.431, 0.5), false, 1.0)
	draw_string(f_orb_b, Vector2(db_x + lbl_w + 8.0, db_y + 13.0), String(_FIN_BD_LABELS[_fin_breakdown]), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.502, 1.0, 0.690))
	draw_string(f_orb, Vector2(db_x + lbl_w + db_w - 12.0, db_y + 13.0), "v", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.471, 0.784, 0.549, 0.7))
	_rects["fin_dd"] = Rect2(db_x + lbl_w, db_y, db_w, db_h)
	# Aggregate the ledger by the selected breakdown.
	var agg := {}
	var order: Array = []
	for e in GameState.finance_ledger:
		var key := ""
		if is_sd:
			key = "SD %d" % int(floor(float(e.sd)))
		elif _fin_breakdown == "cargo":
			key = _fin_cargo_label(String(e.cargoType))
		elif _fin_breakdown == "train":
			key = String(e.trainName) if String(e.trainName) != "" else "Unknown"
		elif _fin_breakdown == "planet":
			var pn := String(_planet_by_id(int(e.planetId)).get("name", ""))
			key = pn if pn != "" else "Unknown"
		else:
			var sid := int(e.starId)
			key = String(Galaxy.stars[sid].name) if sid >= 0 and sid < Galaxy.stars.size() else "Unknown"
		if not agg.has(key):
			agg[key] = {"revenue": 0.0, "cost": 0.0}
			order.append(key)
		agg[key].revenue += float(e.revenue)
		agg[key].cost += float(e.cost)
	var purch := {}
	if is_sd:
		for ple in GameState.purchase_ledger:
			var pk := "SD %d" % int(floor(float(ple.sd)))
			purch[pk] = float(purch.get(pk, 0.0)) + float(ple.amount)
			if not agg.has(pk):
				agg[pk] = {"revenue": 0.0, "cost": 0.0}
				order.append(pk)
	var rows: Array = []
	for k in order:
		rows.append({"key": k, "revenue": agg[k].revenue, "cost": agg[k].cost, "profit": agg[k].revenue - agg[k].cost})
	if is_sd:
		rows.sort_custom(func(a, b): return float(String(a.key).substr(3)) < float(String(b.key).substr(3)))
	else:
		rows.sort_custom(func(a, b): return a.profit > b.profit)
	# Columns: 6 in SD mode (SOURCE|REVENUE|COSTS|PROFIT|PURCHASES|CORP VALUE), 4 otherwise.
	var col_x := px + 14.0
	var rw := pw - 28.0
	var c2 := col_x + rw * (0.30 if is_sd else 0.44)   # REVENUE right edge
	var c3 := col_x + rw * (0.48 if is_sd else 0.62)   # COSTS right edge
	var c4 := col_x + rw * (0.66 if is_sd else 0.80)   # PROFIT right edge
	var c5 := col_x + rw * 0.83                          # PURCHASES right edge (SD)
	var c_end := col_x + rw                              # CORP VALUE right edge (SD)
	var hdr_y := py + 118.0
	draw_rect(Rect2(col_x, hdr_y - 14.0, rw, 18.0), Color(0.031, 0.078, 0.055, 0.8))
	var hc := Color(0.392, 0.706, 0.510, 0.7)
	draw_string(f_orb_b, Vector2(col_x + 4.0, hdr_y), "SOURCE", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, hc)
	_rt(f_orb_b, c2 - 2.0, hdr_y, "REVENUE", 8, hc)
	_rt(f_orb_b, c3 - 2.0, hdr_y, "COSTS", 8, hc)
	_rt(f_orb_b, c4 - 2.0, hdr_y, "PROFIT", 8, hc)
	if is_sd:
		_rt(f_orb_b, c5 - 2.0, hdr_y, "PURCHASES", 8, hc)
		_rt(f_orb_b, c_end - 2.0, hdr_y, "CORP VALUE", 8, hc)
	# Rows (scrollable band).
	var row_h := 18.0
	var list_y := hdr_y + 6.0
	var tot_y := py + ph - 28.0
	var list_h := tot_y - 20.0 - list_y
	var max_scroll: float = maxf(0.0, rows.size() * row_h - list_h)
	_fin_scroll = clampf(_fin_scroll, 0.0, max_scroll)
	var cur_floor := int(floor(GameState.stardate))
	if rows.is_empty():
		_ctr(f_exo, px + pw * 0.5, list_y + list_h * 0.5, "No financial data yet.", 11, Color(0.314, 0.549, 0.392, 0.5))
	for ri in rows.size():
		var r: Dictionary = rows[ri]
		var ry := list_y + ri * row_h - _fin_scroll
		if ry < list_y - 1.0 or ry + row_h > list_y + list_h + 1.0:
			continue
		draw_rect(Rect2(col_x, ry, rw, row_h), Color(0.031, 0.086, 0.055, 0.5) if ri % 2 == 0 else Color(0.055, 0.133, 0.086, 0.5))
		draw_string(f_exo, Vector2(col_x + 4.0, ry + 12.0), String(r.key), HORIZONTAL_ALIGNMENT_LEFT, c2 - col_x - 12.0, 9, Color(0.706, 0.863, 0.784, 0.85))
		_rt(f_exo, c2 - 2.0, ry + 12.0, _fmt_cr(int(r.revenue)), 9, Color(0.392, 0.824, 0.549, 0.85))
		_rt(f_exo, c3 - 2.0, ry + 12.0, ("-" + _fmt_cr(int(r.cost))) if r.cost > 0 else "—", 9, Color(0.824, 0.392, 0.392, 0.85))
		var prof: float = r.profit
		_rt(f_exo, c4 - 2.0, ry + 12.0, ("-" if prof < 0 else "") + _fmt_cr(int(abs(prof))), 9, Color(0.392, 0.863, 0.588, 0.95) if prof >= 0 else Color(0.863, 0.314, 0.314, 0.95))
		if is_sd:
			var rp := float(purch.get(String(r.key), 0.0))
			_rt(f_exo, c5 - 2.0, ry + 12.0, ("-" + _fmt_cr(int(rp))) if rp > 0 else "—", 9, Color(0.824, 0.392, 0.392, 0.85))
			var sdn := int(String(r.key).substr(3))
			var cv := "—"
			if sdn < cur_floor and GameState.corp_value_history.has(sdn):
				cv = _fmt_cr(int(GameState.corp_value_history[sdn]))
			elif sdn == cur_floor:
				cv = _fmt_cr(Leaderboard._corp_value())
			_rt(f_exo, c_end - 2.0, ry + 12.0, cv, 9, Color(1.0, 0.843, 0.235, 0.82))
	# TOTAL row.
	var tot_rev := 0.0
	var tot_cost := 0.0
	for e in GameState.finance_ledger:
		tot_rev += float(e.revenue)
		tot_cost += float(e.cost)
	var tot_purch := 0.0
	if is_sd:
		for ple in GameState.purchase_ledger:
			tot_purch += float(ple.amount)
	var tot_profit := tot_rev - tot_cost
	draw_rect(Rect2(col_x, tot_y - 14.0, rw, 20.0), Color(0.039, 0.102, 0.071, 0.9))
	draw_line(Vector2(col_x, tot_y - 14.0), Vector2(col_x + rw, tot_y - 14.0), Color(0.235, 0.706, 0.392, 0.3), 1.0)
	draw_string(f_orb_b, Vector2(col_x + 4.0, tot_y), "TOTAL", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.627, 0.863, 0.706, 0.9))
	_rt(f_orb_b, c2 - 2.0, tot_y, _fmt_cr(int(tot_rev)), 9, Color(0.392, 0.863, 0.549, 0.9))
	_rt(f_orb_b, c3 - 2.0, tot_y, "-" + _fmt_cr(int(tot_cost)), 9, Color(0.863, 0.392, 0.392, 0.9))
	_rt(f_orb_b, c4 - 2.0, tot_y, ("-" if tot_profit < 0 else "") + _fmt_cr(int(abs(tot_profit))), 9, Color(0.392, 0.902, 0.588) if tot_profit >= 0 else Color(0.902, 0.353, 0.353))
	if is_sd:
		_rt(f_orb_b, c5 - 2.0, tot_y, ("-" + _fmt_cr(int(tot_purch))) if tot_purch > 0 else "—", 9, Color(0.863, 0.392, 0.392, 0.9))
		_rt(f_orb_b, c_end - 2.0, tot_y, _fmt_cr(Leaderboard._corp_value()), 9, Color(1.0, 0.843, 0.235, 0.9))
	# Dropdown options (drawn last, on top).
	if _fin_dd_open:
		for oi in _FIN_BD_KEYS.size():
			var oy := db_y + db_h + oi * db_h
			var ka: String = _FIN_BD_KEYS[oi]
			var act := ka == _fin_breakdown
			var ohov := _hov(Rect2(db_x + lbl_w, oy, db_w, db_h)) and not act
			draw_rect(Rect2(db_x + lbl_w, oy, db_w, db_h), Color(0.157, 0.471, 0.255, 0.95) if act else (Color(0.094, 0.227, 0.141, 0.98) if ohov else Color(0.055, 0.125, 0.078, 0.97)))
			draw_rect(Rect2(db_x + lbl_w, oy, db_w, db_h), Color(0.235, 0.706, 0.392, 0.4), false, 1.0)
			draw_string(f_orb_b, Vector2(db_x + lbl_w + 8.0, oy + 13.0), String(_FIN_BD_LABELS[ka]), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.753, 1.0, 0.816) if act else (Color(0.659, 0.882, 0.722) if ohov else Color(0.549, 0.784, 0.627, 0.8)))
			_rects["fin_opt_%s" % ka] = Rect2(db_x + lbl_w, oy, db_w, db_h)

func _fmt_cr(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if n < 0 else "") + out

# ── Corp dashboard (build_game.py drawCorpPopup 17584) ───────────────────────
func _draw_corp() -> void:
	var pw := 570.0
	var ph := 320.0
	var o := _base(pw, ph, Color(0.314, 0.549, 1.0, 0.65))
	var px := o.x
	var py := o.y
	# Header band: circular logo + corp name + [ESC].
	draw_rect(Rect2(px + 1.0, py + 1.0, pw - 2.0, 40.0), Color(0.039, 0.078, 0.176, 0.85))
	draw_circle(Vector2(px + 28.0, py + 21.0), 13.0, Color(0.157, 0.314, 0.627, 0.9))
	draw_arc(Vector2(px + 28.0, py + 21.0), 13.0, 0.0, TAU, 24, Color(0.471, 0.706, 1.0, 0.8), 1.5)
	_ctr(f_orb_b, px + 28.0, py + 25.0, String(GameState.corp_name).substr(0, 2).to_upper(), 11, Color(0.706, 0.863, 1.0))
	draw_string(f_orb_b, Vector2(px + 50.0, py + 26.0), String(GameState.corp_name), HORIZONTAL_ALIGNMENT_LEFT, pw - 160.0, 15, Color(0.78, 0.88, 1.0))
	_esc_hint(px, py, pw)
	# ── Left financials pane: 4×2 labelled grid ──
	var total_rev := 0.0
	var total_cost := 0.0
	for e in GameState.finance_ledger:
		total_rev += float(e.revenue)
		total_cost += float(e.cost)
	var total_purch := 0.0
	for ple in GameState.purchase_ledger:
		total_purch += float(ple.amount)
	var expenses := total_cost + total_purch
	var profit := total_rev - expenses
	var corp_value := Leaderboard._corp_value()
	var liquid := GameState.credits
	var hard := corp_value - liquid
	var grid := [
		["TOTAL REVENUES", "+ " + _fmt_cr(int(total_rev)), Color(0.392, 0.863, 0.549)],
		["TOTAL EXPENSES", "- " + _fmt_cr(int(expenses)), Color(0.863, 0.392, 0.392)],
		["TOTAL PROFITS", ("-" if profit < 0 else "+ ") + _fmt_cr(int(abs(profit))), Color(0.392, 0.902, 0.588) if profit >= 0 else Color(0.902, 0.353, 0.353)],
		["STARDATES ACTIVE", "%.1f" % maxf(0.0, GameState.stardate - Tuning.START_STARDATE), Color(0.745, 0.824, 0.941)],
		["LIQUID CASH", _fmt_cr(liquid), Color(0.706, 0.863, 1.0)],
		["HARD ASSETS", _fmt_cr(hard), Color(0.706, 0.863, 1.0)],
		["DEBTS", _fmt_cr(0), Color(0.6, 0.65, 0.78)],
		["CORP VALUE", _fmt_cr(corp_value), Color(1.0, 0.843, 0.235)],
	]
	var pane_x := px + 16.0
	var pane_w := 350.0
	var cell_w := pane_w * 0.5
	draw_string(f_orb_b, Vector2(pane_x, py + 62.0), "CORPORATE FINANCES", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.471, 0.706, 1.0, 0.7))
	for i in grid.size():
		var col_i := i % 2
		var row_i := int(i / 2.0)
		var gx := pane_x + col_i * cell_w
		var gy := py + 84.0 + row_i * 50.0
		draw_rect(Rect2(gx, gy, cell_w - 10.0, 44.0), Color(0.039, 0.078, 0.176, 0.5))
		draw_string(f_exo, Vector2(gx + 8.0, gy + 16.0), String(grid[i][0]), HORIZONTAL_ALIGNMENT_LEFT, cell_w - 18.0, 8, Color(0.471, 0.588, 0.784, 0.7))
		draw_string(f_orb_b, Vector2(gx + 8.0, gy + 34.0), String(grid[i][1]), HORIZONTAL_ALIGNMENT_LEFT, cell_w - 18.0, 12, grid[i][2])
	# Vertical divider.
	draw_line(Vector2(px + 384.0, py + 50.0), Vector2(px + 384.0, py + ph - 14.0), Color(0.196, 0.353, 0.627, 0.35), 1.0)
	# ── Right CEO pane ──
	_ctr(f_orb_b, px + 478.0, py + 62.0, "CEO", 9, Color(0.471, 0.706, 1.0, 0.7))
	var ceo := String(GameState.ceo_name)
	if ceo != "":
		var sprite := String(GameState.ceo.get("sprite", "ceo_" + ceo.to_lower()))
		var tex: Texture2D = load("res://assets/sprites/%s.png" % sprite)
		var portrait := Rect2(px + 440.0, py + 76.0, 76.0, 76.0)
		if tex != null:
			draw_texture_rect(tex, portrait, false)
		# Portrait is a button → opens the Hire-a-CEO window (when off cooldown).
		var on_cd := GameState.ceo_cooldown() > 0.001
		_stroke_round(portrait, 6.0, Color(0.62, 0.82, 1.0, 0.9) if (_hov(portrait) and not on_cd) else Color(0.353, 0.627, 1.0, 0.55), 1.5 if _hov(portrait) else 1.0)
		if not on_cd:
			_rects["corp_ceo_portrait"] = portrait
		_ctr(f_orb_b, px + 478.0, py + 172.0, ceo.to_upper(), 12, Color(0.78, 0.88, 1.0))
		_ctr(f_exo, px + 478.0, py + 186.0, String(GameState.ceo.get("nickname", "")), 9, Color(0.627, 0.706, 0.863, 0.7), 160.0)
		var yy := py + 204.0
		for cargo in GameState.ceo_revenue_mult.keys():
			var pct := int(round((float(GameState.ceo_revenue_mult[cargo]) - 1.0) * 100.0))
			if pct > 0:
				_ctr(f_exo, px + 478.0, yy, "+%d%% %s" % [pct, String(cargo).capitalize()], 9, Color(0.549, 0.863, 0.627, 0.9), 160.0)
				yy += 16.0
		_ctr(f_exo, px + 478.0, py + ph - 18.0, "click portrait to hire", 8, Color(0.471, 0.588, 0.784, 0.6), 160.0)
	else:
		_ctr(f_exo, px + 478.0, py + 130.0, "No CEO hired", 10, Color(0.5, 0.6, 0.75, 0.7), 160.0)


# Hire-a-CEO window (build_game.py drawCeoHirePopup 17882): 700×370, three columns
# [Current | Candidate 1 | Candidate 2] with portraits, salary/perk pills, HIRE.
func _draw_ceohire() -> void:
	var pw := 700.0
	var ph := 370.0
	var o := _base(pw, ph, Color(0.235, 0.314, 0.784, 0.7))
	var px := o.x
	var py := o.y
	# Title (glowing) + ESC.
	for off in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
		_ctr(f_orb_b, px + pw * 0.5 + off.x, py + 22.0 + off.y, "HIRE A CEO", 12, Color(0.251, 0.376, 0.878, 0.5))
	_ctr(f_orb_b, px + pw * 0.5, py + 22.0, "HIRE A CEO", 12, Color(0.627, 0.722, 1.0))
	_esc_hint(px, py, pw)
	draw_line(Vector2(px + 6.0, py + 32.0), Vector2(px + pw - 6.0, py + 32.0), Color(0.314, 0.314, 0.784, 0.4), 1.0)
	var cool := GameState.ceo_cooldown()
	var on_cool := cool > 0.001
	if on_cool:
		_ctr(f_exo, px + pw * 0.5, py + 48.0, "HIRING COOLDOWN: %.2f SD remaining" % cool, 9, Color(1.0, 0.706, 0.235, 0.9))
	var pad := 14.0
	var gap := 10.0
	var pan_w := floorf((pw - pad * 2.0 - gap * 2.0) / 3.0)
	var pan_y := py + (58.0 if on_cool else 42.0)
	var pan_h := ph - (pan_y - py) - 14.0
	# Current CEO.
	_ceo_col(GameState.ceo, px + pad, pan_y, pan_w, pan_h, true, -1, on_cool)
	# Candidate columns + HIRE buttons.
	for ci in mini(2, GameState.ceo_candidates.size()):
		_ceo_col(GameState.ceo_candidates[ci], px + pad + (pan_w + gap) * (ci + 1), pan_y, pan_w, pan_h, false, ci, on_cool)

func _ceo_col(c: Dictionary, pan_x: float, pan_y: float, pan_w: float, pan_h: float, is_current: bool, idx: int, on_cool: bool) -> void:
	if c.is_empty():
		return
	var pan_cx := pan_x + pan_w * 0.5
	var pr := Rect2(pan_x, pan_y, pan_w, pan_h)
	_fill_round(pr, 6.0, Color(0.031, 0.055, 0.157, 0.65) if is_current else Color(0.071, 0.125, 0.345, 0.6))
	_stroke_round(pr, 6.0, Color(0.235, 0.275, 0.510, 0.45) if is_current else Color(0.275, 0.431, 0.824, 0.55), 1.0)
	# Role badge.
	_ctr(f_orb_b, pan_cx, pan_y + 12.0, "CURRENT" if is_current else "AVAILABLE FOR HIRE", 7, Color(0.431, 0.510, 0.765, 0.72) if is_current else Color(0.431, 0.725, 1.0, 0.8))
	# Portrait.
	var pw2 := 76.0
	var p_x := pan_cx - pw2 * 0.5
	var p_y := pan_y + 20.0
	var tex: Texture2D = load("res://assets/sprites/%s.png" % String(c.get("sprite", "")))
	if tex != null:
		draw_texture_rect(tex, Rect2(p_x, p_y, pw2, pw2), false, Color(1, 1, 1, 0.72) if is_current else Color(1, 1, 1, 1))
	_stroke_round(Rect2(p_x, p_y, pw2, pw2), 6.0, Color(0.275, 0.353, 0.667, 0.45) if is_current else Color(0.353, 0.627, 1.0, 0.6), 1.0)
	# Name + nickname.
	_ctr(f_orb_b, pan_cx, p_y + pw2 + 16.0, String(c.get("name", "")), 11, Color(0.549, 0.647, 0.902, 0.85) if is_current else Color(0.765, 0.863, 1.0, 0.97))
	_ctr(f_exo, pan_cx, p_y + pw2 + 30.0, String(c.get("nickname", "")), 10, Color(0.471, 0.549, 0.784, 0.62) if is_current else Color(0.627, 0.725, 0.941, 0.7))
	# Salary pill (red >200K, orange >100K, yellow otherwise).
	var sal := int(c.get("salary", 0))
	var sal_txt := "-%s cr/Stardate" % _fmt_cr(sal)
	var sal_pw := minf(pan_w - 20.0, f_exo.get_string_size(sal_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 16.0)
	var sal_y := p_y + pw2 + 52.0
	var bg := Color(0.353, 0.071, 0.071, 0.65) if sal > 200000 else (Color(0.353, 0.204, 0.039, 0.65) if sal > 100000 else Color(0.333, 0.282, 0.031, 0.65))
	var fg := Color(0.922, 0.373, 0.373, 0.97) if sal > 200000 else (Color(1.0, 0.725, 0.255, 0.97) if sal > 100000 else Color(1.0, 0.902, 0.196, 0.97))
	if is_current:
		bg = Color(0.294, 0.078, 0.078, 0.55); fg = Color(0.745, 0.353, 0.353, 0.8)
	_fill_round(Rect2(pan_cx - sal_pw * 0.5, sal_y - 12.0, sal_pw, 20.0), 4.0, bg)
	_ctr(f_exo, pan_cx, sal_y + 1.0, sal_txt, 11, fg)
	# Separator + perk pills.
	var pk_y := p_y + pw2 + 80.0
	draw_line(Vector2(pan_x + 10.0, pk_y - 8.0), Vector2(pan_x + pan_w - 10.0, pk_y - 8.0), Color(0.235, 0.314, 0.627, 0.28), 0.6)
	var perks: Array = c.get("perks", [])
	for pi in perks.size():
		var lbl := String(perks[pi])
		var is_green := pi == 0
		var tw := f_exo.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		var pill_w := minf(pan_w - 20.0, tw + 14.0)
		_fill_round(Rect2(pan_cx - pill_w * 0.5, pk_y - 12.0, pill_w, 20.0), 4.0, Color(0.098, 0.282, 0.149, 0.62) if is_green else Color(0.098, 0.176, 0.392, 0.62))
		_ctr(f_exo, pan_cx, pk_y + 1.0, lbl, 11, Color(0.529, 0.961, 0.659, 0.97) if is_green else Color(0.686, 0.843, 1.0, 0.95), pan_w - 16.0)
		pk_y += 27.0
	# HIRE button (candidates only).
	if not is_current:
		var b := Rect2(pan_cx - 57.0, pan_y + pan_h - 38.0, 114.0, 26.0)
		if on_cool:
			_fill_round(b, 4.0, Color(0.110, 0.149, 0.314, 0.55))
			_ctr(f_orb_b, pan_cx, b.position.y + 17.0, "HIRE", 10, Color(0.275, 0.333, 0.529, 0.65))
		else:
			_btn(b.position.x, b.position.y, 114.0, 26.0, "HIRE", Color(0.216, 0.471, 0.902, 0.94), Color(0.882, 0.949, 1.0, 0.97), 10)
			_rects["hire_%d" % idx] = b


# ── small draw helpers ──────────────────────────────────────────────────────
func _btn(x: float, y: float, w: float, h: float, label: String, fill: Color, text_col: Color, size: int = 10) -> void:
	var r := Rect2(x, y, w, h)
	var hov := _hov(r)
	var rad := minf(6.0, h * 0.32)
	_fill_round(r, rad, fill.lightened(0.18) if hov else fill)
	_stroke_round(r, rad, Color(0.62, 0.82, 1.0, 0.95) if hov else Color(0.314, 0.627, 1.0, 0.8), 1.5 if hov else 1.0)
	_ctr(f_orb_b, x + w * 0.5, y + h * 0.5 + size * 0.36, label, size, text_col.lightened(0.25) if hov else text_col, w)

func _ctr(font: Font, cx: float, cy: float, text: String, size: int, col: Color, width: float = 600.0) -> void:
	draw_string(font, Vector2(cx - width * 0.5, cy), text, HORIZONTAL_ALIGNMENT_CENTER, width, size, col)
