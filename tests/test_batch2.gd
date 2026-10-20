extends GutTest
## B1 undo never refunds a mistake; B2 classic tier persists; B4 doubled coins label; QA API; ads without mock.

const Board = preload("res://game/board_state.gd")
const Sudoku = preload("res://sudoku/sudoku.gd")
var main

func before_each():
	Store.clear()
	Ads.call_log.clear()
	Ads.set_mode("mock_available")
	main = load("res://scenes/main.tscn").instantiate()
	add_child_autofree(main)
	await wait_frames(2)

func after_each():
	Ads.set_mode("mock_available")

func test_b1_undo_does_not_refund_mistake():
	var p = Sudoku.generate(6, 1, 3)
	var b = Board.new(); b.setup(6, p.givens, p.solution)
	var i = b.cells.find(0)
	var wrong = (b.solution[i] % 6) + 1
	b.place(i, wrong)
	assert_eq(b.mistakes, 1)
	assert_true(b.undo())
	assert_eq(b.cells[i], 0, "digit removed by undo")
	assert_eq(b.mistakes, 1, "mistake is NOT refunded by undo")
	assert_true(b.any_mistake)
	b.place(i, wrong); b.undo(); b.place(i, wrong)
	assert_eq(b.mistakes, 3, "each wrong placement counts, undo never refunds")

func test_b1_undo_in_ui_keeps_mistake_count_and_label():
	main.profile.path_next = 5
	main.start_path_grid()
	var b = main.board
	var i = b.cells.find(0)
	main._on_cell(i); main._on_digit((b.solution[i] % 6) + 1)
	main._undo()
	assert_eq(b.mistakes, 1)
	assert_eq(main.mistakes_label.text, "Mistakes 1/3")

func test_b2_classic_tier_persists_across_reload():
	main.show_harbour()
	for btn in main.root.find_children("*", "Button", true, false):
		if btn.text == "T3": btn.pressed.emit(); break
	assert_eq(main.classic_tier, 3)
	var m2 = load("res://scenes/main.tscn").instantiate()
	add_child_autofree(m2)
	await wait_frames(2)
	assert_eq(m2.classic_tier, 3)
	m2.show_harbour()
	var found = false
	for btn in m2.root.find_children("*", "Button", true, false):
		if btn.text == "T3": assert_true(btn.button_pressed); found = true
		if btn.text.begins_with("Classic 9x9"): assert_eq(btn.text, "Classic 9x9 (tier 3)")
	assert_true(found)

func _finish_grid():
	main.start_path_grid()
	var b = main.board
	for i in b.cells.size():
		if main.screen_name != "grid": break
		if b.cells[i] == 0: main._on_cell(i); main._on_digit(b.solution[i])

func test_b4_double_coins_updates_label():
	_finish_grid()
	var lbl = main.root.find_child("ResultsRewards", true, false)
	assert_string_starts_with(lbl.text, "+20 coins")   # v1.3: L1 is 6x6
	var coins = main.profile.coins
	await main._double(20)
	assert_eq(main.profile.coins, coins + 20)
	assert_string_starts_with(lbl.text, "+40 coins")
	assert_null(main.root.find_child("RewardedDouble", true, false))

func test_b4_failed_double_keeps_label():
	_finish_grid()
	Ads.set_mode("mock_error")
	await main._double(20)
	assert_string_starts_with(main.root.find_child("ResultsRewards", true, false).text, "+20 coins")

func test_qa_api_set_coins_tokens_reset_cap():
	var h = Dbg.hooks
	assert_not_null(h, "debug hooks loaded in debug build")
	h.set_coins(7); h.set_tokens(25)
	assert_eq(main.profile.coins, 7)
	assert_eq(main.profile.tokens, 10, "clamped to cap")
	var now = Dbg.now_ms()
	for k in 3: main.profile.record_second_chance(now - k)
	assert_true(main.profile.sc_capped(now))
	h.reset_sc_cap()
	assert_false(main.profile.sc_capped(now))
	var d = Store.load_data()
	assert_eq(int(d.coins), 7, "QA changes are saved")

func test_ads_none_mode_never_grants():
	Ads.set_mode("none")
	assert_false(Ads.available())
	Ads.set_context("results")
	var ok = await Ads.rewarded("double_coins")
	assert_false(ok)
	assert_eq(Ads.call_log.back().result, "unavailable")

func test_release_mode_defaults_without_mock():
	# simulate the release export: no mock script available -> "none", no mock modes accepted
	var a = load("res://autoload/ads.gd").new()
	assert_eq(a.mode, "none")
	a.mock = null
	assert_eq(a.modes(), ["none", "sdk"])
	a.set_mode("mock_available")
	assert_eq(a.mode, "none")
	assert_false(a.available())
	a.free()
