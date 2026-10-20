# Sudoku Dash: QA Test Plan (Vertical Slice, spec v3 + Level Objectives v1.1)
Target: Godot 4.3 **single-thread** web export. Primary browser: Chrome on the QA box; Firefox ESR (`/usr/bin/firefox`) for AC4. Source: `VERTICAL_SLICE_SPEC.md` v3 (15 acceptance criteria; G1-G11 resolution status below).
Each test is binary **PASS/FAIL**. Evidence goes to `qa/evidence/<TEST-ID>_*` (screenshot = PNG, console = `.log` from DevTools "Save as", script = stdout `.txt`).
Ordered by priority (P1 is highest). Build path: TBD (waiting on SD Godot Build).

## Test environment
- Serve the export locally: `python3 -m http.server` from the export dir (single-thread needs no COOP/COEP), and also via the CrazyGames QA tool when available.
- Ads mock: the CrazyGames SDK v3 mock with switchable states `available | unavailable | error | timeout`. **Needed from Build:** a URL flag or debug menu for this (e.g. `?ads=unavailable`), plus a readable **SDK call log** (console lines or `window.__adsLog`). Without them, P3 tests are blocked.
- A fresh Chrome profile per run (or clear site data first). uBlock Origin installed in a second profile.
- Puzzle export hook, **needed from Build/Dev:** a headless script that dumps seeded 4x4/6x6 puzzles to JSONL for `qa/sudoku_check.py` (see header of that file).

