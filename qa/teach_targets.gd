## QA run5 (LO C10): random partial boards per level -> Sudoku.step_for_targets dump. Not part of the game.
## godot --headless --path . -s qa/teach_targets.gd -- out=/abs/file.json n=40
extends SceneTree
const Sudoku = preload("res://sudoku/sudoku.gd")
func _init() -> void:
	var a := {}
	for s in OS.get_cmdline_user_args():
		var kv = s.split("="); a[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var n := int(a.get("n", "40")); var rng := RandomNumberGenerator.new(); rng.seed = 5
	var D = JSON.parse_string(FileAccess.get_file_as_string("res://data/levels/harbour.json"))
	var res := []
	for lv in D.levels:
		var gr = D.grids[lv.grid_id]; var sz := int(lv.size)
		var p = JSON.parse_string(FileAccess.get_file_as_string("res://data/packs/%s.json" % gr.pack)).puzzles[int(gr.index)]
		var t := []
		for rc in lv.target: t.append(int(rc[0]) * sz + int(rc[1]))
		for i in n:
			var g: Array = []
			for v in p.givens: g.append(int(v))
			var empt := []
			for k in g.size(): if g[k] == 0: empt.append(k)
			empt.shuffle()
			var f := int(empt.size() * rng.randf_range(0.0, 0.7))
			for k in f: g[empt[k]] = int(p.solution[empt[k]])
			var left := false
			for c in t: if g[c] == 0: left = true
			if not left: continue
			var st = Sudoku.step_for_targets(g, t)
			res.append({"level": lv.level, "grid": g, "solution": p.solution, "target": t, "step": st})
	var fo := FileAccess.open(a.get("out", "/tmp/tt.json"), FileAccess.WRITE); fo.store_string(JSON.stringify(res)); fo.close()
	print("boards ", res.size()); quit(0)
