## Sudoku Dash vertical slice: screen flow, grid input, hint / second-chance panels, results, Harbour meta.
extends Control

const Sudoku = preload("res://sudoku/sudoku.gd")
const Logic = preload("res://sudoku/logic.gd")
const Board = preload("res://game/board_state.gd")
const Profile = preload("res://game/profile.gd")
const AdPolicy = preload("res://game/ad_policy.gd")
const Source = preload("res://game/puzzle_source.gd")
const GridView = preload("res://ui/grid_view.gd")
const Obj = preload("res://game/objectives.gd")
const Levels = preload("res://game/levels.gd")
const HarbourView = preload("res://ui/harbour_view.gd")
const UiLayout = preload("res://game/ui_layout.gd")
const TouchScroll = preload("res://ui/touch_scroll.gd")
const AP = preload("res://assets/art/art_palette.gd")   # art kit v1 palette (class_name ArtPalette)
const ART_THEME = preload("res://assets/art/theme/sudoku_dash_theme.tres")
const FONT_TITLE = preload("res://assets/art/fonts/Fraunces-BoldSoft.ttf")
const FONT_HEADER = preload("res://assets/art/fonts/Fraunces-SemiBoldSoft.ttf")
const BG_PORTRAIT = preload("res://assets/art/harbour/harbour_bg_portrait.webp")
const BG_LANDSCAPE = preload("res://assets/art/harbour/harbour_bg_landscape.webp")

var profile = Profile.new()
var source = Source.new()
var policy = null
var board = null
var screen_name: String = ""
var grid_meta: Dictionary = {}   # {mode, path_index, size, tier, seed, id}
var notes_mode: bool = false
var digit_lock: int = 0

var root: Control
var grid_view
var overlay: Control = null
var teach_label: Label
var status_label: Label
var notes_btn: Button
var mistakes_label: Label
var classic_tier: int:
	get: return profile.classic_tier
	set(v): profile.classic_tier = v
var results_label: Label = null
var level: Dictionary = {}        # current path level ({} for quick/classic)
var targets: Array = []           # target cell indices T
var elapsed_ms: int = 0           # Beat the Tide timer (Reveal penalties included)
var continues: int = 0
var _save_accum: float = 0.0
var objective_label: Label
var tide_bar: ProgressBar
var timer_debug_label: Label
const GRID_MARGIN = 10
var last_teach: Dictionary = {}   # checker format: {cell,value} | {eliminations} | {flag}
# ---- mobile / responsive (game/ui_layout.gd) ----
var compact: bool = false          # portrait one-column layout (set per screen build)
var css_size: Vector2 = Vector2.ZERO   # page size in CSS px (web) / window px (desktop, dpr 1)
var units_per_css: float = 1.0     # logical units per CSS px
var safe_css: Array = [0.0, 0.0, 0.0, 0.0]   # safe-area insets (CSS px): top, right, bottom, left
var _relayout_queued: bool = false
var _ad_busy: bool = false         # a rewarded ad is running (panel buttons stay locked across relayouts)
var _results: Dictionary = {}      # results screen state, kept so a resize can rebuild it
var _settings_back: String = "title"
var _touch: bool = false
var backdrop: TextureRect = null    # village scene behind menu screens (title / settings / results / restored)
var _just_restored: String = ""    # task bought this visit: the Harbour fades its restored sprite in

func _ready() -> void:
	Dbg.main = self
	policy = AdPolicy.new(Time.get_ticks_msec())
	await Store.wait_ready()   # don't read the save until the CrazyGames SDK init has settled
	var d = Store.load_data()
	if not d.is_empty(): profile.from_dict(d)
	Sfx.set_reason("user", not profile.sound_on)
	_touch = DisplayServer.is_touchscreen_available()
	theme = ART_THEME   # art kit v1: fonts, button/panel styles and colours for every screen
	var bg = ColorRect.new(); bg.color = AP.BG_LINEN; bg.set_anchors_preset(PRESET_FULL_RECT); add_child(bg)
	backdrop = TextureRect.new(); backdrop.set_anchors_preset(PRESET_FULL_RECT)
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE; backdrop.visible = false
	add_child(backdrop)
	root = Control.new(); root.set_anchors_preset(PRESET_FULL_RECT); add_child(root)
	apply_view()
	get_viewport().size_changed.connect(_on_size_changed)
	show_title()

func save() -> void:
	if board and screen_name == "grid":
		profile.current_grid = {"meta": grid_meta, "board": board.to_dict(), "level": {"elapsed_ms": elapsed_ms, "continues": continues}}
	Store.save(profile.to_dict())
	Dbg.publish()

func _clear() -> void:
	overlay = null
	var vp = get_viewport_rect().size
	compact = UiLayout.is_compact(vp)
	if backdrop:   # menus sit on the village scene (cover-cropped, picked by aspect); grid + harbour on linen
		backdrop.visible = screen_name in ["title", "settings", "results", "restored"]
		backdrop.texture = BG_PORTRAIT if vp.y > vp.x * 1.2 else BG_LANDSCAPE
	for c in root.get_children():
		root.remove_child(c)
		c.queue_free()

## Page resized / rotated: refit the logical viewport, then rebuild the current screen once (deferred).
func _on_size_changed() -> void:
	apply_view()
	if not _relayout_queued:
		_relayout_queued = true
		call_deferred("_deferred_relayout")

func _deferred_relayout() -> void:
	_relayout_queued = false
	apply_view()
	_relayout()

## Page CSS size, device pixel ratio and safe-area insets -> window content scale + root insets.
func apply_view() -> void:
	var win = get_tree().root
	var dpr = 1.0
	if OS.has_feature("web"):
		dpr = float(JavaScriptBridge.eval("window.devicePixelRatio || 1"))
		var ins = JavaScriptBridge.eval("window.SD_VIEW ? window.SD_VIEW.insets().join(',') : '0,0,0,0'")
		var parts = str(ins).split(",")
		if parts.size() == 4:
			for k in 4: safe_css[k] = maxf(0.0, float(parts[k]))
	else:
		dpr = maxf(1.0, DisplayServer.screen_get_scale())
		if DisplayServer.get_name() == "headless": dpr = 1.0
	if dpr <= 0.0: dpr = 1.0
	css_size = Vector2(win.size) / dpr
	var ls = UiLayout.logical_size(css_size)
	var base = Vector2i(UiLayout.DESKTOP_BASE) if ls == Vector2.ZERO else Vector2i(ls)
	if win.content_scale_size != base: win.content_scale_size = base
	units_per_css = UiLayout.units_per_css(css_size)
	if root:
		root.offset_top = safe_css[0] * units_per_css
		root.offset_right = -safe_css[1] * units_per_css
		root.offset_bottom = -safe_css[2] * units_per_css
		root.offset_left = safe_css[3] * units_per_css

