## Player profile + economy rules (spec v3 §3, §5, §7). Pure logic; times are Unix ms passed in.
extends RefCounted

const TOKEN_CAP = 10
const HINT_COIN_PRICE = 30
const CONTINUE_COIN_PRICE = 50
const SC_WINDOW_MS = 24 * 3600 * 1000
const SC_MAX = 3
const COINS = {4: 10, 6: 20, 9: 40}
const TASKS = [
	{"id": "dock", "name": "Fix dock", "cost": 3, "decor": ["Oak planks", "Blue planks", "Rope posts"]},
	{"id": "boats", "name": "Paint boats", "cost": 4, "decor": ["Red & white", "Sea green", "Sunny yellow"]},
	{"id": "flowers", "name": "Plant flowerbeds", "cost": 4, "decor": ["Geraniums", "Lavender"]},
	{"id": "lighthouse", "name": "Restore lighthouse", "cost": 4, "decor": ["Red stripes", "Blue stripes", "Classic white"]},
	{"id": "cafe", "name": "Café terrace", "cost": 5, "decor": ["Striped awning", "Parasols"]},
]
const Levels = preload("res://game/levels.gd")
const PATH_VERSION = 2   # 1 = old 15-grid path, 2 = 20-level objectives path
## Save format version. Bump it when a field changes meaning and add a step to _migrate(); never rename
## or reuse a key. Saves from newer builds load too (unknown keys are kept and written back).
const SAVE_VERSION = 2

var coins: int = 100
var tokens: int = 3
var stars: int = 0          # unspent stars
var stars_earned: int = 0
var path_next: int = 0      # index of next path grid (0..15)
var path_stars: Array = []  # stars awarded per completed level (first completion)
var level_best: Array = []  # best stars per level (0 = unknown / migrated)
var migrated_from_v1: bool = false
var tasks: Dictionary = {}  # id -> true
var decor: Dictionary = {}  # id -> choice index
var sc_times: Array = []    # second-chance use timestamps (Unix ms)
var sc_lock_until: int = 0  # clock-rollback lock
var current_grid: Dictionary = {}  # saved grid in progress
var classic_index: Dictionary = {}  # tier -> next pack index
var quick_seed: int = 0
var classic_tier: int = 1
var sound_on: bool = true   # Settings > Sound (mute reason "user")
var story_seen: bool = false   # first Play shows the story intro once (replay from the title)
var save_version_loaded: int = 0   # "v" of the save this profile came from (0 = fresh)
var _extra: Dictionary = {}        # keys this build doesn't know (written by a newer build): kept as-is

func grant_tokens(n: int) -> int:
	var before = tokens
	tokens = mini(TOKEN_CAP, tokens + n)
	return tokens - before

func can_afford(price: int) -> bool:
	return coins >= price

func need_more(price: int) -> int:
	return maxi(0, price - coins)

func spend_coins(price: int) -> bool:
	if coins < price: return false
	coins -= price
	return true

func spend_token() -> bool:
	if tokens <= 0: return false
	tokens -= 1
	return true

# ---- second chance cap (rolling 24 h, rollback-protected) ----
func _newest() -> int:
	var m = 0
	for t in sc_times: m = maxi(m, int(t))
	return m

func sc_capped(now_ms: int) -> bool:
	var newest = _newest()
	if now_ms < newest:
		# Clock moved back: window treated as full until the clock passes newest + 24h.
		sc_lock_until = maxi(sc_lock_until, newest + SC_WINDOW_MS)
	if now_ms < sc_lock_until: return true
	var n = 0
	for t in sc_times:
		var tt = mini(int(t), now_ms)  # clamp future timestamps
		if tt > now_ms - SC_WINDOW_MS: n += 1
	return n >= SC_MAX

func record_second_chance(now_ms: int) -> void:
	sc_times.append(now_ms)
	# keep only what can still matter
	var keep = []
	for t in sc_times:
		if int(t) > now_ms - SC_WINDOW_MS or int(t) > now_ms: keep.append(int(t))
	sc_times = keep

