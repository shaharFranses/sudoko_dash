extends GutTest

const MuteState = preload("res://game/mute_state.gd")

func after_each():
	for r in ["ad", "hidden", "user"]: Sfx.set_reason(r, false)
	Ads.set_mode("mock_available")

func test_mute_state_any_reason():
	var m = MuteState.new()
	assert_false(m.muted())
	m.set_reason("ad", true); assert_true(m.muted())
	m.set_reason("hidden", true); m.set_reason("ad", false)
	assert_true(m.muted(), "still hidden")
	m.set_reason("hidden", false); assert_false(m.muted())

func test_mute_reason_idempotent():
	var m = MuteState.new()
	m.set_reason("ad", true); m.set_reason("ad", true); m.set_reason("ad", false)
	assert_false(m.muted())

func test_master_bus_follows_reasons():
	Sfx.set_reason("hidden", true)
	assert_true(AudioServer.is_bus_mute(0))
	Sfx.set_reason("hidden", false)
	assert_false(AudioServer.is_bus_mute(0))

func test_ad_mutes_during_and_restores_after():
	Ads.set_mode("mock_available")
	Ads.set_context("results")
	var seen = []
	var probe = func(): seen.append(AudioServer.is_bus_mute(0))
	Ads.logged.connect(func(e): if e.result == "requested": probe.call())
	var ok = await Ads.rewarded("test")
	assert_true(ok)
	assert_eq(seen, [true], "muted while ad running")
	assert_false(AudioServer.is_bus_mute(0), "unmuted after ad")

func test_ad_error_and_timeout_unmute():
	Ads.timeout_s = 0.2
	Ads.set_context("results")
	for m in ["mock_error", "mock_timeout"]:
		Ads.set_mode(m)
		await Ads.rewarded("test")
		assert_false(AudioServer.is_bus_mute(0), m)
	Ads.timeout_s = Ads.TIMEOUT_S

func test_ad_end_keeps_hidden_mute():
	Sfx.set_reason("hidden", true)
	Ads.set_context("results")
	await Ads.rewarded("test")
	assert_true(AudioServer.is_bus_mute(0), "tab still hidden -> stay muted")

func test_unavailable_ad_does_not_touch_mute():
	Ads.set_mode("mock_unavailable")
	Ads.set_context("results")
	await Ads.rewarded("test")
	assert_false(AudioServer.is_bus_mute(0))

func test_sfx_generated_and_tiny():
	for k in ["tap", "place", "mistake", "complete"]:
		assert_true(Sfx.streams.has(k))
		assert_lt(Sfx.streams[k].data.size(), 40000)

func test_gameplay_sounds_wired():
	Store.clear()
	var main = load("res://scenes/main.tscn").instantiate()
	main.play_intro = false   # PKD intro covered by test_pkd_intro.gd
	add_child_autofree(main)
	await wait_frames(2)
	main.profile.path_next = 5
	main.start_path_grid()
	Sfx.played.clear()
	var b = main.board
	var i = b.cells.find(0)
	main._on_cell(i); main._on_digit((b.solution[i] % 6) + 1)
	main._undo()
	main._on_digit(b.solution[i])
	assert_has(Sfx.played, "tap"); assert_has(Sfx.played, "mistake"); assert_has(Sfx.played, "place")
	for j in b.cells.size():
		if b.cells[j] == 0: main._on_cell(j); main._on_digit(b.solution[j])
	assert_eq(Sfx.played.back(), "complete")
