extends GutTest
## Hint (Teach / Reveal) regressions: "asking for another hint gives the same one" (Shahar, after af08eb1).
## Every PAID Teach must teach a step that is new relative to the hints already given on this attempt;
## when nothing new exists the previous hint is re-shown for free (never charged).

const Sudoku = preload("res://sudoku/sudoku.gd")
const Logic = preload("res://sudoku/logic.gd")
const Shape = preload("res://sudoku/shape.gd")
const Board = preload("res://game/board_state.gd")
const Levels = preload("res://game/levels.gd")
const Source = preload("res://game/puzzle_source.gd")
var main

func before_each():
	Store.clear()
	Ads.call_log.clear()
	Ads.set_mode("mock_available")
	Sfx.set_reason("hidden", false); Sfx.set_reason("blur", false)
	main = load("res://scenes/main.tscn").instantiate()
	add_child_autofree(main)
	await wait_frames(2)

func _pack(size: int, tier: int, index: int) -> Dictionary:
	return Source.new().from_pack(size, tier, index)

func _level_puzzle(lv: Dictionary) -> Dictionary:
	var gr = Levels.grid(lv.grid_id)
	var pk: String = gr.pack
	return _pack(int(gr.size), int(pk.substr(pk.length() - 1)), int(gr.index))

## Board state just before the first elimination step of the human solve (placements applied only).
func _state_before_first_elimination(p: Dictionary) -> Array:
	var shape = Shape.of(9)
	var g = p.givens.duplicate()
	var cand = Logic.init_candidates(shape, g)
	for k in 200:
		var s = Logic.find_step(shape, g, cand, 4)
		if s.is_empty() or not Logic.is_placement(s): return g
		Logic.apply_step(shape, g, cand, s)
	return g

func _key(s: Dictionary) -> String:
	if Logic.is_placement(s): return "P%d" % int(s.cells[0])
	return "E" + str(s.eliminations)

# ---------------- engine ----------------
func test_root_cause_stateless_step_repeats():
	# The old Teach called Sudoku.step(correct_board()), a pure function of the placed digits: an
	# unplaced single, and ANY elimination step (which never changes the digits), came back every time.
	var p = _pack(9, 4, 0)
	var g = _state_before_first_elimination(p)
	var s1 = Sudoku.step(g)
	assert_false(Logic.is_placement(s1), "state has an elimination step first")
	assert_eq(_key(Sudoku.step(g)), _key(s1), "old engine: identical step again")
	var s2 = Sudoku.next_hint(g, p.solution, [], [s1])
	assert_false(s2.is_empty())
	assert_ne(_key(s2), _key(s1), "new engine: a different step")

func test_consecutive_hints_without_acting_are_distinct_and_sound():
	for idx in [0, 1, 2]:
		for tier in [1, 2, 3, 4]:
			var p = _pack(9, tier, idx)
			var g = p.givens.duplicate()
			var taught = []
			var seen = {}
			for k in 12:
				var s = Sudoku.next_hint(g, p.solution, [], taught)
				if s.is_empty(): break
				assert_false(seen.has(_key(s)), "T%d #%d hint %d repeats %s" % [tier, idx, k, _key(s)])
				seen[_key(s)] = true
				if Logic.is_placement(s):
					assert_eq(s.value, p.solution[s.cells[0]], "taught digit is correct")
				else:
					assert_gt(s.eliminations.size(), 0)
					for e in s.eliminations: assert_ne(e[1], p.solution[e[0]], "never eliminates the true digit")
				taught.append(s)
			assert_gt(seen.size(), 1, "T%d #%d: more than one hint available" % [tier, idx])

func test_taught_eliminations_lead_to_a_placement():
	var p = _pack(9, 4, 0)
	var g = _state_before_first_elimination(p)
	var taught = []
	var placed = false
	for k in 40:
		var s = Sudoku.next_hint(g, p.solution, [], taught)
		if s.is_empty(): break
		taught.append(s)
		if Logic.is_placement(s):
			placed = true
			break
	assert_true(placed, "chained elimination hints eventually teach a placement (no loop)")

func test_no_new_step_returns_empty():
	var p = _pack(6, 1, 0)
	var g = p.solution.duplicate()
	g[5] = 0
	var s = Sudoku.next_hint(g, p.solution, [], [])
	assert_eq(s.cells, [5])
	assert_true(Sudoku.next_hint(g, p.solution, [], [s]).is_empty(), "only cell is already taught")

