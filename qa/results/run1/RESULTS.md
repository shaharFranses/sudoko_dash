# QA Run 1: non-GUI tests (no browser driven by this worker)
Source: commit **05a922d** (HEAD). Builds checked (unchanged through the whole run; see `BUILD_HASHES.txt`):
| File | mtime (IDT, UTC+3) | sha256 |
|---|---|---|
| build/web/index.pck | 2026-10-20 11:33:29 | 65f80dec14421a5cbd41e19e8737af08c83cddf297f9c17073e1ea5c6d9bcbfc |
| build/web/index.wasm | 2026-10-20 11:33:30 | 20bbe3d6bd8f1197b59335c4263b126ac435e8c8c74fa063227121e27210723a |
| build/web-release/index.pck | 2026-10-20 11:33:34 | a53ebec2192fd9f3e3345034fe7cfec99e9389ba0d8ef30e5dca14ef309073e7 |
| build/web-release/index.wasm | 2026-10-20 11:33:34 | fe5cebc590758c10bc4469be5a591e28edbde5ec8f458f21baeb83db50d028b9 |

Godot 4.3.stable (headless). Superseded first-pass outputs from 8891ad9 are kept in `seeds_old_8891ad9/` for reference only; they aren't used for any verdict below.

## Verdicts per test
| Test | AC | Verdict | Evidence |
|---|---|---|---|
| GRID-01 GUT headless | 1 | **PASS**: 78/78 tests, 574 asserts, 0 failures, 0 `SCRIPT ERROR` (the 8891ad9 run had 2 in test_ad_failures.gd, now fixed). Only an "ObjectDB leaked at exit" warning. | `GRID-01_gut.txt` |
| GRID-02 packs unique and tier | 2 | **PASS**: 1600/1600 (9x9 t1-t4 x300, 4x4 x200, 6x6 t1/t2 x100). Independent checker: exactly 1 solution, stored solution matches, checker tier = stored tier. Pack data is byte-identical to the checked set (sudoku/, data/, tools/ unchanged 8891ad9..05a922d). | `packs/*.check.txt`, `packs/UNCHANGED_SINCE_8891ad9.txt` |
| GRID-03 seeded export (H6), 200 per difficulty | 2 | **PASS**: 7 size/tier combos x 200 = 1400/1400 unique, checker tier = requested, game grade = requested, game solution_count = 1. | `seeds/SUMMARY.txt`, `seeds/s*_t*.check.txt` |
| GRID-04 determinism | 2 | **PASS**: two independent exports of seeds 0-19 (4x4 t1, 6x6 t2) are byte-identical. | `determinism/RESULT.txt` |
| GRID-05 pack steps vs checker | 2 | **PASS (tier level)**: checker tiers agree on all 1600. Step-by-step comparison of the stored `steps[]` wasn't done; stored steps aren't shown to players (v3). | `packs/` |
| GR-01 independent grader | 2 | **PASS** (same data as GRID-02/03, 3000 puzzles total). | as above |
| GR-02 known-technique fixtures | 2 | **PASS (via GUT)**: test_vectors_match_module, test_steps_are_sound_on_vectors, test_vectors_cover_all_tiers_9x9. | `GRID-01_gut.txt` |
| GR-03 clue count isn't the grade | 2 | **PASS**: 9x9 clue ranges overlap across tiers (t1 23-29, t2 21-28, t3 22-28, t4 21-28). | `GR-03_clues_vs_tier.txt` |
| GRID-06 no runtime 9x9 gen | 3 | **PASS (static + headless)**: puzzle_source returns 9x9 only from packs; GUT test_runtime_never_generates_9x9 and test_runtime_no_9x9_generation_logged. The in-browser log check is left to the browser worker. | source, `GRID-01_gut.txt` |
| GRID-07 4x4/6x6 gen at most 30 ms p95 | 3 | **NOT RUN in web (browser worker).** Native runtime path (puzzle_source.get_puzzle, 100 calls each): 4x4 p95 1.3 ms; 6x6 t1 p95 9.1 ms (max 30.2); 6x6 t2 p95 15.1 ms because it **falls back to the pack after the first slow generations** (96/100 from pack; generations take up to 34.6 ms native). **Risk:** wasm is typically 1.5-3x slower, so the first few 6x6 generations in the browser may exceed 50 ms per frame (AC3 frame rule) before fallback kicks in. | `gen_timing_solo/RUNTIME_PATH_native.txt`, `gen_timing_solo/GEN_TIMING_solo.txt` |
| HN-02 Teach = valid live step (module level) | 7 | **PASS**: game `step()` output fed to `sudoku_check.py --step`. 210 fresh boards (step(givens) on 30 per size/tier) plus all 1400 seeded first steps: all valid. | `step/SUMMARY.txt`, `seeds/SUMMARY.txt` |
| HN-04 diverged 9x9 Teach (module level) | 14 | **PASS**: 200 random-order diverged 9x9 boards (all naked singles) and 200 diverged t3/t4 boards stuck after singles (naked pair 142, hidden pair 34, pointing 22, box-line 2). **400/400 valid** under the N3 rule. `step()` native: median 0.28 ms, max 0.95 ms (budget 20 ms). The UI part (highlights, label) is left to the browser worker. | `teach_diverge/SUMMARY.txt`, `teach_diverge/boards/` |
| HN-05 wrong digit flag-and-stop | 14 | **Not GUI-free.** GUT test_teach_matches_step_and_flags_wrong_first passes; the UI check is for the browser worker. | `GRID-01_gut.txt` |
| P3 rules (SC-/RW-/AD- logic) | 9,10,15 | **PASS at rules level (GUT, 05a922d)**: rolling 24 h cap, clock rollback until newest + 24 h, retry, token cap 10, coin hint, ad error/timeout (8 s default), midgame policy, never both on results, unaffordable option disabled. The in-browser SC-/AD- screens are for the browser worker. **Gap:** there's no GUT test by name for RW-04 (ad-for-token button hidden at 10 tokens); the code exists per the 8891ad9 commit message, so it needs browser verification. | `GRID-01_gut.txt` |
| BOOT-03 single-thread / no SAB | 4 | **PASS**: export preset `thread_support=false`; `ensureCrossOriginIsolationHeaders:false`; wasm memory is defined and **not shared** (both builds); the release is served on :8061 with **no** COOP/COEP and still fetches correctly. Note: :8060 (debug) sends COOP/COEP, so boot tests there don't prove a header-less boot. Use `http://127.0.0.1:8061/web-release/index.html` for the CrazyGames-like check. | `REL-01_build_inspect.txt` |
| REL size | 4 | **PASS with warning**: release initial download 39.5 MB raw (wasm 35.4 + pck 3.7 + js 0.33), about 8.6 MB gzip (wasm 8.0, pck 0.47, js 0.08). Under the ~50 MB limit; **over the 20 MB recommendation if CrazyGames counts uncompressed**, but well under it gzipped. | `REL-01_build_inspect.txt` |
| REL debug hooks | n/a | **PASS (static), with a caveat.** The release pck **still contains** the hook code (`autoload/dbg.gdc` with SD_DEBUG/SD_QA/__midgame/__sdDump/?ads=/?clock=, F6-F8; `ads.gdc` with __adsLog and the mock_* modes). All of it is gated by `OS.is_debug_build()`, and the release uses the release template (35.4 MB wasm vs 43.0 MB debug). No other caller of `Ads.set_mode`. Raw index.js/index.html have none of the hook names (the `F6`/`F8`/`ads=` hits are Emscripten/Godot internals like `pads=`). **Needs a runtime confirmation** from the browser worker on the release: `window.SD_DEBUG`, `window.SD_QA` and `window.__adsLog` are undefined, `?ads=unavailable` and `?clock=` are ignored, and F6-F8 do nothing. | `REL-03_debug_hook_audit.txt`, `pck_extract/web-release/` |
| REL pck hygiene | n/a | **Minor FAIL (non-blocking)**: the release pck ships `data/test_vectors.json` (120 KB) and 6 `build/web*/…png.import` files (the build/ dir has no `.gdignore`). `addons/gut` appears only in the class/uid caches (no GUT scripts shipped). | `REL-02_pck_listing.txt` |
| REL CrazyGames SDK v3 | 8,10 | **PASS with risks** (static): loads `https://sdk.crazygames.com/crazygames-sdk-v3.js` only on `/crazygames\./` hosts or `?cgsdk=1`; `SDK.init()`, `ad.hasAdblock()`, `ad.requestAd(type,{adStarted,adFinished,adError})`, `game.gameplayStart/Stop`, `data.setItem/getItem` with a localStorage fallback. See the risks below. | `index.html` lines 81-125 (release) |

