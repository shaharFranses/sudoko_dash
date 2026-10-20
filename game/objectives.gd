## Level objectives (LEVEL_OBJECTIVES_SPEC v1). Pure logic: target sets, validation, par time, stars, labels.
extends RefCounted

const Shape = preload("res://sudoku/shape.gd")
const PAR_BASE = {4: 10, 6: 20, 9: 30}
const REVEAL_PENALTY_S = 15.0
const TYPES = ["full", "digit", "line", "lantern", "tide"]

static func _unit_index(n: int, u: Dictionary) -> int:
	match str(u.kind):
		"row": return int(u.index)
		"col": return n + int(u.index)
	return 2 * n + int(u.index)

## Target cells T (sorted cell indices). Lantern T = EMPTY path cells only (v1.2 §9.5).
static func targets(n: int, givens: Array, solution: Array, objective: String, params: Dictionary) -> Array:
	var shape = Shape.of(n)
	var t = {}
	match objective:
		"full":
			for i in shape.cells:
				if int(givens[i]) == 0: t[i] = true
		"digit":
			for i in shape.cells:
				if int(givens[i]) == 0 and int(solution[i]) == int(params.digit): t[i] = true
		"line":
			for u in params.units:
				for c in shape.units[_unit_index(n, u)]:
					if int(givens[c]) == 0: t[c] = true
		"lantern":
			for rc in params.path:
				var c = int(rc[0]) * n + int(rc[1])
				if int(givens[c]) == 0: t[c] = true
		"tide":
			var inner = params.duplicate()
			return targets(n, givens, solution, str(params.inner), inner)
	var out = t.keys()
	out.sort()
	return out

## Lantern path: 6-10 distinct cells, consecutive cells orthogonally adjacent, >= 4 empty.
static func lantern_valid(n: int, path: Array, givens: Array) -> bool:
	if path.size() < 6 or path.size() > 10: return false
	var seen = {}
	var empty = 0
	for k in path.size():
		var r = int(path[k][0]); var c = int(path[k][1])
		if r < 0 or c < 0 or r >= n or c >= n or seen.has(r * n + c): return false
		seen[r * n + c] = true
		if int(givens[r * n + c]) == 0: empty += 1
		if k > 0 and absi(r - int(path[k - 1][0])) + absi(c - int(path[k - 1][1])) != 1: return false
	return empty >= 4

static func par_time_s(n: int, steps_to_t: int, par_mult: float) -> int:
	return int(round((PAR_BASE[n] + 6 * steps_to_t) * par_mult))

static func is_timed(level: Dictionary) -> bool:
	return str(level.objective) == "tide"

## Stars 1-3. Non-timed: 1 + (no mistakes & no Continue) + (no Reveal).
## Tide (v1.2 §9.1-2): elapsed_ms (Reveal penalties included) <= floor(0.75*par*1000) -> 3, <= par*1000 -> 2, else 1.
static func stars(level: Dictionary, had_mistakes_or_continue: bool, reveals: int, elapsed_ms: int) -> int:
	if is_timed(level):
		var par_ms = int(level.par_time_s) * 1000
		if elapsed_ms <= int(floor(0.75 * int(level.par_time_s) * 1000.0)): return 3
		if elapsed_ms <= par_ms: return 2
		return 1
	return 1 + (0 if had_mistakes_or_continue else 1) + (1 if reveals == 0 else 0)

## Level complete: every target holds its correct digit.
static func complete(cells: Array, solution: Array, t: Array) -> bool:
	for i in t:
		if int(cells[i]) != int(solution[i]): return false
	return true

static func progress(cells: Array, solution: Array, t: Array) -> int:
	var k = 0
	for i in t:
		if int(cells[i]) == int(solution[i]): k += 1
	return k

static func _units_text(units: Array) -> String:
	var parts = []
	for u in units:
		parts.append("%s %d" % [{"row": "row", "col": "column", "box": "box"}[str(u.kind)], int(u.index) + 1])
	return " and ".join(parts)

## Player-facing objective line.
static func label(level: Dictionary, cells: Array = [], solution: Array = [], t: Array = []) -> String:
	var p: Dictionary = level.params
	var obj = str(level.objective)
	var inner = str(p.get("inner", "")) if obj == "tide" else obj
	var txt = ""
	match inner:
		"full": txt = "Solve the board"
		"digit":
			txt = "Place every %d" % int(p.digit)
			if not cells.is_empty():
				# count of all cells with that digit (givens included), e.g. 3/9
				var have = 0
				var total = 0
				for i in solution.size():
					if int(solution[i]) == int(p.digit):
						total += 1
						if int(cells[i]) == int(p.digit): have += 1
				txt += "  %d/%d" % [have, total]
		"line": txt = "Complete " + _units_text(p.units)
		"lantern":
			txt = "Light the lanterns"
			if not cells.is_empty(): txt += "  %d/%d" % [progress(cells, solution, t), t.size()]
	if obj == "tide": txt = "Beat the Tide: " + txt
	return txt
