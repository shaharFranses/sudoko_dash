extends GutTest
## Mobile / responsive layout (game/ui_layout.gd + main.gd compact layout). Headless: dpr 1, so the window
## size in px stands in for the page's CSS size.

const UiLayout = preload("res://game/ui_layout.gd")
const SIZES = [Vector2i(360, 640), Vector2i(390, 844), Vector2i(412, 915), Vector2i(768, 1024), Vector2i(844, 390)]
var main
var old_size: Vector2i

func before_each():
	Store.clear()
	Ads.call_log.clear()
	Ads.set_mode("mock_available")
	old_size = get_tree().root.size
	main = load("res://scenes/main.tscn").instantiate()
	add_child_autofree(main)
	await wait_frames(2)

func after_each():
	Sfx.set_reason("user", false)
	get_tree().root.size = old_size
	await wait_frames(3)

func _resize(sz: Vector2i) -> void:
	get_tree().root.size = sz
	await wait_frames(4)

func _visible_buttons() -> Array:
	var out = []
	for b in main.root.find_children("*", "Button", true, false):
		if not b.is_queued_for_deletion() and b.is_visible_in_tree(): out.append(b)
	return out

func _css(v: float) -> float:
	return v / main.units_per_css

# ---------------- pure breakpoints ----------------
func test_logical_size_breakpoints():
	assert_eq(UiLayout.logical_size(Vector2(360, 640)), Vector2(720, 1280), "art kit portrait base")
	assert_eq(UiLayout.logical_size(Vector2(390, 844)), Vector2(720, 1558))
	assert_eq(UiLayout.logical_size(Vector2(412, 915)), Vector2(720, 1599))
	assert_eq(UiLayout.logical_size(Vector2(768, 1024)), Vector2(945, 1260), "tablet: wider base, same 88-unit buttons (71 CSS px)")
	assert_eq(UiLayout.logical_size(Vector2(844, 390)), Vector2(1039, 480))
	for desk in [Vector2(1280, 800), Vector2(1280, 720), Vector2(1366, 768), Vector2(1920, 1080), Vector2(1024, 768)]:
		assert_eq(UiLayout.logical_size(desk), Vector2.ZERO, "%s keeps the desktop 1280x720 base" % desk)
	assert_true(UiLayout.is_compact(Vector2(720, 1280)))
	assert_false(UiLayout.is_compact(Vector2(1039, 480)))
	assert_false(UiLayout.is_compact(Vector2(1280, 800)))

func test_min_button_is_a_touch_target_at_every_mobile_size():
	for css in SIZES:
		var upc = UiLayout.units_per_css(Vector2(css))
		var min_btn = UiLayout.COMPACT_MIN_BTN if css.y > css.x else 56
		assert_gte(min_btn / upc, UiLayout.MIN_TOUCH_CSS, "%s: %d units = %.1f CSS px" % [css, min_btn, min_btn / upc])
	assert_almost_eq(UiLayout.units_per_css(Vector2(1280, 800)), 1.0, 0.001, "desktop 1280x800: 1 unit = 1 px")
	assert_eq(UiLayout.COMPACT_MIN_BTN, 88, "matches ArtPalette.MIN_TOUCH (88 at a 720-wide portrait base)")

func test_pad_columns():
	assert_eq(UiLayout.pad_columns(6, true), 6)
	assert_eq(UiLayout.pad_columns(9, true), 5)
	assert_eq(UiLayout.pad_columns(9, false), 3)
	assert_eq(UiLayout.pad_columns(6, false), 3)

