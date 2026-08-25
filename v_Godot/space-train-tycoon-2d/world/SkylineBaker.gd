extends Node2D
## SkylineBaker — draws the urban cityscape (and, later, ancient ruins) skyline
## ONCE into a SubViewport so GalaxyContent can blit the baked texture scaled per
## planet (faithful to build_game.py _buildUrbanSkylineCache:12567 — bake once,
## drawImage many). Reference frame: refR=280, halo=110, halfW=390, 780×780.

var mode := "city"

const REF_R := 280.0
const HALO := 110.0
const HALF_W := REF_R + HALO  # 390
const SC := REF_R / 80.0      # 3.5 — rescales the original 80px design

var _seed: int = 0

# JS LCG (build_game.py:12582): _seed=(_seed*1103515245+12345)&0x7fffffff.
func _rng() -> float:
	_seed = (_seed * 1103515245 + 12345) & 0x7fffffff
	return float(_seed) / float(0x7fffffff)


func _draw() -> void:
	if mode == "city":
		_draw_city()
	else:
		_draw_ruins()


func _draw_city() -> void:
	_seed = 1234567
	var ctr := Vector2(HALF_W, HALF_W)
	var col_tall := Color8(82, 96, 118, 235)
	var col_light := Color8(64, 76, 98, 219)
	var col_dark := Color8(46, 58, 80, 204)
	var col_win := Color8(255, 225, 140, 199)
	# ── Surface buildings (dense radial rects inside the disc) ──
	var surf_n := int(round(900.0 * SC * SC))
	for i in surf_n:
		var rd := sqrt(_rng()) * REF_R * 0.97
		var th := _rng() * TAU
		var pos := ctr + Vector2(rd * cos(th), rd * sin(th))
		var dn := Vector2(cos(th), sin(th))   # radial outward
		var tn := Vector2(-dn.y, dn.x)         # tangent
		var bw := (2.2 + _rng() * 2.6) * SC
		var bh := (1.8 + _rng() * 4.5) * SC
		var is_tall := _rng() < 0.15
		var w2 := (bw * 1.05 if is_tall else bw) * 0.5
		var h2 := (bh * 1.8 if is_tall else bh) * 0.5
		var fill := col_tall if is_tall else (col_light if _rng() < 0.35 else col_dark)
		draw_colored_polygon(PackedVector2Array([
			pos - tn * w2 - dn * h2, pos + tn * w2 - dn * h2,
			pos + tn * w2 + dn * h2, pos - tn * w2 + dn * h2,
		]), fill)
		var wr := _rng()
		if wr < 0.04:
			var ws := maxf(0.9, h2 * 2.0 * 0.18)
			var off := h2 * 2.0 * 0.22
			draw_rect(Rect2(pos + dn * -off - Vector2(ws, ws) * 0.5, Vector2(ws, ws)), col_win)
			draw_rect(Rect2(pos + dn * off - Vector2(ws, ws) * 0.5, Vector2(ws, ws)), col_win)
		elif wr < 0.19:
			var ws := maxf(0.9, h2 * 2.0 * 0.20)
			var off := h2 * 2.0 * 0.12
			draw_rect(Rect2(pos + dn * off - Vector2(ws, ws) * 0.5, Vector2(ws, ws)), col_win)
	# ── Skyline (towers radiating from the silhouette, packed 0→2π) ──
	var ang := 0.0
	var bi := 0
	while ang < TAU - 0.001:
		var style_r := _rng()
		var style := 1 if style_r < 0.18 else (2 if style_r < 0.40 else 0)
		var dang: float
		if style == 0: dang = 0.055 + _rng() * 0.045
		elif style == 1: dang = 0.085 + _rng() * 0.06
		else: dang = 0.07 + _rng() * 0.055
		if ang + dang > TAU: dang = TAU - ang
		var ac := ang + dang * 0.5
		var ca := cos(ac)
		var sa := sin(ac)
		var tn := Vector2(-sa, ca)
		var base := ctr + Vector2(ca, sa) * REF_R
		if style == 1:
			var sub_n := 6 + int(_rng() * 4)
			var w_per := (dang * REF_R) / float(sub_n)
			var hs: Array = []
			for k in sub_n: hs.append(REF_R * (0.20 + _rng() * 0.20))
			hs.sort()
			var mid := (sub_n - 1) / 2.0
			for k in sub_n:
				var d := absf(k - mid)
				var h: float = hs[hs.size() - 1 - int(round(d))]
				var off := (k - (sub_n - 1) / 2.0) * w_per
				var sb := base + tn * off
				var st := ctr + Vector2(ca, sa) * (REF_R + h) + tn * off
				_trap(sb, st, tn, w_per * 0.96, w_per * 0.92, Color8(38, 50, 70, 247))
				_win(sb, st, 1, bi * sub_n + k)
		elif style == 2:
			var h := REF_R * (0.10 + _rng() * 0.20)
			var wt := dang * REF_R * 0.96
			var top := ctr + Vector2(ca, sa) * (REF_R + h)
			_trap(base, top, tn, wt, wt * 0.95, Color8(50, 62, 82, 242))
			_win(base, top, 2, bi)
		else:
			var h := REF_R * (0.06 + _rng() * 0.30)
			var wt := dang * REF_R * 0.96
			var top := ctr + Vector2(ca, sa) * (REF_R + h)
			_trap(base, top, tn, wt, wt * 0.93, Color8(44, 56, 78, 242))
			if h > REF_R * 0.18: _win(base, top, 0, bi)
		ang += dang
		bi += 1


