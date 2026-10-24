## Human-style technique engine. Pure logic: plain Arrays of ints, no scene/tree types.
## A board is a flat Array of ints (0 = empty), length size*size. Candidates are bitmasks (bit d-1 = digit d).
extends RefCounted

const Shape = preload("res://sudoku/shape.gd")

const TIERS = {
	"naked_single": 1,
	"hidden_single": 2,
	"naked_pair": 3, "hidden_pair": 3, "pointing": 3,
	"box_line_reduction": 4, "naked_triple": 4, "hidden_triple": 4, "x_wing": 4,
}
const NAMES = {
	"naked_single": "Naked single", "hidden_single": "Hidden single",
	"naked_pair": "Naked pair", "hidden_pair": "Hidden pair", "pointing": "Pointing",
	"box_line_reduction": "Box-line reduction", "naked_triple": "Naked triple",
	"hidden_triple": "Hidden triple", "x_wing": "X-Wing",
}

static func unit_label(shape, ui: int) -> String:
	if ui < shape.size: return "row %d" % (ui + 1)
	if ui < 2 * shape.size: return "column %d" % (ui - shape.size + 1)
	return "box %d" % (ui - 2 * shape.size + 1)

static func unit_kind(shape, ui: int) -> String:
	if ui < shape.size: return "row"
	if ui < 2 * shape.size: return "column"
	return "box"

## Candidate masks computed from placed digits only.
static func init_candidates(shape, g: Array) -> Array:
	var cand = []
	cand.resize(shape.cells)
	for i in shape.cells:
		if g[i] != 0:
			cand[i] = 0
			continue
		var m: int = shape.full_mask
		for p in shape.peers[i]:
			if g[p] != 0: m &= ~(1 << (g[p] - 1))
		cand[i] = m
	return cand

static func _mk(tech: String, cells: Array, value: int, elims: Array, ui: int, text: String) -> Dictionary:
	return {"technique": tech, "tier": TIERS[tech], "cells": cells, "value": value,
		"eliminations": elims, "unit": ui, "explanation": NAMES[tech] + ": " + text}

## Returns the easiest available step with tier <= max_tier, {} if stuck,
## or {"technique":"contradiction"} if the board is broken.
## tg: optional target-cell set {cell: true}; when non-empty only steps touching it are returned.
## skip: optional cell set {cell: true}; singles (placements) into these cells are not returned
## (used by the hint engine for cells the player was already taught but hasn't filled yet).
static func find_step(shape, g: Array, cand: Array, max_tier: int = 4, tg: Dictionary = {}, skip: Dictionary = {}) -> Dictionary:
	var n: int = shape.size
	# Tier 1: naked single
	for i in shape.cells:
		if g[i] == 0:
			if cand[i] == 0: return {"technique": "contradiction", "cells": [i]}
			if Shape.popcount(cand[i]) == 1 and not skip.has(i):
				var d = Shape.first_digit(cand[i])
				var _st = _mk("naked_single", [i], d, [], -1, "%d is the only digit that fits this cell." % d)
				if _touches(_st, tg): return _st
	if max_tier < 2: return {}
	# Tier 2: hidden single (boxes first, as players scan boxes)
	var order = []
	for k in n: order.append(2 * n + k)
	for k in 2 * n: order.append(k)
	for ui in order:
		var u: Array = shape.units[ui]
		var placed = 0
		for c in u:
			if g[c] != 0: placed |= 1 << (g[c] - 1)
		for d in range(1, n + 1):
			var b = 1 << (d - 1)
			if placed & b: continue
			var pos = -1
			var cnt = 0
			for c in u:
				if cand[c] & b:
					cnt += 1
					pos = c
			if cnt == 0: return {"technique": "contradiction", "cells": u.duplicate()}
			if cnt == 1 and not skip.has(pos):
				var _st = _mk("hidden_single", [pos], d, [], ui, "%d can only go here in this %s." % [d, unit_kind(shape, ui)])
				if _touches(_st, tg): return _st
	if max_tier < 3: return {}
	var s: Dictionary
	s = _naked_subset(shape, g, cand, 2, tg)
	if s: return s
	s = _hidden_subset(shape, g, cand, 2, tg)
	if s: return s
	s = _pointing(shape, g, cand, tg)
	if s: return s
	if max_tier < 4: return {}
	s = _box_line(shape, g, cand, tg)
	if s: return s
	s = _naked_subset(shape, g, cand, 3, tg)
	if s: return s
	s = _hidden_subset(shape, g, cand, 3, tg)
	if s: return s
	s = _x_wing(shape, g, cand, tg)
	if s: return s
	return {}

