extends Node2D
## Labels — world-anchored text drawn in SCREEN space (so fonts stay crisp and
## fixed-size, like the JS which draws star/BH names at clamped px sizes). The
## JS HD-text-overlay hack is gone: native draw_string is sharp for free.
## M4 swaps the fallback font for the real Exo 2 theme.

var view: Node2D  # GalaxyView2D controller
var _font: Font


func _ready() -> void:
	_font = ThemeDB.fallback_font


func _draw() -> void:
	var sc: float = view.sc
	# Star names (build_game.py:28633): under the disc, clamped 10..13px.
	for s in Galaxy.stars:
		var sp: Vector2 = view._w2s(Vector2(s.x, s.y))
		var sr := float(s.radius) * sc
		if sr <= 5.0:
			continue
		if sp.x < -60.0 or sp.x > Tuning.W + 60.0 or sp.y < 0.0 or sp.y > Tuning.GH:
			continue
		var fs := int(clampf(sr * 0.14 + 9.0, 10.0, 13.0))
		_centered(String(s.name), Vector2(sp.x, sp.y + sr + 14.0), fs, Color(1.0, 0.90, 0.59, 0.85))
	# Black hole names (build_game.py:28559).
	for b in Galaxy.black_holes:
		var bp: Vector2 = view._w2s(Vector2(b.x, b.y))
		var bsr := float(b.radius) * sc
		if bsr <= 12.0:
			continue
		var bfs := int(clampf(bsr * 0.14 + 8.0, 10.0, 13.0))
		_centered("BLACK HOLE", Vector2(bp.x, bp.y + bsr * 0.5), bfs, Color(0.31, 0.31, 0.31, 0.85))


func _centered(text: String, pos: Vector2, font_size: int, color: Color) -> void:
	var w := 240.0
	draw_string(_font, Vector2(pos.x - w * 0.5, pos.y), text, HORIZONTAL_ALIGNMENT_CENTER, w, font_size, color)
