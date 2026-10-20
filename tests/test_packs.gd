extends GutTest

const Sudoku = preload("res://sudoku/sudoku.gd")

func _ints(a):
	var o = []
	for x in a:
		o.append(int(x))
	return o

func _load(name: String) -> Dictionary:
	var t = FileAccess.get_file_as_string("res://data/packs/%s.json" % name)
	assert_ne(t, "", name + " exists")
	return JSON.parse_string(t) if t != "" else {"puzzles": []}

func _verify(name: String, size: int, tier: int, expected: int):
	var p = _load(name)
	assert_eq(p.puzzles.size(), expected, name + " count")
	var bad = []
	var ids = {}
	for e in p.puzzles:
		var g = _ints(e.givens)
		var r = Sudoku.solve(g)
		var gr = Sudoku.grade(g)
		if r.count != 1 or r.solution != _ints(e.solution) or gr.tier != tier or int(e.tier) != tier:
			bad.append(e.id)
		if e.steps.size() != gr.steps.size(): bad.append(e.id + ":steps")
		ids[e.id] = true
	assert_eq(ids.size(), p.puzzles.size(), name + " ids distinct")
	assert_eq(bad, [], name + " all unique + graded")

func test_pack_9x9_t1(): _verify("9x9_t1", 9, 1, 300)
func test_pack_9x9_t2(): _verify("9x9_t2", 9, 2, 300)
func test_pack_9x9_t3(): _verify("9x9_t3", 9, 3, 300)
func test_pack_9x9_t4(): _verify("9x9_t4", 9, 4, 300)
func test_fallback_pack_4x4(): _verify("4x4_t1", 4, 1, 200)
func test_fallback_pack_6x6_t1(): _verify("6x6_t1", 6, 1, 100)
func test_fallback_pack_6x6_t2(): _verify("6x6_t2", 6, 2, 100)

func test_9x9_packs_givens_distinct():
	var seen = {}
	var n = 0
	for t in [1, 2, 3, 4]:
		for e in _load("9x9_t%d" % t).puzzles:
			seen[str(e.givens)] = true
			n += 1
	assert_eq(seen.size(), n)

func _p95(a: Array) -> float:
	a.sort(); return a[int(ceil(a.size() * 0.95)) - 1]

func test_step_9x9_le_20ms_on_diverged_boards():
	# AC14 + timing: board = givens + a random subset of correct digits (diverged from stored order)
	var rng = RandomNumberGenerator.new(); rng.seed = 7
	var ts = []
	var invalid = 0
	for t in [1, 2, 3, 4]:
		var pz = _load("9x9_t%d" % t).puzzles
		for k in 15:
			var e = pz[k * 7 % pz.size()]
			var g = _ints(e.givens); var sol = _ints(e.solution)
			var empties = []
			for i in 81:
				if g[i] == 0: empties.append(i)
			empties.shuffle()
			for j in int(empties.size() * rng.randf_range(0.0, 0.7)): g[empties[j]] = sol[empties[j]]
			var t0 = Time.get_ticks_usec()
			var s = Sudoku.step(g)
			ts.append((Time.get_ticks_usec() - t0) / 1000.0)
			if s.is_empty():
				# beyond tier-4 from this exact candidate state is impossible for a solvable subset only if stuck; count as invalid
				invalid += 1; continue
			if s.technique == "naked_single" or s.technique == "hidden_single":
				if g[s.cells[0]] != 0 or s.value != sol[s.cells[0]]: invalid += 1
			else:
				for el in s.eliminations:
					if el[1] == sol[el[0]]: invalid += 1
	var p = _p95(ts)
	gut.p("9x9 step() p95 = %.2f ms, max = %.2f ms (native headless)" % [p, ts.max()])
	assert_eq(invalid, 0)
	assert_lt(p, 20.0)