## Rebuild the current screen for the new size. A run in progress keeps its board, selection, notes mode,
## digit lock, timer and any open panel / hint highlight.
func _relayout() -> void:
	match screen_name:
		"grid":
			var kind = "" if overlay == null else str(overlay.name)
			var keep = {"teach": grid_view.teach_cells if grid_view else [], "flag": grid_view.flag_cells if grid_view else [],
				"elims": grid_view.teach_elims if grid_view else [], "text": teach_label.text if is_instance_valid(teach_label) else ""}
			_build_grid_screen()
			grid_view.teach_cells = keep.teach; grid_view.flag_cells = keep.flag; grid_view.teach_elims = keep.elims
			teach_label.text = keep.text
			if kind == "HintPanel": _open_hint_panel()
			elif kind == "SecondChancePanel": _open_second_chance()
			if overlay and _ad_busy: _lock_overlay()
		"harbour": show_harbour()
		"title": _build_title()
		"results": _build_results()
		"restored": show_area_restored()
		"settings": show_settings()

## Layout facts for QA hooks / tests.
func layout_info() -> Dictionary:
	return {"screen": screen_name, "compact": compact, "cssSize": [css_size.x, css_size.y], "unitsPerCss": units_per_css,
		"safeCss": safe_css, "touch": _touch, "overlay": "" if overlay == null else str(overlay.name)}

# ---------------- widgets ----------------
func _btn(text: String, cb: Callable, fs: int = 26, min_h: int = 64) -> Button:
	var b = Button.new()
	b.text = text
	if compact:   # portrait (720-wide base): text scaled for the base, never below the 88-unit touch target
		fs = int(round(fs * 0.85 * UiLayout.COMPACT_SCALE))
		min_h = maxi(UiLayout.COMPACT_MIN_BTN, int(round(min_h * 0.85 * UiLayout.COMPACT_SCALE)))
	b.custom_minimum_size = Vector2(0, min_h)
	b.add_theme_font_size_override("font_size", fs)
	if _touch:   # no sticky hover highlight after a tap on touch screens
		b.ready.connect(_no_hover.bind(b), CONNECT_ONE_SHOT)
	b.pressed.connect(func(): Sfx.play("tap"))
	if _touch:   # touch: run the action after the tap's own event handling (it may free this button)
		b.pressed.connect(func(): cb.call_deferred())
	else:
		b.pressed.connect(cb)
	return b

## Touch: hover looks like normal. Resolved once the button is in the tree, so it copies whatever Theme
## is active there (the art kit theme can be dropped in on the root without code changes).
func _no_hover(b: Button) -> void:
	for st in [["hover", "normal"], ["hover_pressed", "pressed"]]:
		b.add_theme_stylebox_override(st[0], b.get_theme_stylebox(st[1]))
	b.add_theme_color_override("font_hover_color", b.get_theme_color("font_color"))
	b.add_theme_color_override("font_hover_pressed_color", b.get_theme_color("font_pressed_color"))

## Art kit v1 button look: theme type variation ("" = primary teal) + optional icon. Sizes untouched:
## min sizes / containers come from the layout code; the icon is capped near the label's cap height.
func _style(b: Button, kind: String = "", icon: String = "") -> Button:
	b.theme_type_variation = kind
	if icon != "":
		var on_accent = kind in ["", "Button", "ButtonSecondary"]
		var variant = "cream" if on_accent else "ink"
		if icon in ["star", "coin"] and not on_accent: variant = "gold"
		b.icon = load(AP.icon_path(icon, variant))
		var fs = b.get_theme_font_size("font_size") if b.has_theme_font_size_override("font_size") else 28
		b.add_theme_constant_override("icon_max_width", int(round(fs * 1.25)))
		for c in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_hover_pressed_color", "icon_focus_color"]:
			b.add_theme_color_override(c, Color.WHITE)   # the icon file already carries its colour (ink / cream / gold)
		b.add_theme_color_override("icon_disabled_color", Color(1, 1, 1, 0.55))
	return b

## Display (Fraunces) heading label: screen titles and panel headers.
func _heading(text: String, fs: int = 40, title: bool = false) -> Label:
	var l = _label(text, fs)
	l.add_theme_font_override("font", FONT_TITLE if title else FONT_HEADER)
	return l

## Small icon for labels / pills.
func _icon_rect(name: String, variant: String, px: float, alpha: float = 1.0) -> TextureRect:
	var t = TextureRect.new()
	t.texture = load(AP.icon_path(name, variant))
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.custom_minimum_size = Vector2(px, px)
	t.modulate.a = alpha
	return t

## Panel stylebox from the theme (PanelModal look) with the layout's own content margin.
func _panel_sb(margin: int) -> StyleBoxFlat:
	var sb: StyleBoxFlat = ART_THEME.get_stylebox("panel", "PanelModal").duplicate()
	sb.set_content_margin_all(margin)
	return sb

## Compact layout distances are authored for a 420-wide screen; scale them to the 720 base.
func _u(x: float) -> int:
	return int(round(x * (UiLayout.COMPACT_SCALE if compact else 1.0)))

func _label(text: String, fs: int = 24, col: Color = AP.TEXT_INK) -> Label:
	var l = Label.new()
	l.text = text
	if compact: fs = int(round(fs * 0.85 * UiLayout.COMPACT_SCALE))
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

func _center_box(min_w: int = 520) -> VBoxContainer:
	var cc = CenterContainer.new(); cc.set_anchors_preset(PRESET_FULL_RECT); root.add_child(cc)
	var panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_sb(_u(16) if compact else 24))
	cc.add_child(panel)
	var v = VBoxContainer.new(); v.custom_minimum_size = Vector2(_panel_w(min_w), 0)
	v.add_theme_constant_override("separation", _u(12))
	panel.add_child(v)
	_wrap_buttons(v)
	return v

## Compact layout: long button labels wrap instead of pushing the panel off-screen.
func _wrap_buttons(v: Control) -> void:
	if not compact: return
	v.child_entered_tree.connect(func(n):
		if n is Button:
			n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			n.size_flags_horizontal = SIZE_EXPAND_FILL)

## Coin-priced button: disabled with price + "Need N more coins" line when unaffordable (never hidden).
func _coin_option(parent: Control, text: String, price: int, cb: Callable) -> void:
	var b = _style(_btn("%s (%d coins)" % [text, price], cb), "", "coin")
	parent.add_child(b)
	var need = profile.need_more(price)
	var l = _label("Need %d more coins" % need if need > 0 else " ", 20, AP.ERROR_INK)
	parent.add_child(l)
	b.disabled = need > 0

# ---------------- title / harbour ----------------
func show_title() -> void:
	_build_title()
	print("[SD] title ready")
	Store.loading_stop()

