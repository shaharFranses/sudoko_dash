# Sudoku Dash (Godot 4.3 vertical slice)
- `sudoku/` engine-agnostic module (RefCounted only): `sudoku.gd` (generate/solve/step/grade), `logic.gd` (techniques), `shape.gd`, `rng.gd` (xorshift32, portable)
- `game/` pure rules: board_state (notes/undo/mistakes), profile (economy, stars, tasks, 24h cap), ad_policy, puzzle_source
- `autoload/` Ads adapter (CrazyGames SDK v3 + mock), Store (CG data / localStorage / user://), Dbg (QA hooks H1-H6, debug builds only)
- `ui/` main flow, grid view, harbour view; `web/head_include.html` SDK glue
- `data/packs/` offline packs (9x9_t1..t4 x300; 4x4_t1 x200, 6x6_t1/t2 x100 fallback); `data/test_vectors.json` (70 vectors for the C# port)

Tests: `godot --headless --path . -s addons/gut/gut_cmdln.gd -gexit` (also grep output for `SCRIPT ERROR`; GUT counts those as risky, not failures)
Packs: `tools/build_all_packs.sh` | Seed dump (H6): `godot --headless --path . -s tools/export_puzzles.gd -- size=6 tier=2 seeds=0-99 format=jsonl out=/tmp/x.jsonl`
Web: `godot --headless --path . --export-release "Web" build/web/index.html` (single-thread, no COOP/COEP)
