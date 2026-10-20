# Sudoku Dash: Level Objectives Spec (v1.3: no 4x4 on the path; Digit Hunt hides target positions)
Owner: SD Game Design. Builds on VERTICAL_SLICE_SPEC.md v3.1 (input, notes, undo, mistakes, hints, ads, and save are unchanged unless stated here). In scope are 4 objective types plus Full Solve. Sum Spotlight is parked.
- **Bar for future objectives:** each one has to change how the player plays, not just add a constraint or a reskin.

## 1. Core rules
- Every level is one pregenerated grid (exactly one solution) plus one objective with target cells **T**. Each level starts fresh from that grid's givens.
- **Valid level:** the grader's logical solve from the givens fills every cell of T. The level's tier is the hardest technique used up to the step where the last cell of T is filled. Store `steps_to_T`.
- **Complete:** every cell of T holds its correct digit. Digits outside T are allowed but not required. Wrong digits anywhere still count as mistakes.
- Teach works as in v3.1, but prefers steps whose cell is in T or whose eliminations affect T. If none exists, it shows the next valid step on the board.

## 2. Objective types
| Type | Player sees | T | Params |
|---|---|---|---|
| **Full Solve** | "Solve the board" | All empty cells | — |
| **Digit Hunt** | "Place every 1" (cells with that digit are counted, e.g. 3/9). Target cells are **never** outlined or highlighted; the player must deduce them (v1.3) | Empty cells whose solution is d | `digit` |
| **Fill the Line** | "Complete row 4" (the unit is outlined) | Empty cells of 1-2 units | `units: [{"kind":"row/col/box","index":0-based}]` |
| **Lantern Path** | A chain of lanterns lights up as cells are solved | 6-10 orthogonally connected cells, at least 4 of them empty | `path: [[r,c],...]` |
| **Beat the Tide** | A tide bar plus one of the objectives above | T of the inner objective | `inner` (any type above), `par_mult` |

## 3. Stars (each level is 1-3 stars)
- **Base:** 1 star for completing the level.
- **Non-timed levels:** +1 for 0 mistakes (using Continue counts as having mistakes), +1 for no Reveal.
- **Beat the Tide:** +1 for finishing under par, +1 for finishing under 0.75x par. Mistakes and Reveal don't affect its stars.
- Only a level's first completion awards stars, and replaying keeps the best result. Quick and Classic modes give coins only.

## 4. Timer (Beat the Tide only)
- `par_time_s = round((base + 6 × steps_to_T) × par_mult)`. The base is 20 for 6x6, and 30 for 9x9.
- The timer is soft: reaching zero never fails the level, the bar just turns calm grey and the speed stars are gone.
- The timer pauses whenever the Hint, Second chance, or Pause panel is open and when the tab is hidden. Each Reveal adds 15 s; Teach adds nothing.
- Continue keeps the elapsed time. Retry resets it to 0. No ads during a level.

## 5. Village Path (20 levels on 12 grids)
| L | Grid | Size | Objective | Params | Tier |
|---|---|---|---|---|---|
| 1 | G01 | 6x6 | Digit Hunt | digit 1 | 1 |
| 2 | G01 | 6x6 | Fill the Line | row 0 | 1 |
| 3 | G02 | 6x6 | Full Solve | — | 1 |
| 4 | G03 | 6x6 | Digit Hunt | digit 3 | 1 |
| 5 | G03 | 6x6 | Lantern Path | 6 cells | 1 |
| 6 | G04 | 6x6 | Full Solve | — | 1 |
| 7 | G05 | 6x6 | Fill the Line | box 2 | 2 |
| 8 | G05 | 6x6 | Beat the Tide | inner: Fill the Line, 2 rows, par 2.0 | 1-2 |
| 9 | G06 | 6x6 | Full Solve | — | 2 |
| 10 | G06 | 6x6 | Beat the Tide | inner: Full Solve, par 2.0 | 2 |
| 11 | G07 | 9x9 | Digit Hunt | digit 5 | 2 |
| 12 | G07 | 9x9 | Lantern Path | 8 cells | 2 |
| 13 | G08 | 9x9 | Full Solve | — | 2 |
| 14 | G09 | 9x9 | Fill the Line | row + col | 2 |
| 15 | G09 | 9x9 | Beat the Tide | inner: Fill the Line, box, par 1.75 | 2 |
| 16 | G10 | 9x9 | Full Solve | — | 2 |
| 17 | G11 | 9x9 | Digit Hunt | digit 7 | 3 |
| 18 | G11 | 9x9 | Lantern Path | 10 cells | 3 |
| 19 | G12 | 9x9 | Fill the Line | col 4 | 3 |
| 20 | G12 | 9x9 | Full Solve (finale) | — | 3 |
- **Mix:** 6 Full Solve, 4 Digit Hunt, 4 Fill the Line, 3 Lantern Path, and 3 Beat the Tide, which is 20 levels. The Beat the Tide levels have Fill the Line as the inner objective twice (L8 and L15) and Full Solve once (L10); they're counted only as Beat the Tide. That makes 7 full-board solves, counting L10. There's at least 1 full solve in every 4 levels and never 2 timed levels in a row.
- **Path stars:** 20 at minimum (20 levels × 1) and 60 at maximum (20 × 3).
- **Harbour tasks (retuned, 20 stars total, equal to the minimum):** Fix dock 3, Paint boats 4, Plant flowerbeds 4, Restore lighthouse 4, Café terrace 5. Finishing the path always restores the Harbour, and leftover stars (up to 40) carry over to the next area. Tasks unlock in order, and each can be bought as soon as the player can afford it.

