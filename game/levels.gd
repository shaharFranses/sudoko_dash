## Loads the Harbour level path (data/levels/harbour.json, built by tools/build_levels.gd).
extends RefCounted

const PATH = "res://data/levels/harbour.json"
static var _data = null

static func data() -> Dictionary:
	if _data == null:
		_data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return _data

static func count() -> int:
	return data().levels.size()

static func level(i: int) -> Dictionary:
	return data().levels[i]

static func grid(grid_id: String) -> Dictionary:
	return data().grids[grid_id]

## Target cell indices from the stored [[r,c],...].
static func target_cells(lvl: Dictionary) -> Array:
	var n = int(lvl.size)
	var out = []
	for rc in lvl.target: out.append(int(rc[0]) * n + int(rc[1]))
	return out
