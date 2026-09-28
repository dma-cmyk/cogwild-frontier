class_name Quests
extends RefCounted
## Quest board shared by every community (race villages and the mixed-race town).
##
## A community offers a small board of quests that is rolled deterministically from the world seed,
## the giver's id and the day, so the same save always shows the same offers. Accepting copies the
## quest into `taken` where it lives until it is turned in, abandoned or missed; the offered rows
## themselves are throwaway and are re-rolled when the day changes.
##
## Kinds:
##   deliver  bring `amount` of `resource` to the giver (a colony unit must stand there)
##   bounty   clear the named bandit camp / machine outpost (`cleared` on its site), report back
##   scout    find the named undiscovered site; accepting tells you the rough direction

const KINDS := ["deliver", "bounty", "scout"]
const STATES := ["offered", "active", "done", "failed", "turned_in"]
const DELIVER_RESOURCES := ["wood", "stone", "ore", "metal", "food"]
const MAX_ACTIVE := 6
## One i18n key per kind (a table, not a concatenated key, so the catalogs stay greppable).
const LINE_KEY := {"deliver": "quest.line.deliver", "bounty": "quest.line.bounty",
	"scout": "quest.line.scout"}
const BOUNTY_RANGE := 220.0       ## how far from a giver a bounty/scout target may sit
const DIRECTIONS := ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]

var w: World
var taken: Dictionary = {}        ## qid -> quest Dictionary (active / done / failed / turned_in)
var _board: Dictionary = {}       ## giver sid -> Array[Dictionary] of offered quests
var _board_day: Dictionary = {}   ## giver sid -> day the board was rolled for
var _next_qid := 1


func _init(world: World) -> void:
	w = world


# --- helpers -------------------------------------------------------------------------------

static func direction_between(from: Vector2, to: Vector2) -> String:
	var a := fposmod(rad_to_deg((to - from).angle()) + 90.0, 360.0)
	return DIRECTIONS[int(round(a / 45.0)) % 8]


func _community(sid: int) -> Dictionary:
	var st: Dictionary = w.sites.get(sid, {})
	return st if w.diplomacy.is_community(st) else {}


## How many quests a community offers and how rich they are, from its config and relation tier.
func _scale(st: Dictionary) -> Dictionary:
	var cfg := w.diplomacy.community_config(st)
	var quest_cfg: Dictionary = cfg.get("quests", {})
	var count := int(quest_cfg.get("count", 2))
	var reward := float(quest_cfg.get("reward_scale", 1.0))
	match Diplomacy.tier_for(int(st.get("relation", 0))):
		"Allied":
			count += 2
			reward *= 1.45
		"Friendly":
			count += 1
			reward *= 1.2
		"Wary":
			count -= 1
			reward *= 0.85
	return {"count": clampi(count, 1, 5), "reward": reward,
		"kinds": quest_cfg.get("kinds", KINDS), "level": maxi(1, int(st.get("level", 1)))}


# --- board ---------------------------------------------------------------------------------

## Offered quests of a community, re-rolled once per day. Empty while it is ruined or hostile.
func board(giver_sid: int) -> Array:
	var st := _community(giver_sid)
	if st.is_empty() or bool(st.get("ruined", false)) \
			or int(st.get("relation", 0)) <= Diplomacy.HOSTILE_AT or not bool(st.get("discovered", false)):
		_board.erase(giver_sid)
		return []
	if int(_board_day.get(giver_sid, -1)) != w.day:
		_roll_board(st)
	return _board.get(giver_sid, [])


func _roll_board(st: Dictionary) -> void:
	var sid := int(st["id"])
	_board_day[sid] = w.day
	var scale := _scale(st)
	var rng := RngUtil.make([w.seed, "quest_board", sid, w.day])
	var rows: Array = []
	var used_targets: Dictionary = {}
	for i in int(scale["count"]):
		var kind := str(RngUtil.pick(rng, scale["kinds"] as Array))
		var q := _make(st, kind, rng, scale, used_targets)
		if q.is_empty() and kind != "deliver":
			q = _make(st, "deliver", rng, scale, used_targets)
		if not q.is_empty():
			rows.append(q)
	_board[sid] = rows
	w.quests_changed.emit()


