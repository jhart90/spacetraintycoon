extends Node2D
## ScreenBackground — the screen-space backdrop drawn BEFORE the clipped world
## content (build_game.py drawGalaxy: bg fill → nebula sheet → parallax stars).
## Drawn in logical 900×500 coords (NOT camera-transformed).

var view: Node2D  # GalaxyView2D controller (cam/sc/star_pan)

const BG := Color("#04060f")

# Background parallax stars (build_game.py:11756-11758): {bx,by,r,b,depth}.
var _g_stars: Array = []
# Simple faint nebula blobs (M1 stand-in for the baked nebula sheet, §4.2).
var _nebula: Array = []

const _NEBULA_COLS := [
	Color(0.30, 0.16, 0.42), Color(0.12, 0.22, 0.40),
	Color(0.40, 0.18, 0.24), Color(0.14, 0.30, 0.34), Color(0.24, 0.18, 0.44),
]


# Parallax stars are drawn as ONE batched draw_multimesh call (was ~550
# individual draw_circle calls/frame = the dominant frame cost). A unit white
# quad per instance; per-frame we update transform (parallax) + colour (twinkle).
var _mm: MultiMesh
var _star_tex: Texture2D

func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x5713A2  # stable layout across runs
	for i in 800:
		_g_stars.append({
			"bx": rng.randf_range(0.0, Tuning.W), "by": rng.randf_range(0.0, Tuning.H),
			"r": rng.randf_range(0.3, 2.2), "b": rng.randf_range(0.35, 1.0),
			"depth": rng.randf_range(0.03, 0.38),
		})
	for i in 7:
		_nebula.append({
			"x": rng.randf_range(0.0, Tuning.W), "y": rng.randf_range(0.0, Tuning.H),
			"r": rng.randf_range(190.0, 380.0), "depth": rng.randf_range(0.015, 0.04),
			"col": _NEBULA_COLS[i % _NEBULA_COLS.size()], "a": rng.randf_range(0.05, 0.10),
		})
	# MultiMesh of unit quads — one batched draw call for all stars.
	var qm := QuadMesh.new()
	qm.size = Vector2(1.0, 1.0)
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_2D
	_mm.use_colors = true
	_mm.mesh = qm
	_mm.instance_count = _g_stars.size()
	# 3x3 white texture (crisp dot; avoids soft glow halo per star).
	var img := Image.create(3, 3, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 1))
	_star_tex = ImageTexture.create_from_image(img)


func _draw() -> void:
	draw_rect(Rect2(0, 0, Tuning.W, Tuning.H), BG)
	var gt: Texture2D = view.glow_tex
	var sp: Vector2 = view.star_pan
	# Faint nebula blobs (deep parallax).
	for nb in _nebula:
		var nx: float = nb.x - sp.x * nb.depth
		var ny: float = nb.y - sp.y * nb.depth
		var c: Color = nb.col
		c.a = nb.a
		_blob(gt, Vector2(nx, ny), nb.r, c)
	# Zoom-responsive parallax background stars — batched (build_game.py:28581).
	var zt := _zoom_t()
	var draw_count := int(round(80.0 + 620.0 * pow(1.0 - zt, 0.65)))
	var size_scale := 0.38 + zt * 0.62
	var ts := float(Time.get_ticks_msec())
	var n: int = mini(draw_count, _g_stars.size())
	_mm.visible_instance_count = n
	for i in n:
		var s: Dictionary = _g_stars[i]
		var px := fposmod(s.bx - sp.x * s.depth, Tuning.W)
		var py := fposmod(s.by - sp.y * s.depth, Tuning.H)
		var a: float = s.b * (0.55 + 0.45 * sin(ts * 0.0008 + s.bx * 0.1))
		var sz: float = maxf(0.8, s.r * size_scale * 2.0)
		_mm.set_instance_transform_2d(i, Transform2D(0.0, Vector2(sz, sz), 0.0, Vector2(px, py)))
		_mm.set_instance_color(i, Color(1, 1, 1, a))
	if n > 0:
		draw_multimesh(_mm, _star_tex)


func _zoom_t() -> float:
	return clampf((log(view.sc) - log(Tuning.MIN_SC)) / (log(Tuning.MAX_SC) - log(Tuning.MIN_SC)), 0.0, 1.0)

func _blob(gt: Texture2D, c: Vector2, radius: float, color: Color) -> void:
	draw_texture_rect(gt, Rect2(c - Vector2(radius, radius), Vector2(radius * 2.0, radius * 2.0)), false, color)
