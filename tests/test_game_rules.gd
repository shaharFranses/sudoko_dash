extends GutTest

const Board = preload("res://game/board_state.gd")
const Profile = preload("res://game/profile.gd")
const AdPolicy = preload("res://game/ad_policy.gd")
const Sudoku = preload("res://sudoku/sudoku.gd")
const Source = preload("res://game/puzzle_source.gd")

func _board(size = 6) -> Board:
	var p = Sudoku.generate(size, 1, 3)
	var b = Board.new(); b.setup(size, p.givens, p.solution)
	return b

func _first_empty(b) -> int:
	for i in b.cells.size():
		if b.cells[i] == 0: return i
	return -1

func _wrong(b, i) -> int:
	return (b.solution[i] % b.size) + 1

func test_undo_restores_exact_state():
	var b = _board()
	var before = b.snapshot()
	var i = _first_empty(b)
	b.toggle_note(i, 1); b.toggle_note(i, 2)
	var mid = b.snapshot()
	b.place(i, b.solution[i])
	b.undo()
	assert_eq(b.snapshot(), mid)
	b.undo(); b.undo()
	assert_eq(b.snapshot(), before)

func test_place_clears_peer_notes():
	var b = _board()
	var i = _first_empty(b)
	var d = b.solution[i]
	var peer = -1
	for p in b.shape.peers[i]:
		if b.cells[p] == 0: peer = p; break
	b.toggle_note(peer, d)
	b.place(i, d)
	assert_eq(b.notes[peer] & (1 << (d - 1)), 0)

func test_third_mistake_reaches_limit_and_continue():
	var b = _board()
	var i = _first_empty(b)
	var r
	for k in 3: r = b.place(i, _wrong(b, i) if k != 1 else ((_wrong(b, i)) % b.size) + 1)
	# ensure distinct wrong values; fall back loop
	assert_eq(b.mistakes, 3)
	assert_true(r.limit_reached)
	b.apply_continue()
	assert_eq(b.mistakes, 0)
	assert_eq(b.wrong_cells(), [])
	for s in b.history:
		for c in s.cells.size(): assert_true(s.cells[c] == 0 or s.cells[c] == b.solution[c])

func test_after_continue_next_three_mistakes_fail():
	var b = _board()
	b.apply_continue()
	var i = _first_empty(b)
	var vals = []
	for d in range(1, b.size + 1):
		if d != b.solution[i]: vals.append(d)
	for k in 3: b.place(i, vals[k])
	assert_true(b.failed)

func test_4x4_has_no_mistake_limit():
	var b = _board(4)
	assert_eq(b.max_mistakes, 0)

func test_retry_restores_givens_and_allowance():
	var b = _board()
	b.apply_continue()
	b.place(_first_empty(b), 1)
	b.retry()
	assert_eq(b.cells, b.givens)
	assert_false(b.second_chance_used)
	assert_eq(b.history, [])

func test_reveal_fills_only_selected_cell():
	var b = _board()
	var i = _first_empty(b)
	var before = b.cells.duplicate()
	b.reveal(i)
	var diff = 0
	for c in before.size():
		if before[c] != b.cells[c]: diff += 1
	assert_eq(diff, 1)
	assert_eq(b.reveals, 1)

func test_board_roundtrip():
	var b = _board()
	b.toggle_note(_first_empty(b), 3); b.place(_first_empty(b), 2)
	var c = Board.new(); c.from_dict(JSON.parse_string(JSON.stringify(b.to_dict())))
	assert_eq(c.to_dict(), b.to_dict())

func test_token_cap_10_all_sources():
	var p = Profile.new()
	assert_eq(p.grant_tokens(20), 7)
	assert_eq(p.tokens, 10)
	assert_eq(p.grant_tokens(1), 0)

func test_coin_hint_never_adds_token():
	var p = Profile.new(); p.tokens = 0
	assert_true(p.spend_coins(Profile.HINT_COIN_PRICE))
	assert_eq(p.tokens, 0); assert_eq(p.coins, 70)
	assert_eq(p.need_more(Profile.CONTINUE_COIN_PRICE), 0)
	p.coins = 20
	assert_eq(p.need_more(30), 10)

