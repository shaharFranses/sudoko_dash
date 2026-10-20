## QA (AC7/AC14): diverged-board live Teach dump. Not part of the game.
## godot --headless --path . -s qa/teach_diverge.gd -- out=/abs/dir n=50
## For 9x9 t3/t4 pack puzzles: fills a random 20-60% of empty cells with correct digits (an order that
## ignores the stored steps), calls Sudoku.step() live, writes {grid, solution, game_step, ms} per board.
extends SceneTree
const Sudoku = preload("res://sudoku/sudoku.gd")
func _init() -> void:
	var a := {}
	for s in OS.get_cmdline_user_args():
		var kv = s.split("="); a[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var out: String = a.get("out", "/tmp"); var n := int(a.get("n", "50"))
	var rng := RandomNumberGenerator.new(); rng.seed = 20261020
	var times := []
	if a.has("in"):   # mode 2: boards from a JSON list [{id, grid(flat)}] -> step per board
		var res := []
		for b in JSON.parse_string(FileAccess.get_file_as_string(a["in"])):
			var g: Array = []
			for v in b.grid: g.append(int(v))
			var t0 := Time.get_ticks_usec(); var st = Sudoku.step(g)
			var ms := (Time.get_ticks_usec() - t0) / 1000.0; times.append(ms)
			res.append({"id": b.id, "step": st, "ms": ms})
		var f := FileAccess.open(a.get("out_file", "/tmp/steps.json"), FileAccess.WRITE); f.store_string(JSON.stringify(res)); f.close()
		times.sort()
		print("step_ms(stuck boards) n=%d median=%.2f p95=%.2f max=%.2f" % [times.size(), times[times.size() / 2], times[int(times.size() * 0.95)], times[-1]])
		quit(0); return
	for t in [1, 2, 3, 4]:
		var pack = JSON.parse_string(FileAccess.get_file_as_string("res://data/packs/9x9_t%d.json" % t))
		for i in n:
			var p = pack.puzzles[i]
			var g: Array = []
			for v in p.givens: g.append(int(v))
			var sol: Array = []
			for v in p.solution: sol.append(int(v))
			var empties := []
			for k in g.size(): if g[k] == 0: empties.append(k)
			# reverse stored order bias: shuffle, then fill a random fraction
			for k in range(empties.size() - 1, 0, -1):
				var j = rng.randi_range(0, k); var tmp = empties[k]; empties[k] = empties[j]; empties[j] = tmp
			var fill := int(empties.size() * rng.randf_range(0.2, 0.6))
			for k in fill: g[empties[k]] = sol[empties[k]]
			var t0 := Time.get_ticks_usec()
			var st = Sudoku.step(g)
			var ms := (Time.get_ticks_usec() - t0) / 1000.0
			times.append(ms)
			var f := FileAccess.open("%s/t%d_%03d.json" % [out, t, i], FileAccess.WRITE)
			f.store_string(JSON.stringify({"size": 9, "tier": t, "id": p.id, "flat_grid": g, "flat_solution": sol, "step": st, "ms": ms}))
			f.close()
	times.sort()
	print("step_ms n=%d median=%.2f p95=%.2f max=%.2f" % [times.size(), times[times.size() / 2], times[int(times.size() * 0.95)], times[-1]])
	quit(0)