## 6. Level data (`data/levels/harbour.json`, built offline by `tools/build_levels.gd`)
```json
{"level": 15, "grid_id": "G09", "size": 9, "objective": "tide",
 "params": {"inner": "line", "units": [{"kind": "box", "index": 4}], "par_mult": 1.75},
 "target": [[3,3],[3,5],[4,4]], "tier": 2, "steps_to_t": 23, "par_time_s": 294}
```
Grids live in the existing packs and are referenced by `grid_id`. `target`, `tier`, `steps_to_t`, and `par_time_s` are computed by the tool and never written by hand. `par_time_s` is null for untimed levels. The 6x6 path grids are also pregenerated, so the path is identical for every player.

## 7. Out of scope
Sum Spotlight (parked), failing a level when time runs out, leaderboards, variant rules, objectives in Quick and Classic modes, daily objective events, and an objective editor.

## 8. Acceptance criteria (pass/fail)
1. `build_levels.gd` runs headless and emits 20 levels. For each one, a logical solve fills every target cell, and the stored tier and steps match a fresh recompute.
2. A GUT test checks the T set for each type: Digit Hunt has exactly the empty cells of that digit; Fill the Line has the empty cells of the listed units; Lantern Path is 6-10 orthogonally connected cells with at least 4 empty.
3. A level completes the moment the last target cell is correct, even with non-target cells still empty, and no earlier.
4. A wrong digit outside T counts as a mistake. The third mistake opens the Second chance panel as in v3.1.
5. Non-timed stars: 0 mistakes and no Reveal gives 3; 1 or more mistakes or any Continue removes 1; any Reveal removes 1; the floor is 1.
6. Beat the Tide stars: finishing under 0.75x par gives 3, under par gives 2, over par gives 1. Reaching 0 never ends the level.
7. The timer doesn't advance while any panel is open or the tab is hidden, and each Reveal adds exactly 15 s.
8. Retry resets the timer to 0, and Continue keeps the elapsed time.
9. 0 ad calls while a level is open, apart from rewarded ads the player starts from a panel (as in v3.1).
10. Teach on a partial objective highlights a step that touches T whenever such a step exists.
11. Playing the path with the most mistakes and Reveals and over par gives exactly 20 stars, and that's enough to buy all 5 tasks. A perfect run gives exactly 60.
12. After a reload, completion, best stars per level, and a level in progress (including timer elapsed) are restored exactly.
13. The path order and objectives exactly match the table in section 5.

## 9. Clarifications (v1.2, answering QA's questions)
1. **Par:** "under par" means elapsed_ms is less than or equal to par_time_s × 1000, at millisecond resolution. The 0.75x threshold is elapsed_ms ≤ floor(0.75 × par_time_s × 1000).
2. **Reveal penalty:** each Reveal adds 15,000 ms to elapsed_ms, which is the value compared against par and shown on the bar.
3. **Retry** starts a clean attempt: mistakes, Reveals, Continues, and the timer all reset, and stars come only from the attempt that completes. **Continue** doesn't change Beat the Tide stars; elapsed time is kept.
4. **Teach "touches T"** means the step places a digit in a T cell, or removes at least one candidate from a T cell. Steps that only affect cells outside T don't count, even if they help indirectly.
5. **Lantern Path:** T is the empty cells only. The 6-10 path cells (givens included) are what's drawn on screen, and at least 4 of them must be empty.
6. **Timer pause:** the timer pauses while any panel is open, which includes a rewarded ad started from a panel. It pauses when the tab is hidden (`visibilitychange`) and when the window loses focus.
7. **Reload:** the restored elapsed_ms is within ±1,000 ms of the saved value. Saves happen on every input and at least every 5 s.
8. **Reveal on the last target cell** completes the level, and it counts as a Reveal for stars (and adds +15 s).
9. **Cap and the minimum-star run:** the 20-star run never needs a second chance, because Retry is always available. A test can use Retry or the debug hook that resets the cap. On a Beat the Tide level, the 1-star minimum comes from finishing over par.

## 10. v1.3 changes (Shahar feedback, 2026-10-20)
- **No 4x4 boards on the Village Path.** G01 and G02 now come from `6x6_t1`; L1-L10 are 6x6 and L11-L20 are 9x9. Objectives, params, tiers, star range (20-60) and Harbour costs (3/4/4/4/5 = 20) are unchanged.
- Every path board uses the normal rules (3-mistake limit, Second chance). The 4x4 "Warm-up: no mistake limit" rule no longer appears on the path.
- **Digit Hunt does not reveal positions.** The grid draws no outline/highlight on T for Digit Hunt (or a Beat the Tide with inner Digit Hunt). Only the counter (e.g. 3/6) is shown. Fill the Line and Lantern Path still mark their cells, since those are chosen by the level, not deduced.
- Save migration: unchanged (level count is still 20). A save that had cleared L1-L3 keeps those clears; they now refer to the 6x6 versions.
