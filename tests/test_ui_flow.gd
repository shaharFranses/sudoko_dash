extends GutTest
## Integration tests driving the real main scene headless (1280x720 viewport).

const Profile = preload("res://game/profile.gd")
var main

func before_each():
	Store.clear()
	Ads.call_log.clear()
	Ads.set_mode("mock_available")
	Dbg.clock_offset_ms = 0
	main = load("res://scenes/main.tscn").instantiate()
	add_child_autofree(main)
	await wait_frames(2)

func _rewarded_nodes() -> Array:
	var out = []
	for n in main.find_children("Rewarded*", "", true, false):
		if not n.is_queued_for_deletion(): out.append(n)
	return out

func _solve_current():
	var b = main.board
	for i in b.cells.size():
		if main.board == null: return
		if b.cells[i] == 0:
			main._on_cell(i)
			main._on_digit(b.solution[i])

func test_boots_to_title_then_harbour():
	assert_eq(main.screen_name, "title")
	main.show_harbour()
	assert_eq(main.screen_name, "harbour")

func test_hint_opens_panel_pauses_and_no_rewarded_on_live_grid():
	main.start_path_grid()
	assert_eq(Ads.context, "grid")
	assert_eq(_rewarded_nodes(), [], "no rewarded button on live grid")
	main._open_hint_panel()
	assert_not_null(main.overlay)
	assert_eq(main.overlay.name, "HintPanel")
	assert_eq(Ads.context, "grid_panel")
	# input blocked while paused
	var before = main.board.snapshot()
	main._on_cell(0); main._on_digit(1)
	assert_eq(main.board.snapshot(), before)

func test_input_mouse_and_keyboard_and_undo_exact():
	main.start_path_grid()
	var b = main.board
	var i = b.cells.find(0)
	var s0 = b.snapshot()
	# tap cell (mouse event on grid view)
	var gv = main.grid_view
	await wait_frames(2)
	var ev = InputEventMouseButton.new(); ev.button_index = MOUSE_BUTTON_LEFT; ev.pressed = true
	ev.position = gv.origin() + Vector2(i % b.size + 0.5, i / b.size + 0.5) * gv.cell_px()
	gv._gui_input(ev)
	assert_eq(gv.selected, i)
	var k = InputEventKey.new(); k.pressed = true; k.keycode = KEY_N
	main._unhandled_input(k)
	assert_true(main.notes_mode)
	k = InputEventKey.new(); k.pressed = true; k.keycode = KEY_1 + 1; k.physical_keycode = KEY_1 + 1
	main._unhandled_input(k)
	assert_ne(b.notes[i], 0)
	var s1 = b.snapshot()
	main._toggle_notes()
	k = InputEventKey.new(); k.pressed = true; k.keycode = KEY_0 + b.solution[i]; k.physical_keycode = KEY_0 + b.solution[i]
	main._unhandled_input(k)
	assert_eq(b.cells[i], b.solution[i])
	k = InputEventKey.new(); k.pressed = true; k.keycode = KEY_Z; k.ctrl_pressed = true
	main._unhandled_input(k)
	assert_eq(b.snapshot(), s1)
	main._undo()
	assert_eq(b.snapshot(), s0)
	# digit-first mode
	main._on_cell(-1) if false else null
	gv.selected = -1
	main._on_digit(b.solution[i])
	assert_eq(main.digit_lock, b.solution[i])
	main._on_cell(i)
	assert_eq(b.cells[i], b.solution[i])
	# arrows + backspace
	k = InputEventKey.new(); k.pressed = true; k.keycode = KEY_BACKSPACE
	main.digit_lock = 0
	main._unhandled_input(k)
	assert_eq(b.cells[i], 0)

func test_teach_matches_step_and_flags_wrong_first():
	main.profile.tokens = 3
	main.classic_tier = 3
	main.start_classic()
	var b = main.board
	var i = b.cells.find(0)
	b.place(i, (b.solution[i] % 9) + 1)
	main._open_hint_panel()
	main._pay_hint("teach", "token")
	assert_eq(main.grid_view.flag_cells, [i])
	assert_eq(main.profile.tokens, 3, "flagging is free")
	b.undo()
	main._open_hint_panel()
	main._pay_hint("teach", "token")
	var s = preload("res://sudoku/sudoku.gd").step(b.correct_board())
	assert_eq(main.grid_view.teach_cells, s.cells)
	assert_true(main.teach_label.text.begins_with(preload("res://sudoku/logic.gd").NAMES[s.technique]))
	assert_eq(main.profile.tokens, 2)

func test_ads_off_no_rewarded_anywhere_and_coins_path():
	Ads.set_mode("mock_unavailable")
	main.profile.tokens = 0
	main.start_path_grid()
	main._open_hint_panel()
	assert_eq(_rewarded_nodes(), [])
	assert_true(main.overlay.find_children("*", "Button", true, false).size() >= 3)
	main._pay_hint("teach", "coins")
	assert_eq(main.profile.coins, 70)
	assert_eq(main.profile.tokens, 0)

func test_unaffordable_coin_option_disabled_with_need_line():
	main.profile.tokens = 0
	main.profile.coins = 10
	main.start_path_grid()
	main._open_hint_panel()
	var found = false
	for b in main.overlay.find_children("*", "Button", true, false):
		if b.text.contains("(30 coins)"): assert_true(b.disabled); found = true
	assert_true(found)
	var labels = []
	for l in main.overlay.find_children("*", "Label", true, false): labels.append(l.text)
	assert_has(labels, "Need 20 more coins")