---
## P1: Boot in a real browser
| ID | AC | Steps | Expected | Evidence |
|---|---|---|---|---|
| BOOT-01 | 4 | Fresh Chrome profile, open build URL, DevTools Console open (Preserve log, Verbose). Wait until title, then tap Play. | Gets past splash and title into the Harbour/path within 15 s. **0 console errors** (warnings are listed but don't fail). | Screenshot of title + of Harbour; console `.log` |
| BOOT-02 | 4 | Same as BOOT-01 in Firefox ESR (`/usr/bin/firefox`, fresh profile). | Same. | Screenshot; console log |
| BOOT-03 | 4 | In the console run `typeof SharedArrayBuffer`, `crossOriginIsolated`; check the Network response headers for `index.html`; inspect the export (`index.html` config / `.js` name) for the threads flag. | The build boots with `crossOriginIsolated === false` and no COOP/COEP headers, i.e. it doesn't depend on SAB. The export config shows threads off. | Console output; screenshot of Network headers |
| BOOT-04 | 4 | Serve without any special headers (plain `http.server`) and through CrazyGames QA tool iframe. | Boots in both. | Screenshots; console logs |
| BOOT-06 | 4 | Console error triage rule (applies to BOOT-01..05 and AD-03/04): classify each error by source URL / stack. | **Ignored:** errors from the CrazyGames ad SDK and from requests blocked by an adblocker (`net::ERR_BLOCKED_BY_CLIENT`). **Every other error counts** as a FAIL. | Console log annotated with the classification |
| BOOT-05 | 4 | Network tab: reload with cache disabled. | No 404s for `.wasm/.pck/.js`; `.wasm` served as `application/wasm`. | HAR file / screenshot |

## P2: Grid validity, uniqueness, generation
| ID | AC | Steps | Expected | Evidence |
|---|---|---|---|---|
| GRID-01 | 1 | `godot --headless -s addons/gut/gut_cmdln.gd -gexit` in the project. | 0 failures, at least 30 tests, includes whole-pack and 100-seed tests. | GUT stdout `.txt` |
| GRID-02 | 2 | Convert each `data/packs/9x9_t{1..4}.json` to JSONL; run `python3 qa/sudoku_check.py`. | 1200/1200 have exactly 1 solution (count with cap 2), the stored solution matches, and the independent grader tier equals the stored tier. Exit code 0. | Script output |
| GRID-03 | 2 | Dump 100 seeded 4x4 and 100 seeded 6x6 per requested tier via the export hook; run the checker. | 100/100 unique per size; graded tier = requested tier. | Script output |
| GRID-04 | 2 | Generate the same seed twice (headless, and in-browser if a debug hook exists). | Identical givens and solution. | Script output (diff) |
| GRID-05 | 2 | Cross-check: compare the pack `steps[]` with the checker's step sequence for 20 random pack puzzles. | Techniques named match the tier claimed; no step uses a technique above the tier. | Script output |
| GRID-06 | 3 | In Chrome, play a full 9x9 path grid and the Classic 9x9 while logging (SDK/debug log, or a Performance profile filtered for `generate`). | 0 runtime calls to generate/grade 9x9. | Console log; profile screenshot |
| GRID-07 | 3 | Debug hook: generate 4x4 and 6x6 100 times each in Chrome; read timings. | p95 at most 30 ms each. If the fallback pack is used instead, the log says so (this still passes, but record it). | Console log with timings |
| GRID-08 | 3 | Performance panel recording across opening 10 grids (4x4/6x6/9x9). | No frame/long task over 50 ms. | Performance trace + screenshot |
| GRID-09 | n/a (§2) | Open one 4x4, 6x6 and 9x9 grid. | Box layouts are 2x2, 2x3 and 3x3. | Screenshots |

## P3: Mistakes, second chance, ads, rewards
| ID | AC | Steps | Expected | Evidence |
|---|---|---|---|---|
| SC-01 | 9 | 6x6 grid, enter 3 wrong digits. | After the 3rd mistake, the grid pauses and the Second chance panel opens (not before the 3rd). | Screenshots after mistakes 2 and 3 |
| SC-02 | 9 | 4x4 grid, enter 5+ wrong digits. | No panel; no limit. | Screenshot |
| SC-03 | 9 | Coins at or above 50, ads available. Trigger the panel. | Shows Continue (50 coins), Continue (ad), Retry. | Screenshot |
| SC-04 | 9 | Choose Continue for 50 coins. | Coins drop by exactly 50; mistakes clear; play resumes on the same board. | Before/after screenshots of the coin counter |
| SC-05 | 9 | Choose Continue (ad) with the mock set to succeed. | Mistakes clear; coins unchanged; SDK log shows exactly 1 rewarded call, made from the panel. | Screenshot; SDK log |
| SC-06 | 9 | After SC-04 or SC-05, make 3 more mistakes on the same grid. | The grid ends; only Retry is shown (1 per attempt). | Screenshot |
| SC-06b | 9 | Continue (coins or ad) after 3 mistakes, with notes and 10+ undo steps on the board. | The mistake counter is 0; wrong digits are removed; the other digits, notes and undo history are kept (undo never brings a wrong digit back). | State dumps before/after; screenshot |
| SC-07 | 15 | Too few coins: set coins to 49 (via play or by editing the save), ads available. Trigger Second chance. | Continue (50) is shown **disabled** with its price and "Need 1 more coins"; not hidden; layout identical to the affordable case; the ad and Retry are still offered; coins never go negative. | Screenshots at 49 and at 50 coins (layout diff) |
| SC-07b | 15 | Hint panel at 0 tokens and 29 coins. | The 30-coin buy is disabled with "Need 1 more coins". | Screenshot |
| SC-08 | 8,15 | Coins at 49 **and** ads unavailable. | Disabled Continue (50) with "Need 1 more coins" and Retry; no rewarded button. | Screenshot |
| SC-09 | 9 | Use 3 second chances within 24 h across path, Quick 6x6 and Classic 9x9 (mix coins + ad). Trigger a 4th. | Only Retry is shown. All modes count. | Screenshots; save dump showing 3 Unix-ms timestamps |
| SC-10 | 9,12 | After SC-09, reload the page and trigger again. | Still capped (the timestamps persist). | Screenshot; localStorage dump |
| SC-11 | 9 | Rolling reset: edit the save so the oldest of 3 timestamps is 24 h + 1 min old (others newer), or move the clock forward with `faketime`. Trigger again. | Exactly 1 more second chance is allowed; it's capped again after that. When all 3 have aged out, 3 are available. At 23 h 59 min it stays capped. | Before/after save dumps; screenshots |
| SC-12 | 15 | Hit the cap, then set the device clock **back** 2 days (`faketime` / OS clock); reload; trigger. | Still capped (only Retry). **Decided rule (N1, strict):** capped until the clock passes the *newest saved timestamp + 24 h*. Then set the clock to newest + 23 h 59 m: still capped; newest + 24 h 1 m: uncapped. | Screenshot; save dump |
| SC-12b | 15 | Put a timestamp 1 h in the future into the save; reload. | It is clamped to now (save dump shows <= now); no crash. The clamp must never shorten the cap below newest + 24 h (N1). | Save dump before/after |
| SC-13 | 9 | Use a second chance, spend a token, then Retry. | The puzzle restarts from its givens; digits, notes, undo and mistakes are cleared; the per-attempt second chance is available again (if under the 24 h cap); spent tokens and coins stay spent. | State dump; counter screenshots |
| AD-01 | 8 | Mock set to `unavailable`; visit the live grid, Hint panel (0 tokens), Second chance panel and results screen. | **No rewarded button anywhere** (hidden, not greyed out). Tokens/coins options remain. | Screenshots of each screen |
| AD-02 | 8 | Mock set to `error`, then `timeout` (no response). Open the Hint and Second chance panels; finish a grid. | `Ads.available()` is false, so rewarded buttons are hidden. If an ad starts and then fails or exceeds 8 s, the game continues within 8 s +/- 1, grants nothing, and the button stays retryable. | Screenshots; console log with timestamps |
| AD-03 | 8 | Remove or block the SDK script (DevTools Network request blocking on the SDK URL; and the offline checkbox). | Boots, no uncaught errors, rewarded buttons hidden, game playable. | Console log; screenshots |
| AD-04 | 8 | Chrome profile with **uBlock Origin** (default lists), run in the CrazyGames QA environment if possible. Play grid 1 to results, use a hint with coins, and use a second chance with coins. | No hang or spinner while waiting on ads (each transition under 9 s); no rewarded buttons; everything works through coins/tokens. Console: only ad-SDK and blocked-request errors are allowed (BOOT-06 rule). | Screen recording / screenshots; console log |
| ~~AD-05~~ SUPERSEDED (LO-11c) | 8,11 | Ads off (mock unavailable): complete the full 15-grid path (debug skip allowed only for solving, not for flow). | Path completes; all tasks can be bought; Area restored. | Screenshots; save dump |
| AD-06 | 10 | Mock on with logging. Open a grid, play, use the Hint panel, trigger Second chance; record the SDK log for the whole time the grid is open. | 0 interstitial/midgame/banner or other unrequested calls. Each rewarded call has a matching player tap in the Hint or Second chance panel. | SDK log + tap log |
| AD-07 | 10 | Fresh session: complete grids quickly (mix path/Quick); fail one, abandon one, retry one; keep going past 5 minutes. On each results screen, record the counter (debug), elapsed time and offer. | Never both. A midgame appears only when counter >= 3 **and** the session is >= 5 min **and** ads are available; the counter then resets to 0. Fails, abandons and retries don't count. Otherwise the rewarded double-coins offer is shown (if ads are available). | Table of grid number, time, counter, offer; SDK log |
| AD-07b | 10 | Reach counter 2, reload the page, complete 1 grid. | The counter starts again from 0 after the reload (not saved), so no midgame. | SDK log |
| AD-08 | 10 | Accept the double-coins offer (mock success); then repeat with mock failure. | Success: coins credited x2 exactly once. Failure: no grant, retryable. | Coin before/after screenshots |
| RW-01 | n/a (§3) | Complete 4x4, 6x6 and 9x9 grids. | Coins +10/+20/+40; +1 token per completed path grid. | Counter screenshots |
| RW-04 | 15 (N5) | Hint panel at exactly 10 tokens with ads available; then 9 tokens. | At 10: the "watch ad for token" button is **hidden** (not disabled). At 9: it is shown. | Screenshots at 10 and 9 |
| RW-03 | n/a (§3) | At 10 tokens, complete a path grid and watch a token ad. At 9, watch an ad. | Never more than 10 (grants at the cap are lost); 9 becomes 10. A 30-coin hint never changes the token count. | Counter screenshots |
| RW-02 | 6 | Press Hint with 0 tokens: pay 30 coins; then watch the ad (mock). | 30 coins deducted, or 1 token credited; hint delivered; no double grant. | Screenshots |

## P4: Notes, undo, hints, input
| ID | AC | Steps | Expected | Evidence |
|---|---|---|---|---|
| IN-01 | 5 | Mouse: cell then digit; digit then several cells. | Digits placed correctly in both modes. | Screenshots |
| IN-02 | 5 | Touch: Chrome DevTools device emulation (touch), plus a real Android/iOS if available. Repeat IN-01. | Same; no double input; no zoom or scroll hijack. | Screenshots |
| IN-03 | 5 | Keyboard: arrows to move, digits, Backspace, N toggles notes. | All work; focus stays on canvas. | Screen recording |
| IN-04 | 5 | Notes on: add notes; place a digit in a peer cell. | Matching notes clear in row, column and box only. | Before/after screenshots |
| IN-05 | 5 | Do a 20-action sequence mixing digits, notes, erase and auto-cleared notes; dump the grid state (debug) after each; then undo 20 times. | Each undo restores the **exact** previous state (digits, notes, auto-cleared notes), compared through the dump; undo is unlimited. | State dumps diff (script output) |
| IN-06 | 5 | Repeat IN-05 using touch and keyboard. | Same. | State dumps |
| HN-01 | 6 | Press Hint on 4x4/6x6/9x9 with tokens, coins and 0 tokens. | The panel always opens and the grid pauses and is dimmed first; no rewarded button on the live grid. | Screenshots |
| HN-02 | 7 | For 10 board states (fresh, and mid-solve after manual moves) per size, use Teach; export the board and the game's Teach step (debug hook H5) and run `qa/sudoku_check.py --step` on it. | The checker reports GAME_STEP valid=True: Teach is computed live on the current board and either places the correct digit or removes only non-solution candidates (N3). The technique name is consistent with the step type. | Screenshots + script output |
| HN-04 | 14 | 9x9 pack puzzle: solve in an order different from the stored `steps[]` (e.g. fill the last stored-step cells first), then Teach at 5 points. | `--step` gives GAME_STEP valid=True at every point (placement correct, or only non-solution candidates removed); it never references a filled cell or a stored step. `step()` takes <= 20 ms (debug timing). | Screenshots; board export + script output; timing log |
| HN-05 | 14 | 9x9 (and 6x6) with 1 wrong digit placed, then Teach. Then fix the digit and Teach again. | **N2:** Teach flags the wrong digit and stops (no technique shown). The checker on the exported state gives WRONG_DIGITS + flagged_correctly=True. After the fix, Teach teaches a valid live step. | Screenshots; `--step` output |
| HN-03 | n/a (§4) | Reveal with a selected cell; inspect the UI for any solve-all control. | Only the selected cell is filled; no solve-all button. | Screenshots |

## P5: Difficulty grading
| ID | AC | Steps | Expected | Evidence |
|---|---|---|---|---|
| GR-01 | 2 | Run `qa/sudoku_check.py` (independent technique grader) over all packs and the seeded sets. | The checker's tier equals the stored/requested tier on 100%; list mismatches. | Script output |
| GR-02 | 2 | Known-technique fixtures (naked single; hidden single; naked/hidden pair and pointing pair/triple = 3; naked/hidden triple, box-line, X-Wing = 4) through the game's `grade()` and the checker. | Both give the expected tier. | Script output |
| GR-03 | 2 | Check that the clue count doesn't correlate with the tier in the game's grader (e.g. a low-clue tier-1 puzzle is graded 1). | The tier depends only on technique. | Script output |

## P6: Persistence and village restore
| ID | AC | Steps | Expected | Evidence |
|---|---|---|---|---|
| PS-01 | 12 | Mid-path: note path progress, stars, coins, tokens, decor choices, second-chance timestamps, and a grid in progress (digits, notes, mistakes). Dump `localStorage`. Reload. | Everything is restored exactly; the dump is identical before and after. | Dumps diff; before/after screenshots |
| PS-02 | 12 | Same, but run outside the CrazyGames portal (localStorage fallback) and inside the QA tool (CrazyGames data). | Restored in both. | Dumps; screenshots |
| PS-03 | 12 | Corrupt or delete the save key; reload. | No crash; starts fresh or recovers. | Console log |
| PS-04 | 12 | Close the tab mid-grid right after a move; reopen. | That last move is present. | Screenshot |
| ~~MT-01~~ SUPERSEDED (LO-11) | 11 | Fresh save: complete all 15 path grids with a mistake (or Continue) + Reveal on every grid. | Exactly **20** stars; all 5 tasks (3+4+4+4+5 = 20) can be bought, leaving 0. | Star counter screenshots |
| ~~MT-01b~~ SUPERSEDED (LO-11b) | 11 | Fresh save: a perfect path (0 mistakes, no Reveal, no Continue). | Exactly **31** stars; after buying all tasks the 11 extra stars are **saved** (save dump shows 11, and still 11 after a reload). That's all that's tested (N4). | Screenshots; save dump |
| MT-01c | 11, LO-AC5 | (Still valid under Level Objectives v1: "path grid" now means "path level".) Replay a completed path grid perfectly; play Quick/Classic. | No extra stars (first completion only); Quick/Classic give coins only. | Counter screenshots |
| MT-02 | 11 | Buy each task in turn. | The Harbour visual changes after each of the 5 buys; Area restored appears after the 5th. | 6 screenshots |
| MT-03 | 11,12 | Change decor for a bought task; reload. | The change is free (no star cost) and persists. | Screenshots |
| ~~MT-04~~ SUPERSEDED (LO-13) | n/a (§7) | Path composition: grids 1-4, 5-10, 11-15. | Sizes/tiers as specified. | Screenshot per grid / log |
| UI-01 | 13 | Window at 1280x720 (DevTools device toolbar, DPR 1). Screenshot 4x4/6x6/9x9; measure in an image tool. | Cells are at least 44 px; digit glyph height is at least 60% of cell height. | Annotated screenshots |
| UI-02 | n/a (§2) | Select a cell. | Row, column, box and matching digits are highlighted. | Screenshot |

**Test count: 70** (P1 6, P2 9, P3 29, P4 11, P5 3, P6 12). Of these, 4 are superseded by Level Objectives v1 (MT-01, MT-01b, MT-04, AD-05), so 66 are active. P7 adds 23, for **89 active**.

## P7: Level Objectives v1 (LEVEL_OBJECTIVES_SPEC.md v1.2, sections 8-9)
This section replaces the v3.1 path and stars (15 grids, 20/31 stars) with 20 levels on 12 grids at 1-3 stars each (20 min / 60 max). The 5 retuned tasks (3, 4, 4, 4, 5) cost 20. The AC column uses the LO criterion number. Any open question in LQ-* that affects a test blocks a binary verdict until it's answered.

| ID | AC | Steps | Expected | Evidence |
|---|---|---|---|---|
| LO-01 | LO 1 | Run `godot --headless --script tools/build_levels.gd` on a clean checkout. Back up the existing `data/levels/harbour.json`, regenerate, then diff. Then run the independent checker (`qa/sudoku_check.py --levels`, to be added) over each level: logical solve from the givens, stopping when the last T cell is filled, and recompute the tier and `steps_to_t`. | Exit 0; exactly 20 levels; for every level the logical solve fills all of T; stored `tier` and `steps_to_t` equal both a fresh tool run and the checker; `par_time_s` = round((base + 6 × steps_to_t) × par_mult) on L8/L10/L15 and null on the other 17. Each grid still has exactly 1 solution. | Tool stdout; JSON diff (empty); checker output table for L1-L20 |
| LO-02 | LO 2 | Run the GUT T-set tests headless. Independently, for each level in `harbour.json`, recompute T in the checker from the grid and params. | GUT 0 failures. Digit Hunt T = exactly the empty cells whose solution is `digit`. Fill the Line T = exactly the empty cells of the listed units (union, no duplicates). Lantern Path (LQ-5): the drawn path is 6-10 orthogonally connected cells (givens included) with at least 4 empty, and **T = only the empty path cells** (no givens in `target`). Beat the Tide: T equals the inner objective's T. The checker matches the stored `target` on 20/20. | GUT log; checker output |
| LO-03 | LO 3 | Debug build, L2 (Fill row 0) and L1 (Digit Hunt 1). Fill every T cell but one correctly, leaving some non-T cells empty. Dump state (H5). Enter the last T cell correctly. Repeat on L5 (Lantern) and L8 (Tide). | Before the last T cell: no completion (no results screen, timer still running on L8). On the correct last T digit: completion fires (results screen in under 1 s) with non-T cells still empty. A wrong digit in the last T cell does not complete. | Screen recording; H5 dumps before/after |
| LO-03b | LO 3 (LQ-8) | Fresh attempt on L1 (0 mistakes) and L8 (timer readout). Fill every T cell but one, then use Reveal on the last T cell. | The Reveal completes the level immediately. Stars treat it as 1 Reveal: L1 = 2 stars. L8: final elapsed_ms = pre-Reveal elapsed + 15000 (±500), and the stars use that value against par. | Readout before/after; results screens; H5 dump (reveals=1) |
| LO-04 | LO 4 | L11 (Digit Hunt 5, 9x9). Enter a wrong digit in a non-T cell 3 times (in different cells). | Each counts as a mistake (counter 1, 2, 3; red digit). The 3rd opens the Second chance panel with the v3.1 options. | Screenshots per mistake; H5 dump with mistakes=3 |
| LO-05 | LO 5 (LQ-3) | Fresh save. On untimed levels, run 5 cases: (a) 0 mistakes, no Reveal; (b) 1 mistake, no Reveal; (c) 3 mistakes + Continue, no Reveal; (d) 0 mistakes, 1 Reveal; (e) 1 mistake + 1 Reveal. Use L1-L5 for one case each (first completion). Then on L6: make 2 mistakes + 1 Reveal, press Retry, and finish the new attempt perfectly. | Stars: (a) 3, (b) 2, (c) 2, (d) 2, (e) 1. Never below 1. L6 after Retry: **3** (only the completing attempt counts; mistakes, Reveals and Continues reset). Saved best stars match. | Results screen screenshots; save dump; H5 after Retry (mistakes=0, reveals=0, continues=0) |
| LO-06 | LO 6 (LQ-1, LQ-2) | Debug build with `?clock=`/H7 readout. On L8 (par P from JSON; thresholds A = floor(0.75 × P × 1000) ms and B = P × 1000 ms), finish at (a) elapsed_ms well under A, (b) between A and B, (c) > B. For (c), let the bar reach 0 and wait 30 s more before finishing. In (a) also make 1 mistake + 1 Continue. | Stars: (a) 3 (mistakes/Continue don't count), (b) 2, (c) 1. At 0 the bar turns calm grey, the level stays playable, no fail or panel appears. | Timer readout at finish; results screens; recording of reaching 0 |
| LO-06b | LO 6 (LQ-1) | Boundary, with the clock hook pinning elapsed_ms at the final input (H7). On L8 finish at: (a) exactly A; (b) A+1 ms; (c) exactly B; (d) B+1 ms. Also unit-test the star function (GUT or checker) with the same 4 values for L8, L10, L15. | (a) 3, (b) 2, (c) 2, (d) 1. Comparison is ≤ at ms resolution, A uses floor. Unit results agree for all 3 levels. | H7 readout; results screens; unit log |
| LO-06c | LO 6 (LQ-2) | L10, H7 readout. Attempt 1: play to elapsed_ms = B − 20000 (and > A + 20000), use 1 Reveal, finish within 4 s. Attempt 2 (Retry): play to B − 20000, use 2 Reveals, finish within 4 s. | Each Reveal adds exactly 15000 ms to the elapsed_ms shown on the bar. Attempt 1 ends at ≤ B − 1000 → **2** stars. Attempt 2 ends at > B + 10000 → **1** star. Stars always equal the star function applied to the bar's final elapsed_ms. | Readout before/after each Reveal; results screens |
| LO-07 | LO 7 (LQ-2, LQ-6) | L10 with H7 readout. Note elapsed; open each of the Hint, Second chance and Pause panels for 20 s each and close. Hide the tab for 20 s (switch tab) and return. Then use 1 Reveal, then 2 more, and 1 Teach. | Elapsed doesn't change while any panel is open or the tab is hidden (±500 ms for the open/close frame). Each Reveal adds exactly 15000 ms (3 Reveals = +45000 ms). Teach adds 0. | Readout before/after each step; H5/timer log |
| LO-07b | LO 7 (LQ-6) | `?ads=available`, L10, H7 readout. Open Second chance (or Hint), press the rewarded button, let the mock ad play ≥15 s, finish it, close the panel. | elapsed_ms is unchanged across the whole ad + panel (±500 ms). | Readout before/after; `__adsLog` timestamps |
| LO-07c | LO 7 (LQ-6) | L10, H7 readout. Keep the tab visible but move focus to another window (click a second window / address bar) for 20 s, then refocus. | elapsed_ms doesn't advance during blur (±500 ms); resumes on focus. | Readout before/after |
| LO-08 | LO 8 (LQ-3) | L15. Play to elapsed ≈ 60 s with 1 Reveal, make 3 mistakes, take Continue (coins), check elapsed; finish under A. Then on another attempt, after mistakes + Reveal, choose Retry. | Continue: elapsed equals the pre-panel value (panel time not added); finishing under A still gives 3 stars (Continue doesn't change Tide stars). Retry: elapsed_ms = 0, mistakes/Reveals/Continues = 0, board back to givens. | Readout screenshots; H5 dumps |
| LO-09 | LO 9 | `?ads=available`, H2 log cleared. Play L1 to completion opening Hint and Second chance panels without pressing any rewarded button; then press one rewarded button from a panel. Repeat on a Tide level (L8). | `window.__adsLog` shows 0 entries between level open and results, other than the one rewarded call started from the panel. No midgame inside a level. | `__adsLog` dump with timestamps |
| LO-10 | LO 10 (LQ-4) | Debug build. On L11 (Digit Hunt 5), L14 (row+col) and L12 (Lantern), at 3 partial states each, press Teach and dump the step (H5). Run the checker `--step --target`: it lists every valid step and marks it T-touching **only** if it places a digit in a T cell or removes ≥1 candidate from a T cell. | Whenever the checker finds ≥1 T-touching step, the game's step is one of them (any is OK) and valid under N3. A step that only changes non-T cells counts as not touching, even if it helps indirectly. If none exists, any valid step passes. 9/9 pass. | H5 dumps; checker output |
| LO-11 | LO 11 (LQ-9) | Fresh save, ads off. Play all 20 levels: ≥1 mistake (1-2, no second chance needed) and ≥1 Reveal on every untimed level, and over par on L8/L10/L15. If the 3rd mistake happens, use Retry (or SD_DEBUG.resetSecondChanceCap). | Exactly **20** stars. The 24 h second-chance cap never blocks the run. All 5 tasks (3+4+4+4+5 = 20) can be bought in order, leaving 0. Harbour restored. | Star counter after each level; screenshots of each buy |
| LO-11b | LO 11 | Fresh save: perfect run (0 mistakes, no Reveal, no Continue, all Tide levels under 0.75 × par). Buy all tasks; reload. | Exactly **60** stars; after buying, 40 left over, saved (save dump 40, still 40 after reload). | Screenshots; save dumps |
| LO-11c | LO 11 (+v3.1 AC 8) | `?ads=unavailable` throughout LO-11. | The path completes with no rewarded buttons shown and no ads; all tasks bought. | Screenshots; `__adsLog` |
| LO-12 | LO 12 (LQ-7) | Mid-path: complete L1-L4 with differing stars, replay L2 with a better result, then leave L8 mid-level (some digits, notes, 1 mistake, 1 Reveal used); note H7 elapsed_ms right after the last input. Dump the save; close for ≥30 s; reload; dump again. | Completed set, best stars, and in-progress L8 (digits, notes, mistakes, Reveal count) restored exactly; dumps identical. Restored elapsed_ms within **±1000 ms** of the saved value (not 0, not advanced by the closed time). | Save dump diff; readouts before/after |
| LO-12b | LO 12 | Replay L3 worse after a 3-star run; reload. | Best stars stay 3; no extra path stars counted. | Save dump |
| LO-13 | LO 13 | Read the in-game level list and open each of L1-L20 (debug skip allowed). Compare each with section 5 (grid, size, objective, params, tier) and with `harbour.json`. Also check the mix rules. | 20/20 match the table: 6 Full Solve, 4 Digit Hunt, 4 Fill the Line, 3 Lantern, 3 Tide (inner Line on L8/L15, Full on L10). At least 1 full-board solve in every 4 consecutive levels; no 2 Tide levels in a row. | Screenshot per level; comparison table |
| LO-13b | LO 13 | Open the same level on two fresh profiles (Chrome incognito ×2) for L1, L4, L20. | Identical givens (pregenerated). | Screenshots; H5 givens diff |
| LO-14 | LO 1 (Teach §1) / LO 2 | Lantern visuals and Digit Hunt counter on L5 and L1: solve T cells one by one. | Lanterns light per solved T cell; counter goes e.g. 0/4 → 4/4. (UI check, not an AC; supports LO-03.) | Screenshots |

**P7 count: 23** (LQ-1..9 resolved in v1.2; added LO-03b, LO-06b, LO-06c, LO-07b, LO-07c).

### Level Objectives: open questions (block a binary verdict until answered)
| Q | Affects | Question |
|---|---|---|
| LQ-1 | LO-06 | ~~"Under par" / "under 0.75x par": strictly less than, or ≤? What resolution is the comparison done in (ms, s, rounded)? Finishing exactly at par must have one defined result.~~ **Resolved (v1.2 §9.1): "elapsed_ms ≤ par_time_s × 1000, at ms resolution; 0.75x is elapsed_ms ≤ floor(0.75 × par_time_s × 1000)." → LO-06b** |
| LQ-2 | LO-06, LO-07 | ~~Does a Reveal's +15 s add to elapsed (counts against par) for the star thresholds? Spec says "adds 15 s" but not to what.~~ **Resolved (§9.2): "each Reveal adds 15,000 ms to elapsed_ms, which is the value compared against par and shown on the bar." → LO-06c, LO-07** |
| LQ-3 | LO-05, LO-08 | ~~After Retry, do mistakes/Reveals from the earlier attempt still count against stars, or does each attempt start clean? And does Continue on a Tide level affect anything (spec says mistakes don't)?~~ **Resolved (§9.3): "Retry starts a clean attempt: mistakes, Reveals, Continues, and the timer all reset… Continue doesn't change Beat the Tide stars; elapsed time is kept." → LO-05, LO-08** |
| LQ-4 | LO-10 | ~~Define "touches T": the step's placed cell is in T, or at least one eliminated candidate is in a T cell. Is an elimination that only affects cells that later determine T (indirectly) counted? Also, if several T-touching steps exist, is any of them OK? Without this, the checker can't be binary.~~ **Resolved (§9.4): "places a digit in a T cell, or removes at least one candidate from a T cell. Steps that only affect cells outside T don't count." → LO-10** |
| LQ-5 | LO-02 | ~~Lantern Path T: is T all 6-10 path cells (givens included, already correct) or only its empty cells? Spec §2 says 6-10 cells but §1 defines T as cells to fill. Affects how the checker compares `target`.~~ **Resolved (§9.5): "T is the empty cells only." → LO-02** |
| LQ-6 | LO-07 | ~~Does the Second chance panel's ad (rewarded) playtime count as "panel open" (paused)? And is window blur (not hidden) a pause condition? Spec only says hidden tab.~~ **Resolved (§9.6): "pauses while any panel is open, which includes a rewarded ad… when the tab is hidden… and when the window loses focus." → LO-07, LO-07b, LO-07c** |
| LQ-7 | LO-12 | ~~What tolerance for "timer elapsed restored exactly" (save interval)? If elapsed is saved every N s, a reload can lose up to N s. Need N or "exact to the last move".~~ **Resolved (§9.7): "restored elapsed_ms is within ±1,000 ms… Saves happen on every input and at least every 5 s." → LO-12** |
| LQ-8 | LO-03 | ~~A wrong digit typed into the last T cell: no completion is assumed. A correct digit placed by Reveal into the last T cell: does it complete (and count as Reveal for stars)? Assumed yes.~~ **Resolved (§9.8): "Reveal on the last target cell completes the level, and it counts as a Reveal (and adds +15 s)." → LO-03b** |
| LQ-9 | LO-11 | ~~Does a level completed via 3 mistakes + Continue on every level reach the min, and is it legal to skip Reveal for Tide levels? (Min run is defined here as over par for Tide; confirm.) Also, can the 2nd-chance 24 h cap (3 per 24 h) block a min-stars run? If so the "worst" run needs only mistakes 1-2 rather than Continue.~~ **Resolved (§9.9): "the 20-star run never needs a second chance, because Retry is always available… 1-star minimum comes from finishing over par." → LO-11** |
| LQ-10 | LO-01 | Tooling: QA needs `harbour.json` + grids and a headless entry point; `qa/sudoku_check.py` needs a `--levels` and `--target` mode (QA will add). Need an H5 field for T, objective and timer elapsed, and a timer readout hook (proposed H7). **Open: pending Build (H7).** |

---
## Debug hooks (Build commits to these; O1 decision)
| Hook | What | Used by |
|---|---|---|
| H1 | Ads mock switch: `?ads=available\|unavailable\|error\|timeout` | AD-01..08, SC-03..08, RW-02, RW-04 |
| H2 | SDK call log (`window.__adsLog` + console lines: type, source panel, timestamp) | AD-05..08, SC-05, GRID-06 |
| H3 | Midgame counter + session age readout | AD-07, AD-07b |
| H4 | Timing log for 4x4/6x6 `generate()` and `step()`; log of any 9x9 generate/grade call | GRID-06..08, HN-04 |
| H5 | Board/state dump as JSON: givens, current grid, notes, mistakes, undo stack, and the last Teach step as `{"cell","value"}`, `{"eliminations"}` or `{"flag"}` (format of `qa/sudoku_check.py --step`) | IN-05/06, SC-06b, SC-13, HN-02, HN-04, HN-05 |
| H7 (proposed) | Level timer readout + H5 extension: `level`, `objective`, `target`, `elapsed_ms`, `reveals`, `continues` | LO-03..12 |
| H6 | Headless seed-dump CLI writing JSONL (`size, tier, seed, givens, solution`) | GRID-03/04, GR-01 |

## Traceability (all 15 AC, spec v3 + Studio Manager decisions)
| AC | Summary | Tests | Testable? |
|---|---|---|---|
| 1 | GUT headless, 0 fail | GRID-01 | Yes (needs project source) |
| 2 | Packs unique and tier match; 100 seeded 4x4/6x6 unique | GRID-02..05, GR-01..03 | Yes (H6) |
| 3 | No runtime 9x9 gen; p95 <= 30 ms; no frame over 50 ms | GRID-06..08 | Yes (H2, H4) |
| 4 | Boots Chrome + Firefox ESR, 0 counted errors, single-thread | BOOT-01..06 | Yes |
| 5 | Digits/notes/undo, all input, exact undo | IN-01..06 | Yes (H5) |
| 6 | Hint opens panel and pauses, no rewarded on grid | HN-01, RW-02 | Yes |
| 7 | Teach matches a valid live step for the board state | HN-02 | Yes (H5 + checker) |
| 8 | Ads off: playable, no rewarded buttons, path completes | AD-01..04, SC-08 (AD-05 superseded by LO-11c) | Yes (H1) |
| 9 | 3rd mistake, 1 per attempt, 3 per rolling 24 h | SC-01..06b, SC-09..11, SC-13 | Yes |
| 10 | No unrequested ad calls in grid; never both; midgame rule | AD-06..08, AD-07b | Yes (H2, H3) |
| 11 | **Star totals superseded by LO AC 11 (20 / 60).** Tasks visuals, Area restored, decor | MT-02, MT-03, MT-01c (MT-01, MT-01b, MT-04, AD-05 superseded) | Yes |
| 12 | Reload restores everything incl. cap | PS-01..04, SC-10, MT-03 | Yes |
| 13 | Readability at 1280x720 | UI-01 | Yes (DPR 1) |
| 14 | Live Teach valid on a diverged 9x9; wrong digit flagged first | HN-04, HN-05 | Yes (H5 + checker) |
| 15 | Clock rollback keeps the cap (strict); disabled coin options; ad-for-token hidden at 10 | SC-07, SC-07b, SC-08, SC-12, SC-12b, RW-04 | Yes |

No v3 criterion is ambiguous or untestable now, provided hooks H1-H6 ship.

### Traceability: Level Objectives v1 (13 AC)
| LO AC | Summary | Tests | Testable? |
|---|---|---|---|
| LO 1 | build_levels headless, 20 levels, T solvable, tier/steps match | LO-01 | Yes (needs source + checker `--levels`; LQ-10) |
| LO 2 | GUT T sets per type | LO-02 | Yes (LQ-5) |
| LO 3 | Completes on last correct T cell, not earlier | LO-03, LO-03b, LO-14 | Yes |
| LO 4 | Wrong non-T digit is a mistake; 3rd opens Second chance | LO-04 | Yes |
| LO 5 | Non-timed stars 3/−1/−1, floor 1 | LO-05, MT-01c | Yes (LQ-3) |
| LO 6 | Tide stars by par; 0 never ends | LO-06, LO-06b, LO-06c | Yes (H7; LQ-1/2 resolved) |
| LO 7 | Timer paused on panels/hidden; Reveal +15 s | LO-07, LO-07b, LO-07c | Yes (H7) |
| LO 8 | Retry resets, Continue keeps | LO-08 | Yes (H7) |
| LO 9 | 0 ad calls in level except player-started rewarded | LO-09 | Yes (H1, H2) |
| LO 10 | Teach prefers T-touching step | LO-10 | Yes (LQ-4 resolved) |
| LO 11 | Min 20 / max 60 stars; 20 buys all tasks | LO-11, LO-11b, LO-11c | Yes (LQ-9) |
| LO 12 | Reload restores completion, best stars, in-progress level + elapsed | LO-12, LO-12b | Yes (LQ-7) |
| LO 13 | Path order/objectives match §5 | LO-13, LO-13b | Yes |

## Gap status: all resolved
| Gap | Status | Decision |
|---|---|---|
| G1-G5, G7-G9, G11 | Resolved | Spec v3 (see the v3 notes in each test) |
| O1 (G6) Debug hooks | **Resolved** | Build implements H1-H6 above |
| O2 (G10) Firefox / console noise | **Resolved** | Firefox ESR at `/usr/bin/firefox`; ignore ad-SDK errors and adblocker-blocked requests; everything else counts (BOOT-06) |
| N1 Clock-tamper conflict | **Resolved** | Strict: capped until newest timestamp + 24 h (SC-12, SC-12b) |
| N2 Teach with wrong digit | **Resolved** | Always live; flag the wrong digit and stop; teach after it's fixed (HN-05) |
| N3 Valid elimination step | **Resolved** | Correct placement, or removes only non-solution candidates; checker validates both (HN-02, HN-04) |
| N4 Star carry-over | **Resolved** | Only test that the extra stars are saved (now LO-11b: 40 leftover) |
| N5 Ad-for-token at 10 | **Resolved** | Hidden at 10 tokens (RW-04) |

## Tooling
- `qa/sudoku_check.py`
  - Puzzle mode (JSONL): uniqueness (cap 2) + technique tier 1-4 (5 = beyond); exit 0 when everything passes.
  - `--step board.json`: checks for wrong digits (expects `{"flag":...}`), prints the reference next step (placement or eliminations), and validates the game's Teach step under the N3 rule. Exit 0 = valid.
- `qa/selftest.sh` + `qa/fixtures/`: 8 regression cases (valid/invalid placement, valid/invalid elimination, wrong-digit flag/no flag, a non-unique puzzle). They all pass.
