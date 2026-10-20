## Draws the sudoku grid and turns taps/clicks into cell selection. Board data lives in game/board_state.gd.
extends Control

signal cell_tapped(index: int)

var board = null
var selected: int = -1
var teach_cells: Array = []
var flag_cells: Array = []
var teach_elims: Array = []
var flash_cell: int = -1
var flash_t: float = 0.0
var feedback_count: int = 0   # wrong-entry feedback events (tests/QA)
const FLASH_S = 0.45

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

const C_BG = Color("fffdf7")
const C_LINE = Color("8aa2b0")
const C_THICK = Color("2d4a5a")
const C_GIVEN = Color("1f2f3a")
const C_ENTRY = Color("2a6fdb")
const C_WRONG = Color("d23c3c")
const C_HL = Color("e3f0f7")
const C_SAME = Color("bcdcf0")
const C_SEL = Color("8fc6ea")
const C_TEACH = Color("ffe38a")
const C_FLAG = Color("ffc2c2")

func _ready() -> void:
	set_process(false)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE

func cell_px() -> float:
	if board == null: return 0.0
	return floor(minf(size.x, size.y) / board.size)

func origin() -> Vector2:
	var s = cell_px() * board.size
	return Vector2(floor((size.x - s) / 2.0), floor((size.y - s) / 2.0))

func _gui_input(e: InputEvent) -> void:
	if board == null: return
	var pos = Vector2.ZERO
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		pos = e.position
	elif e is InputEventScreenTouch and e.pressed:
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
	var font = get_theme_default_font()
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
			var fs = int(cp * 0.66)
			var c = C_GIVEN if board.is_given(i) else (C_WRONG if d != board.solution[i] else C_ENTRY)
			var txt = str(d)
			var ts = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
			var asc = font.get_ascent(fs)
			var desc = font.get_descent(fs)
			draw_string(font, r.position + Vector2((cp - ts.x) / 2.0, (cp - (asc + desc)) / 2.0 + asc), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, c)
		elif board.notes[i] != 0:
			var bw: int = board.shape.box_w
			var bh: int = board.shape.box_h
			# notes laid out in a box_w x box_h mini grid (6x6: 3x2)
			var cols = bw if n != 4 else 2
			var rows = int(ceil(float(n) / cols))
			var fs2 = int(cp / max(rows, cols) * 0.8)
			for dd in range(1, n + 1):
				if board.notes[i] & (1 << (dd - 1)):
					var k = dd - 1
					var cell_w = cp / cols
					var cell_h = cp / rows
					var t = str(dd)
					var ts2 = font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2)
					var nc = Color("5c7080")
					for el in teach_elims:
						if el[0] == i and el[1] == dd: nc = C_WRONG
					draw_string(font, r.position + Vector2((k % cols) * cell_w + (cell_w - ts2.x) / 2.0, (k / cols) * cell_h + (cell_h + font.get_ascent(fs2) - font.get_descent(fs2)) / 2.0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, nc)
	for k in range(n + 1):
		var thick_v = k % board.shape.box_w == 0
		var thick_h = k % board.shape.box_h == 0
		draw_line(o + Vector2(k * cp, 0), o + Vector2(k * cp, n * cp), C_THICK if thick_v else C_LINE, 3.0 if thick_v else 1.0)
		draw_line(o + Vector2(0, k * cp), o + Vector2(n * cp, k * cp), C_THICK if thick_h else C_LINE, 3.0 if thick_h else 1.0)
