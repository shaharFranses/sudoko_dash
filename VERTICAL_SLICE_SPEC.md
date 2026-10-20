# Sudoku Dash: Vertical Slice Spec (v3.1: v3 plus SM clarifications)
Owner: SD Game Design. Engine: Godot 4.3, single-thread web export. Ships to CrazyGames first.

## 1. Sudoku module (engine-agnostic)
- Pure GDScript in `sudoku/` that uses no Node, SceneTree, or UI APIs. Inputs and outputs are plain arrays and dicts, so it ports 1:1 to Unity or C#.
- **Generator:** `generate(size, tier, seed) -> {givens, solution}` is deterministic per seed. Every puzzle has exactly one solution (solution counter capped at 2).
- **Solver:** `solve(grid) -> {solution, count}`. `step(grid) -> {technique, cells, eliminations, value}` returns the next human-style step.
- **Grader:** `grade(givens) -> {tier, steps[]}`. Tier is the hardest technique required: 1 is naked single, 2 hidden single, 3 naked or hidden pair and pointing pair or triple, 4 triples, box-line reduction, or X-Wing. `steps[]` is stored in packs for QA and grading only. Clue count is never used.
- **Where puzzles come from:**
  - 9x9 comes only from offline packs: `data/packs/9x9_t{1-4}.json` with 300 puzzles per tier, made with a headless Godot CLI script (`tools/build_packs.gd`). Each entry has givens, solution, tier, and steps. At runtime the game never generates or grades a 9x9.
  - 4x4 and 6x6 are generated at runtime, which must take 30 ms or less (p95). If that budget is missed, fall back to a bundled pack of 200 puzzles per size.
- **Tests:** GUT, run headless, at least 30 tests. They verify the whole pack (every puzzle unique, with the tier it claims) plus 100 seeded 4x4 and 6x6 puzzles.

## 2. Grids and input
- Supported sizes are 4x4 (2x2 boxes), 6x6 (2x3 boxes), and 9x9 (3x3 boxes).
- **Input:** tap a cell then a digit, or a digit then cells. Keyboard uses digits, arrow keys, Backspace, and N to toggle notes.
- **Notes:** a toggle. Placing a digit auto-clears matching notes in the same row, column, and box. Undo is unlimited per grid and covers digits and notes.
- **Readability:** digits at least 60% of cell height, cells at least 44 px at 1280x720, highlights for row, column, box, and matching digits.

## 3. Economy (minimal, slice only)
- **Coins:** 4x4 grid +10, 6x6 +20, 9x9 +40. The player starts with 100.
- **Hint tokens:** start with 3. Each completed path grid gives +1 free token, and ads give +1 per view. The cap is 10 total tokens from every source, and grants are lost when the player is at the cap. At 10 tokens, the "watch ad for token" button is hidden. Buying with coins spends 30 coins on one hint immediately, which never adds a token.
- **Coin options the player can't afford** are shown disabled with their price, plus the line "Need N more coins". They're never hidden, so the screen layout stays stable.

## 4. Hints (never placed on the live grid)
- The grid shows only a **Hint** button. It pauses the timer-free grid and opens the Hint panel, so the board is covered or dimmed.
- **Teach:** shows the next entry from the grader's step log, highlighting its cells and explaining the technique in one line, such as "Hidden single: 7 can only go here in this box." Every size, 9x9 included, calls `step()` live on the current board (givens plus player digits). If a wrong digit is present, Teach flags that digit and stops. A valid step either places the correct digit or removes only candidates that aren't in the solution. Stored steps are never shown, and `step()` on a 9x9 must take 20 ms or less.
- **Reveal:** fills the selected cell.
- **Paying:** a hint costs 1 token. With 0 tokens the player can pay 30 coins, and if ads are available they can instead watch an ad for 1 token.
- No button solves the whole grid.

## 5. Mistakes and second chance
- After 3 mistakes, the grid pauses and a Second chance panel opens. 4x4 grids have no limit.
- **Options:** Continue for 50 coins, Continue for free with an ad (only if ads are available), and Retry.
- **Continue:** the mistake counter resets to 0, wrong digits are removed, and the board, notes, and undo history (minus the wrong digits) are kept. The next 3 mistakes end the grid with only Retry available.
- **Retry:** restarts the same puzzle from its givens. Placed digits, notes, undo history, and mistakes are all cleared, and the grid's second-chance allowance is restored. Tokens and coins that were spent stay spent.
- **Cap:** 1 second chance per grid attempt, and no more than 3 in any rolling 24-hour window, counting coins and ads together. Path, Quick 6x6, and Classic 9x9 all count. Usage timestamps (Unix ms) are saved.
- **Clock tampering:** if the device clock is earlier than the newest saved timestamp, treat the window as still full, so the cap stays in place until the clock passes that timestamp plus 24 hours. Once capped, only Retry is shown.