func _build_title() -> void:
	screen_name = "title"
	Ads.set_context("menu")
	_clear()
	var v = _center_box()
	v.add_child(_heading("Sudoku Dash", 56, true))
	v.add_child(_label("Restore the Harbour, one puzzle at a time.", 24))
	var play = _btn("Play", show_harbour, 34, 80)
	play.name = "PlayButton"
	v.add_child(play)
	var st = _style(_btn("Settings", func(): show_settings("title"), 24, 56), "ButtonChip", "settings")
	st.name = "SettingsButton"
	v.add_child(st)

# ---------------- settings ----------------
func show_settings(back: String = "") -> void:
	if back != "": _settings_back = back
	screen_name = "settings"
	Ads.set_context("menu")
	_clear()
	var v = _center_box()
	v.add_child(_heading("Settings", 44))
	var sb = _style(_btn("Sound: On" if profile.sound_on else "Sound: Off", _toggle_sound, 26, 64), "ButtonChip", "sound_on" if profile.sound_on else "sound_off")
	sb.name = "SoundButton"
	v.add_child(sb)
	var bb = _style(_btn("Back", func(): show_harbour() if _settings_back == "harbour" else _build_title(), 24, 64), "ButtonChip", "back")
	bb.name = "SettingsBack"
	v.add_child(bb)

func _toggle_sound() -> void:
	profile.sound_on = not profile.sound_on
	Sfx.set_reason("user", not profile.sound_on)
	save()
	show_settings()

func show_harbour() -> void:
	screen_name = "harbour"
	Ads.set_context("menu")
	board = null
	_clear()
	if profile.area_restored() and not profile.current_grid.has("restored_seen"):
		pass
	var vp = get_viewport_rect().size
	var landscape = vp.x >= vp.y
	var box = HBoxContainer.new() if landscape else VBoxContainer.new()
	box.set_anchors_preset(PRESET_FULL_RECT)
	box.add_theme_constant_override("separation", 10)
	root.add_child(box)
	var hv = HarbourView.new(); hv.profile = profile
	hv.name = "HarbourView"
	hv.reveal_id = _just_restored   # gentle fade-in of a task restored this visit
	_just_restored = ""
	hv.size_flags_horizontal = SIZE_EXPAND_FILL; hv.size_flags_vertical = SIZE_EXPAND_FILL
	hv.custom_minimum_size = Vector2(300, 220)
	box.add_child(hv)
	var av = avail_size()
	var sc = TouchScroll.new(); sc.custom_minimum_size = Vector2(460 if landscape else av.x, 0 if landscape else av.y * 0.55)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.name = "HarbourScroll"
	sc.drag_enabled = _touch   # desktop mouse behaviour unchanged
	sc.drag_threshold = 10.0 * units_per_css
	var lsb = StyleBoxFlat.new(); lsb.bg_color = Color(AP.PANEL_CREAM, 0.94); lsb.set_corner_radius_all(18)   # no content margin: geometry unchanged
	sc.add_theme_stylebox_override("panel", lsb)
	box.add_child(sc)
	var v = VBoxContainer.new(); v.size_flags_horizontal = SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 8)
	if compact:   # side margins so buttons don't touch the screen edge
		var hm = MarginContainer.new(); hm.size_flags_horizontal = SIZE_EXPAND_FILL
		for side_name in ["margin_left", "margin_right", "margin_bottom"]: hm.add_theme_constant_override(side_name, _u(GRID_MARGIN))
		sc.add_child(hm)
		hm.add_child(v)
	else:
		sc.add_child(v)
	v.add_child(_heading("Harbour", 34))
	var pills = HBoxContainer.new(); pills.alignment = BoxContainer.ALIGNMENT_CENTER
	pills.add_theme_constant_override("separation", _u(6))
	var ipx = _u(28)
	for it in [["star", "gold", "Stars %d" % profile.stars], ["coin", "gold", "Coins %d" % profile.coins], ["hint", "ink", "Tokens %d" % profile.tokens]]:
		pills.add_child(_icon_rect(it[0], it[1], ipx))
		var pl = _label(it[2], 22); pl.autowrap_mode = TextServer.AUTOWRAP_OFF
		pl.add_theme_font_override("font", load(AP.FONT_UI_BOLD))
		pills.add_child(pl)
		if it[0] != "hint": pills.add_child(_spacer(_u(10)))
	v.add_child(pills)
	if profile.current_grid.has("board"):
		v.add_child(_btn("Resume grid", resume_grid, 28, 72))
	if not profile.path_finished():
		var lv = Levels.level(profile.path_next)
		v.add_child(_btn("Level %d/%d: %s" % [profile.path_next + 1, Profile.path_length(), Obj.label(lv)], start_path_grid, 24, 72))
	else:
		v.add_child(_label("Path complete! Stars earned: %d" % profile.stars_earned, 22))
	v.add_child(_btn("Quick 6x6", start_quick, 24))
	var tiers = HBoxContainer.new()
	for t in [1, 2, 3, 4]:
		var b = _style(_btn("T%d" % t, func(): classic_tier = t; save(); show_harbour(), 22, 56), "ButtonChip")
		b.toggle_mode = true; b.button_pressed = t == classic_tier
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		tiers.add_child(b)
	v.add_child(tiers)
	v.add_child(_btn("Classic 9x9 (tier %d)" % classic_tier, start_classic, 24))
	v.add_child(_heading("Tasks", 28))
	for t in Profile.TASKS:
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", _u(8))
		var thumb = TextureRect.new()
		thumb.texture = load(AP.task_sprite_path(t.id, profile.tasks.has(t.id)))
		thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		thumb.custom_minimum_size = Vector2(_u(44), _u(44))
		row.add_child(thumb)
		var l = _label(t.name, 22); l.size_flags_horizontal = SIZE_EXPAND_FILL; l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.add_child(l)
		if profile.tasks.has(t.id):
			var ch = profile.decor.get(t.id, 0)
			var id = t.id
			var n = t.decor.size()
			row.add_child(_style(_btn(t.decor[ch], func(): profile.set_decor(id, (ch + 1) % n); save(); show_harbour(), 20, 56), "ButtonChip"))
		else:
			var id2 = t.id
			var unl = profile.task_unlocked(t.id)
			var b = _btn("Buy (%d stars)" % t.cost if unl else "Locked", func(): _buy_task(id2), 20, 56)
			b.disabled = profile.stars < t.cost or not unl
			if not unl: _style(b, "ButtonLocked", "lock")
			else: _style(b, "ButtonSecondary", "star")
			if b.disabled: b.icon = load(AP.icon_path("lock" if not unl else "star", "ink"))
			row.add_child(b)
		v.add_child(row)
	if profile.area_restored():
		v.add_child(_style(_btn("Area restored!", show_area_restored, 24), "ButtonSecondary", "star"))
	var stb = _style(_btn("Settings", func(): show_settings("harbour"), 22, 56), "ButtonChip", "settings")
	stb.name = "SettingsButton"
	v.add_child(stb)

