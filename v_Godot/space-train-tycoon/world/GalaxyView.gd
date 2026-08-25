extends Node3D
## GalaxyView — the 3D galaxy root + camera rig (PLAN §2 world/, §3 boundary).
##
## PHASE 0 SPIKE: hardcoded 3 stars + 5 planets as placeholder spheres, an
## orbit/pan/zoom camera rig, and raycast picking. Proves the hybrid 2D/3D
## boundary end to end:
##   - Screen→world picking via project_ray_origin/normal + PhysicsRayQuery (§3).
##   - World→screen via camera.unproject_position, pushed into GameState so the
##     HUD can float a label without ever reading this 3D tree (§3).
##
## Phase 1 replaces the hardcoded data with Galaxy.generate(seed) output.

# World→Godot scale: 1 Godot unit = (1/WORLD_SCALE) game world-units.
# Galaxy spans ~±200k world-units → ~±200 Godot units at 0.001.
const WORLD_SCALE := 0.001
const DEFAULT_SEED := 12345

# --- Camera rig state ---
var _cam: Camera3D
var _pivot: Vector3 = Vector3.ZERO   # point the camera orbits / WASD pans
var _yaw: float = 0.0
var _pitch: float = -1.05             # near top-down (the 2D game was top-down)
var _distance: float = 460.0
const MIN_DIST := 8.0
const MAX_DIST := 1600.0
const MIN_PITCH := -1.45              # almost straight down
const MAX_PITCH := -0.20              # shallow angle
var _dragging := false
var _reveal_all := false  # debug fog toggle (F key)
var _station_nodes: Dictionary = {}  # planet id -> station-ring MeshInstance3D
var _space_resume_idx := Tuning.SPEED_DEFAULT_IDX  # speed to restore on un-pause

# --- World model (placeholder) ---
# id -> {node: MeshInstance3D, kind: String, name: String, world_pos: Vector3}
var _bodies: Dictionary = {}
var _selection_ring: MeshInstance3D


func _ready() -> void:
	_build_environment()
	_build_camera()
	Galaxy.generate(DEFAULT_SEED)
	GameState.start_new_game()
	Missions.start_new_game()
	Discovery.init_for_new_game()
	_build_from_galaxy()
	AICorp.init_corp("normal")
	_setup_trains()
	_build_selection_ring()
	_update_camera()
	GameState.selection_changed.connect(_on_selection_changed)
	# Start at the title screen over a fully-revealed, slowly-rotating backdrop.
	# (New Game restores the fog via Discovery.init_for_new_game.)
	Discovery.reveal_all()
	GameState.phase = GameState.Phase.TITLE

func _w2g(x: float, y: float) -> Vector3:
	# Galaxy plane lies in XZ (JS y → Godot z), matching the 2D top-down view.
	return Vector3(x * WORLD_SCALE, 0.0, y * WORLD_SCALE)


# ---------------------------------------------------------------------------
# Scene construction
# ---------------------------------------------------------------------------

func _build_environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.02, 0.06)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.38, 0.5)
	env.ambient_light_energy = 0.6
	# Glow gives emissive stars a cheap bloom — a taste of the Phase 5 look.
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.glow_bloom = 0.2
	we.environment = env
	add_child(we)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-55, -30, 0)
	key.light_energy = 0.7
	add_child(key)


func _build_camera() -> void:
	_cam = Camera3D.new()
	_cam.fov = 55.0
	_cam.far = 4000.0
	add_child(_cam)