Not run by this worker (GUI, owned by the browser worker): BOOT-01/02/04/05/06, GRID-07/08 in web, IN-*, HN-01/03/05 UI, SC-*/AD-*/RW-* screens, PS-*, MT-* visuals, UI-*.

## Per acceptance criterion (what non-GUI could establish)
| AC | Verdict |
|---|---|
| 1 | PASS |
| 2 | PASS |
| 3 | 9x9-no-runtime-gen PASS; web timing/frames pending the browser (risk on 6x6 t2 first frames) |
| 4 | Single-thread requirement PASS; boot/console pending the browser |
| 7 | PASS at module level; UI pending |
| 14 | PASS at module level (400/400, step at most 1 ms native); UI pending |
| 5, 6, 8, 9, 10, 11, 12, 13, 15 | GUT rules-level PASS; in-browser verdicts pending |

## CrazyGames Basic Launch: blockers / risks
- **No hard blocker found.** Single-thread and no SAB/COOP/COEP needed; size under 50 MB; SDK v3 present; no hooks reachable in release (pending a runtime confirmation).
- Risk 1: `SDK.game.loadingStart()/loadingStop()` are **never called**. CrazyGames recommends them for v3; confirm whether the QA review requires them.
- Risk 2: the save `load()` can run before the async SDK `init()` resolves. On the portal, the first read then comes from localStorage instead of CrazyGames data, so progress could look lost if the two differ.
- Risk 3: ads are enabled only when `SDK.environment === 'crazygames'`. In the CrazyGames QA tool / `local` environment, rewarded buttons are hidden, so real ad flows can't be exercised there. Portal detection depends on the hostname matching `crazygames.`.
- Risk 4: `available()` returns true before `hasAdblock()` resolves, so there's a short window after boot where rewarded buttons could show under an adblocker.
- Risk 5: off-portal, the release defaults to `mock_available`, so rewarded ads "succeed" instantly (free coins and tokens) on any non-CrazyGames host. This isn't a CrazyGames issue, but it's an exploit if the build is ever hosted elsewhere.
- Size: 39.5 MB raw is over the 20 MB recommendation if it's measured uncompressed.
- Hygiene: exclude `build/` (add a `.gdignore`), `data/test_vectors.json` and, ideally, `autoload/dbg.gd` from the release export.

## Tools added for this run
`qa/run_seed_checks.py` (export json -> checker + game-step validation), `qa/teach_diverge.gd` (diverged/stuck 9x9 boards -> live `step()`), `qa/runtime_gen_timing.gd` (runtime puzzle_source timing). `qa/results/.gdignore` was added so Godot doesn't import evidence PNGs (earlier headless runs had created `.import` files next to the browser worker's screenshots in `browser/`).
