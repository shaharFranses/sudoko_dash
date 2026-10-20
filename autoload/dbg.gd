## QA debug hooks (G6). Active only in debug builds (OS.is_debug_build()); inert in release exports.
## Web: window.SD_DEBUG.{setAdMode(m), setClockOffsetMs(ms), dump()} ; state mirrored to window.SD_QA
##   (adLog, genLog, grid, profile). URL ?ads=<mode> sets the ad mock at boot.
## Desktop/web keys: F6 cycle ad mode, F7 dump grid state to console, F8 +25h clock offset.
extends Node

var enabled: bool = false
var clock_offset_ms: int = 0
var main = null   # set by main.gd
var _cbs: Array = []

func _ready() -> void:
	enabled = OS.is_debug_build()
	if not enabled: return
	print("[SD][debug] QA hooks enabled (debug build)")
	if OS.has_feature("web"):
		var q = str(JavaScriptBridge.eval("new URLSearchParams(location.search).get('ads') || ''"))
		if q != "": Ads.set_mode(q if q.begins_with("mock_") or q == "sdk" else "mock_" + q)
		var o = str(JavaScriptBridge.eval("new URLSearchParams(location.search).get('clock') || ''"))
		if o != "": clock_offset_ms = int(o)
		var win = JavaScriptBridge.get_interface("window")
		JavaScriptBridge.eval("window.SD_DEBUG = {}")
		var dbg = JavaScriptBridge.get_interface("window").SD_DEBUG
		var c1 = JavaScriptBridge.create_callback(func(args): Ads.set_mode(str(args[0])); publish())
		var c2 = JavaScriptBridge.create_callback(func(args): clock_offset_ms = int(args[0]); publish())
		var c3 = JavaScriptBridge.create_callback(func(_args): publish())
		_cbs = [c1, c2, c3]
		dbg.setAdMode = c1
		dbg.setClockOffsetMs = c2
		dbg.dump = c3
	Ads.changed.connect(publish)

func now_ms() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0) + (clock_offset_ms if enabled else 0)

func state() -> Dictionary:
	var d = {"adMode": Ads.mode, "adsAvailable": Ads.available(), "context": Ads.context,
		"adLog": Ads.call_log, "clockOffsetMs": clock_offset_ms}
	if main:
		d["genLog"] = main.source.log
		d["profile"] = main.profile.to_dict()
		d["grid"] = main.board.to_dict() if main.board else null
		d["screen"] = main.screen_name
		d["midgame"] = {"counter": main.policy.counter, "sessionAgeMs": Time.get_ticks_msec() - main.policy.session_start_ms}  # H3
		d["stepDump"] = main.step_dump()  # H5
	return d

func publish() -> void:
	if not enabled: return
	if OS.has_feature("web"):
		var st = state()
		JavaScriptBridge.eval("window.SD_QA = %s; window.__midgame = window.SD_QA.midgame; window.__sdDump = window.SD_QA.stepDump;" % JSON.stringify(st))

func _unhandled_input(e: InputEvent) -> void:
	if not enabled or not (e is InputEventKey) or not e.pressed: return
	match e.keycode:
		KEY_F6:
			Ads.set_mode(Ads.MODES[(Ads.MODES.find(Ads.mode) + 1) % Ads.MODES.size()])
			print("[SD][debug] ad mode = ", Ads.mode)
		KEY_F7:
			print("[SD][debug] state = ", JSON.stringify(state()))
		KEY_F8:
			clock_offset_ms += 25 * 3600 * 1000
			print("[SD][debug] clock offset ms = ", clock_offset_ms)
	publish()
