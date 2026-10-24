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

func _ready() -> void:
	Dbg.main = self
	policy = AdPolicy.new(Time.get_ticks_msec())
	await Store.wait_ready()   # don't read the save until the CrazyGames SDK init has settled
	var d = Store.load_data()
	if not d.is_empty(): profile.from_dict(d)
	var bg = ColorRect.new(); bg.color = Color("bfe3ef"); bg.set_anchors_preset(PRESET_FULL_RECT); add_child(bg)
	root = Control.new(); root.set_anchors_preset(PRESET_FULL_RECT); add_child(root)
	get_viewport().size_changed.connect(_relayout)
	show_title()

func save() -> void:
	if board and screen_name == "grid":
		profile.current_grid = {"meta": grid_meta, "board": board.to_dict(), "level": {"elapsed_ms": elapsed_ms, "continues": continues}}
	Store.save(profile.to_dict())
	Dbg.publish()

func _clear() -> void:
	overlay = null
	for c in root.get_children():
		root.remove_child(c)
		c.queue_free()

func _relayout() -> void:
	match screen_name:
		"grid": _build_grid_screen()
		"harbour": show_harbour()

# ---------------- widgets ----------------
func _btn(text: String, cb: Callable, fs: int = 26, min_h: int = 64) -> Button:
	var b = Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, min_h)
	b.add_theme_font_size_override("font_size", fs)
	b.pressed.connect(func(): Sfx.play("tap"))
	b.pressed.connect(cb)
	return b

func _label(text: String, fs: int = 24, col: Color = Color("1f2f3a")) -> Label:
	var l = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

func _center_box(min_w: int = 520) -> VBoxContainer:
	var cc = CenterContainer.new(); cc.set_anchors_preset(PRESET_FULL_RECT); root.add_child(cc)
	var panel = PanelContainer.new()
	var sb = StyleBoxFlat.new(); sb.bg_color = Color("fffaf0"); sb.set_corner_radius_all(18); sb.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", sb)
	cc.add_child(panel)
	var v = VBoxContainer.new(); v.custom_minimum_size = Vector2(min(min_w, get_viewport_rect().size.x - 40), 0)
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	return v

## Coin-priced button: disabled with price + "Need N more coins" line when unaffordable (never hidden).
func _coin_option(parent: Control, text: String, price: int, cb: Callable) -> void:
	var b = _btn("%s (%d coins)" % [text, price], cb)
	parent.add_child(b)
	var need = profile.need_more(price)
	var l = _label("Need %d more coins" % need if need > 0 else " ", 20, Color("b04040"))
	parent.add_child(l)
	b.disabled = need > 0

# ---------------- title / harbour ----------------
func show_title() -> void:
	screen_name = "title"
	Ads.set_context("menu")
	_clear()
	var v = _center_box()
	v.add_child(_label("Sudoku Dash", 56))
	v.add_child(_label("Restore the Harbour, one puzzle at a time.", 24))
	var play = _btn("Play", show_harbour, 34, 80)
	play.name = "PlayButton"
	v.add_child(play)
	print("[SD] title ready")
	Store.loading_stop()

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
	hv.size_flags_horizontal = SIZE_EXPAND_FILL; hv.size_flags_vertical = SIZE_EXPAND_FILL
	hv.custom_minimum_size = Vector2(300, 220)
	box.add_child(hv)
	var sc = ScrollContainer.new(); sc.custom_minimum_size = Vector2(460 if landscape else vp.x, 0 if landscape else vp.y * 0.55)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(sc)
	var v = VBoxContainer.new(); v.size_flags_horizontal = SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 8)
	sc.add_child(v)
	v.add_child(_label("Harbour  |  Stars %d   Coins %d   Tokens %d" % [profile.stars, profile.coins, profile.tokens], 24))
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
		var b = _btn("T%d" % t, func(): classic_tier = t; save(); show_harbour(), 22, 56)
		b.toggle_mode = true; b.button_pressed = t == classic_tier
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		tiers.add_child(b)
	v.add_child(tiers)
	v.add_child(_btn("Classic 9x9 (tier %d)" % classic_tier, start_classic, 24))
	v.add_child(_label("Tasks", 26))
	for t in Profile.TASKS:
		var row = HBoxContainer.new()
		var l = _label(t.name, 22); l.size_flags_horizontal = SIZE_EXPAND_FILL; l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.add_child(l)
		if profile.tasks.has(t.id):
			var ch = profile.decor.get(t.id, 0)
			var id = t.id
			var n = t.decor.size()
			row.add_child(_btn(t.decor[ch], func(): profile.set_decor(id, (ch + 1) % n); save(); show_harbour(), 20, 56))
		else:
			var id2 = t.id
			var b = _btn("Buy (%d stars)" % t.cost if profile.task_unlocked(t.id) else "Locked", func(): _buy_task(id2), 20, 56)
			b.disabled = profile.stars < t.cost or not profile.task_unlocked(t.id)
			row.add_child(b)
		v.add_child(row)
	if profile.area_restored():
		v.add_child(_btn("Area restored!", show_area_restored, 24))

