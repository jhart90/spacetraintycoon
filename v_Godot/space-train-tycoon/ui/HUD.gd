extends CanvasLayer
## HUD — the 2D Control layer (PLAN §2 ui/, §3 boundary).
##
## PHASE 4 (functional core): top bar (credits, stardate, speed, AI net worth),
## a mission tracker, a selection info panel, and a floating world-anchored
## label. Reads ONLY GameState/Missions/AICorp/Discovery — never the 3D tree
## (§3). Speed/pause input lives in GalaxyView and writes GameState.
##
## DEFERRED (full §22-§23 UI parity): Train Builder, Planet Detail + upgrades,
## Routes [R], Stations [U], Options, Finances, Star Registry, tutorial chain,
## intro cutscene, chat log, save/load. Those are the bulk of Phase 4 and each
## becomes its own Control scene.

var _topbar: Label
var _mission_panel: RichTextLabel
var _info_label: RichTextLabel
var _float_label: Label
var _help: Label
var _flash: Label
var _flash_until: float = 0.0
var _now: float = 0.0
var _act_row: HBoxContainer
var _btn_builder: Button
var _btn_station: Button
var _btn_foundry: Button
var _btn_large: Button

const SPEED_LABELS := ["⏸", "0.5×", "1×", "2×", "5×", "10×"]


func _ready() -> void:
	layer = 10

	_topbar = Label.new()
	_topbar.position = Vector2(16, 10)
	_topbar.add_theme_color_override("font_color", Color(0.92, 0.95, 1.0))
	_topbar.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_topbar.add_theme_constant_override("outline_size", 4)
	add_child(_topbar)

	_help = Label.new()
	_help.text = "drag=orbit·scroll=zoom·WASD=pan·[ ]=speed·space=pause·F=reveal·V=visit·N=station·G=foundry·B=quick train·T=builder·R=routes·U=stations·C=finances·P=planet·O=options"
	_help.add_theme_color_override("font_color", Color(0.6, 0.66, 0.78))
	_help.position = Vector2(16, 34)
	add_child(_help)

	_flash = Label.new()
	_flash.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_flash.position = Vector2(16, -150)
	_flash.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_flash.add_theme_constant_override("outline_size", 4)
	_flash.visible = false
	add_child(_flash)
	Player.action_done.connect(func(m): _set_flash(m, Color(0.55, 1.0, 0.7)))
	Player.action_failed.connect(func(m): _set_flash("✘ " + m, Color(1.0, 0.55, 0.55)))

	# Chat log + popups + front-end (composite on top within this CanvasLayer).
	add_child(preload("res://ui/ChatLog.gd").new())
	add_child(preload("res://ui/TrainBuilder.gd").new())
	add_child(preload("res://ui/Popups.gd").new())
	add_child(preload("res://ui/Tutorial.gd").new())
	add_child(preload("res://ui/Title.gd").new())
	add_child(preload("res://ui/Intro.gd").new())

	# Context action buttons (bottom-centre).
	_act_row = HBoxContainer.new()
	_act_row.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_act_row.position = Vector2(-260, -44)
	_act_row.add_theme_constant_override("separation", 8)
	add_child(_act_row)
	_btn_builder = _act_button("Train Builder (T)", func(): GameState.popup_requested.emit("train_builder"))
	_btn_station = _act_button("Build Station (N)", func(): _act_on_planet(Player.build_station))
	_btn_foundry = _act_button("Build Foundry (G)", func(): _act_on_planet(func(pid): Player.build_upgrade(pid, "iron_foundry")))
	_btn_large = _act_button("Large Station", func(): _act_on_planet(Player.build_large_station))

	_mission_panel = RichTextLabel.new()
	_mission_panel.bbcode_enabled = true
	_mission_panel.fit_content = true
	_mission_panel.scroll_active = false
	_mission_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_mission_panel.position = Vector2(-340, 56)
	_mission_panel.custom_minimum_size = Vector2(320, 0)
	add_child(_mission_panel)

	var info_panel := PanelContainer.new()
	info_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	info_panel.position = Vector2(16, -120)
	info_panel.custom_minimum_size = Vector2(320, 96)
	_info_label = RichTextLabel.new()
	_info_label.bbcode_enabled = true
	_info_label.fit_content = true
	_info_label.custom_minimum_size = Vector2(296, 80)
	_info_label.text = "[color=#888]Nothing selected.[/color]"
	info_panel.add_child(_info_label)
	add_child(info_panel)

	_float_label = Label.new()
	_float_label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.7))
	_float_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_float_label.add_theme_constant_override("outline_size", 4)
	_float_label.visible = false
	add_child(_float_label)

	GameState.selection_changed.connect(_on_selection_changed)


func _process(delta: float) -> void:
	_now += delta
	_update_topbar()
	_update_missions()
	_update_float_label()
	_update_action_buttons()
	if _flash.visible and _now >= _flash_until:
		_flash.visible = false


