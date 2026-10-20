## Public API of the engine-agnostic sudoku module. Pure static functions over plain Arrays/Dictionaries.
##   generate(size, tier, seed) -> {givens, solution, tier, steps, size}
##   solve(grid)                -> {solution, count}   (count capped at 2)
##   step(grid)                 -> {technique, cells, eliminations, value, ...} or {}
##   grade(givens)              -> {tier, steps[]}     (tier 5 = needs techniques beyond tier 4 / unsolvable)
extends RefCounted

const Shape = preload("res://sudoku/shape.gd")
const Logic = preload("res://sudoku/logic.gd")
const Rng = preload("res://sudoku/rng.gd")

const MAX_ATTEMPTS = 400

static func size_of(grid: Array) -> int:
	var n = int(round(sqrt(grid.size())))
	assert(n * n == grid.size() and (n == 4 or n == 6 or n == 9), "grid must be 16, 36 or 81 cells")
	return n

# ---------------- Backtracking ----------------

static func _search(shape, g: Array, rows: Array, cols: Array, boxes: Array, cap: int, rng, out: Dictionary) -> void:
	var best = -1
	var best_mask = 0
	var best_cnt = 99
	for i in shape.cells:
		if g[i] != 0: continue
		var m: int = shape.full_mask & ~(rows[i / shape.size] | cols[i % shape.size] | boxes[shape.box(i)])
		var pc = Shape.popcount(m)
		if pc < best_cnt:
			best_cnt = pc; best = i; best_mask = m
			if pc <= 1: break
	if best == -1:
		out.count += 1
		if out.solution.is_empty(): out.solution = g.duplicate()
		return
	if best_cnt == 0: return
	var ds = Shape.digits(best_mask)
	if rng != null: rng.shuffle(ds)
	var r: int = best / shape.size
	var c: int = best % shape.size
	var b: int = shape.box(best)
	for d in ds:
		var bit = 1 << (d - 1)
		g[best] = d; rows[r] |= bit; cols[c] |= bit; boxes[b] |= bit
		_search(shape, g, rows, cols, boxes, cap, rng, out)
		g[best] = 0; rows[r] &= ~bit; cols[c] &= ~bit; boxes[b] &= ~bit
		if out.count >= cap: return

static func _count(shape, grid: Array, cap: int, rng = null) -> Dictionary:
	var g = grid.duplicate()
	var rows = []; var cols = []; var boxes = []
	rows.resize(shape.size); cols.resize(shape.size); boxes.resize(shape.size)
	rows.fill(0); cols.fill(0); boxes.fill(0)
	for i in shape.cells:
		var d: int = g[i]
		if d == 0: continue
		var bit = 1 << (d - 1)
		var r: int = i / shape.size
		var c: int = i % shape.size
		var bx: int = shape.box(i)
		if (rows[r] | cols[c] | boxes[bx]) & bit:
			return {"solution": [], "count": 0}
		rows[r] |= bit; cols[c] |= bit; boxes[bx] |= bit
	var out = {"count": 0, "solution": []}
	_search(shape, g, rows, cols, boxes, cap, rng, out)
	return out

static func solve(grid: Array) -> Dictionary:
	return _count(Shape.of(size_of(grid)), grid, 2)

# ---------------- Human steps / grading ----------------

static func step(grid: Array) -> Dictionary:
	var shape = Shape.of(size_of(grid))
	var cand = Logic.init_candidates(shape, grid)
	return Logic.find_step(shape, grid, cand, 4)

## Next step given explicit candidate masks (e.g. after earlier eliminations).
static func step_with_candidates(grid: Array, cand: Array) -> Dictionary:
	return Logic.find_step(Shape.of(size_of(grid)), grid, cand, 4)

static func grade(givens: Array) -> Dictionary:
	var r = Logic.run(Shape.of(size_of(givens)), givens, 4, true)
	return {"tier": r.tier, "steps": r.steps, "solved": r.solved}

## Compact step log for storage: [{t, c, v, e}] -> see expand_step.
static func compact_steps(steps: Array) -> Array:
	var out = []
	for s in steps:
		var e = {"t": s.technique, "c": s.cells, "v": s.value}
		if s.eliminations.size() > 0: e["e"] = s.eliminations
		if s.get("unit", -1) >= 0: e["u"] = s.unit
		out.append(e)
	return out

# ---------------- Generation ----------------

static func valid_tiers(n: int) -> Array:
	match n:
		4: return [1]
		6: return [1, 2]
	return [1, 2, 3, 4]

