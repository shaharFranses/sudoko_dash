## Builds res://data/target_vectors.json for analyze_targets() (C# port verification).
## godot --headless --path . -s tools/export_target_vectors.gd
extends SceneTree

const Sudoku = preload("res://sudoku/sudoku.gd")

func _ints(a):
	var o = []
	for x in a: o.append(int(x))
	return o

func _init() -> void:
	var cases = []
	var S4 = [1,2,3,4, 3,4,1,2, 2,1,4,3, 4,3,2,1]
	var g = S4.duplicate(); g[0] = 0; g[5] = 0
	cases.append({"name": "4x4_hand_two_holes", "size": 4, "givens": g, "targets": [5]})
	cases.append({"name": "4x4_given_target", "size": 4, "givens": g, "targets": [1]})
	cases.append({"name": "4x4_empty_targets", "size": 4, "givens": g, "targets": []})
	var e = []; e.resize(16); e.fill(0)
	cases.append({"name": "4x4_empty_grid_stuck", "size": 4, "givens": e, "targets": [0]})
	var bad = S4.duplicate(); bad[1] = 1
	cases.append({"name": "4x4_conflict", "size": 4, "givens": bad, "targets": [0]})
	cases.append({"name": "4x4_invalid_cells", "size": 4, "givens": g, "targets": [-1, 16]})
	for spec in [[4, 1, 7], [6, 2, 11], [9, 3, 0], [9, 4, 0]]:
		var gv: Array
		if spec[0] == 9:
			var pk = JSON.parse_string(FileAccess.get_file_as_string("res://data/packs/9x9_t%d.json" % spec[1])).puzzles[spec[2]]
			gv = _ints(pk.givens)
		else:
			gv = Sudoku.generate(spec[0], spec[1], spec[2]).givens
		var empties = []
		for i in gv.size():
			if gv[i] == 0: empties.append(i)
		var n = spec[0]
		cases.append({"name": "%dx%d_t%d_all_empty" % [n, n, spec[1]], "size": n, "givens": gv, "targets": empties})
		cases.append({"name": "%dx%d_t%d_three_targets" % [n, n, spec[1]], "size": n, "givens": gv,
			"targets": [empties[0], empties[empties.size() / 2], empties[empties.size() - 1]]})
	for c in cases:
		var r = Sudoku.analyze_targets(c.givens, c.size, c.targets)
		c["expected"] = r
	var f = FileAccess.open("res://data/target_vectors.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"format": 1, "function": "analyze_targets(givens, size, target_cells)",
		"notes": "steps counted over the full grade() step log (eliminations included), 1-based; order lists non-given targets in fill order.",
		"count": cases.size(), "vectors": cases}, "  "))
	f.close()
	print("wrote %d target vectors" % cases.size())
	quit(0)
