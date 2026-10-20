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
