## Grid geometry for 4x4 (2x2 boxes), 6x6 (2x3 boxes), 9x9 (3x3 boxes). Cells are row*size+col.
extends RefCounted

var size: int
var box_h: int
var box_w: int
var cells: int
var full_mask: int
var units: Array = []        # Array[Array[int]]; rows 0..n-1, cols n..2n-1, boxes 2n..3n-1
var cell_units: Array = []   # per cell: [row_unit, col_unit, box_unit]
var peers: Array = []        # per cell: Array[int]

static var _cache = {}

static func of(n: int):
	if not _cache.has(n):
		_cache[n] = load("res://sudoku/shape.gd").new(n)
	return _cache[n]

func _init(n: int) -> void:
	assert(n == 4 or n == 6 or n == 9, "unsupported size")
	size = n
	match n:
		4: box_h = 2; box_w = 2
		6: box_h = 2; box_w = 3
		9: box_h = 3; box_w = 3
	cells = n * n
	full_mask = (1 << n) - 1
	for r in n:
		var u = []
		for c in n: u.append(r * n + c)
		units.append(u)
	for c in n:
		var u = []
		for r in n: u.append(r * n + c)
		units.append(u)
	for b in n:
		var u = []
		var r0 = (b / (n / box_w)) * box_h
		var c0 = (b % (n / box_w)) * box_w
		for dr in box_h:
			for dc in box_w:
				u.append((r0 + dr) * n + c0 + dc)
		units.append(u)
	for i in cells:
		var r = i / n
		var c = i % n
		var b = (r / box_h) * (n / box_w) + c / box_w
		cell_units.append([r, n + c, 2 * n + b])
		var p = {}
		for ui in cell_units[i]:
			for j in units[ui]:
				if j != i: p[j] = true
		peers.append(p.keys())

func row(i: int) -> int: return i / size
func col(i: int) -> int: return i % size
func box(i: int) -> int: return cell_units[i][2] - 2 * size

static func popcount(m: int) -> int:
	var c = 0
	while m:
		m &= m - 1
		c += 1
	return c

## Lowest digit (1-based) in mask.
static func first_digit(m: int) -> int:
	var d = 1
	while (m & 1) == 0:
		m >>= 1
		d += 1
	return d

static func digits(m: int) -> Array:
	var out = []
	var d = 1
	while m:
		if m & 1: out.append(d)
		m >>= 1
		d += 1
	return out
