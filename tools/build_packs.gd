## Offline puzzle-pack builder (headless Godot CLI). Never used at runtime.
## Usage:
##   godot --headless --path . -s tools/build_packs.gd -- size=9 tier=3 count=300 [shard=0 shards=1] [out=res://data/packs/9x9_t3.json]
##   godot --headless --path . -s tools/build_packs.gd -- merge size=9 tier=3 shards=6
## Puzzle i uses seed i (seed = index), so any entry can be regenerated with Sudoku.generate(size, tier, i).
## Every entry is verified: solver count == 1, grade(givens).tier == tier, solution matches.
extends SceneTree

const Sudoku = preload("res://sudoku/sudoku.gd")

func _init() -> void:
	var a := {}
	for s in OS.get_cmdline_user_args():
		var kv = s.split("=")
		a[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var size := int(a.get("size", "9"))
	var tier := int(a.get("tier", "1"))
	var count := int(a.get("count", "300"))
	var shards := int(a.get("shards", "1"))
	var shard := int(a.get("shard", "0"))
	var base := "res://data/packs/%dx%d_t%d" % [size, size, tier]
	if a.has("merge"):
		var all := []
		for k in shards:
			var f := FileAccess.open(base + ".shard%d.json" % k, FileAccess.READ)
			all.append_array(JSON.parse_string(f.get_as_text()).puzzles)
			f.close()
			DirAccess.remove_absolute(ProjectSettings.globalize_path(base + ".shard%d.json" % k))
		all.sort_custom(func(x, y): return x.seed < y.seed)
		_write(a.get("out", base + ".json"), size, tier, all)
		print("merged %d puzzles -> %s" % [all.size(), base + ".json"])
		quit(0)
		return
	var out: String = a.get("out", base + (".shard%d.json" % shard if shards > 1 else ".json"))
	var puzzles := []
	var t0 := Time.get_ticks_msec()
	var i := shard
	while i < count:
		var p := Sudoku.generate(size, tier, i)
		var chk := Sudoku.solve(p.givens)
		var gr := Sudoku.grade(p.givens)
		if p.tier != tier or chk.count != 1 or gr.tier != tier or chk.solution != p.solution:
			push_error("seed %d failed verification (tier %d, count %d)" % [i, gr.tier, chk.count])
			quit(1)
			return
		puzzles.append({"id": "%dx%d_t%d_%04d" % [size, size, tier, i], "seed": i, "tier": tier,
			"givens": p.givens, "solution": p.solution, "steps": Sudoku.compact_steps(gr.steps)})
		i += shards
	_write(out, size, tier, puzzles)
	print("wrote %d puzzles to %s in %d ms" % [puzzles.size(), out, Time.get_ticks_msec() - t0])
	quit(0)

func _write(path: String, size: int, tier: int, puzzles: Array) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"format": 1, "size": size, "tier": tier, "count": puzzles.size(),
		"generator": "sudoku/sudoku.gd generate(size, tier, seed)", "puzzles": puzzles}))
	f.close()