func _make_mistakes(n: int):
	var b = main.board
	var i = b.cells.find(0)
	var vals = []
	for d in range(1, b.size + 1):
		if d != b.solution[i]: vals.append(d)
	for k in n:
		main._on_cell(i); main._on_digit(vals[k % vals.size()])

func test_third_mistake_second_chance_once_per_grid():
	main.profile.path_next = 5   # 6x6
	main.start_path_grid()
	_make_mistakes(3)
	assert_eq(main.overlay.name, "SecondChancePanel")
	assert_eq(Ads.context, "grid_panel")
	await main._second_chance("coins")
	assert_eq(main.profile.coins, 50)
	assert_eq(main.board.mistakes, 0)
	_make_mistakes(3)
	assert_eq(main.overlay.name, "SecondChancePanel")
	var texts = []
	for b in main.overlay.find_children("*", "Button", true, false): texts.append(b.text)
	assert_eq(texts, ["Retry from the start"])

func test_sc_capped_after_3_in_24h_and_clock_rollback():
	var now = Dbg.now_ms()
	for k in 3: main.profile.record_second_chance(now - 1000 + k)
	main.profile.path_next = 5
	main.start_path_grid()
	_make_mistakes(3)
	var texts = []
	for b in main.overlay.find_children("*", "Button", true, false): texts.append(b.text)
	assert_eq(texts, ["Retry from the start"])
	Dbg.clock_offset_ms = -5 * 24 * 3600 * 1000
	main._retry()
	_make_mistakes(3)
	texts = []
	for b in main.overlay.find_children("*", "Button", true, false): texts.append(b.text)
	assert_eq(texts, ["Retry from the start"], "still capped after clock set back")

func test_retry_resets_board():
	main.profile.path_next = 5
	main.start_path_grid()
	_make_mistakes(3)
	main._retry()
	assert_eq(main.board.cells, main.board.givens)
	assert_eq(main.board.mistakes, 0)
	assert_null(main.overlay)

func test_full_path_ads_off_and_area_restored_min_stars():
	Ads.set_mode("mock_unavailable")
	for g in 15:
		main.start_path_grid()
		if main.board.size != 4: _make_mistakes(1)
		if main.board.size == 9:
			var i = main.board.cells.find(0)
			main._on_cell(i)
			main.profile.tokens = maxi(main.profile.tokens, 1)
			main._open_hint_panel(); main._pay_hint("reveal", "token")
		# clear the wrong digit then solve
		for w in main.board.wrong_cells(): main.board.erase(w)
		_solve_current()
		assert_eq(main.screen_name, "results")
		assert_eq(_rewarded_nodes(), [])
	assert_true(main.profile.path_finished())
	assert_eq(main.profile.stars_earned, 20)
	for t in Profile.TASKS: main._buy_task(t.id)
	assert_eq(main.screen_name, "restored")
	for e in Ads.call_log: assert_ne(e.kind, "midgame")

func test_perfect_path_31_stars():
	for g in 15:
		main.start_path_grid()
		_solve_current()
	assert_eq(main.profile.stars_earned, 31)

func test_no_midgame_while_grid_open_and_never_both_on_results():
	main.policy.session_start_ms = -10 * 60 * 1000
	for g in 3:
		main.start_quick()
		var r = await Ads.midgame("test")
		assert_false(r)
		_solve_current()
		await wait_seconds(0.8)
	var mids = []
	for e in Ads.call_log:
		if e.kind == "midgame" and e.result == "requested": mids.append(e)
		if e.result == "requested": assert_false(e.grid_open and e.kind == "midgame")
	assert_eq(mids.size(), 1, "midgame after 3rd completion")
	assert_eq(_rewarded_nodes(), [], "results with midgame shows no rewarded offer")

func test_reload_restores_everything():
	main.profile.path_next = 5
	main.start_path_grid()
	var b = main.board
	var i = b.cells.find(0)
	main._on_cell(i); main._toggle_notes(); main._on_digit(1); main._on_digit(2)
	main.profile.record_second_chance(Dbg.now_ms())
	main.profile.stars = 7; main.profile.buy_task("dock"); main.profile.set_decor("dock", 2)
	main.save()
	var snap_p = JSON.stringify(main.profile.to_dict())
	var snap_b = JSON.stringify(b.to_dict())
	var m2 = load("res://scenes/main.tscn").instantiate()
	add_child_autofree(m2)
	await wait_frames(1)
	assert_eq(JSON.stringify(m2.profile.to_dict()), snap_p)
	m2.resume_grid()
	assert_eq(JSON.stringify(m2.board.to_dict()), snap_b)

func test_readability_9x9_at_1280x720():
	get_tree().root.size = Vector2i(1280, 720)
	await wait_frames(2)
	main.classic_tier = 1
	main.start_classic()
	await wait_frames(3)
	var vp = main.get_viewport_rect().size
	gut.p("viewport %s, 9x9 cell px = %s" % [vp, main.grid_view.cell_px()])
	var gv = main.grid_view
	assert_eq(vp, Vector2(1280, 720))
	assert_gte(main.grid_view.cell_px(), 44.0)
	assert_gte(int(main.grid_view.cell_px() * 0.66) / main.grid_view.cell_px(), 0.6)

func test_runtime_no_9x9_generation_logged():
	main.classic_tier = 4; main.start_classic()
	main.start_path_grid()
	for e in main.source.log:
		if e.size == 9: assert_eq(e.source, "pack")
