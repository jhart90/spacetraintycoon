extends Control
## Chrome — the always-on HUD chrome (build_game.py §22-§23), drawn immediate-mode
## in logical 900×500 space on the HUD CanvasLayer. The JS HD-text-overlay hack is
## gone — native draw_string is crisp here. M4: top bar, speed/zoom cluster, full-
## height right panel frame + tabs, bottom info bar (selection readout + watermark).
## Real Orbitron/Exo 2 fonts replace the debug stub.

var view: Node2D  # GalaxyView2D controller (cam zoom)

var f_exo: Font
var f_orb: Font
var f_orb_b: Font
var f_lato: Font

# Chat log (build_game.py §12) — event feed, newest at the bottom-left.
var _chat: Array = []  # {text:String, color:Color, sd:float}

var panel_tab := "trains"   # "trains" | "stations" (tab-switch click in Phase B)
var _speed_val_cx := 700.0  # cached centre-x of the #X speed value (info-bar buttons centre under it)
var _last_credits := -1
var _credit_delta := 0.0
var _delta_timer := 0.0
# Info-bar button hit-rects (consumed by Phase B interactivity).
var info_rects: Dictionary = {}
var _hover_key := ""  # which info_rects element the cursor is over (hover states)

const TOP_H := 28.0
const BAR_H := 72.0
const GH := 428.0
const W := 900.0
const H := 500.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # M4 is display-only; clicks pass to world
	f_exo = load("res://assets/fonts/Exo2-Variable.woff2")
	f_orb = load("res://assets/fonts/Orbitron-Variable.woff2")
	f_orb_b = _weight(f_orb, 700)
	f_lato = load("res://assets/fonts/Lato-Regular.woff2")
	GameState.selection_changed.connect(func(_s): queue_redraw())
	# Chat-log event wiring (mirrors the JS _chatMsg call sites).
	Transit.train_delivered.connect(_on_delivered)
	Discovery.star_revealed.connect(func(sid: int): _push_chat("%s — STAR DISCOVERED" % String(Galaxy.stars[sid].name), Color8(255, 200, 80)))
	Missions.mission_introduced.connect(func(id: String): _push_chat("New mission: %s" % String(Missions.def_for(id).get("name", "?")), Color8(120, 200, 255)))
	Missions.mission_completed.connect(func(id: String, r: int): _push_chat("Mission complete: %s (+%s cr)" % [String(Missions.def_for(id).get("name", "?")), _fmt_cr(r)], Color8(80, 230, 120)))

func _push_chat(text: String, color: Color) -> void:
	_chat.append({"text": text, "color": color, "sd": GameState.stardate})
	if _chat.size() > 40:
		_chat.pop_front()

func _on_delivered(tid: int, pid: int, cargo: String, rev: int) -> void:
	if rev <= 0:
		return
	for t in Transit.trains:
		if int(t.id) == tid and bool(t.isPlayer):
			_push_chat("%s: +%s cr (%s)" % [String(Galaxy.planets[pid].name), _fmt_cr(rev), cargo], Color8(255, 210, 80))
			return

func _weight(base: Font, wght: int) -> FontVariation:
	var fv := FontVariation.new()
	fv.base_font = base
	fv.variation_opentype = {"wght": wght}
	return fv


func _process(delta: float) -> void:
	# Credit delta — accumulates recent changes, fades after ~3 s.
	if _last_credits < 0:
		_last_credits = GameState.credits
	var d := GameState.credits - _last_credits
	if d != 0:
		_credit_delta += float(d)
		_delta_timer = 3.0
		_last_credits = GameState.credits
	if _delta_timer > 0.0:
		_delta_timer -= delta
		if _delta_timer <= 0.0:
			_credit_delta = 0.0
	queue_redraw()  # stardate/credits/zoom tick every frame


# UI clicks are handled in _input (runs before the world picker's _unhandled_input)
# so chrome consumes button/panel clicks and lets galaxy clicks fall through.
func _input(event: InputEvent) -> void:
	if GameState.gs != "galaxy":
		return  # front-end screens own input
	if GameState.popup_active:
		return  # a modal popup is open — it owns input
	if event is InputEventMouseMotion:
		# Track the hovered HUD element so chrome buttons get a hover state
		# (matches the JS *Hover globals). Redraw only when it changes.
		var p := (event as InputEventMouseMotion).position
		var hk := ""
		for k in info_rects.keys():
			if (info_rects[k] as Rect2).has_point(p):
				hk = String(k)
				break
		if hk != _hover_key:
			_hover_key = hk
			queue_redraw()
		return
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return
	# Panel double-click → open the row's detail popup (build_game.py panelDblClick).
	if mb.double_click:
		var pp := mb.position
		for k in info_rects.keys():
			if String(k).begins_with("train_row_") and _hit_ui(k, pp):
				var tid := int(String(k).trim_prefix("train_row_"))
				GameState.select("train", "train_%d" % tid, "Train %d" % tid)
				GameState.popup_requested.emit("train"); get_viewport().set_input_as_handled(); return
			if String(k).begins_with("station_row_") and _hit_ui(k, pp):
				var spid := int(String(k).trim_prefix("station_row_"))
				GameState.select("planet", "planet_%d" % spid, String(_planet_by_id(spid).get("name", "?")))
				GameState.popup_requested.emit("planet_detail"); get_viewport().set_input_as_handled(); return
	if _handle_ui_click(mb.position):
		get_viewport().set_input_as_handled()

# True when the named HUD element is currently hovered (set in _input motion).
func _hov_k(key: String) -> bool:
	return _hover_key == key

func _hit_ui(key: String, p: Vector2) -> bool:
	return info_rects.has(key) and (info_rects[key] as Rect2).has_point(p)