## 6. Ads (an adapter over CrazyGames SDK v3, with a mock offline)
- `Ads.available()` returns false when Basic Launch has ads off, an adblocker is present, the SDK has an error, or the player is offline.
- **Never show a rewarded button that does nothing:** when ads aren't available, rewarded options are hidden, not greyed out, and coins or tokens always remain as a path.
- No interstitial or other unrequested ad while a grid is open. A rewarded ad started by the player from the Hint or Second chance panel is allowed. Rewarded buttons only appear in the Hint and Second chance pause panels and on the results screen.
- **Between grids:** each results screen gets either one midgame ad or one rewarded offer (double coins), never both.
- **Midgame counting:** a counter adds 1 for each grid completed in any mode. Retries, abandons, and failed grids don't count. When the counter is 3 or more, the session is at least 5 minutes old, and ads are available, show the midgame ad and reset the counter to 0. Otherwise offer the rewarded option if ads are available. The counter is per session and isn't saved.
- If an ad errors or times out after 8 s, the game continues as if no ad was offered, and a rewarded ad that fails grants nothing and stays retryable.

## 7. Meta: one seaside area ("Harbour")
- Path of 15 grids: grids 1-4 are 4x4 tier 1, 5-10 are 6x6 tier 1-2, 11-15 are 9x9 tier 2-3 (from the packs).
- **Stars:** 4x4 earns 1. 6x6 earns 1, +1 for 0 mistakes. 9x9 earns 2, +1 for 0 mistakes and no Reveal. A grid that used Continue counts as having mistakes. Across the path that's 20 at minimum (4+6+10) and 31 at maximum (4+12+15). Only a grid's first completion awards stars, and Quick and Classic award coins only.
- **5 tasks:** Fix dock (3 stars), Paint boats (4), Plant flowerbeds (4), Restore lighthouse (4), Café terrace (5), 20 stars in total, which equals the path minimum. Finishing the path always restores the Harbour (the generous choice), and extra stars carry over to the next area. Each task has 2-3 decor choices that can be changed later for free. The Harbour scene updates when a task is bought, and finishing all 5 shows the Area restored screen.
- **Also included:** Quick 6x6 and Classic 9x9 (tier 1-4, from the packs), unlimited and outside the path.
- **Save:** CrazyGames data with a localStorage fallback. Saves path progress, stars, coins, tokens, tasks, decor, second-chance usage timestamps, and the grid in progress.

## 7b. Debug hooks
Debug hooks follow the list in QA_TEST_PLAN.md.

## 8. Out of scope
Materials, IAP, pass, events, daily puzzles, accounts or cloud sync, tier 5 techniques, more than one area, audio beyond placeholder, localisation, mobile builds, and Unity.

## 9. Acceptance criteria (pass/fail)
1. The GUT suite passes headless with 0 failures.
2. Every pack puzzle has exactly one solution and a grade matching its stored tier. 100 out of 100 seeded 4x4 and 6x6 puzzles are unique.
3. The web build makes no runtime calls to generate a 9x9 (log check). 4x4 and 6x6 generation takes 30 ms or less (p95) in Chrome, with no frame over 50 ms.
4. The web build boots past the title in Chrome and Firefox with 0 console errors (errors from the ad SDK or from requests an adblocker blocked are ignored), and works as a single-thread export.
5. Digits, notes, and undo work with touch, mouse, and keyboard, and undo restores the exact previous state.
6. Pressing Hint always opens the panel and pauses the grid first, with no rewarded button visible on the live grid.
7. Teach shows the technique name and highlights matching the grader's step for that board state.
8. With ads off (mock set to unavailable, or an adblocker), hints and second chance still work through tokens or coins, no rewarded button is visible anywhere, and the full path can be completed.
9. The third mistake opens the Second chance panel. A second chance works once per grid, and after 3 in 24 hours only Retry is shown.
10. The SDK call log shows 0 interstitial or unrequested ad calls while a grid is open (rewarded calls started from the Hint or Second chance panel are allowed). No results screen shows both a midgame ad and a rewarded offer, and a midgame ad fires only after 3 or more counted completions and 5 or more minutes into the session.
11. Finishing the path with the most mistakes and Reveals yields exactly 20 stars, and a perfect path yields exactly 31. All 5 tasks can be bought, the visuals change per task, and the Area restored screen appears.
12. After a reload, progress, coins, tokens, decor, the second-chance cap, and the grid in progress are restored exactly.
13. Digits are at least 60% of cell height and cells at least 44 px at 1280x720 (screenshot check).
14. Teach on a 9x9 after the player has diverged from the stored solve order still gives a step that's valid on the current board.
15. A second chance at 3 uses within 24 hours stays capped after the clock is set back. Unaffordable coin options appear disabled with the "Need N more coins" line.
