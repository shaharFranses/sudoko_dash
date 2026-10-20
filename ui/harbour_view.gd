## Simple procedural Harbour scene; each bought task (and its decor choice) changes the drawing.
extends Control

var profile = null

func _draw() -> void:
	var w = size.x
	var h = size.y
	draw_rect(Rect2(0, 0, w, h * 0.55), Color("bfe3ef"))           # sky
	draw_rect(Rect2(0, h * 0.55, w, h * 0.45), Color("3d8fb5"))     # sea
	draw_rect(Rect2(0, h * 0.45, w * 0.55, h * 0.12), Color("e8d7a8"))  # quay
	var t: Dictionary = profile.tasks if profile else {}
	var dc: Dictionary = profile.decor if profile else {}
	# Dock
	var dock_c = [Color("a0703c"), Color("4f7fbf"), Color("8a6a4a")]
	if t.has("dock"):
		draw_rect(Rect2(w * 0.35, h * 0.55, w * 0.3, h * 0.05), dock_c[dc.get("dock", 0)])
		for k in 4: draw_rect(Rect2(w * (0.36 + k * 0.09), h * 0.6, w * 0.012, h * 0.1), Color("5a3d22"))
	else:
		draw_rect(Rect2(w * 0.35, h * 0.56, w * 0.12, h * 0.03), Color("6b5a4a"))  # broken
	# Boats
	var boat_c = [Color("d94141"), Color("2f9e7a"), Color("f2c230")]
	for k in 2:
		var x = w * (0.62 + k * 0.16)
		var c = boat_c[dc.get("boats", 0)] if t.has("boats") else Color("7a7a7a")
		draw_colored_polygon(PackedVector2Array([Vector2(x, h * 0.72), Vector2(x + w * 0.12, h * 0.72), Vector2(x + w * 0.1, h * 0.79), Vector2(x + w * 0.02, h * 0.79)]), c)
	# Flowerbeds
	if t.has("flowers"):
		var fc = [Color("e5484d"), Color("9b7be0")][dc.get("flowers", 0)]
		for k in 10: draw_circle(Vector2(w * (0.03 + k * 0.05), h * 0.47), h * 0.015, fc)
	# Lighthouse
	var lx = w * 0.88
	var stripe = [Color("d23c3c"), Color("2a6fdb"), Color("ffffff")][dc.get("lighthouse", 0)] if t.has("lighthouse") else Color("9a9a9a")
	draw_rect(Rect2(lx, h * 0.18, w * 0.05, h * 0.37), Color("f4f4f4") if t.has("lighthouse") else Color("b0b0b0"))
	for k in 3: draw_rect(Rect2(lx, h * (0.22 + k * 0.11), w * 0.05, h * 0.04), stripe)
	if t.has("lighthouse"): draw_circle(Vector2(lx + w * 0.025, h * 0.16), h * 0.03, Color("ffe066"))
	# Café
	draw_rect(Rect2(w * 0.05, h * 0.25, w * 0.22, h * 0.2), Color("f1e3c6") if t.has("cafe") else Color("bdb4a5"))
	if t.has("cafe"):
		if dc.get("cafe", 0) == 0:
			for k in 6: draw_rect(Rect2(w * (0.05 + k * 0.0367), h * 0.25, w * 0.0367, h * 0.05), Color("d23c3c") if k % 2 == 0 else Color("ffffff"))
		else:
			for k in 3: draw_circle(Vector2(w * (0.08 + k * 0.08), h * 0.42), h * 0.035, Color("f2a541"))
