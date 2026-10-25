extends GutTest
## Rewarded-ad failure modes (mock error / timeout) on every rewarded path.

var main

func before_each():
	Store.clear()
	Ads.call_log.clear()
	Ads.busy = false
	Ads.timeout_s = 0.3
	Dbg.clock_offset_ms = 0
	main = load("res://scenes/main.tscn").instantiate()
	main.play_intro = false   # PKD intro covered by test_pkd_intro.gd
	add_child_autofree(main)
	await wait_frames(2)

func after_each():
	Ads.timeout_s = Ads.TIMEOUT_S
	Ads.set_mode("mock_available")

func _entries(kind: String) -> Array:
	return Ads.call_log.filter(func(e): return e.kind == kind)

func _assert_log(kind: String, origin: String, result: String, ctx: String):
	var es = _entries(kind)
	assert_eq(es.size(), 2, "requested + outcome logged")
	if es.size() < 2: return
	assert_eq(es[0].result, "requested")
	assert_eq(es[1].result, result)
	for e in es:
		assert_eq(e.origin, origin)
		assert_eq(e.context, ctx)
	assert_false(Ads.busy, "adapter not stuck busy")

func _buttons() -> Array:
	var o = []
	if main.overlay:
		for b in main.overlay.find_children("*", "Button", true, false): o.append(b)
	return o

func _btn(prefix: String):
	for b in _buttons():
		if b.text.begins_with(prefix): return b
	return null

func _mistakes3():
	var b = main.board
	var i = b.cells.find(0)
	var vals = []
	for d in range(1, b.size + 1):
		if d != b.solution[i]: vals.append(d)
	for k in 3:
		main._on_cell(i); main._on_digit(vals[k])

func _recover_and_unpause():
	var back = _btn("Back to grid")
	assert_not_null(back, "panel offers Back")
	if back: back.pressed.emit()
	assert_null(main.overlay)
	assert_eq(Ads.context, "grid", "grid unpaused")
	var b = main.board
	var i = b.cells.find(0)
	main._on_cell(i); main._on_digit(b.solution[i])
	assert_eq(b.cells[i], b.solution[i], "input works after recovery")

# ---- hint token ----
func _hint_token_case(mode: String, result: String):
	main.profile.tokens = 0
	main.start_path_grid()
	Ads.set_mode(mode); Ads.call_log.clear()
	main._open_hint_panel()
	var ab = _btn("Watch an ad")
	assert_not_null(ab, "rewarded token button shown (ads 'available')")
	var coins = main.profile.coins
	main._ad_for_token()
	if mode == "mock_timeout":
		await wait_frames(2)
		for b in _buttons(): assert_true(b.disabled, "panel locked while ad pending")
	await wait_seconds(0.6)
	assert_eq(main.profile.tokens, 0, "no token granted")
	assert_eq(main.profile.coins, coins)
	assert_eq(main.overlay.name, "HintPanel")
	assert_eq(Ads.context, "grid_panel")
	assert_not_null(_btn("Watch an ad"), "still retryable")
	assert_false(_btn("Watch an ad").disabled)
	assert_string_contains(main.teach_label.text, "no token")
	_assert_log("rewarded", "hint_token", result, "grid_panel")
	_recover_and_unpause()

func test_hint_token_ad_error(): await _hint_token_case("mock_error", "error")
func test_hint_token_ad_timeout(): await _hint_token_case("mock_timeout", "timeout")

func test_hint_token_retry_after_error_then_success():
	main.profile.tokens = 0
	main.start_path_grid()
	Ads.set_mode("mock_error")
	main._open_hint_panel()
	await main._ad_for_token()
	Ads.set_mode("mock_available")
	await main._ad_for_token()
	assert_eq(main.profile.tokens, 1)