# ---- path / stars ----
static func path_length() -> int:
	return Levels.count()

## Level completion (path). Stars only on first completion; best kept on replays. Coins by size.
func complete_level(index: int, size: int, stars_won: int) -> Dictionary:
	var r = {"coins": COINS[size], "stars": 0, "token": 0, "level_stars": stars_won}
	coins += COINS[size]
	while level_best.size() <= index: level_best.append(0)
	level_best[index] = maxi(level_best[index], stars_won)
	if index == path_next and path_next < path_length():
		path_stars.append(stars_won)
		stars += stars_won
		stars_earned += stars_won
		path_next += 1
		r.stars = stars_won
		r.token = grant_tokens(1)
	return r

## Quick / Classic: coins only.
func complete_grid(mode: String, size: int, _path_index: int = -1, _m: bool = false, _r: bool = false) -> Dictionary:
	coins += COINS[size]
	return {"coins": COINS[size], "stars": 0, "token": 0}

func path_finished() -> bool:
	return path_next >= path_length()

func task_cost(id: String) -> int:
	for t in TASKS:
		if t.id == id: return t.cost
	return 999

## Tasks unlock in order (spec v1 §5).
func task_unlocked(id: String) -> bool:
	for t in TASKS:
		if t.id == id: return true
		if not tasks.has(t.id): return false
	return false

func buy_task(id: String) -> bool:
	if tasks.has(id) or not task_unlocked(id) or stars < task_cost(id): return false
	stars -= task_cost(id)
	tasks[id] = true
	decor[id] = 0
	return true

func set_decor(id: String, choice: int) -> void:
	if tasks.has(id): decor[id] = choice

func area_restored() -> bool:
	return tasks.size() == TASKS.size()

func to_dict() -> Dictionary:
	var d = _extra.duplicate(true)
	d.merge(_to_dict_known(), true)
	return d

func _to_dict_known() -> Dictionary:
	return {"v": maxi(SAVE_VERSION, save_version_loaded), "coins": coins, "tokens": tokens, "stars": stars, "stars_earned": stars_earned,
		"path_v": PATH_VERSION, "path_next": path_next, "path_stars": path_stars, "level_best": level_best, "migrated_from_v1": migrated_from_v1, "tasks": tasks, "decor": decor,
		"sc_times": sc_times, "sc_lock_until": sc_lock_until, "current_grid": current_grid,
		"classic_index": classic_index, "quick_seed": quick_seed, "classic_tier": classic_tier, "sound_on": sound_on, "story_seen": story_seen}

const KNOWN_KEYS = ["v", "coins", "tokens", "stars", "stars_earned", "path_v", "path_next", "path_stars", "level_best",
	"migrated_from_v1", "tasks", "decor", "sc_times", "sc_lock_until", "current_grid", "classic_index", "quick_seed",
	"classic_tier", "sound_on", "story_seen"]

## Load a save from any build: migrate old formats, keep unknown keys, then fit the data to this build's
## content (levels, tasks, decor may have changed in a deploy). Never throws on odd data.
func from_dict(raw: Dictionary) -> void:
	save_version_loaded = int(raw.get("v", 1))
	var d = _migrate(raw.duplicate(true))
	_extra = {}
	for k in d:
		if not str(k) in KNOWN_KEYS: _extra[k] = d[k]
	_from_dict_known(d)
	_sanitize()

## Step-by-step save migrations (v -> v+1). Add a branch per SAVE_VERSION bump.
static func _migrate(d: Dictionary) -> Dictionary:
	var v = int(d.get("v", 1))
	if v < 2:
		# v1 -> v2: no field changes; v2 adds story_seen (defaulted from progress) and the versioned loader.
		v = 2
	d["v"] = maxi(v, int(d.get("v", 1)))
	return d

