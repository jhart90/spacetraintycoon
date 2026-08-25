extends Control
## Popups — one switchable modal for the read/lightweight windows (PLAN Phase 4,
## code map §10/§22-§23): Options, Routes [R], Stations [U], Finances [C], Planet
## Detail [P]. Built in code on demand; one visible at a time. (Train Builder is
## its own scene; this handles the rest.)

const KNOWN := ["options", "routes", "stations", "finances", "planet_detail"]
const TITLES := {
	"options": "OPTIONS", "routes": "ROUTES", "stations": "STATIONS",
	"finances": "CORP FINANCES", "planet_detail": "PLANET DETAILS",
}

var _title: Label
var _content: VBoxContainer
var _current: String = ""


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(560, 440)
	center.add_child(pc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	pc.add_child(v)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 22)
	v.add_child(_title)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(520, 340)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 6)
	_content.custom_minimum_size = Vector2(500, 0)
	scroll.add_child(_content)

	var close := Button.new()
	close.text = "CLOSE (Esc)"
	close.pressed.connect(close_popup)
	v.add_child(close)

	GameState.popup_requested.connect(_on_popup_requested)


func _on_popup_requested(name: String) -> void:
	if name in KNOWN:
		open_popup(name)


func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close_popup()
		get_viewport().set_input_as_handled()


func open_popup(name: String) -> void:
	_current = name
	_title.text = TITLES.get(name, name.to_upper())
	for c in _content.get_children():
		c.queue_free()
	match name:
		"options": _build_options()
		"routes": _build_routes()
		"stations": _build_stations()
		"finances": _build_finances()
		"planet_detail": _build_planet_detail()
	visible = true


func close_popup() -> void:
	visible = false


func _lbl(text: String, color := Color(0.85, 0.88, 0.95)) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(490, 0)
	l.add_theme_color_override("font_color", color)
	_content.add_child(l)
	return l


# ── Options: SFX + Music volume ───────────────────────────────────────────
func _build_options() -> void:
	_lbl("SOUND EFFECTS", Color(0.6, 0.7, 0.85))
	var mute := CheckBox.new()
	mute.text = "Mute SFX"
	mute.button_pressed = Audio.sfx_muted
	mute.toggled.connect(func(on): Audio.set_sfx_muted(on))
	_content.add_child(mute)
	var sfx := HSlider.new()
	sfx.min_value = 0.0; sfx.max_value = 1.0; sfx.step = 0.05; sfx.value = Audio.sfx_vol
	sfx.custom_minimum_size = Vector2(400, 0)
	sfx.value_changed.connect(func(v): Audio.set_sfx_volume(v))
	_content.add_child(sfx)
	_lbl("MUSIC", Color(0.6, 0.7, 0.85))
	var mus := HSlider.new()
	mus.min_value = 0.0; mus.max_value = 1.0; mus.step = 0.05; mus.value = Audio.music_vol
	mus.custom_minimum_size = Vector2(400, 0)
	mus.value_changed.connect(func(v): Audio.music_vol = v; Audio._apply_volume())
	_content.add_child(mus)


# ── Routes: player trains + their routes ──────────────────────────────────
func _build_routes() -> void:
	var any := false
	for t in Transit.trains:
		if not t.isPlayer:
			continue
		any = true
		var cars := "engine + %d cars" % t.cars.size()
		var phase := "orbit" if t.phase == Transit.Phase.ORBIT else "transit"
		var stops := "—"
		if t.route != null:
			var names := []
			for sid in t.route.stops:
				names.append(Galaxy.planets[sid].name)
			stops = " → ".join(names)
		_lbl("Train #%d  [%s]  %s  [%s]\n   route: %s" % [t.id, _short(t.engine), cars, phase, stops])
	if not any:
		_lbl("No player trains yet. Press T to build one.", Color(0.6, 0.6, 0.7))


# ── Stations: player station planets ──────────────────────────────────────
func _build_stations() -> void:
	var any := false
	for p in Galaxy.planets:
		if not (p.get("playerBuiltStation", false) or p.get("isStarter", false)):
			continue
		any = true
		var tier := "Terminal" if p.get("hasTerminal", false) else ("Large" if p.get("hasLargeStation", false) else "Station")
		var ups: Array = p.get("upgrades", [])
		_lbl("%s  [%s]  %s%s" % [p.name, String(p.type.id).to_upper(), tier, ("  · " + ", ".join(PackedStringArray(ups))) if not ups.is_empty() else ""])
	if not any:
		_lbl("No stations built. Select a planet and press N.", Color(0.6, 0.6, 0.7))


