## QA run7: headless hint-memory check (paid Teach repeated without placing). Not part of the game.
## godot --headless --path <wt> -s /workspace/sudoku-dash/qa/hint_memory.gd -- out=/abs/file.json n=4
## Mirrors ui/main.gd _pay_hint: s = Sudoku.next_hint(correct_board, solution, targets, taught, hunt);
## empty -> free re-show of board.active_hint(); else board.add_taught(s) (paid).
extends SceneTree
const Sudoku = preload("res://sudoku/sudoku.gd")
const BoardState = preload("res://game/board_state.gd")
func _init() -> void:
	var a := {}
	for s in OS.get_cmdline_user_args():
		var kv = s.split("="); a[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var n := int(a.get("n", "4")); var rng := RandomNumberGenerator.new(); rng.seed = 7
	var D = JSON.parse_string(FileAccess.get_file_as_string("res://data/levels/harbour.json"))
	var res := []
	var cases := []
	for lv in D.levels: cases.append(lv)
	# plus Quick/Classic-style 9x9 boards with no targets
	for pk in ["9x9_t1", "9x9_t2", "9x9_t3", "9x9_t4"]: cases.append({"level": 0, "pack": pk, "index": 3, "size": 9, "target": [], "objective": "none", "params": {}})
	for lv in cases:
		var sz := int(lv.size)
		var pack = lv.get("pack", ""); var idx = int(lv.get("index", 0))
		if lv.level != 0:
			var gr = D.grids[lv.grid_id]; pack = gr.pack; idx = int(gr.index)
		var p = JSON.parse_string(FileAccess.get_file_as_string("res://data/packs/%s.json" % pack)).puzzles[idx]
		var t := []
		for rc in lv.target: t.append(int(rc[0]) * sz + int(rc[1]))
		var hunt = str(lv.params.get("inner", lv.objective)) == "digit"
		var giv: Array = []; var sol: Array = []
		for v in p.givens: giv.append(int(v))
		for v in p.solution: sol.append(int(v))
		for i in n:
			var b = BoardState.new(); b.setup(sz, giv.duplicate(), sol.duplicate())
			var empt := []
			for k in giv.size(): if giv[k] == 0: empt.append(k)
			empt.shuffle()
			var f := 0 if i == 0 else int(empt.size() * rng.randf_range(0.0, 0.6))
			for k in f: b.cells[empt[k]] = sol[empt[k]]
			var grid = b.correct_board()
			var seq := []; var reshow = {}; var ended := false
			for it in 200:
				var s = Sudoku.next_hint(b.correct_board(), b.solution, t, b.taught, hunt)
				if s.is_empty():
					reshow = b.active_hint(); ended = true; break
				b.add_taught(s)
				seq.append({"technique": s.technique, "cells": s.cells, "value": s.get("value", 0), "eliminations": s.get("eliminations", []), "touches_target": s.get("touches_target", false)})
			res.append({"level": lv.level, "objective": lv.objective, "hunt": hunt, "digit": int(lv.params.get("digit", 0)), "size": sz,
				"grid": grid, "solution": sol, "target": t, "steps": seq, "ended": ended, "reshow": reshow,
				"cells_unchanged": b.correct_board() == grid})
	var fo := FileAccess.open(a.get("out", "/tmp/hm.json"), FileAccess.WRITE); fo.store_string(JSON.stringify(res)); fo.close()
	print("boards ", res.size()); quit(0)
