## Save storage. Web: localStorage (synchronous) plus the CrazyGames data module on the portal ("cloud").
## Desktop: user://. Each copy is ONE atomic record, the v2 envelope {v, seq, saved_at, profile}
## (game/save_merge.gd). Load picks the best VALID copy (seq first, clock only as tiebreak); a fresh / default
## profile is never written over stored progress, and nothing is written over unreadable copies until the
## player makes real progress. Legacy v1 saves (bare profile + '.t' stamp) still load and are left in place.
extends Node

const SaveMerge = preload("res://game/save_merge.gd")
const KEY = "sudoku_dash_save_v2"
const LEGACY_KEY = "sudoku_dash_save_v1"
const FILE = "user://save_v2.json"
const LEGACY_FILE = "user://save.json"

## Storage backend: get(source, key) -> String or null, put(source, key, text), remove(source, key), has_cloud().
## Tests swap in a MemoryBackend (two sources) to exercise merges headless.
var backend = null
var _seq: int = 0
var _hold_fresh: bool = false   # stored copies exist but none is valid: don't overwrite them with a fresh profile
var last_load: Dictionary = {}  # {source, seq, legacy, copies} for tests / QA
var writes: int = 0             # successful save() writes (tests)
var refused: Array = []         # reasons a save() was skipped (tests / QA)

func _ready() -> void:
	if backend == null: backend = WebBackend.new() if OS.has_feature("web") else FileBackend.new()

func _be():
	if backend == null: _ready()
	return backend

## Waits (max 5 s) until the CrazyGames SDK init has resolved or failed; immediate off-portal.
func wait_ready() -> void:
	if not OS.has_feature("web"): return
	var t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 5000:
		if str(JavaScriptBridge.eval("(!window.SD_CG || window.SD_CG.ready()) ? 'y' : 'n'")) == "y": return
		await get_tree().create_timer(0.05).timeout

## CrazyGames loadingStop, through the Ads SDK gate (logged in Ads.sdk_log; never while the boot intro holds it).
func loading_stop() -> void:
	Ads.sdk("loadingStop", "window.SD_CG && window.SD_CG.loadingStop()")

func _sources() -> Array:
	return ["cloud", "local"] if _be().has_cloud() else ["local"]

func _copies() -> Array:
	var out = []
	for s in _sources():
		var b = _be()
		out.append(SaveMerge.parse_copy(s, b.get_text(s, KEY), b.get_text(s, LEGACY_KEY), b.get_text(s, LEGACY_KEY + ".t")))
	return out

## The profile to play with ({} = fresh). Also primes the save counter above every stored copy.
func load_data() -> Dictionary:
	var copies = _copies()
	var best = SaveMerge.choose(copies)
	_seq = maxi(_seq, SaveMerge.max_seq(copies))
	var anything_stored = false
	for c in copies:
		if c.parsed or c.valid: anything_stored = true
	for s in _sources():
		if _be().get_text(s, KEY) != null or _be().get_text(s, LEGACY_KEY) != null: anything_stored = true
	_hold_fresh = best.is_empty() and anything_stored
	last_load = {"source": best.get("source", ""), "seq": best.get("seq", -2), "legacy": best.get("legacy", false),
		"hold_fresh": _hold_fresh, "copies": copies.map(func(c): return {"source": c.source, "parsed": c.parsed, "valid": c.valid, "seq": c.seq})}
	if best.is_empty() and anything_stored:
		print("[SD][save] no valid stored save (kept untouched until real progress)")
	return best.get("profile", {}).duplicate(true)

## Synchronous write of one envelope to every source (web: localStorage.setItem; portal: also CG data).
## Guards: invalid profile -> refused; a no-progress profile is never written over a valid stored save with
## progress, nor over unreadable copies (_hold_fresh) — the first real progress lifts the hold.
func save(d: Dictionary) -> void:
	if not SaveMerge.valid_profile(d):
		refused.append("invalid"); print("[SD][save] refused: profile failed validation"); return
	if not SaveMerge.has_progress(d):
		if _hold_fresh:
			refused.append("hold_fresh"); return
		var best = SaveMerge.choose(_copies())
		if not best.is_empty() and SaveMerge.has_progress(best.profile):
			refused.append("would_wipe"); print("[SD][save] refused: fresh profile over stored progress"); return
	_hold_fresh = false
	_seq += 1
	var text = SaveMerge.envelope(_seq, int(Time.get_unix_time_from_system() * 1000.0), d)
	for s in _sources(): _be().put(s, KEY, text)
	writes += 1

func clear() -> void:
	for s in ["cloud", "local"]:
		for k in [KEY, LEGACY_KEY, LEGACY_KEY + ".t"]: _be().remove(s, k)
	_seq = 0
	_hold_fresh = false
	last_load = {}
	refused.clear()

# ---------------- backends ----------------
class WebBackend:
	func has_cloud() -> bool:
		return str(JavaScriptBridge.eval("(window.SD_CG && window.SD_CG.hasCloud()) ? 'y' : 'n'")) == "y"
	func get_text(source: String, key: String):
		var v = JavaScriptBridge.eval("window.SD_CG ? window.SD_CG.get(%s, %s) : localStorage.getItem(%s)" % [JSON.stringify(source), JSON.stringify(key), JSON.stringify(key)])
		return null if v == null else str(v)
	func put(source: String, key: String, text: String) -> void:
		JavaScriptBridge.eval("window.SD_CG ? window.SD_CG.set(%s, %s, %s) : localStorage.setItem(%s, %s)" % [JSON.stringify(source), JSON.stringify(key), JSON.stringify(text), JSON.stringify(key), JSON.stringify(text)])
	func remove(source: String, key: String) -> void:
		JavaScriptBridge.eval("window.SD_CG ? window.SD_CG.del(%s, %s) : localStorage.removeItem(%s)" % [JSON.stringify(source), JSON.stringify(key), JSON.stringify(key)])

## Desktop: one local copy per key in user:// (legacy v1 save at user://save.json).
class FileBackend:
	func has_cloud() -> bool: return false
	func _path(key: String) -> String:
		if key == "sudoku_dash_save_v2": return "user://save_v2.json"
		if key == "sudoku_dash_save_v1": return "user://save.json"
		return "user://" + key.replace("/", "_") + ".txt"
	func get_text(source: String, key: String):
		if source != "local" or not FileAccess.file_exists(_path(key)): return null
		return FileAccess.get_file_as_string(_path(key))
	func put(source: String, key: String, text: String) -> void:
		if source != "local": return
		var tmp = _path(key) + ".tmp"
		var f = FileAccess.open(tmp, FileAccess.WRITE)
		if f == null: return
		f.store_string(text); f.close()
		DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(_path(key)))   # atomic replace
	func remove(source: String, key: String) -> void:
		if source == "local" and FileAccess.file_exists(_path(key)):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(_path(key)))

## In-memory two-source backend (tests; also a template for the portal mock).
class MemoryBackend:
	var data = {"local": {}, "cloud": {}}
	var cloud = true
	func has_cloud() -> bool: return cloud
	func get_text(source: String, key: String): return data[source].get(key)
	func put(source: String, key: String, text: String) -> void: data[source][key] = text
	func remove(source: String, key: String) -> void: data[source].erase(key)