func _handle_ui_click(p: Vector2) -> bool:
	var pw := GameState.panel_w()
	if _hit_ui("panel_expand", p):
		GameState.panel_expanded = not GameState.panel_expanded; Audio.play("button"); return true
	if _hit_ui("topbar_corp", p):
		GameState.popup_requested.emit("corp"); return true
	if _hit_ui("topbar_finances", p):
		GameState.popup_requested.emit("finances"); return true
	if _hit_ui("gear", p):
		GameState.popup_requested.emit("options"); return true
	# Bottom hint-bar items open their popup (build_game.py _hintBounds).
	for k in info_rects.keys():
		if String(k).begins_with("hint_") and _hit_ui(k, p):
			GameState.popup_requested.emit(String(k).trim_prefix("hint_")); return true
	if _hit_ui("speed_left", p):
		GameState.set_speed_idx(GameState.game_speed_idx - 1); Audio.play("button"); return true
	if _hit_ui("speed_right", p):
		GameState.set_speed_idx(GameState.game_speed_idx + 1); Audio.play("button"); return true
	if _hit_ui("tab_trains", p):
		panel_tab = "trains"; Audio.play("button"); return true
	if _hit_ui("tab_stations", p):
		panel_tab = "stations"; Audio.play("button"); return true
	if _hit_ui("planet_details", p):
		GameState.popup_requested.emit("planet_detail"); return true
	if _hit_ui("route_here", p):
		var sel: Dictionary = GameState.selected
		if String(sel.get("kind", "")) == "planet":
			var pid := int(String(sel.get("id", "")).trim_prefix("planet_"))
			if bool(_planet_by_id(pid).get("hasStation", false)):
				if GameState.route_stops.is_empty() or int(GameState.route_stops[-1]) != pid:
					GameState.route_stops.append(pid)  # multi-stop: add to the route
					Audio.play("button")
		return true
	if _hit_ui("mission_tracker", p):
		GameState.popup_requested.emit("missions"); return true
	if _hit_ui("add_train", p):
		GameState.popup_requested.emit("trainbuilder"); return true
	for k in info_rects.keys():
		if String(k).begins_with("train_row_") and _hit_ui(k, p):
			var tid := int(String(k).trim_prefix("train_row_"))
			GameState.select("train", "train_%d" % tid, "Train %d" % tid); Audio.play("button"); return true
		if String(k).begins_with("station_row_") and _hit_ui(k, p):
			var spid := int(String(k).trim_prefix("station_row_"))
			GameState.select("planet", "planet_%d" % spid, String(_planet_by_id(spid).get("name", "?"))); Audio.play("button"); return true
		# Info-bar planet strip (star selected): click a disc → select that planet.
		if String(k).begins_with("infostrip_") and _hit_ui(k, p):
			var ppid := int(String(k).trim_prefix("infostrip_"))
			GameState.select("planet", "planet_%d" % ppid, String(_planet_by_id(ppid).get("name", "?"))); Audio.play("button"); return true
	# Any other click on chrome (panel / top bar / bottom bar) is consumed so it
	# doesn't fall through to the world picker behind it.
	return p.x >= W - pw or p.y < TOP_H or p.y >= GH


func _draw() -> void:
	info_rects.clear()
	if GameState.gs != "galaxy":
		return  # hidden behind the title / intro / menu screens (M6)
	var pw := GameState.panel_w()
	_draw_mission_tracker(pw)
	_draw_chat_log(pw)
	_draw_hint_bar(pw)
	_draw_right_panel(pw)
	_draw_bottom_bar(pw)
	_draw_top_bar(pw)
	_draw_speed_cluster(pw)


# ── Mission tracker (build_game.py §4.17) — active mission, upper-left ───────
func _draw_mission_tracker(pw: float) -> void:
	if not GameState.mission_tracker_enabled:
		return  # toggled off in Options
	if Missions.active.is_empty():
		return
	var m: Dictionary = Missions.active[0]
	var def: Dictionary = Missions.def_for(String(m.id))
	if def.is_empty():
		return
	var x := 10.0
	var y := TOP_H + 16.0
	var tw := 248.0
	var top_y := y - 12.0
	var hov := _hov_k("mission_tracker")
	draw_string(f_orb_b, Vector2(x, y), String(def.get("name", "")).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, tw, 11, Color(1.0, 0.91, 0.55, 1.0) if hov else Color(1.0, 0.82, 0.31, 0.95))
	y += 16.0
	var objs: Array = m.get("objectives", [])
	var defobjs: Array = def.get("objectives", [])
	for oi in objs.size():
		var done := bool(objs[oi].get("done", false))
		var txt := String(defobjs[oi].get("text", "")) if oi < defobjs.size() else ""
		var bc := Color(0.31, 0.9, 0.47, 0.95) if done else Color(0.47, 0.55, 0.71, 0.85)
		draw_rect(Rect2(x, y - 8.0, 9.0, 9.0), bc, false, 1.0)
		if done:
			draw_line(Vector2(x + 1.5, y - 3.5), Vector2(x + 3.5, y - 1.0), bc, 1.5)
			draw_line(Vector2(x + 3.5, y - 1.0), Vector2(x + 7.5, y - 6.5), bc, 1.5)
		var tcol := Color(0.71, 0.82, 0.6, 0.7) if done else Color(0.78, 0.86, 1.0, 0.9)
		var sz := f_exo.get_multiline_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, tw - 15.0, 10, 3)
		draw_multiline_string(f_exo, Vector2(x + 15.0, y), txt, HORIZONTAL_ALIGNMENT_LEFT, tw - 15.0, 10, 3, tcol)
		y += maxf(15.0, sz.y + 6.0)
	# Whole tracker is clickable → opens the Missions popup (build_game.py:33839).
	info_rects["mission_tracker"] = Rect2(x - 2.0, top_y, tw, y - top_y)


# ── Chat log (build_game.py §12) — event feed, bottom-left ──────────────────
func _draw_chat_log(pw: float) -> void:
	if _chat.is_empty():
		return
	var cw := 295.0
	var x := 10.0
	var line_h := 15.0
	var n: int = min(6, _chat.size())
	var bottom := GH - 14.0
	# Background panel behind the visible feed.
	var box_top := bottom - float(n) * line_h - 4.0
	draw_rect(Rect2(x - 6.0, box_top, cw + 8.0, float(n) * line_h + 10.0), Color(0.02, 0.04, 0.10, 0.55))
	draw_line(Vector2(x - 6.0, box_top), Vector2(x + cw + 2.0, box_top), Color(0.2, 0.35, 0.6, 0.35), 1.0)
	for i in n:
		var msg: Dictionary = _chat[_chat.size() - n + i]
		var y := bottom - float(n - 1 - i) * line_h
		var col: Color = msg.color
		col.a = lerpf(0.5, 1.0, float(i + 1) / float(n))  # older = fainter
		draw_string(f_exo, Vector2(x, y), String(msg.text), HORIZONTAL_ALIGNMENT_LEFT, cw - 52.0, 11, col)
		draw_string(f_exo, Vector2(x + cw - 48.0, y), "SD %.1f" % float(msg.sd), HORIZONTAL_ALIGNMENT_LEFT, 48.0, 9, Color(0.45, 0.55, 0.72, 0.6))