func _act_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	_act_row.add_child(b)
	return b


func _selected_planet_id() -> int:
	var id: String = GameState.selected.get("id", "")
	if id.begins_with("planet_"):
		return int(id.substr(7))
	return -1


func _act_on_planet(fn: Callable) -> void:
	var pid := _selected_planet_id()
	if pid >= 0:
		fn.call(pid)


func _update_action_buttons() -> void:
	var pid := _selected_planet_id()
	var p: Dictionary = {} if pid < 0 else Galaxy.planets[pid]
	_btn_station.disabled = p.is_empty() or p.get("hasStation", false)
	_btn_foundry.disabled = p.is_empty() or not p.get("hasStation", false) or p.get("type", {}).get("id", "") != "desert" or ("iron_foundry" in p.get("upgrades", []))
	_btn_large.disabled = p.is_empty() or not p.get("hasStation", false) or p.get("hasLargeStation", false) or not GameState.unlocked_upgrades.has("large_station")


func _set_flash(msg: String, col: Color) -> void:
	_flash.text = msg
	_flash.add_theme_color_override("font_color", col)
	_flash.visible = true
	_flash_until = _now + 3.0


func _update_topbar() -> void:
	var spd: String = SPEED_LABELS[clampi(GameState.game_speed_idx, 0, SPEED_LABELS.size() - 1)]
	var txt := "⬢ %s   SD %.2f   %s" % [_money(GameState.credits), GameState.stardate, spd]
	if AICorp.active:
		txt += "      vs %s: %s" % [AICorp.corp_name, _money(AICorp.net_worth())]
	_topbar.text = txt


func _update_missions() -> void:
	if Missions.active.is_empty():
		_mission_panel.text = "[right][color=#667]no active missions[/color][/right]"
		return
	var s := "[right][b][color=#ffd070]MISSIONS[/color][/b]\n"
	for m in Missions.active:
		var d: Dictionary = Missions.def_for(m.id)
		s += "[color=#cfe0ff]%s[/color]\n" % d.get("name", m.id)
		for o in m.objectives:
			var mark := "[color=#6f6]✔[/color]" if o.done else "[color=#889]○[/color]"
			# objective text omitted here for brevity; show count
			s += "  %s\n" % mark
	s += "[/right]"
	_mission_panel.text = s


func _on_selection_changed(sel: Dictionary) -> void:
	if sel.is_empty():
		_info_label.text = "[color=#888]Nothing selected.[/color]"
		return
	_info_label.text = _describe(sel)


func _describe(sel: Dictionary) -> String:
	var kind: String = sel.kind
	if kind == "planet":
		var pid: int = _planet_id_from(sel.id)
		if pid >= 0:
			var tier: int = Discovery.planet_tier(pid)
			if tier != Discovery.Tier.VISITED:
				return "[b][color=#9ad]??? UNKNOWN PLANET ???[/color][/b]\n[color=#888]Visit to reveal details.[/color]"
			var p: Dictionary = Galaxy.planets[pid]
			var sup := ", ".join(PackedStringArray(p.get("supplyRate", {}).keys()))
			var dem := ", ".join(PackedStringArray(p.get("demandRate", {}).keys()))
			return "[b][color=#9ad]%s[/color][/b]  [color=#aaa]%s · %s[/color]\n[color=#9c9]supplies:[/color] %s\n[color=#c99]demands:[/color] %s\n[color=#aaa]pop %s · health %.2f[/color]" % [
				p.name, String(p.type.id).to_upper(), p.size, sup, dem, _money(int(p.get("population", 0))), p.get("economicHealth", 0.0)]
	elif kind == "star":
		return "[b][color=#fd8]%s[/color][/b]\n[color=#aaa]STAR[/color]" % sel.name
	elif kind == "blackhole":
		return "[b][color=#b8f]%s[/color][/b]\n[color=#aaa]BLACK HOLE[/color]" % sel.name
	return "[b]%s[/b]\n[color=#aaa]%s[/color]" % [sel.name, kind.to_upper()]


func _planet_id_from(id_str: String) -> int:
	if id_str.begins_with("planet_"):
		return int(id_str.substr(7))
	return -1


func _update_float_label() -> void:
	if GameState.selected.is_empty() or GameState.selected_screen_pos == Vector2.INF:
		_float_label.visible = false
		return
	_float_label.visible = true
	_float_label.text = GameState.selected.name
	_float_label.position = GameState.selected_screen_pos + Vector2(14, -10)


## Compact money formatting (e.g. 5,461,565 → "5.46M").
func _money(n: int) -> String:
	var a := absi(n)
	if a >= 1_000_000_000:
		return "%.2fB" % (n / 1e9)
	if a >= 1_000_000:
		return "%.2fM" % (n / 1e6)
	if a >= 10_000:
		return "%.1fk" % (n / 1e3)
	return str(n)
