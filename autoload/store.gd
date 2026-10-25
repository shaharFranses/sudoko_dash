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

func save(d: Dictionary) -> void:
	var text = JSON.stringify(d)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.SD_CG ? window.SD_CG.save(%s, %s) : localStorage.setItem(%s, %s)" % [JSON.stringify(KEY), JSON.stringify(text), JSON.stringify(KEY), JSON.stringify(text)])
	else:
		var f = FileAccess.open("user://save.json", FileAccess.WRITE)
		if f:
			f.store_string(text)
			f.close()

func load_data() -> Dictionary:
	var text = ""
	if OS.has_feature("web"):
		var v = JavaScriptBridge.eval("(window.SD_CG ? window.SD_CG.load(%s) : localStorage.getItem(%s)) || ''" % [JSON.stringify(KEY), JSON.stringify(KEY)])
		text = str(v) if v != null else ""
	elif FileAccess.file_exists("user://save.json"):
		text = FileAccess.get_file_as_string("user://save.json")
	if text == "": return {}
	var d = JSON.parse_string(text)
	return d if d is Dictionary else {}

func clear() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("try{localStorage.removeItem(%s)}catch(e){}" % JSON.stringify(KEY))
	elif FileAccess.file_exists("user://save.json"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.json"))
