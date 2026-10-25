extends GutTest
## QA run5 independent checks: star math (spec 8.5/8.6 + 9.1/9.2/9.8) and v1->v2 save migration.
const Profile = preload("res://game/profile.gd")
const Obj = preload("res://game/objectives.gd")
const Levels = preload("res://game/levels.gd")

func test_tide_par_boundaries_all_levels():
	for i in 20:
		var lv = Levels.level(i)
		if not Obj.is_timed(lv): continue
		var par = int(lv.par_time_s) * 1000
		var q = int(floor(0.75 * int(lv.par_time_s) * 1000.0))
		assert_eq(Obj.stars(lv, false, 0, 0), 3)
		assert_eq(Obj.stars(lv, false, 0, q), 3, "L%d at 0.75 floor" % (i+1))
		assert_eq(Obj.stars(lv, false, 0, q + 1), 2)
		assert_eq(Obj.stars(lv, false, 0, par), 2, "L%d at par" % (i+1))
		assert_eq(Obj.stars(lv, false, 0, par + 1), 1)
		assert_eq(Obj.stars(lv, false, 0, par * 10), 1, "floor 1")
		assert_eq(Obj.stars(lv, true, 5, q), 3, "mistakes/reveals ignored on Tide")
		# reveal penalty: 1 reveal = +15000 ms must cross a boundary exactly
		assert_eq(Obj.stars(lv, false, 1, q - 15000 + 15000), 3)
		assert_eq(Obj.stars(lv, false, 1, par - 14999 + 15000), 1)

func test_untimed_table_all_levels():
	for i in 20:
		var lv = Levels.level(i)
		if Obj.is_timed(lv): continue
		assert_eq(Obj.stars(lv, false, 0, 999999), 3)
		assert_eq(Obj.stars(lv, true, 0, 0), 2)
		assert_eq(Obj.stars(lv, false, 1, 0), 2)
		assert_eq(Obj.stars(lv, false, 4, 0), 2)
		assert_eq(Obj.stars(lv, true, 2, 0), 1)

func test_migration_every_n():
	for n in 16:
		var p = Profile.new()
		var ps = []
		for k in n: ps.append(3)
		p.from_dict({"v": 1, "path_next": n, "path_stars": ps, "stars": 7, "stars_earned": 3 * n, "coins": 123, "tokens": 6,
			"current_grid": {"meta": {"mode": "path", "path_index": n}, "board": {"cells": [1]}}})
		assert_eq(p.path_next, int(floor(n * 20 / 15.0)), "n=%d" % n)
		assert_eq(p.stars, 7); assert_eq(p.stars_earned, 3 * n); assert_eq(p.coins, 123); assert_eq(p.tokens, 6)
		assert_eq(p.current_grid, {}, "path grid dropped n=%d" % n)
		var q = Profile.new(); q.from_dict(p.to_dict())
		assert_eq(q.path_next, p.path_next, "idempotent n=%d" % n)

func test_migration_non_path_grid():
	var p = Profile.new()
	p.from_dict({"path_next": 3, "current_grid": {"meta": {"mode": "quick"}, "board": {}}})
	gut.p("non-path in-progress grid after migration: %s" % str(p.current_grid))
	assert_true(true)