func _sphere(radius: float, color: Color, emissive: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 32
	mesh.rings = 16
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	if emissive:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 3.0
	mi.material_override = mat
	return mi


## Adds a clickable body: a visual sphere + a StaticBody3D sphere collider tagged
## with metadata so picking can resolve it back to a logical id. `meta` carries
## fog-relevant fields (star_id / planet_id / base_color).
func _add_body(id: String, kind: String, display_name: String, world_pos: Vector3, radius: float, color: Color, emissive: bool, meta: Dictionary = {}) -> void:
	var mi := _sphere(radius, color, emissive)
	mi.position = world_pos
	add_child(mi)

	var body := StaticBody3D.new()
	body.position = world_pos
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	shape.shape = sphere
	body.add_child(shape)
	body.set_meta("kind", kind)
	body.set_meta("id", id)
	body.set_meta("display_name", display_name)
	add_child(body)

	var entry := {"node": mi, "collider": body, "kind": kind, "name": display_name,
		"world_pos": world_pos, "radius": radius, "base_color": color, "emissive": emissive,
		"relic_ring": null}
	entry.merge(meta)
	_bodies[id] = entry


## Build the 3D scene from the generated Galaxy autoload state (PLAN Phase 1).
func _build_from_galaxy() -> void:
	# Black holes — dark sphere + glowing accretion disk (Phase 5).
	for i in Galaxy.black_holes.size():
		var b: Dictionary = Galaxy.black_holes[i]
		var bpos := _w2g(b.x, b.y)
		var br: float = b.radius * WORLD_SCALE
		_add_body("bh_%d" % i, "blackhole", "Black Hole", bpos, br, Color(0.02, 0.0, 0.03), false)
		_add_accretion_disk(bpos, br)

	# Stars (emissive, colour by palette).
	for s in Galaxy.stars:
		var col := _star_color(s.colorName)
		_add_body("star_%d" % s.id, "star", s.name, _w2g(s.x, s.y), s.radius * WORLD_SCALE, col, true,
			{"star_id": s.id})

	# Planets — biome-styled materials; some gas/storm worlds get rings.
	for p in Galaxy.planets:
		var pcol := Color.html(String(p.type.base))
		var pr: float = max(p.radius * WORLD_SCALE, 0.12)  # floor so tiny worlds stay clickable
		var pid_key := "planet_%d" % p.id
		_add_body(pid_key, "planet", p.name, _w2g(p.x, p.y), pr, pcol, false,
			{"planet_id": p.id, "star_id": p.starId})
		_style_planet(_bodies[pid_key].node, p, pr)
		if p.isAlienRelic:
			_bodies[pid_key].relic_ring = _add_relic_marker(_w2g(p.x, p.y), pr)

	_apply_fog()
	Discovery.discovery_changed.connect(_apply_fog)


func _star_color(color_name: String) -> Color:
	var entry = Tuning.STAR_COLORS.get(color_name, null)
	if entry == null:
		return Color(1, 1, 1)
	return Color.html(String(entry.core))


func _add_relic_marker(pos: Vector3, body_r: float) -> MeshInstance3D:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = body_r * 1.8
	torus.outer_radius = body_r * 2.1
	ring.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.95, 0.4)
	mat.emission_enabled = true
	mat.emission = Color(0.3, 0.95, 0.4)
	mat.emission_energy_multiplier = 2.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = mat
	ring.rotation_degrees = Vector3(90, 0, 0)
	ring.position = pos
	add_child(ring)
	return ring


## Biome-aware planet material (Phase 5 overhaul): atmosphere rim + per-biome
## emission/roughness, and a ring on some gas/storm/ocean worlds.
func _style_planet(node: MeshInstance3D, p: Dictionary, pr: float) -> void:
	var mat: StandardMaterial3D = node.material_override
	if mat == null:
		return
	mat.rim_enabled = true
	mat.rim = 0.55
	mat.rim_tint = 0.5
	var bio := String(p.type.id)
	match bio:
		"lava":
			mat.emission_enabled = true
			mat.emission = Color(1.0, 0.35, 0.08)
			mat.emission_energy_multiplier = 1.3
			mat.roughness = 0.7
		"ice":
			mat.roughness = 0.15
			mat.metallic = 0.15
		"ocean", "resort":
			mat.roughness = 0.25
			mat.metallic = 0.2
		"storm":
			mat.emission_enabled = true
			mat.emission = Color(0.45, 0.2, 0.75)
			mat.emission_energy_multiplier = 0.45
		"oil", "chemical":
			mat.roughness = 0.92
		_:
			mat.roughness = 0.8
	var rim: Array = p.type.rim
	if bio in ["storm", "ocean", "chemical"] and (p.id % 5 == 0):
		_add_planet_ring(node, pr, Color8(rim[0], rim[1], rim[2]))