func _spacer(w: float) -> Control:
	var c = Control.new(); c.custom_minimum_size = Vector2(w, 0)
	return c

func _buy_task(id: String) -> void:
	if profile.buy_task(id):
		_just_restored = id
		save()
		if profile.area_restored():
			show_area_restored()
			return
	show_harbour()

func show_area_restored() -> void:
	screen_name = "restored"
	_clear()
	var v = _center_box()
	v.add_child(_heading("Area restored!", 48, true))
	v.add_child(_label("The Harbour is bustling again. Extra stars carry over to the next area.", 24))
	v.add_child(_btn("Back to Harbour", show_harbour))

# ---------------- grids ----------------
func start_path_grid() -> void:
	start_level(profile.path_next)

## Path level i (0-based). Grid comes from the packs via the level's grid_id.
func start_level(i: int) -> void:
	var lv = Levels.level(i)
	var gr = Levels.grid(lv.grid_id)
	var pk: String = gr.pack
	var p = source.from_pack(int(gr.size), int(pk.substr(pk.length() - 1)), int(gr.index))
	grid_meta = {"mode": "path", "path_index": i, "level": i + 1, "size": int(gr.size), "tier": int(lv.tier), "seed": int(gr.index), "id": p.id}
	board = Board.new()
	board.setup(int(gr.size), p.givens, p.solution)
	_set_level(lv, 0, 0)
	_enter_grid()

func _set_level(lv: Dictionary, el: int, cont: int) -> void:
	level = lv
	targets = Levels.target_cells(lv) if not lv.is_empty() else []
	elapsed_ms = el
	continues = cont

func start_quick() -> void:
	profile.quick_seed += 1
	_start({"mode": "quick", "path_index": -1, "size": 6, "tier": 1 + profile.quick_seed % 2, "seed": 10000 + profile.quick_seed})

func start_classic() -> void:
	var k = str(classic_tier)
	var idx = int(profile.classic_index.get(k, 0))
	profile.classic_index[k] = idx + 1
	_start({"mode": "classic", "path_index": -1, "size": 9, "tier": classic_tier, "seed": idx})

func _start(meta: Dictionary) -> void:
	var p = source.get_puzzle(meta.size, meta.tier, meta.seed)
	meta["id"] = p.id
	grid_meta = meta
	board = Board.new()
	board.setup(meta.size, p.givens, p.solution)
	_set_level({}, 0, 0)
	_enter_grid()

func resume_grid() -> void:
	grid_meta = profile.current_grid.meta
	grid_meta.size = int(grid_meta.size); grid_meta.tier = int(grid_meta.tier); grid_meta.path_index = int(grid_meta.path_index)
	board = Board.new()
	board.from_dict(profile.current_grid.board)
	var lvd = profile.current_grid.get("level", {})
	if grid_meta.mode == "path":
		_set_level(Levels.level(int(grid_meta.path_index)), int(lvd.get("elapsed_ms", 0)), int(lvd.get("continues", 0)))
	else:
		_set_level({}, 0, 0)
	_enter_grid()

func _enter_grid() -> void:
	screen_name = "grid"
	notes_mode = false
	digit_lock = 0
	grid_view = null
	_build_grid_screen()
	Ads.set_context("grid")
	save()
	if board.max_mistakes > 0 and board.mistakes >= board.max_mistakes:
		_open_second_chance()

func _build_grid_screen() -> void:
	var sel = grid_view.selected if grid_view else -1
	_clear()
	if compact:
		_build_grid_compact(sel)
		_refresh()
		return
	var vp = get_viewport_rect().size
	var landscape = vp.x >= vp.y
	# Phone landscape (logical height < 600; desktop/tablet bases are >= 720): tighter rows, two-row pad.
	var short = landscape and vp.y < 600
	var bh = 56 if short else 64
	# Safe margin so the grid's outer border and the side column never touch the canvas edge
	# (QA run 6: bottom border clipped at 1280x800 in Chrome).
	var mc = MarginContainer.new(); mc.set_anchors_preset(PRESET_FULL_RECT)
	for side_name in ["margin_left", "margin_right", "margin_bottom"]: mc.add_theme_constant_override(side_name, GRID_MARGIN)
	mc.add_theme_constant_override("margin_top", 0)
	root.add_child(mc)
	var outer = VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	mc.add_child(outer)
	var top = HBoxContainer.new(); top.custom_minimum_size = Vector2(0, bh)
	outer.add_child(top)
	var back = _style(_btn("Back", _leave_grid, 26, 56 if short else 60), "ButtonChip", "back"); back.name = "BackButton"
	top.add_child(back)
	var tl = _label(_grid_title(), 24); tl.size_flags_horizontal = SIZE_EXPAND_FILL
	tl.autowrap_mode = TextServer.AUTOWRAP_OFF; tl.clip_text = true
	top.add_child(tl)
	mistakes_label = _label("", 24)
	mistakes_label.name = "MistakesLabel"
	mistakes_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	top.add_child(mistakes_label)
	var hint = _style(_btn("Hint", _open_hint_panel, 26, 56 if short else 60), "ButtonSecondary", "hint"); hint.name = "HintButton"
	top.add_child(hint)
	var body = HBoxContainer.new() if landscape else VBoxContainer.new()
	body.size_flags_vertical = SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	outer.add_child(body)
	_make_grid_view(sel)
	body.add_child(grid_view)
	var side = VBoxContainer.new()
	side.custom_minimum_size = Vector2(min(420, vp.x * 0.4) if landscape else vp.x - 2 * GRID_MARGIN, 0 if landscape else min(vp.y * 0.38, 360))
	side.add_theme_constant_override("separation", 8)
	body.add_child(side)
	objective_label = _label("", 22, AP.ACCENT_TEAL_PRESSED)
	objective_label.name = "ObjectiveLabel"
	side.add_child(objective_label)
	_make_tide_bar(side, 18)
	teach_label = _label("", 20, AP.ACCENT_TERRACOTTA_PRESSED)
	teach_label.name = "TeachLabel"
	side.add_child(teach_label)
	var pad = GridContainer.new()
	pad.name = "DigitPad"
	pad.columns = UiLayout.pad_columns(board.size, not landscape or short)
	pad.size_flags_vertical = SIZE_EXPAND_FILL
	pad.add_theme_constant_override("h_separation", 8); pad.add_theme_constant_override("v_separation", 8)
	side.add_child(pad)
	for d in range(1, board.size + 1):
		var b = _style(_btn(str(d), _on_digit.bind(d), 34, bh), "ButtonTile")
		b.name = "Digit%d" % d
		b.custom_minimum_size = Vector2(56, 56) if short else Vector2(64, 64)
		b.size_flags_horizontal = SIZE_EXPAND_FILL; b.size_flags_vertical = SIZE_EXPAND_FILL
		b.toggle_mode = true
		b.button_pressed = digit_lock == d
		pad.add_child(b)
	var tools = HBoxContainer.new(); tools.add_theme_constant_override("separation", 8)
	side.add_child(tools)
	notes_btn = _style(_btn("Notes: OFF", _toggle_notes, 22, bh), "ButtonChip"); notes_btn.name = "NotesButton"
	notes_btn.size_flags_horizontal = SIZE_EXPAND_FILL; notes_btn.toggle_mode = true
	tools.add_child(notes_btn)
	var ub = _style(_btn("Undo", _undo, 22, bh), "ButtonChip"); ub.name = "UndoButton"; ub.size_flags_horizontal = SIZE_EXPAND_FILL
	tools.add_child(ub)
	var eb = _style(_btn("Erase", _erase, 22, bh), "ButtonChip"); eb.name = "EraseButton"; eb.size_flags_horizontal = SIZE_EXPAND_FILL
	if short and board.size > 6:
		eb.size_flags_vertical = SIZE_EXPAND_FILL
		pad.add_child(eb)   # 9x9: Erase fills the 10th pad slot (5 + 5)
	else:
		tools.add_child(eb)
	status_label = _label("", 18, AP.DIGIT_NOTES)
	status_label.name = "StatusLabel"
	status_label.visible = not short   # no room on a phone held sideways; the pad covers every action
	side.add_child(status_label)
	_refresh()

