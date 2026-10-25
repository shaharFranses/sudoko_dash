## Draws the sudoku grid and turns taps/clicks into cell selection. Board data lives in game/board_state.gd.
extends Control

signal cell_tapped(index: int)

var board = null
var selected: int = -1
var teach_cells: Array = []
var flag_cells: Array = []
var teach_elims: Array = []
var target_cells: Array = []
var lantern_path: Array = []
var flash_cell: int = -1
var flash_t: float = 0.0
var feedback_count: int = 0   # wrong-entry feedback events (tests/QA)
const FLASH_S = 0.45
const EDGE_INSET = 3.0

## Wrong entry: red flash on the cell + short horizontal shake of the grid.
func wrong_feedback(i: int) -> void:
	feedback_count += 1
	flash_cell = i
	flash_t = FLASH_S
	set_process(true)
	queue_redraw()

func _process(delta: float) -> void:
	if flash_t <= 0.0:
		set_process(false)
		return
	flash_t = maxf(0.0, flash_t - delta)
	queue_redraw()

func _shake() -> Vector2:
	if flash_t <= 0.0: return Vector2.ZERO
	var k = flash_t / FLASH_S
	return Vector2(cos((1.0 - k) * 40.0) * 6.0 * k, 0)

# Art kit v1 palette (assets/art/art_palette.gd); see docs/art/STYLE_GUIDE.md for the contrast table.
const AP = preload("res://assets/art/art_palette.gd")
const C_BG = AP.GRID_CELL
const C_LINE = AP.GRID_LINE_THIN
const C_THICK = AP.GRID_LINE_BOX
const C_GIVEN = AP.DIGIT_GIVEN
const C_ENTRY = AP.DIGIT_PLAYER
const C_WRONG = AP.ERROR_INK
const C_HL = AP.HL_PEER
const C_SAME = AP.HL_SAME
const C_SEL = AP.HL_SELECTED
const C_TEACH = Color("D9EBCB")   # soft sage: teach step (distinct from the butter selection)
const C_FLAG = AP.ERROR_CELL
const C_NOTES = AP.DIGIT_NOTES
const FONT_GIVEN = preload("res://assets/art/fonts/AtkinsonHyperlegibleNext-Bold.ttf")
const FONT_ENTRY = preload("res://assets/art/fonts/AtkinsonHyperlegibleNext-Medium.ttf")
const FONT_NOTES = preload("res://assets/art/fonts/AtkinsonHyperlegibleNext-Regular.ttf")

func _ready() -> void:
	set_process(false)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE

func cell_px() -> float:
	if board == null: return 0.0
	# Inset by the thick border width so the outer 3 px lines are drawn fully inside the control.
	return floor((minf(size.x, size.y) - 2.0 * EDGE_INSET) / board.size)

func origin() -> Vector2:
	var s = cell_px() * board.size
	return Vector2(floor((size.x - s) / 2.0), floor((size.y - s) / 2.0))

func _gui_input(e: InputEvent) -> void:
	if board == null: return
	var pos = Vector2.ZERO
	# Touch arrives as an emulated left click (input_devices/pointing/emulate_mouse_from_touch, default on).
	# Handling InputEventScreenTouch as well made one tap select/apply twice (a note toggled on and back off).
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		pos = e.position
	else:
		return
	var p = (pos - origin()) / cell_px()
	if p.x < 0 or p.y < 0 or p.x >= board.size or p.y >= board.size: return
	cell_tapped.emit(int(p.y) * board.size + int(p.x))
	accept_event()

