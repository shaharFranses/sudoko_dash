extends GutTest

const Sudoku = preload("res://sudoku/sudoku.gd")
const Shape = preload("res://sudoku/shape.gd")
const Logic = preload("res://sudoku/logic.gd")
const Rng = preload("res://sudoku/rng.gd")

# A well-known unique puzzle (Wikipedia example).
const WIKI = [5,3,0,0,7,0,0,0,0, 6,0,0,1,9,5,0,0,0, 0,9,8,0,0,0,0,6,0, 8,0,0,0,6,0,0,0,3, 4,0,0,8,0,3,0,0,1, 7,0,0,0,2,0,0,0,6, 0,6,0,0,0,0,2,8,0, 0,0,0,4,1,9,0,0,5, 0,0,0,0,8,0,0,7,9]

func _empty(n): var a = []; a.resize(n * n); a.fill(0); return a

func _is_valid_full(n, g) -> bool:
	var sh = Shape.of(n)
	for u in sh.units:
		var seen = {}
		for c in u:
			if g[c] < 1 or g[c] > n or seen.has(g[c]): return false
			seen[g[c]] = true
	return true

func test_rng_deterministic():
	var a = Rng.new(42); var b = Rng.new(42)
	for i in 50: assert_eq(a.next_u32(), b.next_u32())

func test_rng_seeds_differ():
	assert_ne(Rng.new(1).next_u32(), Rng.new(2).next_u32())

func test_shape_9x9():
	var s = Shape.of(9)
	assert_eq(s.units.size(), 27)
	assert_eq(s.peers[0].size(), 20)

func test_shape_6x6_boxes_are_2x3():
	var s = Shape.of(6)
	assert_eq(s.units[12], [0, 1, 2, 6, 7, 8])
	assert_eq(s.peers[0].size(), 12)

func test_shape_4x4():
	var s = Shape.of(4)
	assert_eq(s.units[8], [0, 1, 4, 5])
	assert_eq(s.peers[0].size(), 7)

func test_solve_wiki_unique():
	var r = Sudoku.solve(WIKI)
	assert_eq(r.count, 1)
	assert_true(_is_valid_full(9, r.solution))

func test_solve_empty_capped_at_2():
	assert_eq(Sudoku.solve(_empty(9)).count, 2)
	assert_eq(Sudoku.solve(_empty(6)).count, 2)
	assert_eq(Sudoku.solve(_empty(4)).count, 2)

func test_solve_conflicting_givens_zero():
	var g = WIKI.duplicate(); g[2] = 5
	assert_eq(Sudoku.solve(g).count, 0)

func test_solve_full_grid_count_one():
	var full = Sudoku.solve(WIKI).solution
	assert_eq(Sudoku.solve(full).count, 1)

func test_grade_wiki_tier1():
	var gr = Sudoku.grade(WIKI)
	assert_true(gr.solved)
	assert_eq(gr.tier, 1)
	assert_gt(gr.steps.size(), 0)

func test_step_naked_single():
	var full = Sudoku.solve(WIKI).solution
	var g = full.duplicate(); g[40] = 0
	var s = Sudoku.step(g)
	assert_eq(s.technique, "naked_single")
	assert_eq(s.cells, [40]); assert_eq(s.value, full[40])

func test_step_hidden_single_needs_tier2():
	# 4x4: digit 1 placed in rows 0,2 and cols forcing a hidden single but no naked single
	var found = false
	for sd in 200:
		var p = Sudoku.generate(6, 2, sd)
		if p.tier == 2:
			var r = Logic.run(Shape.of(6), p.givens, 1, false)
			assert_false(r.solved, "tier-2 puzzle should not be solvable by naked singles only")
			found = true
			break
	assert_true(found)

func test_step_contradiction():
	var g = _empty(4)
	g[0] = 1; g[1] = 2; g[4] = 3; g[8] = 4  # cell 5? fine; craft: row0 has 1,2 ; col0 3,4 -> cell 0 fixed; force cell 12 empty cand
	g = [1,2,0,0, 3,4,0,0, 0,0,0,0, 0,0,0,0]
	g[2] = 3; g[3] = 0; g[6] = 0
	# cell 3 in row0 has {4}, box1 contains 3; put 4 in col3 => contradiction
	g[15] = 4
	var s = Sudoku.step(g)
	assert_eq(s.technique, "contradiction")