func _grid_title() -> String:
	if grid_meta.mode == "path": return "Level %d/%d" % [grid_meta.path_index + 1, Profile.path_length()]
	return "Quick 6x6" if grid_meta.mode == "quick" else "Classic 9x9 T%d" % grid_meta.tier

func _make_grid_view(sel: int) -> void:
	grid_view = GridView.new()
	grid_view.name = "GridView"
	grid_view.board = board
	grid_view.selected = sel
	grid_view.size_flags_horizontal = SIZE_EXPAND_FILL
	grid_view.size_flags_vertical = SIZE_EXPAND_FILL
	grid_view.cell_tapped.connect(_on_cell)
	# Digit Hunt: never outline T (it would reveal where the digit goes). Counter only.
	grid_view.target_cells = [] if (not level.is_empty() and str(level.params.get("inner", level.objective)) == "digit") else targets
	grid_view.lantern_path = []
	if not level.is_empty():
		if level.objective == "lantern":
			for rc in level.params.path: grid_view.lantern_path.append(int(rc[0]) * board.size + int(rc[1]))

func _make_tide_bar(parent: Control, h: int) -> void:
	tide_bar = ProgressBar.new()
	tide_bar.name = "TideBar"
	tide_bar.show_percentage = false
	tide_bar.custom_minimum_size = Vector2(0, h)
	tide_bar.visible = not level.is_empty() and Obj.is_timed(level)
	parent.add_child(tide_bar)
	timer_debug_label = null
	if Dbg.enabled:   # H7: on-screen timer readout (debug builds only)
		timer_debug_label = _label("", 16, Color("7a2a2a"))
		timer_debug_label.name = "TimerDebug"
		parent.add_child(timer_debug_label)

## Portrait phones/tablets: one column. Top bar (Back, level, mistakes), objective + tide bar,
## full-width square grid, hint text, digit pad, tools (Notes, Erase, Undo, Hint). Every control is
## >= 52 logical units (>= 44 CSS px at the narrowest 360 px page); no keyboard needed.
func _build_grid_compact(sel: int) -> void:
	var mc = MarginContainer.new(); mc.set_anchors_preset(PRESET_FULL_RECT)
	for side_name in ["margin_left", "margin_right", "margin_bottom"]: mc.add_theme_constant_override(side_name, _u(8))
	mc.add_theme_constant_override("margin_top", _u(4))
	root.add_child(mc)
	var outer = VBoxContainer.new()
	outer.add_theme_constant_override("separation", _u(6))
	mc.add_child(outer)
	var top = HBoxContainer.new(); top.add_theme_constant_override("separation", _u(6))
	outer.add_child(top)
	var back = _style(_btn("Back", _leave_grid, 24, 56), "ButtonChip"); back.name = "BackButton"
	back.custom_minimum_size.x = _u(72)
	top.add_child(back)
	var tl = _label(_grid_title(), 24); tl.size_flags_horizontal = SIZE_EXPAND_FILL
	tl.autowrap_mode = TextServer.AUTOWRAP_OFF; tl.clip_text = true
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	top.add_child(tl)
	mistakes_label = _label("", 24)
	mistakes_label.name = "MistakesLabel"
	mistakes_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	top.add_child(mistakes_label)
	objective_label = _label("", 24, AP.ACCENT_TEAL_PRESSED)
	objective_label.name = "ObjectiveLabel"
	outer.add_child(objective_label)
	_make_tide_bar(outer, _u(14))
	_make_grid_view(sel)
	grid_view.custom_minimum_size = Vector2(0, _u(180))
	outer.add_child(grid_view)
	teach_label = _label("", 22, AP.ACCENT_TERRACOTTA_PRESSED)
	teach_label.name = "TeachLabel"
	teach_label.custom_minimum_size = Vector2(0, _u(44))   # room for a 2-line hint without the grid jumping
	teach_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	outer.add_child(teach_label)
	var pad = GridContainer.new()
	pad.name = "DigitPad"
	pad.columns = UiLayout.pad_columns(board.size, true)
	pad.add_theme_constant_override("h_separation", _u(6)); pad.add_theme_constant_override("v_separation", _u(6))
	outer.add_child(pad)
	for d in range(1, board.size + 1):
		var b = _style(_btn(str(d), _on_digit.bind(d), 36, 60), "ButtonTile")
		b.name = "Digit%d" % d
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		b.toggle_mode = true
		b.button_pressed = digit_lock == d
		pad.add_child(b)
	var tools = HBoxContainer.new(); tools.add_theme_constant_override("separation", _u(6))
	outer.add_child(tools)
	var tfs = 24 if board.size > 6 else 21   # 6x6 has four tools in the row: keep "Notes: OFF" unclipped
	var eb = _style(_btn("Erase", _erase, tfs, 60), "ButtonChip"); eb.name = "EraseButton"; eb.size_flags_horizontal = SIZE_EXPAND_FILL
	if board.size > 6: pad.add_child(eb)   # 9x9: Erase fills the 10th pad slot (5 + 5)
	notes_btn = _style(_btn("Notes: OFF", _toggle_notes, tfs, 60), "ButtonChip"); notes_btn.name = "NotesButton"
	notes_btn.size_flags_horizontal = SIZE_EXPAND_FILL; notes_btn.clip_text = true; notes_btn.toggle_mode = true
	if board.size <= 6: notes_btn.size_flags_stretch_ratio = 1.5   # widest label among four tools
	tools.add_child(notes_btn)
	if board.size <= 6: tools.add_child(eb)
	var ub = _style(_btn("Undo", _undo, tfs, 60), "ButtonChip"); ub.name = "UndoButton"; ub.size_flags_horizontal = SIZE_EXPAND_FILL
	tools.add_child(ub)
	var hint = _style(_btn("Hint", _open_hint_panel, tfs, 60), "ButtonSecondary"); hint.name = "HintButton"; hint.size_flags_horizontal = SIZE_EXPAND_FILL
	tools.add_child(hint)
	status_label = _label("", 18, AP.DIGIT_NOTES)
	status_label.name = "StatusLabel"
	status_label.visible = false   # keyboard help is for desktop; phones use the pad
	outer.add_child(status_label)

