extends GutTest
## Timed-level elapsed time survives a reload within +-1000 ms (QA dbg44 row 4): save when the timer pauses
## (tab hidden / blur), on page leave (SD_PAGE -> on_page_leave), and every 1 s on timed levels.

const Levels = preload("res://game/levels.gd")
const Obj = preload("res://game/objectives.gd")
var main

func before_each():
	Store.clear()
	Ads.call_log.clear()
	Ads.set_mode("mock_available")
	Sfx.set_reason("hidden", false); Sfx.set_reason("blur", false)
	main = _new_main()
	await wait_frames(2)

func after_each():
	Sfx.set_reason("hidden", false); Sfx.set_reason("blur", false)

func _new_main():
	var m = load("res://scenes/main.tscn").instantiate()
	m.play_intro = false
	add_child_autofree(m)
	return m

func _start(timed: bool) -> Dictionary:
	for i in 20:
		var lv = Levels.level(i)
		if Obj.is_timed(lv) == timed:
			main.start_level(i)
			return lv
	return {}

func _saved_elapsed() -> int:
	var d = Store.load_data()
	return int(d.current_grid.level.elapsed_ms) if d.has("current_grid") and d.current_grid.has("level") else -1

## Simulated reload: a fresh main scene reads the save and resumes.
func _reload_elapsed() -> int:
	var m2 = _new_main()
	await wait_frames(2)
	m2.resume_grid()
	var e = m2.elapsed_ms
	return e

## Run the live timer for about `s` seconds of real frames.
func _play(s: float) -> void:
	var t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(s * 1000.0):
		await wait_frames(1)

func test_timed_level_uses_1s_fallback_untimed_keeps_5s():
	_start(true)
	assert_true(main.timer_running())
	assert_lte(main.save_interval(), 1.0, "timed: fallback save at least every 1 s")
	_start(false)
	assert_eq(main.save_interval(), 5.0, "untimed levels: unchanged 5 s periodic save")

func test_restore_after_tab_hidden_within_1000ms():
	_start(true)
	await _play(1.6)
	main.elapsed_ms += 2345   # pretend more play, so the last periodic save is stale by > 1 s
	var pre = main.elapsed_ms
	Sfx.set_reason("hidden", true)   # the page-event path: timer pauses -> save
	assert_false(main.timer_running())
	assert_eq(_saved_elapsed(), pre, "saved exactly at the pause")
	var restored = await _reload_elapsed()
	gut.p("hidden: pre %d restored %d offset %d ms" % [pre, restored, restored - pre])
	assert_almost_eq(restored, pre, 1000)

func test_restore_after_blur_within_1000ms():
	_start(true)
	await _play(0.5)
	main.elapsed_ms += 4321
	var pre = main.elapsed_ms
	Sfx.set_reason("blur", true)
	assert_eq(_saved_elapsed(), pre)
	var restored = await _reload_elapsed()
	assert_almost_eq(restored, pre, 1000)

func test_restore_after_page_leave_within_1000ms():
	_start(true)
	await _play(0.5)
	main.elapsed_ms += 3210   # unsaved time (periodic save not due yet)
	assert_lt(_saved_elapsed(), main.elapsed_ms - 1000, "stale before the unload save")
	var pre = main.elapsed_ms
	main.on_page_leave()   # what SD_PAGE.onLeave calls on pagehide / beforeunload / hidden
	assert_eq(_saved_elapsed(), pre, "saved synchronously on page leave")
	var restored = await _reload_elapsed()
	gut.p("unload: pre %d restored %d offset %d ms" % [pre, restored, restored - pre])
	assert_almost_eq(restored, pre, 1000)

func test_fallback_bounds_loss_under_1000ms():
	_start(true)
	var worst = 0
	for k in 12:   # sample the saved-vs-live gap at arbitrary points over ~3.5 s of play
		await _play(0.29)
		var gap = main.elapsed_ms - _saved_elapsed()
		worst = maxi(worst, gap)
	gut.p("fallback: worst unsaved gap %d ms" % worst)
	assert_lt(worst, 1000, "a plain reload with no unload event loses < 1000 ms")
	var pre = main.elapsed_ms
	var restored = await _reload_elapsed()
	assert_lt(pre - restored, 1000)
	assert_gte(pre - restored, 0)

func test_untimed_level_unchanged():
	_start(false)
	assert_false(main.timer_running(), "untimed: no timer")
	await _play(1.3)
	assert_eq(main.elapsed_ms, 0, "untimed: elapsed stays 0")
	Sfx.set_reason("hidden", true)   # pause save still harmless
	assert_eq(_saved_elapsed(), 0)
	main.on_page_leave()
	var d = Store.load_data()
	assert_true(d.current_grid.has("board"), "board still saved as before")
	main._save_accum = 0.0
	main._process(4.0)
	main._process(1.1)   # 5 s total -> periodic save, as before
	assert_almost_eq(main._save_accum, 0.0, 0.001)

func test_pause_on_menu_does_not_save_grid():
	main.show_harbour()
	Sfx.set_reason("hidden", true)
	assert_false(Store.load_data().get("current_grid", {}).has("board"))
