# QA Run 4: non-GUI (commit 054dd29), no browser driven
| # | Item | Verdict | Evidence |
|---|---|---|---|
| 1a | Hashes | PASS (unchanged start to end) | BUILD_HASHES.txt |
| 1b | GUT | PASS 111/111, 686 asserts, 0 SCRIPT ERROR | GUT.txt |
| 1c | Seeds 5000-5049 x 7 + Teach | PASS 350/350 unique and tiered; 350/350 first steps valid | seeds/SUMMARY.txt |
| 2a | release_audit.sh (B3) | PASS: 0 hook hits in release pck/js/html; only the inert stub + path strings; branding .import files are legitimate | B3_debug_audit.txt |
| 2b | ?ads= debug-only | PASS: release has no debug/ files, no get('ads'), no mock_*; debug has get('ads') + mock_available/unavailable/error/timeout (timeout path in ads_mock) | ADS_PARAM_check.txt |
| 3 | A1 audio gate | PASS (bus not muted on blur but the context is suspended; edge notes in the file) | A1_audio.txt |
| 4 | Input | PASS (minor: Ctrl+Z key repeat still repeats undo) | INPUT_feedback.txt |
| 5 | 4x4 label + wrong-entry feedback | PASS | INPUT_feedback.txt |
| 6 | Run 2/3 hardening | PASS, intact | REGRESSION_hardening.txt |
| 7 | Cold-load timing (GitHub Pages) | Measured; see the notes | COLD_LOAD_curl.txt, DEPLOYED_hashes.txt |

## Cold-load notes
- **The deployed site is NOT 054dd29**: its pck/html/wasm sha256 match the **run 2 release (3689a0c)** (pck 4be7de45…, html 73ca94bc…). Redeploy before any in-browser test of the new features on Pages.
- GitHub Pages (Fastly) serves **gzip only, no brotli** (`Accept-Encoding: br` returns uncompressed). cache-control max-age=600. No COOP/COEP (fine; single-thread).
- Transfer sizes (gzip): html 2.9 KB, js 85 KB, wasm 8.15 MB, pck 0.51 MB, so about **8.75 MB total**. Uncompressed is 39.3 MB.
- From the box (datacenter link, so not representative of players): TTFB 0.12-0.35 s; wasm gzip total 1.11 s on run 1 (cold CDN, TTFB 1.09 s), 0.16-0.17 s on runs 2-3 (CDN HIT). On a 10 Mbps player link, the about 8.75 MB gzip download would take roughly 7 s; that's an estimate, not measured.
- On CrazyGames the files are hosted by CrazyGames, so the Pages numbers only indicate the compression ratio.