## Clamp everything to the current build's content so a deploy can never crash an old save.
func _sanitize() -> void:
	coins = maxi(0, coins); tokens = clampi(tokens, 0, TOKEN_CAP)
	stars = maxi(0, stars); stars_earned = maxi(stars_earned, 0)
	var n = path_length()
	path_next = clampi(path_next, 0, n)
	while path_stars.size() > n: path_stars.pop_back()
	while level_best.size() > n: level_best.pop_back()
	var known = {}
	for t in TASKS: known[t.id] = t
	var kept = {}
	for id in tasks:
		if known.has(str(id)): kept[str(id)] = true
	tasks = kept
	var dec = {}
	for id in decor:
		if tasks.has(str(id)): dec[str(id)] = clampi(int(decor[id]), 0, known[str(id)].decor.size() - 1)
	decor = dec
	if not _grid_ok(current_grid): current_grid = {}

## A saved in-progress grid is resumable only if it is well formed and, for a path level, the level still
## uses the same puzzle in this build.
static func _grid_ok(g) -> bool:
	if not g is Dictionary or g.is_empty(): return true   # nothing to resume is fine
	var meta = g.get("meta"); var b = g.get("board")
	if not meta is Dictionary or not b is Dictionary: return false
	if not str(meta.get("mode", "")) in ["path", "quick", "classic"]: return false
	var sz = int(b.get("size", 0))
	if not sz in [4, 6, 9]: return false
	for k in ["givens", "solution", "cells"]:
		if not b.get(k) is Array or b[k].size() != sz * sz: return false
	if not b.get("notes") is Array or not b.get("history") is Array: return false
	if str(meta.mode) == "path":
		var i = int(meta.get("path_index", -1))
		if i < 0 or i >= path_length(): return false
		var gr = Levels.grid(Levels.level(i).grid_id)
		if str(gr.get("id", "")) != str(meta.get("id", "")): return false
	return true

func _from_dict_known(d: Dictionary) -> void:
	coins = int(d.get("coins", 100)); tokens = int(d.get("tokens", 3))
	stars = int(d.get("stars", 0)); stars_earned = int(d.get("stars_earned", 0))
	path_next = int(d.get("path_next", 0))
	path_stars = []
	for s in d.get("path_stars", []): path_stars.append(int(s))
	level_best = []
	for s in d.get("level_best", []): level_best.append(int(s))
	migrated_from_v1 = bool(d.get("migrated_from_v1", false))
	if int(d.get("path_v", 1)) < PATH_VERSION:
		_migrate_v1()
	tasks = d.get("tasks", {}) if d.get("tasks") is Dictionary else {}
	decor = {}
	for k in d.get("decor", {}): decor[k] = int(d.decor[k])
	sc_times = []
	for t in d.get("sc_times", []): sc_times.append(int(t))
	sc_lock_until = int(d.get("sc_lock_until", 0))
	current_grid = d.get("current_grid", {}) if d.get("current_grid") is Dictionary else {}
	classic_index = {}
	for k in d.get("classic_index", {}): classic_index[str(k)] = int(d.classic_index[k])
	quick_seed = int(d.get("quick_seed", 0))
	if int(d.get("path_v", 1)) < PATH_VERSION and current_grid.get("meta", {}).get("mode", "") == "path":
		current_grid = {}   # an old 15-grid path grid in progress can't map to a level
	classic_tier = clampi(int(d.get("classic_tier", 1)), 1, 4)
	sound_on = bool(d.get("sound_on", true))
	# Saves from before the story intro: a player with any progress has already met the Harbour.
	story_seen = bool(d.get("story_seen", stars_earned > 0 or path_next > 0 or not tasks.is_empty()))

## Old 15-grid path -> 20-level path. Earned stars, coins, tokens and bought tasks are kept as-is
## (no double award); progress maps proportionally (n/15 -> floor(n*20/15)); those levels count as
## completed with best = 0 (replayable, no further stars).
func _migrate_v1() -> void:
	var old = path_next
	path_next = mini(path_length(), int(floor(old * path_length() / 15.0)))
	level_best = []
	for i in path_next: level_best.append(0)
	path_stars = []
	for i in path_next: path_stars.append(0)
	migrated_from_v1 = old > 0