static func generate(n: int, tier: int, seed_value: int, max_attempts: int = MAX_ATTEMPTS) -> Dictionary:
	var shape = Shape.of(n)
	var rng = Rng.new(seed_value * 31 + n * 7 + tier)
	var empty = []
	empty.resize(shape.cells); empty.fill(0)
	var best = {}
	for attempt in max_attempts:
		var solution: Array = _count(shape, empty, 1, rng).solution
		var givens = solution.duplicate()
		var order = range(shape.cells)
		rng.shuffle(order)
		for c in order:
			var v = givens[c]
			givens[c] = 0
			# Solvable using techniques <= tier implies a unique solution.
			if not Logic.run(shape, givens, tier, false).solved:
				givens[c] = v
		var gr = grade(givens)
		var res = {"size": n, "givens": givens, "solution": solution, "tier": gr.tier, "steps": gr.steps, "attempts": attempt + 1}
		if gr.tier == tier: return res
		if best.is_empty() or absi(gr.tier - tier) < absi(best.tier - tier): best = res
	return best

# ---------------- Level objectives: target-cell analysis ----------------

## Teach for objectives: next step on `grid` preferring steps whose cell is in `target_cells`
## or whose eliminations affect them; falls back to step(grid) when no such step exists.
## Adds "touches_target": bool to the returned step.
static func step_for_targets(grid: Array, target_cells: Array) -> Dictionary:
	var shape = Shape.of(size_of(grid))
	var cand = Logic.init_candidates(shape, grid)
	var tg = {}
	for t in target_cells:
		if grid[int(t)] == 0: tg[int(t)] = true
	if not tg.is_empty():
		var s = Logic.find_step(shape, grid, cand, 4, tg)
		if not s.is_empty() and s.technique != "contradiction":
			s["touches_target"] = true
			return s
	var s2 = Logic.find_step(shape, grid, cand, 4)
	if not s2.is_empty() and s2.technique != "contradiction":
		s2["touches_target"] = Logic._touches(s2, tg) and not tg.is_empty()
	return s2

## Runs the human-technique solve (tiers 1-4, same step order as grade()) step by step and
## records when each target cell is filled.
##   givens: flat Array (0 = empty), length size*size. size: 4, 6 or 9.
##   target_cells: Array of cell indices (row*size+col). Duplicates are ignored.
## Returns:
##   reachable (bool): every target is filled by logic alone (no guessing).
##   max_tier (int): hardest tier used up to and including the step that fills the last target
##     (0 if no step needed; if unreachable: hardest tier used before logic got stuck).
##   steps_to_last_target (int): 1-based index (in the full step log, eliminations included) of the
##     step that fills the last target; 0 if nothing to fill; -1 if unreachable.
##   order (Array): non-given targets in fill order: {cell, value, step, technique, tier}.
##   given_targets (Array): targets that are already givens (count as filled at step 0).
##   error (String): "" | "invalid_size" | "invalid_grid" (conflicting givens) | "invalid_cells" | "stuck".
##   invalid_cells (Array): offending target entries when error == "invalid_cells".
static func analyze_targets(givens: Array, size: int, target_cells: Array) -> Dictionary:
	var res = {"reachable": false, "max_tier": 0, "steps_to_last_target": -1, "order": [],
		"given_targets": [], "error": "", "invalid_cells": []}
	if not (size == 4 or size == 6 or size == 9) or givens.size() != size * size:
		res.error = "invalid_size"
		return res
	var shape = Shape.of(size)
	var g = []
	for v in givens:
		var iv = int(v)
		if iv < 0 or iv > size:
			res.error = "invalid_grid"
			return res
		g.append(iv)
	var targets = {}
	for t in target_cells:
		if (typeof(t) != TYPE_INT and typeof(t) != TYPE_FLOAT) or int(t) != t or int(t) < 0 or int(t) >= shape.cells:
			res.invalid_cells.append(t)
		else:
			targets[int(t)] = true
	if res.invalid_cells.size() > 0:
		res.error = "invalid_cells"
		return res
	if _has_conflict(shape, g):
		res.error = "invalid_grid"
		return res
	var pending = {}
	for t in targets:
		if g[t] != 0: res.given_targets.append(t)
		else: pending[t] = true
	res.given_targets.sort()
	if pending.is_empty():
		res.reachable = true
		res.steps_to_last_target = 0
		return res
	var cand = Logic.init_candidates(shape, g)
	var step_no = 0
	var tier = 0
	while true:
		var s = Logic.find_step(shape, g, cand, 4)
		if s.is_empty() or s.technique == "contradiction":
			res.error = "stuck"
			res.max_tier = tier
			return res
		Logic.apply_step(shape, g, cand, s)
		step_no += 1
		tier = maxi(tier, s.tier)
		if Logic.is_placement(s) and pending.has(s.cells[0]):
			pending.erase(s.cells[0])
			res.order.append({"cell": s.cells[0], "value": s.value, "step": step_no, "technique": s.technique, "tier": s.tier})
			if pending.is_empty():
				res.reachable = true
				res.max_tier = tier
				res.steps_to_last_target = step_no
				return res
	return res

static func _has_conflict(shape, g: Array) -> bool:
	for u in shape.units:
		var seen = 0
		for c in u:
			if g[c] == 0: continue
			var b = 1 << (g[c] - 1)
			if seen & b: return true
			seen |= b
	return false
