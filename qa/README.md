# qa/ — Sudoku Dash QA harness (SD QA)

Independent runtime checks for the Godot 4.3 web build. These scripts aren't part of the game.
`qa/.gdignore` keeps this folder out of Godot's import, and the export presets also exclude `qa/*`.
GUT's default config (`.gutconfig.json` → `res://tests/`) never loads anything from here.
Scripts run with `-s` and GUT runs pointed at `-gdir=res://qa` still work.
You can reuse the harness for game #4 (Meowdoku) by changing the URLs, ports and colour/OCR keys.

**Box assumptions (absolute paths, not secrets):**
- Chrome is at `/usr/bin/google-chrome`.
- Python venvs:
  - `/tmp/qav` has `websocket-client` and `Pillow`.
  - `/tmp/zv` has `zstandard` (release_audit.sh creates it).
- `tesseract` must be on PATH.
- Local servers are on `127.0.0.1:80xx`.
- Temp screenshots go to `/tmp/_*.png`.
- `run10_extra.py` uses `WT=/tmp/wt_ede4bfd`.
- The comment header of `hint_memory.gd` mentions `/workspace/sudoku-dash`.
- Output goes to `qa/results/<run>/`. That folder isn't committed for new runs because it's too big; keep it local.

## Scripts (run from repo root unless noted)

| Script | What it does | How to run |
|---|---|---|
| `serve.py` | Static server with COOP/COEP + no-store headers (needed for Godot web threads) | `python3 qa/serve.py 8069 /workspace/sudoku-dash-gated` |
| `mobile_qa.py` | Raw-CDP headless Chrome driver (`CDP` class). It uses mobile emulation with touch-only input. Modes: 5-viewport mobile regression, harbour drag-scroll, rotation, desktop clip, release smoke. Env vars: `QA_BUILD`, `QA_RUN`, `QA_DEBUG_PORT`, `QA_RELEASE_PORT`, `QA_DESKTOP_REF` | `QA_BUILD=<sha> QA_RUN=runN /tmp/qav/bin/python qa/mobile_qa.py mobile 390x844 \| rotate \| desktop \| release` |
| `live_check.py` | Checks the deployed release build, which has no hooks. It finds buttons by colour and reads text with tesseract OCR | `/tmp/qav/bin/python qa/live_check.py mobile\|desktop [url]` |
| `ocr_locate.py` | Library: colour-agnostic UI text locator (tesseract TSV on dark/light masks), used from the art build onward | imported by run10*/run11* |
| `cg_sizes.py` | CrazyGames embed-size readability/layout check at DPR 1 with mouse input. Measures glyph px for the grid, notes, buttons and hint panel | `/tmp/qav/bin/python qa/cg_sizes.py 800x450 [url] [tag] [cdp_port]` |
| `cg_sizes_report.py` | Builds the per-size verdict table from `results/cg_sizes/live_<size>.json` | `python3 qa/cg_sizes_report.py` |
| `run10.py` | Art-build wrappers that monkeypatch `mobile_qa` button finders with OCR. Modes: mobile, harbour, rotate | `QA_BUILD=<sha> QA_RUN=<run> QA_DEBUG_PORT=8070 /tmp/qav/bin/python qa/run10.py mobile 390x844 <cdp_port>` |
| `run10_extra.py` | Art-build extra modes: desktop, cg WxH, visual (contrast, error underline/shake, lock icons, sprite swap), landscape, release. Env var: `QA_RELEASE_URL` | `/tmp/qav/bin/python qa/run10_extra.py <mode> [WxH] <cdp_port>` |
| `run11_intro.py` | Checks the PKD studio intro. Modes: natural, skip_touch, skip_mouse, skip_key, sdk. It logs SDK, audio and console timing with a mock CrazyGames SDK | `QA_BUILD=<sha> QA_RUN=<run> /tmp/qav/bin/python qa/run11_intro.py MODE WxH PORT [URL]` |
| `run11_release_smoke.py` | Gated release: boot, then the intro, then the title, then Play opens the Harbour | `/tmp/qav/bin/python qa/run11_release_smoke.py WxH PORT` |
| `sudoku_check.py` | Independent solver, uniqueness checker, technique grader and `--step` validator | `python3 qa/sudoku_check.py puzzles.jsonl [--strict-tier]` |
| `selftest.sh` | Self-test of `sudoku_check.py` against `fixtures/` | `sh qa/selftest.sh` |
| `run_seed_checks.py` | Converts generator dumps and checks game grade = requested tier and first step | `python3 qa/run_seed_checks.py <dir of s{size}_t{tier}.json>` |
| `check_levels.py` | Level path check: uniqueness, tiers, objective spec per level, 20/60 stars | `python3 qa/check_levels.py data/levels/harbour.json` |
| `teach_targets.gd` | Headless dump of `Sudoku.step_for_targets` on random partial boards per level | `godot --headless --path . -s qa/teach_targets.gd -- out=/tmp/tt.json n=40` |
| `check_teach_targets.py` | Validates the teach_targets dump: steps are valid and touch the targets | `python3 qa/check_teach_targets.py /tmp/tt.json` |
| `hint_memory.gd` | Headless dump of repeated paid Teach hints with nothing placed (mirrors `ui/main.gd _pay_hint`) | `godot --headless --path . -s qa/hint_memory.gd -- out=/tmp/hm.json n=4` |
| `check_hint_memory.py` | Validates the hint_memory dump: each paid hint is new, the free re-show works, and Digit Hunt is preferred | `python3 qa/check_hint_memory.py /tmp/hm.json [--cli]` |
| `teach_diverge.gd` | Live Teach on diverged 9x9 boards | `godot --headless --path . -s qa/teach_diverge.gd -- out=/tmp/dir n=50` |
| `runtime_gen_timing.gd` | Times the runtime puzzle generation for 4x4/6x6 | `godot --headless --path . -s qa/runtime_gen_timing.gd` |
| `test_qa_run5.gd` | Independent GUT tests: star math and v1→v2 save migration | `godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://qa -gprefix=test_ -gexit` |
| `release_audit.sh` | Lists the pck contents of build/web-release against build/web. Flags debug/, tests/, qa/, addons/, tools/ and `.import` leaks | `qa/release_audit.sh <out_dir>` (run on a temp copy) |
| `retro/SD_QA_RETRO.md` | SD QA retro: what worked, time sinks, gaps, reusable items | — |
| `../QA_TEST_PLAN.md` | Full test plan, including P7 LO-* and LQ-1..9 | — |

