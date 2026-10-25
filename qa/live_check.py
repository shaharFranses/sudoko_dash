#!/usr/bin/env python3
"""Live check of the deployed Sudoku Dash (release build: no SD_DEBUG/SD_QA hooks).
Reuses the raw-CDP Chrome driver from qa/mobile_qa.py (fresh profile, real Chrome, touch-only on mobile).
Without hooks, state is read from screenshots: button rectangles by colour, labels/text by tesseract OCR.
Usage: /tmp/qav/bin/python qa/live_check.py mobile|desktop [url]"""
import json, os, re, subprocess, sys, tempfile, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mobile_qa import CDP, metrics_ok, on_screen
from PIL import Image, ImageOps

URL = sys.argv[2] if len(sys.argv) > 2 else "https://shaharfranses.github.io/sudoko_dash/"
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "results", "live_b5479ff")
os.makedirs(OUT, exist_ok=True)


def ocr(img, psm=6, wl=None):
    with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as f: img.save(f.name)
    a = ["tesseract", f.name, "-", "--psm", str(psm)] + (["-c", f"tessedit_char_whitelist={wl}"] if wl else [])
    r = subprocess.run(a, capture_output=True, text=True).stdout.strip(); os.unlink(f.name); return r


def ink(crop, light_text):   # -> black text on white for OCR
    g = ImageOps.grayscale(crop)
    return g.point(lambda v: 0 if (v > 200 if light_text else v < 110) else 255)


