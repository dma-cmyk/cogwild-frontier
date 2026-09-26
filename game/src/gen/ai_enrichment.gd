class_name AiEnrichment
extends Node
## Optional AI Enrichment Layer. The game never needs it: every name, bio and flavor text is
## generated locally first (NpcGen / ItemGen / NamedEnemyGen). When an OpenAI-compatible
## chat-completions endpoint is configured, this node rewrites a few text fields of newly met
## characters and notable items in the background. Only text is touched, so the simulation stays
## deterministic and saves stay valid with or without it.
##
## Configuration (never in code): environment variables
##   COGWILD_AI_ENDPOINT  e.g. https://api.openai.com/v1/chat/completions or a local LLM server
##   COGWILD_AI_KEY       bearer token (optional for local servers)
##   COGWILD_AI_MODEL     model name
## or the same keys (endpoint, key, model) in section [ai] of user://ai_enrichment.cfg.

signal enriched(kind: String, target: Variant)

const TIMEOUT := 20.0
const MAX_QUEUE := 24

var endpoint := ""
var api_key := ""
var model := ""
var _http: HTTPRequest
var _queue: Array = []  # [{kind, target, messages}]
var _busy: Dictionary = {}


func _ready() -> void:
	endpoint = OS.get_environment("COGWILD_AI_ENDPOINT")
	api_key = OS.get_environment("COGWILD_AI_KEY")
	model = OS.get_environment("COGWILD_AI_MODEL")
	var cfg := ConfigFile.new()
	if endpoint == "" and cfg.load("user://ai_enrichment.cfg") == OK:
		endpoint = str(cfg.get_value("ai", "endpoint", ""))
		api_key = str(cfg.get_value("ai", "key", ""))
		model = str(cfg.get_value("ai", "model", ""))
	_http = HTTPRequest.new()
	_http.timeout = TIMEOUT
	add_child(_http)
	_http.request_completed.connect(_on_completed)


func is_enabled() -> bool:
	return endpoint != ""


## Queues a character (NpcGen record) for a new bio quote and backstory.
func enrich_character(c: Dictionary) -> void:
	if not is_enabled() or bool(c.get("ai_enriched", false)):
		return
	var traits := []
	for t: String in c.get("traits", []):
		traits.append(str(DB.get_def("traits", t).get("name", t)))
	var facts := "Name: %s. Race: %s. Role: %s. Age: %d. Traits: %s. Quirk: %s." % [c.get("name", ""),
		c.get("race", ""), c.get("role", ""), int(c.get("age", 30)), ", ".join(PackedStringArray(traits)), c.get("quirk", "")]
	_push("character", c, facts + " Write JSON {\"bio\": one short first-person quote (max 14 words), \"backstory\": two sentences}.")


## Queues an item (ItemGen record) for new flavor text.
func enrich_item(it: Dictionary) -> void:
	if not is_enabled() or bool(it.get("ai_enriched", false)):
		return
	var facts := "Item: %s (%s %s, quality %s). Effects: %s." % [it.get("name", ""), it.get("material", ""), it.get("base", ""),
		it.get("quality", ""), JSON.stringify(it.get("mods", {}))]
	_push("item", it, facts + " Write JSON {\"flavor\": one evocative sentence, max 22 words}.")


func _push(kind: String, target: Dictionary, prompt: String) -> void:
	if _queue.size() >= MAX_QUEUE:
		return
	_queue.append({"kind": kind, "target": target, "messages": [
		{"role": "system", "content": "You write short, cozy fantasy-steampunk flavor text for a frontier colony game. Reply with a single JSON object only."},
		{"role": "user", "content": prompt}]})
	_next()


func _next() -> void:
	if not _busy.is_empty() or _queue.is_empty():
		return
	_busy = _queue.pop_front()
	var body := {"messages": _busy["messages"], "temperature": 0.8}
	if model != "":
		body["model"] = model
	var headers := PackedStringArray(["Content-Type: application/json"])
	if api_key != "":
		headers.append("Authorization: Bearer " + api_key)
	var err := _http.request(endpoint, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		_busy = {}


func _on_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var job := _busy
	_busy = {}
	if result == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300:
		_apply(job, body.get_string_from_utf8())
	_next()


func _apply(job: Dictionary, text: String) -> void:
	var resp: Variant = JSON.parse_string(text)
	if not (resp is Dictionary):
		return
	var content := ""
	var choices: Array = (resp as Dictionary).get("choices", [])
	if not choices.is_empty() and choices[0] is Dictionary:
		content = str(((choices[0] as Dictionary).get("message", {}) as Dictionary).get("content", ""))
	var start := content.find("{")
	var end := content.rfind("}")
	if start < 0 or end <= start:
		return
	var data: Variant = JSON.parse_string(content.substr(start, end - start + 1))
	if not (data is Dictionary):
		return
	var target: Dictionary = job["target"]
	var applied := false
	if job["kind"] == "character":
		for k: String in ["bio", "backstory"]:
			var v := str((data as Dictionary).get(k, "")).strip_edges()
			if v != "" and v.length() <= (160 if k == "bio" else 420):
				target[k] = v.trim_prefix("\"").trim_suffix("\"")
				applied = true
	else:
		var v := str((data as Dictionary).get("flavor", "")).strip_edges()
		if v != "" and v.length() <= 240:
			target["flavor"] = v
			applied = true
	if applied:
		target["ai_enriched"] = true
		enriched.emit(str(job["kind"]), target)


func pending() -> int:
	return _queue.size() + (0 if _busy.is_empty() else 1)
