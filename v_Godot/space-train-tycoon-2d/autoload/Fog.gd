extends Node
## Fog — fog-of-war breadcrumb state (build_game.py updateFog/drawFog §16178+).
## The sim accumulates a grid-deduped trail of world positions the player's
## trains have travelled through (`points`), plus bigger reveals around visited
## stars (`star_reveals`) and currently-orbited planets (`orbited`). FogLayer
## renders a black overlay punched with reveal holes at these points.

const REVEAL_R := 5000.0   # world SU — train-car reveal radius (FOG_REVEAL_R)
const GRID := 600.0        # world SU dedup grid cell (FOG_GRID)
const STAR_PAD := 1000.0   # extra radius beyond a star's outer orbit on reveal

var enabled := true
var points: Array = []          # [{x,y}] grid-deduped breadcrumb centres
var star_reveals: Array = []     # [{x,y,r}] big reveals around visited stars
var orbited: Dictionary = {}     # pid -> true (live-position reveals)
var dirty := true
var _grid: Dictionary = {}       # "gx_gy" -> true dedup
var _acc := 0.0

func reset() -> void:
	points = []
	star_reveals = []
	orbited = {}
	_grid = {}
	_acc = 0.0
	dirty = true

## Accumulate breadcrumbs from player train positions (updateFog, throttled to
## ~0.01 SD like the original).
func update(dt_sd: float) -> void:
	_acc += dt_sd
	if _acc < 0.01:
		return
	_acc = 0.0
	for t in Transit.trains:
		if not bool(t.get("isPlayer", false)):
			continue
		_add_point(float(t.get("x", 0.0)), float(t.get("y", 0.0)))

func _add_point(wx: float, wy: float) -> void:
	var gx := int(floor(wx / GRID))
	var gy := int(floor(wy / GRID))
	var key := "%d_%d" % [gx, gy]
	if _grid.has(key):
		return
	_grid[key] = true
	points.append({"x": wx, "y": wy})
	dirty = true

## Reveal a whole star system (build_game.py:15937) — radius = outermost orbit.
func reveal_star(s: Dictionary) -> void:
	var max_orbit := 0.0
	for pid in s.get("planetIds", []):
		var p: Dictionary = Galaxy.planets[int(pid)] if int(pid) < Galaxy.planets.size() else {}
		max_orbit = maxf(max_orbit, float(p.get("orbitRadius", 0.0)))
	star_reveals.append({"x": float(s.get("x", 0.0)), "y": float(s.get("y", 0.0)), "r": max_orbit + STAR_PAD})
	dirty = true

## A planet that has been orbited keeps a live reveal (build_game.py:15948).
func reveal_orbited(pid: int) -> void:
	if not orbited.has(pid):
		orbited[pid] = true
		dirty = true