# ── Finances: you vs the rival ────────────────────────────────────────────
func _build_finances() -> void:
	var trains := 0
	var stations := 0
	var train_val := 0
	for t in Transit.trains:
		if t.isPlayer:
			trains += 1
			train_val += int(Tuning.ENGINE_COSTS.get(t.engine, 10000)) + t.cars.size() * Tuning.CAR_COST
	for p in Galaxy.planets:
		if p.get("playerBuiltStation", false) or p.get("isStarter", false):
			stations += 1
	var net := GameState.credits + train_val + stations * Tuning.STATION_COST
	_lbl("Credits:    ⬢ %d" % GameState.credits, Color(0.7, 1.0, 0.8))
	_lbl("Trains:     %d   (asset value ⬢ %d)" % [trains, train_val])
	_lbl("Stations:   %d" % stations)
	_lbl("NET WORTH:  ⬢ %d" % net, Color(1.0, 0.95, 0.6))
	_lbl("")
	if AICorp.active:
		_lbl("RIVAL — %s" % AICorp.corp_name, Color(0.91, 0.58, 0.13))
		_lbl("   net worth: ⬢ %d   revenue: ⬢ %d" % [AICorp.net_worth(), AICorp.total_revenue])
		_lbl("   %s" % ("You lead." if net >= AICorp.net_worth() else "Rival leads."), Color(0.8, 0.85, 0.95))


# ── Planet Detail: selected planet + build actions ────────────────────────
func _build_planet_detail() -> void:
	var id: String = GameState.selected.get("id", "")
	if not id.begins_with("planet_"):
		_lbl("Select a planet first.", Color(0.6, 0.6, 0.7))
		return
	var pid := int(id.substr(7))
	var p: Dictionary = Galaxy.planets[pid]
	if Discovery.planet_tier(pid) != Discovery.Tier.VISITED:
		_lbl("??? UNKNOWN PLANET ???\nRoute a train here to reveal its details.", Color(0.6, 0.66, 0.8))
		return
	_lbl("%s   [%s · %s]" % [p.name, String(p.type.id).to_upper(), p.size], Color(0.6, 0.85, 1.0))
	_lbl("population %s   ·   economic health %.2f" % [_money(int(p.get("population", 0))), p.get("economicHealth", 0.0)])
	_lbl("supplies: " + (", ".join(PackedStringArray(p.get("supplyRate", {}).keys())) if not p.get("supplyRate", {}).is_empty() else "—"), Color(0.6, 0.9, 0.6))
	_lbl("demands: " + (", ".join(PackedStringArray(p.get("demandRate", {}).keys())) if not p.get("demandRate", {}).is_empty() else "—"), Color(0.9, 0.6, 0.6))
	var tier := "Large Station" if p.get("hasLargeStation", false) else ("Station" if p.hasStation else "no station")
	_lbl("station: %s   upgrades: %s" % [tier, ", ".join(PackedStringArray(p.get("upgrades", []))) if not p.get("upgrades", []).is_empty() else "none"])
	# Actions row.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_content.add_child(row)
	_pd_btn(row, "Build Station", not p.hasStation, func(): Player.build_station(pid); open_popup("planet_detail"))
	_pd_btn(row, "Build Foundry", p.hasStation and p.type.id == "desert" and not ("iron_foundry" in p.get("upgrades", [])), func(): Player.build_upgrade(pid, "iron_foundry"); open_popup("planet_detail"))
	_pd_btn(row, "Large Station", p.hasStation and not p.get("hasLargeStation", false) and GameState.unlocked_upgrades.has("large_station"), func(): Player.build_large_station(pid); open_popup("planet_detail"))


func _pd_btn(row: HBoxContainer, text: String, enabled: bool, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.disabled = not enabled
	b.pressed.connect(cb)
	row.add_child(b)


func _short(s: String) -> String:
	return s.replace("engine_", "").replace("car_", "").to_upper()


func _money(n: int) -> String:
	if absi(n) >= 1_000_000_000: return "%.2fB" % (n / 1e9)
	if absi(n) >= 1_000_000: return "%.2fM" % (n / 1e6)
	if absi(n) >= 10_000: return "%.1fk" % (n / 1e3)
	return str(n)
