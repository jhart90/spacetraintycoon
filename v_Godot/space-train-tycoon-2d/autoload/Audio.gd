extends Node
## Audio — SFX playback on game events (PLAN Phase 4/§5, §7). Two buses (SFX,
## Music) with volume from settings; replaces the JS _sfxVol/_sfxMuted system.
## Sound files (wav/mp3, imported natively by Godot 4) live in assets/audio/.
##
## Wires the existing autoload signals to sounds so the game has audible feedback
## (delivery ding, build chime, mission notification, discovery sting).

const DIR := "res://assets/audio/"
# The ORIGINAL embeds exactly these 5 sounds (build_game.py:41). 'click'/'purchase'
# are played in the JS but reference keys that don't exist in SOUNDS → silent
# no-ops. The 3D port's 'ding'/'blip' are NOT in the original → removed.
const SOUNDS := {
	"button": "button.mp3",
	"discovery": "discovery.mp3",
	"notification": "notification.mp3",
	"construction_complete": "construction_complete.mp3",
	"breakdown": "breakdown.mp3",
}

var sfx_vol: float = 0.7
var sfx_muted: bool = false
var music_vol: float = 0.35  # build_game.py:729 (_soundtrack.volume=0.35)

# Fixed-order soundtrack (build_game.py:719 _MUSIC_TRACKS) — advances on finish, wraps.
const MUSIC_DIR := "res://assets/music/"
const MUSIC_TRACKS := [
	"a.o.huge_01_last_train_home.mp3", "a.o.huge_02_interstellar_segment.mp3",
	"a.o.huge_03_star_depot_groove.mp3", "a.o.huge_04_neon_katsu_sandwich.mp3",
	"a.o.huge_05_lunar_save_point.mp3", "a.o.huge_06_nebulosa_amistosa.mp3",
	"a.o.huge_07_midnight_cargo_run.mp3",
]
var _music_player: AudioStreamPlayer
var _music_idx := 0

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
	# Soundtrack player (Music bus), starts the fixed-order playlist.
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = "Music"
	add_child(_music_player)
	_music_player.finished.connect(_next_track)
	_play_track(0)
	_apply_volume()
	# Event wiring — faithful to the original's playSound contexts:
	#  • delivery posts a chat message → 'notification' (build_game.py:2570; NOT 'ding')
	#  • star/planet discovered → 'discovery' (15933/15986)
	#  • mission intro/complete post chat messages → 'notification'
	#  • upgrade/station construction completes → 'construction_complete' (33042+)
	#  • opening a player popup / button → 'button' (36108/22135)
	# (No 'blip' on action_failed — the original has no such sound.)
	GameState.player_delivered.connect(func(_rev): play("notification", 0.05))
	Player.action_done.connect(func(_m): play("construction_complete"))
	Missions.mission_completed.connect(func(_id, _r): play("notification"))
	Missions.mission_introduced.connect(func(_id): play("notification"))
	Discovery.star_revealed.connect(func(_s): play("discovery"))
	GameState.popup_requested.connect(func(_n): play("button"))


func _process(delta: float) -> void:
	_t += delta

func _play_track(i: int) -> void:
	_music_idx = ((i % MUSIC_TRACKS.size()) + MUSIC_TRACKS.size()) % MUSIC_TRACKS.size()
	var path: String = MUSIC_DIR + MUSIC_TRACKS[_music_idx]
	if ResourceLoader.exists(path):
		_music_player.stream = load(path)
		_music_player.play()

func _next_track() -> void:
	_play_track(_music_idx + 1)


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
