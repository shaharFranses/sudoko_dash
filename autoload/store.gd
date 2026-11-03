## Save storage: CrazyGames data module on the portal, else localStorage (web) or user://save.json (desktop).
extends Node

const KEY = "sudoku_dash_save_v1"

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

## Save slots. NEVER rename KEY: every player's progress lives under it, across all deployed versions.
## slot + ".bak" holds the last save that loaded cleanly (written once per boot), used if the main slot is
## ever unreadable. A save from an older format is also copied to KEY + ".pre_v<N>" before migrating.
var slot: String = KEY         # the key actually used: KEY, or KEY + "_staging" on the staging site
var load_source: String = ""   # "main" | "backup" | "" (fresh): QA / debug

## Staging (…/staging/ on the same github.io domain as the live build) gets its own save slot, so
## playtesting never touches a real player's progress.
func _ready() -> void:
	if OS.has_feature("web"):
		var path = str(JavaScriptBridge.eval("location.pathname || ''"))
		if path.find("/staging") >= 0: slot = KEY + "_staging"
	print("[SD] save slot ", slot)

## Web: synchronous localStorage write (stamped; SD_CG picks the newer of localStorage / CrazyGames data on load),
## so a save from a page-leave handler has landed before unload. Desktop: user://save.json, written to a temp
## file then renamed over the old one, so a crash mid-write never leaves a half-written save.
func save(d: Dictionary) -> void:
	_write(slot, JSON.stringify(d))

## Main slot first; if it is missing or unreadable, the backup. The unreadable text is kept under
## slot + ".corrupt" (not overwritten silently) so it can be recovered by hand.
func load_data() -> Dictionary:
	var text = _read(slot)
	var d = _parse(text)
	if not d.is_empty():
		load_source = "main"
		return d
	if text != "":
		push_warning("[SD] save unreadable, trying backup")
		_write(slot + ".corrupt", text)
	d = _parse(_read(slot + ".bak"))
	load_source = "backup" if not d.is_empty() else ""
	return d

## Last known good copy (called after a successful load + migration).
func backup(d: Dictionary) -> void:
	_write(slot + ".bak", JSON.stringify(d))

## Untouched copy of an old-format save, before the migration rewrites it.
func keep_copy(suffix: String, d: Dictionary) -> void:
	var k = slot + "." + suffix
	if _read(k) == "": _write(k, JSON.stringify(d))

func clear() -> void:
	load_source = ""
	if OS.has_feature("web"):
		JavaScriptBridge.eval("try{var s=%s;for(var i=localStorage.length-1;i>=0;i--){var k=localStorage.key(i);if(k===s||(k&&k.indexOf(s+'.')===0))localStorage.removeItem(k)}}catch(e){}" % JSON.stringify(slot))
	else:
		var dir = DirAccess.open("user://")
		if dir:
			for f in dir.get_files():
				if f.begins_with("save") and f.ends_with(".json"): dir.remove(f)

static func _parse(text: String) -> Dictionary:
	if text == "": return {}
	var d = JSON.parse_string(text)
	return d if d is Dictionary else {}

static func _file(k: String) -> String:
	return "user://save.json" if k == KEY else "user://save%s.json" % k.substr(KEY.length())

func _write(k: String, text: String) -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.SD_CG ? window.SD_CG.save(%s, %s) : localStorage.setItem(%s, %s)" % [JSON.stringify(k), JSON.stringify(text), JSON.stringify(k), JSON.stringify(text)])
		return
	var path = _file(k)
	var tmp = path + ".tmp"
	var f = FileAccess.open(tmp, FileAccess.WRITE)
	if f == null: return
	f.store_string(text)
	f.close()
	DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(path))

func _read(k: String) -> String:
	if OS.has_feature("web"):
		var v = JavaScriptBridge.eval("(window.SD_CG ? window.SD_CG.load(%s) : localStorage.getItem(%s)) || ''" % [JSON.stringify(k), JSON.stringify(k)])
		return str(v) if v != null else ""
	var path = _file(k)
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