# ---- second chance ----
func _sc_case(mode: String, result: String):
	main.profile.path_next = 5
	main.start_path_grid()
	_mistakes3()
	Ads.set_mode(mode); Ads.call_log.clear()
	main._open_second_chance()
	assert_not_null(_btn("Continue free"))
	var coins = main.profile.coins
	main._second_chance("ad")
	if mode == "mock_timeout":
		await wait_frames(2)
		for b in _buttons(): assert_true(b.disabled, "panel locked while ad pending")
	await wait_seconds(0.6)
	assert_eq(main.board.mistakes, 3, "no continue granted")
	assert_false(main.board.second_chance_used)
	assert_eq(main.profile.sc_times, [], "cap not consumed")
	assert_eq(main.profile.coins, coins)
	assert_eq(main.overlay.name, "SecondChancePanel")
	assert_eq(Ads.context, "grid_panel")
	assert_not_null(_btn("Continue free"), "still retryable")
	assert_false(_btn("Continue free").disabled)
	assert_false(_btn("Continue (50").disabled, "coin path still available")
	_assert_log("rewarded", "second_chance", result, "grid_panel")
	# recover via coins
	_btn("Continue (50").pressed.emit()
	assert_null(main.overlay)
	assert_eq(Ads.context, "grid")
	assert_eq(main.board.mistakes, 0)

func test_second_chance_ad_error(): await _sc_case("mock_error", "error")
func test_second_chance_ad_timeout(): await _sc_case("mock_timeout", "timeout")

func test_second_chance_ad_fail_then_retry_button_works():
	main.profile.path_next = 5
	main.start_path_grid()
	_mistakes3()
	Ads.set_mode("mock_error")
	await main._second_chance("ad")
	_btn("Retry").pressed.emit()
	assert_null(main.overlay)
	assert_eq(main.board.cells, main.board.givens)
	assert_eq(Ads.context, "grid")

# ---- double coins on results ----
func _double_case(mode: String, result: String):
	main.start_path_grid()
	var b = main.board
	for i in b.cells.size():
		if main.screen_name != "grid": break
		if b.cells[i] == 0: main._on_cell(i); main._on_digit(b.solution[i])
	assert_eq(main.screen_name, "results")
	var db = main.root.find_child("RewardedDouble", true, false)
	assert_not_null(db)
	Ads.set_mode(mode); Ads.call_log.clear()
	var coins = main.profile.coins
	main._double(10)
	if mode == "mock_timeout":
		await wait_frames(2)
		assert_true(db.disabled, "button locked while pending")
	await wait_seconds(0.6)
	assert_eq(main.profile.coins, coins, "no coins granted")
	assert_true(is_instance_valid(db))
	assert_false(db.disabled, "retryable")
	assert_string_contains(db.text, "try again")
	_assert_log("rewarded", "double_coins", result, "results")

func test_double_coins_ad_error(): await _double_case("mock_error", "error")
func test_double_coins_ad_timeout(): await _double_case("mock_timeout", "timeout")

func test_double_coins_leaving_results_while_pending_is_safe():
	main.start_path_grid()
	var b = main.board
	for i in b.cells.size():
		if main.screen_name != "grid": break
		if b.cells[i] == 0: main._on_cell(i); main._on_digit(b.solution[i])
	Ads.set_mode("mock_timeout")
	main._double(10)
	await wait_frames(1)
	main.show_harbour()   # player leaves; button freed
	await wait_seconds(0.6)
	assert_eq(main.screen_name, "harbour")
	assert_false(Ads.busy)

# ---- midgame failure: game continues ----
func test_midgame_error_and_timeout_do_not_block():
	for m in ["mock_error", "mock_timeout"]:
		Ads.set_mode(m); Ads.call_log.clear()
		Ads.set_context("results")
		var ok = await Ads.midgame("results")
		assert_false(ok)
		assert_eq(Ads.call_log.back().result, "error" if m == "mock_error" else "timeout")
		assert_false(Ads.busy)

func test_default_timeout_is_8s():
	assert_eq(Ads.TIMEOUT_S, 8.0)
