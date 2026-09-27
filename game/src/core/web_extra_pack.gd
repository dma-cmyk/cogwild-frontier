class_name WebExtraPack
extends Node
## Autoload "WebArt". The browser build ships two packs: the core one the page downloads before the
## engine starts, and this optional art pack (extra races, building back views, extra looks) that is
## fetched in the background while the title menu is already usable. Everything it contains has a
## working fallback (procedural low-poly figures, front views, look v1), so the game is playable the
## whole time; when the pack mounts, live views rebuild themselves.
##
## The file is kept in user:// (IndexedDB on the web) so a revisit mounts it without any request, and
## the service worker also caches the response so a first visit on a fresh profile is served locally.
## Native builds ship one pack and never enter any of this.

## Nodes in this group get `refresh_after_web_extra_art()` after a pack is mounted.
const REFRESH_GROUP := &"web_extra_art_refresh"
const PACK_PREFIX := "web-extra-"
const MANIFEST_FILE := "web-extra.json"

## 0.0 .. 1.0 of the optional pack; 1.0 once it is mounted (or when there is nothing to fetch).
signal progress_changed(ratio: float)
## The pack is mounted and the new art is loadable.
signal art_arrived

var _manifest_request: HTTPRequest
var _pack_request: HTTPRequest
var _manifest: Dictionary = {}
var _started := false
var _downloading := false
var _mounted := false
var _progress := 0.0


func _ready() -> void:
	set_process(false)
	if not OS.has_feature("web"):
		_progress = 1.0


## Called by the title screen. Idempotent: later scenes may call it again without restarting work.
func begin() -> void:
	if _started or not OS.has_feature("web"):
		return
	_started = true
	_manifest_request = _make_request(30.0, _on_manifest_completed)
	_pack_request = _make_request(300.0, _on_pack_completed)
	var url := _base_url()
	if url.is_empty():
		_finish_without_pack()
		return
	var err := _manifest_request.request(url + MANIFEST_FILE)
	if err != OK:
		_warn("could not request the pack manifest (%s)" % error_string(err))
		_finish_without_pack()


func progress() -> float:
	return _progress


func is_mounted() -> bool:
	return _mounted


func _make_request(timeout: float, handler: Callable) -> HTTPRequest:
	var request := HTTPRequest.new()
	request.timeout = timeout
	# The browser's fetch already undoes Content-Encoding (GitHub Pages gzips .pck); letting
	# HTTPRequest inflate again fails with RESULT_BODY_DECOMPRESS_FAILED.
	request.accept_gzip = false
	request.request_completed.connect(handler)
	add_child(request)
	return request


func _base_url() -> String:
	var value: Variant = JavaScriptBridge.eval("new URL('.', window.location.href).href", true)
	return str(value) if value is String else ""


func _on_manifest_completed(result: int, response_code: int, _headers: PackedStringArray,
		body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		_warn("pack manifest request failed (HTTP %d, result %d)" % [response_code, result])
		_finish_without_pack()
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not parsed is Dictionary:
		_warn("pack manifest is not an object")
		_finish_without_pack()
		return
	var manifest: Dictionary = parsed as Dictionary
	var version := str(manifest.get("version", ""))
	if not _is_hex_version(version) or str(manifest.get("file", "")) != _pack_name(version):
		_warn("pack manifest names an unexpected file")
		_finish_without_pack()
		return
	_manifest = manifest
	_drop_stale_packs(version)
	var cached := _cache_path(version)
	if FileAccess.file_exists(cached) and _mount(cached):
		return
	_download(version)


## The version is a content hash and becomes part of a user:// file name: accept hex only.
func _is_hex_version(version: String) -> bool:
	if version.length() != 16:
		return false
	for c: String in version:
		if not "0123456789abcdef".contains(c):
			return false
	return true


func _pack_name(version: String) -> String:
	return "%s%s.pck" % [PACK_PREFIX, version]


func _cache_path(version: String) -> String:
	return "user://" + _pack_name(version)


func _download(version: String) -> void:
	var url := _base_url()
	if url.is_empty():
		_finish_without_pack()
		return
	# The body is kept in memory and written with FileAccess: on the web, HTTPRequest's
	# download_file into user:// (IndexedDB) read back as an empty file when the request completed.
	_pack_request.download_file = ""
	var err := _pack_request.request(url + _pack_name(version))
	if err != OK:
		_warn("could not request the art pack (%s)" % error_string(err))
		_finish_without_pack()
		return
	_downloading = true
	set_process(true)


func _process(_delta: float) -> void:
	if not _downloading:
		set_process(false)
		return
	var total := _pack_request.get_body_size()
	if total <= 0:
		total = int(_manifest.get("bytes", 0))
	if total <= 0:
		return
	_set_progress(clampf(float(_pack_request.get_downloaded_bytes()) / float(total), 0.0, 0.99))


func _on_pack_completed(result: int, response_code: int, _headers: PackedStringArray,
		body: PackedByteArray) -> void:
	_downloading = false
	set_process(false)
	var version := str(_manifest.get("version", ""))
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		_warn("art pack request failed (HTTP %d, result %d)" % [response_code, result])
		_finish_without_pack()
		return
	if body.is_empty():
		_warn("the downloaded art pack is empty")
		_finish_without_pack()
		return
	var cached := _cache_path(version)
	_remove_file(cached)
	var file := FileAccess.open(cached, FileAccess.WRITE)
	if file == null:
		_warn("could not store the art pack (%s)" % error_string(FileAccess.get_open_error()))
		_finish_without_pack()
		return
	file.store_buffer(body)
	file.close()
	if not _mount(cached):
		_remove_file(cached)
		_finish_without_pack()


func _mount(path: String) -> bool:
	# Additive: the core pack always keeps its own copy of everything it already ships.
	if not ProjectSettings.load_resource_pack(path, false):
		_warn("could not mount the art pack")
		return false
	_mounted = true
	SpriteLibrary.clear_missing_cache()
	get_tree().call_group(REFRESH_GROUP, "refresh_after_web_extra_art")
	_set_progress(1.0)
	art_arrived.emit()
	return true


## Older versions stay behind in IndexedDB after a deploy and would waste the storage quota.
func _drop_stale_packs(keep_version: String) -> void:
	var dir := DirAccess.open("user://")
	if dir == null:
		return
	for file: String in dir.get_files():
		if file.begins_with(PACK_PREFIX) and file != _pack_name(keep_version):
			_remove_file("user://" + file)


func _finish_without_pack() -> void:
	_set_progress(1.0)


func _set_progress(ratio: float) -> void:
	if is_equal_approx(ratio, _progress):
		return
	_progress = ratio
	progress_changed.emit(ratio)


func _remove_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _warn(message: String) -> void:
	push_warning("Optional web art pack: " + message)
