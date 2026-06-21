extends Control
## Title — front-end screen (PLAN Phase 4, code map §14). Shown while
## GameState.phase == TITLE, over the slowly-rotating galaxy backdrop. New Game →
## intro; Continue → load save; Options → popup.

var _continue_btn: Button


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.35)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(v)

	var t := Label.new()
	t.text = "SPACE TRAIN TYCOON"
	t.add_theme_font_size_override("font_size", 48)
	t.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	t.add_theme_constant_override("outline_size", 6)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var sub := Label.new()
	sub.text = "Godot port — reconnect the stars"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_color", Color(0.7, 0.78, 0.9))
	v.add_child(sub)

	v.add_child(_button("NEW GAME", _on_new_game))
	_continue_btn = _button("CONTINUE", _on_continue)
	v.add_child(_continue_btn)
	v.add_child(_button("OPTIONS", func(): GameState.popup_requested.emit("options")))


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(220, 36)
	b.pressed.connect(cb)
	return b


func _process(_delta: float) -> void:
	visible = GameState.phase == GameState.Phase.TITLE
	if visible:
		_continue_btn.disabled = not FileAccess.file_exists(SaveLoad.SAVE_PATH)


func _on_new_game() -> void:
	Discovery.init_for_new_game()  # restore new-game fog (backdrop had reveal-all)
	GameState.phase = GameState.Phase.INTRO


func _on_continue() -> void:
	if SaveLoad.load_game():
		GameState.phase = GameState.Phase.GALAXY
