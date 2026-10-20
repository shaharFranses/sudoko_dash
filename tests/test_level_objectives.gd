extends GutTest
## LEVEL_OBJECTIVES_SPEC v1.2: content, rules, timer, save, H7 debug hook.

const Profile = preload("res://game/profile.gd")
const Obj = preload("res://game/objectives.gd")
const Levels = preload("res://game/levels.gd")
const Sudoku = preload("res://sudoku/sudoku.gd")
var main

func before_each():
	Store.clear()
	Ads.call_log.clear()
	Ads.set_mode("mock_available")
	Sfx.set_reason("hidden", false); Sfx.set_reason("blur", false)
	main = load("res://scenes/main.tscn").instantiate()
	add_child_autofree(main)
	await wait_frames(2)

func after_each():
	Sfx.set_reason("hidden", false); Sfx.set_reason("blur", false)

func _ints(a):
	var o = []
	for x in a: o.append(int(x))
	return o

func _grid(lv):
	var gr = Levels.grid(lv.grid_id)
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/packs/%s.json" % gr.pack)).puzzles[int(gr.index)]

# ---------------- content ----------------
func test_mix_and_ordering_rules():
	assert_eq(Levels.count(), 20)
	var c = {}
	for i in 20:
		var o = str(Levels.level(i).objective)
		c[o] = c.get(o, 0) + 1
	assert_eq(c, {"full": 6, "digit": 4, "line": 4, "lantern": 3, "tide": 3})
	for i in 19:
		assert_false(Obj.is_timed(Levels.level(i)) and Obj.is_timed(Levels.level(i + 1)), "no 2 timed in a row at L%d" % (i + 1))
	for s in 17:
		var any_full = false
		for k in 4:
			var lv = Levels.level(s + k)
			if lv.objective == "full" or str(lv.params.get("inner", "")) == "full": any_full = true
		assert_true(any_full, "full solve within L%d-L%d" % [s + 1, s + 4])

func test_harbour_json_matches_analyze_targets():
	for i in 20:
		var lv = Levels.level(i)
		var e = _grid(lv)
		var n = int(lv.size)
		var t = Obj.targets(n, _ints(e.givens), _ints(e.solution), str(lv.objective), lv.params)
		assert_eq(t, Levels.target_cells(lv), "L%d target" % (i + 1))
		var a = Sudoku.analyze_targets(_ints(e.givens), n, t)
		assert_true(a.reachable)
		assert_eq(a.max_tier, int(lv.tier))
		assert_eq(a.steps_to_last_target, int(lv.steps_to_t))
		if Obj.is_timed(lv):
			assert_eq(int(lv.par_time_s), Obj.par_time_s(n, a.steps_to_last_target, float(lv.params.par_mult)))

func test_lantern_targets_are_empty_path_cells_only():
	for i in 20:
		var lv = Levels.level(i)
		if lv.objective != "lantern": continue
		var e = _grid(lv)
		var g = _ints(e.givens)
		var n = int(lv.size)
		assert_true(Obj.lantern_valid(n, lv.params.path, g))
		var empty = []
		for rc in lv.params.path:
			if g[int(rc[0]) * n + int(rc[1])] == 0: empty.append(int(rc[0]) * n + int(rc[1]))
		empty.sort()
		assert_eq(Levels.target_cells(lv), empty)
		assert_gte(empty.size(), 4)

# ---------------- stars / par ----------------
func test_par_boundaries_ms():
	var lv = {"objective": "tide", "par_time_s": 268, "params": {}}
	assert_eq(Obj.stars(lv, false, 0, 201000), 3)          # floor(0.75*268000)=201000
	assert_eq(Obj.stars(lv, false, 0, 201001), 2)
	assert_eq(Obj.stars(lv, false, 0, 268000), 2)           # <= par
	assert_eq(Obj.stars(lv, false, 0, 268001), 1)
	assert_eq(Obj.stars(lv, true, 3, 1000), 3, "Tide: speed only")
	var odd = {"objective": "tide", "par_time_s": 326, "params": {}}
	assert_eq(Obj.stars(odd, false, 0, 244500), 3)
	assert_eq(Obj.stars(odd, false, 0, 244501), 2)

func _start(objective: String) -> Dictionary:
	for i in 20:
		if Levels.level(i).objective == objective:
			main.start_level(i)
			return Levels.level(i)
	return {}

func test_reveal_adds_15s_and_last_target_reveal_completes():
	var lv = _start("tide")
	var t = main.targets.filter(func(c): return main.board.cells[c] == 0)
	for k in t.size() - 1:
		main._on_cell(t[k]); main._on_digit(main.board.solution[t[k]])
	main.elapsed_ms = 1000
	main.grid_view.selected = t.back()
	main.profile.tokens = 1
	main._open_hint_panel(); main._pay_hint("reveal", "token")
	assert_eq(main.screen_name, "results")
	assert_eq(main.profile.path_stars.back() if main.profile.path_stars.size() > 0 else -1, -1, "level not at path_next -> no stars")
	assert_eq(main.profile.level_best[Levels.data().levels.find(lv)], 3, "16000 ms well under par")

