extends GutTest
## Story intro (first Play) and the Classic 9x9 difficulty submenu.

const Profile = preload("res://game/profile.gd")
var main

func before_each():
	Store.clear()
	main = load("res://scenes/main.tscn").instantiate()
	main.play_intro = false   # PKD intro covered by test_pkd_intro.gd
	add_child_autofree(main)
	await wait_frames(2)

func test_first_play_shows_story_then_harbour():
	assert_false(main.profile.story_seen)
	main._on_play()
	assert_eq(main.screen_name, "story")
	assert_eq(main.story_page, 0)
	for i in main.STORY.size() - 1:
		main._story_next()
		assert_eq(main.story_page, i + 1)
	assert_null(main.root.find_child("StorySkip", true, false), "no Skip on the last page")
	main._story_next()
	assert_eq(main.screen_name, "harbour")
	assert_true(main.profile.story_seen)
	assert_true(bool(Store.load_data().get("story_seen", false)), "saved")
	main._build_title()
	main._on_play()
	assert_eq(main.screen_name, "harbour", "second Play goes straight to the Harbour")

func test_skip_marks_seen():
	main._on_play()
	main._story_done()
	assert_eq(main.screen_name, "harbour")
	assert_true(main.profile.story_seen)

func test_story_replay_from_title():
	main.profile.story_seen = true
	assert_not_null(main.root.find_child("StoryButton", true, false))
	main.show_story(0)
	assert_eq(main.screen_name, "story")

func test_story_survives_relayout():
	main.show_story(1)
	main._relayout()
	assert_eq(main.screen_name, "story")
	assert_eq(main.story_page, 1)

func test_old_saves_with_progress_skip_story():
	var p = Profile.new()
	var d = p.to_dict(); d.erase("story_seen")
	p.from_dict(d)
	assert_false(p.story_seen, "fresh save: story pending")
	d.stars_earned = 3
	p.from_dict(d)
	assert_true(p.story_seen, "existing player: no story forced on them")

func test_classic_menu_starts_picked_tier():
	main.show_harbour()
	assert_not_null(main.root.find_child("ClassicButton", true, false))
	main.show_classic_menu()
	assert_eq(main.screen_name, "classic")
	(main.root.find_child("Classic4", true, false) as Button).pressed.emit()
	await wait_frames(2)
	assert_eq(main.screen_name, "grid")
	assert_eq(main.grid_meta.mode, "classic")
	assert_eq(main.grid_meta.tier, 4)
	assert_eq(main.profile.classic_tier, 4)
	assert_eq(main._grid_title(), "Classic Expert")

func test_classic_back_returns_to_harbour():
	main.show_classic_menu()
	main._relayout()
	assert_eq(main.screen_name, "classic")
	(main.root.find_child("ClassicBack", true, false) as Button).pressed.emit()
	await wait_frames(2)
	assert_eq(main.screen_name, "harbour")
