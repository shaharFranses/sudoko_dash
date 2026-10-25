#!/usr/bin/env python3
"""QA run 10 (art integration, ede4bfd): colour-agnostic wrappers over qa/mobile_qa.py.
The art kit replaced the slate/gray button colours that mobile_qa.bands()/hint_buttons() keyed on, so this file
monkeypatches them with OCR (tesseract) + edge expansion, then reuses run_mobile / run_harbour / run_rotate unchanged.
Usage: QA_BUILD=ede4bfd QA_RUN=run10_ede4bfd QA_DEBUG_PORT=8070 /tmp/qav/bin/python qa/run10.py mobile 390x844 9471 | harbour WxH port | rotate WxH port"""
import os, sys, json, re
os.environ.setdefault("QA_BUILD", "ede4bfd"); os.environ.setdefault("QA_RUN", "run10_ede4bfd"); os.environ.setdefault("QA_DEBUG_PORT", "8070")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mobile_qa as M
import ocr_locate as O

def _diff(a, b): return abs(a[0] - b[0]) + abs(a[1] - b[1]) + abs(a[2] - b[2])

def expand(img, dpr, t, thr=60):
    """text line t (CSS) -> the button rect around it, by walking out from just above the text to the first colour edge."""
    px = img.load(); W, H = img.size
    cx = int((t["x"] + t["w"] / 2) * dpr); yt = int((t["y"] - 2) * dpr); yb = int((t["y"] + t["h"] + 2) * dpr)
    yt = max(0, min(H - 1, yt)); yb = max(0, min(H - 1, yb))
    ref = px[cx, yt]
    y = yt
    while y > 0 and _diff(px[cx, y - 1], ref) <= thr: y -= 1
    top = y
    ref2 = px[cx, yb]; y = yb
    while y < H - 1 and _diff(px[cx, y + 1], ref2) <= thr: y += 1
    bot = y
    x = int((t["x"] - 1) * dpr); x = max(0, x)
    while x > 0 and _diff(px[x - 1, yt], ref) <= thr: x -= 1
    left = x
    x = min(W - 1, int((t["x"] + t["w"] + 1) * dpr))
    while x < W - 1 and _diff(px[x + 1, yt], ref) <= thr: x += 1
    right = x
    return {"x": left / dpr, "y": top / dpr, "w": (right - left + 1) / dpr, "h": (bot - top + 1) / dpr, "label": t["text"]}

LAST = {}
def harbour_buttons(img, dpr, x0, x1, y0, y1):
    ls = O.lines(img, dpr, (max(0, x0 - 4), max(0, y0), min(img.width / dpr, x1 + 14), min(img.height / dpr, y1)))
    LAST["lines"] = ls
    out = []
    pats = [r"Level\s*\d", r"Resume", r"Quick\s*6", r"Classic\s*9", r"^\W*Buy|Buy\s*\(", r"Locked", r"Settings", r"Area restored", r"Path complete"]
    seen = set()
    for l in ls:
        for p in pats:
            if re.search(p, l["text"], re.I):
                b = expand(img, dpr, l); b["tx"], b["ty"] = l["x"] + l["w"] / 2, l["y"] + l["h"] / 2; b["text_box"] = l
                key = (round(b["y"] / 4), round(b["x"] / 20))
                if key in seen or b["h"] < 20 or b["w"] < 30: break
                seen.add(key); b["kind"] = p; out.append(b); break
    # tier row: OCR "T1".."T4" if present, else the gap between Quick and Classic
    q = next((b for b in out if "Quick" in b["kind"]), None); cl = next((b for b in out if "Classic" in b["kind"]), None)
    tl = [l for l in ls if re.fullmatch(r"\W*T[1-4l|]\W*", l["text"])]
    if q and cl and cl["y"] - (q["y"] + q["h"]) > 20:
        out.append({"x": q["x"], "y": q["y"] + q["h"] + 3, "w": q["w"], "h": cl["y"] - (q["y"] + q["h"]) - 6, "label": "T-row", "kind": "T"})
    elif tl:
        ty = min(l["y"] for l in tl); th = max(l["h"] for l in tl)
        ref = q or cl or (out[0] if out else {"x": x0, "w": x1 - x0})
        out.append({"x": ref["x"], "y": ty - 12, "w": ref["w"], "h": th + 24, "label": "T-row", "kind": "T"})
    out = [b for b in out if b["y"] + b["h"] / 2 >= y0 and b["y"] + b["h"] / 2 <= y1]
    return sorted(out, key=lambda b: (round(b["y"] / 6), b["x"]))

