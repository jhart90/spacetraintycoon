extends Control
## Tutorial — onboarding bubble chain (build_game.py _drawTutorialChain §11),
## the core early phases: welcome → zoom out → click a planet → done. Blue/yellow
## speech bubbles anchored to world bodies; advances on the player's actions.

const W := 900.0
const GH := 428.0
const TOP_H := 28.0

var view: Node2D
var f_exo: Font
var f_orb_b: Font
var phase := "welcome"
var _t := 0.0
var _start_sc := 0.0
var _armed := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	f_exo = load("res://assets/fonts/Exo2-Variable.woff2")
	var orb: Font = load("res://assets/fonts/Orbitron-Variable.woff2")
	var fv := FontVariation.new()
	fv.base_font = orb
	fv.variation_opentype = {"wght": 700}
	f_orb_b = fv


func _process(delta: float) -> void:
	visible = GameState.gs == "galaxy" and phase != "done" and view != null
	if not visible:
		return
	if not _armed:
		_armed = true
		_t = 0.0
		_start_sc = view.sc
	_t += delta
	match phase:
		"welcome":
			if _t > 4.5:
				_go("zoom_out")
		"zoom_out":
			if view.sc < _start_sc * 0.6:
				_go("click_planet")
		"click_planet":
			if String(GameState.selected.get("kind", "")) == "planet":
				_go("done")
	queue_redraw()


func _go(p: String) -> void:
	phase = p
	_t = 0.0
	_start_sc = view.sc


func _draw() -> void:
	if view == null:
		return
	var anchor := _orijen_screen()
	match phase:
		"welcome":
			_bubble(Vector2(anchor.x, anchor.y - 78.0), "Welcome, CEO. This is your HOME PLANET.", anchor, true)
		"zoom_out":
			_bubble(Vector2(W * 0.42, GH * 0.42), "ZOOM OUT using the SCROLL WHEEL or ARROW KEYS", anchor, false)
		"click_planet":
			_bubble(Vector2(anchor.x, anchor.y - 78.0), "CLICK a PLANET to select it and see its details", anchor, false)


func _orijen_screen() -> Vector2:
	var p: Dictionary = Galaxy.planets[Galaxy.origen_id]
	return view._w2s(Vector2(p.x, p.y))


# Rounded speech bubble with a tail pointing toward `target` (build_game.py
# _drawBubble). Blue = narration, yellow = call-to-action.
func _bubble(pos: Vector2, text: String, target: Vector2, is_blue: bool) -> void:
	var pad := 11.0
	var tw := f_exo.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	var bw := tw + pad * 2.0
	var bh := 28.0
	# Keep the bubble inside the galaxy viewport.
	var bx := clampf(pos.x - bw * 0.5, 6.0, W - 190.0 - bw - 6.0)
	var by := clampf(pos.y - bh * 0.5, TOP_H + 6.0, GH - bh - 30.0)
	var r := Rect2(bx, by, bw, bh)
	var fill := Color(0.12, 0.34, 0.66, 0.95) if is_blue else Color(0.95, 0.78, 0.2, 0.96)
	var border := Color(0.4, 0.68, 1.0, 0.9) if is_blue else Color(1.0, 0.9, 0.5, 0.95)
	var text_col := Color(0.92, 0.97, 1.0) if is_blue else Color(0.12, 0.08, 0.0)
	# Tail toward the target (drawn first, under the body).
	var cx := r.position + r.size * 0.5
	var dir := (target - cx)
	if dir.length() > 4.0:
		dir = dir.normalized()
		var base := cx + dir * (bh * 0.5)
		var perp := Vector2(-dir.y, dir.x) * 7.0
		draw_colored_polygon(PackedVector2Array([base - perp, base + perp, cx + dir * (bh * 0.5 + 16.0)]), fill)
	draw_rect(r, fill)
	draw_rect(r, border, false, 1.5)
	draw_string(f_exo, Vector2(bx + pad, by + bh * 0.5 + 4.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, text_col)
