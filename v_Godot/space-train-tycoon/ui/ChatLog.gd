extends Control
## ChatLog — scrolling event feed (PLAN Phase 4, code map §12). Bottom-left.
## Connects to existing autoload signals (no new emitters needed) and keeps the
## last N lines. The JS chat log's SD-timestamp wrap logic is simplified here to
## a flat "[SD] message" feed.

const MAX_LINES := 8
var _label: RichTextLabel
var _lines: Array = []
var _last_delivery_t: float = -999.0
var _t: float = 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel := PanelContainer.new()
	panel.position = Vector2(16, -300)
	panel.custom_minimum_size = Vector2(360, 0)
	add_child(panel)
	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.fit_content = true
	_label.scroll_active = false
	_label.custom_minimum_size = Vector2(336, 0)
	panel.add_child(_label)

	Player.action_done.connect(func(m): add(m, "#9f9"))
	Player.action_failed.connect(func(m): add("can't: " + m, "#f99"))
	Missions.mission_introduced.connect(func(id): add("NEW MISSION: " + _mname(id), "#ffd070"))
	Missions.mission_completed.connect(func(id, r): add("MISSION COMPLETE: %s  (+%d)" % [_mname(id), r], "#9fe0ff"))
	Discovery.star_revealed.connect(func(sid): add("%s — STAR DISCOVERED" % Galaxy.stars[sid].name, "#ffc850"))
	GameState.player_delivered.connect(_on_delivered)


func _process(delta: float) -> void:
	_t += delta


func _on_delivered(rev: int) -> void:
	# Throttle so a fast fleet doesn't flood the log.
	if _t - _last_delivery_t < 1.0:
		return
	_last_delivery_t = _t
	add("delivery: +%d credits" % rev, "#cfe0a0")


func _mname(id: String) -> String:
	var d: Dictionary = Missions.def_for(id)
	return d.get("name", id)


func add(text: String, color: String = "#cfd6e6") -> void:
	_lines.append("[color=%s]SD %.2f  %s[/color]" % [color, GameState.stardate, text])
	while _lines.size() > MAX_LINES:
		_lines.pop_front()
	_label.text = "\n".join(_lines)
