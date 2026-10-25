extends GutTest
## Art kit v1 integration (art/integrate-v1): theme on every screen, harbour art by aspect, task sprite swap.

const HarbourView = preload("res://ui/harbour_view.gd")
var main

func before_each():
	Store.clear()
	Ads.set_mode("mock_available")
	main = load("res://scenes/main.tscn").instantiate()
	add_child_autofree(main)
	await wait_frames(2)

func test_art_theme_applied_to_the_ui():
	assert_eq(main.theme.resource_path, "res://assets/art/theme/sudoku_dash_theme.tres")
	var play: Button = main.root.find_child("PlayButton", true, false)
	assert_eq(play.get_theme_font("font").resource_path, ArtPalette.FONT_UI_BOLD, "buttons use Atkinson Hyperlegible Next Bold")
	assert_eq(main.root.find_child("SettingsButton", true, false).theme_type_variation, "ButtonChip")

func test_harbour_art_picked_by_aspect():
	assert_eq(HarbourView.pick(Vector2(720, 700)), "portrait")
	assert_eq(HarbourView.pick(Vector2(810, 800)), "portrait")
	assert_eq(HarbourView.pick(Vector2(1200, 600)), "landscape")

func test_harbour_view_covers_and_keeps_every_task_on_screen():
	for sz in [Vector2(720, 566), Vector2(720, 691), Vector2(569, 470), Vector2(810, 790), Vector2(1200, 500)]:
		var hv = HarbourView.new(); hv.profile = main.profile
		add_child_autofree(hv)
		hv.size = sz
		var vt = hv.view_transform()
		var lay: Dictionary = HarbourView.LAYOUT[vt.kind]
		for id in lay:
			for st in [false, true]:
				var r: Rect2 = hv._rect_of(id, lay, st)
				var on = Rect2(vt.offset + r.position * vt.scale, r.size * vt.scale)
				assert_true(Rect2(Vector2.ZERO, sz).grow(0.5).encloses(on), "%s %s sprite on screen at %s" % [id, st, sz])

func test_task_sprite_swaps_when_bought():
	main.profile.stars = 10
	main.show_harbour()
	await wait_frames(2)
	var hv = main.root.find_child("HarbourView", true, false)
	assert_eq(hv.state_of("dock"), "unrestored")
	main._buy_task("dock")
	await wait_frames(2)
	hv = main.root.find_child("HarbourView", true, false)
	assert_eq(hv.state_of("dock"), "restored")
	assert_eq(hv.reveal_id, "dock", "fresh restore fades in")
