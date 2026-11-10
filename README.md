# Sudoku Dash (Godot 4.3 vertical slice)
- `sudoku/` engine-agnostic module (RefCounted only): `sudoku.gd` (generate/solve/step/grade), `logic.gd` (techniques), `shape.gd`, `rng.gd` (xorshift32, portable)
- `game/` pure rules: board_state (notes/undo/mistakes), profile (economy, stars, tasks, 24h cap), ad_policy, puzzle_source
- `autoload/` Ads adapter (CrazyGames SDK v3 + mock), Store (CG data / localStorage / user://), Dbg (QA hooks H1-H6, debug builds only)
- `ui/` main flow, grid view, harbour view; `web/head_include.html` SDK glue
- `pkd_intro/` PKD studio intro (drop-in from /workspace/pikeydi-logo/godot, INTEGRATION.md overlay mode): plays over the title at boot; sound, ads and every SDK call (loadingStop, gameplayStart/Stop, requestAd) wait for its `finished`; tap/click/key skips. v1.1: wall-clock playback (~1.93 s from the first visible frame, hard cap 2.5 s). Plain navy `#1E1B3A` boot splash (`pkd_boot_splash_plain.png`) + HTML loader with no logo, so the PKD mark appears once, at the end of the morph
- `data/packs/` offline packs (9x9_t1..t4 x300; 4x4_t1 x200, 6x6_t1/t2 x100 fallback); `data/test_vectors.json` (70 vectors for the C# port)

Tests: `godot --headless --path . -s addons/gut/gut_cmdln.gd -gexit` (also grep output for `SCRIPT ERROR`; GUT counts those as risky, not failures)
Packs: `tools/build_all_packs.sh` | Seed dump (H6): `godot --headless --path . -s tools/export_puzzles.gd -- size=6 tier=2 seeds=0-99 format=jsonl out=/tmp/x.jsonl`
Web: `godot --headless --path . --export-release "Web" build/web/index.html` (single-thread, no COOP/COEP)

## Release pipeline (GitHub Actions)
| Stage | Trigger | Build | Where |
|---|---|---|---|
| Tests | every PR (and before every deploy) | GUT, headless Godot 4.3 | PR checks |
| Staging / playtest | push / merge to `dev` | `Web` preset, debug (QA hooks on) | `https://shaharfranses.github.io/sudoko_dash/staging/` |
| Production | tag `v*` (`git tag v1.3.0 && git push origin v1.3.0`) | `Web Release` preset | GitHub Release zip (upload to CrazyGames) + site root `https://shaharfranses.github.io/sudoko_dash/` |

- Merging never ships to players; only a tag does. The tested staging commit is the one you tag.
- Rollback: Actions > Release > Run workflow with an older tag (rebuilds and redeploys it; saves are forward/backward compatible, see below).
- Staging lives in `staging/` on the `gh-pages` branch, the live build at its root; each deploy only replaces its own part. Staging uses its own save slot (`sudoku_dash_save_v1_staging`).
- Optional manual gate: add required reviewers to the `production` environment (Settings > Environments).

## Saves (progress across runs and deploys)
- One slot, key `sudoku_dash_save_v1` (CrazyGames data module + localStorage on web, `user://save.json` on desktop). **Never rename it**: that wipes every player's progress.
- Saves are versioned (`Profile.SAVE_VERSION`, field `v`). To change what a field means: bump the version and add a step to `Profile._migrate()`. Add fields freely (give them a default in `_from_dict_known`); never reuse a key.
- On load, `Profile._sanitize()` fits the save to the current content: path progress clamped to the level count, removed tasks/decor dropped, and an in-progress path grid is dropped if its level now uses a different puzzle. Changing levels, tasks or packs in a deploy never crashes an old save.
- Keys written by a newer build are kept and written back, so rolling back a deploy loses nothing.
- Safety copies: `.bak` (last save that loaded cleanly, refreshed each boot; used if the main slot is unreadable), `.pre_v<N>` (untouched copy before a migration), `.corrupt` (an unreadable main slot, kept for recovery).
- localStorage is per web origin: moving the game to a new domain starts players fresh (on CrazyGames the data module carries progress).

## Level path (LEVEL_OBJECTIVES_SPEC v1.2)
- Data: `data/levels/harbour.json` (committed; 20 levels on 12 grids from `data/packs/`).
- Rebuild (headless, deterministic, validates every level with `Sudoku.analyze_targets`):
  `godot --headless --path . -s tools/build_levels.gd`
- QA: `SD_DEBUG.startLevel(n)` jumps to level n (debug builds).
- Cheat (staging / debug builds only, never in the release export): a **CHEAT: Solve** button at the top centre of every grid screen fills the grid in one tap and goes to results; F9 does the same on desktop. Lives in `debug/qa_hooks.gd`.
- Debug hook H7 (debug builds only): on-screen `TimerDebug` readout on Beat the Tide levels; the state dump
  (`step_dump()` / `window.SD_QA`) includes `level, objective, params, target, elapsed_ms, reveals, continues, par_time_s, timer_running`.
