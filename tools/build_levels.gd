## Offline level builder (LEVEL_OBJECTIVES_SPEC v1 §5-6). Writes res://data/levels/harbour.json.
## godot --headless --path . -s tools/build_levels.gd
## Grids come from the existing packs (deterministic search, first match wins). Every level is
## validated with Sudoku.analyze_targets: reachable, tier within the table's range; target/tier/
## steps_to_t/par_time_s are computed here, never by hand.
extends SceneTree

const Sudoku = preload("res://sudoku/sudoku.gd")
const Obj = preload("res://game/objectives.gd")
const Rng = preload("res://sudoku/rng.gd")

# grid_id: pack
const GRID_PACKS = {"G01": "6x6_t1", "G02": "6x6_t1", "G03": "6x6_t1", "G04": "6x6_t1", "G05": "6x6_t2", "G06": "6x6_t2",
	"G07": "9x9_t2", "G08": "9x9_t2", "G09": "9x9_t2", "G10": "9x9_t2", "G11": "9x9_t3", "G12": "9x9_t3"}
# [level, grid, objective, params-spec, allowed tiers]
const TABLE = [
	[1, "G01", "digit", {"digit": 1}, [1]],
	[2, "G01", "line", {"units": [{"kind": "row", "index": 0}]}, [1]],
	[3, "G02", "full", {}, [1]],
	[4, "G03", "digit", {"digit": 3}, [1]],
	[5, "G03", "lantern", {"len": 6}, [1]],
	[6, "G04", "full", {}, [1]],
	[7, "G05", "line", {"units": [{"kind": "box", "index": 2}]}, [2]],
	[8, "G05", "tide", {"inner": "line", "choose": "2rows", "par_mult": 2.0}, [1, 2]],
	[9, "G06", "full", {}, [2]],
	[10, "G06", "tide", {"inner": "full", "par_mult": 2.0}, [2]],
	[11, "G07", "digit", {"digit": 5}, [2]],
	[12, "G07", "lantern", {"len": 8}, [2]],
	[13, "G08", "full", {}, [2]],
	[14, "G09", "line", {"choose": "row+col"}, [2]],
	[15, "G09", "tide", {"inner": "line", "choose": "box", "par_mult": 1.75}, [2]],
	[16, "G10", "full", {}, [2]],
	[17, "G11", "digit", {"digit": 7}, [3]],
	[18, "G11", "lantern", {"len": 10}, [3]],
	[19, "G12", "line", {"units": [{"kind": "col", "index": 4}]}, [3]],
	[20, "G12", "full", {}, [3]],
]

var packs = {}

func _pack(name: String) -> Array:
	if not packs.has(name):
		packs[name] = JSON.parse_string(FileAccess.get_file_as_string("res://data/packs/%s.json" % name)).puzzles
	return packs[name]

func _ints(a):
	var o = []
	for x in a: o.append(int(x))
	return o

## Candidate concrete params for a level spec on a grid (deterministic order).
func _options(n: int, givens: Array, spec: Dictionary, objective: String, seed_value: int) -> Array:
	var out = []
	var choose = str(spec.get("choose", ""))
	var base = spec.duplicate()
	base.erase("choose"); base.erase("len")
	if objective == "lantern":
		var rng = Rng.new(seed_value)
		var L = int(spec.len)
		for attempt in 400:
			var r = rng.below(n); var c = rng.below(n)
			var path = [[r, c]]
			var seen = {r * n + c: true}
			var ok = true
			while path.size() < L:
				var dirs = [[0, 1], [1, 0], [0, -1], [-1, 0]]
				rng.shuffle(dirs)
				var moved = false
				for d in dirs:
					var nr = path.back()[0] + d[0]; var nc = path.back()[1] + d[1]
					if nr >= 0 and nc >= 0 and nr < n and nc < n and not seen.has(nr * n + nc):
						path.append([nr, nc]); seen[nr * n + nc] = true; moved = true; break
				if not moved: ok = false; break
			if ok and Obj.lantern_valid(n, path, givens):
				var p = base.duplicate(); p["path"] = path; out.append(p)
		return out
	match choose:
		"2rows":
			for a in n:
				for b in range(a + 1, n):
					var p = base.duplicate(); p["units"] = [{"kind": "row", "index": a}, {"kind": "row", "index": b}]; out.append(p)
		"row+col":
			for a in n:
				for b in n:
					var p = base.duplicate(); p["units"] = [{"kind": "row", "index": a}, {"kind": "col", "index": b}]; out.append(p)
		"box":
			for a in n:
				var p = base.duplicate(); p["units"] = [{"kind": "box", "index": a}]; out.append(p)
		_:
			out.append(base)
	return out