func test_reveal_penalty_counts_against_par():
	var lv = _start("tide")
	main.elapsed_ms = int(lv.par_time_s) * 1000 - 10000
	var c = main.targets.filter(func(x): return main.board.cells[x] == 0)[0]
	main.grid_view.selected = c
	main.profile.tokens = 1
	main._open_hint_panel(); main._pay_hint("reveal", "token")
	assert_eq(main.elapsed_ms, int(lv.par_time_s) * 1000 + 5000)

# ---------------- timer ----------------
func test_timer_runs_only_when_live():
	_start("tide")
	assert_true(main.timer_running())
	var e0 = main.elapsed_ms
	await wait_frames(10)
	assert_gt(main.elapsed_ms, e0)
	main._open_hint_panel()
	assert_false(main.timer_running(), "panel pauses")
	var e1 = main.elapsed_ms
	await wait_frames(10)
	assert_eq(main.elapsed_ms, e1)
	main._close_overlay()
	Sfx.set_reason("blur", true)
	assert_false(main.timer_running(), "blur pauses")
	Sfx.set_reason("blur", false)
	Sfx.set_reason("hidden", true)
	assert_false(main.timer_running(), "hidden pauses")
	Sfx.set_reason("hidden", false)
	Ads.set_context("ad")
	assert_false(main.timer_running(), "ad pauses")
	Ads.set_context("grid")
	assert_true(main.timer_running())

func test_timer_paused_during_rewarded_ad_from_panel():
	_start("tide")
	main.board.mistakes = main.board.max_mistakes
	main._open_second_chance()
	var e = main.elapsed_ms
	main._second_chance("ad")   # mock rewarded ad in flight
	assert_false(main.timer_running())
	await wait_frames(10)
	assert_eq(main.elapsed_ms, e)

func test_non_timed_level_has_no_timer():
	_start("digit")
	assert_false(main.timer_running())
	assert_false(main.tide_bar.visible)

func test_retry_resets_continue_keeps():
	_start("tide")
	main.elapsed_ms = 50000
	main.board.mistakes = main.board.max_mistakes
	main.profile.coins = 999
	main._open_second_chance(); main._second_chance("coins")
	assert_eq(main.elapsed_ms, 50000)
	assert_eq(main.continues, 1)
	main._retry()
	assert_eq(main.elapsed_ms, 0)
	assert_eq(main.continues, 0)
	assert_eq(main.board.reveals, 0)

# ---------------- save ----------------
func test_save_and_resume_restores_level_and_elapsed():
	var lv = _start("tide")
	main.elapsed_ms = 123456
	main.continues = 1
	main.save()
	var d = Store.load_data()
	assert_eq(int(d.current_grid.level.elapsed_ms), 123456)
	var m2 = load("res://scenes/main.tscn").instantiate()
	add_child_autofree(m2)
	await wait_frames(2)
	m2.resume_grid()
	assert_eq(m2.level, lv)
	assert_almost_eq(m2.elapsed_ms, 123456, 1000)
	assert_eq(m2.continues, 1)
	assert_eq(m2.targets, main.targets)

func test_input_saves_and_periodic_save():
	_start("tide")
	var c = main.targets.filter(func(x): return main.board.cells[x] == 0)[0]
	main._on_cell(c); main._on_digit(main.board.solution[c])
	assert_eq(int(Store.load_data().current_grid.board.cells[c]), main.board.solution[c], "saved on input")
	main.elapsed_ms = 7777
	main._process(5.1)
	assert_gte(int(Store.load_data().current_grid.level.elapsed_ms), 7777, "saved within 5 s")

func test_migration_from_15_grid_path():
	var p = Profile.new()
	p.from_dict({"path_next": 9, "path_stars": [2,2,2,2,2,2,2,2,2], "stars": 5, "stars_earned": 18, "coins": 40,
		"current_grid": {"meta": {"mode": "path", "path_index": 9}, "board": {}}})
	assert_eq(p.path_next, 12)
	assert_eq(p.stars, 5)
	assert_eq(p.stars_earned, 18)
	assert_eq(p.current_grid, {})
	assert_true(p.migrated_from_v1)
	var d = p.to_dict()
	var q = Profile.new(); q.from_dict(d)
	assert_eq(q.path_next, 12, "no re-migration")

# ---------------- teach / H7 ----------------
func test_teach_prefers_targets():
	_start("digit")
	main.profile.tokens = 1
	main._open_hint_panel(); main._pay_hint("teach", "token")
	var tg = main.targets
	var hit = false
	for c in main.grid_view.teach_cells: if c in tg: hit = true
	for e in main.grid_view.teach_elims: if e[0] in tg: hit = true
	assert_true(hit)

func test_h7_state_dump_and_timer_readout():
	var lv = _start("tide")
	main.elapsed_ms = 4321
	var s = main.step_dump()
	for k in ["level", "objective", "target", "elapsed_ms", "reveals", "continues"]:
		assert_true(s.has(k), k)
	assert_eq(s.objective, "tide")
	assert_eq(s.elapsed_ms, 4321)
	main._refresh_timer()
	var lbl = main.find_child("TimerDebug", true, false)
	assert_not_null(lbl, "debug timer readout")
	assert_string_contains(lbl.text, "elapsed_ms=4321")