func _make(st: Dictionary, kind: String, rng: RandomNumberGenerator, scale: Dictionary,
		used_targets: Dictionary) -> Dictionary:
	var sid := int(st["id"])
	var level := int(scale["level"])
	var reward_scale := float(scale["reward"])
	var q := {"id": 0, "kind": kind, "giver_sid": sid, "target_sid": -1, "resource": "",
		"amount": 0, "reward_gold": 0, "reward_relation": 10, "reward_items": [],
		"deadline_day": w.day + 6, "state": "offered"}
	match kind:
		"deliver":
			var cfg := w.diplomacy.community_config(st)
			var wants: Array = cfg.get("wants", DELIVER_RESOURCES)
			if wants.is_empty():
				wants = DELIVER_RESOURCES
			var resource := str(RngUtil.pick(rng, wants))
			var amount := rng.randi_range(6, 12) + level * 2
			q["resource"] = resource
			q["amount"] = amount
			q["reward_gold"] = int(round(float(10 + amount * int(Diplomacy.RESOURCE_PRICES.get(resource, 2))) * reward_scale))
			q["reward_relation"] = 12
			q["deadline_day"] = w.day + rng.randi_range(3, 5)
		"bounty":
			var target := _pick_target(st, rng, used_targets, ["bandit_camp", "machine_outpost"], false)
			if target < 0:
				return {}
			q["target_sid"] = target
			var target_level := maxi(1, int((w.gen.sites.get(target, {}) as Dictionary).get("level", 1)))
			q["reward_gold"] = int(round(float(60 + target_level * 35) * reward_scale))
			q["reward_relation"] = 18
			q["deadline_day"] = w.day + rng.randi_range(6, 10)
			if rng.randf() < 0.55:
				q["reward_items"] = [ItemGen.generate(rng, {"level": maxi(level, target_level),
					"luck": 0.25, "source": "quest"})]
		"scout":
			var scout_target := _pick_target(st, rng, used_targets, [], true)
			if scout_target < 0:
				return {}
			q["target_sid"] = scout_target
			q["reward_gold"] = int(round(float(35 + level * 20) * reward_scale))
			q["reward_relation"] = 10
			q["deadline_day"] = w.day + rng.randi_range(5, 8)
		_:
			return {}
	q["id"] = _next_qid
	_next_qid += 1
	return q


## A site of one of `kinds` near the giver. `undiscovered` picks an unknown site (scouting),
## otherwise an uncleared hostile camp.
func _pick_target(st: Dictionary, rng: RandomNumberGenerator, used: Dictionary, kinds: Array,
		undiscovered: bool) -> int:
	var centre := Vector2(st["center"])
	var candidates: Array = []
	for gs: Dictionary in w.gen.sites.values():
		var target_sid := int(gs["id"])
		if target_sid == int(st["id"]) or used.has(target_sid):
			continue
		if not kinds.is_empty() and not (str(gs["kind"]) in kinds):
			continue
		if Vector2(gs["center"]).distance_to(centre) > BOUNTY_RANGE:
			continue
		var runtime: Dictionary = w.sites.get(target_sid, {})
		if undiscovered:
			if bool(runtime.get("discovered", false)) or str(gs["kind"]) in ["ore_field", "crystal_grove"]:
				continue
		elif bool(runtime.get("cleared", false)):
			continue
		candidates.append(target_sid)
	if candidates.is_empty():
		return -1
	var chosen := int(candidates[rng.randi_range(0, candidates.size() - 1)])
	used[chosen] = true
	return chosen


# --- taking and tracking -------------------------------------------------------------------

func get_quest(qid: int) -> Dictionary:
	if taken.has(qid):
		return taken[qid]
	for rows: Array in _board.values():
		for q: Dictionary in rows:
			if int(q["id"]) == qid:
				return q
	return {}


## All quests the player is working on (`active`) or that are waiting to be handed in (`done`).
func active() -> Array:
	var out: Array = []
	for q: Dictionary in taken.values():
		if str(q["state"]) in ["active", "done"]:
			out.append(q)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["id"]) < int(b["id"]))
	return out


## Quests of one giver the player already accepted.
func accepted_for(giver_sid: int) -> Array:
	var out: Array = []
	for q: Dictionary in active():
		if int(q["giver_sid"]) == giver_sid:
			out.append(q)
	return out


func active_count() -> int:
	return active().size()


## "" when the quest can be accepted, else an i18n key explaining why not.
func accept_blocker(qid: int) -> String:
	var q := get_quest(qid)
	if q.is_empty() or str(q["state"]) != "offered":
		return "quest.blocked.gone"
	var st := _community(int(q["giver_sid"]))
	if st.is_empty() or bool(st.get("ruined", false)):
		return "quest.blocked.gone"
	if int(st.get("relation", 0)) <= Diplomacy.HOSTILE_AT:
		return "quest.blocked.hostile"
	if active_count() >= MAX_ACTIVE:
		return "quest.blocked.too_many"
	if not w.diplomacy.is_near_community(int(q["giver_sid"])):
		return "quest.blocked.presence"
	return ""


