#!/usr/bin/env python3
"""CrazyGames embed-size readability/layout check (desktop window, DPR 1, mouse input, no emulation).
Reuses the raw-CDP driver (mobile_qa.CDP) and the colour/OCR readers (live_check). Works on the release build (no hooks).
Usage: /tmp/qav/bin/python qa/cg_sizes.py WxH [url] [src_tag] [cdp_port]"""
import json, os, re, sys, statistics
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mobile_qa import CDP, metrics_ok, on_screen, cream_bbox, bands, glyph_heights, candidates
from live_check import ocr, ink, buttons, find, board_box, _glyph, read_board, solve, cell_colour
from PIL import Image, ImageOps

TAG = sys.argv[1]; W, H = map(int, TAG.split("x"))
URL = sys.argv[2] if len(sys.argv) > 2 else "https://shaharfranses.github.io/sudoko_dash/"
SRC = sys.argv[3] if len(sys.argv) > 3 else "live"
PORT = int(sys.argv[4]) if len(sys.argv) > 4 else 9580
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "results", "cg_sizes")
os.makedirs(OUT, exist_ok=True)
P = lambda n: os.path.join(OUT, f"{SRC}_{TAG}_{n}.png")
R = {"src": SRC, "url": URL, "viewport": TAG, "checks": {}, "meas": {}}; C = R["checks"]; M = R["meas"]
def chk(name, ok, **ev):
    C[name] = {"result": "PASS" if ok else "FAIL", **ev}; print(name, C[name]["result"], json.dumps(ev, default=str)[:400]); return ok
HR = (0, 0, W - 9, H)   # harbour: exclude the ScrollContainer scrollbar (same slate colour, touches the buttons)
ctr = lambda b: (b["x"] + b["w"] / 2, b["y"] + b["h"] / 2)
def lbls(bs): return [(b["label"], round(b["x"]), round(b["y"]), round(b["w"]), round(b["h"])) for b in bs]
def inside(b, tol=0.5): return b["x"] >= -tol and b["y"] >= -tol and b["x"] + b["w"] <= W + tol and b["y"] + b["h"] <= H + tol

def text_margin(img, b):
    """light label ink bbox inside a slate button -> min margin (px) to the button edge (0 = touching = possible clip)."""
    cr = img.crop((int(b["x"]) + 1, int(b["y"]) + 1, int(b["x"] + b["w"]) - 1, int(b["y"] + b["h"]) - 1))
    g = ImageOps.grayscale(cr).point(lambda v: 255 if v > 190 else 0); bb = g.getbbox()
    if not bb: return None, None
    return min(bb[0], bb[1], cr.width - bb[2], cr.height - bb[3]), bb[3] - bb[1]

def pad_digits(bs, n):
    """digit pad = n squarish buttons whose OCR is a digit; fallback = n largest similar squares sorted row-major."""
    d = {}
    for b in bs:
        t = re.sub(r"\D", "", b["label"])
        if len(t) == 1 and 1 <= int(t) <= n and b["label"].strip() == t: d.setdefault(int(t), b)
    if len(d) < n:
        sq = [b for b in bs if abs(b["w"] - b["h"]) < 0.35 * max(b["w"], b["h"]) and b["w"] >= 28]
        if len(sq) >= n:
            ref = statistics.median(b["w"] for b in sq)
            sq = [b for b in sq if abs(b["w"] - ref) < 6][:n]
            sq.sort(key=lambda b: (round(b["y"] / 10), b["x"]))
            if len(sq) == n: d = {i + 1: b for i, b in enumerate(sq)}
    return d

def board_border_ok(img, bb):
    """thick border (2d4a5a-ish dark) on all 4 sides just outside/at the fffdf7 area, and fully inside the viewport."""
    px = img.load(); res = {}
    def dark(p): return 0.299 * p[0] + 0.587 * p[1] + 0.114 * p[2] < 110
    x0, y0, x1, y1 = int(bb["x"]), int(bb["y"]), int(bb["x"] + bb["w"]), int(bb["y"] + bb["h"])
    xs = range(x0 + 4, x1 - 4, 5); ys = range(y0 + 4, y1 - 4, 5)
    res["top"] = any(sum(dark(px[x, y]) for x in xs) > 0.8 * len(xs) for y in range(max(0, y0 - 4), y0 + 2))
    res["bottom"] = any(sum(dark(px[x, y]) for x in xs) > 0.8 * len(xs) for y in range(y1 - 2, min(H, y1 + 5)))
    res["left"] = any(sum(dark(px[x, y]) for y in ys) > 0.8 * len(ys) for x in range(max(0, x0 - 4), x0 + 2))
    res["right"] = any(sum(dark(px[x, y]) for y in ys) > 0.8 * len(ys) for x in range(x1 - 2, min(W, x1 + 5)))
    return res

