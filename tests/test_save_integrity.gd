extends GutTest
## Save integrity (QA run 13 finding 3c): validated local/cloud choice, no-wipe write guard, atomic v2 envelope
## with a monotonic seq (clock only as tiebreak), legacy v1 migration. Uses Store's in-memory two-source backend.

const SaveMerge = preload("res://game/save_merge.gd")
const Profile = preload("res://game/profile.gd")
var mem
var saved_backend

func before_each():
	saved_backend = Store.backend
	mem = Store.MemoryBackend.new()
	Store.backend = mem
	Store.clear()
	Store.writes = 0

func after_each():
	Store.clear()
	Store.backend = saved_backend
	Store.clear()

func _progress(coins := 777) -> Dictionary:
	var p = Profile.new()
	p.coins = coins; p.tokens = 7; p.stars = 2; p.stars_earned = 5; p.path_next = 3
	p.path_stars = [3, 2, 1]; p.level_best = [3, 2, 1]; p.tasks = {"dock": true}; p.decor = {"dock": 0}
	return p.to_dict()

func _env(seq: int, at: int, prof) -> String:
	return JSON.stringify({"v": 2, "seq": seq, "saved_at": at, "profile": prof})

func _stored(src: String):
	var t = mem.data[src].get(Store.KEY)
	return null if t == null else JSON.parse_string(t)

func test_corrupt_newer_cloud_falls_back_to_local():
	mem.data.local[Store.KEY] = _env(5, 1000, _progress(555))
	mem.data.cloud[Store.KEY] = '{"v":2,"seq":9,"saved_at":99999,"profile":{"coins":'   # truncated JSON, newer
	var d = Store.load_data()
	assert_eq(int(d.coins), 555, "local progress loaded, not an empty profile")
	assert_eq(Store.last_load.source, "local")
	# the next save outranks the corrupt copy (seq 10) and repairs both copies with the real progress
	var p = Profile.new(); p.from_dict(d); p.coins += 10
	Store.save(p.to_dict())
	assert_gt(int(_stored("local").seq), 5, "outranks the local copy (the corrupt cloud seq is unreadable)")
	assert_eq(int(_stored("cloud").seq), int(_stored("local").seq), "both copies get the same record")
	assert_eq(int(_stored("cloud").profile.coins), 565, "cloud repaired with real progress")
	assert_eq(int(Store.load_data().coins), 565)

func test_unparseable_newer_cloud_garbage_text():
	mem.data.local[Store.KEY] = _env(2, 1000, _progress(321))
	mem.data.cloud[Store.KEY] = "\u0000not json at all"
	assert_eq(int(Store.load_data().coins), 321)

func test_valid_json_but_empty_or_garbage_typed_profile_rejected():
	for bad in [{}, {"coins": "lots", "tokens": 3, "path_next": 0}, {"coins": 100, "tokens": 3, "path_next": -4},
			{"coins": 100, "tokens": 3, "path_next": 2, "tasks": ["dock"]}, {"coins": 100, "tokens": 3, "path_next": 2, "level_best": [9]},
			{"coins": 1.5, "tokens": 3, "path_next": 0}, {"coins": 100, "tokens": 3, "path_next": 0, "current_grid": {"meta": 3}},
			{"coins": 100, "tokens": 3, "path_next": 0, "sound_on": "no"}, [], "x", null]:
		assert_false(SaveMerge.valid_profile(bad), "rejected: %s" % str(bad))
	assert_true(SaveMerge.valid_profile(_progress()))
	assert_true(SaveMerge.valid_profile(Profile.new().to_dict()), "a real default profile is valid")
	mem.data.local[Store.KEY] = _env(1, 10, _progress(444))
	mem.data.cloud[Store.KEY] = _env(50, 99999, {})                         # valid envelope, empty profile
	assert_eq(int(Store.load_data().coins), 444)
	mem.data.cloud[Store.KEY] = _env(50, 99999, {"coins": "9", "tokens": 3, "path_next": 0})
	assert_eq(int(Store.load_data().coins), 444, "garbage-typed newer copy rejected")
	mem.data.cloud[Store.KEY] = '{"v":2,"seq":"51","profile":{}}'            # seq of the wrong type
	assert_eq(int(Store.load_data().coins), 444)

func test_both_corrupt_fresh_profile_no_overwrite_until_progress():
	mem.data.local[Store.KEY] = "{broken"
	mem.data.cloud[Store.KEY] = _env(3, 5, {"coins": []})
	var d = Store.load_data()
	assert_eq(d, {}, "fresh profile")
	assert_true(Store.last_load.hold_fresh)
	Store.save(Profile.new().to_dict())     # e.g. an early save with nothing done yet
	assert_eq(mem.data.local[Store.KEY], "{broken", "local copy untouched")
	assert_eq(mem.data.cloud[Store.KEY], _env(3, 5, {"coins": []}), "cloud copy untouched")
	assert_eq(Store.writes, 0)
	assert_has(Store.refused, "hold_fresh")
	var p = Profile.new(); p.coins = 120   # real progress (a reward)
	Store.save(p.to_dict())
	assert_eq(Store.writes, 1)
	assert_eq(int(_stored("local").profile.coins), 120)
	assert_gt(int(_stored("cloud").seq), 3, "new record outranks the old unreadable one")

