#!/usr/bin/env python3
"""QA run 10 extra modes (art build): desktop | cg WxH | visual | landscape | release.
Usage: /tmp/qav/bin/python qa/run10_extra.py <mode> [WxH] <cdp_port>"""
import os, sys, json, re, time, statistics, base64, io
import run10 as R10            # sets env + monkeypatches mobile_qa
import mobile_qa as M
import ocr_locate as O
from PIL import Image, ImageChops, ImageOps

OUT = M.OUT; SH = os.path.join(OUT, "shots"); os.makedirs(SH, exist_ok=True)
WT = "/tmp/wt_ede4bfd"
RELEASE_URL = os.environ.get("QA_RELEASE_URL", "http://127.0.0.1:8071/ede4bfd/index.html")

# ---------------------------------------------------------------- colour science
def _lin(v):
    v /= 255.0; return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4
def rel_lum(c): return 0.2126 * _lin(c[0]) + 0.7152 * _lin(c[1]) + 0.0722 * _lin(c[2])
def contrast(a, b):
    la, lb = rel_lum(a), rel_lum(b); hi, lo = max(la, lb), min(la, lb); return round((hi + 0.05) / (lo + 0.05), 2)
def hexc(c): return "#%02X%02X%02X" % tuple(int(round(v)) for v in c[:3])

