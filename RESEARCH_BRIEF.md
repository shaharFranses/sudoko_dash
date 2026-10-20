# Sudoku Dash — Research Brief (2026-10-20)
Target: Godot 4.3 web (single-thread export), CrazyGames first, then Poki / GameDistribution.
All figures come from the pages linked here as fetched on 2026-10-20. "Not found" means I could not verify it.

## 1. Competitive landscape
### CrazyGames (tag page: https://www.crazygames.com/t/sudoku ; mirror listing: https://crazygames.to/tag/sudoku)
| Game | URL | What it does | Rating / votes shown |
|---|---|---|---|
| Sudoku Online (Playgama) | https://www.crazygames.com/game/sudoku-szc | Classic 9x9, difficulty levels, hints, undo, notes. Portrait | 8.7 (6 mo); 2.8K likes / 498 dislikes; plays not found |
| Sudoku Classic & Killer (TopOp Games, May 2026) | https://www.crazygames.com/game/sudoku-classic-killer | Classic + Killer, daily seed, 3 hints/day (+rewarded), 3 lives with a rewarded continue, 8 unlockable themes, 6 languages | 9.2; 347 likes / 29 dislikes; plays not found |
| Others in the tag (not inspected in detail) | tag page | Daily Sudoku, Sudoku 9x9, Brainrot Sudoku, Fruit/Xmas Sudoku, Sudoblock Daily, many "Weekend Sudoku NN" reskins, Killer/Futoshiki/Kakuro variants | not found |

### Poki
| Game | URL | What it does | Rating (votes) |
|---|---|---|---|
| Sudoku (InfinityGames) | https://poki.com/en/g/sudoku | Classic, difficulty levels, hints | 4.1 (32,271) |
| Online Sudoku (Logic.cool) | https://poki.com/en/g/online-sudoku | Daily puzzle + leaderboard | 4.0 (10,584) |
| Ultimate Sudoku (Codethislab) | https://poki.com/en/g/ultimate-sudoku | Classic, 3 difficulty levels | 3.9 (25,443) |
| Sudoku Calendar (supernice.games) | https://poki.com/en/g/sudoku-calendar | Daily calendar puzzle, streaks, hints | 4.3 (16,575) |
| Sudoblocks (InfinityGames) | https://poki.com/en/g/sudoblocks | Block-placement game with sudoku rules | 3.9 (108,975) |
Poki does not show play counts publicly (not found).

### Gaps we can exploit
- None of the games we inspected has a **meta progression or theme layer** (restoration, decorating, collection). Progression stops at difficulty tiers, daily streaks, or color themes. Our cozy seaside village restoration would be different.
- **No onboarding ramp.** Everyone starts at 9x9. Snack grids (4x4, then 6x6, then 9x9) lower the barrier for casual and young portal players.
- The top-rated CG entry (9.2) has the most features: hints economy, lives, daily, themes, i18n. That is the quality bar. Copying its rewarded patterns is validated. Its vote count is small, so the category looks under-served by polished games.
- Poki's sudoku games are mostly old (last updated 2022–2023, apart from Ultimate Sudoku in Dec 2025 and Sudoku Calendar in Jan 2026), rated about 3.9–4.3. That is room for a modern, juicy one.
- Technique-taught hints (explaining *why*) were not seen in the listings. Possible differentiator; competitors' hints are unverified.

## 2. CrazyGames requirements and ad rules
Sources: https://docs.crazygames.com/requirements/intro/ , https://docs.crazygames.com/requirements/ads/
- **Basic Launch: monetization is DISABLED and the SDK is optional.** If the SDK is integrated, the game must run smoothly with ads off. The docs specifically say "There should not be rewarded ad buttons without effect", and the game must not freeze between levels. Implication: hints and second chances need a non-ad route (soft currency / free daily allowance), and rewarded buttons are hidden or work as no-ad grants when ads are unavailable.
- Basic technical limits: initial download ≤ 50 MB; total ≤ 250 MB (50 MB without SDK); ≤ 1500 files; PEGI 12; no external ads; no external login.
- Full Launch (if selected): SDK + gameplayStart event, land directly in gameplay, ads only via SDK, works with AdBlock, progress linked to the CG account. IAP is invite-only, via Xsolla.
- Midgame: only at logical breaks, never on navigation buttons (menu/settings/shop). The SDK caps frequency itself (max 1 per 3 min), so we can request at every puzzle-complete. Pause and block input until adFinished/adError. Mute only when the ad actually starts. Treat adError as "continue".
- Rewarded: offer optional and not too often. No chaining. The skip option must look the same as the watch option, and the close button can't be hidden or delayed. Show a video icon. Offer an alternative (coins). Never reward on adError. **The request button may not appear on an active gameplay screen.**
- Specific to our plan:
  - *Second chance after the 3rd mistake* = an "out-of-lives" placement. Allowed, but **not every time**: needs a cooldown or per-session cap, plus a coin alternative.
  - *Rewarded hints*: the button can't sit on the live grid. Open a hint panel/pause overlay first, or tie it to a hint-refill screen.
  - **Between two puzzles you can show a midgame ad OR a "watch to keep playing" offer, never both.** If the player takes the second chance, skip the midgame on that transition.
  - No mid-grid ads: matches the rules.