func test_valid_save_never_replaced_by_empty_or_default():
	Store.save(_progress(900))
	assert_eq(Store.writes, 1)
	var before_l = mem.data.local[Store.KEY]
	var before_c = mem.data.cloud[Store.KEY]
	Store.save(Profile.new().to_dict())   # default / fresh profile
	Store.save({})                         # empty
	Store.save({"coins": "x"})             # garbage
	assert_eq(mem.data.local[Store.KEY], before_l, "local kept")
	assert_eq(mem.data.cloud[Store.KEY], before_c, "cloud kept")
	assert_eq(Store.writes, 1)
	assert_has(Store.refused, "would_wipe"); assert_has(Store.refused, "invalid")
	assert_eq(int(Store.load_data().coins), 900)

func test_skewed_clock_higher_seq_with_older_saved_at_wins():
	mem.data.cloud[Store.KEY] = _env(8, 1000, _progress(800))           # later save, from a slow clock
	mem.data.local[Store.KEY] = _env(7, 9999999999999, _progress(700))  # earlier save, clock far in the future
	assert_eq(int(Store.load_data().coins), 800, "seq wins over the timestamp")
	mem.data.cloud[Store.KEY] = _env(7, 1000, _progress(801))
	assert_eq(int(Store.load_data().coins), 700, "same seq: saved_at breaks the tie")
	mem.data.cloud[Store.KEY] = _env(7, 9999999999999, _progress(802))
	assert_eq(int(Store.load_data().coins), 802, "full tie: cloud (previous behaviour)")
	Store.save(_progress(803))
	assert_gt(int(_stored("local").seq), 8, "next seq is above every stored copy")

func test_one_atomic_record_per_copy():
	Store.save(_progress(10))
	for src in ["local", "cloud"]:
		assert_eq(mem.data[src].keys(), [Store.KEY], "a single key per copy (no separate stamp key)")
		var e = _stored(src)
		assert_eq(int(e.v), 2)
		assert_true(e.has("seq") and e.has("saved_at") and e.has("profile"))
	Store.save(_progress(11))
	assert_eq(int(_stored("local").seq), 2, "seq increments on every save")

func test_legacy_v1_migration_keeps_everything():
	var legacy = _progress(1234)
	legacy.erase("v")
	legacy.current_grid = {"meta": {"mode": "path", "path_index": 3}, "board": {"cells": [0]}, "level": {"elapsed_ms": 4321, "continues": 0}}
	legacy["path_v"] = 2
	mem.data.local[Store.LEGACY_KEY] = JSON.stringify(legacy)
	mem.data.local[Store.LEGACY_KEY + ".t"] = "1700000000000"
	mem.data.cloud[Store.LEGACY_KEY] = JSON.stringify(_progress(1000))
	mem.data.cloud[Store.LEGACY_KEY + ".t"] = "1600000000000"            # older stamp
	var d = Store.load_data()
	assert_eq(int(d.coins), 1234, "newer-stamped legacy copy wins, as in 24718eb")
	assert_true(Store.last_load.legacy)
	assert_eq(JSON.stringify(d.current_grid, "", true), JSON.stringify(JSON.parse_string(JSON.stringify(legacy.current_grid)), "", true), "grid in progress kept")
	assert_eq(int(d.current_grid.level.elapsed_ms), 4321)
	var p = Profile.new(); p.from_dict(d)
	assert_eq(p.tasks, {"dock": true}); assert_eq(p.path_stars, [3, 2, 1])
	Store.save(p.to_dict())
	assert_eq(int(_stored("local").seq), 1, "first v2 record")
	assert_true(mem.data.local.has(Store.LEGACY_KEY), "legacy copy left in place (nothing lost)")
	assert_eq(int(Store.load_data().coins), 1234, "v2 outranks legacy from now on")
	# unstamped legacy (44aa231 era) on both: cloud wins, as before
	Store.clear()
	mem.data.local[Store.LEGACY_KEY] = JSON.stringify(_progress(1))
	mem.data.cloud[Store.LEGACY_KEY] = JSON.stringify(_progress(2))
	assert_eq(int(Store.load_data().coins), 2)

func test_corrupt_v2_falls_back_to_legacy_same_source():
	mem.cloud = false
	mem.data.local[Store.KEY] = "{oops"
	mem.data.local[Store.LEGACY_KEY] = JSON.stringify(_progress(42))
	assert_eq(int(Store.load_data().coins), 42)

func test_desktop_file_backend_roundtrip():
	Store.backend = Store.FileBackend.new()
	Store.clear()
	Store.save(_progress(66))
	assert_true(FileAccess.file_exists("user://save_v2.json"))
	assert_eq(int(Store.load_data().coins), 66)
	Store.clear()
	assert_false(FileAccess.file_exists("user://save_v2.json"))
