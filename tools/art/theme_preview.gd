## Visual smoke test for the art kit (not shipped; tools/ is export-excluded).
## Run: xvfb-run -a godot --path . --resolution 720x1280 -s tools/art/theme_preview.gd -- out=/tmp/preview.png
extends SceneTree

const P = preload("res://assets/art/art_palette.gd")

func _tex(p: String) -> Texture2D:
	return load(p)

func _initialize() -> void:
	get_root().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	var root := Control.new()
	root.theme = load(P.THEME_PATH)
	root.size = Vector2(720, 1280)
	get_root().add_child(root)
	var bg := TextureRect.new(); bg.texture = _tex("res://assets/art/harbour/harbour_bg_portrait.webp")
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.set_anchors_preset(Control.PRESET_FULL_RECT); root.add_child(bg)
	var placements = [["lighthouse", true, Vector2(553, 280), 0.33], ["boats", true, Vector2(300, 640), 0.42],
		["dock", false, Vector2(480, 760), 0.38], ["cafe", true, Vector2(10, 690), 0.5], ["flowers", true, Vector2(330, 900), 0.4]]
	for pl in placements:
		var s := TextureRect.new(); s.texture = _tex(P.task_sprite_path(pl[0], pl[1]))
		s.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; s.size = s.texture.get_size() * pl[3]; s.position = pl[2]
		root.add_child(s)
	var bar := PanelContainer.new(); bar.theme_type_variation = "PanelTopBar"; bar.position = Vector2(0, 0); bar.size = Vector2(720, 96)
	root.add_child(bar)
	var h := HBoxContainer.new(); h.add_theme_constant_override("separation", 12); bar.add_child(h)
	var back := Button.new(); back.theme_type_variation = "ButtonIconFlat"; back.icon = _tex(P.icon_path("back")); h.add_child(back)
	for pill in [["star", "24"], ["coin", "120"]]:
		var pc := PanelContainer.new(); pc.theme_type_variation = "PanelPill"; h.add_child(pc)
		var ph := HBoxContainer.new(); pc.add_child(ph)
		var ic := TextureRect.new(); ic.texture = _tex(P.icon_path(pill[0], "ink")); ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; ic.custom_minimum_size = Vector2(36, 36); ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; ph.add_child(ic)
		var pl2 := Label.new(); pl2.theme_type_variation = "LabelPill"; pl2.text = pill[1]; ph.add_child(pl2)
	var sp := Control.new(); sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL; h.add_child(sp)
	for icn in ["sound_on", "settings"]:
		var b := Button.new(); b.theme_type_variation = "ButtonIconFlat"; b.icon = _tex(P.icon_path(icn)); h.add_child(b)
	var panel := PanelContainer.new(); panel.position = Vector2(40, 1000); panel.size = Vector2(640, 250); root.add_child(panel)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 12); panel.add_child(v)
	var t := Label.new(); t.theme_type_variation = "LabelHeader"; t.text = "Harbour tasks"; v.add_child(t)
	var r1 := HBoxContainer.new(); r1.add_theme_constant_override("separation", 10); v.add_child(r1)
	var play := Button.new(); play.text = "Play Level 7"; r1.add_child(play)
	var buy := Button.new(); buy.theme_type_variation = "ButtonSecondary"; buy.text = "Buy  3"; buy.icon = _tex(P.icon_path("star", "cream")); r1.add_child(buy)
	var lk := Button.new(); lk.theme_type_variation = "ButtonLocked"; lk.text = "Locked"; lk.icon = _tex(P.icon_path("lock")); r1.add_child(lk)
	var r2 := HBoxContainer.new(); r2.add_theme_constant_override("separation", 10); v.add_child(r2)
	for k in 3:
		var tile := Button.new(); tile.theme_type_variation = "ButtonTile"; tile.text = str(k + 1); tile.custom_minimum_size = Vector2(88, 88); r2.add_child(tile)
	var chip := Button.new(); chip.theme_type_variation = "ButtonChip"; chip.text = "Notes"; chip.icon = _tex(P.icon_path("notes")); chip.toggle_mode = true; chip.button_pressed = true; r2.add_child(chip)
	var hint := Button.new(); hint.theme_type_variation = "ButtonIcon"; hint.icon = _tex(P.icon_path("hint", "cream")); r2.add_child(hint)
	var title := Label.new(); title.theme_type_variation = "LabelTitle"; title.text = "Sudoku Dash"; title.position = Vector2(170, 110)
	title.add_theme_color_override("font_color", P.PANEL_CREAM); title.add_theme_color_override("font_outline_color", P.TEXT_INK); title.add_theme_constant_override("outline_size", 12)
	root.add_child(title)
	for i in 6: await process_frame
	await RenderingServer.frame_post_draw
	var out := "/tmp/theme_preview.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4)
	get_root().get_texture().get_image().save_png(out)
	print("preview saved ", out)
	quit()
