## QA: time the RUNTIME path (game/puzzle_source.gd get_puzzle) for 4x4/6x6, 100 calls each, fresh source per size.
extends SceneTree
func _init() -> void:
	var PS = load("res://game/puzzle_source.gd")
	for st in [[4, 1], [6, 1], [6, 2]]:
		var src = PS.new()
		var times := []; var srcs := {}
		for sd in 100:
			var t0 := Time.get_ticks_usec()
			var p = src.get_puzzle(st[0], st[1], 5000 + sd)
			times.append((Time.get_ticks_usec() - t0) / 1000.0)
			var s = "pack" if str(p.get("id", "")).find("gen_") < 0 else "generated"
			srcs[s] = srcs.get(s, 0) + 1
		times.sort()
		print("RUNTIME size=%d tier=%d n=100 median=%.2f p95=%.2f max=%.2f ms sources=%s fallback_now=%s" % [st[0], st[1], times[50], times[95], times[-1], srcs, src.use_fallback])
	quit(0)
