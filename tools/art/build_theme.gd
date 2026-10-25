## Builds res://assets/art/theme/sudoku_dash_theme.tres from ArtPalette.
## Run: godot --headless --path . -s tools/art/build_theme.gd
## Layout-agnostic: only colours, fonts, corner radii, margins. No sizes/anchors.
extends SceneTree

const P = preload("res://assets/art/art_palette.gd")
const BTN_MH = 14
const BTN_MV = 8

func _sb(bg: Color, radius: int = 18, border: Color = Color(0, 0, 0, 0), bw: int = 0, shadow: bool = true, mh: int = 24, mv: int = 16) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.corner_detail = 8
	s.anti_aliasing = true
	if bw > 0:
		s.border_color = border
		s.set_border_width_all(bw)
	if shadow:
		s.shadow_color = P.SHADOW
		s.shadow_size = 6
		s.shadow_offset = Vector2(0, 3)
	s.content_margin_left = mh; s.content_margin_right = mh
	s.content_margin_top = mv; s.content_margin_bottom = mv
	return s

func _focus(radius: int = 18) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.draw_center = false
	s.set_corner_radius_all(radius + 4)
	s.border_color = P.STAR_GOLD
	s.set_border_width_all(4)
	s.expand_margin_left = 4; s.expand_margin_right = 4; s.expand_margin_top = 4; s.expand_margin_bottom = 4
	return s

func _button(t: Theme, type: String, n: Color, h: Color, p: Color, fc: Color, radius: int = 18, border: Color = Color(0, 0, 0, 0), bw: int = 0) -> void:
	# Compact content margins (14 x 8): the game sets its own min sizes; wide margins would clip labels
	# in the 4-up portrait tool row.
	t.set_stylebox("normal", type, _sb(n, radius, border, bw, true, BTN_MH, BTN_MV))
	t.set_stylebox("hover", type, _sb(h, radius, border, bw, true, BTN_MH, BTN_MV))
	t.set_stylebox("pressed", type, _sb(p, radius, border, bw, false, BTN_MH, BTN_MV))
	t.set_stylebox("hover_pressed", type, _sb(p, radius, border, bw, false, BTN_MH, BTN_MV))
	t.set_stylebox("disabled", type, _sb(P.BTN_DISABLED, radius, P.GRID_LINE_THIN, 2, false, BTN_MH, BTN_MV))
	t.set_stylebox("focus", type, _focus(radius))
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		t.set_color(c, type, fc)
	t.set_color("font_disabled_color", type, P.TEXT_INK)
	for c in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_hover_pressed_color", "icon_focus_color"]:
		t.set_color(c, type, fc)
	t.set_color("icon_disabled_color", type, P.TEXT_INK)
	t.set_constant("h_separation", type, 12)
	t.set_constant("icon_max_width", type, 48)
	# Type variations do NOT inherit font/font_size from "Button" in this theme (Godot falls back to the theme
	# default font), so every button type gets the bold UI font explicitly.
	t.set_font("font", type, load(P.FONT_UI_BOLD))
	t.set_font_size("font_size", type, 30)

