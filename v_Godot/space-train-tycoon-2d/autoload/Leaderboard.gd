extends Node
## Leaderboard — the REAL public high-score backend (build_game.py:2577-2921).
##
## Cloudflare Worker + D1. Faithful port of the JS client:
##   • GET  /top?metric=<col>&limit=100   → fetch the top-100 for a metric
##   • POST /submit  (HMAC-SHA256 signed)  → submit this corp's 7 metrics
## Identity = a persisted per-corp UUID (`corp_id`). 30 s submit throttle.
## `best_ranks` tracks the best (lowest) rank ever hit per metric so the
## rainbow chat announcement only fires on a genuine improvement. Every network
## failure is swallowed — the leaderboard can never affect the game or a save.

const LB_URL := "https://stt-leaderboard.spacetraintycoon.workers.dev"
# Embedded HMAC key — NOT secret (matches the JS); only blocks casual spoofing.
const LB_SIG_KEY := "4c984c6229e81b59fef9a6e53ff0db0d25a66be94387b3b1137e8506a55b3c0d"
const SUBMIT_THROTTLE_MS := 30000
const STATION_ASSET_VALUE := 50000   # build_game.py:2057
const UPGRADE_ASSET_VALUE := 10000   # build_game.py:2058

# The 7 ranked metrics in display order: {key (submit JSON), col (server id), label, short}.
const METRICS := [
	{"key": "corpValue", "col": "corp_value", "label": "CORP VALUE", "short": "VALUE"},
	{"key": "numTrains", "col": "num_trains", "label": "TRAINS", "short": "TRAINS"},
	{"key": "numRoutes", "col": "num_routes", "label": "ROUTES", "short": "ROUTES"},
	{"key": "numStations", "col": "num_stations", "label": "STATIONS", "short": "STAT."},
	{"key": "latestSd", "col": "latest_sd", "label": "STARDATE", "short": "S.D."},
	{"key": "discoveredPlanets", "col": "discovered_planets", "label": "PLANETS", "short": "PLNTS"},
	{"key": "discoveredStars", "col": "discovered_stars", "label": "STARS", "short": "STARS"},
]

var corp_id := ""              # stable per-corp UUID = leaderboard identity
var rows: Array = []           # fetched rows (<=100) for the current sort metric
var metric := "corp_value"     # current sort column id
var page := 0                  # 0-based; 10 rows/page, up to page 9 (ranks 91-100)
var status := ""               # "" | loading | ok | empty | error
var best_ranks: Dictionary = {}
var _last_submit_ms := 0

signal changed                          # state changed → views redraw
signal rank_improved(corp_name: String) # newly qualified / improved a rank

var _http_top: HTTPRequest
var _http_submit: HTTPRequest

const _CORP_ID_PATH := "user://stt_corp_id.txt"

func _ready() -> void:
	_http_top = HTTPRequest.new()
	_http_top.timeout = 12.0
	add_child(_http_top)
	_http_top.request_completed.connect(_on_top_completed)
	_http_submit = HTTPRequest.new()
	_http_submit.timeout = 12.0
	add_child(_http_submit)
	_http_submit.request_completed.connect(_on_submit_completed)
	_load_corp_id()

# ── Identity ────────────────────────────────────────────────────────────────
func _load_corp_id() -> void:
	if FileAccess.file_exists(_CORP_ID_PATH):
		var f := FileAccess.open(_CORP_ID_PATH, FileAccess.READ)
		if f:
			corp_id = f.get_as_text().strip_edges()
			f.close()

func ensure_corp_id() -> String:
	if corp_id != "":
		return corp_id
	var b := Crypto.new().generate_random_bytes(16)
	b[6] = (b[6] & 0x0f) | 0x40   # version 4
	b[8] = (b[8] & 0x3f) | 0x80   # variant
	var hx := b.hex_encode()
	corp_id = "%s-%s-%s-%s-%s" % [hx.substr(0, 8), hx.substr(8, 4), hx.substr(12, 4), hx.substr(16, 4), hx.substr(20, 12)]
	var f := FileAccess.open(_CORP_ID_PATH, FileAccess.WRITE)
	if f:
		f.store_string(corp_id)
		f.close()
	return corp_id

# ── Stats (build_game.py _lbStats / _corpAssets) ────────────────────────────
func _car_cost(c: String) -> int:
	if c == "caboose":
		return 0
	if Tuning.ENGINE_COSTS.has(c):
		return int(Tuning.ENGINE_COSTS[c])
	return 1000

func _corp_value() -> int:
	var train_val := 0
	for t in Transit.trains:
		if not bool(t.isPlayer):
			continue
		train_val += int(Tuning.ENGINE_COSTS.get(String(t.engine), 0))
		for c in t.get("cars", []):
			train_val += _car_cost(String(c))
	var station_val := 0
	var upgrade_val := 0
	for p in Galaxy.planets:
		var known: bool = bool(p.get("isStarter", false)) or Discovery.discovered_planet_ids.has(int(p.id))
		if bool(p.get("hasStation", false)) and (bool(p.get("playerBuiltStation", false)) or bool(p.get("isStarter", false)) or known):
			station_val += STATION_ASSET_VALUE
			if bool(p.get("hasLargeStation", false)):
				station_val += STATION_ASSET_VALUE
		for uid in p.get("upgrades", []):
			var pb: bool = (p.get("playerBuiltUpgrades", []) as Array).has(uid)
			if pb or Discovery.discovered_planet_ids.has(int(p.id)):
				upgrade_val += UPGRADE_ASSET_VALUE
	return GameState.credits + train_val + station_val + upgrade_val

