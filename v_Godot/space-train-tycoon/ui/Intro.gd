extends Control
## Intro — narration sequence (PLAN Phase 4, code map §13). Shown while
## GameState.phase == INTRO. The 3 _INTRO_TEXT paragraphs from build_game.py,
## advanced with NEXT, ending in BEGIN → GALAXY; SKIP jumps straight in.
##
## This is the narration core; the full §13 11-shot 3D camera cutscene is the
## deferred cinematic layer (the camera already slowly rotates behind it).

const PARAS := [
	"STARDATE 829.\n\nThirty Stardates have passed since the sudden implosion of the Dutch East Earth Interstellar Trading Company (DEEITC), the once-dominant commercial power whose vast network of trade routes, orbital infrastructure, and wormhole technology bound thousands of planets together into a single galactic economy.\n\nIn the aftermath, entire star systems were cut off from one another, industries collapsed, and countless worlds have endured decades of economic isolation.",
	"Now, a new age of opportunity has begun.\n\nAcross the galaxy, ambitious CORPORATIONS are racing to fill the void left behind. As the newly appointed CEO of one such enterprise, your mission is to reconnect the stars through a new network of SPACE TRAINS.\n\nEstablish profitable trade ROUTES. Transport CARGO from worlds of abundance to worlds in need. Rebuild the foundations of interstellar civilization, one star system at a time.",
	"But commerce alone is not enough. Hidden among the ruins of DEEITC's fallen empire lie the components and knowledge required to reconstruct the legendary WORMHOLE APPARATUS — a colossal device capable of bending space itself.\n\nThe Corporation that rebuilds this ancient technology first will unlock access to THE MULTIVERSE... and the secrets within.\n\nThe race has begun. The stars await.",
]

var _idx := 0
var _was_visible := false
var _text: RichTextLabel
var _next_btn: Button


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	v.custom_minimum_size = Vector2(720, 0)
	center.add_child(v)

	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.custom_minimum_size = Vector2(720, 320)
	v.add_child(_text)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	_next_btn = Button.new()
	_next_btn.text = "NEXT"
	_next_btn.pressed.connect(_on_next)
	row.add_child(_next_btn)
	var skip := Button.new()
	skip.text = "SKIP"
	skip.pressed.connect(_begin)
	row.add_child(skip)
	v.add_child(row)


func _process(_delta: float) -> void:
	visible = GameState.phase == GameState.Phase.INTRO
	if visible and not _was_visible:
		_idx = 0
		_refresh()
	_was_visible = visible


func _refresh() -> void:
	_text.text = "[center]%s[/center]" % PARAS[_idx]
	_next_btn.text = "BEGIN" if _idx >= PARAS.size() - 1 else "NEXT  (%d/%d)" % [_idx + 1, PARAS.size()]


func _on_next() -> void:
	if _idx >= PARAS.size() - 1:
		_begin()
	else:
		_idx += 1
		_refresh()


func _begin() -> void:
	GameState.phase = GameState.Phase.GALAXY
