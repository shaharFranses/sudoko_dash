extends GutTest
## Staging cheat button (debug builds only, lives in debug/qa_hooks.gd): visible on grid screens only,
## one press solves the grid and lands on results.

var main

func before_each():
	Store.clear()
	Ads.set_mode("mock_available")
	Dbg.clock_offset_ms = 0
	main = load("res://scenes/main.tscn").instantiate()
	main.play_intro = false
	add_child_autofree(main)
	await wait_frames(2)

func _btn() -> Button:
	return Dbg.hooks.find_child("CheatSolveButton", true, false) if Dbg.hooks else null

func test_cheat_button_only_on_grid_and_solves_level():
	assert_true(Dbg.enabled, "tests run as a debug build")
	var b = _btn()
	assert_not_null(b)
	await wait_frames(2)
	assert_false(b.visible, "hidden on title")
	main.start_level(0)
	await wait_frames(2)
	assert_true(b.visible, "shown on grid")
	assert_null(main.find_child("CheatSolveButton", true, false), "not part of main's UI tree")
	b.pressed.emit()
	await wait_frames(2)
	assert_eq(main.screen_name, "results")
	assert_eq(main.profile.path_next, 1, "level 1 cleared")
	assert_false(b.visible, "hidden on results")