# ---------------- grid screen at each size ----------------
func _check_grid_screen(sz: Vector2i, lv: int) -> void:
	main.start_level(lv)
	await wait_frames(3)
	var tag = "%s L%d" % [sz, lv + 1]
	var vp = main.get_viewport_rect().size
	var n = main.board.size
	assert_eq(main.compact, sz.y > sz.x, tag + " compact")
	# every action is on screen: digits, notes, erase, undo, hint, back
	var need = ["NotesButton", "EraseButton", "UndoButton", "HintButton", "BackButton"]
	for d in range(1, n + 1): need.append("Digit%d" % d)
	for nm in need:
		var nd = main.root.find_child(nm, true, false)
		assert_not_null(nd, tag + " has " + nm)
		if nd: assert_true(nd.is_visible_in_tree(), tag + " " + nm + " visible")
	for b in _visible_buttons():
		var r: Rect2 = b.get_global_rect()
		assert_gte(_css(r.size.y), UiLayout.MIN_TOUCH_CSS - 0.5, "%s %s height %.1f CSS px" % [tag, b.name, _css(r.size.y)])
		assert_gte(_css(r.size.x), UiLayout.MIN_TOUCH_CSS - 0.5, "%s %s width %.1f CSS px" % [tag, b.name, _css(r.size.x)])
		if main.compact:
			assert_gte(r.size.y, UiLayout.COMPACT_MIN_BTN - 0.5, "%s %s >= 88 units on the 720 base" % [tag, b.name])
			assert_gte(r.size.x, UiLayout.COMPACT_MIN_BTN - 0.5, "%s %s width >= 88 units" % [tag, b.name])
		assert_true(Rect2(Vector2.ZERO, vp).grow(0.5).encloses(r), "%s %s inside viewport %s" % [tag, b.name, r])
	var gv = main.grid_view
	var tl = gv.get_global_rect().position + gv.origin()
	var span = gv.cell_px() * n
	assert_true(Rect2(Vector2(4, 0), vp - Vector2(8, 4)).encloses(Rect2(tl, Vector2(span, span))), tag + " grid fully inside")
	var pad: Control = main.root.find_child("DigitPad", true, false)
	if main.compact:
		assert_lte(tl.y + span, pad.get_global_rect().position.y, tag + " grid above the pad")
		if sz.y >= 1.6 * sz.x:
			assert_gte(span, 0.9 * (vp.x - 28), tag + " grid fills the width (%.0f of %.0f)" % [span, vp.x])
		else:   # 360x640 / tablets: height-limited
			assert_gte(span, 0.7 * (vp.x - 28), tag + " grid (%.0f of %.0f)" % [span, vp.x])
		assert_false(main.status_label.visible, tag + " no keyboard help line in portrait")
	else:
		assert_lte(tl.x + span, pad.get_global_rect().position.x, tag + " grid left of the pad")
	# readable text: objective / mistakes >= 14 CSS px; 9x9 notes >= 11 CSS px
	for lbl in [main.objective_label, main.mistakes_label]:
		var fs = lbl.get_theme_font_size("font_size")
		assert_gte(_css(fs), 14.0, "%s %s font %.1f CSS px" % [tag, lbl.name, _css(fs)])
	if n == 9:
		var notes_px = _css(int(gv.cell_px() / 3.0))
		assert_gte(notes_px, 11.0, "%s notes %.1f CSS px" % [tag, notes_px])
	# hint panel fits
	main._open_hint_panel()
	await wait_frames(3)
	var panel: Control = main.overlay.find_children("*", "PanelContainer", true, false)[0]
	assert_true(Rect2(Vector2.ZERO, vp).encloses(panel.get_global_rect()), "%s hint panel inside (%s)" % [tag, panel.get_global_rect()])
	for b in main.overlay.find_children("*", "Button", true, false):
		assert_gte(_css(b.get_global_rect().size.y), UiLayout.MIN_TOUCH_CSS - 0.5, "%s panel %s" % [tag, b.text])
	main._close_overlay()

func test_grid_screens_fit_every_mobile_size():
	for sz in SIZES:
		await _resize(sz)
		await _check_grid_screen(sz, 0)    # L1 6x6
		await _check_grid_screen(sz, 10)   # L11 9x9
		main._leave_grid()

func test_menus_fit_every_mobile_size():
	for sz in SIZES:
		await _resize(sz)
		var vp = main.get_viewport_rect().size
		for scr in ["title", "harbour", "settings", "results"]:
			match scr:
				"title": main._build_title()
				"harbour": main.show_harbour()
				"settings": main.show_settings("harbour")
				"results":
					main.start_level(1)
					await wait_frames(1)
					Dbg.hooks.solve_current() if Dbg.hooks else null
			await wait_frames(3)
			assert_eq(main.screen_name, scr, "%s screen" % sz)
			for b in _visible_buttons():
				var r: Rect2 = b.get_global_rect()
				assert_gte(_css(r.size.y), UiLayout.MIN_TOUCH_CSS - 0.5, "%s %s %s height %.1f" % [sz, scr, b.text, _css(r.size.y)])
				assert_gte(r.position.x, -0.5, "%s %s %s left inside" % [sz, scr, b.text])
				assert_lte(r.end.x, vp.x + 0.5, "%s %s %s right inside (%.0f > %.0f)" % [sz, scr, b.text, r.end.x, vp.x])
				if scr != "harbour":   # harbour list scrolls vertically
					assert_lte(r.end.y, vp.y + 0.5, "%s %s %s bottom inside" % [sz, scr, b.text])

# ---------------- live resize / rotation ----------------
func test_rotation_mid_run_keeps_the_run_and_open_panel():
	await _resize(Vector2i(390, 844))
	main.start_level(13)   # a timed (Beat the Tide) or any level: state must survive
	await wait_frames(2)
	var b = main.board
	var i = b.cells.find(0)
	main._on_cell(i); main._on_digit(b.solution[i])
	var j = b.cells.find(0)
	main._on_cell(j)
	main._toggle_notes()
	main.elapsed_ms = 4321
	var snap = b.snapshot()
	main._open_hint_panel()
	for sz in [Vector2i(844, 390), Vector2i(360, 640), Vector2i(1280, 800)]:
		await _resize(sz)
		assert_eq(main.screen_name, "grid", "%s still on the grid" % sz)
		assert_eq(main.board, b, "%s same board object" % sz)
		assert_eq(main.board.snapshot(), snap, "%s board unchanged" % sz)
		assert_eq(main.grid_view.selected, j, "%s selection kept" % sz)
		assert_true(main.notes_mode, "%s notes mode kept" % sz)
		assert_not_null(main.overlay, "%s hint panel still open" % sz)
		if main.overlay: assert_eq(str(main.overlay.name), "HintPanel")
		assert_eq(Ads.context, "grid_panel", "%s still paused" % sz)
		assert_eq(main.elapsed_ms, 4321, "%s timer not reset (paused under the panel)" % sz)
	main._close_overlay()
	assert_eq(Ads.context, "grid")

