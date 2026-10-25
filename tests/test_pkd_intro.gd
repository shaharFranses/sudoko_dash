extends GutTest
## PKD studio intro (pkd_intro/, INTEGRATION.md overlay mode): intro first, then the title; tap / click / key
## skips it; no sound, no ads and no CrazyGames SDK call (loadingStop, gameplayStart/Stop, requestAd) before `finished`.

var main
var times = {}   # wall-clock ms of the intro's started / finished signals

func before_each():
	Store.clear()
	Ads.call_log.clear()
	Ads.sdk_log.clear()
	Ads.set_mode("sdk")   # off-web the SDK gate only records (Ads.sdk_log), so every page call is observable
	Sfx.played.clear()

func after_each():
	Ads.hold(false)
	Sfx.set_reason("intro", false)
	Ads.set_mode("mock_available")
	Ads.sdk_log.clear()

func _boot() -> void:
	times = {}
	main = load("res://scenes/main.tscn").instantiate()   # play_intro defaults to true
	add_child_autofree(main)
	main.intro.started.connect(func(): times["started"] = Time.get_ticks_msec())
	main.intro.finished.connect(func(): times["finished"] = Time.get_ticks_msec())
	await wait_frames(2)

func _calls() -> Array:
	return Ads.sdk_log.map(func(e): return e.call)

func _screen_pos(n: Control) -> Vector2:
	return main.get_viewport().get_final_transform() * n.get_global_rect().get_center()

func test_intro_plays_first_then_title():
	await _boot()
	assert_not_null(main.intro, "intro instanced at boot")
	assert_true(is_instance_valid(main.intro) and main.intro.is_inside_tree())
	assert_eq(main.intro.layer, 128, "covers every screen")
	assert_false(main.intro_finished)
	assert_true(Ads.held, "SDK/ads held during the intro")
	assert_eq(_calls(), [], "no SDK call yet")
	var intro = main.intro
	var dur: float = intro.get_duration()
	assert_almost_eq(dur, 1.93, 0.05, "1.93 s intro")
	await wait_for_signal(main.intro_done, 6.0)
	assert_true(main.intro_finished, "intro finished on its own")
	# v1.1 keeps the node for one more draw (final frame on screen) and frees it on the next
	# RenderingServer.frame_post_draw. The headless dummy renderer never emits frame_post_draw (checked:
	# 0 in 30 frames), so the free can only be asserted with a real renderer (web smoke test covers it).
	var draws = [0]
	var cb = func(): draws[0] += 1
	RenderingServer.frame_post_draw.connect(cb)
	for k in 20:
		if not is_instance_valid(intro): break
		await wait_frames(1)
	RenderingServer.frame_post_draw.disconnect(cb)
	assert_true(intro == null or not is_instance_valid(intro) or intro._done, "intro done")
	assert_null(main.intro, "main dropped its intro reference")
	if draws[0] > 0:
		assert_false(is_instance_valid(intro), "intro node freed one draw after finished")
	else:
		gut.p("headless: no frame_post_draw, intro free not observable here (verified in the web smoke test)")
	assert_eq(main.screen_name, "title", "title follows the intro")
	var play = main.find_child("PlayButton", true, false)
	assert_not_null(play)
	assert_true(play.is_visible_in_tree(), "title Play button visible after the intro")
	assert_false(Ads.held)
	assert_eq(_calls().count("loadingStop"), 1, "loadingStop exactly once, after the intro")
	for e in Ads.sdk_log:
		assert_true(e.t_ms >= main.intro_finished_ms, "SDK call %s after finished" % e.call)
	assert_false(_calls().has("gameplayStart"), "title is not gameplay")

func _skip_with(ev: InputEvent) -> void:
	await _boot()
	assert_false(main.intro_finished)
	var play = main.find_child("PlayButton", true, false)
	assert_not_null(play, "title built underneath the intro")
	var pos = _screen_pos(play)   # tap right over the Play button underneath
	if ev is InputEventMouseButton or ev is InputEventScreenTouch: ev.position = pos
	if ev is InputEventMouseButton: ev.global_position = pos
	var t0 = Time.get_ticks_msec()
	main.get_tree().root.push_input(ev)
	await wait_frames(2)
	assert_true(main.intro_finished, "skipped by %s" % ev.get_class())
	assert_lt(Time.get_ticks_msec() - t0, 1500, "finished right away, not after the full intro")
	assert_eq(main.screen_name, "title", "the skip tap is consumed: it does not press Play underneath")
	assert_eq(_calls().count("loadingStop"), 1)

func test_touch_tap_skips():
	var ev = InputEventScreenTouch.new(); ev.index = 0; ev.pressed = true
	await _skip_with(ev)

func test_mouse_click_skips():
	var ev = InputEventMouseButton.new(); ev.button_index = MOUSE_BUTTON_LEFT; ev.pressed = true
	await _skip_with(ev)

func test_key_skips():
	var ev = InputEventKey.new(); ev.keycode = KEY_SPACE; ev.physical_keycode = KEY_SPACE; ev.pressed = true
	await _skip_with(ev)

func test_release_and_motion_do_not_skip():
	await _boot()
	var up = InputEventScreenTouch.new(); up.pressed = false
	main.get_tree().root.push_input(up)
	var mv = InputEventMouseMotion.new(); mv.position = Vector2(100, 100)
	main.get_tree().root.push_input(mv)
	await wait_frames(2)
	assert_false(main.intro_finished, "only a press skips")

