extends GutTest
## Box readability: alternate boxes tinted on 4x4 / 6x6, heavier box lines.

const GridView = preload("res://ui/grid_view.gd")
const Shape = preload("res://sudoku/shape.gd")

func test_6x6_boxes_checkerboard():
	var s = Shape.of(6)
	var shaded = []
	for u in s.units.slice(12, 18):   # the six 2x3 boxes
		var first = GridView.box_shaded(s, u[0])
		for c in u: assert_eq(GridView.box_shaded(s, c), first, "a box is tinted as a whole")
		shaded.append(first)
	assert_eq(shaded.count(true), 3, "half the boxes tinted")
	# neighbours differ: box 0 (top-left) vs box 1 (top-right) and box 2 (below)
	assert_ne(shaded[0], shaded[1])
	assert_ne(shaded[0], shaded[2])

func test_4x4_tinted_9x9_plain():
	assert_true(GridView.box_shaded(Shape.of(4), 2))    # row 0, col 2: second box
	for i in 81: assert_false(GridView.box_shaded(Shape.of(9), i))