func _initialize() -> void:
	var t := Theme.new()
	var ui_r: Font = load(P.FONT_UI_REGULAR)
	var ui_m: Font = load(P.FONT_UI_MEDIUM)
	var ui_b: Font = load(P.FONT_UI_BOLD)
	var d_sb: Font = load(P.FONT_DISPLAY_SEMIBOLD)
	var d_b: Font = load(P.FONT_DISPLAY_BOLD)
	t.default_font = ui_r
	t.default_font_size = 28

	# --- Buttons -------------------------------------------------------------
	_button(t, "Button", P.ACCENT_TEAL, P.ACCENT_TEAL_HOVER, P.ACCENT_TEAL_PRESSED, P.PANEL_CREAM)
	t.set_font("font", "Button", ui_b)
	t.set_font_size("font_size", "Button", 30)

	t.set_type_variation("ButtonSecondary", "Button")
	_button(t, "ButtonSecondary", P.ACCENT_TERRACOTTA, P.ACCENT_TERRACOTTA_HOVER, P.ACCENT_TERRACOTTA_PRESSED, P.PANEL_CREAM)

	# Locked: always looks disabled even if clickable (shows "needs X stars"); pair with icon_lock_ink.
	t.set_type_variation("ButtonLocked", "Button")
	_button(t, "ButtonLocked", P.BTN_DISABLED, P.BTN_DISABLED, P.PANEL_CREAM_PRESSED, P.TEXT_INK, 18, P.DIGIT_NOTES, 2)

	# Keypad / number tiles: cream with ink digits (bold), teal border on press.
	t.set_type_variation("ButtonTile", "Button")
	_button(t, "ButtonTile", P.PANEL_CREAM, P.HL_PEER, P.HL_SELECTED, P.TEXT_INK, 16, P.GRID_LINE_THIN, 2)
	t.set_font_size("font_size", "ButtonTile", 44)

	# Chips / toggles (tiers, Notes ON/OFF): use toggle_mode; pressed = teal.
	t.set_type_variation("ButtonChip", "Button")
	_button(t, "ButtonChip", P.PANEL_CREAM, P.HL_PEER, P.ACCENT_TEAL, P.TEXT_INK, 24, P.ACCENT_TEAL, 2)
	t.set_color("font_pressed_color", "ButtonChip", P.PANEL_CREAM)
	t.set_color("font_hover_pressed_color", "ButtonChip", P.PANEL_CREAM)
	t.set_color("icon_pressed_color", "ButtonChip", P.PANEL_CREAM)
	t.set_font_size("font_size", "ButtonChip", 26)

	# Round icon buttons (hint, settings, sound, undo, erase, back): set icon, no text.
	t.set_type_variation("ButtonIcon", "Button")
	_button(t, "ButtonIcon", P.ACCENT_TEAL, P.ACCENT_TEAL_HOVER, P.ACCENT_TEAL_PRESSED, P.PANEL_CREAM, 999)
	for s in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var sb: StyleBoxFlat = t.get_stylebox(s, "ButtonIcon")
		sb.content_margin_left = 18; sb.content_margin_right = 18; sb.content_margin_top = 18; sb.content_margin_bottom = 18

	# Flat icon button on cream panels (ink icon, no fill until hover).
	t.set_type_variation("ButtonIconFlat", "Button")
	_button(t, "ButtonIconFlat", Color(0, 0, 0, 0), P.HL_PEER, P.PANEL_CREAM_PRESSED, P.TEXT_INK, 999)
	for s in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var sb2: StyleBoxFlat = t.get_stylebox(s, "ButtonIconFlat")
		sb2.shadow_size = 0
		sb2.content_margin_left = 14; sb2.content_margin_right = 14; sb2.content_margin_top = 14; sb2.content_margin_bottom = 14

	# --- Panels --------------------------------------------------------------
	var panel := _sb(P.PANEL_CREAM, 22, Color(0, 0, 0, 0), 0, true, 24, 24)
	panel.shadow_size = 10; panel.shadow_offset = Vector2(0, 5)
	t.set_stylebox("panel", "Panel", panel)
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "PopupPanel", panel)
	t.set_type_variation("PanelModal", "PanelContainer")
	var modal := panel.duplicate()
	modal.set_corner_radius_all(28); modal.shadow_size = 18; modal.shadow_offset = Vector2(0, 8)
	modal.content_margin_left = 32; modal.content_margin_right = 32; modal.content_margin_top = 32; modal.content_margin_bottom = 32
	t.set_stylebox("panel", "PanelModal", modal)
	t.set_type_variation("PanelTopBar", "PanelContainer")
	var bar := _sb(P.PANEL_CREAM, 0, Color(0, 0, 0, 0), 0, true, 20, 10)
	bar.corner_radius_bottom_left = 22; bar.corner_radius_bottom_right = 22
	t.set_stylebox("panel", "PanelTopBar", bar)
	# Currency pill (stars/coins/tokens): gold fill, ink text -> 7.7:1
	t.set_type_variation("PanelPill", "PanelContainer")
	t.set_stylebox("panel", "PanelPill", _sb(P.STAR_GOLD, 999, P.TEXT_INK, 2, false, 16, 6))
	# Scrim behind modals
	t.set_type_variation("PanelScrim", "Panel")
	var scrim := StyleBoxFlat.new(); scrim.bg_color = Color(P.SHADOW_LILAC, 0.55)
	t.set_stylebox("panel", "PanelScrim", scrim)

	# --- Labels --------------------------------------------------------------
	t.set_color("font_color", "Label", P.TEXT_INK)
	t.set_font("font", "Label", ui_r)
	t.set_font_size("font_size", "Label", 28)
	t.set_constant("line_spacing", "Label", 4)
	for v in [["LabelTitle", d_b, 56], ["LabelHeader", d_sb, 38], ["LabelBody", ui_r, 28], ["LabelStrong", ui_b, 28],
			["LabelSmall", ui_m, 22], ["LabelPill", ui_b, 26], ["LabelOnAccent", ui_b, 28], ["LabelError", ui_b, 24]]:
		t.set_type_variation(v[0], "Label")
		t.set_font("font", v[0], v[1])
		t.set_font_size("font_size", v[0], v[2])
	t.set_color("font_color", "LabelSmall", P.DIGIT_NOTES)
	t.set_color("font_color", "LabelOnAccent", P.PANEL_CREAM)
	t.set_color("font_color", "LabelError", P.ERROR_INK)
	t.set_color("font_color", "RichTextLabel", P.TEXT_INK)
	t.set_color("default_color", "RichTextLabel", P.TEXT_INK)
	t.set_font("normal_font", "RichTextLabel", ui_r)
	t.set_font("bold_font", "RichTextLabel", ui_b)
	t.set_font_size("normal_font_size", "RichTextLabel", 28)
	t.set_font_size("bold_font_size", "RichTextLabel", 28)

	# --- Misc controls --------------------------------------------------------
	var track := _sb(P.HL_PEER, 999, P.GRID_LINE_THIN, 2, false, 0, 0)
	var fill := _sb(P.STAR_GOLD, 999, Color(0, 0, 0, 0), 0, false, 0, 0)
	t.set_stylebox("background", "ProgressBar", track)
	t.set_stylebox("fill", "ProgressBar", fill)
	t.set_color("font_color", "ProgressBar", P.TEXT_INK)
	t.set_font("font", "ProgressBar", ui_b)
	var tip := _sb(P.TEXT_INK, 12, Color(0, 0, 0, 0), 0, false, 14, 8)
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_color("font_color", "TooltipLabel", P.PANEL_CREAM)
	var sep := StyleBoxLine.new(); sep.color = P.GRID_LINE_THIN; sep.thickness = 2
	t.set_stylebox("separator", "HSeparator", sep)
	var grab := _sb(P.GRID_LINE_THIN, 999, Color(0, 0, 0, 0), 0, false, 0, 0)
	grab.content_margin_left = 6; grab.content_margin_right = 6
	t.set_stylebox("grabber", "VScrollBar", grab)
	t.set_stylebox("grabber_highlight", "VScrollBar", grab)
	t.set_stylebox("grabber_pressed", "VScrollBar", grab)
	t.set_stylebox("scroll", "VScrollBar", StyleBoxEmpty.new())

	var err := ResourceSaver.save(t, P.THEME_PATH)
	print("theme saved: ", P.THEME_PATH, " err=", err)
	quit(err)