func test_no_audio_ads_or_sdk_before_finished():
	await _boot()
	assert_true(Sfx.is_muted(), "muted during intro")
	assert_true(Sfx.state.reasons.has("intro"))
	Sfx.play("tap")
	assert_eq(Sfx.playing_count(), 0, "no sound during the intro")
	Ads.set_context("grid")
	Ads.set_context("menu")
	Store.loading_stop()
	assert_eq(_calls(), [], "no gameplayStart/Stop or loadingStop before finished")
	Ads.set_mode("mock_available")
	assert_false(Ads.available(), "no rewarded offers during the intro")
	var ok = await Ads.midgame("intro_test")
	assert_false(ok)
	assert_eq(Ads.call_log.back().result, "blocked_intro")
	for e in Ads.call_log: assert_ne(e.result, "requested", "no ad requested during intro")
	Ads.set_mode("sdk")
	Ads.sdk_log.clear()
	main.intro.skip()
	await wait_frames(1)
	assert_true(main.intro_finished)
	assert_false(Sfx.state.reasons.has("intro"), "sound released after finished")
	assert_false(Ads.held)
	assert_eq(_calls(), ["gameplayStop", "loadingStop"], "menu state re-announced, then loadingStop")
	Ads.set_mode("mock_available")
	assert_true(Ads.available(), "ads available again after the intro")

func test_scene_freed_mid_intro_releases_holds():
	await _boot()
	assert_true(Ads.held)
	remove_child(main); main.free(); main = null
	assert_false(Ads.held, "no stuck hold if the scene goes away mid-intro")
	assert_false(Sfx.state.reasons.has("intro"))

func test_integration_files_and_settings():
	assert_true(ResourceLoader.exists("res://pkd_intro/pkd_intro.tscn"))
	assert_true(ResourceLoader.exists("res://pkd_intro/pkd_frames.res"))
	assert_false(DirAccess.dir_exists_absolute("res://pkd_intro/src_frames"), "src_frames not copied")
	var fr = load("res://pkd_intro/pkd_frames.res")
	assert_eq(fr.frames.size(), 58)
	var navy = Color(0.117647, 0.105882, 0.227451, 1)
	assert_true(ProjectSettings.get_setting("application/boot_splash/bg_color").is_equal_approx(navy))
	assert_eq(ProjectSettings.get_setting("application/boot_splash/image"), "res://pkd_boot_splash_plain.png", "v1.1: plain navy boot splash")
	var splash = load("res://pkd_boot_splash_plain.png").get_image()
	assert_not_null(splash)
	if splash: assert_true(splash.get_pixel(0, 0).is_equal_approx(navy) or splash.get_pixel(0, 0).to_html(false) == "1e1b3a", "plain splash is navy")
	assert_true(ProjectSettings.get_setting("application/boot_splash/fullsize"))
	assert_true(ProjectSettings.get_setting("rendering/environment/defaults/default_clear_color").is_equal_approx(navy))
	var head = FileAccess.get_file_as_string("res://web/head_include.html")
	assert_string_contains(head, "background-color: #1E1B3A !important")
	assert_string_contains(head, "#status-splash { visibility: hidden !important; }", "v1.1: no logo on the HTML loader")
	assert_false(head.contains("object-fit: contain"), "v1.0 logo-splash CSS removed")
	assert_false(head.to_lower().contains("#bfe3ef"), "old sky loader colour gone")
	var presets = FileAccess.get_file_as_string("res://export_presets.cfg")
	assert_false(presets.to_lower().contains("#bfe3ef"), "both presets carry the navy head_include")
	assert_eq(presets.count("background-color: #1E1B3A !important"), 2)
	assert_eq(presets.count("#status-splash { visibility: hidden !important; }"), 2)

# ---- v1.1: wall-clock playback, `started`, hard cap ----

func test_v11_started_then_finished_on_wall_clock():
	await _boot()
	await wait_for_signal(main.intro_done, 6.0)
	assert_true(times.has("started"), "started fired")
	assert_true(times.has("finished"), "finished fired")
	if times.has("started") and times.has("finished"):
		var len_s = (times.finished - times.started) / 1000.0
		gut.p("headless visible -> finished: %.2f s" % len_s)
		assert_between(len_s, 1.85, 2.6, "about 1.93 s of wall clock from the first visible frame, never past the cap (+1 frame)")
	assert_eq(_calls().count("loadingStop"), 1)
	for e in Ads.sdk_log:
		assert_true(e.t_ms >= times.finished, "SDK call %s only after finished" % e.call)

func test_v11_hard_cap_shows_final_frame_and_finishes():
	await _boot()
	var intro = main.intro
	assert_eq(intro.MAX_SECONDS, 2.5)
	if not times.has("started"): await wait_for_signal(intro.started, 2.0)
	assert_false(main.intro_finished)
	# Simulate a stall: the clock says 3 s have passed since the first visible frame (past the 2.5 s cap).
	intro._start_ms = Time.get_ticks_msec() - 3000
	await wait_frames(1)
	assert_true(main.intro_finished, "finished on the first frame past the cap")
	assert_eq(intro._shown, intro.FRAMES.frames.size() - 1, "final PKD frame on screen when it ends")
	assert_false(Ads.held)
	assert_false(Sfx.state.reasons.has("intro"))

func test_v11_slow_device_skips_frames_and_stays_bounded():
	await _boot()
	var stall = func():   # ~350 ms of main-thread work every frame (about 3 fps)
		var t0 = Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 350: pass
	main.get_tree().process_frame.connect(stall)
	await wait_for_signal(main.intro_done, 8.0)
	main.get_tree().process_frame.disconnect(stall)
	assert_true(main.intro_finished)
	if times.has("started") and times.has("finished"):
		var len_s = (times.finished - times.started) / 1000.0
		gut.p("headless 3 fps visible -> finished: %.2f s" % len_s)
		assert_lt(len_s, 2.5 + 0.8, "wall clock: a slow device doesn't stretch the intro (v1.0 counted each long frame as 1/30 s)")