func test_rotation_keeps_hint_highlight():
	await _resize(Vector2i(360, 640))
	main.start_level(10)
	await wait_frames(2)
	main.profile.tokens = 3
	main._pay_hint("teach", "token")
	var cells = main.grid_view.teach_cells.duplicate()
	var txt = main.teach_label.text
	assert_ne(txt, "")
	await _resize(Vector2i(844, 390))
	assert_eq(main.grid_view.teach_cells, cells)
	assert_eq(main.teach_label.text, txt)

func test_results_rebuild_on_resize_does_not_rerun_the_offer():
	await _resize(Vector2i(390, 844))
	main.start_level(1)
	await wait_frames(1)
	Dbg.hooks.solve_current()
	await wait_frames(2)
	assert_eq(main.screen_name, "results")
	var calls = Ads.call_log.size()
	var txt = main.root.find_child("ResultsRewards", true, false).text
	await _resize(Vector2i(844, 390))
	assert_eq(main.screen_name, "results")
	assert_eq(main.root.find_child("ResultsRewards", true, false).text, txt)
	assert_eq(Ads.call_log.size(), calls, "no new ad call from a relayout")

func test_desktop_1280x800_unchanged():
	await _resize(Vector2i(1280, 800))
	assert_eq(get_tree().root.content_scale_size, Vector2i(1280, 720))
	assert_eq(main.get_viewport_rect().size, Vector2(1280, 800))
	main.start_level(10)
	await wait_frames(3)
	assert_false(main.compact)
	var hint = main.root.find_child("HintButton", true, false)
	var back = main.root.find_child("BackButton", true, false)
	assert_eq(hint.get_parent(), back.get_parent(), "Hint stays in the top bar on desktop")
	assert_eq(back.get_theme_font_size("font_size"), 26)
	assert_eq(int(hint.custom_minimum_size.y), 60)
	assert_eq(main.root.find_child("DigitPad", true, false).columns, 3)
	assert_true(main.status_label.visible)

func test_phone_resize_sets_logical_viewport_and_back():
	await _resize(Vector2i(360, 640))
	assert_eq(get_tree().root.content_scale_size, Vector2i(720, 1280))
	assert_almost_eq(main.units_per_css, 2.0, 0.001)
	await _resize(Vector2i(1280, 800))
	assert_eq(get_tree().root.content_scale_size, Vector2i(1280, 720))

# ---------------- input ----------------
func test_one_tap_is_one_action():
	await _resize(Vector2i(360, 640))
	main.start_level(10)
	await wait_frames(3)
	var b = main.board
	var i = b.cells.find(0)
	main._toggle_notes()
	main._on_digit(1)   # digit lock 1 (no cell selected yet)
	await wait_frames(2)
	assert_eq(main.digit_lock, 1)
	var gv = main.grid_view
	var pos = gv.origin() + Vector2(i % b.size + 0.5, i / b.size + 0.5) * gv.cell_px()
	# a real touch delivers both: the screen touch and the emulated left click
	var t = InputEventScreenTouch.new(); t.pressed = true; t.position = pos
	gv._gui_input(t)
	var m = InputEventMouseButton.new(); m.button_index = MOUSE_BUTTON_LEFT; m.pressed = true; m.position = pos
	gv._gui_input(m)
	assert_eq(b.notes[i] & 1, 1, "note 1 toggled on exactly once")

# ---------------- settings ----------------
func test_settings_sound_toggle_persists():
	main.show_settings("title")
	assert_eq(main.screen_name, "settings")
	main._toggle_sound()
	assert_false(main.profile.sound_on)
	assert_true(Sfx.state.reasons.has("user"))
	assert_false(bool(Store.load_data().get("sound_on", true)), "saved")
	main._toggle_sound()
	assert_true(main.profile.sound_on)
	assert_false(Sfx.state.reasons.has("user"))

func test_compact_tool_labels_fit():
	await _resize(Vector2i(360, 640))
	for lv in [0, 10]:
		main.start_level(lv)
		await wait_frames(3)
		for nm in ["NotesButton", "EraseButton", "UndoButton", "HintButton"]:
			var b: Button = main.root.find_child(nm, true, false)
			var font = b.get_theme_font("font")
			var tw = font.get_string_size("Notes: OFF" if nm == "NotesButton" else b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, b.get_theme_font_size("font_size")).x
			assert_lt(tw + 8, b.size.x, "L%d %s label fits (%.0f in %.0f)" % [lv + 1, nm, tw, b.size.x])