static func _combos(items: Array, k: int) -> Array:
	var out = []
	var m = items.size()
	if k == 2:
		for a in m:
			for b in range(a + 1, m): out.append([items[a], items[b]])
	elif k == 3:
		for a in m:
			for b in range(a + 1, m):
				for c in range(b + 1, m): out.append([items[a], items[b], items[c]])
	return out

static func _naked_subset(shape, g: Array, cand: Array, k: int, tg: Dictionary = {}) -> Dictionary:
	var tech = "naked_pair" if k == 2 else "naked_triple"
	for ui in shape.units.size():
		var u: Array = shape.units[ui]
		var pool = []
		for c in u:
			if g[c] == 0:
				var pc = Shape.popcount(cand[c])
				if pc >= 2 and pc <= k: pool.append(c)
		for combo in _combos(pool, k):
			var un = 0
			for c in combo: un |= cand[c]
			if Shape.popcount(un) != k: continue
			var el = []
			for c in u:
				if g[c] == 0 and not combo.has(c) and (cand[c] & un):
					for d in Shape.digits(cand[c] & un): el.append([c, d])
			if el.size() > 0:
				var _st = _mk(tech, combo, 0, el, ui, "digits %s are locked into these cells, so remove them elsewhere in this %s." % [_dl(Shape.digits(un)), unit_kind(shape, ui)])
				if _touches(_st, tg): return _st
	return {}

static func _hidden_subset(shape, g: Array, cand: Array, k: int, tg: Dictionary = {}) -> Dictionary:
	var tech = "hidden_pair" if k == 2 else "hidden_triple"
	for ui in shape.units.size():
		var u: Array = shape.units[ui]
		var pos = {}
		var ds = []
		for d in range(1, shape.size + 1):
			var b = 1 << (d - 1)
			var p = []
			var placed = false
			for c in u:
				if g[c] == d: placed = true
				if cand[c] & b: p.append(c)
			if placed: continue
			if p.size() >= 2 and p.size() <= k:
				pos[d] = p
				ds.append(d)
		for combo in _combos(ds, k):
			var cells = {}
			var dm = 0
			for d in combo:
				dm |= 1 << (d - 1)
				for c in pos[d]: cells[c] = true
			if cells.size() != k: continue
			var el = []
			for c in cells.keys():
				for d in Shape.digits(cand[c] & ~dm): el.append([c, d])
			if el.size() > 0:
				var cl = cells.keys()
				cl.sort()
				var _st = _mk(tech, cl, 0, el, ui, "digits %s can only go in these cells of this %s, so other candidates there are removed." % [_dl(combo), unit_kind(shape, ui)])
				if _touches(_st, tg): return _st
	return {}

static func _pointing(shape, g: Array, cand: Array, tg: Dictionary = {}) -> Dictionary:
	var n: int = shape.size
	for bi in n:
		var ui = 2 * n + bi
		var u: Array = shape.units[ui]
		for d in range(1, n + 1):
			var b = 1 << (d - 1)
			var p = []
			for c in u:
				if cand[c] & b: p.append(c)
			if p.size() < 2: continue
			for line in [0, 1]:  # 0 row, 1 col
				var key: int = shape.cell_units[p[0]][line]
				var same = true
				for c in p:
					if shape.cell_units[c][line] != key: same = false
				if not same: continue
				var el = []
				for c in shape.units[key]:
					if not u.has(c) and (cand[c] & b): el.append([c, d])
				if el.size() > 0:
					var _st = _mk("pointing", p, d, el, ui, "in this box %d must be in %s, so remove %d from the rest of that %s." % [d, unit_label(shape, key), d, unit_kind(shape, key)])
					if _touches(_st, tg): return _st
	return {}