func _buy_task(id: String) -> void:
	if profile.buy_task(id):
		save()
		if profile.area_restored():
			show_area_restored()
			return
	show_harbour()

func show_area_restored() -> void:
	screen_name = "restored"
	_clear()
	var v = _center_box()
	v.add_child(_label("Area restored!", 48))
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
	var vp = get_viewport_rect().size
	var landscape = vp.x >= vp.y
	# Safe margin so the grid's outer border and the side column never touch the canvas edge
	# (QA run 6: bottom border clipped at 1280x800 in Chrome).
	var mc = MarginContainer.new(); mc.set_anchors_preset(PRESET_FULL_RECT)
	for side_name in ["margin_left", "margin_right", "margin_bottom"]: mc.add_theme_constant_override(side_name, GRID_MARGIN)
	mc.add_theme_constant_override("margin_top", 0)
	root.add_child(mc)
	var outer = VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	mc.add_child(outer)
	var top = HBoxContainer.new(); top.custom_minimum_size = Vector2(0, 64)
	outer.add_child(top)
	top.add_child(_btn("Back", _leave_grid, 26, 60))
	var title = "Level %d/%d" % [grid_meta.path_index + 1, Profile.path_length()] if grid_meta.mode == "path" else ("Quick 6x6" if grid_meta.mode == "quick" else "Classic 9x9 T%d" % grid_meta.tier)
	var tl = _label(title, 24); tl.size_flags_horizontal = SIZE_EXPAND_FILL
	tl.autowrap_mode = TextServer.AUTOWRAP_OFF; tl.clip_text = true
	top.add_child(tl)
	mistakes_label = _label("", 24)
	mistakes_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	top.add_child(mistakes_label)
	var hint = _btn("Hint", _open_hint_panel, 26, 60); hint.name = "HintButton"
	top.add_child(hint)
	var body = HBoxContainer.new() if landscape else VBoxContainer.new()
	body.size_flags_vertical = SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	outer.add_child(body)
	grid_view = GridView.new()
	grid_view.board = board
	grid_view.selected = sel
	grid_view.size_flags_horizontal = SIZE_EXPAND_FILL
	grid_view.size_flags_vertical = SIZE_EXPAND_FILL
	grid_view.cell_tapped.connect(_on_cell)
	# Digit Hunt: never outline T (it would reveal where the digit goes). Counter only.
	grid_view.target_cells = [] if (not level.is_empty() and str(level.params.get("inner", level.objective)) == "digit") else targets
	grid_view.lantern_path = []
	if not level.is_empty():
		var inner = str(level.params.get("inner", level.objective))
		if level.objective == "lantern":
			for rc in level.params.path: grid_view.lantern_path.append(int(rc[0]) * board.size + int(rc[1]))
	body.add_child(grid_view)
	var side = VBoxContainer.new()
	side.custom_minimum_size = Vector2(min(420, vp.x * 0.4) if landscape else vp.x - 2 * GRID_MARGIN, 0 if landscape else min(vp.y * 0.38, 360))
	side.add_theme_constant_override("separation", 8)
	body.add_child(side)
	objective_label = _label("", 22, Color("1d4f73"))
	objective_label.name = "ObjectiveLabel"
	side.add_child(objective_label)
	tide_bar = ProgressBar.new()
	tide_bar.name = "TideBar"
	tide_bar.show_percentage = false
	tide_bar.custom_minimum_size = Vector2(0, 18)
	tide_bar.visible = not level.is_empty() and Obj.is_timed(level)
	side.add_child(tide_bar)
	timer_debug_label = null
	if Dbg.enabled:   # H7: on-screen timer readout (debug builds only)
		timer_debug_label = _label("", 16, Color("7a2a2a"))
		timer_debug_label.name = "TimerDebug"
		side.add_child(timer_debug_label)
	teach_label = _label("", 20, Color("6a4b00"))
	side.add_child(teach_label)
	var pad = GridContainer.new()
	pad.columns = 3 if board.size == 9 or board.size == 6 else 2
	if not landscape: pad.columns = board.size if board.size <= 6 else 5
	pad.size_flags_vertical = SIZE_EXPAND_FILL
	pad.add_theme_constant_override("h_separation", 8); pad.add_theme_constant_override("v_separation", 8)
	side.add_child(pad)
	for d in range(1, board.size + 1):
		var b = _btn(str(d), _on_digit.bind(d), 34, 64)
		b.name = "Digit%d" % d
		b.custom_minimum_size = Vector2(64, 64)
		b.size_flags_horizontal = SIZE_EXPAND_FILL; b.size_flags_vertical = SIZE_EXPAND_FILL
		b.toggle_mode = true
		b.button_pressed = digit_lock == d
		pad.add_child(b)
	var tools = HBoxContainer.new(); tools.add_theme_constant_override("separation", 8)
	side.add_child(tools)
	notes_btn = _btn("Notes: OFF", _toggle_notes, 22, 64); notes_btn.name = "NotesButton"
	notes_btn.size_flags_horizontal = SIZE_EXPAND_FILL
	tools.add_child(notes_btn)
	var ub = _btn("Undo", _undo, 22, 64); ub.name = "UndoButton"; ub.size_flags_horizontal = SIZE_EXPAND_FILL
	tools.add_child(ub)
	var eb = _btn("Erase", _erase, 22, 64); eb.name = "EraseButton"; eb.size_flags_horizontal = SIZE_EXPAND_FILL
	tools.add_child(eb)
	status_label = _label("", 18, Color("40505a"))
	side.add_child(status_label)
	_refresh()