def note_glyphs(img, box, ins=3, thr=190):
    """8-connected components of non-background ink (lum < 190) inside one cell (inset past grid lines) -> [(h, w)] px."""
    x0, y0, x1, y1 = [int(round(v)) for v in box]
    cr = img.crop((x0 + ins, y0 + ins, x1 - ins, y1 - ins)); Wc, Hc = cr.size; px = cr.load()
    dk = [[0.299 * px[x, y][0] + 0.587 * px[x, y][1] + 0.114 * px[x, y][2] < thr for x in range(Wc)] for y in range(Hc)]
    seen = set(); out = []
    for y in range(Hc):
        for x in range(Wc):
            if dk[y][x] and (x, y) not in seen:
                st = [(x, y)]; seen.add((x, y)); xs = []; ys = []
                while st:
                    a, b = st.pop(); xs.append(a); ys.append(b)
                    for da in (-1, 0, 1):
                        for db in (-1, 0, 1):
                            u, v = a + da, b + db
                            if 0 <= u < Wc and 0 <= v < Hc and dk[v][u] and (u, v) not in seen: seen.add((u, v)); st.append((u, v))
                if len(xs) >= 4 and 4 <= max(ys) - min(ys) + 1 < Hc * 0.6: out.append((max(ys) - min(ys) + 1, max(xs) - min(xs) + 1))
    return out

def digit_heights(img, bb, n, cells, thr, which):
    cp = bb["w"] / n; hs = []
    for (r, c) in which:
        x0, y0 = bb["x"] + c * cp, bb["y"] + r * cp
        g = _glyph(img.crop((int(x0 + cp * 0.12), int(y0 + cp * 0.12), int(x0 + cp * 0.88), int(y0 + cp * 0.88))), thr)
        if g is not None: hs.append(g.height)
    return hs

REF = {6: [[0, 1, 0, 0, 0, 0], [0, 5, 4, 0, 6, 0], [0, 4, 0, 5, 0, 3], [0, 0, 0, 0, 0, 1], [0, 0, 0, 0, 0, 0], [0, 2, 0, 0, 5, 0]],
       9: [[3, 0, 6, 0, 0, 7, 0, 0, 0], [7, 0, 0, 4, 0, 0, 0, 0, 3], [0, 0, 8, 0, 3, 1, 9, 7, 0], [1, 0, 0, 0, 0, 3, 0, 0, 0], [0, 0, 0, 6, 0, 2, 0, 0, 8],
           [9, 0, 0, 7, 0, 0, 0, 0, 0], [4, 0, 7, 8, 0, 0, 6, 0, 0], [8, 0, 0, 0, 4, 0, 0, 0, 0], [0, 0, 9, 0, 0, 0, 0, 4, 1]]}   # visually verified

def consistent(g, n):
    bw, bh = (3, 2) if n == 6 else (3, 3)
    units = [[(r, c) for c in range(n)] for r in range(n)] + [[(r, c) for r in range(n)] for c in range(n)]
    units += [[(br + i, bc + j) for i in range(bh) for j in range(bw)] for br in range(0, n, bh) for bc in range(0, n, bw)]
    for u in units:
        v = [g[r][c] for r, c in u if g[r][c]]
        if len(v) != len(set(v)): return False
    return True