func test_digit_hunt_hints_place_the_hunted_digit_or_unlock_it():
	# Digit Hunt: a hint is a placement of the hunted digit whenever one is available by singles;
	# otherwise the easiest step anywhere. Never an elimination that merely marks a target cell.
	var n = 0
	var hunted = 0
	for i in Levels.count():
		var lv = Levels.level(i)
		if str(lv.params.get("inner", lv.objective)) != "digit": continue
		n += 1
		var p = _level_puzzle(lv)
		var tg = Levels.target_cells(lv)
		var digit = int(lv.params.digit)
		var shape = Shape.of(int(lv.size))
		var taught = []
		for k in 4:
			var s = Sudoku.next_hint(p.givens, p.solution, tg, taught, true)
			assert_false(s.is_empty(), "L%d hint %d exists" % [i + 1, k])
			# is a target single available on the player's board (+ taught eliminations, minus taught cells)?
			var cand = Logic.init_candidates(shape, p.givens)
			var skip = {}
			var tgd = {}
			for t in taught:
				if Logic.is_placement(t): skip[t.cells[0]] = true
				else:
					for e in t.eliminations: cand[e[0]] &= ~(1 << (e[1] - 1))
			for c in tg: if not skip.has(c): tgd[c] = true
			var avail = Logic.find_step(shape, p.givens, cand, 2, tgd, skip)
			if not avail.is_empty():
				assert_true(Logic.is_placement(s) and s.cells[0] in tg and s.value == digit, "L%d hint %d places the hunted digit %d" % [i + 1, k, digit])
				hunted += 1
			else:
				assert_eq(_key(s), _key(Sudoku.next_hint(p.givens, p.solution, [], taught)), "L%d hint %d falls back to the easiest step" % [i + 1, k])
			taught.append(s)
	assert_eq(n, 4, "4 Digit Hunt levels")
	assert_gt(hunted, 0, "hunted-digit placements are taught when available")

func test_every_level_first_hints_touch_targets_and_differ():
	for i in Levels.count():
		var lv = Levels.level(i)
		var p = _level_puzzle(lv)
		var tg = Levels.target_cells(lv)
		var a = Sudoku.next_hint(p.givens, p.solution, tg, [])
		var b = Sudoku.next_hint(p.givens, p.solution, tg, [a])
		var hunt = str(lv.params.get("inner", lv.objective)) == "digit"
		a = Sudoku.next_hint(p.givens, p.solution, tg, [], hunt)
		b = Sudoku.next_hint(p.givens, p.solution, tg, [a], hunt)
		var any_t = Sudoku.step_for_targets(p.givens, tg)
		if any_t.get("touches_target", false) and not hunt:
			assert_true(a.get("touches_target", false), "L%d (%s) first hint touches target when possible" % [i + 1, lv.objective])
		assert_false(b.is_empty(), "L%d second hint exists" % (i + 1))
		assert_ne(_key(a), _key(b), "L%d second hint differs" % (i + 1))

# ---------------- board state ----------------
func test_board_active_hint_tracks_acting_and_persists():
	var p = _pack(6, 1, 0)
	var b = Board.new(); b.setup(6, p.givens, p.solution)
	assert_true(b.active_hint().is_empty())
	var s = Sudoku.next_hint(b.correct_board(), b.solution, [], b.taught)
	b.add_taught(s)
	assert_eq(b.active_hint().cells, s.cells)
	var d = JSON.parse_string(JSON.stringify(b.to_dict()))   # real save round-trip (ints become floats)
	var b2 = Board.new(); b2.from_dict(d)
	assert_eq(b2.taught.size(), 1)
	assert_eq(b2.active_hint().cells, s.cells)
	assert_eq(typeof(b2.taught[0].cells[0]), TYPE_INT)
	assert_ne(_key(Sudoku.next_hint(b2.correct_board(), b2.solution, [], b2.taught)), _key(s), "restored save still advances")
	b.place(s.cells[0], s.value)
	assert_true(b.active_hint().is_empty(), "acted on")
	b.undo()
	assert_false(b.active_hint().is_empty(), "undo makes it pending again")
	b.retry()
	assert_eq(b.taught, [], "retry clears taught hints")

func test_old_save_without_taught_loads():
	var p = _pack(6, 1, 0)
	var b = Board.new(); b.setup(6, p.givens, p.solution)
	var d = b.to_dict(); d.erase("taught")
	var b2 = Board.new(); b2.from_dict(d)
	assert_eq(b2.taught, [])