func test_generate_deterministic():
	assert_eq(Sudoku.generate(6, 2, 77), Sudoku.generate(6, 2, 77))
	assert_eq(Sudoku.generate(4, 1, 5).givens, Sudoku.generate(4, 1, 5).givens)

func test_generate_different_seeds_differ():
	assert_ne(Sudoku.generate(6, 1, 1).givens, Sudoku.generate(6, 1, 2).givens)

func _check_seeded(n: int):
	var tiers = Sudoku.valid_tiers(n)
	var unique = 0; var tier_ok = 0; var sol_ok = 0
	for sd in 100:
		var t = tiers[sd % tiers.size()]
		var p = Sudoku.generate(n, t, sd)
		var r = Sudoku.solve(p.givens)
		if r.count == 1: unique += 1
		if r.solution == p.solution and _is_valid_full(n, p.solution): sol_ok += 1
		if Sudoku.grade(p.givens).tier == t: tier_ok += 1
	assert_eq(unique, 100, "%dx%d unique" % [n, n])
	assert_eq(sol_ok, 100, "%dx%d solution" % [n, n])
	assert_eq(tier_ok, 100, "%dx%d tier" % [n, n])

func test_100_seeded_4x4_unique_and_tiered():
	_check_seeded(4)

func test_100_seeded_6x6_unique_and_tiered():
	_check_seeded(6)

func _p95(a: Array) -> float:
	a.sort(); return a[int(ceil(a.size() * 0.95)) - 1]

func test_generation_budget_4x4_6x6_p95_le_30ms():
	for n in [4, 6]:
		var ts = []
		for sd in 40:
			var t0 = Time.get_ticks_usec()
			Sudoku.generate(n, 1, 500 + sd)
			ts.append((Time.get_ticks_usec() - t0) / 1000.0)
		var p = _p95(ts)
		gut.p("%dx%d tier-1 raw generate p95 = %.2f ms (native headless)" % [n, n, p])
		assert_lt(p, 30.0)

func test_steps_are_sound_on_vectors():
	# every placement equals the solution; every elimination removes a non-solution digit
	var v = _vectors()
	var bad = 0
	for e in v:
		var gr = Sudoku.grade(_ints(e.givens))
		for s in gr.steps:
			if Logic.is_placement(s):
				if s.value != int(e.solution[s.cells[0]]): bad += 1
			for el in s.eliminations:
				if el[1] == int(e.solution[el[0]]): bad += 1
	assert_eq(bad, 0)

func test_module_has_no_engine_node_dependencies():
	var bad = []
	for f in ["shape.gd", "logic.gd", "sudoku.gd", "rng.gd"]:
		var t = FileAccess.get_file_as_string("res://sudoku/" + f)
		for w in ["extends Node", "SceneTree", "get_tree", "Control", "Engine.", "OS.", "Input", "Time."]:
			if t.contains(w): bad.append(f + ":" + w)
		assert_true(t.contains("extends RefCounted"), f)
	assert_eq(bad, [])

func _ints(a):
	var o = []
	for x in a:
		o.append(int(x))
	return o

func _vectors() -> Array:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/test_vectors.json")).vectors

func test_vectors_file_present_and_sized():
	var v = _vectors()
	assert_gte(v.size(), 60)

func test_vectors_match_module():
	var fails = []
	for e in _vectors():
		var g = _ints(e.givens)
		var r = Sudoku.solve(g)
		var gr = Sudoku.grade(g)
		var techs = {}
		for s in gr.steps: techs[s.technique] = true
		var tk = techs.keys(); tk.sort()
		var st = Sudoku.step(g)
		var ok = r.count == 1 and int(e.solution_count) == 1 and r.solution == _ints(e.solution) \
			and gr.tier == int(e.tier) and tk == Array(e.techniques) \
			and st.technique == e.first_step.technique and st.value == int(e.first_step.value) \
			and st.cells == _ints(e.first_step.cells)
		var regen = Sudoku.generate(int(e.size), int(e.requested_tier), int(e.seed))
		if regen.givens != g: ok = false
		if not ok: fails.append("%dx%d seed %d" % [e.size, e.size, e.seed])
	assert_eq(fails, [])

func test_vectors_cover_all_tiers_9x9():
	var seen = {}
	for e in _vectors():
		if int(e.size) == 9: seen[int(e.tier)] = true
	assert_eq(seen.size(), 4)
