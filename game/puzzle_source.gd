## Supplies puzzles. 9x9 ONLY from offline packs (never generated/graded at runtime).
## 4x4/6x6 generated at runtime within 30 ms p95, else fall back to bundled packs.
extends RefCounted

const Sudoku = preload("res://sudoku/sudoku.gd")
const BUDGET_MS = 30.0

var _packs: Dictionary = {}
var gen_times_ms: Array = []
var call_times_ms: Array = []
const RUNTIME_ATTEMPTS = 3
var use_fallback: Dictionary = {4: false, 6: false}
var log: Array = []   # [{size, tier, source, ms}] - QA hook (AC3)

func pack(size: int, tier: int) -> Array:
	var key = "%dx%d_t%d" % [size, size, tier]
	if not _packs.has(key):
		var f = FileAccess.open("res://data/packs/%s.json" % key, FileAccess.READ)
		_packs[key] = JSON.parse_string(f.get_as_text()).puzzles if f else []
	return _packs[key]

static func _ints(a: Array) -> Array:
	var o = []
	for v in a: o.append(int(v))
	return o

func from_pack(size: int, tier: int, index: int) -> Dictionary:
	var p: Array = pack(size, tier)
	var e: Dictionary = p[index % p.size()]
	log.append({"size": size, "tier": tier, "source": "pack", "index": index % p.size(), "ms": 0.0})
	print("[SD][gen] pack size=%d tier=%d index=%d (no runtime generate/grade)" % [size, tier, index % p.size()])
	return {"size": size, "tier": tier, "givens": _ints(e.givens), "solution": _ints(e.solution), "id": e.id}

func get_puzzle(size: int, tier: int, seed_value: int) -> Dictionary:
	if size == 9: return from_pack(9, tier, seed_value)
	if use_fallback.get(size, false): return from_pack(size, tier, seed_value)
	var t0 = Time.get_ticks_usec()
	var p = Sudoku.generate(size, tier, seed_value, RUNTIME_ATTEMPTS)
	var ms = (Time.get_ticks_usec() - t0) / 1000.0
	if p.tier != tier:
		# missed within the time-bounded attempt budget -> bundled pack
		gen_times_ms.append(ms)
		return from_pack(size, tier, seed_value)
	gen_times_ms.append(ms)
	log.append({"size": size, "tier": tier, "source": "generated", "seed": seed_value, "ms": ms})
	print("[SD][timing] generate size=%d tier=%d seed=%d ms=%.2f" % [size, tier, seed_value, ms])
	if p95() > BUDGET_MS and gen_times_ms.size() >= 5: use_fallback[size] = true
	if ms > BUDGET_MS * 2: use_fallback[size] = true
	return {"size": size, "tier": tier, "givens": p.givens, "solution": p.solution, "id": "gen_%d_%d_%d" % [size, tier, seed_value]}

func p95() -> float:
	if gen_times_ms.is_empty(): return 0.0
	var s = gen_times_ms.duplicate()
	s.sort()
	return s[mini(s.size() - 1, int(ceil(s.size() * 0.95)) - 1)]