func _refresh() -> void:
	if board == null or grid_view == null: return
	mistakes_label.text = ("Mistakes %d/%d" % [board.mistakes, board.max_mistakes]) if board.max_mistakes > 0 else "Warm-up: no mistake limit"
	notes_btn.text = "Notes: ON" if notes_mode else "Notes: OFF"
	if notes_btn.toggle_mode: notes_btn.set_pressed_no_signal(notes_mode)   # chip shows teal while notes are on
	status_label.text = ("Tap a cell, then a digit. Or tap a digit, then cells." if _touch else "Tap a cell then a digit, or a digit then cells. Keys: 1-%d, arrows, Backspace, N, Ctrl+Z" % board.size)
	objective_label.text = Obj.label(level, board.cells, board.solution, targets) if not level.is_empty() else ""
	_refresh_timer()
	grid_view.queue_redraw()

func _refresh_timer() -> void:
	if tide_bar == null or not is_instance_valid(tide_bar) or level.is_empty() or not Obj.is_timed(level): return
	var par_ms = int(level.par_time_s) * 1000
	tide_bar.max_value = par_ms
	tide_bar.value = maxi(0, par_ms - elapsed_ms)
	tide_bar.modulate = Color(0.6, 0.6, 0.6) if elapsed_ms > par_ms else Color(1, 1, 1)   # calm grey after par
	if timer_debug_label and is_instance_valid(timer_debug_label):
		timer_debug_label.text = "[debug] elapsed_ms=%d par_ms=%d" % [elapsed_ms, par_ms]

## Timer runs only on a live timed level: no panel, tab visible, window focused (v1.2 §9.6).
func timer_running() -> bool:
	return screen_name == "grid" and board != null and not level.is_empty() and Obj.is_timed(level) \
		and overlay == null and Ads.context == "grid" and not Sfx.state.reasons.has("hidden") and not Sfx.state.reasons.has("blur")

func _process(delta: float) -> void:
	if timer_running():
		elapsed_ms += int(round(delta * 1000.0))
		_refresh_timer()
	if screen_name == "grid" and board != null:
		_save_accum += delta
		if _save_accum >= 5.0:   # periodic save (at least every 5 s)
			_save_accum = 0.0
			save()

func _level_done() -> bool:
	if level.is_empty(): return board.is_complete()
	return Obj.complete(board.cells, board.solution, targets)

func _clear_teach() -> void:
	if grid_view:
		grid_view.teach_cells = []; grid_view.flag_cells = []; grid_view.teach_elims = []
	if teach_label: teach_label.text = ""

func _on_cell(i: int) -> void:
	if overlay: return
	Sfx.play("tap")
	_clear_teach()
	if digit_lock != 0:
		grid_view.selected = i
		_apply_digit(i, digit_lock)
	else:
		grid_view.selected = i
	_refresh()

func _on_digit(d: int) -> void:
	if overlay: return
	_clear_teach()
	var sel = grid_view.selected
	if sel >= 0 and not board.is_given(sel) and digit_lock == 0:
		_apply_digit(sel, d)
	else:
		digit_lock = 0 if digit_lock == d else d
		if digit_lock != 0: grid_view.selected = -1
		_build_grid_screen()
		return
	_refresh_pad()
	_refresh()

func _refresh_pad() -> void:
	if board == null: return
	for d in range(1, board.size + 1):
		var b = root.find_child("Digit%d" % d, true, false)
		if b: b.set_pressed_no_signal(digit_lock == d)

func _apply_digit(i: int, d: int) -> void:
	if notes_mode:
		board.toggle_note(i, d)
	else:
		var r = board.place(i, d)
		if r.changed: Sfx.play("mistake" if r.mistake else "place")
		if r.mistake: grid_view.wrong_feedback(i)
		if r.changed and _level_done():
			save()
			_complete()
			return
		if r.limit_reached:
			save()
			_open_second_chance()
			return
	save()
	_refresh()

func _toggle_notes() -> void:
	notes_mode = not notes_mode
	_refresh()

func _undo() -> void:
	if overlay: return
	_clear_teach()
	board.undo(); save(); _refresh()

func _erase() -> void:
	if overlay or grid_view.selected < 0: return
	_clear_teach()
	board.erase(grid_view.selected); save(); _refresh()

func _leave_grid() -> void:
	save()   # grid in progress stays saved for Resume
	show_harbour()

func _unhandled_input(e: InputEvent) -> void:
	if screen_name != "grid" or overlay or not (e is InputEventKey) or not e.pressed: return
	var n = board.size
	var k = e.keycode
	var pk = e.physical_keycode
	var mod = e.ctrl_pressed or e.meta_pressed or e.alt_pressed
	# Digits by PHYSICAL key (top row / numpad) so AZERTY etc. work; no modifiers; no key-repeat.
	var d = 0
	if pk >= KEY_1 and pk <= KEY_9: d = pk - KEY_0
	elif pk >= KEY_KP_1 and pk <= KEY_KP_9: d = pk - KEY_KP_0
	elif k >= KEY_KP_1 and k <= KEY_KP_9: d = k - KEY_KP_0
	if d > 0:
		if mod or e.echo or d > n: return
		_on_digit(d)
	elif k == KEY_N and not mod:
		if e.echo: return
		_toggle_notes()
	elif k == KEY_Z and (e.ctrl_pressed or e.meta_pressed):
		if e.echo:   # holding Ctrl/Cmd+Z: one undo per press
			get_viewport().set_input_as_handled()
			return
		_undo()
	elif (k == KEY_BACKSPACE or k == KEY_DELETE) and not mod:
		if e.echo: return
		_erase()
	elif k in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]:
		if grid_view.selected < 0:
			grid_view.selected = 0   # first arrow press selects the top-left cell
		else:
			var s = grid_view.selected
			var r = s / n; var c = s % n
			match k:
				KEY_LEFT: c = (c + n - 1) % n
				KEY_RIGHT: c = (c + 1) % n
				KEY_UP: r = (r + n - 1) % n
				KEY_DOWN: r = (r + 1) % n
			grid_view.selected = r * n + c
		digit_lock = 0
		_refresh_pad()
		_refresh()
	else:
		return
	get_viewport().set_input_as_handled()