func test_blur_signal_from_page_events():
	var S = load("res://autoload/sfx.gd")
	assert_true(S.blur_from_page("n"))
	assert_false(S.blur_from_page("y"))
	assert_false(S.blur_from_page("u"), "no page script -> treated as focused (headless QA)")
	_start("tide")
	Sfx.set_reason("blur", S.blur_from_page("n"))
	assert_false(main.timer_running())
	Sfx.set_reason("blur", S.blur_from_page("y"))
	assert_true(main.timer_running())

# ---------------- section 8 criteria ----------------
func test_c13_path_matches_spec_table():
	var md = FileAccess.get_file_as_string("res://LEVEL_OBJECTIVES_SPEC.md") if FileAccess.file_exists("res://LEVEL_OBJECTIVES_SPEC.md") else ""
	if md == "": pending("spec not in res://"); return
	var names = {"Digit Hunt": "digit", "Fill the Line": "line", "Full Solve": "full", "Full Solve (finale)": "full", "Lantern Path": "lantern", "Beat the Tide": "tide"}
	var rows = 0
	for line in md.split("\n"):
		var c = Array(line.split("|")).map(func(x): return x.strip_edges())
		if c.size() < 8 or not c[1].is_valid_int(): continue
		var lv = Levels.level(int(c[1]) - 1)
		rows += 1
		assert_eq(lv.grid_id, c[2]); assert_eq("%dx%d" % [lv.size, lv.size], c[3]); assert_eq(lv.objective, names[c[4]], "L" + c[1])
		var tiers = Array(c[6].split("-")).map(func(x): return int(x))
		assert_between(int(lv.tier), tiers[0], tiers.back(), "L%s tier" % c[1])
		var p: String = c[5]
		if p.begins_with("digit"): assert_eq(int(lv.params.digit), int(p.split(" ")[1]))
		if p.ends_with("cells"): assert_eq(lv.params.path.size(), int(p.split(" ")[0]))
		if p.contains("par "): assert_almost_eq(float(lv.params.par_mult), float(p.split("par ")[1]), 0.001)
		if lv.objective == "line":
			var u = lv.params.units
			if p == "row + col": assert_eq([u[0].kind, u[1].kind], ["row", "col"])
			elif p.contains(" "): assert_eq([u[0].kind, int(u[0].index)], [p.split(" ")[0], int(p.split(" ")[1])])
	assert_eq(rows, 20)
	assert_eq(Profile.TASKS.map(func(t): return t.cost), [3, 4, 4, 4, 5])

func test_c3_completes_at_last_target_not_before():
	_start("digit")
	var t = main.targets.filter(func(c): return main.board.cells[c] == 0)
	var nont = main.board.cells.find(0)
	while nont in main.targets: nont = main.board.cells.find(0, nont + 1)
	for k in t.size():
		assert_eq(main.screen_name, "grid", "not complete before target %d" % k)
		main._on_cell(t[k]); main._on_digit(main.board.solution[t[k]])
	assert_eq(main.screen_name, "results")

func test_c4_wrong_outside_t_is_mistake_third_opens_second_chance():
	main.start_level(6)   # L7 6x6 Fill the Line (4x4 has no mistake limit)
	var c = 0
	while main.board.cells[c] != 0 or c in main.targets: c += 1
	var wrong = []
	for d in range(1, main.board.size + 1):
		if d != main.board.solution[c]: wrong.append(d)
	for k in 3:
		main._on_cell(c); main._on_digit(wrong[k])
	assert_eq(main.board.mistakes, 3)
	assert_eq(main.overlay.name, "SecondChancePanel")

func test_c5_non_timed_star_table():
	var lv = {"objective": "digit", "params": {}}
	assert_eq(Obj.stars(lv, false, 0, 0), 3)
	assert_eq(Obj.stars(lv, true, 0, 0), 2)
	assert_eq(Obj.stars(lv, false, 2, 0), 2)
	assert_eq(Obj.stars(lv, true, 5, 0), 1)

func test_c6_tide_reaching_zero_does_not_end_level():
	var lv = _start("tide")
	main.elapsed_ms = int(lv.par_time_s) * 1000 + 60000
	main._process(0.1)
	assert_eq(main.screen_name, "grid")
	assert_eq(main.tide_bar.value, 0.0)

func test_c9_no_ads_while_level_open():
	Ads.call_log.clear()
	main.policy.session_start_ms = -10 * 60 * 1000
	for i in 20:
		main.start_level(i)
		var b = main.board
		for c in b.cells.size():
			if main.board == null: break
			if b.cells[c] == 0: main._on_cell(c); main._on_digit(b.solution[c])
		await wait_frames(1)
	for e in Ads.call_log:
		assert_false(e.get("grid_open", false) and e.kind == "midgame", str(e))

func test_grid_title_shows_level_of_20():
	main.start_level(11)
	assert_not_null(main.find_child("*", true, false))
	var found = false
	for l in main.find_children("*", "Label", true, false):
		if l.text == "Level 12/20": found = true
	assert_true(found)
