extends Node
## Audio (autoload "Sfx"): compressed effect pool, context-aware looping score and wind ambience.

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
const TRACKS := ["title", "frontier_day", "workshop", "night", "battle"]
const TRACK_NAMES := {
	"title": "Frontier Overture", "frontier_day": "A New Day", "workshop": "Gears & Gatherings",
	"night": "Lanterns at Rest", "battle": "Ironbound Resolve",
}
const MIN_GAP_MS := 70
const POOL := 14
const CROSSFADE_SECONDS := 2.0

var enabled := true
var _streams: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
var _next := 0
var _last: Dictionary = {}
var music: AudioStreamPlayer
var _music_next: AudioStreamPlayer
var ambience: AudioStreamPlayer
var _music_tween: Tween
var _started := false
var _track_setting := "auto"
var _current_track := ""
var _last_calmed_track := ""
var _calm_switch_timer := 0.0
var _context_timer := 0.0
var _last_battle_time := -100.0
var _shuffle_timer := 0.0
var _world_ref: World
var _world_fx_callable := Callable()


func _ready() -> void:
	if AudioServer.get_driver_name() == "Dummy":
		enabled = false
	for ev: StringName in EVENTS:
		var base := str(EVENTS[ev][0])
		if _streams.has(base):
			continue
		var list: Array[AudioStream] = []
		for i in [1, 2]:
			var p := "res://assets/audio/%s_%02d.ogg" % [base, i]
			if ResourceLoader.exists(p):
				list.append(load(p) as AudioStream)
		_streams[base] = list
	for i in POOL:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool.append(p)
	music = _make_player("Music")
	_music_next = _make_player("Music")
	ambience = _make_player("Ambience")
	Settings.changed.connect(_on_setting_changed)
	_apply_volumes()
	_track_setting = str(Settings.get_value("audio/music_track"))


