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
## Path of 15 grids: [size, tier]
const PATH = [[4, 1], [4, 1], [4, 1], [4, 1],
	[6, 1], [6, 1], [6, 1], [6, 2], [6, 2], [6, 2],
	[9, 2], [9, 2], [9, 3], [9, 3], [9, 3]]

var coins: int = 100
var tokens: int = 3
var stars: int = 0          # unspent stars
var stars_earned: int = 0
var path_next: int = 0      # index of next path grid (0..15)
var path_stars: Array = []  # stars awarded per completed path grid
var tasks: Dictionary = {}  # id -> true
var decor: Dictionary = {}  # id -> choice index
var sc_times: Array = []    # second-chance use timestamps (Unix ms)
var sc_lock_until: int = 0  # clock-rollback lock
var current_grid: Dictionary = {}  # saved grid in progress
var classic_index: Dictionary = {}  # tier -> next pack index
var quick_seed: int = 0
var classic_tier: int = 1

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
static func stars_for(size: int, mistakes_or_continue: bool, revealed: bool) -> int:
	match size:
		4: return 1
		6: return 1 + (0 if mistakes_or_continue else 1)
	return 2 + (0 if (mistakes_or_continue or revealed) else 1)

## Completion bookkeeping. mode: "path" | "quick" | "classic". Returns {coins, stars, token}.
func complete_grid(mode: String, size: int, path_index: int, had_mistakes: bool, revealed: bool) -> Dictionary:
	var r = {"coins": COINS[size], "stars": 0, "token": 0}
	coins += COINS[size]
	if mode == "path" and path_index == path_next and path_next < PATH.size():
		var s = stars_for(size, had_mistakes, revealed)
		path_stars.append(s)
		stars += s
		stars_earned += s
		path_next += 1
		r.stars = s
		r.token = grant_tokens(1)
	return r

func path_finished() -> bool:
	return path_next >= PATH.size()

func task_cost(id: String) -> int:
	for t in TASKS:
		if t.id == id: return t.cost
	return 999

func buy_task(id: String) -> bool:
	if tasks.has(id) or stars < task_cost(id): return false
	stars -= task_cost(id)
	tasks[id] = true
	decor[id] = 0
	return true

func set_decor(id: String, choice: int) -> void:
	if tasks.has(id): decor[id] = choice

func area_restored() -> bool:
	return tasks.size() == TASKS.size()

func to_dict() -> Dictionary:
	return {"v": 1, "coins": coins, "tokens": tokens, "stars": stars, "stars_earned": stars_earned,
		"path_next": path_next, "path_stars": path_stars, "tasks": tasks, "decor": decor,
		"sc_times": sc_times, "sc_lock_until": sc_lock_until, "current_grid": current_grid,
		"classic_index": classic_index, "quick_seed": quick_seed, "classic_tier": classic_tier}

func from_dict(d: Dictionary) -> void:
	coins = int(d.get("coins", 100)); tokens = int(d.get("tokens", 3))
	stars = int(d.get("stars", 0)); stars_earned = int(d.get("stars_earned", 0))
	path_next = int(d.get("path_next", 0))
	path_stars = []
	for s in d.get("path_stars", []): path_stars.append(int(s))
	tasks = d.get("tasks", {})
	decor = {}
	for k in d.get("decor", {}): decor[k] = int(d.decor[k])
	sc_times = []
	for t in d.get("sc_times", []): sc_times.append(int(t))
	sc_lock_until = int(d.get("sc_lock_until", 0))
	current_grid = d.get("current_grid", {})
	classic_index = {}
	for k in d.get("classic_index", {}): classic_index[str(k)] = int(d.classic_index[k])
	quick_seed = int(d.get("quick_seed", 0))
	classic_tier = clampi(int(d.get("classic_tier", 1)), 1, 4)