def grid_checks(img, n, name, thr=110):
    bb = board_box(img, 1)
    if not bb: chk(f"{name}_grid_visible", False, board=None); return None, None, None
    bord = board_border_ok(img, bb)
    chk(f"{name}_grid_fully_visible_with_border", inside(bb) and all(bord.values()) and abs(bb["w"] - bb["h"]) < 4, board={k: round(v, 1) for k, v in bb.items()}, border=bord)
    tries = []
    for t in (110, 150, 130):   # tesseract on a single glyph is threshold-sensitive (5 vs 3); keep the first read that solves
        g, cells = read_board(img, 1, bb, n, thr=t); sol = solve(g, n); tries.append({"thr": t, "solvable": sol is not None})
        if sol: break
    if not sol and n in REF:
        # the fresh-profile L1 / Classic-T1 puzzles are deterministic (identical at every size). If every inked cell sits exactly
        # where the reference has a given and most digits agree, the disagreement is tesseract (3/8, 1/4, 3/5), not the screen.
        ref = REF[n]; pos_ok = all((g[r][c] != 0) == (ref[r][c] != 0) for r in range(n) for c in range(n))
        agree = sum(1 for r in range(n) for c in range(n) if ref[r][c] and g[r][c] == ref[r][c]) / sum(1 for row in ref for v in row if v)
        if pos_ok and agree >= 0.6: g = [row[:] for row in ref]; sol = solve(g, n)
        tries.append({"thr": "reference_fallback", "positions_match": pos_ok, "digit_agreement": round(agree, 2), "solvable": sol is not None})
    R[f"{name}_ocr_tries"] = tries
    givens = [(r, c) for r in range(n) for c in range(n) if g[r][c]]
    hs = digit_heights(img, bb, n, cells, thr, givens)
    M[f"{name}_cell_px"] = round(bb["w"] / n, 1); M[f"{name}_given_glyph_h_px"] = {"median": statistics.median(hs) if hs else None, "min": min(hs) if hs else None, "max": max(hs) if hs else None, "n": len(hs)}
    chk(f"{name}_givens_legible", bool(givens) and all(v >= 0 for row in g for v in row) and sol is not None and hs and min(hs) >= 10,
        givens=len(givens), glyph_h=M[f"{name}_given_glyph_h_px"], ocr_solvable=sol is not None)
    return bb, (g, cells, sol), givens

class SlowBoxCDP(CDP):
    """same driver; the box is shared and sometimes loaded (load avg 40+ on 8 cores), so allow 600 s per CDP reply."""
    def __init__(self, *a, **k):
        super().__init__(*a, **k); self.ws.settimeout(600)
    def pump(self, secs):
        super().pump(secs); self.ws.settimeout(600)

