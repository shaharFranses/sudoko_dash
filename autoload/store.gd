## Save storage: CrazyGames data module on the portal, else localStorage (web) or user://save.json (desktop).
extends Node

const KEY = "sudoku_dash_save_v1"

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