func _add_planet_ring(parent: Node3D, pr: float, color: Color) -> void:
	var ring := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = pr * 1.5
	t.outer_radius = pr * 2.5
	ring.mesh = t
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(color.r, color.g, color.b, 0.5)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = m
	ring.rotation_degrees = Vector3(72, 0, 18)
	parent.add_child(ring)


## Black-hole accretion disk: two flat emissive annuli (read as glowing under the
## bloom environment). The dark sphere is the event horizon.
func _add_accretion_disk(pos: Vector3, br: float) -> void:
	for spec in [{"i": br * 1.2, "o": br * 2.6, "c": Color(1.0, 0.5, 0.12)}, {"i": br * 1.02, "o": br * 1.2, "c": Color(1.0, 0.9, 0.6)}]:
		var disk := MeshInstance3D.new()
		var t := TorusMesh.new()
		t.inner_radius = spec.i
		t.outer_radius = spec.o
		disk.mesh = t
		var m := StandardMaterial3D.new()
		m.albedo_color = spec.c
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		disk.material_override = m
		disk.rotation_degrees = Vector3(82, 0, 12)
		disk.position = pos
		add_child(disk)


func _make_station_ring(pr: float) -> MeshInstance3D:
	var ring := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = pr * 1.25
	t.outer_radius = pr * 1.45
	ring.mesh = t
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.45, 0.65, 1.0)
	m.emission_enabled = true
	m.emission = Color(0.45, 0.7, 1.0)
	m.emission_energy_multiplier = 1.4
	ring.material_override = m
	ring.rotation_degrees = Vector3(64, 0, 0)
	return ring


## Apply the discovery fog to every body (PLAN Phase 1; §10).
##  - Star not revealed → hidden (mesh + collider). Revealed → visible.
##  - Planet whose star is unrevealed → hidden.
##  - Planet discovered-but-unvisited → blacked-out disc, no relic ring.
##  - Planet visited → biome colour, relic ring shown.
##  - Black holes are always visible (giant landmarks, not fogged in the JS).
func _apply_fog() -> void:
	for id in _bodies:
		var e: Dictionary = _bodies[id]
		match e.kind:
			"blackhole":
				_set_body_visible(e, true)
			"star":
				_set_body_visible(e, Discovery.is_star_revealed(e.star_id))
			"planet":
				var star_seen: bool = Discovery.is_star_revealed(e.star_id)
				_set_body_visible(e, star_seen)
				if star_seen:
					var tier: int = Discovery.planet_tier(e.planet_id)
					var visited: bool = tier == Discovery.Tier.VISITED
					_tint_body(e, e.base_color if visited else Color(0.04, 0.04, 0.05))
					if e.relic_ring != null:
						e.relic_ring.visible = visited


func _set_body_visible(e: Dictionary, vis: bool) -> void:
	e.node.visible = vis
	# Disable picking on hidden bodies by parking their collision layer.
	e.collider.collision_layer = 1 if vis else 0
	if e.get("relic_ring") != null and not vis:
		e.relic_ring.visible = false


func _tint_body(e: Dictionary, col: Color) -> void:
	var mat: StandardMaterial3D = e.node.material_override
	if mat:
		mat.albedo_color = col