func _eval(n: int, e: Dictionary, objective: String, params: Dictionary, tiers: Array):
	var g = _ints(e.givens); var sol = _ints(e.solution)
	var t = Obj.targets(n, g, sol, objective, params)
	var empty_t = t.filter(func(i): return g[i] == 0)
	if empty_t.size() < (4 if objective == "lantern" else 1): return null
	if objective != "lantern" and objective != "full" and str(params.get("inner", "")) != "full" and empty_t.size() < 2 and n > 4: return null
	var a = Sudoku.analyze_targets(g, n, t)
	if not a.reachable or not (a.max_tier in tiers): return null
	return {"t": t, "a": a}

func _init() -> void:
	var n_of = {"4x4": 4, "6x6": 6, "9x9": 9}
	var used = {}
	var grids = {}
	var levels = []
	var by_grid = {}
	for row in TABLE:
		if not by_grid.has(row[1]): by_grid[row[1]] = []
		by_grid[row[1]].append(row)
	var gids = by_grid.keys(); gids.sort()
	var chosen = {}   # level -> {params, eval}
	for gid in gids:
		var pack_name: String = GRID_PACKS[gid]
		var n: int = n_of[pack_name.substr(0, 3)]
		var pz = _pack(pack_name)
		var found = false
		for idx in pz.size():
			var key = pack_name + ":" + str(idx)
			if used.has(key): continue
			var e = pz[idx]
			var picks = {}
			var all_ok = true
			for row in by_grid[gid]:
				var objective: String = row[2]
				var hit = null
				for p in _options(n, _ints(e.givens), row[3], objective, row[0] * 1000 + idx):
					var r = _eval(n, e, objective, p, row[4])
					if r != null:
						hit = {"params": p, "r": r}
						break
				if hit == null: all_ok = false; break
				picks[row[0]] = hit
			if all_ok:
				used[key] = true
				grids[gid] = {"pack": pack_name, "index": idx, "id": e.id, "size": n}
				for k in picks: chosen[k] = picks[k]
				found = true
				break
		if not found:
			push_error("no grid found for " + gid)
			quit(1)
			return
	for row in TABLE:
		var gid: String = row[1]
		var n: int = grids[gid].size
		var c = chosen[row[0]]
		var a = c.r.a
		var params: Dictionary = c.params
		var lvl = {"level": row[0], "grid_id": gid, "size": n, "objective": row[2], "params": params,
			"target": c.r.t.map(func(i): return [i / n, i % n]), "tier": a.max_tier, "steps_to_t": a.steps_to_last_target,
			"par_time_s": Obj.par_time_s(n, a.steps_to_last_target, float(params.par_mult)) if row[2] == "tide" else null}
		levels.append(lvl)
	var f = FileAccess.open("res://data/levels/harbour.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"format": 1, "area": "harbour", "spec": "LEVEL_OBJECTIVES_SPEC v1.3", "grids": grids, "levels": levels}, "  "))
	f.close()
	for l in levels:
		print("L%02d %s %dx%d %-8s tier %d steps_to_t %3d par %s T=%d %s" % [l.level, l.grid_id, l.size, l.size, l.objective, l.tier, l.steps_to_t, str(l.par_time_s), l.target.size(), JSON.stringify(l.params)])
	print("wrote 20 levels to data/levels/harbour.json")
	quit(0)