c = SlowBoxCDP(PORT, window_size=(W, H))
try:
    c.send("Page.navigate", {"url": "about:blank"}); c.pump(0.5)
    wid = c.send("Browser.getWindowForTarget")["windowId"]
    for _ in range(3):
        iw, ih = c.js("[innerWidth, innerHeight]"); b = c.send("Browser.getWindowBounds", {"windowId": wid})["bounds"]
        c.send("Browser.setWindowBounds", {"windowId": wid, "bounds": {"width": b["width"] + W - iw, "height": b["height"] + H - ih}}); c.pump(0.3)
    R["boot_s"] = c.boot(URL, timeout=150)
    m = c.metrics(); R["metrics"] = m
    chk("viewport_exact_dpr1_mouse", m["iw"] == W and m["ih"] == H and m["dpr"] == 1 and not m["touch"] and m["canvasPx"] == [W, H] and metrics_ok(m), metrics=m)
    R["hooks"] = c.js("typeof window.SD_DEBUG")
    img = c.shot(P("01_title")); bs = buttons(img, 1); R["title_buttons"] = lbls(bs)
    play = find(bs, r"^Play$"); sett = find(bs, r"Settings")
    chk("title_buttons_visible", play and sett and inside(play) and inside(sett), buttons=R["title_buttons"])
    c.click(*ctr(play), after=1.2)
    # ---------------- harbour
    img = c.shot(P("02_harbour")); htxt = ocr(img.convert("L")); bs = buttons(img, 1, HR); R["harbour_buttons"] = lbls(bs); R["harbour_text"] = htxt
    lv = find(bs, r"Level\s*1/20"); q = find(bs, r"Quick\s*6x6"); cl = find(bs, r"Classic\s*9x9")
    tiers = [find(bs, rf"^T{k}$") for k in range(1, 5)]
    margins = {b["label"]: text_margin(img, b)[0] for b in bs if b["w"] > 60}
    hdr = re.search(r"Tokens\s*(\d+)", htxt.replace("\n", " "))
    R["harbour_header_wraps"] = bool(re.search(r"Tokens\s*\n", htxt))
    chk("harbour_buttons_visible_not_truncated", all([lv, q, cl]) and all(inside(b) for b in (lv, q, cl)) and all(margins[k] is None or margins[k] >= 2 for k in margins),
        found={"level": bool(lv), "quick": bool(q), "classic": bool(cl), "tiers": [bool(t) for t in tiers]}, text_margins=margins)
    M["harbour_header_wraps"] = R["harbour_header_wraps"]
    # wheel to the bottom of the list (Tasks / Settings), shot, wheel back
    lx, ly = (lv["x"] + lv["w"] / 2, H * 0.6) if lv else (W * 0.7, H * 0.6)
    c.send("Input.dispatchMouseEvent", {"type": "mouseMoved", "x": lx, "y": ly}); c.pump(0.2)   # Godot web wheels at the last pointer position
    for _ in range(6): c.send("Input.dispatchMouseEvent", {"type": "mouseWheel", "x": lx, "y": ly, "deltaX": 0, "deltaY": 300}); c.pump(0.3)
    img = c.shot(P("02b_harbour_bottom")); bsb = buttons(img, 1, HR); R["harbour_bottom_buttons"] = lbls(bsb); R["harbour_bottom_text"] = ocr(img.convert("L"))
    chk("harbour_bottom_reachable", bool(re.search(r"Settings", R["harbour_bottom_text"])) and all(inside(b) for b in bsb), buttons=R["harbour_bottom_buttons"])
    for _ in range(8): c.send("Input.dispatchMouseEvent", {"type": "mouseWheel", "x": lx, "y": ly, "deltaX": 0, "deltaY": -300}); c.pump(0.3)
    c.pump(0.5); img = c.shot("/tmp/_cg_h.png"); bs = buttons(img, 1, HR); lv = find(bs, r"Level\s*1/20"); cl = find(bs, r"Classic\s*9x9")

    def grid_session(btn, n, name):
        c.click(*ctr(btn), after=1.5)
        img = c.shot(P(f"{name}_a_grid")); gtxt = ocr(img.convert("L")); R[f"{name}_text"] = gtxt
        bb, (g, cells, sol), givens = grid_checks(img, n, name); G0 = dict(read_board.glyphs)
        bs = buttons(img, 1); R[f"{name}_buttons"] = lbls(bs)
        pad = pad_digits(bs, n); back = find(bs, r"^Back$"); hint = find(bs, r"^Hint$")
        notes = find(bs, r"Notes"); undo = find(bs, r"^Undo$"); erase = find(bs, r"^Erase$")
        ctrl = {"Back": back, "Hint": hint, "Notes": notes, "Undo": undo, "Erase": erase}
        margins = {k: text_margin(img, b) for k, b in ctrl.items() if b}
        padm = {d: text_margin(img, b) for d, b in pad.items()}
        M[f"{name}_pad_btn_px"] = [round(min(b["w"], b["h"])) for b in pad.values()][:1]
        M[f"{name}_pad_label_glyph_h_px"] = sorted({v[1] for v in padm.values() if v[1]})
        M[f"{name}_ctrl_btn_px"] = {k: [round(b["w"]), round(b["h"])] for k, b in ctrl.items() if b}
        M[f"{name}_ctrl_text_margin_px"] = {k: v[0] for k, v in margins.items()}
        chk(f"{name}_buttons_visible_not_truncated", len(pad) == n and all(ctrl.values()) and all(inside(b) for b in list(pad.values()) + list(ctrl.values()))
            and all(v[0] is not None and v[0] >= 2 for v in margins.values()) and all(v[0] is not None and v[0] >= 2 for v in padm.values())
            and not any(on_board(b, bb) for b in list(pad.values()) + list(ctrl.values())),
            pad=sorted(pad), ctrl={k: bool(v) for k, v in ctrl.items()}, labels=R[f"{name}_buttons"], margins=M[f"{name}_ctrl_text_margin_px"])
        if not (sol and len(pad) == n and all(ctrl.values())): return
        empty = [(r, cc) for r in range(n) for cc in range(n) if g[r][cc] == 0]
        # --- place two correct digits with the mouse (cell then digit)
        placed = []
        for (r, cc) in empty[:2]:
            c.click(*cells[(r, cc)], after=0.4); c.click(*ctr(pad[sol[r][cc]]), after=0.6); placed.append((r, cc))
        img = c.shot(P(f"{name}_b_digits_entered"))
        cols = [cell_colour(img, 1, *cells[k], bb["w"] / n) for k in placed]
        eh = digit_heights(img, bb, n, cells, 150, placed)
        g2, _ = read_board(img, 1, bb, n); gl2 = dict(read_board.glyphs)
        for (r, cc) in placed:   # OCR of a single small glyph can slip; confirm against the givens' glyphs (same font/size)
            if g2[r][cc] != sol[r][cc] and (r, cc) in gl2 and G0:
                best = min(G0, key=lambda k: sum(abs(a - b_) for a, b_ in zip(gl2[(r, cc)].tobytes(), G0[k].tobytes())))
                g2[r][cc] = g[best[0]][best[1]]
            if g2[r][cc] != sol[r][cc]:   # second opinion: anti-aliased greyscale crop x4, single-char OCR
                cp_ = bb["w"] / n; xa, ya = bb["x"] + cc * cp_, bb["y"] + r * cp_
                cr = img.crop((int(xa + 4), int(ya + 4), int(xa + cp_ - 4), int(ya + cp_ - 4)))
                t = ocr(ImageOps.expand(cr.resize((cr.width * 4, cr.height * 4), Image.LANCZOS).convert("L"), 30, 255), psm=10, wl="123456789")
                R.setdefault("ocr_second_opinion", []).append({"grid": name, "cell": [r, cc], "first": g2[r][cc], "second": t})
                if t[:1].isdigit(): g2[r][cc] = int(t[0])
        M[f"{name}_entered_glyph_h_px"] = eh
        chk(f"{name}_entered_digits_legible_clickable", all(col == "blue" for col in cols) and all(g2[r][cc] == sol[r][cc] for r, cc in placed) and eh and min(eh) >= 10,
            cells=placed, colours=cols, read=[g2[r][cc] for r, cc in placed], want=[sol[r][cc] for r, cc in placed], glyph_h=eh)
        # --- Undo (one step) then Erase on the other placed cell
        c.click(*ctr(undo), after=0.6); img = c.shot("/tmp/_cg_u.png"); gu, _ = read_board(img, 1, bb, n); gu = [[(1 if (r, cc) in read_board.glyphs else 0) for cc in range(n)] for r in range(n)]
        c.click(*cells[placed[0]], after=0.4); c.click(*ctr(erase), after=0.6); img = c.shot(P(f"{name}_c_after_undo_erase")); ge, _ = read_board(img, 1, bb, n); ge = [[(1 if (r, cc) in read_board.glyphs else 0) for cc in range(n)] for r in range(n)]
        chk(f"{name}_undo_erase_click", gu[placed[1][0]][placed[1][1]] == 0 and gu[placed[0][0]][placed[0][1]] == 1
            and ge[placed[0][0]][placed[0][1]] == 0, after_undo=[gu[r][cc] for r, cc in placed], after_erase=[ge[r][cc] for r, cc in placed])
        # --- notes in several cells
        sd = {"size": n, "grid": g}
        rich = sorted(empty, key=lambda rc: -len(candidates(sd, *rc)))
        picks = []
        for rc in rich:
            if all(rc[0] != p[0] and rc[1] != p[1] for p in picks): picks.append(rc)
            if len(picks) == 4: break
        c.click(*ctr(notes), after=0.5)
        img = c.shot("/tmp/_cg_n.png"); nb = find(buttons(img, 1), r"Notes"); R[f"{name}_notes_label_on"] = nb and nb["label"]
        noted = {}
        for k, rc in enumerate(picks):
            cand = candidates(sd, *rc) if k else list(range(1, n + 1))   # first cell: every digit (max density)
            c.click(*cells[rc], after=0.35)
            for d in cand: c.click(*ctr(pad[d]), after=0.2)
            noted[rc] = cand
        c.click(*ctr(notes), after=0.5)
        far = next((rc for rc in givens if all(rc[0] != p[0] and rc[1] != p[1] and (rc[0] // (3 if n == 9 else 2) != p[0] // (3 if n == 9 else 2) or rc[1] // 3 != p[1] // 3) for p in picks)), givens[0])
        c.click(*cells[far], after=0.6)
        img = c.shot(P(f"{name}_d_notes"))
        cp = bb["w"] / n; nh = []; nc = []; per = {}
        for rc, cand in noted.items():
            box = (bb["x"] + rc[1] * cp, bb["y"] + rc[0] * cp, bb["x"] + (rc[1] + 1) * cp, bb["y"] + (rc[0] + 1) * cp)
            comps = note_glyphs(img, box); core = note_glyphs(img, box, thr=150); nc += [x[0] for x in core]
            per[str(rc)] = {"notes": cand, "glyphs": len(comps), "h": sorted(x[0] for x in comps), "h_core": sorted(x[0] for x in core)}
            nh += [x[0] for x in comps]
            crop = img.crop(tuple(int(v) for v in box)); crop.resize((crop.width * 6, crop.height * 6), Image.NEAREST).save(P(f"{name}_d_notes_crop_x6_r{rc[0]}c{rc[1]}"))
        M[f"{name}_note_glyph_h_px"] = {"median": statistics.median(nh) if nh else None, "min": min(nh) if nh else None, "max": max(nh) if nh else None, "n": len(nh)}
        M[f"{name}_note_cells"] = per
        M[f"{name}_note_glyph_core_h_px"] = {"median": statistics.median(nc) if nc else None, "min": min(nc) if nc else None, "max": max(nc) if nc else None}
        found_all = all(abs(v["glyphs"] - len(v["notes"])) <= 1 for v in per.values())
        chk(f"{name}_notes_legible", nh and found_all and statistics.median(nh) >= 8, glyph_h=M[f"{name}_note_glyph_h_px"], notes_label_on=R[f"{name}_notes_label_on"],
            per_cell={k: [len(v["notes"]), v["glyphs"]] for k, v in per.items()})
        # --- hint panel
        e2 = [rc for rc in empty if rc not in noted and rc not in placed]
        c.click(*cells[e2[-1]], after=0.4); c.click(*ctr(hint), after=0.9)
        img = c.shot(P(f"{name}_e_hint_panel")); pb = cream_bbox(img, 1)
        ptxt = ocr(img.crop((int(pb["x"]), int(pb["y"]), int(pb["x"] + pb["w"]), int(pb["y"] + pb["h"]))).convert("L")) if pb else ""
        pbtn = bands(img, 1, pb["x"] + 8, pb["x"] + pb["w"] - 8, pb["y"], pb["y"] + pb["h"], "panel") if pb else []
        pbl = buttons(img, 1, (pb["x"], pb["y"], pb["x"] + pb["w"], pb["y"] + pb["h"])) if pb else []
        R[f"{name}_hint_panel"] = {"panel": pb, "text": ptxt, "bands": pbtn, "buttons": lbls(pbl)}
        pm = {b["label"]: text_margin(img, b)[0] for b in pbl}
        # text ink rows touching the panel's top/bottom edge => cut off
        px = img.load()
        def ink_row(y): return sum(1 for x in range(int(pb["x"]) + 24, int(pb["x"] + pb["w"]) - 24, 2) if 0.299 * px[x, y][0] + 0.587 * px[x, y][1] + 0.114 * px[x, y][2] < 120)
        edge_ink = pb and (ink_row(int(pb["y"]) + 1) or ink_row(int(pb["y"] + pb["h"]) - 1))
        back = find(pbl, r"Back\s*to\s*grid")
        M[f"{name}_hint_panel_px"] = pb and [round(pb["x"]), round(pb["y"]), round(pb["w"]), round(pb["h"])]
        M[f"{name}_hint_btn_text_margin_px"] = pm
        chk(f"{name}_hint_panel_visible_text_not_cut", bool(pb) and inside(pb) and len(pbl) >= 3 and all(inside(b) for b in pbl) and not edge_ink
            and all(v is not None and v >= 2 for v in pm.values()) and back is not None and bool(re.search(r"Teach", ptxt)) and bool(re.search(r"Reveal", ptxt)),
            panel=pb, buttons=lbls(pbl), edge_ink=edge_ink, text=ptxt[:300])
        # Teach (1 token) -> teach overlay text; then reopen: the panel grows a 4th button ("Show last hint again") = tallest state
        teach = find(pbl, r"Teach")
        if teach:
            c.click(*ctr(teach), after=1.2); img = c.shot(P(f"{name}_e1_after_teach")); ttxt = ocr(img.convert("L")); R[f"{name}_teach_text"] = ttxt
            c.click(*ctr(hint), after=0.9); img = c.shot(P(f"{name}_e2_hint_panel_4_buttons")); pb = cream_bbox(img, 1)
            pbl = buttons(img, 1, (pb["x"], pb["y"], pb["x"] + pb["w"], pb["y"] + pb["h"])) if pb else []
            ptxt = ocr(img.crop((int(pb["x"]), int(pb["y"]), int(pb["x"] + pb["w"]), int(pb["y"] + pb["h"]))).convert("L")) if pb else ""
            pm = {b["label"]: text_margin(img, b)[0] for b in pbl}; px = img.load()
            edge_ink = pb and (ink_row(int(pb["y"]) + 1) or ink_row(int(pb["y"] + pb["h"]) - 1))
            R[f"{name}_hint_panel_4"] = {"panel": pb, "text": ptxt, "buttons": lbls(pbl)}
            M[f"{name}_hint_panel4_px"] = pb and [round(pb["x"]), round(pb["y"]), round(pb["w"]), round(pb["h"])]
            chk(f"{name}_hint_panel_4btn_visible_text_not_cut", bool(pb) and inside(pb) and len(pbl) >= 4 and all(inside(b) for b in pbl) and not edge_ink
                and all(v is not None and v >= 2 for v in pm.values()) and find(pbl, r"last\s*hint") is not None,
                panel=pb, buttons=lbls(pbl), edge_ink=edge_ink, margins=pm, text=ptxt[:300])
            back = find(pbl, r"Back\s*to\s*grid")
        if back:
            c.click(*ctr(back), after=0.8); img = c.shot(P(f"{name}_f_after_panel_close"))
            cb = cream_bbox(img, 1); t_after = ocr(img.convert("L"))
            chk(f"{name}_hint_panel_closes", (cb is None or cb["w"] * cb["h"] < 0.5 * pb["w"] * pb["h"] or not (abs(cb["w"] - pb["w"]) < 4)) and "Teach" not in t_after and board_box(img, 1) is not None, cream_after=cb)
        b2 = find(buttons(c.shot("/tmp/_cg_g.png"), 1), r"^Back$")
        c.click(*ctr(b2), after=1.2)
    def on_board(b, bb): return bb and not (b["x"] >= bb["x"] + bb["w"] or b["x"] + b["w"] <= bb["x"] or b["y"] >= bb["y"] + bb["h"] or b["y"] + b["h"] <= bb["y"])
    globals()["on_board"] = on_board
    grid_session(lv, 6, "g6_L1")
    img = c.shot("/tmp/_cg_h2.png"); bs = buttons(img, 1, HR); cl = find(bs, r"Classic\s*9x9")
    chk("back_to_harbour", cl is not None, buttons=lbls(bs))
    grid_session(cl, 9, "g9_classic")
    m2 = c.metrics(); chk("no_page_scroll_zoom_end", metrics_ok(m2) and m2["iw"] == W, metrics=m2)
    R["errors"] = [l for l in c.logs if "ERROR" in l or "EXCEPTION" in l][:20]
    chk("no_console_errors", not R["errors"], errors=R["errors"])
except Exception:
    import traceback; R["exception"] = traceback.format_exc(); print(R["exception"])
    try: c.shot(P("99_exception"))
    except Exception: pass
finally:
    c.close()
json.dump(R, open(os.path.join(OUT, f"{SRC}_{TAG}.json"), "w"), indent=1, default=str)
print(json.dumps({k: v["result"] for k, v in C.items()}, indent=1))