func _draw() -> void:
	if board == null: return
	var n: int = board.size
	var cp = cell_px()
	var o = origin() + _shake()
	var font = FONT_NOTES
	# paper card: soft lilac shadow under the grid (never pure black)
	draw_rect(Rect2(o + Vector2(0, 4), Vector2(cp * n, cp * n)).grow(2), Color(AP.SHADOW_LILAC, 0.18))
	draw_rect(Rect2(o, Vector2(cp * n, cp * n)), C_BG)
	var sel_d = board.cells[selected] if selected >= 0 else 0
	for i in n * n:
		var r = Rect2(o + Vector2(i % n, i / n) * cp, Vector2(cp, cp))
		var col = Color(0, 0, 0, 0)
		if selected >= 0:
			if board.shape.row(i) == board.shape.row(selected) or board.shape.col(i) == board.shape.col(selected) or board.shape.box(i) == board.shape.box(selected):
				col = C_HL
			if sel_d != 0 and board.cells[i] == sel_d: col = C_SAME
			if i == selected: col = C_SEL
		if i in teach_cells: col = C_TEACH
		if i in flag_cells: col = C_FLAG
		if i == flash_cell and flash_t > 0.0: col = C_FLAG.lerp(C_WRONG, 0.5 * flash_t / FLASH_S)
		if col.a > 0: draw_rect(r, col)
		var d: int = board.cells[i]
		if d != 0:
			var fs = int(cp * 0.68)
			var given = board.is_given(i)
			var wrong = not given and d != board.solution[i]
			var c = C_GIVEN if given else (C_WRONG if wrong else C_ENTRY)
			var df: Font = FONT_GIVEN if given else FONT_ENTRY
			var txt = str(d)
			var ts = df.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
			var asc = df.get_ascent(fs)
			var desc = df.get_descent(fs)
			var base = r.position + Vector2((cp - ts.x) / 2.0, (cp - (asc + desc)) / 2.0 + asc)
			draw_string(df, base, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, c)
			if wrong:   # never colour-only: a wrong digit is also underlined
				var uy = base.y + maxf(3.0, cp * 0.06)
				draw_line(Vector2(base.x - cp * 0.04, uy), Vector2(base.x + ts.x + cp * 0.04, uy), C_WRONG, maxf(2.0, cp * 0.05))
		elif board.notes[i] != 0:
			var bw: int = board.shape.box_w
			var bh: int = board.shape.box_h
			# notes laid out in a box_w x box_h mini grid (6x6: 3x2)
			var cols = bw if n != 4 else 2
			var rows = int(ceil(float(n) / cols))
			# Notes font = their mini cell (glyphs ~70% of it); 9x9 on a 360 px phone: ~11 CSS px.
			var fs2 = int(cp / max(rows, cols))
			for dd in range(1, n + 1):
				if board.notes[i] & (1 << (dd - 1)):
					var k = dd - 1
					var cell_w = cp / cols
					var cell_h = cp / rows
					var t = str(dd)
					var ts2 = font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2)
					var nc = C_NOTES
					for el in teach_elims:
						if el[0] == i and el[1] == dd: nc = C_WRONG
					draw_string(font, r.position + Vector2((k % cols) * cell_w + (cell_w - ts2.x) / 2.0, (k / cols) * cell_h + (cell_h + font.get_ascent(fs2) - font.get_descent(fs2)) / 2.0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, nc)
	# objective overlay: lantern chain, then target outlines
	for k in lantern_path.size():
		var c = lantern_path[k]
		var ctr = o + Vector2(c % n + 0.5, c / n + 0.5) * cp
		if k > 0:
			var p0 = lantern_path[k - 1]
			draw_line(o + Vector2(p0 % n + 0.5, p0 / n + 0.5) * cp, ctr, Color(AP.STAR_GOLD, 0.55), 3.0)
		var lit = board.cells[c] == board.solution[c]
		var lc = ctr + Vector2(cp * 0.36, -cp * 0.36)
		draw_circle(lc, cp * 0.09 + 1.5, AP.TEXT_INK if lit else AP.GRID_LINE_THIN)
		draw_circle(lc, cp * 0.09, AP.STAR_GOLD if lit else AP.HL_PEER)
	for c in target_cells:
		if c in lantern_path: continue
		var rr = Rect2(o + Vector2(c % n, c / n) * cp, Vector2(cp, cp)).grow(-3)
		draw_rect(rr, AP.ACCENT_TERRACOTTA if board.cells[c] != board.solution[c] else Color("4F7D45"), false, 2.5)
	for k in range(n + 1):
		var thick_v = k % board.shape.box_w == 0
		var thick_h = k % board.shape.box_h == 0
		draw_line(o + Vector2(k * cp, 0), o + Vector2(k * cp, n * cp), C_THICK if thick_v else C_LINE, 3.0 if thick_v else 1.5)
		draw_line(o + Vector2(0, k * cp), o + Vector2(n * cp, k * cp), C_THICK if thick_h else C_LINE, 3.0 if thick_h else 1.5)