## Debug hook contract (debug builds only; `debug/qa_hooks.gd`, stripped from Web Release)
- `window.SD_DEBUG.startLevel(n)`: jump to harbour level n (1–20).
- `SD_DEBUG.setTokens(n)` and `SD_DEBUG.setCoins(n)`: set the wallet.
- `SD_DEBUG.dump()`: full state dump.
- Other `SD_DEBUG` hooks:
  - `setAdMode(m)`
  - `setClockOffsetMs(ms)`
  - `resetSecondChanceCap()`
  - `show(screen)`
  - `solve()`
  - `rect(node)`, which writes CSS px to `window.__sdRect`
  - `layout()`, which writes to `window.__sdLayout`
- `window.SD_QA` holds the published state.
  - `SD_QA.stepDump` (also `window.__sdDump`) has `elapsed_ms`, `reveals`, `continues` and `timer_running`.
  - `SD_QA.midgame` is also exposed as `window.__midgame`.
- `window.__adsLog` logs ad calls (H2).
- URL params: `?ads=available|unavailable|error|timeout` and `?clock=<ms>`.
- Keys: F6 cycles the ad mode, F7 dumps state, F8 adds 25 h to the clock.
- H7: an on-screen TimerDebug label (tide timer readout) in debug builds (`ui/main.gd`).
- Release builds have no hooks. Use `live_check.py`, `run11_release_smoke.py` and `cg_sizes.py`, which use colour and OCR only.

## Gated-folder workflow (each build that ships)
1. Check the debug build in a real browser: run the mobile_qa / run10 / run11 modes against `/workspace/sudoku-dash-debug/<sha>/` served by `serve.py`.
2. Release export from a clean worktree of `<sha>` with the **Web Release** preset into `/workspace/sudoku-dash-gated/<sha>/`, then write `SHA256SUMS.txt` (`sha256sum * > SHA256SUMS.txt`).
3. Run `qa/release_audit.sh` on a temp copy. Expect no debug/, tests/, qa/, tools/, addons/ or `.import` entries in the pck.
4. Run GUT on the worktree (`godot --headless --path . -s addons/gut/gut_cmdln.gd -gexit`). It must pass in full. `test_generation_budget_4x4_6x6_p95` is load-flaky, so rerun it alone if it fails.
5. Report PASS/FAIL with evidence in `qa/results/<run>/RESULTS.md`.
6. After deploy, check that the curl sha256 of the live `index.pck` equals the gated pck, and run `live_check.py` for phone and desktop.
7. Only then does a link go to Shahar.
