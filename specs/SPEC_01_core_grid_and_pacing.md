# SPEC 01: Core Grid, Difficulty Grading, and Early Pacing (v0.1 draft)
Owner: SD Game Design. For: SD Godot Build. Target: Godot 4.3 web build (CrazyGames/Poki/GD).

## 1. Grid sizes
| Size | Boxes | Digits | Use |
|---|---|---|---|
| 4x4 | 2x2 | 1-4 | Tutorial and village levels 1-5 |
| 6x6 | 2x3 (2 rows by 3 cols) | 1-6 | Village levels 6-20, plus a permanent "Quick 6x6" mode |
| 9x9 | 3x3 | 1-9 | Village level 21+, plus Classic mode |
Every puzzle has exactly one solution (the generator checks for uniqueness before shipping a puzzle).

## 2. Readability
- Given digits are at least 60% of cell height, in a dark navy colour. Player digits are the same size in teal.
- Notes are at least 28% of cell height. Minimum cell size is 44 px at 1280x720.
- Highlight the selected row, column, and box, and every matching digit. Conflicts get a soft red cell plus an icon, never colour alone.

## 3. Mistakes
- A wrong entry counts as one mistake; the limit is 3 per grid. On 4x4 grids mistakes are shown but there is no limit.
- On the third mistake, offer a second chance: watch a rewarded ad to clear the mistakes and continue, once per grid. Otherwise retry, and the board is kept.
- Mistake checking can be switched off in settings, for purists. With checking off there's no limit and a 10% star bonus.

## 4. Hints (the game never solves the puzzle for the player)
| Hint | Effect | Cost |
|---|---|---|
| Teach | Highlights the cells involved and names the technique in one line | 1 hint token |
| Reveal cell | Fills the selected cell | 1 hint token |
| Auto-notes | Fills in every valid candidate | Free in settings |
Players start with 3 tokens and earn 1 per day plus 1 per rewarded ad, up to a cap of 10.

## 5. Difficulty is graded by the hardest technique needed
| Tier | Hardest technique | Sizes |
|---|---|---|
| 1 Gentle | Naked single only | 4x4, 6x6 |
| 2 Easy | Hidden single | 6x6, 9x9 |
| 3 Medium | Naked or hidden pair, pointing pair | 9x9 |
| 4 Hard | Triples, box-line reduction, X-Wing | 9x9 |
| 5 Expert | Swordfish, XY-Wing, simple colouring | 9x9 |
The solver applies techniques from easiest to hardest and tags each puzzle with the highest tier it needed. Clue count is never used to grade.

## 6. Rewards per grid
| Size | Stars | Coins | Materials |
|---|---|---|---|
| 4x4 | 1 | 10 | 1 |
| 6x6 | 1-2 | 20 | 1-2 |
| 9x9 | 2-3 | 40 | 2-3 |
You earn the top star count by finishing with 0 mistakes and no Reveal hints. Time is never used, so the game stays calm.

## 7. Restoration
- Each task costs 1-3 stars. The player picks from 2-3 decor styles, and the choice can be changed later for free.
- Early pacing goal: one task about every 2 grids for the first 15 minutes.

## 8. Ads
No ads during a grid. Interstitials only appear between grids, at most 1 every 3 grids, and never in the first 5 minutes.

## Open questions
- The plan summary says Unity 6 mobile-first, but the studio direction is Godot web. This spec assumes Godot web.