func _build_selection_ring() -> void:
	_selection_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 1.7
	torus.outer_radius = 2.0
	_selection_ring.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 1.0, 0.6)
	mat.emission_enabled = true
	mat.emission = Color(0.4, 1.0, 0.6)
	mat.emission_energy_multiplier = 2.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_selection_ring.material_override = mat
	_selection_ring.rotation_degrees = Vector3(90, 0, 0)  # lie flat in the XZ plane
	_selection_ring.visible = false
	add_child(_selection_ring)


# ---------------------------------------------------------------------------
# Camera rig
# ---------------------------------------------------------------------------

func _update_camera() -> void:
	var offset := Vector3(0, 0, _distance)
	offset = offset.rotated(Vector3(1, 0, 0), _pitch)
	offset = offset.rotated(Vector3(0, 1, 0), _yaw)
	_cam.global_position = _pivot + offset
	_cam.look_at(_pivot, Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					_distance = clampf(_distance * 0.9, MIN_DIST, MAX_DIST)
					_update_camera()
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					_distance = clampf(_distance * 1.1, MIN_DIST, MAX_DIST)
					_update_camera()
			MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
				_dragging = event.pressed
			MOUSE_BUTTON_LEFT:
				if event.pressed:
					_pick_at(event.position)
	elif event is InputEventMouseMotion and _dragging:
		_yaw -= event.relative.x * 0.006
		_pitch = clampf(_pitch - event.relative.y * 0.006, MIN_PITCH, MAX_PITCH)
		_update_camera()
	elif event is InputEventKey and event.pressed and not event.echo and GameState.phase == GameState.Phase.GALAXY:
		match event.keycode:
			KEY_F:
				# Debug: toggle full-galaxy reveal vs new-game fog.
				_reveal_all = not _reveal_all
				if _reveal_all:
					Discovery.reveal_all()
				else:
					Discovery.init_for_new_game()
			KEY_V:
				# Debug: "visit" the selected planet's system (demonstrates fog reveal).
				if GameState.selected.get("kind", "") == "planet":
					var e: Dictionary = _bodies.get(GameState.selected.id, {})
					if e.has("planet_id"):
						Discovery.track_visit(e.planet_id)
			KEY_BRACKETLEFT:
				GameState.set_speed_idx(GameState.game_speed_idx - 1)
			KEY_BRACKETRIGHT:
				GameState.set_speed_idx(GameState.game_speed_idx + 1)
			KEY_SPACE:
				# Pause/resume (build_game.py SPACE pause, §8).
				if GameState.game_speed_idx == 0:
					GameState.set_speed_idx(_space_resume_idx)
				else:
					_space_resume_idx = GameState.game_speed_idx
					GameState.set_speed_idx(0)
			KEY_N:
				_with_selected_planet(func(pid): Player.build_station(pid))
			KEY_G:
				_with_selected_planet(func(pid): Player.build_upgrade(pid, "iron_foundry"))
			KEY_B:
				_with_selected_planet(_build_and_route_train)
			KEY_T:
				GameState.popup_requested.emit("train_builder")
			KEY_R:
				GameState.popup_requested.emit("routes")
			KEY_U:
				GameState.popup_requested.emit("stations")
			KEY_O:
				GameState.popup_requested.emit("options")
			KEY_C:
				GameState.popup_requested.emit("finances")
			KEY_P:
				GameState.popup_requested.emit("planet_detail")


## Run `fn(planet_id)` if a planet is currently selected.
func _with_selected_planet(fn: Callable) -> void:
	if GameState.selected.get("kind", "") != "planet":
		return
	var e: Dictionary = _bodies.get(GameState.selected.id, {})
	if e.has("planet_id"):
		fn.call(e.planet_id)


## Build a basic train at `pid` and route it to a sensible second stop so it
## immediately does something (B hotkey).
func _build_and_route_train(pid: int) -> void:
	var t := Player.build_train(pid, "engine_constellation", ["car_passenger"])
	if t.is_empty():
		return
	var dest := Galaxy.origen_id if pid != Galaxy.origen_id else -1
	if dest < 0:
		for opid in Galaxy.stars[Galaxy.home_star_id].planetIds:
			if opid != pid and Galaxy.planets[opid].get("demandRate", {}).has("passengers"):
				dest = opid
				break
	if dest >= 0:
		Player.assign_route(t.id, [pid, dest])


func _process(delta: float) -> void:
	# Slowly orbit the camera over the title/intro backdrop.
	if GameState.phase != GameState.Phase.GALAXY:
		_yaw += 0.05 * delta
		_update_camera()
	_handle_wasd_pan(delta)
	_sync_planet_positions()
	_render_trains()
	_update_selection_ring_pos()
	_push_selection_screen_pos()


# ── Trains (Phase 2 slice 3) ──────────────────────────────────────────────
var _trains_root: Node3D
var _train_nodes: Dictionary = {}  # train id -> Node3D
const TRAIN_GLB := "res://assets/models/train_engine.glb"  # Phase-5 Blender assets
const CAR_GLB := "res://assets/models/car_passenger.glb"
var _train_scene: PackedScene = null
var _car_scene: PackedScene = null
const CONSIST_SCALE := 0.4
const CONSIST_SPACING := 2.8  # local units between units (pre-scale)

func _setup_trains() -> void:
	_trains_root = Node3D.new()
	add_child(_trains_root)
	if ResourceLoader.exists(TRAIN_GLB):
		_train_scene = load(TRAIN_GLB)
	if ResourceLoader.exists(CAR_GLB):
		_car_scene = load(CAR_GLB)
	if Transit.trains.is_empty():
		_spawn_demo_train()

## A demo player train so the galaxy has visible traffic: Orijen ⇄ a nearby
## passenger-demanding home world. (Real player-built trains arrive with the
## Train Builder UI in Phase 4.)
func _spawn_demo_train() -> void:
	var home: Dictionary = Galaxy.stars[Galaxy.home_star_id]
	var dest := -1
	for pid in home.planetIds:
		if pid == Galaxy.origen_id:
			continue
		if Galaxy.planets[pid].get("demandRate", {}).has("passengers"):
			dest = pid
			break
	if dest < 0:
		return
	var t := Transit.build_train(Galaxy.origen_id, "engine_galaxy", ["car_passenger", "car_passenger"], true)
	Transit.assign_route(t, [Galaxy.origen_id, dest])

func _render_trains() -> void:
	for t in Transit.trains:
		var node: Node3D = _train_nodes.get(t.id)
		if node == null:
			node = _make_consist(t)
			_trains_root.add_child(node)
			_train_nodes[t.id] = node
		var pos := _w2g(t.x, t.y)
		pos.y = 0.4  # float above the orbital plane so it reads over planets
		# Orient the consist so its +X (engine front) points along travel.
		var prev: Vector3 = node.get_meta("prev", Vector3.INF)
		if prev != Vector3.INF:
			var d: Vector3 = pos - prev
			d.y = 0.0
			if d.length() > 0.0001:
				node.set_meta("ry", atan2(-d.z, d.x))
		node.set_meta("prev", pos)
		node.position = pos
		node.rotation.y = node.get_meta("ry", 0.0)


## A train consist: engine + one car per cargo car, lined up along -X, oriented
## each frame to face travel. Uses Blender .glb models when present, else boxes.
func _make_consist(t: Dictionary) -> Node3D:
	var consist := Node3D.new()
	consist.scale = Vector3(CONSIST_SCALE, CONSIST_SCALE, CONSIST_SCALE)
	consist.set_meta("ry", 0.0)
	consist.set_meta("prev", Vector3.INF)
	consist.add_child(_unit(_train_scene, t.isPlayer, true))  # engine at x=0
	for ci in t.cars.size():
		var car := _unit(_car_scene, t.isPlayer, false)
		car.position = Vector3(-(ci + 1) * CONSIST_SPACING, 0, 0)
		consist.add_child(car)
	return consist


func _unit(scene: PackedScene, is_player: bool, is_engine: bool) -> Node3D:
	if scene != null:
		return scene.instantiate()
	# Fallback box (pre-Blender).
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.8 if is_engine else 1.5, 0.9, 0.9)
	mi.mesh = box
	var mat := StandardMaterial3D.new()
	var col := Color(0.3, 1.0, 1.0) if is_player else Color(1.0, 0.6, 0.2)
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 1.4
	mi.material_override = mat
	return mi


