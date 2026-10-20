# Sudoku Dash: CrazyGames Basic Launch checklist
Prepared 2026-10-20 against commit 3689a0c (live: https://shaharfranses.github.io/sudoko_dash/). Nothing submitted, nothing pushed.

Sources (fetched 2026-10-20):
- Requirements intro: https://docs.crazygames.com/requirements/intro/
- Technical: https://docs.crazygames.com/requirements/technical/
- Game covers: https://docs.crazygames.com/requirements/game-covers/
- Ads: https://docs.crazygames.com/requirements/ads/ (summarised in RESEARCH_BRIEF.md §2)

**Key point:** in Basic Launch the SDK is optional and **monetization is disabled**. Ads are turned off even when they are integrated. If the SDK is present, the only Basic requirement is a `gameplayStart` event when the player reaches a playable state. That event is also where the initial download size is measured. Our rewarded and midgame hooks are fine to keep, but they will never fire, so every no-ad route has to work on its own.

## 1. Required submission assets
| Asset | Spec (docs) | Status |
|---|---|---|
| Landscape cover | 16:9, 1920x1080 | MISSING |
| Portrait cover | 2:3, 800x1200 | MISSING |
| Square cover | 1:1, 800x800 | MISSING |
| Preview video, landscape | 1080p 16:9, 15–20 s, ≤50 MB, no sound, first frame = cover, no black bars/cursor/promo text | MISSING (mandatory) |
| Preview video, portrait | 1080p 2:3, same rules | MISSING (mandatory) |
| Description | free text (metadata) | DRAFT below |
| Controls | free text (metadata) | DRAFT below |
| Tags/category | chosen in the portal form | DRAFT below |
| Supported orientations | set in the form (portal enforces rotation) | Decide: both (stretch=expand, handheld orientation=6 sensor) |

Cover rules: no borders; the game title is the only text allowed (no "New" or "Play"); no icons or store logos; no blurry art; use art we own. The covers should be stylised art, not screenshots. The repo has **no art assets** (only the Godot default icons and QA screenshots), so the covers have to be made from scratch.

## 2. Draft metadata
**Title:** Sudoku Dash

**Short description:** Restore a cozy seaside village one puzzle at a time! Start with quick 4x4 grids, step up to 6x6, then master classic 9x9 Sudoku.

**Description:**
Sudoku Dash is a relaxing Sudoku adventure with a cozy seaside twist. Solve puzzles along the Village Path to earn stars and materials, then use them to restore the harbour café step by step. New to Sudoku? Begin with small 4x4 and 6x6 grids before taking on full 9x9 puzzles. Stuck? Smart hints tell you *why* a number fits, so you learn real techniques as you play. Prefer the classic experience? Classic mode offers unlimited Easy, Medium and Hard 9x9 puzzles. Notes, undo, erase and conflict highlighting are all included, and your progress saves automatically.

Features:
- Village Path with gentle 4x4 → 6x6 → 9x9 progression
- Restore a seaside café with the stars and materials you earn
- Technique-explaining hints
- Unlimited classic 9x9 in three difficulties
- Notes, undo, mistake highlighting, auto-save

**Controls:**
- Mouse/touch: tap a cell, then tap a number to place it
- Keyboard: arrow keys to move, 1–9 to place a number, N to toggle notes, Backspace/Delete to erase, Ctrl+Z to undo  ← *verify bindings against ui/main.gd before submitting*
- Notes button: switch to pencil marks

**Tags (proposed):** Sudoku, Puzzle, Logic, Number, Brain, Casual, Relaxing, Mobile, Board. Category: Puzzle.

## 3. Requirements vs our build
| Requirement (doc) | Our build (3689a0c) | Result |
|---|---|---|
| Initial download ≤ 50 MB (technical) | 39.5 MB (wasm 35.4 MB + pck 3.6 MB + js 0.33 MB) | PASS |
| ≤ 20 MB for mobile homepage eligibility | 39.5 MB | FAIL (optional, but costs mobile reach) |
| Total ≤ 250 MB with SDK | ~39.5 MB | PASS |
| File count ≤ 1500 | 8 files in build/web-release | PASS |
| Relative paths only | index.html uses relative refs; only absolute URL is the SDK script | PASS |
| SDK `gameplayStart` when playable (Basic, if SDK used) | `Ads.set_context("grid")` → `SD_CG.gameplay(true)`; Stop on leaving the grid | PASS (verify in CG QA tool) |
| gameplayStop on pause/menus (Full) | Fires when context ≠ grid (grid_panel, results, menu) | PASS |
| loadingStart/Stop (optional) | Wired in head_include.html | PASS |
| SDK only on portal | Loads only on `*crazygames.*` hosts or `?cgsdk=1`, and requires `environment==='crazygames'` | PASS. Note: the CG dev-portal preview may report `environment` "local"/"disabled", which makes `cg()` null and suppresses gameplay events in preview. Check in the QA tool. |
| No external ads / ads only via SDK | No other ad code | PASS |
| Monetization disabled in Basic → game works with no ads; no dead rewarded buttons | Rewarded is hidden until adblock is known; release off-portal = unavailable, never grants; coin/token alternatives exist (QA HN-02, SC-10) | PASS (QA-verified) |
| Midgame only at breaks, never on grid/nav | `midgame()` is blocked while the grid is open | PASS |
| Rewarded not on active gameplay screen | Allowed only in grid_panel/results | PASS |
| Mute audio on adStarted, resume after | `adStarted` callback is empty. The game has **no audio** at all | N/A now, FAIL once audio is added |
| Mute on visibility hide / iOS AudioContext resume on touch | No audio, no handler | N/A now. Required with audio |
| `user-select:none` CSS on body (mobile) | Not in head_include/index.html | FAIL (easy fix) |
| Mouse + keyboard + touch | Covered in QA (IN-01, IN-03) | PASS |
| Landscape playable on desktop | 1280x720, stretch expand | PASS |
| Chrome/Edge/Safari; Chromebook 4 GB | Chrome tested; Safari/iOS, Chromebook untested | UNKNOWN |
| Safe-area padding in CG app | Not handled | UNKNOWN |
| PEGI 12 | Sudoku, no objectionable content | PASS |
| No external login | None | PASS |
| No external links / iframe-safe | No `shell_open`/links found in game code | PASS |
| Sitelock whitelisting | No sitelock | PASS/N/A |
| Privacy/consent notice if collecting data beyond SDK | Saves only to localStorage + CG data module; no analytics | PASS (none needed now). Required if ByteBrew/analytics is added. |
| Language | English only | OK (no requirement found; competitor ships 6 languages) |
| Basic visual QA | Godot default icon/favicon; placeholder art? | UNKNOWN. Needs an art pass review |

## 4. Gaps (suggested owners)
1. **Covers ×3 (1920x1080, 800x1200, 800x800)**: no art exists. Owner: Art/marketing (designer or image-gen + manual polish).
2. **Preview videos ×2 (1080p 16:9 and 2:3, 15–20 s, silent)**: mandatory. Needs final art first. Owner: Art/marketing; capture via the QA browser harness.
3. **Audio missing entirely (SFX/music)**: once added, implement mute on `adStarted`/unmute after, mute on `visibilitychange` hidden, and AudioContext resume on touchend. Owner: Audio + Godot dev.
4. **Visual polish / branding**: replace Godot default favicon/apple-touch icon and splash; review placeholder UI art for the "Basic visual QA". Owner: Art + dev.
5. **`user-select:none` (and `-webkit-touch-callout:none`) on body** in head_include.html. Owner: Godot dev (5-min fix).
6. **Size 39.5 MB > 20 MB mobile-homepage threshold**: try a custom Godot web template (disable 3D/unused modules, `optimize=size`), wasm-opt, Brotli. Target ≤20 MB. Owner: Build/dev.
7. **Verify in the CG Developer Portal QA tool**: that gameplayStart fires (environment value in preview), and the measured initial size. Owner: Studio Manager/QA (no submission needed, preview only).
8. **Untested platforms**: Safari/iOS, Chromebook 4 GB, CG app safe areas. Owner: QA.
9. **Controls text**: confirm the actual key bindings. Owner: dev.
10. **Privacy note**: not required now. Write a short Privacy Policy if analytics is ever added. Owner: Studio Manager.
11. **Localization**: optional; EN only for launch. Owner: later.
