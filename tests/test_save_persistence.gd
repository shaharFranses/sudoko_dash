extends GutTest
## Progress survives restarts and new deploys: versioned saves, migration, unknown keys kept,
## content changes clamped, unreadable main slot falls back to the backup.

const Profile = preload("res://game/profile.gd")
const Levels = preload("res://game/levels.gd")

func before_each():
	Store.clear()

func after_each():
	Store.clear()

func _boot():
	var m = load("res://scenes/main.tscn").instantiate()
	m.play_intro = false
	add_child_autofree(m)
	await wait_frames(2)
	return m

func test_progress_survives_restart():
	var m = await _boot()
	m.profile.coins = 321; m.profile.stars_earned = 7; m.profile.tasks = {"dock": true}
	m.save()
	var m2 = await _boot()
	assert_eq(m2.profile.coins, 321)
	assert_eq(m2.profile.stars_earned, 7)
	assert_true(m2.profile.tasks.has("dock"))
	assert_eq(Store.load_source, "main")

func test_v1_save_migrates_and_keeps_copy():
	Store.save({"v": 1, "path_v": 2, "coins": 55, "stars_earned": 2, "path_next": 3, "tasks": {"dock": true}})
	var m = await _boot()
	assert_eq(m.profile.coins, 55)
	assert_eq(m.profile.path_next, 3)
	assert_true(m.profile.story_seen, "existing player skips the story")
	assert_eq(int(Store.load_data().v), Profile.SAVE_VERSION, "written back in the new format")
	assert_eq(int(Store._parse(Store._read(Store.KEY + ".pre_v1")).coins), 55, "untouched pre-migration copy")

func test_newer_build_keys_are_kept():
	var p = Profile.new()
	var d = p.to_dict(); d.v = Profile.SAVE_VERSION + 3; d["pets"] = {"cat": 1}
	p.from_dict(d)
	var out = p.to_dict()
	assert_eq(out.get("pets"), {"cat": 1}, "rollback to an older build does not lose new data")
	assert_eq(int(out.v), Profile.SAVE_VERSION + 3, "version not downgraded")

func test_content_changes_are_clamped():
	var p = Profile.new()
	var d = p.to_dict()
	d.path_next = 999; d.coins = -5; d.tokens = 99
	d.tasks = {"dock": true, "removed_task": true}
	d.decor = {"dock": 42, "removed_task": 1}
	d.path_stars = []
	for i in 999: d.path_stars.append(1)
	p.from_dict(d)
	assert_eq(p.path_next, Profile.path_length())
	assert_eq(p.coins, 0)
	assert_eq(p.tokens, Profile.TOKEN_CAP)
	assert_eq(p.tasks, {"dock": true})
	assert_eq(p.decor, {"dock": Profile.TASKS[0].decor.size() - 1})
	assert_eq(p.path_stars.size(), Profile.path_length())

func test_stale_path_grid_dropped():
	var lv = Levels.level(0)
	var n = int(lv.size) * int(lv.size)
	var z = []; z.resize(n); z.fill(0)
	var board = {"size": int(lv.size), "givens": z, "solution": z, "cells": z, "notes": z, "history": [], "mistakes": 0,
		"second_chance_used": false, "used_continue": false, "any_mistake": false, "reveals": 0, "failed": false}
	var p = Profile.new()
	var d = p.to_dict()
	d.current_grid = {"meta": {"mode": "path", "path_index": 0, "id": Levels.grid(lv.grid_id).id}, "board": board}
	p.from_dict(d)
	assert_false(p.current_grid.is_empty(), "same puzzle: resumable")
	d.current_grid.meta.id = "puzzle_from_an_old_build"
	p.from_dict(d)
	assert_true(p.current_grid.is_empty(), "level now uses another puzzle: dropped, no crash")
	d.current_grid = {"meta": {"mode": "path", "path_index": 9999, "id": "x"}, "board": board}
	p.from_dict(d)
	assert_true(p.current_grid.is_empty(), "level removed: dropped")

func test_unreadable_save_falls_back_to_backup():
	var m = await _boot()
	m.profile.coins = 777
	m.save()
	var m2 = await _boot()   # boot writes the backup
	assert_eq(m2.profile.coins, 777)
	Store._write(Store.KEY, "{not json")
	var m3 = await _boot()
	assert_eq(Store.load_source, "backup")
	assert_eq(m3.profile.coins, 777, "progress recovered from the backup")
	assert_eq(Store._read(Store.KEY + ".corrupt"), "{not json", "unreadable save kept, not lost")