- AdBlock users must be able to play normally. You may disable a rewarded feature, but show a notice and never leave a dead button.
- Poki and GameDistribution rules were not researched in this pass (not found here). Check them before porting.

## 3. Generation, solving, grading
Proven approaches:
- **Solver**: constraint propagation + backtracking with MRV (minimum remaining values), using bitmask candidates (Norvig, https://norvig.com/sudoku.html). Alternatively Knuth's Dancing Links / Algorithm X (https://arxiv.org/abs/cs/0011047), which is fast for exact cover and generalizes to 4x4/6x6/9x9 and variants. **Uniqueness check = count solutions, stop at 2.**
- **Generation**: (a) fill a full grid by randomized backtracking (seeded RNG); (b) remove clues in random or symmetric order, keeping a removal only if the solution count stays 1; (c) grade; (d) repeat until the target band is hit. For daily or level puzzles, generate offline and ship a seeded or pre-baked pack. This avoids web CPU spikes on a single-thread export.
- **Difficulty grading**: run a *human-style* logical solver that applies techniques in order of cost and records the hardest technique needed plus how many steps each took: naked/hidden single, then pointing/claiming, naked/hidden pairs and triples, then X-Wing, Swordfish, XY-Wing, and chains. Rating is the max technique tier, with optional weighting. Prior art: SudokuWiki strategy catalogue (https://www.sudokuwiki.org/Strategy_Families), HoDoKu (https://hodoku.sourceforge.net/en/tech_intro.php), Sudoku Explainer SE rating. The same step log can drive **explanatory hints** ("Hidden single in row 4").
- Clue count alone is a poor difficulty predictor; base grading on techniques (consensus in the sources above).

**Recommended structure (engine-agnostic, tested):**
- Write the **core in C#** (netstandard 2.1 class library `SudokuCore`: Grid(N, boxW, boxH), Candidates bitmask, Solver (DLX or bitmask backtrack), Generator(seed), Grader(technique list), HintEngine) with **xUnit tests** (known puzzles, uniqueness, golden grades, seed determinism).
  - Unity uses it directly.
  - Catch: **Godot 4.3 C# cannot export to web** (C#/.NET web export is unsupported in Godot 4.x as of 4.3; see https://docs.godotengine.org/en/4.3/tutorials/scripting/c_sharp/index.html). The web build therefore needs GDScript.
- Practical plan: keep **one spec + shared JSON test vectors** (puzzle, solution, expected grade, seed→grid). Implement **GDScript `sudoku_core/`** now (tested with GUT or gdUnit4), and port to C# later against the same vectors.
  - GDScript runs slower, so rely on **pre-generated puzzle packs** (JSON produced offline by the C# or a Python tool). At runtime only the cheap parts run: validation, hints from the stored technique log, and maybe 4x4/6x6 generation.
- Alternative: a C/C++ core via GDExtension. Possible for web in 4.3, but more build complexity on a single-thread export. Not recommended for the slice.

## 4. Proposed vertical slice
IN:
- Village Path with ~15 nodes: 4x4 (5), then 6x6 (5), then 9x9 easy/medium (5), from pre-baked graded packs. Stars by mistakes and time; materials restore **one** seaside scene (e.g., harbor café: 4–5 restoration steps with tween/particle juice).
- Unlimited classic 9x9 (Easy/Medium/Hard) from packs.
- Core UX: notes, undo, erase, conflict highlight, 3-mistake limit, technique-explained hint (free allowance + coins).
- Ad hooks behind an `Ads` interface:
  - midgame request on puzzle complete;
  - rewarded hint (from the hint panel, not the live grid) and capped second chance;
  - full no-ad fallback, so it's Basic-Launch safe.
- Local save, CrazyGames SDK stub/optional, built and checked against the 50 MB initial-size limit; desktop + mobile portrait/landscape.
- Core library + test vectors; offline pack generator.

OUT (later):
- Variants (Killer, Jigsaw, Diagonal), daily challenge, events, pass, IAP, multiple villages, leaderboards, account sync, localization beyond EN, Unity port, Poki/GD SDKs.

Open questions: exact CG Basic Launch progression metrics (guide page not fetched: not found); Poki/GD ad rules; whether pass/IAP is feasible on portals (CG IAP is invite-only).
