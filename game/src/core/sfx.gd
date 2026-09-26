extends Node
## Audio (autoload "Sfx"): named sound events mapped to procedurally generated clips
## (assets/audio, made with audio_gen.py), a small player pool with per-event rate limiting and
## distance attenuation, plus the looping music and wind ambience.

## event -> [clip base name, volume dB, pitch]
const EVENTS := {
	&"ui_select": ["ui_click", -8.0, 1.0], &"ui_confirm": ["ui_confirm", -8.0, 1.0],
	&"ui_error": ["ui_cancel", -6.0, 1.0], &"ui_hover": ["ui_hover", -18.0, 1.0],
	&"build_place": ["impact", -8.0, 0.8], &"build_done": ["powerup", -10.0, 0.85],
	&"chop": ["hit", -16.0, 1.25], &"mine": ["impact", -17.0, 1.6], &"melee": ["swing", -12.0, 1.0],
	&"hit": ["hit", -13.0, 0.9], &"arrow": ["shoot", -17.0, 1.35], &"cannon": ["explosion", -12.0, 1.25],
	&"blaster": ["laser", -16.0, 1.1], &"hurt": ["hurt", -14.0, 1.0], &"death": ["death", -12.0, 1.0],
	&"loot": ["coin", -10.0, 1.0], &"rare_loot": ["powerup", -5.0, 1.2], &"levelup": ["powerup", -8.0, 1.35],
	&"discover": ["blip", -9.0, 0.85], &"alert": ["blip", -7.0, 0.6], &"coin": ["coin", -10.0, 1.1],
}
const MIN_GAP_MS := 70
const POOL := 14

var enabled := true
var sfx_db := 0.0
var music_db := -8.0
var _streams: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
var _next := 0
var _last: Dictionary = {}
var music: AudioStreamPlayer
var ambience: AudioStreamPlayer


func _ready() -> void:
	# The Dummy driver (headless / automated runs) never mixes, so playbacks would never be
	# released: stay silent there.
	if AudioServer.get_driver_name() == "Dummy":
		enabled = false
	for ev: StringName in EVENTS:
		var base := str(EVENTS[ev][0])
		if _streams.has(base):
			continue
		var list: Array = []
		for i in [1, 2]:
			var p := "res://assets/audio/%s_%02d.wav" % [base, i]
			if ResourceLoader.exists(p):
				list.append(load(p))
		_streams[base] = list
	for i in POOL:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)
	music = AudioStreamPlayer.new()
	add_child(music)
	ambience = AudioStreamPlayer.new()
	add_child(ambience)


## Plays an event. attenuation 0..1 (1 = full volume), e.g. from distance to the camera.
func play(ev: StringName, attenuation: float = 1.0) -> void:
	if not enabled or attenuation <= 0.02 or not EVENTS.has(ev):
		return
	var now := Time.get_ticks_msec()
	if now - int(_last.get(ev, -1000)) < MIN_GAP_MS:
		return
	_last[ev] = now
	var e: Array = EVENTS[ev]
	var list: Array = _streams.get(str(e[0]), [])
	if list.is_empty():
		return
	var p := _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stream = list[randi() % list.size()]
	p.volume_db = float(e[1]) + sfx_db + linear_to_db(clampf(attenuation, 0.02, 1.0))
	p.pitch_scale = float(e[2]) * randf_range(0.94, 1.06)
	p.play()


func start_music() -> void:
	if music.playing or not enabled:
		return
	var m: AudioStream = load("res://assets/audio/bgm_frontier.ogg")
	if m is AudioStreamOggVorbis:
		(m as AudioStreamOggVorbis).loop = true
	music.stream = m
	music.volume_db = music_db
	music.play()
	var a: AudioStream = load("res://assets/audio/amb_wind.ogg")
	if a is AudioStreamOggVorbis:
		(a as AudioStreamOggVorbis).loop = true
	ambience.stream = a
	ambience.volume_db = music_db - 10.0
	ambience.play()


## Streams still playing at exit would be reported as leaks: stop and release everything.
func _exit_tree() -> void:
	for p: AudioStreamPlayer in _pool + [music, ambience]:
		p.stop()
		p.stream = null
	_streams.clear()


func stop_music() -> void:
	music.stop()
	ambience.stop()


func set_music_volume(db: float) -> void:
	music_db = db
	music.volume_db = db
	ambience.volume_db = db - 10.0