# ── Hint bar (build_game.py §4.19) — hotkey row at the galaxy-view bottom ────
func _draw_hint_bar(_pw: float) -> void:
	# build_game.py:30350 — exact item set, separator, colours, baseline GH-8.
	# When the panel is EXPANDED, [P] planets and [L] leaderboard are dropped.
	# Each item is clickable (opens its popup) and hovers white — like the JS
	# _hintBounds row (build_game.py:30350).
	var hints := [["[T] trains", "trains"], ["[R] routes", "routes"], ["[U] stations", "stations"], ["[M] missions", "missions"], ["[I] tech tree", "techtree"], ["[P] planets", "pokedex"], ["[L] leaderboard", "leaderboard"]]
	if GameState.panel_expanded:
		hints = [["[T] trains", "trains"], ["[R] routes", "routes"], ["[U] stations", "stations"], ["[M] missions", "missions"], ["[I] tech tree", "techtree"]]
	var col := Color(0.353, 0.549, 0.784, 0.52)
	var sep_col := Color(0.275, 0.431, 0.667, 0.35)
	var x := 8.0
	var y := GH - 8.0
	for i in hints.size():
		var h: String = hints[i][0]
		var popup: String = hints[i][1]
		var iw := f_exo.get_string_size(h, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
		var r := Rect2(x, y - 10.0, iw, 14.0)
		info_rects["hint_" + popup] = r
		draw_string(f_exo, Vector2(x, y), h, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 1, 1, 0.95) if _hov_k("hint_" + popup) else col)
		x += iw
		if i < hints.size() - 1:
			draw_string(f_exo, Vector2(x, y), "  ·  ", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, sep_col)
			x += f_exo.get_string_size("  ·  ", HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x


# ── Top bar (build_game.py:28381) ───────────────────────────────────────────
func _draw_top_bar(pw: float) -> void:
	var bar_w := W - pw
	var s1w := 175.0
	var s2w := 210.0
	var slant := 5.0
	var cy := TOP_H * 0.5
	var s2x := s1w
	var s3x := s1w + s2w
	# Background.
	draw_rect(Rect2(0, 0, bar_w, TOP_H), Color8(4, 8, 22))
	# Corp-name section → Corp dashboard; credits section → Finances (build_game.py).
	info_rects["topbar_corp"] = Rect2(s2x, 0, s3x - s2x, TOP_H)
	info_rects["topbar_finances"] = Rect2(s3x, 0, bar_w - s3x, TOP_H)
	# Section parallelogram fills.
	_para(0, s1w, slant, Color(0.196, 0.353, 0.686, 0.13))
	_para(s3x, bar_w - s3x, slant, Color(0.196, 0.353, 0.686, 0.13))
	# Diagonal separators + bottom border.
	draw_line(Vector2(s2x, 0), Vector2(s2x + slant, TOP_H), Color(0.275, 0.451, 0.824, 0.55), 0.8)
	draw_line(Vector2(s3x, 0), Vector2(s3x + slant, TOP_H), Color(0.275, 0.451, 0.824, 0.55), 0.8)
	draw_line(Vector2(0, TOP_H - 0.5), Vector2(bar_w, TOP_H - 0.5), Color(0.196, 0.353, 0.686, 0.30), 1.0)
	# Section 1: STARDATE.
	var sd_lbl := "STARDATE"
	var sd_val := "%.2f" % GameState.stardate
	var lw1 := f_exo.get_string_size(sd_lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x + 5.0
	var vw1 := f_orb.get_string_size(sd_val, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	var tx1: float = roundf(s1w * 0.5 - (lw1 + vw1) * 0.5)
	_txt(f_exo, Vector2(tx1, cy), sd_lbl, 9, Color(0.392, 0.569, 0.843, 0.52))
	_txt(f_orb, Vector2(tx1 + lw1, cy), sd_val, 10, Color(0.725, 0.843, 1.0, 0.92))
	# Section 2: corp name (player) — Orbitron bold, centred.
	var cn := String(GameState.corp_name)  # set by the M6 corp-setup flow
	_txt_centered(f_orb_b, s2x + s2w * 0.5, cy, cn, 12, Color(0.784, 0.863, 1.0, 0.78), s2w - 22.0)
	# Section 3: CREDITS.
	var cr_lbl := "CREDITS"
	var cr_val := _fmt_cr(GameState.credits)
	var lw3 := f_exo.get_string_size(cr_lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x + 5.0
	var cr_tx := s3x + 14.0
	_txt(f_exo, Vector2(cr_tx, cy), cr_lbl, 9, Color(0.392, 0.569, 0.843, 0.52))
	_txt(f_orb, Vector2(cr_tx + lw3, cy), cr_val, 10, Color(0.725, 0.843, 1.0, 0.92))
	# Credit delta arrow + value, immediately right of credits. Hidden when the
	# panel is EXPANDED (build_game.py:28492) — the narrower bar has no room.
	if not GameState.panel_expanded:
		var up := _credit_delta >= 0.0
		var dcol := Color(0.251, 0.878, 0.376) if up else Color(0.878, 0.251, 0.251)
		var vw3 := f_orb.get_string_size(cr_val, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		var d_start := cr_tx + lw3 + vw3 + 12.0
		var arx := d_start + 4.5
		if up:
			draw_colored_polygon(PackedVector2Array([Vector2(arx, cy - 3.5), Vector2(arx + 4.5, cy + 2.5), Vector2(arx - 4.5, cy + 2.5)]), dcol)
		else:
			draw_colored_polygon(PackedVector2Array([Vector2(arx, cy + 3.5), Vector2(arx + 4.5, cy - 2.5), Vector2(arx - 4.5, cy - 2.5)]), dcol)
		_txt(f_exo, Vector2(d_start + 11.0, cy), ("+" if up else "-") + _fmt_cr(int(abs(_credit_delta))), 9, dcol)

func _para(x: float, w: float, slant: float, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([
		Vector2(x, 0), Vector2(x + w, 0), Vector2(x + w + slant, TOP_H), Vector2(x + slant, TOP_H)]), col)


# ── Right panel (full height; build_game.py §22) ────────────────────────────
func _draw_right_panel(pw: float) -> void:
	var px := W - pw
	# Opaque frame, full height; left border (build_game.py §22).
	draw_rect(Rect2(px, 0, pw, H), Color8(4, 8, 20))
	draw_line(Vector2(px, 0), Vector2(px, H), Color(0.196, 0.392, 0.784, 0.40), 1.0)
	if not GameState.route_stops.is_empty():
		# SELECT A TRAIN banner replaces the tab strip while assigning a route.
		draw_rect(Rect2(px + 1.0, 0, pw - 2.0, TOP_H), Color(0.314, 0.667, 1.0))
		draw_rect(Rect2(px + 1.0, 0, pw - 2.0, TOP_H), Color(0.471, 0.784, 1.0, 0.85), false, 2.0)
		_txt_centered(f_orb_b, px + pw * 0.5, TOP_H * 0.5 + 3.5, "SELECT A TRAIN", 10, Color.BLACK, pw)
	else:
		# Tab headers at the TOP_H strip (drawPanelTabs).
		var tab_w := pw * 0.5
		_draw_panel_tab(px, tab_w, "TRAINS", panel_tab == "trains", "tab_trains")
		_draw_panel_tab(px + tab_w, tab_w, "STATIONS", panel_tab == "stations", "tab_stations")
		info_rects["tab_trains"] = Rect2(px, 0, tab_w, TOP_H)
		info_rects["tab_stations"] = Rect2(px + tab_w, 0, tab_w, TOP_H)
		# Expand / collapse arrow just left of the active tab label.
		var act_lbl := "TRAINS" if panel_tab == "trains" else "STATIONS"
		var act_cx := px + (tab_w * 0.5 if panel_tab == "trains" else tab_w * 1.5)
		var lbl_hw := f_orb_b.get_string_size(act_lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x * 0.5
		var arx := act_cx - lbl_hw - 9.0
		var ary := TOP_H * 0.5
		var ar_col := Color(0.75, 0.91, 1.0, 1.0) if _hov_k("panel_expand") else Color(0.51, 0.784, 1.0, 0.95)
		if GameState.panel_expanded:
			draw_colored_polygon(PackedVector2Array([Vector2(arx - 2.5, ary - 4.0), Vector2(arx + 3.5, ary), Vector2(arx - 2.5, ary + 4.0)]), ar_col)
		else:
			draw_colored_polygon(PackedVector2Array([Vector2(arx + 2.5, ary - 4.0), Vector2(arx - 3.5, ary), Vector2(arx + 2.5, ary + 4.0)]), ar_col)
		info_rects["panel_expand"] = Rect2(arx - 8.0, ary - 9.0, 16.0, 18.0)
	var content_y := TOP_H + 8.0
	if panel_tab == "trains":
		_draw_trains_panel(px, content_y, pw)
	else:
		_draw_stations_panel(px, content_y, pw)

func _draw_panel_tab(x: float, w: float, label: String, active: bool, key := "") -> void:
	var hov := key != "" and _hov_k(key)
	if active:
		draw_rect(Rect2(x, 0, w, TOP_H), Color8(4, 8, 20))
		var bc := Color(0.314, 0.588, 1.0, 0.65)
		draw_line(Vector2(x, 0.5), Vector2(x + w, 0.5), bc, 1.0)
		draw_line(Vector2(x + 0.5, 0), Vector2(x + 0.5, TOP_H), bc, 1.0)
		draw_line(Vector2(x + w - 0.5, 0), Vector2(x + w - 0.5, TOP_H), bc, 1.0)
	else:
		draw_rect(Rect2(x, 0, w, TOP_H), Color8(6, 12, 30) if hov else Color8(3, 5, 16))
		draw_rect(Rect2(x, 0, w, TOP_H), Color(0.353, 0.549, 0.882, 0.55) if hov else Color(0.196, 0.353, 0.706, 0.35), false, 1.0)
	var lc := Color(0.51, 0.784, 1.0, 0.95) if active else (Color(0.49, 0.66, 0.92, 0.85) if hov else Color(0.255, 0.392, 0.627, 0.55))
	_txt_centered(f_orb_b, x + w * 0.5, TOP_H * 0.5 + 3.0, label, 8, lc, w)

const _PANEL_ROW_H := 82.0

func _draw_trains_panel(px: float, ry0: float, pw: float) -> void:
	var ry := ry0
	var sel: Dictionary = GameState.selected
	var sel_id := -1
	if String(sel.get("kind", "")) == "train":
		sel_id = int(String(sel.get("id", "")).trim_prefix("train_"))
	for t in Transit.trains:
		if not bool(t.isPlayer):
			continue
		var tid := int(t.id)
		if tid == sel_id:
			draw_rect(Rect2(px + 2.0, ry, pw - 4.0, _PANEL_ROW_H - 2.0), Color(0.314, 0.549, 1.0, 0.10))
			draw_rect(Rect2(px + 2.0, ry, pw - 4.0, _PANEL_ROW_H - 2.0), Color(0.314, 0.627, 1.0, 0.30), false, 1.0)
		elif _hov_k("train_row_%d" % tid):
			draw_rect(Rect2(px + 2.0, ry, pw - 4.0, _PANEL_ROW_H - 2.0), Color(0.314, 0.549, 1.0, 0.07))
		# Consist strip.
		if view and view.get("_trains"):
			var consist: Array = [String(t.engine)]
			for c in t.cars:
				consist.append(String(c))
			var full: Array = [true]
			for c in t.get("carCargo", []):
				full.append(c != null)
			view._trains.draw_car_strip(self, Rect2(px + 8.0, ry + 4.0, pw - 16.0, 30.0), consist, full)
		# Name + status badge.
		var nm := String(t.get("name", "TRAIN %d" % tid))
		_txt(f_orb_b, Vector2(px + 10.0, ry + 50.0), nm, 9, Color(0.627, 0.863, 1.0, 0.95))
		var st := _train_status(t)
		var stw := f_orb_b.get_string_size(st[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
		_txt(f_orb_b, Vector2(px + pw - 10.0 - stw, ry + 50.0), st[0], 8, st[1])
		# Location line + car count.
		var loc := "in transit"
		if int(t.get("planetId", -1)) >= 0:
			var lp := _planet_by_id(int(t.planetId))
			var lsid := int(lp.get("starId", -1))
			var ls: Dictionary = Galaxy.stars[lsid] if lsid >= 0 and lsid < Galaxy.stars.size() else {}
			loc = "%s · %s" % [String(lp.get("name", "?")), String(ls.get("name", "?"))]
		_txt(f_exo, Vector2(px + 10.0, ry + 64.0), loc, 8, Color(0.392, 0.588, 0.863, 0.75))
		var cc := "%d cars" % int(t.cars.size())
		var ccw := f_exo.get_string_size(cc, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
		_txt(f_exo, Vector2(px + pw - 10.0 - ccw, ry + 64.0), cc, 8, Color(0.471, 0.588, 0.784, 0.8))
		info_rects["train_row_%d" % tid] = Rect2(px, ry, pw, _PANEL_ROW_H)
		ry += _PANEL_ROW_H
	# "+ Add new train" pseudo-row (clickable → train builder).
	var add_hov := _hov_k("add_train")
	if add_hov:
		draw_rect(Rect2(px + 2.0, ry, pw - 4.0, _PANEL_ROW_H - 2.0), Color(0.118, 0.392, 0.196, 0.25))
	_txt_centered(f_orb_b, px + pw * 0.5, ry + _PANEL_ROW_H * 0.5, "+ Add new train", 9, Color(0.62, 0.85, 1.0, 0.95) if add_hov else Color(0.51, 0.706, 0.941, 0.80), pw)
	info_rects["add_train"] = Rect2(px + 2.0, ry, pw - 4.0, _PANEL_ROW_H - 2.0)

const _CARGO_SHORT := {
	"passengers": "PSNGR", "livestock": "LVSTK", "mail": "MAIL", "water": "WATER",
	"ice": "ICE", "sand": "SAND", "molten_ore": "ORE", "iron": "IRON", "gold": "GOLD",
	"diamond": "DMND", "hazmat": "HAZMT", "oil": "OIL", "battery": "BATT",
	"chemical": "CHEM", "flowers": "FLWRS", "medical": "MEDCL", "grain": "GRAIN",
	"fruit": "FRUIT", "steel": "STEEL", "glass": "GLASS", "machinery": "MACH",
}

func _draw_stations_panel(px: float, ry0: float, pw: float) -> void:
	var ry := ry0
	var any := false
	for p in Galaxy.planets:
		if not bool(p.get("hasStation", false)):
			continue
		if bool(p.get("isAlienRelic", false)) and Discovery.planet_tier(int(p.id)) != Discovery.Tier.VISITED:
			continue  # relics hidden until visited (faithful)
		if ry > H - 30.0:
			break
		any = true
		if _hov_k("station_row_%d" % int(p.id)):
			draw_rect(Rect2(px + 2.0, ry, pw - 4.0, _PANEL_ROW_H - 2.0), Color(0.314, 0.549, 1.0, 0.07))
		var ty2: Dictionary = p.get("type", {})
		# Planet disc (left).
		var dc := Vector2(px + 26.0, ry + 28.0)
		var bt: Texture2D = view._content.biome_tex(String(ty2.get("id", ""))) if (view and view.get("_content")) else null
		if bt != null:
			draw_texture_rect(bt, Rect2(dc - Vector2(20.0, 20.0), Vector2(40.0, 40.0)), false)
		else:
			draw_circle(dc, 18.0, Color.from_string(String(ty2.get("base", "#888888")), Color(0.5, 0.5, 0.5)))
		draw_arc(dc, 23.0, 0.0, TAU, 24, Color(0.42, 0.68, 0.9, 0.5), 1.0)
		# Name · star · tier.
		var nx := px + 54.0
		var rival := bool(p.get("aiHasStation", false))
		var nm := String(p.get("name", "?")) + (" [HOME]" if bool(p.get("isStarter", false)) else "")
		_txt(f_orb_b, Vector2(nx, ry + 16.0), nm, 9, Color(0.667, 0.843, 1.0, 0.90) if not rival else Color(1.0, 0.66, 0.36, 0.9))
		var sid := int(p.get("starId", -1))
		var star: Dictionary = Galaxy.stars[sid] if sid >= 0 and sid < Galaxy.stars.size() else {}
		var tier_lbl := "TERMINAL" if bool(p.get("hasTerminal", false)) else ("LARGE STATION" if bool(p.get("hasLargeStation", false)) else "STATION")
		_txt(f_exo, Vector2(nx, ry + 28.0), "%s · %s" % [String(star.get("name", "?")), tier_lbl], 8, Color(0.431, 0.608, 0.863, 0.6))
		# SUPPLY / DEMAND brief columns.
		_txt(f_orb_b, Vector2(nx, ry + 46.0), "SUPPLY", 7, Color(0.314, 0.784, 1.0, 0.70))
		_txt(f_orb_b, Vector2(nx + 92.0, ry + 46.0), "DEMAND", 7, Color(1.0, 0.667, 0.235, 0.70))
		var syy := ry + 57.0
		for k in (p.get("supplyRate", {}) as Dictionary).keys().slice(0, 3):
			_txt(f_exo, Vector2(nx, syy), String(_CARGO_SHORT.get(String(k), String(k).to_upper())), 7, Color(0.55, 0.7, 0.9, 0.8)); syy += 8.5
		syy = ry + 57.0
		for k in (p.get("demandRate", {}) as Dictionary).keys().slice(0, 3):
			_txt(f_exo, Vector2(nx + 92.0, syy), String(_CARGO_SHORT.get(String(k), String(k).to_upper())), 7, Color(0.9, 0.7, 0.4, 0.8)); syy += 8.5
		info_rects["station_row_%d" % int(p.id)] = Rect2(px, ry, pw, _PANEL_ROW_H)
		ry += _PANEL_ROW_H
	if not any:
		_txt_centered(f_exo, px + pw * 0.5, ry0 + 16.0, "No stations built", 10, Color(0.5, 0.62, 0.85, 0.7), pw)

func _train_status(t: Dictionary) -> Array:
	if String(t.cargoPhase) == "unloading":
		return ["UNLOADING", Color(1.0, 0.65, 0.16, 0.92)]
	if String(t.cargoPhase) == "loading":
		return ["LOADING", Color(0.24, 0.82, 0.71, 0.92)]
	if int(t.phase) == Transit.Phase.TRANSIT:
		return ["IN TRANSIT", Color(1.0, 0.78, 0.24, 0.85)]
	return ["IN ORBIT", Color(0.24, 0.86, 0.47, 0.85)]


# ── Bottom info bar (build_game.py §22-§23) ─────────────────────────────────
func _draw_bottom_bar(pw: float) -> void:
	var bar_w := W - pw
	var by := GH
	draw_rect(Rect2(0, by, bar_w, BAR_H), Color8(6, 10, 24))
	draw_line(Vector2(0, by + 0.5), Vector2(bar_w, by + 0.5), Color(0.196, 0.353, 0.686, 0.35), 1.0)
	var sel: Dictionary = GameState.selected
	if sel.is_empty():
		_draw_watermark(bar_w, by)
	else:
		_draw_selection(sel, bar_w, by)

func _draw_watermark(bar_w: float, by: float) -> void:
	var cx := bar_w * 0.5
	_txt_centered(f_orb_b, cx, by + 26.0, "SPACE TRAIN", 17, Color(0.32, 0.45, 0.72, 0.42), bar_w)
	_txt_centered(f_orb_b, cx, by + 48.0, "TYCOON", 15, Color(0.32, 0.45, 0.72, 0.42), bar_w)

func _draw_selection(sel: Dictionary, bar_w: float, by: float) -> void:
	var kind := String(sel.get("kind", ""))
	var id_str := String(sel.get("id", ""))
	match kind:
		"planet": _draw_planet_info(_planet_by_id(int(id_str.trim_prefix("planet_"))), by, bar_w)
		"star": _draw_star_info(int(id_str.trim_prefix("star_")), by)
		"train": _draw_train_info(int(id_str.trim_prefix("train_")), by)
		"blackhole": _txt(f_orb_b, Vector2(16, by + 38.0), "BLACK HOLE", 15, Color(0.7, 0.5, 0.9, 0.95))

# #8bc body-text colour used throughout the info bar (build_game.py).
const _C8BC := Color(0.533, 0.733, 0.8)

func _draw_planet_info(p: Dictionary, by: float, _bar_w: float) -> void:
	if p.is_empty():
		return
	var ty: Dictionary = p.get("type", {})
	var hi := Color.from_string(String(ty.get("hi", "#aaaaaa")), Color(0.7, 0.7, 0.7))
	var pid := int(p.get("id", -1))
	# View-through visibility (build_game.py:29870 _ibPVis): VISITED, or AI-stationed,
	# or playerPreview. Otherwise the planet reads UNKNOWN.
	var vis := Discovery.planet_tier(pid) == Discovery.Tier.VISITED or bool(p.get("aiHasStation", false)) or bool(p.get("playerPreview", false))
	# ── Planet disc: centred at x=0, r=80, bleeds off the left edge, clipped to bar.
	var pcy := by + BAR_H * 0.5
	if vis:
		var bt: Texture2D = view._content.biome_tex(String(ty.get("id", ""))) if (view and view.get("_content")) else null
		if bt != null:
			_draw_bleeding_disc(bt, pcy, by, Color.WHITE)
		else:
			_draw_bleeding_disc(null, pcy, by, Color.from_string(String(ty.get("base", "#888888")), Color(0.4, 0.4, 0.5)))
	else:
		_draw_bleeding_disc(null, pcy, by, Color(0.016, 0.024, 0.063, 0.97))
	var text_x := 120.0
	if vis:
		# Title: name (+ [HOME]) in biome hi colour.
		var nm := String(p.get("name", "?")) + (" [HOME]" if bool(p.get("isStarter", false)) else "")
		_txt(f_orb_b, Vector2(text_x, by + 22.0), nm, 12, hi)
		# Row 2: Type · Size · Orbit (+ " SU").
		var pre := "Type: %s  ·  Size: %s  ·  Orbit: %d" % [String(ty.get("id", "")).to_upper(), String(p.get("size", "M")), int(round(float(p.get("orbitRadius", 0.0))))]
		_txt(f_exo, Vector2(text_x, by + 40.0), pre, 12, _C8BC)
		var pre_w := f_exo.get_string_size(pre, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		_txt(f_exo, Vector2(text_x + pre_w, by + 40.0), " SU", 8, _C8BC)
		# Row 3: Star: NAME · Coords: (x, y).
		_txt(f_exo, Vector2(text_x, by + 56.0), "Star: ", 12, _C8BC)
		var star_lbl_w := f_exo.get_string_size("Star: ", HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		var star: Dictionary = Galaxy.stars[int(p.get("starId", 0))] if int(p.get("starId", -1)) >= 0 and int(p.get("starId", 0)) < Galaxy.stars.size() else {}
		var spal: Dictionary = Tuning.STAR_COLORS.get(String(star.get("colorName", "yellow")), Tuning.STAR_COLORS["yellow"])
		var star_name := String(star.get("name", "?"))
		_txt(f_orb_b, Vector2(text_x + star_lbl_w, by + 56.0), star_name, 12, Color.from_string(String(spal["core"]), Color.WHITE))
		var star_name_w := f_orb_b.get_string_size(star_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		_txt(f_exo, Vector2(text_x + star_lbl_w + star_name_w, by + 56.0), "  ·  Coords: (%d, %d)" % [int(round(float(p.get("x", 0.0)) / 100.0)), int(round(float(p.get("y", 0.0)) / 100.0))], 12, _C8BC)
	else:
		_txt(f_orb_b, Vector2(text_x, by + 22.0), "UNKNOWN PLANET", 12, Color(0.235, 0.314, 0.549, 0.6))
		_txt(f_exo, Vector2(text_x, by + 40.0), "Type: ???  ·  Size: ???", 12, Color(0.196, 0.275, 0.471, 0.5))
		_txt(f_exo, Vector2(text_x, by + 56.0), "Star: ???", 12, Color(0.196, 0.275, 0.471, 0.5))
	# Stacked PLANET DETAILS / ROUTE TRAIN HERE buttons, centred under #X (build_game.py:29951).
	var lbl_w := maxf(f_orb_b.get_string_size("PLANET DETAILS", HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x, f_orb_b.get_string_size("ROUTE TRAIN HERE", HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x)
	var bw := roundf(lbl_w) + 14.0
	var bh := 22.0
	var gap := 4.0
	var top_y := by + (BAR_H - (bh * 2 + gap)) * 0.5
	var bx := roundf(_speed_val_cx - bw * 0.5)
	var pd := Rect2(bx, top_y, bw, bh)
	_btn_pill(pd, "PLANET DETAILS", Color(0.078, 0.235, 0.588, 0.92), Color(0.78, 0.88, 1.0, 0.95))
	info_rects["planet_details"] = pd
	var has_station := bool(p.get("hasStation", false))
	var rt := Rect2(bx, top_y + bh + gap, bw, bh)
	_btn_pill(rt, "ROUTE TRAIN HERE", Color(0.1, 0.42, 0.22, 0.9) if has_station else Color(0.13, 0.16, 0.24, 0.7), Color(0.7, 1.0, 0.78, 0.95) if has_station else Color(0.45, 0.5, 0.6, 0.6))
	info_rects["route_here"] = rt

func _draw_star_info(sid: int, by: float) -> void:
	if sid < 0 or sid >= Galaxy.stars.size():
		return
	var s: Dictionary = Galaxy.stars[sid]
	var pal: Dictionary = Tuning.STAR_COLORS.get(String(s.get("colorName", "yellow")), Tuning.STAR_COLORS["yellow"])
	var core := Color.from_string(String(pal["core"]), Color.WHITE)
	var vis := Discovery.is_star_revealed(sid)
	var pcy := by + BAR_H * 0.5
	# Star disc bleeds off the left edge, clipped to the bar.
	if vis:
		_draw_bleeding_disc(_star_tex(), pcy, by, core)
	else:
		_draw_bleeding_disc(null, pcy, by, Color(0.016, 0.024, 0.063, 0.97))
	var text_x := 112.0
	if vis:
		_txt(f_orb_b, Vector2(text_x, by + 22.0), String(s.get("name", "?")), 12, core)
		var coords := "Coords: (%d, %d)" % [int(round(float(s.get("x", 0.0)) / 100.0)), int(round(float(s.get("y", 0.0)) / 100.0))]
		_txt(f_exo, Vector2(text_x, by + 40.0), coords, 12, _C8BC)
		var npl := (s.get("planetIds", []) as Array).size()
		var radius_line := "%d planet%s  ·  Radius: %d SU" % [npl, ("" if npl == 1 else "s"), int(s.get("radius", 0))]
		_txt(f_exo, Vector2(text_x, by + 56.0), radius_line, 12, _C8BC)
		# Planet strip — starts just right of the text block.
		if not GameState.panel_expanded:
			var nw := f_orb_b.get_string_size(String(s.get("name", "?")), HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			var cw := f_exo.get_string_size(coords, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			var rw := f_exo.get_string_size(radius_line, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			_draw_star_planet_strip(s, text_x + maxf(maxf(nw, cw), rw) + 28.0, by)
	else:
		_txt(f_orb_b, Vector2(text_x, by + 22.0), "UNKNOWN STAR", 12, Color(0.235, 0.314, 0.549, 0.6))
		_txt(f_exo, Vector2(text_x, by + 40.0), "Coords: ???", 12, Color(0.196, 0.275, 0.471, 0.5))
		_txt(f_exo, Vector2(text_x, by + 56.0), "Orbit a planet in this system to reveal.", 12, Color(0.196, 0.275, 0.471, 0.5))

func _draw_star_planet_strip(s: Dictionary, strip_x: float, by: float) -> void:
	var pids: Array = (s.get("planetIds", []) as Array).duplicate()
	# Sort by orbit radius (inner → outer), matching the original.
	pids.sort_custom(func(a, b): return float(Galaxy.planets[int(a)].orbitRadius) < float(Galaxy.planets[int(b)].orbitRadius))
	var spacing := 58.0
	var bar_right := 900.0 - GameState.panel_w()
	var cy := by + BAR_H * 0.5 - 4.0
	for pid in pids:
		if strip_x + 30.0 > bar_right:
			break
		var pp: Dictionary = Galaxy.planets[int(pid)] if int(pid) < Galaxy.planets.size() else {}
		if pp.is_empty():
			continue
		# Each strip disc is clickable → selects that planet (build_game.py:33738).
		info_rects["infostrip_%d" % int(pid)] = Rect2(strip_x - 16.0, cy - 16.0, 32.0, 32.0)
		if _hov_k("infostrip_%d" % int(pid)):
			draw_arc(Vector2(strip_x, cy), 17.0, 0.0, TAU, 20, Color(1.0, 0.9, 0.5, 0.85), 1.5)
		if Discovery.planet_tier(int(pid)) == Discovery.Tier.UNKNOWN:
			draw_circle(Vector2(strip_x, cy), 13.0, Color(0.12, 0.16, 0.26, 0.85))
			draw_arc(Vector2(strip_x, cy), 13.0, 0.0, TAU, 16, Color(0.3, 0.4, 0.6, 0.5), 1.0)
			_txt(f_exo, Vector2(strip_x - 4.0, cy + 4.0), "?", 11, Color(0.55, 0.65, 0.85, 0.8))
			_txt(f_exo, Vector2(strip_x - 14.0, cy + 26.0), "???", 8, Color(0.45, 0.55, 0.75, 0.6))
		else:
			var pty: Dictionary = pp.get("type", {})
			var bt2: Texture2D = view._content.biome_tex(String(pty.get("id", ""))) if (view and view.get("_content")) else null
			if bt2 != null:
				draw_texture_rect(bt2, Rect2(Vector2(strip_x - 13.0, cy - 13.0), Vector2(26.0, 26.0)), false)
			else:
				draw_circle(Vector2(strip_x, cy), 13.0, Color.from_string(String(pty.get("base", "#888888")), Color(0.5, 0.5, 0.5)))
			if bool(pp.get("hasStation", false)):
				draw_arc(Vector2(strip_x, cy), 16.0, 0.0, TAU, 18, Color(0.42, 0.68, 0.9, 0.55), 1.0)
			var nm := String(pp.get("name", "?"))
			if nm.length() > 8:
				nm = nm.substr(0, 8)
			_txt_centered(f_exo, strip_x, cy + 26.0, nm, 8, Color(0.7, 0.82, 1.0, 0.75), 56.0)
		strip_x += spacing

# Draws an 80px-radius disc whose centre sits at screen x=0 — only the visible
# right half (x∈[0,80]) is painted, so it reads as a disc bleeding off the left
# edge, clipped to the info-bar top `by`. tex = sphere/star texture (fills frame),
# or null → a blacked-out fogged disc. modulate tints the texture.
func _draw_bleeding_disc(tex: Texture2D, pcy: float, by: float, modulate: Color) -> void:
	var t: Texture2D = tex if tex != null else _white_disc_tex()
	var r := 80.0
	var disc_top := pcy - r
	var top_clip := maxf(0.0, by - disc_top)        # sliver clipped above the bar top
	var bot_clip := maxf(0.0, (pcy + r) - H)        # sliver clipped below the screen bottom
	var dest_h := r * 2.0 - top_clip - bot_clip
	if dest_h <= 0.0:
		return
	var tw := float(t.get_width())
	var th := float(t.get_height())
	# Source = right half of the texture, just the vertical band that lands in-bar.
	var src := Rect2(tw * 0.5, th * (top_clip / (r * 2.0)), tw * 0.5, th * (dest_h / (r * 2.0)))
	draw_texture_rect_region(t, Rect2(0.0, maxf(disc_top, by), r, dest_h), src, modulate)

var _star_disc_tex: Texture2D = null
func _star_tex() -> Texture2D:
	if _star_disc_tex == null:
		_star_disc_tex = _make_radial_tex(true)
	return _star_disc_tex

var _white_disc_tex_c: Texture2D = null
func _white_disc_tex() -> Texture2D:
	if _white_disc_tex_c == null:
		_white_disc_tex_c = _make_radial_tex(false)
	return _white_disc_tex_c

# Builds a 128px radial disc. star=true → soft star falloff (bright core, fading
# corona). star=false → hard-edged solid disc (for the fogged black disc).
func _make_radial_tex(star: bool) -> Texture2D:
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c := (n - 1) * 0.5
	for y in n:
		for x in n:
			var d := Vector2(x - c, y - c).length() / (n * 0.5)
			var a := 0.0
			if star:
				if d < 0.5:
					a = 1.0
				elif d < 1.0:
					a = pow(clampf(1.0 - (d - 0.5) / 0.5, 0.0, 1.0), 1.4)
			else:
				a = 1.0 if d <= 0.985 else 0.0
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)

func _btn_pill(r: Rect2, label: String, fill: Color, text_col: Color) -> void:
	var hov := r.has_point(get_local_mouse_position())
	var rad := minf(5.0, r.size.y * 0.32)
	_round_rect(r.position.x, r.position.y, r.size.x, r.size.y, rad, fill.lightened(0.18) if hov else fill)
	_stroke_round(r, rad, Color(0.62, 0.82, 1.0, 0.95) if hov else Color(0.314, 0.627, 1.0, 0.8), 1.5 if hov else 1.0)
	_txt_centered(f_orb_b, r.position.x + r.size.x * 0.5, r.position.y + r.size.y * 0.5 + 3.0, label, 8, text_col.lightened(0.2) if hov else text_col, r.size.x)

func _stroke_round(r: Rect2, rad: float, col: Color, w: float) -> void:
	rad = minf(rad, minf(r.size.x, r.size.y) * 0.5)
	var p := r.position
	var s := r.size
	draw_line(Vector2(p.x + rad, p.y), Vector2(p.x + s.x - rad, p.y), col, w)
	draw_line(Vector2(p.x + rad, p.y + s.y), Vector2(p.x + s.x - rad, p.y + s.y), col, w)
	draw_line(Vector2(p.x, p.y + rad), Vector2(p.x, p.y + s.y - rad), col, w)
	draw_line(Vector2(p.x + s.x, p.y + rad), Vector2(p.x + s.x, p.y + s.y - rad), col, w)
	draw_arc(p + Vector2(rad, rad), rad, PI, PI * 1.5, 6, col, w)
	draw_arc(p + Vector2(s.x - rad, rad), rad, PI * 1.5, TAU, 6, col, w)
	draw_arc(p + Vector2(rad, s.y - rad), rad, PI * 0.5, PI, 6, col, w)
	draw_arc(p + Vector2(s.x - rad, s.y - rad), rad, 0.0, PI * 0.5, 6, col, w)

func _draw_train_info(tid: int, by: float) -> void:
	var t := _train_by_id(tid)
	if t.is_empty():
		return
	_txt(f_orb_b, Vector2(16.0, by + 22.0), "TRAIN %d" % tid, 14, Color(0.85, 0.93, 1.0, 0.95))
	var st := _train_status(t)
	_txt(f_exo, Vector2(16.0, by + 42.0), st[0], 10, st[1])
	var loaded := 0
	for c in t.get("carCargo", []):
		if c != null:
			loaded += 1
	_txt(f_exo, Vector2(16.0, by + 58.0), "%d/%d cars loaded · %s" % [loaded, int(t.cars.size()), String(t.engine).trim_prefix("engine_").to_upper()], 9, Color(0.5, 0.62, 0.85, 0.75))
	# Real consist sprite strip.
	if view and view.get("_trains"):
		var consist: Array = [String(t.engine)]
		for c in t.cars:
			consist.append(String(c))
		var full: Array = [true]
		for c in t.get("carCargo", []):
			full.append(c != null)
		view._trains.draw_car_strip(self, Rect2(180.0, by + 14.0, 360.0, 46.0), consist, full)

func _btn_bar(r: Rect2, label: String, fill: Color, text_col: Color) -> void:
	draw_rect(r, fill)
	draw_rect(r, Color(0.314, 0.627, 1.0, 0.7), false, 1.0)
	_txt_centered(f_orb_b, r.position.x + r.size.x * 0.5, r.position.y + r.size.y * 0.5 + 3.5, label, 9, text_col, r.size.x)

func _planet_by_id(pid: int) -> Dictionary:
	if pid >= 0 and pid < Galaxy.planets.size() and int(Galaxy.planets[pid].id) == pid:
		return Galaxy.planets[pid]
	for p in Galaxy.planets:
		if int(p.id) == pid:
			return p
	return {}

func _train_by_id(tid: int) -> Dictionary:
	for t in Transit.trains:
		if int(t.id) == tid:
			return t
	return {}


# ── Speed / zoom cluster (build_game.py:16330) ──────────────────────────────
func _draw_speed_cluster(pw: float) -> void:
	var panel_edge := W - pw - 6.0
	var row_y := GH - 10.0
	var btn_w := 18.0
	var btn_h := 16.0
	var val_w := 32.0
	# Gear button (far right).
	var gx := panel_edge - btn_w
	var gy := row_y - btn_h * 0.5
	var ghov := Rect2(gx, gy, btn_w, btn_h).has_point(get_local_mouse_position())
	_round_rect(gx, gy, btn_w, btn_h, 3.0, Color(0.353, 0.569, 0.961, 0.92) if ghov else Color(0.235, 0.431, 0.784, 0.75))
	_gear(gx + btn_w * 0.5, gy + btn_h * 0.5, 5.2, Color(0.82, 0.93, 1.0, 1.0) if ghov else Color(0.627, 0.824, 1.0, 0.95))
	info_rects["gear"] = Rect2(gx, gy, btn_w, btn_h)
	var right_edge := gx - 8.0
	var sel_w := btn_w + val_w + btn_w + 4.0
	var sel_x := right_edge - sel_w
	var left_bx := sel_x
	var right_bx := sel_x + btn_w + val_w + 4.0
	var idx := GameState.game_speed_idx
	_speed_arrow(left_bx, row_y - btn_h * 0.5, btn_w, btn_h, -1, idx > 0)
	_speed_arrow(right_bx, row_y - btn_h * 0.5, btn_w, btn_h, 1, idx < Tuning.SPEED_OPTS.size() - 1)
	info_rects["speed_left"] = Rect2(left_bx, row_y - btn_h * 0.5, btn_w, btn_h)
	info_rects["speed_right"] = Rect2(right_bx, row_y - btn_h * 0.5, btn_w, btn_h)
	# Speed value label.
	var spd: float = Tuning.SPEED_OPTS[idx]
	var lbl := "P"
	var col := Color(0.784, 0.824, 0.882, 0.85)
	if spd > 1.0:
		lbl = "%dX" % int(spd); col = Color(1.0, 0.863, 0.235, 0.95)
	elif spd < 1.0 and spd > 0.0:
		lbl = "0.5X"; col = Color(0.706, 0.882, 1.0, 0.85)
	elif spd == 1.0:
		lbl = "1X"; col = Color(0.549, 0.745, 1.0, 0.85)
	var val_cx := sel_x + btn_w + val_w * 0.5 + 2.0
	_speed_val_cx = val_cx  # info-bar PLANET DETAILS / ROUTE buttons centre under this
	_txt_centered(f_orb_b, val_cx, row_y + 0.5, lbl, 9, col, val_w + 8.0)
	# Zoom bar.
	var zoom_w := 60.0
	var zoom_h := 5.0
	var zoom_x := sel_x - 8.0 - zoom_w
	var zt := clampf((log(view.sc) - log(Tuning.MIN_SC)) / (log(Tuning.MAX_SC) - log(Tuning.MIN_SC)), 0.0, 1.0)
	draw_rect(Rect2(zoom_x, row_y - zoom_h * 0.5, zoom_w, zoom_h), Color(0.078, 0.157, 0.314, 0.55))
	draw_rect(Rect2(zoom_x, row_y - zoom_h * 0.5, zoom_w * zt, zoom_h), Color(0.314, 0.627, 1.0, 0.8))
	# Labels above each cluster.
	var lbl_y := row_y - 13.0
	_txt_centered(f_orb, zoom_x + zoom_w * 0.5, lbl_y, "ZOOM", 8, Color(0.471, 0.706, 1.0, 0.6), zoom_w)
	_txt_centered(f_orb, sel_x + sel_w * 0.5, lbl_y, "GAME SPEED", 8, Color(0.471, 0.706, 1.0, 0.6), sel_w + 20.0)

func _speed_arrow(x: float, y: float, w: float, h: float, dir: int, enabled: bool) -> void:
	var a := 0.85 if enabled else 0.3
	var hov := enabled and Rect2(x, y, w, h).has_point(get_local_mouse_position())
	var col := Color(0.75, 0.90, 1.0, 1.0) if hov else Color(0.471, 0.706, 1.0, a)
	var cx := x + w * 0.5
	var cy := y + h * 0.5
	var hw := 4.0
	var hh := 5.0
	if dir < 0:
		draw_colored_polygon(PackedVector2Array([Vector2(cx - hw, cy), Vector2(cx + hw, cy - hh), Vector2(cx + hw, cy + hh)]), col)
	else:
		draw_colored_polygon(PackedVector2Array([Vector2(cx + hw, cy), Vector2(cx - hw, cy - hh), Vector2(cx - hw, cy + hh)]), col)

func _gear(cx: float, cy: float, r: float, col: Color) -> void:
	for i in 8:
		var a := (float(i) / 8.0) * TAU
		var p := Vector2(cx + cos(a) * r * 1.25, cy + sin(a) * r * 1.25)
		draw_circle(p, r * 0.28, col)
	draw_arc(Vector2(cx, cy), r, 0.0, TAU, 20, col, 1.6)
	draw_circle(Vector2(cx, cy), r * 0.42, col)


# ── Helpers ─────────────────────────────────────────────────────────────────
func _txt(font: Font, pos: Vector2, text: String, size: int, col: Color) -> void:
	# pos.y is the vertical CENTRE (JS textBaseline 'middle'); offset to baseline.
	draw_string(font, Vector2(pos.x, pos.y + size * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)

func _txt_centered(font: Font, cx: float, cy: float, text: String, size: int, col: Color, width: float) -> void:
	draw_string(font, Vector2(cx - width * 0.5, cy + size * 0.36), text, HORIZONTAL_ALIGNMENT_CENTER, width, size, col)

func _round_rect(x: float, y: float, w: float, h: float, r: float, col: Color) -> void:
	draw_rect(Rect2(x + r, y, w - 2.0 * r, h), col)
	draw_rect(Rect2(x, y + r, w, h - 2.0 * r), col)
	draw_circle(Vector2(x + r, y + r), r, col)
	draw_circle(Vector2(x + w - r, y + r), r, col)
	draw_circle(Vector2(x + r, y + h - r), r, col)
	draw_circle(Vector2(x + w - r, y + h - r), r, col)

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