## Takes an offered quest. Returns "" or an i18n key reason.
func accept(qid: int) -> String:
	var blocker := accept_blocker(qid)
	if blocker != "":
		return blocker
	var q := get_quest(qid)
	var sid := int(q["giver_sid"])
	var rows: Array = _board.get(sid, [])
	rows.erase(q)
	q["state"] = "active"
	taken[int(q["id"])] = q
	var st: Dictionary = w.sites[sid]
	var params := describe(q)
	params["village_name"] = str(st.get("name", ""))
	if str(q["kind"]) == "scout":
		_reveal_direction(q)
	w.notify_key("sim.quest.accepted", params, "info", Vector2(st["center"]), {"site": sid})
	w.quests_changed.emit()
	return ""


## The scouting hint: the giver points you in a rough direction, nothing more.
func _reveal_direction(q: Dictionary) -> void:
	var st: Dictionary = w.sites.get(int(q["giver_sid"]), {})
	var target: Dictionary = w.gen.sites.get(int(q["target_sid"]), {})
	if st.is_empty() or target.is_empty():
		return
	q["hint"] = direction_between(Vector2(st["center"]), Vector2(target["center"]))
	q["hint_distance"] = int(Vector2(st["center"]).distance_to(Vector2(target["center"])))


func abandon(qid: int) -> void:
	var q := get_quest(qid)
	if q.is_empty() or not taken.has(int(q["id"])):
		return
	taken.erase(int(q["id"]))
	var sid := int(q["giver_sid"])
	w.diplomacy.change_relation(sid, -4, "quest")
	var st: Dictionary = w.sites.get(sid, {})
	if not st.is_empty():
		w.notify_key("sim.quest.abandoned", {"village_name": str(st.get("name", "")),
			"quest": describe_text(q)}, "bad", Vector2(st["center"]), {"site": sid})
	w.quests_changed.emit()


# --- progress ------------------------------------------------------------------------------

## {done, have, need} for the progress bar and the turn-in button.
func progress(q: Dictionary) -> Dictionary:
	match str(q.get("kind", "")):
		"deliver":
			var need := int(q.get("amount", 0))
			var have := mini(int(w.res.get(str(q.get("resource", "food")), 0)), need)
			return {"done": have >= need, "have": have, "need": need}
		"bounty":
			var cleared := bool((w.sites.get(int(q.get("target_sid", -1)), {}) as Dictionary).get("cleared", false))
			return {"done": cleared, "have": 1 if cleared else 0, "need": 1}
		"scout":
			var found := bool((w.sites.get(int(q.get("target_sid", -1)), {}) as Dictionary).get("discovered", false))
			return {"done": found, "have": 1 if found else 0, "need": 1}
	return {"done": false, "have": 0, "need": 1}


## Refreshes `done`/`active` from the world state (called on the tick and before the UI reads it).
func refresh_states() -> void:
	var changed := false
	for q: Dictionary in taken.values():
		var state := str(q["state"])
		if state != "active" and state != "done":
			continue
		var done := bool(progress(q)["done"])
		var wanted := "done" if done else "active"
		if wanted != state:
			q["state"] = wanted
			changed = true
	if changed:
		w.quests_changed.emit()


## "" when it can be handed in, else an i18n key.
func turn_in_blocker(qid: int) -> String:
	var q := get_quest(qid)
	if q.is_empty() or not taken.has(int(q["id"])) or str(q["state"]) not in ["active", "done"]:
		return "quest.blocked.gone"
	if not bool(progress(q)["done"]):
		return "quest.blocked.unfinished"
	var sid := int(q["giver_sid"])
	var st := _community(sid)
	if st.is_empty() or bool(st.get("ruined", false)):
		return "quest.blocked.gone"
	if int(st.get("relation", 0)) <= Diplomacy.HOSTILE_AT:
		return "quest.blocked.hostile"
	if not w.diplomacy.is_near_community(sid):
		return "quest.blocked.presence"
	return ""