func _refresh() -> void:
	if board == null or grid_view == null: return
	mistakes_label.text = ("Mistakes %d/%d" % [board.mistakes, board.max_mistakes]) if board.max_mistakes > 0 else "Warm-up: no mistake limit"
	notes_btn.text = "Notes: ON" if notes_mode else "Notes: OFF"
	status_label.text = "Tap a cell then a digit, or a digit then cells. Keys: 1-%d, arrows, Backspace, N, Ctrl+Z" % board.size
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
	var dim = ColorRect.new(); dim.color = Color(0.1, 0.15, 0.2, 0.82); dim.set_anchors_preset(PRESET_FULL_RECT)
	overlay.add_child(dim)
	var cc = CenterContainer.new(); cc.set_anchors_preset(PRESET_FULL_RECT); overlay.add_child(cc)
	var panel = PanelContainer.new()
	var sb = StyleBoxFlat.new(); sb.bg_color = Color("fffaf0"); sb.set_corner_radius_all(18); sb.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", sb)
	cc.add_child(panel)
	var v = VBoxContainer.new(); v.custom_minimum_size = Vector2(min(560, get_viewport_rect().size.x - 40), 0)
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	return v

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
	v.add_child(_label("Hint", 36))
	v.add_child(_label("Tokens: %d   Coins: %d" % [profile.tokens, profile.coins], 22))
	var sel = grid_view.selected
	var can_reveal = sel >= 0 and not board.is_given(sel) and board.cells[sel] != board.solution[sel]
	if not board.active_hint().is_empty():
		var again = _btn("Show my last hint again (free)", _reshow_hint)
		again.name = "ReshowHint"
		v.add_child(again)
	if profile.tokens > 0:
		v.add_child(_btn("Teach me the next step (1 token)", func(): _pay_hint("teach", "token")))
		var rb = _btn("Reveal selected cell (1 token)", func(): _pay_hint("reveal", "token"))
		rb.disabled = not can_reveal
		v.add_child(rb)
	else:
		_coin_option(v, "Teach me the next step", Profile.HINT_COIN_PRICE, func(): _pay_hint("teach", "coins"))
		_coin_option(v, "Reveal selected cell", Profile.HINT_COIN_PRICE, func(): _pay_hint("reveal", "coins"))
		if not can_reveal: v.get_child(v.get_child_count() - 2).disabled = true
		if Ads.available() and profile.tokens < Profile.TOKEN_CAP:
			var ab = _btn("Watch an ad for +1 token", _ad_for_token)
			ab.name = "RewardedToken"
			v.add_child(ab)
	if not can_reveal: v.add_child(_label("Select an empty cell to reveal it.", 18, Color("40505a")))
	v.add_child(_btn("Back to grid", _close_overlay, 24))
	Dbg.publish()