def buttons(img, dpr, region=None):
    """Connected components of button colour (slate / panel gray) -> CSS rects with OCR'd labels."""
    W, H = img.size; px = img.load(); st = max(1, int(dpr))
    x0, y0, x1, y1 = region or (0, 0, W / dpr, H / dpr)
    gx0, gy0, gx1, gy1 = int(x0 * dpr) // st, int(y0 * dpr) // st, int(x1 * dpr) // st, int(y1 * dpr) // st
    def isb(p):
        lum = 0.299 * p[0] + 0.587 * p[1] + 0.114 * p[2]; return 75 < lum < 170 and max(p) - min(p) < 32
    m = {}
    for gy in range(gy0, min(gy1, H // st)):
        for gx in range(gx0, min(gx1, W // st)):
            m[(gx, gy)] = isb(px[gx * st, gy * st])
    seen = set(); out = []
    for k, v in m.items():
        if not v or k in seen: continue
        stack = [k]; seen.add(k); xs = []; ys = []
        while stack:
            a, b = stack.pop(); xs.append(a); ys.append(b)
            for n in ((a + 1, b), (a - 1, b), (a, b + 1), (a, b - 1)):
                if m.get(n) and n not in seen: seen.add(n); stack.append(n)
        r = {"x": min(xs) * st / dpr, "y": min(ys) * st / dpr, "w": (max(xs) - min(xs) + 1) * st / dpr, "h": (max(ys) - min(ys) + 1) * st / dpr}
        if r["w"] >= 28 and r["h"] >= 28 and r["w"] < 0.95 * W / dpr and len(xs) > 0.6 * (r["w"] * r["h"] * dpr * dpr / st / st):
            crop = img.crop((int(r["x"] * dpr) + 3, int(r["y"] * dpr) + 3, int((r["x"] + r["w"]) * dpr) - 3, int((r["y"] + r["h"]) * dpr) - 3))
            r["label"] = ocr(ink(crop, True), psm=7)
            out.append(r)
    return sorted(out, key=lambda r: (round(r["y"] / 8), r["x"]))


def find(bs, pat):
    return next((b for b in bs if re.search(pat, b["label"], re.I)), None)


def board_box(img, dpr):
    px = img.load(); W, H = img.size; xs = []; ys = []
    for y in range(0, H, 3):
        for x in range(0, W, 3):
            if px[x, y] == (255, 253, 247): xs.append(x); ys.append(y)
    if len(xs) < 200: return None
    return {"x": min(xs) / dpr, "y": min(ys) / dpr, "w": (max(xs) - min(xs)) / dpr, "h": (max(ys) - min(ys)) / dpr, "frac": len(xs) * 9 / (W * H)}


def _glyph(crop, thr=150):   # dark navy givens (~44), blue/red entries (~100) are ink; cell highlights (>= ~180) are not
    g = ImageOps.grayscale(crop).point(lambda v: 0 if v < thr else 255)
    bb = ImageOps.invert(g).getbbox()
    return g.crop(bb) if bb else None


def read_board(img, dpr, bb, n, thr=150):
    """Given/entered digits per cell: tesseract on the normalised glyph; anything it can't read is matched
    against the glyphs it did read (same font, same size) by pixel difference."""
    cp = bb["w"] / n; g = []; cells = {}; glyphs = {}
    for r in range(n):
        row = []
        for c in range(n):
            x0, y0 = bb["x"] + c * cp, bb["y"] + r * cp
            crop = img.crop((int((x0 + cp * 0.15) * dpr), int((y0 + cp * 0.15) * dpr), int((x0 + cp * 0.85) * dpr), int((y0 + cp * 0.85) * dpr)))
            gl = _glyph(crop, thr); d = 0
            if gl is not None and gl.width * gl.height > 30:
                s_ = 64 / gl.height
                big = gl.resize((max(1, int(gl.width * s_)), 64), Image.LANCZOS).point(lambda v: 0 if v < 128 else 255)
                t = ocr(ImageOps.expand(big, 40, 255), psm=10, wl="123456789")
                d = int(t[0]) if t[:1].isdigit() else -1
                glyphs[(r, c)] = gl.resize((24, 36))
            row.append(d); cells[(r, c)] = (x0 + cp / 2, y0 + cp / 2)
        g.append(row)
    known = {k: g[k[0]][k[1]] for k in glyphs if g[k[0]][k[1]] > 0}
    for (r, c), gl in glyphs.items():
        if g[r][c] == -1 and known:
            best = min(known, key=lambda k: sum(abs(a - b) for a, b in zip(gl.tobytes(), glyphs[k].tobytes())))
            g[r][c] = known[best]
    read_board.glyphs = glyphs
    return g, cells


def solve(g, n):
    bw, bh = (3, 2) if n == 6 else (3, 3)
    g = [row[:] for row in g]
    def ok(r, c, d):
        if d in g[r] or any(g[k][c] == d for k in range(n)): return False
        br, bc = r // bh * bh, c // bw * bw
        return all(g[i][j] != d for i in range(br, br + bh) for j in range(bc, bc + bw))
    def bt():
        for r in range(n):
            for c in range(n):
                if g[r][c] == 0:
                    for d in range(1, n + 1):
                        if ok(r, c, d):
                            g[r][c] = d
                            if bt(): return True
                            g[r][c] = 0
                    return False
        return True
    return g if bt() else None


def cell_colour(img, dpr, cx, cy, cp):
    crop = img.crop((int((cx - cp * 0.3) * dpr), int((cy - cp * 0.3) * dpr), int((cx + cp * 0.3) * dpr), int((cy + cp * 0.3) * dpr)))
    blue = sum(1 for p in crop.getdata() if abs(p[0] - 0x2a) < 40 and abs(p[1] - 0x6f) < 40 and abs(p[2] - 0xdb) < 40)
    red = sum(1 for p in crop.getdata() if abs(p[0] - 0xd2) < 40 and abs(p[1] - 0x3c) < 40 and abs(p[2] - 0x3c) < 40)
    return "blue" if blue > red and blue > 30 else ("red" if red > 30 else "none")


def teach_cells(img, dpr, bb, n):
    cp = bb["w"] / n; px = img.load(); out = []
    for r in range(n):
        for c in range(n):
            x, y = int((bb["x"] + (c + 0.12) * cp) * dpr), int((bb["y"] + (r + 0.12) * cp) * dpr)
            p = px[x, y]
            if abs(p[0] - 0xff) < 12 and abs(p[1] - 0xe3) < 16 and abs(p[2] - 0x8a) < 24: out.append([r, c])
    return out


def tokens_coins(text):
    t = re.search(r"Tokens:?\s*(\d+)", text); c = re.search(r"Coins:?\s*(\d+)", text)
    return (int(t.group(1)) if t else None, int(c.group(1)) if c else None)


def run(mode):
    mobile = mode == "mobile"
    w, h, dpr = (390, 844, 3) if mobile else (1280, 800, 1)
    tag = "390x844" if mobile else "desktop_1280x800"
    R = {"url": URL, "viewport": tag, "checks": {}}; C = R["checks"]
    def chk(name, ok, **ev): C[name] = {"result": "PASS" if ok else "FAIL", **ev}; print(name, C[name]["result"], ev if not ok else ""); return ok
    P = lambda n: os.path.join(OUT, f"{tag}_{n}.png")
    c = CDP(9561 if mobile else 9562, window_size=None if mobile else (1280, 800))
    act = (lambda x, y, after=0.6: c.tap(x, y, after=after)) if mobile else (lambda x, y, after=0.6: c.click(x, y, after=after))
    def ctr(b): return b["x"] + b["w"] / 2, b["y"] + b["h"] / 2
    try:
        if mobile: c.emulate(w, h, dpr)
        else:
            c.send("Page.navigate", {"url": "about:blank"}); c.pump(0.5)
            wid = c.send("Browser.getWindowForTarget")["windowId"]
            for _ in range(3):
                iw, ih = c.js("[innerWidth, innerHeight]"); b = c.send("Browser.getWindowBounds", {"windowId": wid})["bounds"]
                c.send("Browser.setWindowBounds", {"windowId": wid, "bounds": {"width": b["width"] + 1280 - iw, "height": b["height"] + 800 - ih}}); c.pump(0.3)
        try: R["boot_s"] = c.boot(URL, timeout=120); booted = True
        except RuntimeError: booted = False
        img = c.shot(P("01_title")); m = c.metrics(); R["metrics_boot"] = m
        title_txt = ocr(img.convert("L"))
        chk("boots_to_title", booted and "Sudoku Dash" in title_txt, boot_s=R.get("boot_s"), first_logs=c.logs[:3])
        R["hooks"] = c.js("({SD_DEBUG: typeof window.SD_DEBUG, SD_QA: typeof window.SD_QA, __sdDump: typeof window.__sdDump})")
        chk("debug_hooks_absent", R["hooks"] == {"SD_DEBUG": "undefined", "SD_QA": "undefined", "__sdDump": "undefined"}, hooks=R["hooks"])
        chk("viewport_size", m["iw"] == w and m["ih"] == h and m["dpr"] == dpr and m["touch"] == mobile, metrics=m)
        bs = buttons(img, dpr); R["title_buttons"] = [b["label"] for b in bs]
        play = find(bs, r"Play"); act(*ctr(play), after=1.2)
        img = c.shot(P("02_harbour")); htxt = ocr(img.convert("L")); R["harbour_text"] = htxt[:300]
        bs = buttons(img, dpr); R["harbour_buttons"] = [b["label"] for b in bs]
        chk("play_opens_harbour", "Harbour" in htxt and find(bs, r"Level\s*1/20") is not None, buttons=R["harbour_buttons"])
        m2 = c.metrics()
        if mobile:
            # drag 120 px starting on "Quick 6x6": list scrolls, nothing pressed
            q = find(bs, r"Quick"); lv0 = find(bs, r"Level\s*1/20")
            c.drag(q["x"] + q["w"] * 0.3, q["y"] + q["h"] / 2, 0, -120, steps=15); c.pump(0.6)
            img2 = c.shot(P("03_harbour_after_button_drag")); bs2 = buttons(img2, dpr); htxt2 = ocr(img2.convert("L"))
            q2 = find(bs2, r"Quick"); bb_ = board_box(img2, dpr)
            R["drag"] = {"quick_y": [q["y"], q2 and q2["y"]], "buttons_after": [b["label"] for b in bs2], "board": bb_}
            chk("button_drag_scrolls_no_press", q2 is not None and abs((q["y"] - q2["y"]) - 120) <= 3 and "Harbour" in htxt2 or (q2 is not None and abs((q["y"] - q2["y"]) - 120) <= 3 and not bb_),
                quick_y=R["drag"]["quick_y"], board=bb_)
            # back to the top (drag down from a button), then tap Level 1
            b0 = bs2[-1]; c.drag(b0["x"] + b0["w"] * 0.3, b0["y"] + b0["h"] / 2, 0, 300, steps=20); c.pump(0.6)
            img = c.shot(P("03b_harbour_back_top")); bs = buttons(img, dpr)
            m2 = c.metrics()
        chk("no_zoom_no_scroll", metrics_ok(m) and metrics_ok(m2) and metrics_ok(c.metrics()), boot={k: m[k] for k in ("sx", "sy", "vvScale", "sh", "ih", "sw", "iw")})
        lv = find(bs, r"Level\s*1/20"); act(*ctr(lv), after=1.5)
        img = c.shot(P("04_L1_grid")); bb = board_box(img, dpr); gtxt = ocr(img.convert("L"))
        n = 6
        g, cells = read_board(img, dpr, bb, n, thr=110) if bb else (None, None)   # givens only (dark): tighter threshold
        glyphs0 = dict(read_board.glyphs) if g else {}
        R["board_box"] = bb; R["board_ocr"] = g
        sq = bb and abs(bb["w"] - bb["h"]) < 4
        chk("level1_opens_6x6_grid", bool(bb) and sq and "Level 1/20" in gtxt and g is not None and all(v >= 0 for row in g for v in row)
            and sum(1 for row in g for v in row if v) >= 6, board=bb, givens=sum(1 for row in g for v in row if v) if g else None)
        pad = buttons(img, dpr); R["grid_buttons"] = [b["label"] for b in pad]
        if not mobile:
            inside = on_screen(bb, c.metrics()) and all(on_screen(b, c.metrics()) for b in pad)
            px_ = img.load(); yb = int(bb["y"] + bb["h"])
            border = [y for y in range(yb - 2, min(800, yb + 5)) if sum(1 for x in range(int(bb["x"]) + 5, int(bb["x"] + bb["w"]) - 5, 9)
                      if abs(px_[x, y][0] - 0x2d) < 25 and abs(px_[x, y][2] - 0x5a) < 25) > 0.7 * (bb["w"] - 10) / 9]
            chk("level1_not_clipped", inside and bool(border) and {"Undo", "Erase"} <= {b["label"] for b in pad} | {"Undo" if find(pad, "Undo") else "", "Erase" if find(pad, "Erase") else ""},
                board=bb, bottom_border_rows=border, buttons=R["grid_buttons"])
        # place a digit: solve from the OCR'd givens, tap an empty cell, then its digit
        sol = solve(g, n) if g else None; R["solution_found"] = sol is not None
        empty = [(r, cc) for r in range(n) for cc in range(n) if g and g[r][cc] == 0]
        (r1, c1) = empty[0]; d = sol[r1][c1] if sol else 1
        act(*cells[(r1, c1)], after=0.5)
        digit = next(b for b in pad if b["label"].strip() == str(d))
        act(*ctr(digit), after=0.8)
        img = c.shot(P("05_digit_placed")); col = cell_colour(img, dpr, *cells[(r1, c1)], bb["w"] / n)
        g2, _ = read_board(img, dpr, bb, n); gl2 = read_board.glyphs
        newly_inked = sorted([list(k) for k in gl2 if g[k[0]][k[1]] == 0])
        lost_ink = sorted([[r, cc] for r in range(n) for cc in range(n) if g[r][cc] != 0 and (r, cc) not in gl2])
        # identity of the new digit: OCR, else nearest given glyph of the initial board
        tgt = g2[r1][c1]
        if tgt != d and (r1, c1) in gl2 and glyphs0:
            best = min(glyphs0, key=lambda k: sum(abs(a - b) for a, b in zip(gl2[(r1, c1)].tobytes(), glyphs0[k].tobytes())))
            tgt = g[best[0]][best[1]]
        R["placement"] = {"cell": [r1, c1], "digit": d, "colour": col, "newly_inked": newly_inked, "lost_ink": lost_ink, "read_digit": tgt}
        chk("tap_cell_then_digit_places_it", newly_inked == [[r1, c1]] and not lost_ink and tgt == d and col == "blue",
            cell=[r1, c1], digit=d, colour=col, read=tgt, newly_inked=newly_inked)
        if mobile:
            def open_hint():
                hb = find(buttons(c.shot("/tmp/_live_g.png"), dpr), r"^Hint$"); act(*ctr(hb), after=0.8)
                im = c.shot("/tmp/_live_p.png"); t = ocr(im.convert("L")); bs_ = buttons(im, dpr)
                return im, tokens_coins(t), bs_
            im, tc0, pb = open_hint(); im.save(P("06_hint_panel"))
            teach = find(pb, r"Teach"); act(*ctr(teach), after=1.0)
            im1 = c.shot(P("07_teach_1")); s1 = teach_cells(im1, dpr, bb, n); lab1 = ocr(im1.crop((0, int((bb["y"] + bb["h"]) * dpr), im1.size[0], im1.size[1])).convert("L"))
            im, tc1, pb = open_hint(); im.save(P("08_hint_panel_after_teach_1"))
            R["reshow_button_shown"] = find(pb, r"last hint") is not None
            teach = find(pb, r"Teach"); act(*ctr(teach), after=1.0)
            im2 = c.shot(P("09_teach_2")); s2 = teach_cells(im2, dpr, bb, n)
            im, tc2, pb = open_hint(); im.save(P("10_hint_panel_after_teach_2"))
            rs = find(pb, r"last hint"); act(*ctr(rs), after=1.0)
            im3 = c.shot(P("11_after_reshow")); s3 = teach_cells(im3, dpr, bb, n)
            im, tc3, pb = open_hint(); im.save(P("12_hint_panel_after_reshow"))
            bk = find(pb, r"Back to grid"); act(*ctr(bk), after=0.6)
            R["teach"] = {"tokens_coins": [tc0, tc1, tc2, tc3], "teach1_cells": s1, "teach2_cells": s2, "reshow_cells": s3}
            chk("teach_charged_once", tc0[0] is not None and tc1[0] == tc0[0] - 1 and tc1[1] == tc0[1], tokens_coins=[tc0, tc1])
            chk("second_teach_different", tc2[0] == tc1[0] - 1 and s1 and s2 and s1 != s2, teach1=s1, teach2=s2, tokens=[tc1, tc2])
            chk("show_last_hint_free", R["reshow_button_shown"] and tc3 == tc2 and s3 == s2, tokens_coins=[tc2, tc3], reshow_cells=s3)
        R["errors"] = [l for l in c.logs if "ERROR" in l or "EXCEPTION" in l][:20]
        chk("no_console_errors", not R["errors"], errors=R["errors"])
    except Exception:
        import traceback; R["exception"] = traceback.format_exc(); print(R["exception"])
        try: c.shot(P("99_exception"))
        except Exception: pass
    finally:
        c.close()
    json.dump(R, open(os.path.join(OUT, f"live_{tag}.json"), "w"), indent=1, default=str)
    print(json.dumps({k: v["result"] for k, v in C.items()}, indent=1))


if __name__ == "__main__":
    run(sys.argv[1])