## Hands a finished quest in: takes the goods, pays gold, items and relation. "" or an i18n key.
func turn_in(qid: int) -> String:
	var blocker := turn_in_blocker(qid)
	if blocker != "":
		return blocker
	var q := get_quest(qid)
	var sid := int(q["giver_sid"])
	var st: Dictionary = w.sites[sid]
	if str(q["kind"]) == "deliver":
		var resource := str(q["resource"])
		var amount := int(q["amount"])
		if int(w.res.get(resource, 0)) < amount:
			return "quest.blocked.unfinished"
		w.res[resource] = int(w.res[resource]) - amount
		var stock: Dictionary = w.diplomacy.stock_of(sid)
		stock[resource] = mini(Diplomacy.STOCK_LIMIT, int(stock.get(resource, 0)) + amount)
	var gold := int(q["reward_gold"])
	if gold > 0:
		w.economy.add("gold", gold)
	for item: Dictionary in q.get("reward_items", []):
		var owned: Dictionary = item.duplicate(true)
		owned["uid"] = w.new_id()
		w.armory.append(owned)
	q["state"] = "turned_in"
	taken.erase(int(q["id"]))
	w.counters["quests_done"] = int(w.counters.get("quests_done", 0)) + 1
	w.diplomacy.change_relation(sid, int(q["reward_relation"]), "request")
	w.notify_key("sim.quest.turned_in", {"village_name": str(st.get("name", "")),
		"quest": describe_text(q), "reward": gold}, "good", Vector2(st["center"]), {"site": sid})
	w.quests_changed.emit()
	return ""


# --- days ----------------------------------------------------------------------------------

func on_new_day() -> void:
	for sid: Variant in _board.keys():
		_board_day[sid] = -1
	for q: Dictionary in taken.values().duplicate():
		if str(q["state"]) in ["active", "done"] and w.day > int(q["deadline_day"]):
			q["state"] = "failed"
			taken.erase(int(q["id"]))
			var st: Dictionary = w.sites.get(int(q["giver_sid"]), {})
			w.diplomacy.change_relation(int(q["giver_sid"]), -6, "ignored")
			if not st.is_empty() and bool(st.get("discovered", false)):
				w.notify_key("sim.quest.failed", {"village_name": str(st.get("name", "")),
					"quest": describe_text(q)}, "bad", Vector2(st["center"]), {"site": int(st["id"])})
	refresh_states()
	w.quests_changed.emit()


# --- migration & persistence ------------------------------------------------------------------

## Old saves carried a single `request` dict per village; it becomes an accepted deliver quest so
## nothing that was already promised is lost.
func migrate_site(st: Dictionary) -> void:
	var request: Dictionary = st.get("request", {})
	st.erase("request")
	st.erase("request_day")
	st.erase("request_serial")
	if request.is_empty() or not w.diplomacy.is_community(st):
		return
	var q := {"id": _next_qid, "kind": "deliver", "giver_sid": int(st["id"]), "target_sid": -1,
		"resource": str(request.get("resource", "food")), "amount": int(request.get("amount", 8)),
		"reward_gold": int(request.get("reward_gold", 20)),
		"reward_relation": int(request.get("relation", 12)), "reward_items": [],
		"deadline_day": maxi(int(request.get("due_day", w.day + 3)), w.day + 1), "state": "active"}
	_next_qid += 1
	taken[int(q["id"])] = q


func to_dict() -> Dictionary:
	var rows: Array = []
	for q: Dictionary in taken.values():
		rows.append(q)
	return {"next_qid": _next_qid, "taken": rows}


func from_dict(d: Dictionary) -> void:
	taken.clear()
	_board.clear()
	_board_day.clear()
	_next_qid = int(d.get("next_qid", 1))
	for row: Variant in d.get("taken", []):
		if not (row is Dictionary):
			continue
		var q: Dictionary = row
		for key: String in ["id", "giver_sid", "target_sid", "amount", "reward_gold",
				"reward_relation", "deadline_day", "hint_distance"]:
			if q.has(key):
				q[key] = int(q[key])
		taken[int(q["id"])] = q
		_next_qid = maxi(_next_qid, int(q["id"]) + 1)


# --- presentation ------------------------------------------------------------------------------

## Parameters for the `quest.line.<kind>` i18n strings.
func describe(q: Dictionary) -> Dictionary:
	var kind := str(q.get("kind", ""))
	var target: Dictionary = w.sites.get(int(q.get("target_sid", -1)), {})
	var gen_target: Dictionary = w.gen.sites.get(int(q.get("target_sid", -1)), {})
	var target_name := str(target.get("name", ""))
	if target_name == "" and not gen_target.is_empty():
		target_name = str(NameGen.place(RngUtil.make([w.seed, "site", int(gen_target["id"])]),
			FactionAI.PLACE_KIND.get(str(gen_target["kind"]), "region")))
	return {"kind": kind, "resource": Loc.t(str(q.get("resource", ""))),
		"amount": int(q.get("amount", 0)), "site_name": target_name,
		"direction": Loc.t(str(q.get("hint", ""))), "distance": int(q.get("hint_distance", 0)),
		"reward": int(q.get("reward_gold", 0)), "deadline": int(q.get("deadline_day", 0))}


func describe_text(q: Dictionary) -> String:
	return Loc.t(str(LINE_KEY.get(str(q.get("kind", "deliver")), LINE_KEY["deliver"])), describe(q))