static func _box_line(shape, g: Array, cand: Array, tg: Dictionary = {}) -> Dictionary:
	var n: int = shape.size
	for ui in 2 * n:
		var u: Array = shape.units[ui]
		for d in range(1, n + 1):
			var b = 1 << (d - 1)
			var p = []
			for c in u:
				if cand[c] & b: p.append(c)
			if p.size() < 2: continue
			var bx: int = shape.cell_units[p[0]][2]
			var same = true
			for c in p:
				if shape.cell_units[c][2] != bx: same = false
			if not same: continue
			var el = []
			for c in shape.units[bx]:
				if not u.has(c) and (cand[c] & b): el.append([c, d])
			if el.size() > 0:
				var _st = _mk("box_line_reduction", p, d, el, ui, "in this %s %d must be in %s, so remove %d from the rest of that box." % [unit_kind(shape, ui), d, unit_label(shape, bx), d])
				if _touches(_st, tg): return _st
	return {}

static func _x_wing(shape, g: Array, cand: Array, tg: Dictionary = {}) -> Dictionary:
	var n: int = shape.size
	for d in range(1, n + 1):
		var b = 1 << (d - 1)
		for base in [0, 1]:  # 0: base rows / cover cols ; 1: base cols / cover rows
			var lines = []
			for li in n:
				var ui: int = li + base * n
				var p = []
				for c in shape.units[ui]:
					if cand[c] & b: p.append(c)
				if p.size() == 2: lines.append(p)
			for i in lines.size():
				for j in range(i + 1, lines.size()):
					var a: Array = lines[i]
					var c2: Array = lines[j]
					var cover = 1 - base
					if shape.cell_units[a[0]][cover] != shape.cell_units[c2[0]][cover]: continue
					if shape.cell_units[a[1]][cover] != shape.cell_units[c2[1]][cover]: continue
					var corners = [a[0], a[1], c2[0], c2[1]]
					var el = []
					for k in 2:
						for c in shape.units[shape.cell_units[a[k]][cover]]:
							if not corners.has(c) and (cand[c] & b): el.append([c, d])
					if el.size() > 0:
						corners.sort()
						var _st = _mk("x_wing", corners, d, el, -1, "%d forms a rectangle in two %ss, so remove %d from the rest of those %ss." % [d, "row" if base == 0 else "column", d, "column" if base == 0 else "row"])
						if _touches(_st, tg): return _st
	return {}

static func _dl(ds: Array) -> String:
	var s = []
	for d in ds: s.append(str(d))
	return "/".join(s)

## Apply a step in place.
static func apply_step(shape, g: Array, cand: Array, s: Dictionary) -> void:
	if s.technique == "naked_single" or s.technique == "hidden_single":
		var c: int = s.cells[0]
		var d: int = s.value
		g[c] = d
		cand[c] = 0
		for p in shape.peers[c]: cand[p] &= ~(1 << (d - 1))
	else:
		for e in s.eliminations: cand[e[0]] &= ~(1 << (e[1] - 1))

static func is_placement(s: Dictionary) -> bool:
	return s.get("technique", "") == "naked_single" or s.get("technique", "") == "hidden_single"

## Solve with techniques up to max_tier. Returns {solved, tier, steps, grid}.
## tier = hardest technique used (0 if nothing to do).
static func run(shape, givens: Array, max_tier: int = 4, record: bool = true) -> Dictionary:
	var g = givens.duplicate()
	var cand = init_candidates(shape, g)
	var steps = []
	var tier = 0
	var empty = 0
	for v in g:
		if v == 0: empty += 1
	while empty > 0:
		var s = find_step(shape, g, cand, max_tier)
		if s.is_empty() or s.technique == "contradiction":
			return {"solved": false, "tier": 5, "steps": steps, "grid": g}
		apply_step(shape, g, cand, s)
		if is_placement(s): empty -= 1
		tier = maxi(tier, s.tier)
		if record: steps.append(s)
	return {"solved": true, "tier": tier, "steps": steps, "grid": g}

## True if tg is empty, or the step places into a target cell, or eliminates from one.
static func _touches(st: Dictionary, tg: Dictionary) -> bool:
	if tg.is_empty(): return true
	if is_placement(st): return tg.has(st.cells[0])
	for e in st.eliminations:
		if tg.has(e[0]): return true
	return false