func _stats() -> Dictionary:
	var pt := 0
	var nroutes := 0
	for t in Transit.trains:
		if not bool(t.isPlayer):
			continue
		pt += 1
		if t.route != null and (t.route.get("stops", []) as Array).size() >= 2:
			nroutes += 1
	var nstations := 0
	for p in Galaxy.planets:
		if bool(p.get("isStarter", false)) or bool(p.get("playerBuiltStation", false)):
			nstations += 1
	return {
		"corpId": ensure_corp_id(),
		"corpName": (String(GameState.corp_name) if String(GameState.corp_name) != "" else "Unnamed Corp"),
		"corpValue": _corp_value(),
		"numTrains": pt,
		"numRoutes": nroutes,
		"numStations": nstations,
		"latestSd": roundf(GameState.stardate * 100.0) / 100.0,
		"discoveredPlanets": Discovery.discovered_planet_ids.size(),
		"discoveredStars": Discovery.revealed_star_ids.size(),
	}

# JSON-encode the body in the EXACT key order + JS number formatting so the HMAC
# signature matches what the backend recomputes from the received bytes.
func _esc(s: String) -> String:
	var out := s.replace("\\", "\\\\").replace("\"", "\\\"")
	out = out.replace("\n", "\\n").replace("\r", "\\r").replace("\t", "\\t")
	return out

func _js_num(v: float) -> String:
	if v == floorf(v):
		return str(int(v))
	var s := String.num(v, 2)
	while s.ends_with("0"):
		s = s.left(s.length() - 1)
	if s.ends_with("."):
		s = s.left(s.length() - 1)
	return s

func _body_json(s: Dictionary) -> String:
	return '{"corpId":"%s","corpName":"%s","corpValue":%d,"numTrains":%d,"numRoutes":%d,"numStations":%d,"latestSd":%s,"discoveredPlanets":%d,"discoveredStars":%d}' % [
		_esc(String(s.corpId)), _esc(String(s.corpName)), int(s.corpValue),
		int(s.numTrains), int(s.numRoutes), int(s.numStations),
		_js_num(float(s.latestSd)), int(s.discoveredPlanets), int(s.discoveredStars)]

func _sign(body: String) -> String:
	var hctx := HMACContext.new()
	if hctx.start(HashingContext.HASH_SHA256, LB_SIG_KEY.to_utf8_buffer()) != OK:
		return ""
	if hctx.update(body.to_utf8_buffer()) != OK:
		return ""
	return hctx.finish().hex_encode()

# ── Submit (fire-and-forget, HMAC-signed, throttled) ────────────────────────
func submit() -> void:
	if Galaxy.planets.is_empty():
		return
	var now := Time.get_ticks_msec()
	if now - _last_submit_ms < SUBMIT_THROTTLE_MS:
		return
	_last_submit_ms = now
	var s := _stats()
	var body := _body_json(s)
	var headers := PackedStringArray(["Content-Type: application/json"])
	var sig := _sign(body)
	if sig != "":
		headers.append("X-LB-Sig: " + sig)
	_http_submit.cancel_request()
	_http_submit.request(LB_URL + "/submit", headers, HTTPClient.METHOD_POST, body)

func _on_submit_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return
	var d = JSON.parse_string(body.get_string_from_utf8())
	if not (d is Dictionary) or not bool(d.get("ok", false)) or not (d.get("ranks") is Dictionary):
		return
	var improved := false
	var ranks: Dictionary = d["ranks"]
	for mk in ranks.keys():
		var rk = ranks[mk]
		if (rk is float or rk is int) and int(rk) <= 100 and (not best_ranks.has(mk) or int(rk) < int(best_ranks[mk])):
			best_ranks[mk] = int(rk)
			improved = true
	if improved:
		rank_improved.emit(_stats().corpName)

# ── Fetch top-100 for a metric ──────────────────────────────────────────────
func fetch_top(m: String) -> void:
	metric = m
	page = 0
	status = "loading"
	rows = []
	changed.emit()
	_http_top.cancel_request()
	var url := LB_URL + "/top?metric=" + m.uri_encode() + "&limit=100"
	if _http_top.request(url) != OK:
		status = "error"
		changed.emit()

func _on_top_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		status = "error"
		changed.emit()
		return
	var d = JSON.parse_string(body.get_string_from_utf8())
	if d is Dictionary and d.get("rows") is Array:
		rows = d["rows"]
		status = "ok" if rows.size() > 0 else "empty"
	else:
		status = "error"
	changed.emit()

# ── View helpers ────────────────────────────────────────────────────────────
func max_page() -> int:
	return maxi(0, mini(9, int(ceil(rows.size() / 10.0)) - 1))

func metric_label(col: String) -> String:
	for m in METRICS:
		if m.col == col:
			return m.label
	return ""

func fmt_cell(row: Dictionary, col: String) -> String:
	if col == "corp_value":
		return _fmt_cr(int(row.get(col, 0)))
	if col == "latest_sd":
		return "%.1f" % (roundf(float(row.get(col, 0.0)) * 10.0) / 10.0)
	# num_trains/routes/stations, discovered_planets/stars are integers — JSON
	# parses them as floats in Godot, so coerce back to int (no ".0" suffix).
	return str(int(round(float(row.get(col, 0)))))

func _fmt_cr(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if n < 0 else "") + out