def ink_and_bg(crop):
    """bg = most common colour; ink = mean of the 25% of pixels farthest from bg (glyph core), plus the single farthest."""
    px = list(crop.getdata())
    from collections import Counter
    bg = Counter(px).most_common(1)[0][0]
    d = sorted(((abs(p[0] - bg[0]) + abs(p[1] - bg[1]) + abs(p[2] - bg[2]), p) for p in px), reverse=True)
    far = [p for dd, p in d if dd > 0.6 * d[0][0]]
    core = far[:max(1, len(far) // 2)]
    ink = tuple(sum(p[i] for p in core) / len(core) for i in range(3))
    return ink, bg, d[0][1]

def components(crop, thr=170):
    """8-connected components of pixels with luminance < thr -> [(h, w, n)] in px."""
    g = ImageOps.grayscale(crop); W, H = g.size; px = g.load(); seen = set(); out = []
    for y in range(H):
        for x in range(W):
            if px[x, y] < thr and (x, y) not in seen:
                st = [(x, y)]; seen.add((x, y)); xs = []; ys = []
                while st:
                    a, b = st.pop(); xs.append(a); ys.append(b)
                    for da in (-1, 0, 1):
                        for db in (-1, 0, 1):
                            u, v = a + da, b + db
                            if 0 <= u < W and 0 <= v < H and px[u, v] < thr and (u, v) not in seen: seen.add((u, v)); st.append((u, v))
                if len(xs) >= 3: out.append((max(ys) - min(ys) + 1, max(xs) - min(xs) + 1, len(xs)))
    return out

def cell_box(geo, r, cc):
    return (geo["ox"] + cc * geo["cp"], geo["oy"] + r * geo["cp"], geo["ox"] + (cc + 1) * geo["cp"], geo["oy"] + (r + 1) * geo["cp"])

def crop_css(img, box, dpr, ins=0):
    return img.crop(tuple(int(round((v + (ins if i < 2 else -ins)) * dpr)) for i, v in enumerate(box)))

def glyph_h(img, geo, r, cc, dpr, thr=170):
    comps = components(crop_css(img, cell_box(geo, r, cc), dpr, ins=max(2.0, 3 / dpr * 1.0) if dpr < 2 else 2), thr)
    comps = [x for x in comps if x[0] >= 3]
    return comps

def window(c, W, H):
    c.send("Page.navigate", {"url": "about:blank"}); c.pump(0.5)
    wid = c.send("Browser.getWindowForTarget")["windowId"]
    for _ in range(4):
        iw, ih = c.js("[innerWidth, innerHeight]"); b = c.send("Browser.getWindowBounds", {"windowId": wid})["bounds"]
        if iw == W and ih == H: break
        c.send("Browser.setWindowBounds", {"windowId": wid, "bounds": {"width": b["width"] + W - iw, "height": b["height"] + H - ih}}); c.pump(0.3)

def ctr(r): return (r["x"] + r["w"] / 2, r["y"] + r["h"] / 2)

def button_text_check(c, img, dpr, name, expect):
    """named Godot button: single-line OCR of its inset interior + horizontal ink margin to the rect edge, measured
    in the middle 40% rows (corners/border excluded). margin < 2 CSS px = text touching the edge = possible clip."""
    from collections import Counter
    r = c.rect(name)
    if not r: return {"name": name, "found": False}
    ins = 4
    band = crop_css(img, (r["x"] + ins, r["y"] + 0.3 * r["h"], r["x"] + r["w"] - ins, r["y"] + 0.7 * r["h"]), dpr)
    fill = Counter(band.getdata()).most_common(1)[0][0]
    bp = band.load(); BW, BH = band.size
    cols = [x for x in range(BW) if any(abs(bp[x, y][0] - fill[0]) + abs(bp[x, y][1] - fill[1]) + abs(bp[x, y][2] - fill[2]) > 90 for y in range(BH))]
    margin = None if not cols else round(min(cols[0], BW - 1 - cols[-1]) / dpr + ins, 1)
    inner = crop_css(img, (r["x"] + ins, r["y"] + ins, r["x"] + r["w"] - ins, r["y"] + r["h"] - ins), dpr)
    k = 3.0 / dpr; inner = inner.resize((max(1, int(inner.width * k)), max(1, int(inner.height * k))), Image.LANCZOS)
    g = ImageOps.grayscale(inner); lum_fill = 0.299 * fill[0] + 0.587 * fill[1] + 0.114 * fill[2]
    m = g.point(lambda v: 0 if v < 120 else 255) if lum_fill > 150 else g.point(lambda v: 0 if v > 200 else 255)
    m = ImageOps.expand(m, 20, 255)
    txt = " ".join(O._tsv(m, 7)[i]["text"] for i in range(len(O._tsv(m, 7))))
    norm = lambda s: re.sub(r"[^a-z0-9:]", "", s.lower().replace("0", "o"))
    ok = norm(expect) in norm(txt) if expect else True
    return {"name": name, "found": True, "rect": {kk: round(v, 1) for kk, v in r.items()}, "ocr": txt, "expect": expect, "text_ok": ok,
            "ink_margin_css": margin, "ink_w_css": None if not cols else round((cols[-1] - cols[0] + 1) / dpr, 1)}

# ---------------------------------------------------------------- 3/4: desktop 1280x800 + hint smoke
def run_desktop(port):
    W, H = 1280, 800; R = {"checks": {}}; C = R["checks"]
    def chk(n, ok, **ev): C[n] = {"result": "PASS" if ok else "FAIL", **ev}; print(n, C[n]["result"], json.dumps(ev, default=str)[:300]); return ok
    S = lambda n: os.path.join(SH, f"desktop_{n}.png")
    c = M.CDP(port, window_size=(W, H))
    try:
        window(c, W, H); R["boot_s"] = c.boot(M.DEBUG_URL); m = c.metrics(); R["metrics"] = m
        chk("desktop_viewport", m["iw"] == W and m["ih"] == H and m["dpr"] == 1 and not m["touch"] and M.metrics_ok(m), metrics=m)
        c.shot(S("01_title"))
        pr = c.rect("PlayButton"); c.click(*ctr(pr), after=1.0)
        img = c.shot(S("02_harbour")); hs = c.rect("HarbourScroll"); hv = c.rect("HarbourView")
        hb = R10.harbour_buttons(img, 1, hs["x"] + 4, hs["x"] + hs["w"] - 14, hs["y"], min(hs["y"] + hs["h"], H))
        R["harbour_buttons"] = [(b["label"], round(b["x"]), round(b["y"]), round(b["w"]), round(b["h"])) for b in hb]
        chk("desktop_harbour_not_clipped", M.on_screen(hv, m) and hs["x"] + hs["w"] <= W + 0.5 and any("Level" in b["kind"] for b in hb)
            and all(M.on_screen(b, m) for b in hb if b["y"] + b["h"] <= H), harbour_view=hv, scroll=hs, buttons=R["harbour_buttons"])
        c.js("SD_DEBUG.startLevel(11)"); c.pump(1.2)
        img = c.shot(S("03_L11"))
        names = ["GridView", "BackButton", "HintButton", "NotesButton", "UndoButton", "EraseButton", "MistakesLabel", "ObjectiveLabel"] + [f"Digit{d}" for d in range(1, 10)]
        rr = {k: c.rect(k) for k in names}; sd = c.dump()["stepDump"]; geo = M.grid_geom(c, 9)
        gb = {"x": geo["ox"], "y": geo["oy"], "w": geo["cp"] * 9, "h": geo["cp"] * 9}; rr["GridCells"] = gb; R["rects"] = rr
        px = img.load()
        def is_box(p): return abs(p[0] - 0x2E) < 30 and abs(p[1] - 0x4A) < 30 and abs(p[2] - 0x5C) < 30
        xs = range(int(gb["x"]) + 6, int(gb["x"] + gb["w"]) - 6, 5); ys = range(int(gb["y"]) + 6, int(gb["y"] + gb["h"]) - 6, 5)
        border = {"top": [y for y in range(max(0, int(gb["y"]) - 3), int(gb["y"]) + 5) if sum(is_box(px[x, y]) for x in xs) > 0.8 * len(xs)],
                  "bottom": [y for y in range(int(gb["y"] + gb["h"]) - 5, min(H, int(gb["y"] + gb["h"]) + 3)) if sum(is_box(px[x, y]) for x in xs) > 0.8 * len(xs)],
                  "left": [x for x in range(max(0, int(gb["x"]) - 3), int(gb["x"]) + 5) if sum(is_box(px[x, y]) for y in ys) > 0.8 * len(ys)],
                  "right": [x for x in range(int(gb["x"] + gb["w"]) - 5, min(W, int(gb["x"] + gb["w"]) + 3)) if sum(is_box(px[x, y]) for y in ys) > 0.8 * len(ys)]}
        R["grid_border"] = border
        texts = {n: button_text_check(c, img, 1, n, e) for n, e in [("BackButton", "Back"), ("HintButton", "Hint"), ("NotesButton", "Notes: OFF"), ("UndoButton", "Undo"), ("EraseButton", "Erase")]}
        R["button_text"] = texts
        chk("desktop_not_clipped", all(M.on_screen(r, m) for r in rr.values()) and all(border.values()) and M.metrics_ok(m),
            off=[k for k, r in rr.items() if not M.on_screen(r, m)], border=border, grid=gb)
        chk("desktop_button_text_not_truncated", all(t["text_ok"] and (t["ink_margin_css"] or 0) >= 2 for t in texts.values()),
            texts={k: [v["ocr"], v["ink_margin_css"]] for k, v in texts.items()})
        # ---- hint smoke (mouse): 3 paid Teaches distinct, 1 token each; free re-show
        c.js("SD_DEBUG.setTokens(3)"); c.pump(0.3)
        steps = []; spent = []
        for k in range(3):
            hb_ = c.rect("HintButton"); c.click(*ctr(hb_), after=0.8)
            img = c.shot(S(f"04_hint_panel_{k+1}")); pb, bb = M.hint_buttons(c, img, 1)
            t = next(b for b in bb if b["kind"] == "Teach"); p0 = c.dump()["profile"]
            c.click(*ctr(t), after=0.9)
            st = c.dump(); steps.append(st["stepDump"]["game_step"]); spent.append([p0["tokens"], st["profile"]["tokens"], p0["coins"], st["profile"]["coins"]])
            c.shot(S(f"05_after_teach_{k+1}"))
        distinct = len({json.dumps(s, sort_keys=True) for s in steps}) == 3 and all(steps)
        chk("hint_paid_teach_new_step_1_token", distinct and all(a - b == 1 and cc == dd for a, b, cc, dd in spent), steps=steps, spent=spent)
        hb_ = c.rect("HintButton"); c.click(*ctr(hb_), after=0.8); c.shot(S("06_panel_with_reshow"))
        rs = c.rect("ReshowHint"); p0 = c.dump()["profile"]
        c.click(*ctr(rs), after=0.9); st = c.dump(); p1 = st["profile"]; c.shot(S("07_after_reshow"))
        chk("hint_reshow_free", rs is not None and p1["tokens"] == p0["tokens"] and p1["coins"] == p0["coins"] and st["stepDump"]["game_step"] == steps[-1]
            and c.layout()["overlay"] == "", tokens=[p0["tokens"], p1["tokens"]], coins=[p0["coins"], p1["coins"]])
        # ---- nothing new -> free re-show: Quick 6x6, fill all but one empty by mouse, Teach (paid) then Teach again (free)
        c.js("SD_DEBUG.show('harbour')"); c.pump(1.0)
        img = c.shot("/tmp/_r10d_h.png"); hs = c.rect("HarbourScroll")
        hb = R10.harbour_buttons(img, 1, hs["x"] + 4, hs["x"] + hs["w"] - 14, hs["y"], min(hs["y"] + hs["h"], H))
        q = next(b for b in hb if "Quick" in b["kind"]); c.click(*ctr(q), after=1.5)
        sd = c.dump()["stepDump"]; n = sd["size"]; geo = M.grid_geom(c, n); sol = sd["solution"]; emp = M.empties(sd)
        R["quick"] = {"size": n, "empties": len(emp)}
        for (r, cc) in emp[:-1]:
            c.click(*M.cell_center(geo, r, cc), after=0.15); dr = c.rect(f"Digit{sol[r][cc]}"); c.click(*ctr(dr), after=0.2)
        c.pump(0.5); sd2 = c.dump()["stepDump"]; left = M.empties(sd2)
        c.js("SD_DEBUG.setTokens(2)"); c.pump(0.3)
        hb_ = c.rect("HintButton"); c.click(*ctr(hb_), after=0.8); img = c.shot(S("08_quick_one_left_panel")); pb, bb = M.hint_buttons(c, img, 1)
        t = next(b for b in bb if b["kind"] == "Teach"); p0 = c.dump()["profile"]; c.click(*ctr(t), after=0.9)
        st1 = c.dump(); p1 = st1["profile"]; s1 = st1["stepDump"]["game_step"]; c.shot(S("09_quick_teach_paid"))
        hb_ = c.rect("HintButton"); c.click(*ctr(hb_), after=0.8); img = c.shot(S("10_quick_panel_again")); pb, bb = M.hint_buttons(c, img, 1)
        t = next(b for b in bb if b["kind"] == "Teach"); c.click(*ctr(t), after=0.9)
        st2 = c.dump(); p2 = st2["profile"]; img = c.shot(S("11_quick_teach_nothing_new"))
        tl = c.rect("TeachLabel"); ttxt = " ".join(l["text"] for l in O.lines(img, 1, (tl["x"], tl["y"] - 4, tl["x"] + tl["w"], tl["y"] + tl["h"] + 4))) if tl else ""
        R["nothing_new"] = {"left": left, "tokens": [p0["tokens"], p1["tokens"], p2["tokens"]], "coins": [p0["coins"], p1["coins"], p2["coins"]], "step1": s1, "step2": st2["stepDump"]["game_step"], "teach_label_ocr": ttxt}
        chk("hint_nothing_new_free_reshow", len(left) == 1 and p1["tokens"] == p0["tokens"] - 1 and p2["tokens"] == p1["tokens"] and p2["coins"] == p1["coins"]
            and re.search(r"no\s*charge", ttxt, re.I) is not None, **R["nothing_new"])
        R["errors"] = [l for l in c.logs if "ERROR" in l or "EXCEPTION" in l][:20]
        chk("desktop_no_console_errors", not R["errors"], errors=R["errors"])
    except Exception:
        import traceback; R["exception"] = traceback.format_exc(); print(R["exception"])
        try: c.shot(S("99_exception"))
        except Exception: pass
    finally: c.close()
    json.dump(R, open(os.path.join(OUT, "desktop.json"), "w"), indent=1, default=str)

# ---------------------------------------------------------------- 5: CrazyGames embed sizes (DPR 1, mouse, debug build)
def run_cg(tag, port):
    W, H = map(int, tag.split("x")); R = {"viewport": tag, "checks": {}, "meas": {}}; C = R["checks"]; MS = R["meas"]
    def chk(n, ok, **ev): C[n] = {"result": "PASS" if ok else "FAIL", **ev}; print(tag, n, C[n]["result"], json.dumps(ev, default=str)[:300]); return ok
    S = lambda n: os.path.join(SH, f"cg_{tag}_{n}.png")
    c = M.CDP(port, window_size=(W, H))
    try:
        window(c, W, H); R["boot_s"] = c.boot(M.DEBUG_URL); m = c.metrics(); R["metrics"] = m
        chk("viewport_exact_dpr1_mouse", m["iw"] == W and m["ih"] == H and m["dpr"] == 1 and not m["touch"] and M.metrics_ok(m), metrics=m)
        img = c.shot(S("01_title"))
        R["title_text"] = [l["text"] for l in O.lines(img, 1)]
        tt = {n: button_text_check(c, img, 1, n, e) for n, e in [("PlayButton", "Play"), ("SettingsButton", "Settings")]}
        chk("title_buttons_ok", all(t["found"] and t["text_ok"] and M.on_screen(t["rect"], m) for t in tt.values()), texts={k: [v.get("ocr"), v.get("ink_margin_css")] for k, v in tt.items()})
        c.click(*ctr(c.rect("PlayButton")), after=1.2)
        img = c.shot(S("02_harbour")); hs = c.rect("HarbourScroll"); hv = c.rect("HarbourView")
        hb = R10.harbour_buttons(img, 1, hs["x"] + 4, hs["x"] + hs["w"] - 14, hs["y"], min(hs["y"] + hs["h"], H))
        R["harbour_buttons"] = [(b["label"], round(b["x"]), round(b["y"]), round(b["w"]), round(b["h"])) for b in hb]
        lines = R10.LAST.get("lines", [])
        lv = next((b for b in hb if "Level" in b["kind"]), None); q = next((b for b in hb if "Quick" in b["kind"]), None); cl = next((b for b in hb if "Classic" in b["kind"]), None)
        # text fully inside its button (>= 2 px on both sides) -> not truncated
        def inside_text(b):
            l = next((l for l in lines if l["text"] == b["label"]), None)
            return l and l["x"] - b["x"] >= 2 and (b["x"] + b["w"]) - (l["x"] + l["w"]) >= 2
        lab_ok = lv and re.search(r"Level\s*1/2[0o9]\s*:\s*Place every 1", lv["label"], re.I) and cl and re.search(r"\(tier\s*1\)", cl["label"]) and q
        hdr = O.find(lines, r"Tokens")
        chk("harbour_visible_not_truncated", bool(lab_ok) and all(inside_text(b) for b in (lv, q, cl)) and all(M.on_screen(b, m) for b in (lv, q, cl)) and M.on_screen(hv, m),
            labels=R["harbour_buttons"], header=hdr and hdr["text"])
        # wheel to bottom
        lx, ly = ctr(q)
        c.send("Input.dispatchMouseEvent", {"type": "mouseMoved", "x": lx, "y": ly}); c.pump(0.2)
        for _ in range(8): c.send("Input.dispatchMouseEvent", {"type": "mouseWheel", "x": lx, "y": ly, "deltaX": 0, "deltaY": 300}); c.pump(0.25)
        c.pump(0.4); img = c.shot(S("02b_harbour_bottom")); sb = c.rect("SettingsButton")
        hb2 = R10.harbour_buttons(img, 1, hs["x"] + 4, hs["x"] + hs["w"] - 14, hs["y"], min(hs["y"] + hs["h"], H))
        R["harbour_bottom_buttons"] = [(b["label"], round(b["x"]), round(b["y"]), round(b["w"]), round(b["h"])) for b in hb2]
        chk("harbour_bottom_reachable", M.on_screen(sb, m) and sum(1 for b in hb2 if re.search(r"Locked|Buy", b["label"])) >= 1, settings=sb, buttons=R["harbour_bottom_buttons"])
        for _ in range(10): c.send("Input.dispatchMouseEvent", {"type": "mouseWheel", "x": lx, "y": ly, "deltaX": 0, "deltaY": -300}); c.pump(0.25)
        c.pump(0.5)
        # ---- grids
        for (lvl, n, name) in ((1, 6, "g6_L1"), (None, 9, "g9_classic")):
            img = c.shot("/tmp/_r10cg_h_%s.png" % tag)
            hb = R10.harbour_buttons(img, 1, hs["x"] + 4, hs["x"] + hs["w"] - 14, hs["y"], min(hs["y"] + hs["h"], H))
            b = next((b for b in hb if ("Level" if n == 6 else "Classic") in b["kind"]), None)
            if not b: chk(f"{name}_open", False); continue
            c.click(*ctr(b), after=1.5)
            sd = c.dump()["stepDump"]; geo = M.grid_geom(c, n); sol = sd["solution"]; g = sd["grid"]
            img = c.shot(S(f"{name}_a_grid"))
            names = ["GridView", "BackButton", "HintButton", "NotesButton", "UndoButton", "EraseButton", "MistakesLabel", "ObjectiveLabel"] + [f"Digit{d}" for d in range(1, n + 1)]
            rr = {k: c.rect(k) for k in names}; gb = {"x": geo["ox"], "y": geo["oy"], "w": geo["cp"] * n, "h": geo["cp"] * n}; rr["GridCells"] = gb
            off = [k for k, r in rr.items() if not M.on_screen(r, m)]
            gridr = rr["GridView"]
            overlap = [k for k, r in rr.items() if k not in ("GridView", "GridCells") and r and not (r["x"] >= gb["x"] + gb["w"] or r["x"] + r["w"] <= gb["x"] or r["y"] >= gb["y"] + gb["h"] or r["y"] + r["h"] <= gb["y"])]
            chk(f"{name}_controls_on_screen_no_overlap", not off and not overlap, off=off, overlap=overlap, cell_px=round(geo["cp"], 1))
            MS[f"{name}_cell_px"] = round(geo["cp"], 1)
            texts = {nm: button_text_check(c, img, 1, nm, e) for nm, e in [("BackButton", "Back"), ("HintButton", "Hint"), ("NotesButton", "Notes: OFF"), ("UndoButton", "Undo"), ("EraseButton", "Erase")] + [(f"Digit{d}", str(d)) for d in range(1, n + 1)]}
            MS[f"{name}_button_text"] = {k: [v.get("ocr"), v.get("ink_margin_css"), v.get("ink_w_css")] for k, v in texts.items()}
            bad = [k for k, v in texts.items() if not v.get("found") or (v["ink_margin_css"] is None or v["ink_margin_css"] < 2) or (not k.startswith("Digit") and not v["text_ok"])]
            chk(f"{name}_buttons_text_not_truncated", not bad, bad={k: MS[f"{name}_button_text"][k] for k in bad})
            givens = [(r, cc) for r in range(n) for cc in range(n) if g[r][cc]]
            gh = [max(x[0] for x in glyph_h(img, geo, r, cc, 1)) for (r, cc) in givens[:12] if glyph_h(img, geo, r, cc, 1)]
            MS[f"{name}_given_glyph_h_px"] = {"min": min(gh), "median": statistics.median(gh), "max": max(gh)} if gh else None
            # place 2 correct digits by mouse
            emp = M.empties(sd)
            for (r, cc) in emp[:2]:
                c.click(*M.cell_center(geo, r, cc), after=0.3); c.click(*ctr(c.rect(f"Digit{sol[r][cc]}")), after=0.4)
            far = next(rc for rc in givens if all(rc[0] != e[0] and rc[1] != e[1] for e in emp[:2]))
            c.click(*M.cell_center(geo, *far), after=0.4)
            img = c.shot(S(f"{name}_b_entered")); sd2 = c.dump()["stepDump"]
            eh = [max(x[0] for x in glyph_h(img, geo, r, cc, 1)) for (r, cc) in emp[:2] if glyph_h(img, geo, r, cc, 1)]
            MS[f"{name}_entered_glyph_h_px"] = eh
            chk(f"{name}_digits_legible_mouse_input", all(sd2["grid"][r][cc] == sol[r][cc] for r, cc in emp[:2]) and gh and min(gh) >= 10 and eh and min(eh) >= 10,
                given_h=MS[f"{name}_given_glyph_h_px"], entered_h=eh)
            # Undo + Erase by mouse
            u0 = c.dump()["stepDump"]; c.click(*ctr(c.rect("UndoButton")), after=0.5); u1 = c.dump()["stepDump"]
            c.click(*M.cell_center(geo, *emp[0]), after=0.3); c.click(*ctr(c.rect("EraseButton")), after=0.5); u2 = c.dump()["stepDump"]
            chk(f"{name}_undo_erase_mouse", u1["grid"][emp[1][0]][emp[1][1]] == 0 and u2["grid"][emp[0][0]][emp[0][1]] == 0, undo=[len(u0["undo"]), len(u1["undo"]), len(u2["undo"])])
            # notes: densest cell gets every digit, 3 more cells get their candidates
            sdn = c.dump()["stepDump"]; empn = M.empties(sdn)
            picks = []
            for rc in sorted(empn, key=lambda rc: -len(M.candidates(sdn, *rc))):
                if all(rc[0] != p[0] and rc[1] != p[1] for p in picks): picks.append(rc)
                if len(picks) == 4: break
            c.click(*ctr(c.rect("NotesButton")), after=0.4)
            img_on = c.shot("/tmp/_r10cg_n.png"); nt = button_text_check(c, img_on, 1, "NotesButton", "Notes: ON"); MS[f"{name}_notes_on_label"] = [nt["ocr"], nt["ink_margin_css"]]
            noted = {}
            for k, rc in enumerate(picks):
                cand = list(range(1, n + 1)) if k == 0 else M.candidates(sdn, *rc)
                c.click(*M.cell_center(geo, *rc), after=0.25)
                for d in cand: c.click(*ctr(c.rect(f"Digit{d}")), after=0.12)
                noted[rc] = cand
            c.pump(0.4); c.click(*ctr(c.rect("NotesButton")), after=0.4)
            far = next((rc for rc in givens if all(rc[0] != p[0] and rc[1] != p[1] for p in picks)), givens[0]); c.click(*M.cell_center(geo, *far), after=0.5)
            img = c.shot(S(f"{name}_c_notes")); sdN = c.dump()["stepDump"]
            per = {}; allh = []
            for rc, cand in noted.items():
                comps = [x for x in glyph_h(img, geo, rc[0], rc[1], 1, thr=200) if x[0] >= 3 and x[0] < geo["cp"] * 0.6]
                per[str(rc)] = {"n_notes": len(cand), "glyphs": len(comps), "h": sorted(x[0] for x in comps)}; allh += [x[0] for x in comps]
                cr = crop_css(img, cell_box(geo, *rc), 1); cr.resize((cr.width * 6, cr.height * 6), Image.NEAREST).save(S(f"{name}_c_notes_x6_r{rc[0]}c{rc[1]}"))
            mask_ok = all(sdN["notes"][rc[0] * n + rc[1]] == sum(1 << (d - 1) for d in cand) for rc, cand in noted.items())
            MS[f"{name}_note_glyph_h_px"] = {"min": min(allh), "median": statistics.median(allh), "max": max(allh), "n": len(allh)} if allh else None
            MS[f"{name}_note_cells"] = per
            chk(f"{name}_notes_legible", mask_ok and allh and statistics.median(allh) >= 8 and all(abs(v["glyphs"] - v["n_notes"]) <= 1 for v in per.values()),
                glyph_h=MS[f"{name}_note_glyph_h_px"], per_cell={k: [v["n_notes"], v["glyphs"]] for k, v in per.items()}, notes_mask_ok=mask_ok)
            # hint panel open + close
            e2 = [rc for rc in M.empties(sdN) if rc not in noted]
            c.click(*M.cell_center(geo, *e2[-1]), after=0.3); c.click(*ctr(c.rect("HintButton")), after=0.9)
            img = c.shot(S(f"{name}_d_hint_panel")); pb, bb = M.hint_buttons(c, img, 1)
            pls = R10.LAST.get("panel_lines", [])
            kinds = [b["kind"] for b in bb]
            teach_lines = [l for l in pls if re.search(r"Teach", l["text"]) or re.fullmatch(r"\W*token\)\W*", l["text"])]
            MS[f"{name}_hint_panel"] = {"panel": pb and {k: round(v) for k, v in pb.items()}, "buttons": [(b["kind"], round(b["x"]), round(b["y"]), round(b["w"]), round(b["h"])) for b in bb],
                                        "teach_wraps_2_lines": len({round(l["y"] / 8) for l in teach_lines}) >= 2, "text": [l["text"] for l in pls]}
            chk(f"{name}_hint_panel_visible", pb is not None and M.on_screen(pb, m) and all(any(k.startswith(p) for k in kinds) for p in ("Teach", "Reveal", "Back")) and all(M.on_screen(b, m) for b in bb)
                and c.layout()["overlay"] == "HintPanel", **MS[f"{name}_hint_panel"])
            bk = next((b for b in bb if b["kind"].startswith("Back")), None)
            if bk: c.click(*ctr(bk), after=0.8)
            img = c.shot(S(f"{name}_e_after_close"))
            chk(f"{name}_hint_panel_closes", c.layout()["overlay"] == "")
            c.click(*ctr(c.rect("BackButton")), after=1.2)
        m2 = c.metrics(); chk("no_page_scroll_zoom", M.metrics_ok(m2) and m2["iw"] == W, metrics=m2)
        R["errors"] = [l for l in c.logs if "ERROR" in l or "EXCEPTION" in l][:20]
        chk("no_console_errors", not R["errors"], errors=R["errors"])
    except Exception:
        import traceback; R["exception"] = traceback.format_exc(); print(R["exception"])
        try: c.shot(S("99_exception"))
        except Exception: pass
    finally: c.close()
    json.dump(R, open(os.path.join(OUT, f"cg_{tag}.json"), "w"), indent=1, default=str)

# ---------------------------------------------------------------- 6: visual (390x844 DPR 3 touch)
def run_visual(port, tag="390x844"):
    w, h = map(int, tag.split("x")); dpr = M.DPR[tag]; R = {"viewport": tag, "checks": {}, "meas": {}}; C = R["checks"]; MS = R["meas"]
    def chk(n, ok, **ev): C[n] = {"result": "PASS" if ok else "FAIL", **ev}; print(n, C[n]["result"], json.dumps(ev, default=str)[:400]); return ok
    S = lambda n: os.path.join(SH, f"visual_{tag}_{n}.png")
    c = M.CDP(port)
    try:
        c.emulate(w, h, dpr); c.boot(M.DEBUG_URL)
        c.js("SD_DEBUG.startLevel(11)"); c.pump(1.2)
        sd = c.dump()["stepDump"]; n = 9; geo = M.grid_geom(c, n); sol = sd["solution"]; g = sd["grid"]; emp = M.empties(sd)
        givens = [(r, cc) for r in range(n) for cc in range(n) if g[r][cc]]
        # entered digit + notes cell + a wrong digit, then deselect onto a far given for neutral backgrounds
        (re_, ce_) = emp[0]; c.tap(*M.cell_center(geo, re_, ce_)); c.tap_node(f"Digit{sol[re_][ce_]}")
        rich = sorted(M.empties(c.dump()["stepDump"]), key=lambda rc: -len(M.candidates(c.dump()["stepDump"], *rc)))
        (rn, cn) = next(rc for rc in rich if rc[0] != re_ and rc[1] != ce_)
        c.tap_node("NotesButton"); c.tap(*M.cell_center(geo, rn, cn))
        for d in range(1, 10): c.tap_node(f"Digit{d}", after=0.15)
        c.tap_node("NotesButton")
        sdx = c.dump()["stepDump"]
        (rw, cw) = next(rc for rc in M.empties(sdx) if rc[0] not in (re_, rn) and rc[1] not in (ce_, cn) and rc[0] // 3 != rn // 3)
        wrong = next(d for d in range(1, 10) if d != sol[rw][cw] and d not in [sdx["grid"][rw][k] for k in range(9)] and d not in [sdx["grid"][k][cw] for k in range(9)])
        c.tap(*M.cell_center(geo, rw, cw))
        # ---- shake: fast clipped screenshots of the grid band right after the wrong tap
        dr = c.rect(f"Digit{wrong}")
        gx0 = geo["ox"] - 12; gy = geo["oy"] + geo["cp"] * 4.5
        clip = {"x": max(0, gx0), "y": gy - 4, "width": 40, "height": 8, "scale": 1}
        frames = []; t0 = time.time(); sent = 0
        c.send("Page.startScreencast", {"format": "png", "everyNthFrame": 1})
        c.ws.settimeout(0.02)
        tx_, ty_ = dr["x"] + dr["w"] / 2, dr["y"] + dr["h"] / 2
        while time.time() - t0 < 2.0:
            el = time.time() - t0
            if sent == 0 and el > 0.3:
                c.n += 1; c.ws.send(json.dumps({"id": c.n, "method": "Input.dispatchTouchEvent", "params": {"type": "touchStart", "touchPoints": [{"x": tx_, "y": ty_, "id": 1}]}})); sent = 1
            elif sent == 1 and el > 0.36:
                c.n += 1; c.ws.send(json.dumps({"id": c.n, "method": "Input.dispatchTouchEvent", "params": {"type": "touchEnd", "touchPoints": []}})); sent = 2; t_tap = el
            try: mm = json.loads(c.ws.recv())
            except Exception: continue
            if mm.get("method") == "Page.screencastFrame":
                p_ = mm["params"]; c.n += 1
                c.ws.send(json.dumps({"id": c.n, "method": "Page.screencastFrameAck", "params": {"sessionId": p_["sessionId"]}}))
                im_ = Image.open(io.BytesIO(base64.b64decode(p_["data"]))).convert("RGB")
                sc = im_.width / w
                frames.append((round(time.time() - t0, 3), im_.crop((int(clip["x"] * sc), int(clip["y"] * sc), int((clip["x"] + clip["width"]) * sc), int((clip["y"] + clip["height"]) * sc))), sc))
            elif "method" in mm: c._event(mm)
        c.ws.settimeout(120)
        c.send("Page.stopScreencast"); c.pump(0.3)
        MS["tap_at_s"] = round(t_tap, 3)
        MS["screencast_scale"] = frames[0][2] if frames else None; frames = [(t, im) for t, im, sc in frames]
        def border_x(im):   # leftmost dark box-line column in the clip -> CSS x
            px = im.load(); W_, H_ = im.size
            for x in range(W_):
                col = [px[x, y] for y in range(H_)]
                if sum(1 for p in col if abs(p[0] - 0x2E) < 30 and abs(p[1] - 0x4A) < 30 and abs(p[2] - 0x5C) < 30) > 0.6 * H_: return clip["x"] + x / (MS.get("screencast_scale") or dpr)
            return None
        xs = [(t, border_x(im)) for t, im in frames]
        base = xs[-1][1]
        offs = [(t, None if x is None or base is None else round(x - base, 2)) for t, x in xs]
        MS["shake_border_offsets_css"] = offs
        fs_ = [f for f in frames if f[0] >= MS["tap_at_s"] - 0.05][:14]
        strip = Image.new("RGB", (frames[0][1].width * len(fs_), frames[0][1].height * 6), "white")
        for k, (t, im) in enumerate(fs_): strip.paste(im.resize((im.width, im.height * 6), Image.NEAREST), (k * im.width, 0))
        strip.save(S("06a_shake_frames_strip"))
        moving = [o for t, o in offs if o not in (None, 0, 0.0)]
        c.pump(0.6)
        st = c.dump(); sdw = st["stepDump"]
        img = c.shot(S("06b_wrong_digit_selected"))
        # deselect to a far given cell so the wrong cell is on plain paper
        far = next((rc for rc in givens if rc[0] // 3 != rw // 3 and rc[1] // 3 != cw // 3 and rc[0] // 3 != rn // 3 and rc[1] // 3 != cn // 3 and rc[0] // 3 != re_ // 3 and rc[1] // 3 != ce_ // 3), givens[0])
        c.tap(*M.cell_center(geo, *far)); c.pump(0.5)
        img = c.shot(S("06c_grid_digits_notes_wrong"))
        # crops
        for nm, rc in (("given", givens[0]), ("entered", (re_, ce_)), ("notes", (rn, cn)), ("wrong", (rw, cw))):
            cr = crop_css(img, cell_box(geo, *rc), dpr); cr.resize((cr.width * 3, cr.height * 3), Image.NEAREST).save(S(f"06d_cell_{nm}_x3"))
        chk("wrong_digit_shakes", len(moving) >= 2 and max(abs(o) for o in moving) >= 1.0, offsets=offs[:20], mistakes=sdw["mistakes"], frames=len(frames))
        # underline: rows of error ink under the glyph in the wrong cell
        cr = crop_css(img, cell_box(geo, rw, cw), dpr, ins=2); px = cr.load(); W_, H_ = cr.size
        def is_err(p): return abs(p[0] - 0xA3) < 40 and abs(p[1] - 0x21) < 40 and abs(p[2] - 0x1A) < 40
        rows = [(y, sum(1 for x in range(W_) if is_err(px[x, y]))) for y in range(H_)]
        ink_rows = [y for y, k in rows if k > 0]
        wide = [y for y, k in rows if k >= 0.45 * W_]
        glyph_rows = [y for y, k in rows if 0 < k < 0.45 * W_]
        MS["wrong_cell"] = {"cell": [rw, cw], "digit": wrong, "underline_rows_css": [round(y / dpr, 1) for y in wide], "glyph_bottom_css": round(max(glyph_rows) / dpr, 1) if glyph_rows else None,
                            "underline_width_frac": round(max((k for y, k in rows), default=0) / W_, 2)}
        chk("wrong_digit_underlined", bool(wide) and glyph_rows and min(wide) > min(glyph_rows) and sdw["grid"][rw][cw] == wrong, **MS["wrong_cell"])
        # ---- contrast (DPR 3: glyph cores reach the true colour)
        con = {}
        for nm, rc in (("given", givens[0]), ("given2", givens[5]), ("entered", (re_, ce_)), ("notes", (rn, cn)), ("wrong", (rw, cw))):
            cr = crop_css(img, cell_box(geo, *rc), dpr, ins=3)
            if nm == "wrong":   # exclude the underline rows from the glyph colour sample: use the glyph itself
                pass
            ink, bg, extreme = ink_and_bg(cr)
            con[nm] = {"ink": hexc(ink), "ink_extreme": hexc(extreme), "bg": hexc(bg), "ratio": contrast(ink, bg), "ratio_extreme": contrast(extreme, bg)}
        # palette (spec) ratios on the paper colour, for reference
        P = {"given": (0x1E, 0x2B, 0x38), "entered": (0x1A, 0x4F, 0xA3), "notes": (0x4E, 0x5D, 0x69), "wrong": (0xA3, 0x21, 0x1A)}
        bgs = {"paper": (0xFF, 0xFD, 0xF8), "selected": (0xFF, 0xE3, 0xA3), "peer": (0xED, 0xF2, 0xF1), "same": (0xB9, 0xD9, 0xE6), "teach": (0xD9, 0xEB, 0xCB), "error_cell": (0xF9, 0xD9, 0xD3)}
        MS["contrast_measured_dpr3"] = con
        MS["contrast_palette"] = {k: {b: contrast(v, bv) for b, bv in bgs.items()} for k, v in P.items()}
        body = [con[k]["ratio"] for k in ("given", "given2", "entered", "wrong")]
        chk("contrast_body_digits_ge_4_5", min(body) >= 4.5 and all(MS["contrast_palette"][k][b] >= 4.5 for k in ("given", "entered", "wrong") for b in bgs), measured={k: con[k]["ratio"] for k in con}, palette_min={k: min(v.values()) for k, v in MS["contrast_palette"].items()})
        chk("contrast_notes_ge_3", con["notes"]["ratio"] >= 3 and min(MS["contrast_palette"]["notes"].values()) >= 3, measured=con["notes"], palette=MS["contrast_palette"]["notes"])
        # ---- harbour: lock icons, Buy -> sprite swap, persistence
        c.js("SD_DEBUG.startLevel(1)"); c.pump(0.8); c.js("SD_DEBUG.solve()"); c.pump(1.5)
        c.js("SD_DEBUG.show('harbour')"); c.pump(1.5)
        p0 = c.dump()["profile"]; MS["stars_before_buy"] = p0["stars"]
        hv = c.rect("HarbourView"); imgA = c.shot(S("07a_harbour_before_buy"))
        # scroll list so the Tasks rows are visible (touch drag on a button = scroll)
        hs = c.rect("HarbourScroll")
        for _ in range(4):
            if M.on_screen(c.rect("SettingsButton"), c.metrics()): break
            c.drag(hs["x"] + hs["w"] * 0.5, hs["y"] + hs["h"] * 0.85, 0, -hs["h"] * 0.6, steps=20); c.pump(0.5)
        img = c.shot(S("07b_harbour_tasks"))
        hb = R10.harbour_buttons(img, dpr, hs["x"] + 4, hs["x"] + hs["w"] - 14, hs["y"], min(hs["y"] + hs["h"], h))
        locked = [b for b in hb if "Locked" in b["kind"] and b["y"] + b["h"] <= h]
        buy = next((b for b in hb if "Buy" in b["kind"]), None)
        # lock icon: ink blob left of the "Locked" text inside the button
        locks = []
        for k, b in enumerate(locked):
            l = next((l for l in R10.LAST["lines"] if re.search("Locked", l["text"]) and abs(l["y"] - (b["y"] + b["h"] / 2 - l["h"] / 2)) < b["h"]), None)
            if not l: continue
            region = (b["x"] + 4, b["y"] + 6, max(b["x"] + 6, re.search("Locked", l["text"]) and (l["x"] + l["w"] - 0.62 * l["w"] * 6 / max(6, len(l["text"]))) or l["x"]), b["y"] + b["h"] - 6)
            region = (b["x"] + 4, b["y"] + 6, b["x"] + b["w"] * 0.32, b["y"] + b["h"] - 6)
            cr = crop_css(img, region, dpr)
            from collections import Counter
            fill = Counter(cr.getdata()).most_common(1)[0][0]
            dm = ImageChops.difference(cr, Image.new("RGB", cr.size, fill)).convert("L").point(lambda v: 255 if v > 50 else 0)
            ibb = dm.getbbox()
            cr2 = crop_css(img, (b["x"], b["y"], b["x"] + b["w"], b["y"] + b["h"]), dpr); cr2.resize((cr2.width * 2, cr2.height * 2), Image.NEAREST).save(S(f"07c_locked_button_{k}_x2"))
            icon = ibb and cr.crop(ibb)
            ink, bg, ext = ink_and_bg(cr) if ibb else (None, None, None)
            locks.append({"button": [round(b["x"]), round(b["y"]), round(b["w"]), round(b["h"])], "icon_bbox_css": ibb and [round(v / dpr, 1) for v in ibb],
                          "icon_colour": ink and hexc(ink), "fill": hexc(fill), "icon_contrast": ink and contrast(ink, fill)})
        MS["locked_buttons"] = locks
        chk("locked_buttons_show_lock_icon", locks and all(l["icon_bbox_css"] and 8 <= l["icon_bbox_css"][3] - l["icon_bbox_css"][1] <= 30 for l in locks), locked=locks)
        # Buy
        tasks0 = dict(p0.get("tasks", {}))
        if buy: c.tap(buy["tx"], buy["ty"], after=1.5)
        st = c.dump(); p1 = st["profile"]; MS["buy"] = {"stars": [p0["stars"], p1["stars"]], "tasks": [tasks0, p1.get("tasks")], "screen_after": st["screen"]}
        c.pump(2.0)
        if c.dump()["screen"] != "harbour": c.js("SD_DEBUG.show('harbour')"); c.pump(2.0)
        # list back to top so the harbour view geometry matches the first shot
        hv1 = c.rect("HarbourView"); imgB = c.shot(S("07d_harbour_after_buy"))
        box = (hv["x"], hv["y"], hv["x"] + hv["w"], hv["y"] + hv["h"])
        A = crop_css(imgA, box, dpr); B = crop_css(imgB, box, dpr)
        dif = ImageChops.difference(A, B).convert("L").point(lambda v: 255 if v > 40 else 0); dbb = dif.getbbox()
        MS["sprite_diff_bbox_css"] = dbb and [round(v / dpr + (hv["x"] if i % 2 == 0 else hv["y"]), 1) for i, v in enumerate(dbb)]
        MS["sprite_diff_pixels"] = dif.histogram()[255]
        if dbb:
            pad = 10 * dpr; bx = (max(0, dbb[0] - pad), max(0, dbb[1] - pad), min(A.width, dbb[2] + pad), min(A.height, dbb[3] + pad))
            pair = Image.new("RGB", ((bx[2] - bx[0]) * 2 + 10, bx[3] - bx[1]), "white"); pair.paste(A.crop(bx), (0, 0)); pair.paste(B.crop(bx), (bx[2] - bx[0] + 10, 0)); pair.save(S("07e_dock_sprite_before_after"))
        # expected location: dock foot in portrait bg px (332, 842), cover-cropped -> just check the diff sits in the harbour view, lower half
        chk("buy_task_swaps_sprite", p1["stars"] == p0["stars"] - 3 and "dock" in (p1.get("tasks") or {}) and dbb is not None and MS["sprite_diff_pixels"] > 500 and hv1 == hv,
            **MS["buy"], diff_bbox=MS["sprite_diff_bbox_css"], diff_px=MS["sprite_diff_pixels"])
        # reload: sprite persists
        c.reload(); c.tap_node("PlayButton"); c.pump(2.0)
        imgC = c.shot(S("07f_harbour_after_reload")); Cc = crop_css(imgC, box, dpr)
        d_BC = ImageChops.difference(B, Cc).convert("L").point(lambda v: 255 if v > 40 else 0).histogram()[255]
        d_AC = ImageChops.difference(A, Cc).convert("L").point(lambda v: 255 if v > 40 else 0).histogram()[255]
        MS["after_reload_diff_px"] = {"vs_after_buy": d_BC, "vs_before_buy": d_AC}
        chk("sprite_persists_after_reload", "dock" in (c.dump()["profile"].get("tasks") or {}) and d_BC < 0.2 * max(1, MS["sprite_diff_pixels"]) and d_AC > 0.8 * MS["sprite_diff_pixels"], **MS["after_reload_diff_px"])
        R["errors"] = [l for l in c.logs if "ERROR" in l or "EXCEPTION" in l][:20]
        chk("no_console_errors", not R["errors"], errors=R["errors"])
    except Exception:
        import traceback; R["exception"] = traceback.format_exc(); print(R["exception"])
        try: c.shot(S("99_exception"))
        except Exception: pass
    finally: c.close()
    json.dump(R, open(os.path.join(OUT, f"visual_{tag}.json"), "w"), indent=1, default=str)

# ---------------------------------------------------------------- 7: landscape vs portrait harbour painting
def cover(src, W, H):
    s = max(W / src.width, H / src.height); im = src.resize((max(1, round(src.width * s)), max(1, round(src.height * s))), Image.BILINEAR)
    return im
def match_score(crop, src):
    """mean abs diff (0-255) between the screenshot crop and the source painting, best over horizontal/vertical crop offsets."""
    W, H = 64, max(8, round(64 * crop.height / crop.width)); a = crop.resize((W, H), Image.BILINEAR).convert("L")
    best = 999
    im = cover(src, W, H).convert("L")
    for ox in range(0, im.width - W + 1, max(1, (im.width - W) // 12 or 1)):
        for oy in range(0, im.height - H + 1, max(1, (im.height - H) // 12 or 1)):
            d = ImageChops.difference(a, im.crop((ox, oy, ox + W, oy + H))); v = sum(d.getdata()) / (W * H); best = min(best, v)
    # zoomed-out case (mirrored edge): also try the source scaled to the crop height
    s = H / src.height; im2 = src.resize((max(1, round(src.width * s)), H), Image.BILINEAR).convert("L")
    if im2.width <= W:
        canvas = Image.new("L", (W, H)); off = (W - im2.width) // 2; canvas.paste(im2, (off, 0))
        best = min(best, sum(ImageChops.difference(a, canvas).getdata()) / (W * H))
    else:
        for ox in range(0, im2.width - W + 1, max(1, (im2.width - W) // 12)):
            best = min(best, sum(ImageChops.difference(a, im2.crop((ox, 0, ox + W, H))).getdata()) / (W * H))
    return round(best, 1)

def run_landscape(port):
    P = Image.open(f"{WT}/assets/art/harbour/harbour_bg_portrait.webp").convert("RGB")
    L = Image.open(f"{WT}/assets/art/harbour/harbour_bg_landscape.webp").convert("RGB")
    sizes = [("390x844", "touch"), ("360x640", "touch"), ("844x390", "touch"), ("768x1024", "touch"), ("1280x800", "desk"), ("1280x720", "desk"), ("1366x768", "desk"), ("1920x1080", "desk"), ("1600x700", "desk"), ("1920x800", "desk"), ("2560x1080", "desk"), ("800x450", "desk")]
    R = {"rows": []}
    for tag, kind in sizes:
        w, h = map(int, tag.split("x")); row = {"viewport": tag, "input": kind}
        c = M.CDP(port, window_size=(w, h) if kind == "desk" else None)
        try:
            if kind == "desk": window(c, w, h)
            else: c.emulate(w, h, M.DPR.get(tag, 3))
            c.boot(M.DEBUG_URL); c.js("SD_DEBUG.show('harbour')"); c.pump(1.5)
            dpr = 1 if kind == "desk" else M.DPR.get(tag, 3)
            img = c.shot(os.path.join(SH, f"landscape_{tag}_harbour.png")); hv = c.rect("HarbourView"); lay = c.layout()
            row["harbour_view_css"] = {k: round(v, 1) for k, v in hv.items()}; row["aspect"] = round(hv["w"] / hv["h"], 3)
            row["predicted"] = "landscape" if hv["w"] >= hv["h"] * 1.35 else "portrait"
            cr = crop_css(img, (hv["x"], hv["y"], hv["x"] + hv["w"], hv["y"] + hv["h"]), dpr)
            sp, sl = match_score(cr, P), match_score(cr, L)
            row["diff_vs_portrait_art"] = sp; row["diff_vs_landscape_art"] = sl
            row["shown"] = "landscape" if sl < sp else "portrait"
            row["metrics_ok"] = M.metrics_ok(c.metrics())
            print(row)
        except Exception:
            import traceback; row["exception"] = traceback.format_exc(); print(row["exception"])
        finally: c.close()
        R["rows"].append(row)
    json.dump(R, open(os.path.join(OUT, "landscape.json"), "w"), indent=1, default=str)

# ---------------------------------------------------------------- 9: release boot smoke (no hooks)
def run_release(port, tag="390x844"):
    w, h = map(int, tag.split("x")); dpr = M.DPR[tag]; R = {"url": RELEASE_URL, "checks": {}}; C = R["checks"]
    def chk(n, ok, **ev): C[n] = {"result": "PASS" if ok else "FAIL", **ev}; print(n, C[n]["result"], json.dumps(ev, default=str)[:300]); return ok
    S = lambda n: os.path.join(SH, f"release_{tag}_{n}.png")
    c = M.CDP(port)
    try:
        c.emulate(w, h, dpr)
        try: R["boot_s"] = c.boot(RELEASE_URL, timeout=120); booted = True
        except RuntimeError: booted = False
        img = c.shot(S("01_title")); m = c.metrics()
        chk("release_boots_past_splash", booted, boot_s=R.get("boot_s"), logs=c.logs[:6])
        chk("release_no_debug_hooks", c.js("typeof window.SD_DEBUG === 'undefined' && typeof window.SD_QA === 'undefined'") is True)
        ls = O.lines(img, dpr); play = O.find(ls, r"^\W*Play\W*$")
        chk("release_title_text", play is not None and O.find(ls, r"Sudoku\s*Dash") is not None, text=[l["text"] for l in ls if len(l["text"]) > 3][:8])
        if play: c.tap(*ctr(play), after=1.5)
        img = c.shot(S("02_harbour")); ls = O.lines(img, dpr)
        lv = O.find(ls, r"Level\s*1"); q = O.find(ls, r"Quick\s*6")
        chk("release_play_reaches_harbour", O.find(ls, r"Harbour") is not None and lv is not None, text=[l["text"] for l in ls if len(l["text"]) > 4][-10:])
        # drag on the Level button: list scrolls, nothing opens
        if lv and q:
            c.drag(lv["x"] + lv["w"] / 2, lv["y"] + lv["h"] / 2, 0, -100, steps=15); c.pump(0.6)
            img2 = c.shot(S("03_harbour_after_button_drag")); ls2 = O.lines(img2, dpr); q2 = O.find(ls2, r"Quick\s*6")
            chk("release_harbour_button_drag_scrolls_no_press", q2 is not None and abs((q["y"] - q2["y"]) - 100) <= 4, quick_y=[round(q["y"], 1), q2 and round(q2["y"], 1)])
            c.drag(w / 2, h * 0.6, 0, 300, steps=15); c.pump(0.6)
        img = c.shot("/tmp/_r10r.png"); ls = O.lines(img, dpr); lv = O.find(ls, r"Level\s*1")
        if lv: c.tap(*ctr(lv), after=2.0)
        img3 = c.shot(S("04_after_level_tap")); px = img3.load(); W3, H3 = img3.size
        paper = sum(1 for y in range(0, H3, 6) for x in range(0, W3, 6) if px[x, y] == (255, 253, 248))
        chk("release_level1_opens_grid", paper > 0.12 * (W3 // 6) * (H3 // 6), paper_frac=round(paper / ((W3 // 6) * (H3 // 6)), 3))
        chk("release_no_zoom_scroll", M.metrics_ok(c.metrics()))
        R["errors"] = [l for l in c.logs if "ERROR" in l or "EXCEPTION" in l][:20]
        chk("release_no_console_errors", not R["errors"], errors=R["errors"])
    except Exception:
        import traceback; R["exception"] = traceback.format_exc(); print(R["exception"])
    finally: c.close()
    json.dump(R, open(os.path.join(OUT, f"release_{tag}.json"), "w"), indent=1, default=str)


# ---------------------------------------------------------------- run9 (c) Buy tappable by touch, per viewport (replaces run_harbour's slate-colour Buy finder)
def run_buy(tag, port):
    w, h = map(int, tag.split("x")); dpr = M.DPR[tag]; R = {"viewport": tag}
    c = M.CDP(port)
    try:
        c.emulate(w, h, dpr); c.boot(M.DEBUG_URL)
        c.js("SD_DEBUG.startLevel(1)"); c.pump(0.8); c.js("SD_DEBUG.solve()"); c.pump(1.5)
        c.js("SD_DEBUG.show('harbour')"); c.pump(1.5)
        hs = c.rect("HarbourScroll"); mm = c.metrics(); drags = 0
        while not M.on_screen(c.rect("SettingsButton"), mm) and drags < 6:
            c.drag(hs["x"] + hs["w"] * 0.5, min(h, hs["y"] + hs["h"]) - 8, 0, -(min(h, hs["y"] + hs["h"]) - hs["y"]) * 0.6, steps=20); c.pump(0.5); drags += 1
        img = c.shot(os.path.join(SH, f"buy_{tag}_01_tasks.png"))
        hb = R10.harbour_buttons(img, dpr, hs["x"] + 4, hs["x"] + hs["w"] - 14, max(0, hs["y"]), min(hs["y"] + hs["h"], h))
        buy = next((b for b in hb if "Buy" in b["kind"]), None)
        p0 = c.dump()["profile"]
        if buy: c.tap(buy["tx"], buy["ty"], after=1.5)
        st = c.dump(); p1 = st["profile"]; c.shot(os.path.join(SH, f"buy_{tag}_02_after_buy.png"))
        R.update(buy_text=buy and buy["label"], tap=buy and [round(buy["tx"]), round(buy["ty"])], stars=[p0["stars"], p1["stars"]], tasks=[p0.get("tasks"), p1.get("tasks")], screen=st["screen"], drags=drags)
        R["result"] = "PASS" if buy and p0["stars"] == 3 and p1["stars"] == 0 and "dock" in (p1.get("tasks") or {}) else "FAIL"
        R["errors"] = [l for l in c.logs if "ERROR" in l or "EXCEPTION" in l][:20]
    except Exception:
        import traceback; R["exception"] = traceback.format_exc(); R["result"] = "FAIL"; print(R["exception"])
    finally: c.close()
    print(json.dumps(R, default=str)); json.dump(R, open(os.path.join(OUT, f"buy_{tag}.json"), "w"), indent=1, default=str)

if __name__ == "__main__":
    mode = sys.argv[1]
    if mode == "desktop": run_desktop(int(sys.argv[2]))
    elif mode == "cg": run_cg(sys.argv[2], int(sys.argv[3]))
    elif mode == "visual": run_visual(int(sys.argv[2]))
    elif mode == "landscape": run_landscape(int(sys.argv[2]))
    elif mode == "release": run_release(int(sys.argv[2]))
    elif mode == "buy": run_buy(sys.argv[2], int(sys.argv[3]))
