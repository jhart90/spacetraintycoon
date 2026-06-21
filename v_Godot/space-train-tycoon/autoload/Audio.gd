extends Node
## Audio — SFX playback on game events (PLAN Phase 4/§5, §7). Two buses (SFX,
## Music) with volume from settings; replaces the JS _sfxVol/_sfxMuted system.
## Sound files (wav/mp3, imported natively by Godot 4) live in assets/audio/.
##
## Wires the existing autoload signals to sounds so the game has audible feedback
## (delivery ding, build chime, mission notification, discovery sting).

const DIR := "res://assets/audio/"
const SOUNDS := {
	"button": "button.mp3", "blip": "blip.mp3", "ding": "ding.wav",
	"discovery": "discovery.mp3", "notification": "notification.mp3",
	"construction_complete": "construction_complete.mp3", "breakdown": "breakdown.mp3",
}

var sfx_vol: float = 0.7
var sfx_muted: bool = false
var music_vol: float = 0.5

var _players: Dictionary = {}
var _last_play: Dictionary = {}  # name -> seconds (throttle rapid repeats)
var _t: float = 0.0


func _ready() -> void:
	_ensure_bus("SFX")
	_ensure_bus("Music")
	for k in SOUNDS:
		var path: String = DIR + SOUNDS[k]
		if ResourceLoader.exists(path):
			var p := AudioStreamPlayer.new()
			p.stream = load(path)
			p.bus = "SFX"
			add_child(p)
			_players[k] = p
	_apply_volume()
	# Event wiring (Audio is the last autoload, so all others are ready).
	GameState.player_delivered.connect(func(_rev): play("ding", 0.12))
	Player.action_done.connect(func(_m): play("construction_complete"))
	Player.action_failed.connect(func(_m): play("blip"))
	Missions.mission_completed.connect(func(_id, _r): play("notification"))
	Missions.mission_introduced.connect(func(_id): play("notification"))
	Discovery.star_revealed.connect(func(_s): play("discovery"))
	GameState.popup_requested.connect(func(_n): play("button"))


func _process(delta: float) -> void:
	_t += delta


func _ensure_bus(name: String) -> void:
	if AudioServer.get_bus_index(name) < 0:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, name)


func play(snd: String, throttle: float = 0.0) -> void:
	if sfx_muted:
		return
	var p: AudioStreamPlayer = _players.get(snd)
	if p == null:
		return
	if throttle > 0.0 and _t - float(_last_play.get(snd, -999.0)) < throttle:
		return
	_last_play[snd] = _t
	p.play()


func set_sfx_volume(v: float) -> void:
	sfx_vol = clampf(v, 0.0, 1.0)
	_apply_volume()


func set_sfx_muted(m: bool) -> void:
	sfx_muted = m
	_apply_volume()


func _apply_volume() -> void:
	var idx := AudioServer.get_bus_index("SFX")
	if idx >= 0:
		AudioServer.set_bus_mute(idx, sfx_muted)
		AudioServer.set_bus_volume_db(idx, linear_to_db(clampf(sfx_vol, 0.0001, 1.0)))
	var midx := AudioServer.get_bus_index("Music")
	if midx >= 0:
		AudioServer.set_bus_volume_db(midx, linear_to_db(clampf(music_vol, 0.0001, 1.0)))
