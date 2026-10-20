# QA Run 3: non-GUI (commit 3f2a0b4, portal polish), no browser driven
| # | Item | Verdict | Evidence |
|---|---|---|---|
| 1 | Hashes | PASS (unchanged start to end; release pck c176fb2d…, wasm fe5cebc5… same template) | BUILD_HASHES.txt |
| 2a | GUT | PASS: 95/95, 631 asserts, 0 SCRIPT ERROR (9 new audio tests) | GUT.txt |
| 2b | Seeds 4000-4049 x 7 size/tier + Teach first step | PASS: 350/350 unique, tier = requested = game grade, 350/350 first steps valid | seeds/SUMMARY.txt |
| 3 | B3 release debug audit | PASS: 0 hook hits in raw pck/js/html; only the inert dbg stub + path strings (as in run 2); no debug/, test_vectors, tests, gut. New `assets/branding/*.png.import` are legitimate texture remaps (needed for the .ctex), not leftovers. | B3_debug_audit.txt, B3_pck_listing.txt |
| 4a | Ad mute/unmute, no stuck path | PASS | AUDIO_logic.txt |
| 4b | visibilitychange hidden + blur mute, restore on visible | **FAIL**: no blur handling at all; "hidden" is a 0.25 s poll of document.hidden in _process (no visibilitychange listener), which may not run while the tab is hidden and rAF is throttled | AUDIO_logic.txt (fix suggested) |
| 4c | AudioContext resume on first gesture | PASS (static) | AUDIO_logic.txt |
| 5 | CSS no-select/touch-callout, contextmenu, icon/splash | PASS | HTML_checks.txt, index*.png |
| 6 | Input mapping | PASS (risks: AZERTY digits via keycode, Ctrl+digit not filtered, key repeat) | INPUT_map.txt |
| 7 | Run 2 hardening regression | PASS (no regression): mode "none" default, mock debug-only, adblock gating, loadingStart/Stop, wait_ready, GUT none-mode tests pass | REGRESSION_run2_hardening.txt |
Tool added: qa/release_audit.sh (reusable B3 audit).
