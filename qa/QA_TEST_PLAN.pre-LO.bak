# Sudoku Dash: QA Test Plan (Vertical Slice, spec v3)
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
| AD-05 | 8,11 | Ads off (mock unavailable): complete the full 15-grid path (debug skip allowed only for solving, not for flow). | Path completes; all tasks can be bought; Area restored. | Screenshots; save dump |
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
| MT-01 | 11 | Fresh save: complete all 15 path grids with a mistake (or Continue) + Reveal on every grid. | Exactly **20** stars; all 5 tasks (3+4+4+4+5 = 20) can be bought, leaving 0. | Star counter screenshots |
| MT-01b | 11 | Fresh save: a perfect path (0 mistakes, no Reveal, no Continue). | Exactly **31** stars; after buying all tasks the 11 extra stars are **saved** (save dump shows 11, and still 11 after a reload). That's all that's tested (N4). | Screenshots; save dump |
| MT-01c | 11 | Replay a completed path grid perfectly; play Quick/Classic. | No extra stars (first completion only); Quick/Classic give coins only. | Counter screenshots |
| MT-02 | 11 | Buy each task in turn. | The Harbour visual changes after each of the 5 buys; Area restored appears after the 5th. | 6 screenshots |
| MT-03 | 11,12 | Change decor for a bought task; reload. | The change is free (no star cost) and persists. | Screenshots |
| MT-04 | n/a (§7) | Path composition: grids 1-4, 5-10, 11-15. | Sizes/tiers as specified. | Screenshot per grid / log |
| UI-01 | 13 | Window at 1280x720 (DevTools device toolbar, DPR 1). Screenshot 4x4/6x6/9x9; measure in an image tool. | Cells are at least 44 px; digit glyph height is at least 60% of cell height. | Annotated screenshots |
| UI-02 | n/a (§2) | Select a cell. | Row, column, box and matching digits are highlighted. | Screenshot |

**Test count: 70** (P1 6, P2 9, P3 29, P4 11, P5 3, P6 12).

---
## Debug hooks (Build commits to these; O1 decision)
| Hook | What | Used by |
|---|---|---|
| H1 | Ads mock switch: `?ads=available\|unavailable\|error\|timeout` | AD-01..08, SC-03..08, RW-02, RW-04 |
| H2 | SDK call log (`window.__adsLog` + console lines: type, source panel, timestamp) | AD-05..08, SC-05, GRID-06 |
| H3 | Midgame counter + session age readout | AD-07, AD-07b |
| H4 | Timing log for 4x4/6x6 `generate()` and `step()`; log of any 9x9 generate/grade call | GRID-06..08, HN-04 |
| H5 | Board/state dump as JSON: givens, current grid, notes, mistakes, undo stack, and the last Teach step as `{"cell","value"}`, `{"eliminations"}` or `{"flag"}` (format of `qa/sudoku_check.py --step`) | IN-05/06, SC-06b, SC-13, HN-02, HN-04, HN-05 |
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
| 8 | Ads off: playable, no rewarded buttons, path completes | AD-01..05, SC-08 | Yes (H1) |
| 9 | 3rd mistake, 1 per attempt, 3 per rolling 24 h | SC-01..06b, SC-09..11, SC-13 | Yes |
| 10 | No unrequested ad calls in grid; never both; midgame rule | AD-06..08, AD-07b | Yes (H2, H3) |
| 11 | Exactly 20 / 31 stars; tasks; visuals; Area restored; extra stars saved | MT-01..04, MT-01b/c, AD-05 | Yes |
| 12 | Reload restores everything incl. cap | PS-01..04, SC-10, MT-03 | Yes |
| 13 | Readability at 1280x720 | UI-01 | Yes (DPR 1) |
| 14 | Live Teach valid on a diverged 9x9; wrong digit flagged first | HN-04, HN-05 | Yes (H5 + checker) |
| 15 | Clock rollback keeps the cap (strict); disabled coin options; ad-for-token hidden at 10 | SC-07, SC-07b, SC-08, SC-12, SC-12b, RW-04 | Yes |

No criterion is ambiguous or untestable now, provided hooks H1-H6 ship.

## Gap status: all resolved
| Gap | Status | Decision |
|---|---|---|
| G1-G5, G7-G9, G11 | Resolved | Spec v3 (see the v3 notes in each test) |
| O1 (G6) Debug hooks | **Resolved** | Build implements H1-H6 above |
| O2 (G10) Firefox / console noise | **Resolved** | Firefox ESR at `/usr/bin/firefox`; ignore ad-SDK errors and adblocker-blocked requests; everything else counts (BOOT-06) |
| N1 Clock-tamper conflict | **Resolved** | Strict: capped until newest timestamp + 24 h (SC-12, SC-12b) |
| N2 Teach with wrong digit | **Resolved** | Always live; flag the wrong digit and stop; teach after it's fixed (HN-05) |
| N3 Valid elimination step | **Resolved** | Correct placement, or removes only non-solution candidates; checker validates both (HN-02, HN-04) |
| N4 Star carry-over | **Resolved** | Only test that the extra stars are saved (MT-01b) |
| N5 Ad-for-token at 10 | **Resolved** | Hidden at 10 tokens (RW-04) |

## Tooling
- `qa/sudoku_check.py`
  - Puzzle mode (JSONL): uniqueness (cap 2) + technique tier 1-4 (5 = beyond); exit 0 when everything passes.
  - `--step board.json`: checks for wrong digits (expects `{"flag":...}`), prints the reference next step (placement or eliminations), and validates the game's Teach step under the N3 rule. Exit 0 = valid.
- `qa/selftest.sh` + `qa/fixtures/`: 8 regression cases (valid/invalid placement, valid/invalid elimination, wrong-digit flag/no flag, a non-unique puzzle). They all pass.