# ---------------- UI flow ----------------
func test_ui_paid_teaches_without_acting_are_all_different():
	main.profile.tokens = 2
	main.profile.coins = 100
	main.classic_tier = 4
	main.start_classic()
	main._open_hint_panel(); main._pay_hint("teach", "token")
	var first = [main.grid_view.teach_cells.duplicate(), main.grid_view.teach_elims.duplicate()]
	assert_eq(main.profile.tokens, 1)
	main._open_hint_panel(); main._pay_hint("teach", "token")
	assert_eq(main.profile.tokens, 0)
	assert_ne([main.grid_view.teach_cells, main.grid_view.teach_elims], first, "second paid hint is different")
	main._open_hint_panel(); main._pay_hint("teach", "coins")
	assert_eq(main.profile.coins, 70)
	assert_eq(main.board.taught.size(), 3)
	var keys = {}
	for t in main.board.taught: keys[_key(t)] = true
	assert_eq(keys.size(), 3, "three distinct taught steps")

func test_ui_no_new_step_reshows_previous_for_free():
	main.profile.tokens = 2
	main.start_quick()
	var b = main.board
	var last = -1
	for i in b.cells.size():
		if b.cells[i] == 0:
			if last >= 0: b.place(last, b.solution[last])
			last = i
	main._open_hint_panel(); main._pay_hint("teach", "token")
	assert_eq(main.profile.tokens, 1)
	assert_eq(main.grid_view.teach_cells, [last])
	main._open_hint_panel()
	assert_not_null(main.overlay.find_child("ReshowHint", true, false), "free re-show offered")
	main._pay_hint("teach", "token")
	assert_eq(main.profile.tokens, 1, "not charged when there is nothing new")
	assert_eq(main.grid_view.teach_cells, [last], "previous hint shown again")
	assert_string_contains(main.teach_label.text, "no charge")
	main.profile.tokens = 0
	main.profile.coins = 100
	main._open_hint_panel(); main._pay_hint("teach", "coins")
	assert_eq(main.profile.coins, 100, "coins not charged either")

func test_ui_reshow_button_is_free_and_restores_highlight():
	main.profile.tokens = 1
	main.start_path_grid()
	main._open_hint_panel()
	assert_null(main.overlay.find_child("ReshowHint", true, false), "nothing to re-show yet")
	main._pay_hint("teach", "token")
	var cells = main.grid_view.teach_cells.duplicate()
	assert_gt(cells.size(), 0)
	main._open_hint_panel()   # opening the panel clears the on-board highlight
	assert_eq(main.grid_view.teach_cells, [])
	var coins = main.profile.coins
	main._reshow_hint()
	assert_eq(main.grid_view.teach_cells, cells)
	assert_eq(main.profile.tokens, 0)
	assert_eq(main.profile.coins, coins)
	assert_null(main.overlay)

func test_ui_reveal_without_valid_cell_is_never_charged():
	main.profile.tokens = 1
	main.start_path_grid()
	main.grid_view.selected = -1
	main._open_hint_panel(); main._pay_hint("reveal", "token")
	assert_eq(main.profile.tokens, 1, "no selection: no charge")
	main._close_overlay()
	var given = -1
	for i in main.board.givens.size():
		if main.board.givens[i] != 0:
			given = i
			break
	main.grid_view.selected = given
	main._open_hint_panel(); main._pay_hint("reveal", "token")
	assert_eq(main.profile.tokens, 1, "given cell: no charge")

func test_ui_taught_hint_survives_save_resume():
	main.profile.tokens = 1
	main.start_path_grid()
	main._open_hint_panel(); main._pay_hint("teach", "token")
	var cells = main.grid_view.teach_cells.duplicate()
	main._leave_grid()
	main.resume_grid()
	main._open_hint_panel()
	assert_not_null(main.overlay.find_child("ReshowHint", true, false))
	main._reshow_hint()
	assert_eq(main.grid_view.teach_cells, cells)

# ---------------- layout (QA run 6 minor: bottom border clipped at 1280x800) ----------------
func test_grid_border_fully_inside_viewport_landscape():
	var win = get_tree().root
	var old = win.size
	for sz in [Vector2i(1280, 800), Vector2i(1280, 753), Vector2i(1280, 720), Vector2i(1366, 768)]:
		win.size = sz
		main.start_level(10)
		await wait_frames(3)
		var gv = main.grid_view
		var vp = main.get_viewport_rect().size
		var tl = gv.get_global_rect().position + gv.origin()
		var span = gv.cell_px() * gv.board.size
		assert_lt(tl.y + span + 1.5, vp.y - 4.0, "%s: grid bottom border inside viewport (%.1f vs %.1f)" % [sz, tl.y + span + 1.5, vp.y])
		assert_lt(tl.x + span + 1.5, vp.x - 4.0, "%s: grid right border inside" % sz)
		assert_gt(tl.x - 1.5, 4.0, "%s: grid left border inside" % sz)
		main._leave_grid()
	win.size = old
	await wait_frames(2)
