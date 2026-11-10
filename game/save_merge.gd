## Save integrity (pure logic, no engine nodes): profile schema check, "real progress" test, the v2 save
## envelope {v, seq, saved_at, profile} and the choice between the local and cloud copies.
##
## Choice: highest seq among copies whose profile is valid; saved_at only breaks a seq tie (device clocks can
## be skewed); a full tie prefers the cloud copy (old behaviour). Legacy (v1: bare profile + optional '.t' stamp)
## copies rank below every v2 envelope (seq -1) and are compared by their stamp. Invalid copies never win.
extends RefCounted

const VERSION = 2
const DEFAULT_COINS = 100
const DEFAULT_TOKENS = 3
const MAX_COUNT = 100000000   # sanity bound for coins / stars / timestamps-as-counts

static func _num(v) -> bool:
	return (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT) and is_finite(float(v))

static func _int_in(v, lo: float, hi: float) -> bool:
	return _num(v) and float(v) >= lo and float(v) <= hi and float(v) == floor(float(v))

static func _num_array(v, lo: float, hi: float) -> bool:
	if typeof(v) != TYPE_ARRAY: return false
	for x in v:
		if not _int_in(x, lo, hi): return false
	return true

## A stored profile is usable: a Dictionary with the core fields every save has written since v1, and every
## present field of the right type and in range (so Profile.from_dict can't be fed garbage).
static func valid_profile(d) -> bool:
	if typeof(d) != TYPE_DICTIONARY: return false
	for k in ["coins", "tokens", "path_next"]:
		if not d.has(k): return false
	if not _int_in(d.coins, 0, MAX_COUNT): return false
	if not _int_in(d.tokens, 0, 1000): return false
	if not _int_in(d.path_next, 0, 100): return false
	var ints = {"stars": [0, MAX_COUNT], "stars_earned": [0, MAX_COUNT], "path_v": [1, 100], "sc_lock_until": [0, 1e16],
		"quick_seed": [-2147483648, 4294967295], "classic_tier": [1, 4], "v": [1, 100]}
	for k in ints:
		if d.has(k) and not _int_in(d[k], ints[k][0], ints[k][1]): return false
	for k in ["path_stars", "level_best"]:
		if d.has(k) and not _num_array(d[k], 0, 3): return false
	if d.has("sc_times") and not _num_array(d.sc_times, 0, 1e16): return false
	for k in ["migrated_from_v1", "sound_on"]:
		if d.has(k) and typeof(d[k]) != TYPE_BOOL: return false
	if d.has("tasks"):
		if typeof(d.tasks) != TYPE_DICTIONARY: return false
		for t in d.tasks:
			if typeof(d.tasks[t]) != TYPE_BOOL: return false
	for k in ["decor", "classic_index"]:
		if d.has(k):
			if typeof(d[k]) != TYPE_DICTIONARY: return false
			for t in d[k]:
				if not _int_in(d[k][t], 0, MAX_COUNT): return false
	if d.has("current_grid"):
		var g = d.current_grid
		if typeof(g) != TYPE_DICTIONARY: return false
		if not g.is_empty():
			if typeof(g.get("meta")) != TYPE_DICTIONARY or typeof(g.get("board")) != TYPE_DICTIONARY: return false
			if g.has("level") and typeof(g.level) != TYPE_DICTIONARY: return false
	return true

## Anything a player did that would be lost by writing a fresh profile over it.
static func has_progress(d: Dictionary) -> bool:
	if int(d.get("coins", DEFAULT_COINS)) != DEFAULT_COINS or int(d.get("tokens", DEFAULT_TOKENS)) != DEFAULT_TOKENS: return true
	for k in ["stars", "stars_earned", "path_next", "quick_seed"]:
		if int(d.get(k, 0)) != 0: return true
	for k in ["path_stars", "level_best", "sc_times", "tasks", "decor", "current_grid", "classic_index"]:
		var v = d.get(k)
		if (v is Array or v is Dictionary) and not v.is_empty(): return true
	if int(d.get("classic_tier", 1)) != 1: return true
	if d.get("sound_on", true) == false: return true
	return false

## JSON parse without engine error logging (a corrupt copy is an expected case, not a console error).
static func parse_json(text: String):
	var j = JSON.new()
	return j.data if j.parse(text) == OK else null

static func envelope(seq: int, saved_at: int, profile: Dictionary) -> String:
	return JSON.stringify({"v": VERSION, "seq": seq, "saved_at": saved_at, "profile": profile})

## Parse one stored copy. v2 text -> envelope; legacy text (bare profile) -> seq -1 and its '.t' stamp.
## Returns {source, parsed (JSON ok + right shape), valid (profile usable), seq, saved_at, profile}.
static func parse_copy(source: String, v2_text, legacy_text = null, legacy_stamp = null) -> Dictionary:
	var out = {"source": source, "parsed": false, "valid": false, "seq": -2, "saved_at": -1, "profile": {}, "legacy": false}
	if v2_text != null and str(v2_text) != "":
		var e = parse_json(str(v2_text))
		if e is Dictionary and _int_in(e.get("seq"), 0, 9007199254740991.0):
			out.parsed = true
			out.seq = int(e.seq)
			out.saved_at = int(e.saved_at) if _num(e.get("saved_at")) else -1
			if valid_profile(e.get("profile")):
				out.valid = true
				out.profile = e.profile
				return out
	# no usable v2 envelope here: the legacy copy (bare profile JSON) may still hold the player's progress
	if legacy_text != null and str(legacy_text) != "":
		var p = parse_json(str(legacy_text))
		if valid_profile(p):
			var st = int(str(legacy_stamp)) if legacy_stamp != null and str(legacy_stamp).is_valid_int() else 0
			return {"source": source, "parsed": true, "valid": true, "seq": -1, "saved_at": st, "profile": p,
				"legacy": true, "v2_seq": out.seq}
	return out

## Best valid copy, or {} if none. Ordering: seq, then saved_at, then cloud over local.
static func choose(copies: Array) -> Dictionary:
	var best = {}
	for c in copies:
		if not c.valid: continue
		if best.is_empty() or _better(c, best): best = c
	return best

static func _better(a: Dictionary, b: Dictionary) -> bool:
	if a.seq != b.seq: return a.seq > b.seq
	if a.saved_at != b.saved_at: return a.saved_at > b.saved_at
	return a.source == "cloud" and b.source != "cloud"

## Highest seq seen in any parseable envelope (valid or not), so the next write outranks every stored copy.
static func max_seq(copies: Array) -> int:
	var m = 0
	for c in copies:
		m = maxi(m, int(c.seq))
		if c.has("v2_seq"): m = maxi(m, int(c.v2_seq))
	return m
