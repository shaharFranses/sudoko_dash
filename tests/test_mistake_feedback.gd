extends GutTest
## Shahar feedback: 4x4 warm-up label; clear feedback on every wrong entry for all sizes.

var main

func before_each():
	Store.clear()
	main = load("res://scenes/main.tscn").instantiate()
	add_child_autofree(main)
	await wait_frames(2)

func _start(size: int):
	match size:
		4: main.profile.path_next = 0; main.start_path_grid()
		6: main.profile.path_next = 5; main.start_path_grid()
		9: main.classic_tier = 1; main.start_classic()

func test_label_4x4_warmup():
	_start(4)
	assert_eq(main.mistakes_label.text, "Warm-up: no mistake limit")

func test_label_6x6_and_9x9_counter():
	_start(6)
	assert_eq(main.mistakes_label.text, "Mistakes 0/3")
	_start(9)
	assert_eq(main.mistakes_label.text, "Mistakes 0/3")

func test_4x4_label_unchanged_after_mistakes_and_no_panel():
	_start(4)
	var b = main.board
	var i = b.cells.find(0)
	for k in 4:
		main._on_cell(i); main._on_digit(((b.solution[i] + k) % 4) + 1 if ((b.solution[i] + k) % 4) + 1 != b.solution[i] else ((b.solution[i] + k + 1) % 4) + 1)
	assert_eq(main.mistakes_label.text, "Warm-up: no mistake limit")
	assert_null(main.overlay)

func _check_feedback(size: int):
	_start(size)
	var b = main.board
	var gv = main.grid_view
	var i = b.cells.find(0)
	var wrong = (b.solution[i] % size) + 1
	Sfx.played.clear()
	var before = gv.feedback_count
	main._on_cell(i); main._on_digit(wrong)
	assert_eq(gv.feedback_count, before + 1, "%dx%d flash/shake fired" % [size, size])
	assert_eq(gv.flash_cell, i)
	assert_gt(gv.flash_t, 0.0)
	assert_ne(gv._shake(), Vector2.ZERO, "shake offset active")
	assert_eq(Sfx.played.back(), "mistake")
	assert_eq(b.cells[i], wrong, "wrong digit shown (drawn red)")
	assert_ne(b.cells[i], b.solution[i])
	await wait_seconds(0.6)
	assert_eq(gv.flash_t, 0.0, "flash ends")
	assert_eq(gv._shake(), Vector2.ZERO)
	# correct entry: no feedback
	main._on_cell(i); main._on_digit(b.solution[i])
	assert_eq(gv.feedback_count, before + 1)
	assert_eq(Sfx.played.back(), "place")

func test_feedback_4x4(): await _check_feedback(4)
func test_feedback_6x6(): await _check_feedback(6)
func test_feedback_9x9(): await _check_feedback(9)

func test_notes_never_trigger_feedback():
	_start(6)
	var gv = main.grid_view
	var i = main.board.cells.find(0)
	main._toggle_notes()
	main._on_cell(i); main._on_digit((main.board.solution[i] % 6) + 1)
	assert_eq(gv.feedback_count, 0)
