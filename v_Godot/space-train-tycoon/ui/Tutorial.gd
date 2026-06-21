extends Control
## Tutorial — guided onboarding overlay (PLAN Phase 4, code map §11).
## A stepped hint bar: each step shows guidance and auto-advances when its
## game-state condition is met. This is a functional port of the chain's CORE
## (the JS has ~25 fine-grained click steps; here we teach the same core loop in
## a handful of condition-checked steps). SKIP dismisses it.
##
## Only active during GameState.phase == GALAXY; hidden on title/intro and once
## complete (or skipped — persisted via a flag so it doesn't reappear on load).

var _idx := 0
var _step_time := 0.0
var _done := false
var _start_player_trains := -1
var _panel: PanelContainer
var _label: RichTextLabel
var _steps: Array = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_CENTER_TOP)
	_panel = PanelContainer.new()
	_panel.position = Vector2(-320, 96)
	_panel.custom_minimum_size = Vector2(640, 0)
	add_child(_panel)
	var v := VBoxContainer.new()
	_panel.add_child(v)
	var hdr := Label.new()
	hdr.text = "TUTORIAL"
	hdr.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	v.add_child(hdr)
	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.fit_content = true
	_label.custom_minimum_size = Vector2(616, 0)
	v.add_child(_label)
	var skip := Button.new()
	skip.text = "Skip tutorial"
	skip.pressed.connect(func(): _done = true)
	v.add_child(skip)

	_steps = [
		{"text": "Welcome, CEO. [b]Drag[/b] to look around, [b]scroll[/b] to zoom, [b]WASD[/b] to pan.",
			"check": func(): return _step_time > 3.0},
		{"text": "[b]Click a planet[/b] to select it (its details show in the bottom-left panel).",
			"check": func(): return GameState.selected.get("kind", "") == "planet"},
		{"text": "Press [b]T[/b] to open the Train Builder — pick an engine, add a [Passenger] car, and [b]BUILD[/b].",
			"check": func(): return _player_trains() > _start_player_trains},
		{"text": "Now grow your network: select a [b]DESERT[/b] planet and press [b]N[/b] to build a STATION.",
			"check": func(): return _any_player_station()},
		{"text": "On that desert station, press [b]G[/b] to build an [b]IRON FOUNDRY[/b] (completes your first mission).",
			"check": func(): return Missions.is_completed("build_foundry")},
		{"text": "You've got the basics! Build trade ROUTES, complete MISSIONS, and outgrow your rival. Good luck.",
			"check": func(): return _step_time > 6.0},
	]


func _process(delta: float) -> void:
	if _done or GameState.phase != GameState.Phase.GALAXY:
		_panel.visible = false
		return
	if _start_player_trains < 0:
		_start_player_trains = _player_trains()
	_panel.visible = true
	_step_time += delta
	var step: Dictionary = _steps[_idx]
	_label.text = "[color=#dfe6f5]%s[/color]" % step.text
	if (step.check as Callable).call():
		_advance()


func _advance() -> void:
	Audio.play("blip")
	_idx += 1
	_step_time = 0.0
	if _idx >= _steps.size():
		_done = true


func _player_trains() -> int:
	var n := 0
	for t in Transit.trains:
		if t.isPlayer:
			n += 1
	return n


func _any_player_station() -> bool:
	for p in Galaxy.planets:
		if p.get("playerBuiltStation", false):
			return true
	return false
