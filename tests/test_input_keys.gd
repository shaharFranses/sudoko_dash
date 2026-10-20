extends GutTest
## Keyboard handling: physical digits (AZERTY), modifiers, key repeat, first arrow.

var main

func before_each():
	Store.clear()
	main = load("res://scenes/main.tscn").instantiate()
	add_child_autofree(main)
	await wait_frames(2)
	main.profile.path_next = 5   # 6x6
	main.start_path_grid()

func _key(keycode, physical = KEY_NONE, echo = false, ctrl = false, meta = false, alt = false) -> InputEventKey:
	var k = InputEventKey.new()
	k.pressed = true; k.keycode = keycode; k.physical_keycode = physical
	k.echo = echo; k.ctrl_pressed = ctrl; k.meta_pressed = meta; k.alt_pressed = alt
	main._unhandled_input(k)
	return k

func _empty() -> int:
	return main.board.cells.find(0)

func _select(i):
	main.grid_view.selected = i

func test_first_arrow_selects_top_left():
	main.grid_view.selected = -1
	_key(KEY_RIGHT)
	assert_eq(main.grid_view.selected, 0)
	_key(KEY_RIGHT)
	assert_eq(main.grid_view.selected, 1)

func test_first_arrow_any_direction_selects_top_left():
	for k in [KEY_LEFT, KEY_UP, KEY_DOWN]:
		main.grid_view.selected = -1
		_key(k)
		assert_eq(main.grid_view.selected, 0)

func test_azerty_top_row_digit_by_physical_key():
	var i = _empty(); _select(i)
	var d = main.board.solution[i]
	# AZERTY: physical "1" key produces '&' (keycode KEY_AMPERSAND) etc. without shift
	var azerty = {1: KEY_AMPERSAND, 2: 0xE9, 3: KEY_QUOTEDBL, 4: KEY_APOSTROPHE, 5: KEY_PARENLEFT, 6: KEY_MINUS}
	_key(azerty[d], KEY_0 + d)
	assert_eq(main.board.cells[i], d)

func test_numpad_digit():
	var i = _empty(); _select(i)
	var d = main.board.solution[i]
	_key(KEY_KP_0 + d, KEY_KP_0 + d)
	assert_eq(main.board.cells[i], d)

func test_ctrl_or_cmd_or_alt_digit_ignored():
	var i = _empty(); _select(i)
	var d = main.board.solution[i]
	var before = main.board.snapshot()
	_key(KEY_0 + d, KEY_0 + d, false, true)
	_key(KEY_0 + d, KEY_0 + d, false, false, true)
	_key(KEY_0 + d, KEY_0 + d, false, false, false, true)
	assert_eq(main.board.snapshot(), before)
	assert_eq(main.digit_lock, 0)

func test_key_repeat_does_not_place_or_toggle():
	var i = _empty(); _select(i)
	var wrong = (main.board.solution[i] % 6) + 1
	_key(KEY_0 + wrong, KEY_0 + wrong, true)
	assert_eq(main.board.cells[i], 0)
	assert_eq(main.board.mistakes, 0, "auto-repeat never costs a mistake")
	_key(KEY_N, KEY_N, true)
	assert_false(main.notes_mode)
	main.board.place(i, main.board.solution[i])
	_key(KEY_BACKSPACE, KEY_BACKSPACE, true)
	assert_eq(main.board.cells[i], main.board.solution[i])

func test_arrow_repeat_still_moves():
	_select(0)
	_key(KEY_RIGHT, KEY_RIGHT, true)
	assert_eq(main.grid_view.selected, 1)

func test_digit_beyond_grid_size_ignored():
	var i = _empty(); _select(i)
	var before = main.board.snapshot()
	_key(KEY_9, KEY_9)
	assert_eq(main.board.snapshot(), before)

func test_ctrl_z_still_undoes():
	var i = _empty(); _select(i)
	var d = main.board.solution[i]
	_key(KEY_0 + d, KEY_0 + d)
	_key(KEY_Z, KEY_Z, false, true)
	assert_eq(main.board.cells[i], 0)