# ---------------- pause panels ----------------
func _open_overlay() -> VBoxContainer:
	Ads.set_context("grid_panel")   # grid paused
	if overlay:
		root.remove_child(overlay)
		overlay.queue_free()
	overlay = Control.new(); overlay.set_anchors_preset(PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(overlay)
	var dim = ColorRect.new(); dim.color = Color(0.16, 0.15, 0.22, 0.72); dim.set_anchors_preset(PRESET_FULL_RECT)   # lilac-ink scrim
	overlay.add_child(dim)
	var cc = CenterContainer.new(); cc.set_anchors_preset(PRESET_FULL_RECT); overlay.add_child(cc)
	var panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_sb(_u(16) if compact else 24))
	cc.add_child(panel)
	var v = VBoxContainer.new(); v.custom_minimum_size = Vector2(_panel_w(560), 0)
	v.add_theme_constant_override("separation", _u(10))
	panel.add_child(v)
	_wrap_buttons(v)
	return v

## Usable width inside the safe area (logical units).
func avail_size() -> Vector2:
	var vp = get_viewport_rect().size
	return vp - Vector2(safe_css[1] + safe_css[3], safe_css[0] + safe_css[2]) * units_per_css

## Panel content width: desktop unchanged (min(w, vp - 40)); compact leaves 12 px gaps + 16 px padding.
func _panel_w(w: int) -> float:
	if compact: return minf(w * UiLayout.COMPACT_SCALE, avail_size().x - _u(56))
	return minf(w, get_viewport_rect().size.x - 40)

func _close_overlay() -> void:
	if overlay:
		root.remove_child(overlay)
		overlay.queue_free()
	overlay = null
	Ads.set_context("grid")
	_refresh()

func _open_hint_panel() -> void:
	if overlay: return
	_clear_teach()
	var v = _open_overlay()
	overlay.name = "HintPanel"
	v.add_child(_heading("Hint", 36))
	v.add_child(_label("Tokens: %d   Coins: %d" % [profile.tokens, profile.coins], 22))
	var sel = grid_view.selected
	var can_reveal = sel >= 0 and not board.is_given(sel) and board.cells[sel] != board.solution[sel]
	if not board.active_hint().is_empty():
		var again = _style(_btn("Show my last hint again (free)", _reshow_hint), "ButtonChip", "hint")
		again.name = "ReshowHint"
		v.add_child(again)
	if profile.tokens > 0:
		v.add_child(_style(_btn("Teach me the next step (1 token)", func(): _pay_hint("teach", "token")), "", "hint"))
		var rb = _btn("Reveal selected cell (1 token)", func(): _pay_hint("reveal", "token"))
		rb.disabled = not can_reveal
		v.add_child(rb)
	else:
		_coin_option(v, "Teach me the next step", Profile.HINT_COIN_PRICE, func(): _pay_hint("teach", "coins"))
		_coin_option(v, "Reveal selected cell", Profile.HINT_COIN_PRICE, func(): _pay_hint("reveal", "coins"))
		if not can_reveal: v.get_child(v.get_child_count() - 2).disabled = true
		if Ads.available() and profile.tokens < Profile.TOKEN_CAP:
			var ab = _style(_btn("Watch an ad for +1 token", _ad_for_token), "ButtonSecondary")
			ab.name = "RewardedToken"
			v.add_child(ab)
	if not can_reveal: v.add_child(_label("Select an empty cell to reveal it.", 18, AP.DIGIT_NOTES))
	v.add_child(_style(_btn("Back to grid", _close_overlay, 24), "ButtonChip", "back"))
	Dbg.publish()

func _lock_overlay() -> void:
	if overlay:
		for b in overlay.find_children("*", "Button", true, false): b.disabled = true

func _ad_for_token() -> void:
	_lock_overlay()
	_ad_busy = true
	var ok = await Ads.rewarded("hint_token")
	_ad_busy = false
	if screen_name != "grid" or board == null: return
	if ok: profile.grant_tokens(1)
	save()
	if overlay:
		root.remove_child(overlay); overlay.queue_free(); overlay = null
	_open_hint_panel()
	if not ok: teach_label.text = "The ad didn't finish, so no token was added. You can try again."

func _pay_hint(kind: String, how: String) -> void:
	var s = {}
	if kind == "teach":
		var wrong = board.wrong_cells()
		if not wrong.is_empty():
			_close_overlay()
			grid_view.flag_cells = wrong
			last_teach = {"flag": wrong.map(func(c): return [c / board.size, c % board.size])}
			teach_label.text = "Some digits are wrong. Fix the highlighted cells first (no charge)."
			grid_view.queue_redraw()
			return
		# Find the step BEFORE charging: a paid Teach must always teach something new.
		var t0 = Time.get_ticks_usec()
		var hunt = not level.is_empty() and str(level.params.get("inner", level.objective)) == "digit"
		s = Sudoku.next_hint(board.correct_board(), board.solution, targets, board.taught, hunt)
		var ms = (Time.get_ticks_usec() - t0) / 1000.0
		source.log.append({"size": board.size, "source": "step", "ms": ms, "technique": s.get("technique", "")})
		print("[SD][timing] step size=%d ms=%.2f" % [board.size, ms])
		if s.is_empty():
			_close_overlay()
			var prev = board.active_hint()
			if not prev.is_empty():
				_show_step(prev, "No new step until you use this hint (no charge). ")
			else:
				teach_label.text = "No simple step found. Try notes! (no charge)"
			grid_view.queue_redraw()
			return
	else:
		var sel = grid_view.selected
		if sel < 0 or board.is_given(sel) or board.cells[sel] == board.solution[sel]: return   # nothing to reveal: never charge
	var paid = profile.spend_token() if how == "token" else profile.spend_coins(Profile.HINT_COIN_PRICE)
	if not paid: return
	_close_overlay()
	if kind == "teach":
		board.add_taught(s)
		_show_step(s)
		print("[SD] teach ", s.technique, " cells=", s.cells, " value=", s.value)
	else:
		var i = grid_view.selected
		if board.reveal(i) and not level.is_empty():
			elapsed_ms += 15000   # Reveal penalty (v1.2 §9.2)
		if _level_done():
			save(); _complete(); return
	save()
	grid_view.queue_redraw()

## Free: re-show the most recent taught step the player hasn't acted on yet.
func _reshow_hint() -> void:
	var prev = board.active_hint()
	_close_overlay()
	if prev.is_empty(): return
	_show_step(prev)
	grid_view.queue_redraw()

func _show_step(s: Dictionary, prefix: String = "") -> void:
	if Logic.is_placement(s):
		last_teach = {"cell": [s.cells[0] / board.size, s.cells[0] % board.size], "value": s.value, "technique": s.technique}
	else:
		last_teach = {"eliminations": s.eliminations.map(func(e): return [e[0] / board.size, e[0] % board.size, e[1]]), "technique": s.technique}
	grid_view.teach_cells = s.cells
	grid_view.teach_elims = s.eliminations
	teach_label.text = prefix + str(s.get("explanation", ""))