## Planets orbit (Galaxy advances them in _physics_process); mirror their world
## positions onto the visual mesh, collider, and relic ring each frame.
func _sync_planet_positions() -> void:
	for p in Galaxy.planets:
		var e: Dictionary = _bodies.get("planet_%d" % p.id, {})
		if e.is_empty():
			continue
		var pos := _w2g(p.x, p.y)
		e.node.position = pos
		e.collider.position = pos
		e.world_pos = pos
		if e.get("relic_ring") != null:
			e.relic_ring.position = pos
		# A built (non-relic) station gets a blue track ring (child → follows planet).
		if p.hasStation and not p.isAlienRelic and not _station_nodes.has(p.id):
			var sr := _make_station_ring(e.radius)
			e.node.add_child(sr)
			_station_nodes[p.id] = sr


func _update_selection_ring_pos() -> void:
	if not _selection_ring.visible:
		return
	var id: String = GameState.selected.get("id", "")
	if _bodies.has(id):
		_selection_ring.position = _bodies[id].world_pos


func _handle_wasd_pan(delta: float) -> void:
	var move := Vector2.ZERO
	if Input.is_key_pressed(KEY_W): move.y -= 1.0
	if Input.is_key_pressed(KEY_S): move.y += 1.0
	if Input.is_key_pressed(KEY_A): move.x -= 1.0
	if Input.is_key_pressed(KEY_D): move.x += 1.0
	if move == Vector2.ZERO:
		return
	# Pan on the XZ plane, relative to the camera's yaw. Speed scales with zoom.
	var speed := _distance * 0.6 * delta
	var fwd := Vector3(0, 0, -1).rotated(Vector3(0, 1, 0), _yaw)  # screen-up on plane
	var right := Vector3(1, 0, 0).rotated(Vector3(0, 1, 0), _yaw)
	_pivot += (fwd * move.y * -1.0 + right * move.x) * speed
	_update_camera()


