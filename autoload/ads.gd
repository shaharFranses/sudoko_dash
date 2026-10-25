## Ads adapter over CrazyGames SDK v3 (glue in web/head_include.html). Autoload "Ads".
## Release: "sdk" on CrazyGames hosts, otherwise "none" (rewarded reports unavailable, never grants).
## Debug builds additionally load res://debug/ads_mock.gd (excluded from the release export).
extends Node

signal changed
signal logged(entry: Dictionary)
signal ad_started
signal ad_finished

const TIMEOUT_S = 8.0
const MOCK_PATH = "res://debug/ads_mock.gd"
var timeout_s: float = TIMEOUT_S   # tests may shorten

var mode: String = "none"       # none | sdk | (debug only) mock modes
var context: String = "menu"    # menu | grid | grid_panel | results
var call_log: Array = []
var busy: bool = false
var mock = null
## Boot hold (PKD studio intro): while held, no SDK call reaches the page (gameplayStart/Stop, requestAd,
## loadingStop via Store) and no ad can run. main.gd holds it from boot until the intro's `finished`.
var held: bool = false
## Every SDK call that would reach the page, in order (tests + QA): {t_ms, call}. Recorded off-web too.
var sdk_log: Array = []

func _ready() -> void:
	if OS.has_feature("web") and _js_bool("window.SD_CG && window.SD_CG.portal()"):
		mode = "sdk"
	elif OS.is_debug_build() and ResourceLoader.exists(MOCK_PATH):
		mock = load(MOCK_PATH).new()
		mode = mock.DEFAULT_MODE

func grid_open() -> bool:
	return context == "grid" or context == "grid_panel"

func set_context(c: String) -> void:
	context = c
	if not held: _push_gameplay()

func _push_gameplay() -> void:
	if mode == "sdk":
		var on = context == "grid"
		sdk(("gameplayStart" if on else "gameplayStop"), "window.SD_CG.gameplay(%s)" % ("true" if on else "false"))

## Hold / release SDK traffic and ads (boot intro). Releasing re-announces the current gameplay state once.
func hold(on: bool) -> void:
	if held == on: return
	held = on
	if not on: _push_gameplay()

## The single gate for page SDK calls. Never reaches the page while held.
func sdk(what: String, js: String):
	if held: return null
	sdk_log.append({"t_ms": Time.get_ticks_msec(), "call": what})
	if OS.has_feature("web"): return JavaScriptBridge.eval(js)
	return null

func modes() -> Array:
	return (["none", "sdk"] + (mock.MODES if mock else []))

func set_mode(m: String) -> void:
	if m in modes():
		mode = m
		_log("mode", m, "set")
		changed.emit()

func available() -> bool:
	if held: return false
	if mode == "sdk": return _js_bool("window.SD_CG && window.SD_CG.available()")
	if mock and mock.handles(mode): return mock.available(mode)
	return false

func _js_bool(expr: String) -> bool:
	if not OS.has_feature("web"): return false
	return str(JavaScriptBridge.eval("(%s) ? 'y' : 'n'" % expr)) == "y"

func _log(kind: String, origin: String, result: String) -> void:
	var e = {"t_ms": Time.get_ticks_msec(), "ts": int(Time.get_unix_time_from_system() * 1000.0),
		"kind": kind, "origin": origin, "context": context, "grid_open": grid_open(), "mode": mode, "result": result}
	call_log.append(e)
	print("[SD][ads] ", JSON.stringify(e))
	logged.emit(e)
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
	if held:
		_log(kind, origin, "blocked_intro")
		return false
	if busy or not available():
		_log(kind, origin, "unavailable")
		return false
	busy = true
	ad_started.emit()   # audio muted for the whole ad (CrazyGames requirement)
	_log(kind, origin, "requested")
	var ok = false
	var timed_out = false
	var t0 = Time.get_ticks_msec()
	if mode == "sdk":
		var id = int(sdk("requestAd(%s)" % kind, "window.SD_CG.request('%s')" % kind))
		var st = "pending"
		while st == "pending" and Time.get_ticks_msec() - t0 < timeout_s * 1000:
			await get_tree().create_timer(0.1).timeout
			st = str(JavaScriptBridge.eval("window.SD_CG.status(%d)" % id))
		ok = st == "finished"
		timed_out = st == "pending"
	elif mock:
		var r: String = await mock.request(self, mode)
		ok = r == "finished"
		timed_out = r == "timeout"
	var res = "finished" if ok else ("timeout" if timed_out else "error")
	_log(kind, origin, res)
	busy = false
	ad_finished.emit()
	return ok