func _open_second_chance() -> void:
	var v = _open_overlay()
	overlay.name = "SecondChancePanel"
	var capped = profile.sc_capped(Dbg.now_ms())
	var only_retry = board.failed or board.second_chance_used or capped
	v.add_child(_heading("Out of mistakes!" if not board.failed else "Grid over", 36))
	if only_retry:
		var why = "You've used the second chance for this grid." if (board.second_chance_used or board.failed) else "Second chances are used up for now (3 per 24 hours)."
		v.add_child(_label(why, 22))
	else:
		v.add_child(_label("Keep your board and clear the wrong digits?", 22))
		_coin_option(v, "Continue", Profile.CONTINUE_COIN_PRICE, func(): _second_chance("coins"))
		if Ads.available():
			var ab = _style(_btn("Continue free (watch an ad)", func(): _second_chance("ad")), "ButtonSecondary")
			ab.name = "RewardedContinue"
			v.add_child(ab)
	var rb = _style(_btn("Retry from the start", _retry, 24), "ButtonChip", "undo"); rb.name = "RetryButton"
	v.add_child(rb)
	Dbg.publish()

func _second_chance(how: String) -> void:
	if how == "coins":
		if not profile.spend_coins(Profile.CONTINUE_COIN_PRICE): return
	else:
		_lock_overlay()
		_ad_busy = true
		var ok = await Ads.rewarded("second_chance")
		_ad_busy = false
		if screen_name != "grid" or board == null: return
		if not ok:
			if overlay:
				root.remove_child(overlay); overlay.queue_free(); overlay = null
			_open_second_chance()
			teach_label.text = "The ad didn't finish. Nothing was granted; you can try again."
			return
	profile.record_second_chance(Dbg.now_ms())
	board.apply_continue()
	continues += 1   # elapsed time kept
	save()
	_close_overlay()

func _retry() -> void:
	board.retry()
	elapsed_ms = 0
	continues = 0
	save()
	_close_overlay()
	_clear_teach()

# ---------------- results ----------------
func _complete() -> void:
	Sfx.play("complete")
	var r: Dictionary
	if not level.is_empty():
		var st = Obj.stars(level, board.any_mistake or board.used_continue, board.reveals, elapsed_ms)
		r = profile.complete_level(int(grid_meta.path_index), board.size, st)
		print("[SD] level %d complete: stars=%d elapsed_ms=%d" % [int(grid_meta.path_index) + 1, st, elapsed_ms])
	else:
		r = profile.complete_grid(grid_meta.mode, board.size)
	level = {}
	targets = []
	profile.current_grid = {}
	policy.on_grid_completed()
	board = null
	Ads.set_context("results")
	save()
	_show_results(r)

func _show_results(r: Dictionary) -> void:
	var offer = policy.results_offer(Time.get_ticks_msec(), Ads.available())
	print("[SD] results offer = ", offer)
	_results = {"r": r, "offer": offer, "doubled": false}
	_build_results()
	if offer == "midgame":
		await Ads.midgame("results")
	Dbg.publish()

## Results UI from _results (also used to rebuild it after a resize without re-running the ad offer).
func _build_results() -> void:
	var r: Dictionary = _results.r
	screen_name = "results"
	_clear()
	var v = _center_box()
	v.add_child(_heading("Level complete!" if r.has("level_stars") else "Grid complete!", 40, true))
	if r.has("level_stars"):
		var row = HBoxContainer.new(); row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", _u(10))
		for k in 3:   # earned = gold star, missing = faint ink outline (never colour-only: the label says it too)
			row.add_child(_icon_rect("star", "gold" if k < int(r.level_stars) else "ink", _u(64), 1.0 if k < int(r.level_stars) else 0.3))
		v.add_child(row)
		var sl = _label("Stars: %d / 3" % r.level_stars, 26, AP.TEXT_INK)
		sl.add_theme_font_override("font", load(AP.FONT_UI_BOLD))
		sl.name = "LevelStars"
		v.add_child(sl)
	results_label = _label("+%d coins   +%d stars%s%s" % [r.coins, r.stars, ("   +1 token" if r.token > 0 else ""), ("  (doubled!)" if _results.doubled else "")], 28)
	results_label.name = "ResultsRewards"
	results_label.set_meta("r", r)
	v.add_child(results_label)
	if _results.offer == "rewarded" and not _results.doubled:
		var cb = int(_results.get("base_coins", r.coins))
		_results["base_coins"] = cb
		var ab = _style(_btn("Double coins (watch an ad)", func(): _double(cb)), "ButtonSecondary", "coin")
		ab.name = "RewardedDouble"
		ab.disabled = _ad_busy
		v.add_child(ab)
	v.add_child(_btn("Continue", show_harbour, 28, 72))

func _double(c: int) -> void:
	var b = root.find_child("RewardedDouble", true, false)
	if b: b.disabled = true
	_ad_busy = true
	var ok = await Ads.rewarded("double_coins")
	_ad_busy = false
	b = root.find_child("RewardedDouble", true, false)   # the screen may have been rebuilt (rotation) during the ad
	if ok:
		profile.coins += c
		save()
		var rr: Dictionary = _results.get("r", results_label.get_meta("r") if is_instance_valid(results_label) else {})
		if not rr.is_empty(): rr.coins = rr.coins + c
		if _results.has("r"): _results.doubled = true
		if is_instance_valid(b):
			b.get_parent().remove_child(b)
			b.queue_free()
		if is_instance_valid(results_label):
			var r: Dictionary = results_label.get_meta("r")
			results_label.text = "+%d coins   +%d stars%s  (doubled!)" % [r.coins, r.stars, ("   +1 token" if r.token > 0 else "")]
	elif is_instance_valid(b):
		b.disabled = false
		b.text = "Ad failed - tap to try again"

## H5: board/state dump in qa/sudoku_check.py --step format (+ notes, mistakes, undo stack).
func step_dump():
	if board == null: return null
	var n = board.size
	var g2 = func(a):
		var o = []
		for r in n: o.append(a.slice(r * n, (r + 1) * n))
		return o
	return {"level": grid_meta.get("level", null), "objective": level.get("objective", null), "params": level.get("params", null),
		"target": targets.map(func(c): return [c / n, c % n]), "elapsed_ms": elapsed_ms, "reveals": board.reveals, "continues": continues,
		"par_time_s": level.get("par_time_s", null), "timer_running": timer_running(),
		"size": n, "grid": g2.call(board.cells), "givens": g2.call(board.givens), "solution": g2.call(board.solution),
		"notes": board.notes, "mistakes": board.mistakes, "undo": board.history, "game_step": last_teach if not last_teach.is_empty() else null}
