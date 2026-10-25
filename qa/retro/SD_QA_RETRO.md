# SD QA retro (for Meowdoku / game #4)
Time lost per item wasn't logged, so the times below are rough and marked "~", not measured.

## 1) Worked, make standard
- Hash-pinned gate: a release export from a clean worktree, plus SHA256SUMS in /workspace/sudoku-dash-gated/<sha>/, release_audit.sh, GUT, then a live curl sha256 of index.pck against the gated hash before a browser smoke test. This caught nothing wrong but made every live PASS provable. Runs 5-9 were all traceable this way.
- Debug hooks in debug builds only (SD_DEBUG.startLevel/setTokens/setCoins/dump, SD_QA.stepDump, H7 timer label). They turned flaky screenshot reads into exact numbers (for example the 68314 ms frozen timer under a panel).
- Spec questions resolved in writing before testing. LQ-1..9 in LEVEL_OBJECTIVES_SPEC section 9 (par <= par*1000, 3-star at floor(0.75*par*1000), Reveal +15000 ms, restore within 1000 ms) turned the tests into binary PASS/FAIL with no arguments.

## 2) Time sinks / failures
- Reading timers off screenshots. Root cause: the box display lags 5-15 s, and PIL grabs are stale. Lost: ~several hours across runs 5-6. Fix: assert from dump()/stepDump only, and use screenshots only for layout.
- Run 8 FAIL, harbour list not scrolling when a drag starts on a button (98ff834). Root cause: the mobile pass tested taps, not drags starting on controls, so it wasn't in the build's own tests. Lost: one full gate cycle (run 8 to run 9). Fix: touch_scroll.gd with a 10 px threshold in b5479ff. The test plan for #4 needs "drag starting on a button scrolls" from day 1.
- Interrupted long QA runs (the run 9 executor died mid-run). Root cause: one monolithic run with no checkpoints. Lost: ~1 partial rerun. Fix: split runs into resumable stages, each writing results to qa/results/<run>/ as it goes.
- The live alert/console check didn't fire on GitHub Pages. Root cause not found. I accepted the pass on hash identity. Fix: a live check that doesn't rely on alert().

## 3) Handoffs that broke
- Art to Build: kit v1 (31c2e66) sits on art/assets-v1, unmerged and "not wired into scenes", while the live build has only placeholder icon and splash art. Nobody owned the integration ticket. Shahar asked "what about the art?" on 25 Oct.
- QA scripts weren't committed: check_levels.py, mobile_qa.py, live_check.py and others are still untracked and only survived a rollback by luck. That's a QA-to-repo handoff gap I own.
- Two working copies (/workspace/sudoku-dash and /workspace/sudoko_dash, the repo name is misspelled). Branches and art live in one, QA results in the other, so it's easy to test the wrong tree.

## 4) Day-1 checklists I wanted
- A gate checklist template: hashes, preset, audit, GUT count, viewports, live sha, then the link to Shahar.
- A viewport matrix fixed up front: phones (390x844 and others), desktop 1280x800/1366x768, and the CrazyGames embeds 800x450/821x462/907x510 at DPR 1. The CG sizes were only added after the live deploy.
- An input matrix: mouse, keyboard (including key repeat), touch tap, touch drag starting on controls, blur/hidden tab.
- A spec "QA questions" section (like LQ) required before any build starts.

## 5) Tooling / infra gaps
- No real-phone or iOS Safari testing. Safe areas and Safari quirks are still unverified, because headless Chrome over CDP is all we have.
- Desktop-display lag and unreliable Ctrl+R/Ctrl+L on the box. I work around it with CDP, and nothing is fixed.
- No CI: GUT and the release audit run by hand per gate.
- No momentum or inertia check for touch scroll (it has none and that's untested).

## 6) One process change for #4
- QA writes the test plan (including the viewport and input matrices) before the build starts, and its scripts are committed to the repo's qa/ folder in the same PR as the feature they test.

## 7) Reusable for Meowdoku
- QA_TEST_PLAN.md (89 active tests; P7 holds the 23 LO-* level-objective tests).
- qa/check_levels.py: grid validity, a unique solution, and difficulty grade against the techniques needed.
- qa/check_teach_targets.py + teach_targets.gd, hint_memory.gd + check_hint_memory.py: hint correctness and no double-charging.
- qa/mobile_qa.py: Chrome CDP with Emulation and touch-only input; multi-viewport.
- qa/live_check.py: live sha + colour-based button finding + tesseract OCR smoke test.
- qa/test_qa_run5.gd (GUT), release_audit.sh, and the gated-folder layout.
- The debug hook contract (SD_DEBUG / SD_QA.stepDump / H7). Ask Build to keep the same names.