func _lock_overlay() -> void:
	if overlay:
		for b in overlay.find_children("*", "Button", true, false): b.disabled = true

func _ad_for_token() -> void:
	_lock_overlay()
	var ok = await Ads.rewarded("hint_token")
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
	v.add_child(_label("Out of mistakes!" if not board.failed else "Grid over", 36))
	if only_retry:
		var why = "You've used the second chance for this grid." if (board.second_chance_used or board.failed) else "Second chances are used up for now (3 per 24 hours)."
		v.add_child(_label(why, 22))
	else:
		v.add_child(_label("Keep your board and clear the wrong digits?", 22))
		_coin_option(v, "Continue", Profile.CONTINUE_COIN_PRICE, func(): _second_chance("coins"))
		if Ads.available():
			var ab = _btn("Continue free (watch an ad)", func(): _second_chance("ad"))
			ab.name = "RewardedContinue"
			v.add_child(ab)
	var rb = _btn("Retry from the start", _retry, 24); rb.name = "RetryButton"
	v.add_child(rb)
	Dbg.publish()

func _second_chance(how: String) -> void:
	if how == "coins":
		if not profile.spend_coins(Profile.CONTINUE_COIN_PRICE): return
	else:
		_lock_overlay()
		var ok = await Ads.rewarded("second_chance")
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
	screen_name = "results"
	_clear()
	var v = _center_box()
	v.add_child(_label("Level complete!" if r.has("level_stars") else "Grid complete!", 40))
	if r.has("level_stars"):
		var sl = _label("Stars: %d / 3" % r.level_stars, 30, Color("b8860b"))
		sl.name = "LevelStars"
		v.add_child(sl)
	results_label = _label("+%d coins   +%d stars%s" % [r.coins, r.stars, ("   +1 token" if r.token > 0 else "")], 28)
	results_label.name = "ResultsRewards"
	results_label.set_meta("r", r)
	v.add_child(results_label)
	var offer = policy.results_offer(Time.get_ticks_msec(), Ads.available())
	print("[SD] results offer = ", offer)
	if offer == "rewarded":
		var cb = r.coins
		var ab = _btn("Double coins (watch an ad)", func(): _double(cb))
		ab.name = "RewardedDouble"
		v.add_child(ab)
	v.add_child(_btn("Continue", show_harbour, 28, 72))
	if offer == "midgame":
		await Ads.midgame("results")
	Dbg.publish()

func _double(c: int) -> void:
	var b = root.find_child("RewardedDouble", true, false)
	if b: b.disabled = true
	var ok = await Ads.rewarded("double_coins")
	if ok:
		profile.coins += c
		save()
		if is_instance_valid(b):
			b.get_parent().remove_child(b)
			b.queue_free()
		if is_instance_valid(results_label):
			var r: Dictionary = results_label.get_meta("r")
			r.coins = r.coins + c
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
