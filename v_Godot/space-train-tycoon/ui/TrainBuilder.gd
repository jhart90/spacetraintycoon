extends Control
## TrainBuilder — the signature build popup (PLAN Phase 4, code map §17/trainbuilder).
## Code-built Control: pick an unlocked engine, add/remove unlocked cars (capped by
## ENGINE_MAX_CARS), see live cost, BUILD → Player.build_train at the selected
## planet (auto-routes to Orijen). Opened via GameState.popup_requested("train_builder").
##
## This is a functional port of the builder's CORE (engine/car selection + cost +
## build). The full §17 visual builder (sprite previews, edit mode, trainyard,
## drag reorder) is deferred — the data/actions are all here.

const ENGINE_ORDER := ["engine_constellation", "engine_galaxy", "engine_classJ", "engine_classR", "engine_N700"]
const CAR_ORDER := ["car_passenger", "car_mail", "car_water_tank", "car_ore", "car_iron",
	"car_sand", "car_oil", "car_battery", "car_chemical", "car_ice", "car_royal", "caboose"]

var _engine: String = "engine_constellation"
var _cars: Array = []
var _panel: VBoxContainer
var _engine_row: HBoxContainer
var _cars_label: Label
var _consist_row: HBoxContainer
var _add_row: HBoxContainer
var _cost_label: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(560, 360)
	center.add_child(pc)
	_panel = VBoxContainer.new()
	_panel.add_theme_constant_override("separation", 10)
	pc.add_child(_panel)

	var title := Label.new()
	title.text = "TRAIN BUILDER"
	title.add_theme_font_size_override("font_size", 22)
	_panel.add_child(title)

	_panel.add_child(_section("ENGINE"))
	_engine_row = HBoxContainer.new()
	_panel.add_child(_engine_row)

	_cars_label = Label.new()
	_panel.add_child(_cars_label)
	_consist_row = HBoxContainer.new()
	_panel.add_child(_consist_row)
	_panel.add_child(_section("ADD CAR"))
	_add_row = HBoxContainer.new()
	_add_row.add_theme_constant_override("separation", 4)
	_panel.add_child(_add_row)

	_cost_label = Label.new()
	_cost_label.add_theme_color_override("font_color", Color(1, 0.9, 0.5))
	_panel.add_child(_cost_label)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	var build_btn := Button.new()
	build_btn.text = "BUILD"
	build_btn.pressed.connect(_on_build)
	buttons.add_child(build_btn)
	var close_btn := Button.new()
	close_btn.text = "CLOSE (Esc)"
	close_btn.pressed.connect(close_popup)
	buttons.add_child(close_btn)
	_panel.add_child(buttons)

	GameState.popup_requested.connect(_on_popup_requested)


func _section(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_color_override("font_color", Color(0.6, 0.7, 0.85))
	return l


func _on_popup_requested(name: String) -> void:
	if name == "train_builder":
		open_popup()


func open_popup() -> void:
	# Default to the first unlocked engine.
	for e in ENGINE_ORDER:
		if GameState.unlocked_engines.has(e):
			_engine = e
			break
	_cars = []
	_rebuild()
	visible = true


func close_popup() -> void:
	visible = false


func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close_popup()
		get_viewport().set_input_as_handled()


func _max_cars() -> int:
	return int(Tuning.ENGINE_MAX_CARS.get(_engine, 6))


func _rebuild() -> void:
	# Engine buttons.
	for c in _engine_row.get_children():
		c.queue_free()
	for e in ENGINE_ORDER:
		if not GameState.unlocked_engines.has(e):
			continue
		var b := Button.new()
		b.text = _short(e)
		b.toggle_mode = true
		b.button_pressed = (e == _engine)
		b.pressed.connect(func(): _engine = e; _cars = _cars.slice(0, _max_cars()); _rebuild())
		_engine_row.add_child(b)

	# Current consist (click a car to remove it).
	_cars_label.text = "CARS  (%d / %d)" % [_cars.size(), _max_cars()]
	for c in _consist_row.get_children():
		c.queue_free()
	for i in _cars.size():
		var idx := i
		var cb := Button.new()
		cb.text = "✕ " + _short(_cars[i])
		cb.pressed.connect(func(): _cars.remove_at(idx); _rebuild())
		_consist_row.add_child(cb)

	# Add-car buttons (unlocked, room remaining).
	for c in _add_row.get_children():
		c.queue_free()
	for ct in CAR_ORDER:
		if not GameState.unlocked_cars.has(ct):
			continue
		var ab := Button.new()
		ab.text = "+ " + _short(ct)
		ab.disabled = _cars.size() >= _max_cars()
		ab.pressed.connect(func(): if _cars.size() < _max_cars(): _cars.append(ct); _rebuild())
		_add_row.add_child(ab)

	_cost_label.text = "COST: ⬢ %d        (you have ⬢ %d)" % [Player.train_cost(_engine, _cars), GameState.credits]


func _short(car_type: String) -> String:
	return car_type.replace("car_", "").replace("engine_", "").to_upper()


func _on_build() -> void:
	var planet: String = GameState.selected.get("id", "")
	var pid := Galaxy.origen_id
	if planet.begins_with("planet_"):
		pid = int(planet.substr(7))
	var t := Player.build_train(pid, _engine, _cars)
	if not t.is_empty():
		# Auto-route to Orijen so the new train does something immediately.
		if pid != Galaxy.origen_id:
			Player.assign_route(t.id, [pid, Galaxy.origen_id])
		close_popup()
