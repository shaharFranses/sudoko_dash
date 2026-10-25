#!/usr/bin/env python3
"""Builds qa/results/cg_sizes/RESULTS_table.md fragment (per-size verdicts + measurements) from live_<size>.json."""
import json, os
D = os.path.join(os.path.dirname(os.path.abspath(__file__)), "results", "cg_sizes")
SIZES = ["800x450", "821x462", "907x510", "1366x768"]
out = []
def med(d): return d and d.get("median")
out.append("| Size | Checks | Verdict | 6x6 cell / given / entered / note px | 9x9 cell / given / entered / note px (core) | Pad btn px (6x6, 9x9) | Hint panel (3 btn → 4 btn) px | Harbour header wraps |")
out.append("|---|---|---|---|---|---|---|---|")
detail = []
for t in SIZES:
    p = os.path.join(D, f"live_{t}.json")
    if not os.path.exists(p): out.append(f"| {t} | missing | — | | | | | |"); continue
    R = json.load(open(p)); C = R["checks"]; M = R["meas"]
    npass = sum(1 for v in C.values() if v["result"] == "PASS"); fails = [k for k, v in C.items() if v["result"] != "PASS"]
    verdict = "PASS" if not fails and not R.get("exception") and npass >= 25 else "FAIL"
    g6 = f'{M.get("g6_L1_cell_px")} / {med(M.get("g6_L1_given_glyph_h_px"))} / {M.get("g6_L1_entered_glyph_h_px")} / {med(M.get("g6_L1_note_glyph_h_px"))}'
    g9 = f'{M.get("g9_classic_cell_px")} / {med(M.get("g9_classic_given_glyph_h_px"))} / {M.get("g9_classic_entered_glyph_h_px")} / {med(M.get("g9_classic_note_glyph_h_px"))} ({med(M.get("g9_classic_note_glyph_core_h_px"))})'
    pads = f'{M.get("g6_L1_pad_btn_px")}, {M.get("g9_classic_pad_btn_px")}'
    hp = f'{M.get("g9_classic_hint_panel_px")} → {M.get("g9_classic_hint_panel4_px")}'
    out.append(f"| {t} | {npass}/{len(C)} | **{verdict}** | {g6} | {g9} | {pads} | {hp} | {M.get('harbour_header_wraps')} |")
    detail.append(f"\n#### {t}\n- checks: " + ", ".join(f"{k}={v['result']}" for k, v in C.items()))
    detail.append(f"- 9x9 note glyph heights (px, AA ink): min {M['g9_classic_note_glyph_h_px']['min']}, median {M['g9_classic_note_glyph_h_px']['median']}, max {M['g9_classic_note_glyph_h_px']['max']} (n={M['g9_classic_note_glyph_h_px']['n']}); core-ink median {M['g9_classic_note_glyph_core_h_px']['median']}")
    detail.append(f"- 6x6 note glyph heights (px): min {M['g6_L1_note_glyph_h_px']['min']}, median {M['g6_L1_note_glyph_h_px']['median']}, max {M['g6_L1_note_glyph_h_px']['max']}")
    detail.append(f"- control buttons WxH px (9x9): {M.get('g9_classic_ctrl_btn_px')}; label-to-edge margin px: {M.get('g9_classic_ctrl_text_margin_px')}")
    detail.append(f"- control buttons WxH px (6x6): {M.get('g6_L1_ctrl_btn_px')}; label-to-edge margin px: {M.get('g6_L1_ctrl_text_margin_px')}")
    detail.append(f"- pad label glyph px: 6x6 {M.get('g6_L1_pad_label_glyph_h_px')}, 9x9 {M.get('g9_classic_pad_label_glyph_h_px')}; hint-panel button label margins: {M.get('g9_classic_hint_btn_text_margin_px')}")
    detail.append(f"- OCR path: 6x6 {R.get('g6_L1_ocr_tries')}, 9x9 {R.get('g9_classic_ocr_tries')}; second-opinion reads: {R.get('ocr_second_opinion')}")
    detail.append(f"- boot {R.get('boot_s')} s; metrics {R.get('metrics')}")
open(os.path.join(D, "RESULTS_table.md"), "w").write("\n".join(out) + "\n\n### Per-size detail\n" + "\n".join(detail) + "\n")
print("\n".join(out))
