## QA hooks H1-H6 (debug builds only; excluded from the release export).
## Web: window.SD_DEBUG.{setAdMode(m), setClockOffsetMs(ms), setCoins(n), setTokens(n), resetSecondChanceCap(), startLevel(n 1-20), dump(),
##      show(screen), solve(), rect(nodeName) -> window.__sdRect (CSS px), layout() -> window.__sdLayout}
##      window.SD_QA (state), window.__adsLog (H2), window.__midgame (H3), window.__sdDump (H5).
##      URL ?ads=available|unavailable|error|timeout (H1), ?clock=<offset ms>.
## Keys: F6 cycle ad mode, F7 dump state, F8 +25h clock offset.
extends Node

var _cbs: Array = []

func _dbg(): return get_parent()

func _ready() -> void:
	print("[SD][debug] QA hooks enabled (debug build)")
	Ads.changed.connect(publish)
	Ads.logged.connect(_on_ad_logged)
	if not OS.has_feature("web"): return
	var q = str(JavaScriptBridge.eval("new URLSearchParams(location.search).get('ads') || ''"))
	if q != "": Ads.set_mode(norm_mode(q))
	var o = str(JavaScriptBridge.eval("new URLSearchParams(location.search).get('clock') || ''"))
	if o != "": _dbg().clock_offset_ms = int(o)
	JavaScriptBridge.eval("window.SD_DEBUG = {}; window.__adsLog = window.__adsLog || [];")
	var dbg = JavaScriptBridge.get_interface("window").SD_DEBUG
	var defs = {
		"setAdMode": func(a): Ads.set_mode(norm_mode(str(a[0]))),
		"setClockOffsetMs": func(a): _dbg().clock_offset_ms = int(a[0]),
		"setCoins": func(a): set_coins(int(a[0])),
		"setTokens": func(a): set_tokens(int(a[0])),
		"resetSecondChanceCap": func(_a): reset_sc_cap(),
		"startLevel": func(a): if _main(): _main().start_level(clampi(int(a[0]) - 1, 0, 19)),
		"dump": func(_a): pass,
		"show": func(a): show_screen(str(a[0])),
		"solve": func(_a): solve_current(),
		"rect": func(a): JavaScriptBridge.eval("window.__sdRect = %s" % JSON.stringify(node_rect(str(a[0])))),
		"layout": func(_a): JavaScriptBridge.eval("window.__sdLayout = %s" % JSON.stringify(layout_info())),
	}
	for k in defs:
		var f: Callable = defs[k]
		var cb = JavaScriptBridge.create_callback(func(args): f.call(args); publish())
		_cbs.append(cb)
		dbg[k] = cb

func _main(): return _dbg().main

## Mobile/layout QA: jump to a screen ("title", "harbour", "hint", "settings", "results").
func show_screen(n: String) -> void:
	var m = _main()
	if m == null: return
	match n:
		"title": m.show_title()
		"harbour": m.show_harbour()
		"hint": if m.screen_name == "grid": m._open_hint_panel()
		"settings": if m.has_method("show_settings"): m.show_settings()
		"results": solve_current()

## Fill every remaining cell with its solution (through the normal input path) -> results screen.
func solve_current() -> void:
	var m = _main()
	if m == null or m.board == null: return
	m.digit_lock = 0
	m.notes_mode = false
	if m.overlay: m._close_overlay()
	var b = m.board
	for i in b.cells.size():
		if m.board == null: return
		if b.cells[i] != b.solution[i] and not b.is_given(i):
			m._on_cell(i)
			m._on_digit(b.solution[i])

## Rect of the first node with this name, in CSS px of the page (null if absent).
func node_rect(n: String):
	var m = _main()
	if m == null: return null
	var nd = m.find_child(n, true, false)
	if nd == null or not (nd is Control) or not nd.is_visible_in_tree(): return null
	var r: Rect2 = nd.get_global_rect()
	var t: Transform2D = m.get_viewport().get_final_transform()
	var css = _css_per_px()
	var p = t * r.position
	var q = t * r.end
	return {"x": p.x / css, "y": p.y / css, "w": (q.x - p.x) / css, "h": (q.y - p.y) / css}

func _css_per_px() -> float:
	if not OS.has_feature("web"): return 1.0
	return float(JavaScriptBridge.eval("(function(){var c=document.querySelector('canvas');return c&&c.clientWidth?c.width/c.clientWidth:window.devicePixelRatio||1;})()"))

func layout_info() -> Dictionary:
	var m = _main()
	var vp = m.get_viewport_rect().size if m else Vector2.ZERO
	var d = {"viewport": [vp.x, vp.y], "window": [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y],
		"scale": m.get_viewport().get_final_transform().get_scale().x if m else 0.0, "cssPerPx": _css_per_px()}
	if m and m.has_method("layout_info"): d.merge(m.layout_info())
	return d

## Accepts "available|unavailable|error|timeout" (QA_TEST_PLAN H1) or full names.
static func norm_mode(q: String) -> String:
	q = q.strip_edges().to_lower()
	return q if q.begins_with("mock_") or q == "sdk" or q == "none" else "mock_" + q

func set_coins(n: int) -> void:
	if _main(): _main().profile.coins = n; _after()

func set_tokens(n: int) -> void:
	if _main(): _main().profile.tokens = clampi(n, 0, 10); _after()

func reset_sc_cap() -> void:
	if _main():
		_main().profile.sc_times = []
		_main().profile.sc_lock_until = 0
		_after()

func _after() -> void:
	var m = _main()
	m.save()
	if m.screen_name == "harbour": m.show_harbour()

func _on_ad_logged(e: Dictionary) -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("(window.__adsLog = window.__adsLog || []).push(%s)" % JSON.stringify(e))

func state() -> Dictionary:
	var d = {"adMode": Ads.mode, "adsAvailable": Ads.available(), "context": Ads.context,
		"adLog": Ads.call_log, "clockOffsetMs": _dbg().clock_offset_ms}
	var m = _main()
	if m:
		d["genLog"] = m.source.log
		d["profile"] = m.profile.to_dict()
		d["grid"] = m.board.to_dict() if m.board else null
		d["screen"] = m.screen_name
		d["midgame"] = {"counter": m.policy.counter, "sessionAgeMs": Time.get_ticks_msec() - m.policy.session_start_ms}
		d["stepDump"] = m.step_dump()
	return d

func publish() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.SD_QA = %s; window.__midgame = window.SD_QA.midgame; window.__sdDump = window.SD_QA.stepDump;" % JSON.stringify(state()))

func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventKey) or not e.pressed: return
	match e.keycode:
		KEY_F6:
			var ms = Ads.modes()
			Ads.set_mode(ms[(ms.find(Ads.mode) + 1) % ms.size()])
			print("[SD][debug] ad mode = ", Ads.mode)
		KEY_F7:
			print("[SD][debug] state = ", JSON.stringify(state()))
		KEY_F8:
			_dbg().clock_offset_ms += 25 * 3600 * 1000
			print("[SD][debug] clock offset ms = ", _dbg().clock_offset_ms)
		_:
			return
	publish()
