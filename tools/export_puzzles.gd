## Headless seeded puzzle export CLI (QA hook G6) and test-vector builder.
## Usage:
##   godot --headless --path . -s tools/export_puzzles.gd -- size=6 tier=2 seeds=0-99 [out=user://x.json] [format=json|jsonl]
##   godot --headless --path . -s tools/export_puzzles.gd -- vectors   (rebuilds res://data/test_vectors.json)
## jsonl output matches qa/sudoku_check.py input (one {"size","givens","solution","tier"} per line).
extends SceneTree

const Sudoku = preload("res://sudoku/sudoku.gd")

func _entry(size: int, tier: int, seed_value: int) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var p := Sudoku.generate(size, tier, seed_value)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	var gr := Sudoku.grade(p.givens)
	var techs := {}
	for s in gr.steps: techs[s.technique] = true
	var t := techs.keys()
	t.sort()
	var first := Sudoku.step(p.givens)
	return {"size": size, "requested_tier": tier, "seed": seed_value, "givens": p.givens, "solution": p.solution,
		"tier": gr.tier, "techniques": t, "solution_count": Sudoku.solve(p.givens).count,
		"first_step": {"technique": first.technique, "cells": first.cells, "value": first.value, "eliminations": first.eliminations},
		"gen_ms": ms}

func _init() -> void:
	var a := {}
	for s in OS.get_cmdline_user_args():
		var kv = s.split("=")
		a[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var rows := []
	var out: String
	if a.has("vectors"):
		out = "res://data/test_vectors.json"
		for size in [4, 6, 9]:
			for tier in Sudoku.valid_tiers(size):
				for sd in 10:
					var e := _entry(size, tier, 1000 + sd)
					e.erase("gen_ms")
					rows.append(e)
		var f := FileAccess.open(out, FileAccess.WRITE)
		f.store_string(JSON.stringify({"format": 1, "description": "Sudoku Dash module test vectors. Cells row-major, 0=empty. Boxes: 4x4=2x2, 6x6=2 rows x 3 cols, 9x9=3x3. Tiers: 1 naked single, 2 hidden single, 3 naked/hidden pair + pointing, 4 box-line, naked/hidden triple, X-Wing. first_step = step(givens), techniques tried in order: naked_single, hidden_single (boxes, then rows, then cols), naked_pair, hidden_pair, pointing, box_line_reduction, naked_triple, hidden_triple, x_wing.", "count": rows.size(), "vectors": rows}, "  "))
		f.close()
		print("wrote %d vectors to %s" % [rows.size(), out])
		quit(0)
		return
	var size := int(a.get("size", "9"))
	var tier := int(a.get("tier", "1"))
	var rng: PackedStringArray = a.get("seeds", "0-9").split("-")
	var lo := int(rng[0])
	var hi := int(rng[rng.size() - 1])
	for sd in range(lo, hi + 1): rows.append(_entry(size, tier, sd))
	out = a.get("out", "")
	var text := ""
	if a.get("format", "json") == "jsonl":
		for r in rows:
			var n: int = r.size
			var g2 = func(a):
				var o = []
				for k in n: o.append(a.slice(k * n, (k + 1) * n))
				return o
			text += JSON.stringify({"size": n, "tier": r.tier, "seed": r.seed, "givens": g2.call(r.givens), "solution": g2.call(r.solution)}) + "\n"
	else:
		text = JSON.stringify(rows, "  ")
	if out == "": print(text)
	else:
		var f := FileAccess.open(out, FileAccess.WRITE)
		f.store_string(text)
		f.close()
		print("wrote %d puzzles to %s" % [rows.size(), ProjectSettings.globalize_path(out)])
	quit(0)
