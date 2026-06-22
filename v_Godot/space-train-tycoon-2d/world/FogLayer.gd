extends Node2D
## FogLayer — fog-of-war overlay (build_game.py drawFog §16200). A SubViewport
## renders the reveal MASK (white radial stamps at the player's explored points,
## visited star systems, and orbited planets); fog.gdshader turns that mask into
## a 92%-black overlay with soft reveal holes. Drawn after the galaxy bodies so
## it fogs everything, but under the HUD CanvasLayer so chrome stays clear.

var view: Node2D  # GalaxyView2D
var _vp: SubViewport
var _drawer: _MaskDrawer
var _stamp: Texture2D
var _last_cam := Vector2.INF
var _last_sc := -1.0


func _ready() -> void:
	_stamp = _make_stamp(128)
	_vp = SubViewport.new()
	_vp.size = Vector2i(int(Tuning.W), int(Tuning.GH))
	_vp.transparent_bg = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	_vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	add_child(_vp)
	_drawer = _MaskDrawer.new()
	_drawer.layer = self
	_vp.add_child(_drawer)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://world/fog.gdshader")
	material = mat


func _process(_dt: float) -> void:
	if not Fog.enabled or Fog.points.is_empty():
		return
	# Re-render the reveal mask ONLY when the camera moved or fog changed (the
	# original caches drawFog the same way) — saves the SubViewport pass while idle.
	if view.cam != _last_cam or view.sc != _last_sc or Fog.dirty:
		_last_cam = view.cam
		_last_sc = view.sc
		Fog.dirty = false
		_drawer.queue_redraw()
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	queue_redraw()  # composite the cached mask over the (every-frame) galaxy redraw


func _draw() -> void:
	if not Fog.enabled or Fog.points.is_empty():
		return
	draw_texture_rect(_vp.get_texture(), Rect2(0, 0, Tuning.W, Tuning.GH), false)


# Radial reveal stamp: flat opaque core then a soft fade to transparent
# (build_game.py fogStamp radialGradient 29→100).
func _make_stamp(n: int) -> Texture2D:
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c := (n - 1) * 0.5
	for y in n:
		for x in n:
			var d := Vector2(x - c, y - c).length() / (n * 0.5)
			var a := 0.0
			if d < 0.29:
				a = 1.0
			elif d < 1.0:
				a = clampf(1.0 - (d - 0.29) / 0.71, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


# Draws the reveal mask into the SubViewport each frame (screen-space, follows cam).
class _MaskDrawer extends Node2D:
	var layer  # FogLayer

	func _draw() -> void:
		var view = layer.view
		var sc: float = view.sc
		var stamp: Texture2D = layer._stamp
		# Breadcrumb reveals — bucketed by world cell to drop redundant stamps.
		# ×1.2 matches the JS stamp diameter (sr*2.4 → radius 1.2·sr).
		var rev := Fog.REVEAL_R * 1.2 * sc
		var seen := {}
		var cell := maxf(Fog.GRID, Fog.REVEAL_R * 0.5)
		for pt in Fog.points:
			var bx := int(floor(pt.x / cell))
			var by := int(floor(pt.y / cell))
			var key := (bx * 65537) ^ by
			if seen.has(key):
				continue
			seen[key] = true
			_stamp_at(view._w2s(Vector2(pt.x, pt.y)), rev, stamp)
		# Visited-star-system reveals (JS draws revR*2 with a gradient out to ×1.1).
		for srv in Fog.star_reveals:
			_stamp_at(view._w2s(Vector2(srv.x, srv.y)), float(srv.r) * 2.2 * sc, stamp)
		# Live orbited-planet reveals (JS 3000 out to ×1.1 = 3300).
		for pid in Fog.orbited:
			var p: Dictionary = Galaxy.planets[int(pid)] if int(pid) < Galaxy.planets.size() else {}
			if p.is_empty():
				continue
			_stamp_at(view._w2s(Vector2(p.x, p.y)), 3300.0 * sc, stamp)

	func _stamp_at(sp: Vector2, r: float, stamp: Texture2D) -> void:
		if r < 1.0:
			return
		if sp.x + r < 0.0 or sp.x - r > Tuning.W or sp.y + r < 0.0 or sp.y - r > Tuning.GH:
			return
		draw_texture_rect(stamp, Rect2(sp - Vector2(r, r), Vector2(r * 2.0, r * 2.0)), false)