func _make_player(bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	add_child(p)
	return p


func _process(delta: float) -> void:
	if not _started:
		return
	_context_timer -= delta
	_calm_switch_timer = maxf(0.0, _calm_switch_timer - delta)
	_shuffle_timer -= delta
	if _context_timer <= 0.0:
		_context_timer = 1.0
		_bind_scene_world()
		_update_music_choice()
	if _track_setting == "shuffle" and _shuffle_timer <= 0.0 and _current_track != "":
		_shuffle_timer = 150.0
		_request_track(_random_track(_current_track))


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
	p.volume_db = float(e[1]) + linear_to_db(clampf(attenuation, 0.02, 1.0))
	p.pitch_scale = float(e[2]) * randf_range(0.94, 1.06)
	p.play()


func start_music() -> void:
	if _started:
		return
	_started = true
	_shuffle_timer = 150.0
	_bind_scene_world()
	_update_music_choice(true)
	if not enabled:
		return
	var stream: AudioStream = load("res://assets/audio/amb_wind.ogg")
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	ambience.stream = stream
	ambience.volume_db = 0.0
	ambience.play()

func _bind_scene_world() -> void:
	var scene := get_tree().current_scene
	var next_world: World = (scene as Game).world if scene is Game else null
	if next_world == _world_ref:
		return
	if _world_ref != null and _world_fx_callable.is_valid() and _world_ref.fx.is_connected(_world_fx_callable):
		_world_ref.fx.disconnect(_world_fx_callable)
	_world_ref = next_world
	_world_fx_callable = Callable()
	if _world_ref != null:
		_world_fx_callable = _on_world_fx
		_world_ref.fx.connect(_world_fx_callable)


func _on_world_fx(kind: StringName, pos: Vector3, _color: Color) -> void:
	if _world_ref == null or not kind in [&"hit_spark", &"death_poof", &"muzzle_flash"]:
		return
	for unit: Unit in _world_ref.unit_list:
		if unit.is_player() and Vector2(unit.pos.x - pos.x, unit.pos.y - pos.z).length_squared() <= 24.0 * 24.0:
			_last_battle_time = Time.get_ticks_msec() / 1000.0
			return


func _update_music_choice(force: bool = false) -> void:
	var desired := ""
	match _track_setting:
		"off":
			desired = ""
			if music.playing or _music_next.playing:
				_fade_to_silence()
			else:
				_current_track = ""
			return
		"shuffle":
			if _current_track == "":
				desired = _random_track("")
			else:
				return
		"auto":
			var scene := get_tree().current_scene
			if scene != null and scene is Game:
				var w: World = (scene as Game).world
				var now := Time.get_ticks_msec() / 1000.0
				if now - _last_battle_time < 15.0:
					desired = "battle"
				elif w != null and w.is_night():
					desired = "night"
				else:
					if _current_track in ["frontier_day", "workshop"] and _calm_switch_timer > 0.0 and not force:
						desired = _current_track
					else:
						desired = "frontier_day" if _last_calmed_track != "frontier_day" else "workshop"
						_last_calmed_track = desired
						_calm_switch_timer = 120.0
			else:
				desired = "title"
		_:
			desired = _track_setting if _track_setting in TRACKS else "title"
	if force or desired != _current_track:
		_request_track(desired)


func _request_track(track_id: String) -> void:
	if track_id == "" or track_id == _current_track:
		return
	if not enabled:
		_current_track = track_id
		return
	var stream: AudioStream = load("res://assets/audio/bgm_%s.ogg" % track_id)
	if stream == null:
		return
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	if _music_tween != null and _music_tween.is_running():
		_music_tween.kill()
	var incoming := _music_next if music.playing else music
	var outgoing := music if incoming == _music_next else _music_next
	incoming.stop()
	incoming.stream = stream
	incoming.volume_db = -60.0 if outgoing.playing else 0.0
	incoming.play()
	_current_track = track_id
	if outgoing.playing:
		_music_tween = create_tween().set_parallel(true)
		_music_tween.tween_property(incoming, "volume_db", 0.0, CROSSFADE_SECONDS)
		_music_tween.tween_property(outgoing, "volume_db", -60.0, CROSSFADE_SECONDS)
		_music_tween.chain().tween_callback(func() -> void:
			outgoing.stop()
			outgoing.stream = null)
	else:
		incoming.volume_db = 0.0


func _fade_to_silence() -> void:
	if _music_tween != null and _music_tween.is_running():
		_music_tween.kill()
	_music_tween = create_tween().set_parallel(true)
	for p: AudioStreamPlayer in [music, _music_next]:
		if p.playing:
			_music_tween.tween_property(p, "volume_db", -60.0, CROSSFADE_SECONDS)
	_music_tween.chain().tween_callback(func() -> void:
		for p: AudioStreamPlayer in [music, _music_next]:
			p.stop()
			p.stream = null)
	_current_track = ""


func _random_track(exclude: String) -> String:
	var options: Array[String] = []
	for track: String in TRACKS:
		if track != exclude:
			options.append(track)
	return options[randi() % options.size()] if not options.is_empty() else "title"


func track_name(track_id: String) -> String:
	if track_id in ["auto", "shuffle", "off"]:
		return Loc.t(track_id.capitalize())
	return Loc.t(str(TRACK_NAMES.get(track_id, "Music off")))


func current_track_name() -> String:
	return track_name(_current_track)


func current_track_id() -> String:
	return _current_track


func _on_setting_changed(key: String, value: Variant) -> void:
	if key.begins_with("audio/"):
		_apply_volumes()
	if key == "audio/music_track":
		_track_setting = str(value)
		_shuffle_timer = 150.0
		if _started:
			_update_music_choice(true)


func _apply_volumes() -> void:
	var master: float = clampf(float(Settings.get_value("audio/master")), 0.0, 1.0)
	var music_volume: float = clampf(float(Settings.get_value("audio/music")), 0.0, 1.0)
	var sfx_volume: float = clampf(float(Settings.get_value("audio/sfx")), 0.0, 1.0)
	var ambience_volume: float = clampf(float(Settings.get_value("audio/ambience")), 0.0, 1.0)
	_set_bus_volume("Master", master)
	_set_bus_volume("Music", music_volume)
	_set_bus_volume("SFX", sfx_volume)
	_set_bus_volume("Ambience", ambience_volume)


func _set_bus_volume(bus: String, value: float) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx >= 0:
		AudioServer.set_bus_mute(idx, value <= 0.0)
		AudioServer.set_bus_volume_db(idx, linear_to_db(value) if value > 0.0 else 0.0)


func stop_music() -> void:
	if _music_tween != null and _music_tween.is_running():
		_music_tween.kill()
	for p: AudioStreamPlayer in [music, _music_next, ambience]:
		p.stop()
		p.stream = null
	_current_track = ""
	_started = false


func _exit_tree() -> void:
	if _world_ref != null and _world_fx_callable.is_valid() and _world_ref.fx.is_connected(_world_fx_callable):
		_world_ref.fx.disconnect(_world_fx_callable)
	if _music_tween != null and _music_tween.is_running():
		_music_tween.kill()
	for p: AudioStreamPlayer in _pool + [music, _music_next, ambience]:
		if is_instance_valid(p):
			p.stop()
			p.stream = null
	_streams.clear()