func test_sc_cap_rolling_24h():
	var p = Profile.new()
	var t = 1_700_000_000_000
	for k in 3: p.record_second_chance(t + k * 1000)
	assert_true(p.sc_capped(t + 5000))
	assert_true(p.sc_capped(t + 24 * 3600 * 1000 - 1))
	assert_false(p.sc_capped(t + 24 * 3600 * 1000 + 3000))

func test_sc_cap_survives_clock_rollback():
	var p = Profile.new()
	var t = 1_700_000_000_000
	for k in 3: p.record_second_chance(t + k)
	var back = t - 10 * 24 * 3600 * 1000
	assert_true(p.sc_capped(back))
	assert_true(p.sc_capped(t + 2 + 24 * 3600 * 1000 - 1))
	assert_false(p.sc_capped(t + 2 + 24 * 3600 * 1000 + 1))

func test_sc_rollback_with_one_use_is_capped_until_plus24h():
	var p = Profile.new()
	var t = 1_700_000_000_000
	p.record_second_chance(t)
	assert_true(p.sc_capped(t - 1000))
	assert_false(p.sc_capped(t + 24 * 3600 * 1000 + 1))

func test_path_star_min_and_max():
	var lo = Profile.new(); var hi = Profile.new()
	for i in Profile.PATH.size():
		var sz = Profile.PATH[i][0]
		lo.complete_grid("path", sz, i, true, true)
		hi.complete_grid("path", sz, i, false, false)
	assert_eq(lo.stars_earned, 20)
	assert_eq(hi.stars_earned, 31)
	assert_true(lo.path_finished())

func test_tasks_cost_20_and_min_path_buys_all():
	var total = 0
	for t in Profile.TASKS: total += t.cost
	assert_eq(total, 20)
	var p = Profile.new()
	for i in Profile.PATH.size(): p.complete_grid("path", Profile.PATH[i][0], i, true, true)
	for t in Profile.TASKS: assert_true(p.buy_task(t.id))
	assert_true(p.area_restored())

func test_stars_only_first_completion_and_quick_coins_only():
	var p = Profile.new()
	p.complete_grid("path", 4, 0, false, false)
	var r = p.complete_grid("path", 4, 0, false, false)
	assert_eq(r.stars, 0)
	r = p.complete_grid("quick", 6, -1, false, false)
	assert_eq(r.stars, 0); assert_eq(r.coins, 20)

func test_profile_roundtrip():
	var p = Profile.new()
	p.complete_grid("path", 4, 0, false, false); p.record_second_chance(123)
	p.stars = 9; p.buy_task("dock"); p.set_decor("dock", 2)
	var q = Profile.new(); q.from_dict(JSON.parse_string(JSON.stringify(p.to_dict())))
	assert_eq(JSON.stringify(q.to_dict()), JSON.stringify(p.to_dict()))

func test_midgame_policy():
	var a = AdPolicy.new(0)
	a.on_grid_completed(); a.on_grid_completed(); a.on_grid_completed()
	assert_eq(a.results_offer(60_000, true), "rewarded", "not before 5 min")
	assert_eq(a.results_offer(300_000, true), "midgame")
	assert_eq(a.counter, 0)
	assert_eq(a.results_offer(300_000, true), "rewarded")
	assert_eq(a.results_offer(300_000, false), "none")

func test_runtime_never_generates_9x9():
	var s = Source.new()
	var p = s.get_puzzle(9, 3, 5)
	assert_eq(s.log[0].source, "pack")
	assert_eq(p.givens.size(), 81)
	for e in s.log: assert_eq(e.source, "pack")

func test_runtime_source_p95_within_budget():
	var s = Source.new()
	for sd in 60:
		var n = 4 if sd % 3 == 0 else 6
		var t0 = Time.get_ticks_usec()
		var p = s.get_puzzle(n, 1 + (sd % 2 if n == 6 else 0), sd)
		s.call_times_ms.append((Time.get_ticks_usec() - t0) / 1000.0)
		assert_eq(Sudoku.solve(p.givens).count, 1)
	var ts = s.call_times_ms.duplicate(); ts.sort()
	var p95 = ts[int(ceil(ts.size() * 0.95)) - 1]
	gut.p("runtime 4x4/6x6 get_puzzle p95 = %.2f ms (native headless)" % p95)
	assert_lt(p95, 30.0)