_orig_bands = M.bands
def bands(img, dpr, x0, x1, y0, y1, kind):
    if kind == "menu": return harbour_buttons(img, dpr, x0, x1, y0, y1)
    return _orig_bands(img, dpr, x0, x1, y0, y1, kind)

def cream_bbox(img, dpr):   # hint panel (PANEL_CREAM FFFAF0) - same colour as before; keep only the biggest cluster region
    return M._orig_cream(img, dpr)

def hint_buttons(c, img, dpr):
    pb = M.cream_bbox(img, dpr)
    if not pb: return None, []
    ls = O.lines(img, dpr, (pb["x"], pb["y"], pb["x"] + pb["w"], pb["y"] + pb["h"]))
    LAST["panel_lines"] = ls
    btns = []
    for p in (r"Show\s*my\s*last", r"Teach", r"Reveal", r"Watch", r"Back\s*to|to\s*grid"):
        l = O.find(ls, p)
        if l:
            b = expand(img, dpr, l); b["kind"] = p
            if b["w"] < 0.4 * pb["w"]: b.update(x=pb["x"] + 16, w=pb["w"] - 32)
            btns.append(b)
    rs = c.rect("ReshowHint")
    if rs and not any(b["kind"].startswith("Show") for b in btns): rs = dict(rs, kind="Show", label="Show my last hint again"); btns.append(rs)
    return pb, sorted(btns, key=lambda b: b["y"])

M._orig_cream = M.cream_bbox
M.bands = bands
M.hint_buttons = hint_buttons

if __name__ == "__main__":
    mode = sys.argv[1]
    if mode == "mobile": M.run_mobile(sys.argv[2], int(sys.argv[3]))
    elif mode == "harbour": M.run_harbour(sys.argv[2], int(sys.argv[3]))
    elif mode == "rotate":
        pw, ph = map(int, sys.argv[2].split("x")); M.run_rotate(int(sys.argv[3]), pw, ph, M.DPR.get(sys.argv[2], 3))
    elif mode == "probe":   # one harbour + hint panel probe, prints what the locators find
        tag = sys.argv[2]; w, h = map(int, tag.split("x")); c = M.CDP(int(sys.argv[3]))
        try:
            c.emulate(w, h, M.DPR.get(tag, 3)); c.boot(M.DEBUG_URL); c.tap_node("PlayButton"); c.pump(0.8)
            img = c.shot("/tmp/_p_h.png"); hs = c.rect("HarbourScroll")
            print(json.dumps([(b["label"], round(b["x"]), round(b["y"]), round(b["w"]), round(b["h"])) for b in bands(img, M.DPR.get(tag, 3), hs["x"] + 4, hs["x"] + hs["w"] - 14, hs["y"], min(hs["y"] + hs["h"], h), "menu")]))
            c.js("SD_DEBUG.startLevel(11)"); c.pump(1); c.tap_node("HintButton"); c.pump(0.6)
            img = c.shot("/tmp/_p_p.png"); pb, hb = hint_buttons(c, img, M.DPR.get(tag, 3))
            print(pb); print(json.dumps([(b["kind"], round(b["x"]), round(b["y"]), round(b["w"]), round(b["h"])) for b in hb]))
        finally: c.close()