# ---------------------------------------------------------------------------
# Picking (screen -> world) and selection feedback (world -> screen)
# ---------------------------------------------------------------------------

func _pick_at(screen_pos: Vector2) -> void:
	var from := _cam.project_ray_origin(screen_pos)
	var dir := _cam.project_ray_normal(screen_pos)
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * 4000.0)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		GameState.clear_selection()
		return
	var collider: Object = hit.collider
	GameState.select(collider.get_meta("kind"), collider.get_meta("id"), collider.get_meta("display_name"))


func _push_selection_screen_pos() -> void:
	if GameState.selected.is_empty():
		return
	var id: String = GameState.selected.get("id", "")
	if not _bodies.has(id):
		GameState.selected_screen_pos = Vector2.INF
		return
	var wp: Vector3 = _bodies[id].world_pos
	if _cam.is_position_behind(wp):
		GameState.selected_screen_pos = Vector2.INF
	else:
		GameState.selected_screen_pos = _cam.unproject_position(wp)


func _on_selection_changed(sel: Dictionary) -> void:
	if sel.is_empty() or not _bodies.has(sel.get("id", "")):
		_selection_ring.visible = false
		return
	var b: Dictionary = _bodies[sel.id]
	_selection_ring.position = b.world_pos
	# Scale the ring (base outer radius 2.0) to ~1.5× the selected body radius.
	var sc: float = max(b.get("radius", 1.0) * 1.5 / 2.0, 0.12)
	_selection_ring.scale = Vector3(sc, sc, sc)
	_selection_ring.visible = true
