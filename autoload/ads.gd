## Ads adapter over CrazyGames SDK v3 (via web/cg_glue.js) with an offline mock. Autoload "Ads".
## Every request is recorded in call_log (QA hook G6 / AC10).
extends Node

signal changed

const TIMEOUT_S = 8.0
var timeout_s: float = TIMEOUT_S   # tests may shorten
const MODES = ["mock_available", "mock_unavailable", "mock_error", "mock_timeout", "sdk"]

var mode: String = "mock_available"
var context: String = "menu"   # menu | grid | grid_panel | results
var call_log: Array = []
var busy: bool = false

func _ready() -> void:
	if OS.has_feature("web") and _js_bool("window.SD_CG && window.SD_CG.portal()"):
		mode = "sdk"

func grid_open() -> bool:
	return context == "grid" or context == "grid_panel"

func set_context(c: String) -> void:
	context = c
	if mode == "sdk":
		JavaScriptBridge.eval("window.SD_CG.gameplay(%s)" % ("true" if c == "grid" else "false"))

func set_mode(m: String) -> void:
	if m in MODES:
		mode = m
		_log("mode", m, "set")
		changed.emit()

func available() -> bool:
	match mode:
		"mock_unavailable": return false
		"sdk": return _js_bool("window.SD_CG && window.SD_CG.available()")
	return true

func _js_bool(expr: String) -> bool:
	if not OS.has_feature("web"): return false
	return str(JavaScriptBridge.eval("(%s) ? 'y' : 'n'" % expr)) == "y"

func _log(kind: String, origin: String, result: String) -> void:
	var e = {"t_ms": Time.get_ticks_msec(), "kind": kind, "origin": origin, "context": context,
		"grid_open": grid_open(), "mode": mode, "result": result}
	e["ts"] = int(Time.get_unix_time_from_system() * 1000.0)
	call_log.append(e)
	print("[SD][ads] ", JSON.stringify(e))
	if OS.is_debug_build() and OS.has_feature("web"):   # H2
		JavaScriptBridge.eval("(window.__adsLog = window.__adsLog || []).push(%s)" % JSON.stringify(e))
	changed.emit()

## Player-requested rewarded ad. Allowed only from pause panels (grid_panel) or results.
func rewarded(origin: String) -> bool:
	if not (context == "grid_panel" or context == "results"):
		_log("rewarded", origin, "blocked_context")
		return false
	return await _request("rewarded", origin)

## Midgame (interstitial). Never while a grid is open.
func midgame(origin: String) -> bool:
	if grid_open():
		_log("midgame", origin, "blocked_grid_open")
		return false
	return await _request("midgame", origin)

func _request(kind: String, origin: String) -> bool:
	if busy or not available():
		_log(kind, origin, "unavailable")
		return false
	busy = true
	_log(kind, origin, "requested")
	var ok = false
	var timed_out = false
	var t0 = Time.get_ticks_msec()
	match mode:
		"mock_available":
			await get_tree().create_timer(0.6).timeout
			ok = true
		"mock_error":
			await get_tree().process_frame
			ok = false
		"mock_timeout":
			await get_tree().create_timer(timeout_s).timeout
			ok = false
			timed_out = true
		"sdk":
			var id = int(JavaScriptBridge.eval("window.SD_CG.request('%s')" % kind))
			var st = "pending"
			while st == "pending" and Time.get_ticks_msec() - t0 < timeout_s * 1000:
				await get_tree().create_timer(0.1).timeout
				st = str(JavaScriptBridge.eval("window.SD_CG.status(%d)" % id))
			ok = st == "finished"
			timed_out = st == "pending"
	var res = "finished" if ok else ("timeout" if timed_out else "error")
	_log(kind, origin, res)
	busy = false
	return ok