func _trap(base: Vector2, top: Vector2, tn: Vector2, wb: float, wt: float, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([
		base - tn * wb * 0.5, base + tn * wb * 0.5, top + tn * wt * 0.5, top - tn * wt * 0.5,
	]), col)

func _win(base: Vector2, top: Vector2, style: int, seed: int) -> void:
	var h := base.distance_to(top)
	var wn := maxi(2, int(floor(h / (4.0 * SC))))
	var ws := 1.2 * SC
	var win := Color8(255, 220, 140, 209)
	for w in wn:
		if ((seed * 7 + w * 11 + style * 3) % 5) < 2:
			var f := (w + 0.5) / float(wn)
			var p := base + (top - base) * f
			draw_rect(Rect2(p - Vector2(ws, ws) * 0.5, Vector2(ws, ws)), win)


func _quad4(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([p0, p1, p2, p3]), col)


# _buildAncientRuinsCache (build_game.py:12759) — broken-column clusters around
# the rim, a central Temple of Jupiter, and floating debris in the halo.
func _draw_ruins() -> void:
	_seed = 24681357
	var ctr := Vector2(HALF_W, HALF_W)
	var c_light := Color8(228, 206, 168, 245)
	var c_mid := Color8(192, 166, 118, 240)
	var c_shade := Color8(138, 108, 72, 224)
	var c_dark := Color8(86, 62, 38, 199)
	var c_float := Color8(208, 180, 138, 209)
	# ── Surface ruin clusters (broken columns on platforms) ──
	var n_clusters := 28 + int(_rng() * 10)
	for i in n_clusters:
		var bang := _rng() * TAU
		var br := REF_R * (0.82 + _rng() * 0.14)
		var b := ctr + Vector2(cos(bang), sin(bang)) * br
		var d := Vector2(cos(bang), sin(bang))  # radial outward = column "up"
		var t := Vector2(-d.y, d.x)             # tangent
		var n_cols := 2 + int(_rng() * 4)
		var col_h := (7.0 + _rng() * 9.0) * SC
		var col_w := (1.4 + _rng() * 0.6) * SC
		var gap := (2.4 + _rng() * 0.8) * SC
		var plat_w := gap * (n_cols - 1) + col_w * 2.4
		var plat_h := col_w * 0.55
		_quad4(b - t * plat_w * 0.5, b + t * plat_w * 0.5, b + t * plat_w * 0.5 + d * plat_h, b - t * plat_w * 0.5 + d * plat_h, c_mid)
		for k in n_cols:
			var ofs := (k - (n_cols - 1) / 2.0) * gap
			var cbase := b + t * ofs + d * plat_h
			var h := col_h * (0.35 + _rng() * 0.7)
			var hw := col_w / 2.0
			var plw := col_w * 1.55
			var plh := col_w * 0.42
			_quad4(cbase - t * plw * 0.5, cbase + t * plw * 0.5, cbase + t * plw * 0.5 + d * plh, cbase - t * plw * 0.5 + d * plh, c_mid)
			var sbase := cbase + d * plh
			var top := sbase + d * h
			_quad4(sbase - t * hw, sbase + t * hw, top + t * hw, top - t * hw, c_light if k % 2 == 0 else c_shade)
			for fi in 3:  # 3 fluting grooves
				var fo := (float(fi) - 1.0) * col_w * 0.30
				var fw := col_w * 0.09
				var fb := sbase + t * fo
				var ft := top + t * fo
				_quad4(fb - t * fw * 0.5, fb + t * fw * 0.5, ft + t * fw * 0.5, ft - t * fw * 0.5, c_dark)
			if _rng() < 0.75:  # capital (echinus + abacus)
				var capw := col_w * 1.45
				var caph := col_w * 0.42
				_quad4(top - t * capw * 0.5, top + t * capw * 0.5, top + t * capw * 0.5 + d * caph, top - t * capw * 0.5 + d * caph, c_light)
				var abw := capw * 1.22
				var abh := caph * 0.55
				var ab := top + d * caph
				_quad4(ab - t * abw * 0.5, ab + t * abw * 0.5, ab + t * abw * 0.5 + d * abh, ab - t * abw * 0.5 + d * abh, c_mid)
		if _rng() < 0.55 and n_cols >= 2:  # broken architrave
			var span := 0.55 + _rng() * 0.4
			var a0 := b - t * plat_w * 0.5 * span + d * (plat_h + col_h)
			var a1 := b + t * plat_w * 0.5 * span + d * (plat_h + col_h)
			var ah := col_w * 0.7
			_quad4(a0, a1, a1 + d * ah, a0 + d * ah, c_shade)
	# ── Temple of Jupiter (upright, near centre) ──
	var tcx := HALF_W - REF_R * 0.16
	var tcy := HALF_W - REF_R * 0.20
	var tw := REF_R * 0.36
	var th := REF_R * 0.32
	var pdh := th * 0.07
	for s in 3:
		var sw := tw * (1.0 - s * 0.06)
		var sy := tcy + th * 0.40 - pdh * s
		draw_rect(Rect2(tcx - sw * 0.5, sy, sw, pdh), c_shade if s == 0 else (c_mid if s == 1 else c_light))
	var n_col := 6
	var col_span := tw * 0.80
	var col_wt := col_span / (n_col * 2.2)
	var col_ht := th * 0.46
	var col_top_y := tcy + th * 0.40 - pdh * 3 - col_ht
	var col_bot_y := tcy + th * 0.40 - pdh * 3
	for k in n_col:
		var xc := tcx - col_span * 0.5 + (k + 0.5) * (col_span / n_col)
		draw_rect(Rect2(xc - col_wt * 0.5, col_top_y, col_wt, col_ht), c_light)
		draw_rect(Rect2(xc + col_wt * 0.18, col_top_y, col_wt * 0.32, col_ht), c_shade)
		draw_rect(Rect2(xc - col_wt * 0.18, col_top_y, col_wt * 0.07, col_ht), c_dark)
		draw_rect(Rect2(xc + col_wt * 0.06, col_top_y, col_wt * 0.07, col_ht), c_dark)
		draw_rect(Rect2(xc - col_wt * 0.75, col_top_y - th * 0.035, col_wt * 1.5, th * 0.035), c_light)
		draw_rect(Rect2(xc - col_wt * 0.65, col_bot_y - th * 0.025, col_wt * 1.3, th * 0.025), c_mid)
	var ent_h := th * 0.11
	var ent_y := col_top_y - th * 0.035 - ent_h
	draw_rect(Rect2(tcx - tw * 0.44, ent_y, tw * 0.88, ent_h), c_mid)
	draw_rect(Rect2(tcx - tw * 0.44, ent_y + ent_h * 0.58, tw * 0.88, ent_h * 0.10), c_shade)
	for dd in 15:
		draw_rect(Rect2(tcx - tw * 0.42 + dd * (tw * 0.058), ent_y + ent_h * 0.72, tw * 0.030, ent_h * 0.22), c_dark)
	var ped_h := th * 0.21
	_quad4(Vector2(tcx - tw * 0.46, ent_y), Vector2(tcx + tw * 0.46, ent_y), Vector2(tcx, ent_y - ped_h), Vector2(tcx, ent_y - ped_h), c_light)
	draw_polyline(PackedVector2Array([Vector2(tcx - tw * 0.46, ent_y), Vector2(tcx, ent_y - ped_h), Vector2(tcx + tw * 0.46, ent_y)]), c_shade, maxf(1.0, SC * 0.5))
	_quad4(Vector2(tcx - tw * 0.38, ent_y - ped_h * 0.10), Vector2(tcx + tw * 0.38, ent_y - ped_h * 0.10), Vector2(tcx, ent_y - ped_h * 0.82), Vector2(tcx, ent_y - ped_h * 0.82), c_mid)
	draw_rect(Rect2(tcx - tw * 0.018, ent_y - ped_h - th * 0.030, tw * 0.036, th * 0.030), c_light)
	draw_rect(Rect2(tcx - col_span * 0.18, col_top_y + col_ht * 0.10, col_span * 0.36, col_ht * 0.55), c_dark)
	# ── Floating debris in the halo ──
	var n_debris := 44 + int(_rng() * 22)
	for i in n_debris:
		var dang := _rng() * TAU
		var dr := REF_R + 6.0 + _rng() * HALO * 0.75
		var dpos := ctr + Vector2(cos(dang), sin(dang)) * dr
		var ds := (1.8 + _rng() * 4.0) * SC
		draw_set_transform(dpos, _rng() * TAU, Vector2.ONE)
		var shape := _rng()
		if shape < 0.62:
			draw_rect(Rect2(-ds * 0.32, -ds * 1.3, ds * 0.64, ds * 2.6), c_float)
		elif shape < 0.85:
			draw_colored_polygon(PackedVector2Array([Vector2(-ds * 1.05, -ds * 0.45), Vector2(ds * 1.05, -ds * 0.45), Vector2(ds * 0.10, -ds * 1.30)]), c_float)
			draw_rect(Rect2(-ds * 1.25, -ds * 0.45, ds * 2.5, ds * 0.32), c_mid)
			draw_rect(Rect2(-ds * 1.25, -ds * 0.13, ds * 2.5, ds * 0.08), c_shade)
			for di in 5:
				draw_rect(Rect2((di - 2) * ds * 0.42 - ds * 0.10, -ds * 0.05, ds * 0.20, ds * 0.22), c_dark)
		else:
			draw_rect(Rect2(-ds * 0.9, -ds * 0.5, ds * 1.8, ds), c_float)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
