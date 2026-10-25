#!/usr/bin/env python3
"""Sudoku Dash QA Run 8 - independent mobile-fit QA (raw Chrome DevTools Protocol, no Playwright).

Drives real Google Chrome (headless=new, SwiftShader GL) over a CDP websocket:
  Emulation.setDeviceMetricsOverride (mobile:true, DPR 2-3) + Emulation.setTouchEmulationEnabled,
  ALL game input on mobile via Input.dispatchTouchEvent (never keyboard). Desktop uses mouse events.
SD_DEBUG is used only to read state (dump/rect/layout) and to jump to a level (startLevel); every
action under test is a real touch.

Usage: /tmp/qav/bin/python qa/mobile_qa.py mobile 390x844 | rotate | desktop | release
Writes qa/results/run8/<mode>_<tag>.json and screenshots to qa/results/run8/mobile/.
"""
import base64, io, json, os, shutil, subprocess, sys, tempfile, time, urllib.request
import websocket
from PIL import Image

CHROME = "/usr/bin/google-chrome"
# Build / run selection (defaults = run 8). Run 9: QA_BUILD=b5479ff QA_RUN=run9 QA_DEBUG_PORT=8068 QA_RELEASE_PORT=8069
BUILD = os.environ.get("QA_BUILD", "98ff834")
RUN = os.environ.get("QA_RUN", "run8")
DEBUG_URL = f"http://127.0.0.1:{os.environ.get('QA_DEBUG_PORT', '8065')}/{BUILD}/index.html"
RELEASE_URL = f"http://127.0.0.1:{os.environ.get('QA_RELEASE_PORT', '8067')}/{BUILD}/index.html"
DESKTOP_REF = os.environ.get("QA_DESKTOP_REF", "run7/clip_L11.png")   # run 9: run8/mobile/desktop_02_L11.png
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "results", RUN)
SHOTS = os.path.join(OUT, "mobile")
DPR = {"360x640": 3, "390x844": 3, "412x915": 2.625, "768x1024": 2, "844x390": 3}
os.makedirs(SHOTS, exist_ok=True)


class CDP:
    def __init__(self, port, window_size=None):
        self.ud = tempfile.mkdtemp(prefix="sdqa_run11_%d_" % os.getpid())     # fresh profile every session
        args = [CHROME, "--headless=new", f"--remote-debugging-port={port}", f"--user-data-dir={self.ud}",
                "--no-first-run", "--no-default-browser-check", "--use-angle=swiftshader",
                "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist", "--hide-scrollbars", "about:blank"]
        if window_size: args.insert(1, f"--window-size={window_size[0]},{window_size[1]}")
        self.proc = subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        for _ in range(100):
            try:
                tl = json.load(urllib.request.urlopen(f"http://127.0.0.1:{port}/json/list"))
                pages = [t for t in tl if t["type"] == "page"]
                if pages: break
            except Exception: pass
            time.sleep(0.2)
        self.ws = websocket.create_connection(pages[0]["webSocketDebuggerUrl"], suppress_origin=True, timeout=120)
        self.n = 0; self.logs = []
        self.send("Runtime.enable"); self.send("Page.enable")

    def _event(self, m):
        meth = m.get("method")
        if meth == "Runtime.consoleAPICalled":
            self.logs.append(" ".join(str(a.get("value", a.get("description", ""))) for a in m["params"]["args"]))
        elif meth == "Runtime.exceptionThrown":
            self.logs.append("EXCEPTION " + json.dumps(m["params"]["exceptionDetails"].get("text")))

    def send(self, method, params=None):
        self.n += 1; mid = self.n
        self.ws.send(json.dumps({"id": mid, "method": method, "params": params or {}}))
        while True:
            m = json.loads(self.ws.recv())
            if m.get("id") == mid:
                if "error" in m: raise RuntimeError(f"{method}: {m['error']}")
                return m.get("result", {})
            self._event(m)

    def pump(self, secs):
        end = time.time() + secs
        self.ws.settimeout(0.05)
        while time.time() < end:
            try: self._event(json.loads(self.ws.recv()))
            except websocket.WebSocketTimeoutException: pass
        self.ws.settimeout(120)

    def js(self, expr):
        r = self.send("Runtime.evaluate", {"expression": expr, "returnByValue": True, "awaitPromise": True})
        if "exceptionDetails" in r: raise RuntimeError(f"JS error in {expr[:80]}: {r['exceptionDetails'].get('text')}")
        return r["result"].get("value")

    def close(self):
        try: self.send("Browser.close")
        except Exception: pass
        try: self.proc.wait(5)
        except Exception: self.proc.kill()
        shutil.rmtree(self.ud, ignore_errors=True)

    # ---- emulation / input ----
    def emulate(self, w, h, dpr, landscape=None):
        land = w > h if landscape is None else landscape
        self.send("Emulation.setDeviceMetricsOverride", {"width": w, "height": h, "deviceScaleFactor": dpr, "mobile": True,
                  "screenWidth": w, "screenHeight": h,
                  "screenOrientation": {"type": "landscapePrimary" if land else "portraitPrimary", "angle": 90 if land else 0}})
        self.send("Emulation.setTouchEmulationEnabled", {"enabled": True, "maxTouchPoints": 5})
        self.send("Emulation.setFocusEmulationEnabled", {"enabled": True})   # headless page keeps focus (timer pauses on blur)

    def tap(self, x, y, hold=0.06, after=0.45):
        pt = {"x": x, "y": y, "radiusX": 2, "radiusY": 2, "force": 1, "id": 1}
        self.send("Input.dispatchTouchEvent", {"type": "touchStart", "touchPoints": [pt]})
        self.pump(hold)
        self.send("Input.dispatchTouchEvent", {"type": "touchEnd", "touchPoints": []})
        self.pump(after)

    def swipe(self, x0, y0, x1, y1, steps=10):
        self.send("Input.dispatchTouchEvent", {"type": "touchStart", "touchPoints": [{"x": x0, "y": y0, "id": 1}]})
        for k in range(1, steps + 1):
            self.send("Input.dispatchTouchEvent", {"type": "touchMove", "touchPoints": [{"x": x0 + (x1 - x0) * k / steps, "y": y0 + (y1 - y0) * k / steps, "id": 1}]})
            self.pump(0.016)
        self.send("Input.dispatchTouchEvent", {"type": "touchEnd", "touchPoints": []})
        self.pump(0.4)

    def drag(self, x, y, dx, dy, steps=10, dt=0.016, settle=0.4):
        """One finger: down at (x,y), move in `steps` equal steps to (x+dx, y+dy), lift there."""
        self.send("Input.dispatchTouchEvent", {"type": "touchStart", "touchPoints": [{"x": x, "y": y, "id": 1}]})
        self.pump(0.03)
        for k in range(1, steps + 1):
            self.send("Input.dispatchTouchEvent", {"type": "touchMove", "touchPoints": [{"x": x + dx * k / steps, "y": y + dy * k / steps, "id": 1}]})
            self.pump(dt)
        self.send("Input.dispatchTouchEvent", {"type": "touchEnd", "touchPoints": []})
        self.pump(settle)

    def pinch(self, cx, cy, d0=30, d1=140, steps=10):
        pts = lambda d: [{"x": cx - d, "y": cy, "id": 1}, {"x": cx + d, "y": cy, "id": 2}]
        self.send("Input.dispatchTouchEvent", {"type": "touchStart", "touchPoints": pts(d0)})
        for k in range(1, steps + 1):
            self.send("Input.dispatchTouchEvent", {"type": "touchMove", "touchPoints": pts(d0 + (d1 - d0) * k / steps)})
            self.pump(0.016)
        self.send("Input.dispatchTouchEvent", {"type": "touchEnd", "touchPoints": []})
        self.pump(0.4)

    def click(self, x, y, after=0.45):   # desktop only
        for t in ("mouseMoved", "mousePressed", "mouseReleased"):
            p = {"type": t, "x": x, "y": y}
            if t != "mouseMoved": p.update(button="left", clickCount=1)
            self.send("Input.dispatchMouseEvent", p); self.pump(0.05)
        self.pump(after)

    def shot(self, path):
        d = base64.b64decode(self.send("Page.captureScreenshot", {"format": "png"})["data"])
        open(path, "wb").write(d)
        return Image.open(io.BytesIO(d)).convert("RGB")

    # ---- game ----
    def boot(self, url, timeout=150):
        self.logs.clear(); t0 = time.time()
        self.send("Page.navigate", {"url": url})
        while time.time() - t0 < timeout:
            self.pump(0.5)
            if any("[SD] title ready" in l for l in self.logs) and (os.environ.get("QA_WAIT_INTRO") != "1" or any("[SD] intro finished" in l for l in self.logs)):
                self.pump(1.5); return round(time.time() - t0, 1)
        raise RuntimeError("no '[SD] title ready' in %ds; last logs %s" % (timeout, self.logs[-10:]))

    def reload(self, timeout=150):
        self.logs.clear(); t0 = time.time()
        self.send("Page.reload", {"ignoreCache": False})
        while time.time() - t0 < timeout:
            self.pump(0.5)
            if any("[SD] title ready" in l for l in self.logs) and (os.environ.get("QA_WAIT_INTRO") != "1" or any("[SD] intro finished" in l for l in self.logs)):
                self.pump(1.5); return round(time.time() - t0, 1)
        raise RuntimeError("no title after reload")

    def dump(self):
        return self.js("SD_DEBUG.dump(), JSON.parse(JSON.stringify(window.SD_QA))")

    def rect(self, name):
        return self.js(f"SD_DEBUG.rect({json.dumps(name)}), window.__sdRect")

    def layout(self):
        return self.js("SD_DEBUG.layout(), window.__sdLayout")

    def metrics(self):
        return self.js("""(()=>{const se=document.scrollingElement, c=document.querySelector('canvas');
          return {sx:scrollX, sy:scrollY, vvScale:visualViewport.scale, vvW:visualViewport.width, vvH:visualViewport.height,
          vvTop:visualViewport.offsetTop, vvLeft:visualViewport.offsetLeft, iw:innerWidth, ih:innerHeight,
          sh:se.scrollHeight, sw:se.scrollWidth, dpr:devicePixelRatio, canvasCss:[c.clientWidth,c.clientHeight], canvasPx:[c.width,c.height],
          touch:('ontouchstart' in window), maxTouch:navigator.maxTouchPoints}})()""")

    def tap_node(self, name, after=0.45):
        r = self.rect(name)
        if not r: raise RuntimeError(f"node {name} not visible")
        self.tap(r["x"] + r["w"] / 2, r["y"] + r["h"] / 2, after=after)
        return r


def metrics_ok(m):
    return (m["sx"] == 0 and m["sy"] == 0 and abs(m["vvScale"] - 1) < 1e-6 and m["sh"] <= m["ih"] and m["sw"] <= m["iw"]
            and m["vvTop"] == 0 and m["vvLeft"] == 0)


def on_screen(r, m, tol=0.5):
    return bool(r) and r["w"] > 0 and r["h"] > 0 and r["x"] >= -tol and r["y"] >= -tol and \
        r["x"] + r["w"] <= m["iw"] + tol and r["y"] + r["h"] <= m["ih"] + tol


def bands(img, dpr, x0, x1, y0, y1, kind):
    """Find button bands by colour (device px screenshot; returns CSS rects). kind 'panel' = gray buttons on the cream
    hint panel; 'menu' = slate buttons on the light-blue harbour."""
    W, H = img.size
    px = img.load()
    def is_btn(p):
        r, g, b = p; lum = 0.299 * r + 0.587 * g + 0.114 * b; sat = max(p) - min(p)
        if kind == "panel": return 70 < lum < 185 and sat < 40
        return 60 < lum < 160 and sat < 40
    # button edges: leftmost / rightmost button-coloured x over the region (text never reaches the edges)
    X0, X1 = int(x0 * dpr), min(W - 1, int(x1 * dpr))
    lefts, rights = [], []
    for y in range(max(0, int(y0 * dpr)), min(H, int(y1 * dpr)), max(1, int(dpr))):
        row = [x for x in range(X0, X1) if is_btn(px[x, y])]
        if len(row) > (X1 - X0) * 0.3: lefts.append(row[0]); rights.append(row[-1])
    if not lefts: return []
    bl, br = min(lefts), max(rights)
    d = max(1, int(dpr))
    xs = [bl + k * d for k in (2, 3, 4, 5, 6)] + [br - k * d for k in (2, 3, 4, 5, 6)]
    rows = []
    for y in range(max(0, int(y0 * dpr)), min(H, int(y1 * dpr))):
        rows.append((y, sum(is_btn(px[min(W - 1, x), y]) for x in xs) >= 8))
    out, start, gap = [], None, 0
    for y, b in rows + [(rows[-1][0] + 1, False)] * 8:
        if b:
            if start is None: start = y
            gap = 0; last = y
        elif start is not None:
            gap += 1
            if gap > 3 * dpr:
                if (last - start) / dpr >= 30: out.append({"x": bl / dpr, "y": start / dpr, "w": (br - bl) / dpr, "h": (last - start + 1) / dpr})
                start = None
    return out


def cream_bbox(img, dpr):
    px = img.load(); W, H = img.size
    xs, ys = [], []
    for y in range(0, H, 2):
        for x in range(0, W, 2):
            r, g, b = px[x, y]
            if abs(r - 255) < 4 and abs(g - 250) < 4 and abs(b - 240) < 5: xs.append(x); ys.append(y)
    if not xs: return None
    return {"x": min(xs) / dpr, "y": min(ys) / dpr, "w": (max(xs) - min(xs)) / dpr, "h": (max(ys) - min(ys)) / dpr}


def hint_buttons(c, img, dpr):
    pb = cream_bbox(img, dpr)
    if not pb: return None, []
    return pb, bands(img, dpr, pb["x"] + 8, pb["x"] + pb["w"] - 8, pb["y"], pb["y"] + pb["h"], "panel")


def grid_geom(c, n):
    g = c.rect("GridView"); lay = c.layout(); upc = lay["unitsPerCss"]
    cp_u = int((min(g["w"], g["h"]) * upc - 6.0) // n)
    side_u = cp_u * n
    ox = g["x"] + int((g["w"] * upc - side_u) // 2) / upc
    oy = g["y"] + int((g["h"] * upc - side_u) // 2) / upc
    return {"ox": ox, "oy": oy, "cp": cp_u / upc, "cp_u": cp_u, "upc": upc, "rect": g}


def cell_center(geo, r, cc):
    return geo["ox"] + (cc + 0.5) * geo["cp"], geo["oy"] + (r + 0.5) * geo["cp"]


def empties(sd):
    n = sd["size"]; return [(r, cc) for r in range(n) for cc in range(n) if sd["grid"][r][cc] == 0]


def candidates(sd, r, cc):
    n = sd["size"]; g = sd["grid"]
    bw, bh = (3, 3) if n == 9 else (3, 2)
    used = set(g[r]) | {g[k][cc] for k in range(n)}
    br, bc = r // bh * bh, cc // bw * bw
    used |= {g[i][j] for i in range(br, br + bh) for j in range(bc, bc + bw)}
    return [d for d in range(1, n + 1) if d not in used]


def glyph_heights(img, box, dpr):
    """Connected dark components (note colour 4a5d6b) inside one cell crop -> glyph ink heights in CSS px."""
    x0, y0, x1, y1 = [int(v * dpr) for v in box]
    ins = int(3 * dpr)
    cr = img.crop((x0 + ins, y0 + ins, x1 - ins, y1 - ins)); W, H = cr.size; px = cr.load()
    dark = [[False] * W for _ in range(H)]
    for y in range(H):
        for x in range(W):
            r, g, b = px[x, y]
            dark[y][x] = (0.299 * r + 0.587 * g + 0.114 * b) < 140 and abs(r - 74) < 60 and abs(b - 107) < 60
    seen = [[False] * W for _ in range(H)]; comps = []
    for y in range(H):
        for x in range(W):
            if dark[y][x] and not seen[y][x]:
                st = [(x, y)]; seen[y][x] = True; ys = []; xs = []
                while st:
                    a, b = st.pop(); ys.append(b); xs.append(a)
                    for da, db in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        u, v = a + da, b + db
                        if 0 <= u < W and 0 <= v < H and dark[v][u] and not seen[v][u]:
                            seen[v][u] = True; st.append((u, v))
                if len(ys) > 4 * dpr: comps.append(((max(ys) - min(ys) + 1) / dpr, (max(xs) - min(xs) + 1) / dpr))
    return comps


def changed_cells(a, b):
    n = len(a); return [(r, cc, a[r][cc], b[r][cc]) for r in range(n) for cc in range(n) if a[r][cc] != b[r][cc]]


def save(name, data):
    p = os.path.join(OUT, name); json.dump(data, open(p, "w"), indent=1); print("wrote", p)


# ------------------------------------------------------------------ mobile viewport run
def run_mobile(tag, port):
    w, h = map(int, tag.split("x")); dpr = DPR[tag]
    R = {"viewport": tag, "dpr": dpr, "checks": {}, "notes": []}
    C = R["checks"]
    def chk(name, ok, **ev): C[name] = {"result": "PASS" if ok else "FAIL", **ev}; return ok
    S = lambda n: os.path.join(SHOTS, f"{tag}_{n}.png")
    c = CDP(port)
    try:
        c.emulate(w, h, dpr)
        R["boot_s"] = c.boot(DEBUG_URL)
        m0 = c.metrics(); R["metrics_boot"] = m0
        R["layout_title"] = c.layout()
        c.shot(S("01_title"))
        # --- title: Play + Settings on screen
        rects = {"PlayButton": c.rect("PlayButton"), "SettingsButton": c.rect("SettingsButton")}
        # Settings by touch (from title) -> Sound visible
        c.tap_node("SettingsButton")
        rects["SoundButton"] = c.rect("SoundButton"); rects["SettingsBack"] = c.rect("SettingsBack")
        st = c.dump(); chk("touch_settings_open", st["screen"] == "settings", screen=st["screen"])
        c.shot(S("02_settings"))
        c.tap_node("SettingsBack"); st = c.dump()
        chk("touch_settings_back", st["screen"] == "title", screen=st["screen"])
        # Play by touch -> harbour
        c.tap_node("PlayButton"); st = c.dump()
        chk("touch_play", st["screen"] == "harbour", screen=st["screen"])
        img = c.shot(S("03_harbour"))
        hs = c.rect("HarbourScroll"); R["harbour_settings_rect_initial"] = c.rect("SettingsButton")
        hb = bands(img, dpr, hs["x"] + 4, hs["x"] + hs["w"] - 14, hs["y"], min(hs["y"] + hs["h"], h), "menu")
        R["harbour_bands"] = hb
        # level select: first slate band in the (unscrolled) harbour list = "Level 1/20" (fresh profile)
        lvl = hb[0] if hb else None; rects["LevelSelect"] = lvl
        if lvl: c.tap(lvl["x"] + lvl["w"] / 2, lvl["y"] + lvl["h"] / 2)
        st = c.dump(); sd = st["stepDump"]
        chk("touch_level_select", st["screen"] == "grid" and sd and sd["level"] in (1, 0), screen=st["screen"], level=sd and sd["level"], size=sd and sd["size"])
        c.pump(0.5); c.shot(S("04_L1"))
        lay1 = c.layout()
        rects_L1 = {n: c.rect(n) for n in ["GridView", "BackButton", "HintButton", "NotesButton", "UndoButton", "EraseButton",
                                            "MistakesLabel", "ObjectiveLabel"] + [f"Digit{d}" for d in range(1, 7)]}
        R["L1_layout"] = lay1
        chk("L1_controls_on_screen", all(on_screen(r, m0) for r in rects_L1.values()),
            off=[k for k, r in rects_L1.items() if not on_screen(r, m0)])
        # Back by touch from grid -> harbour
        c.tap_node("BackButton"); st = c.dump()
        chk("touch_grid_back", st["screen"] == "harbour", screen=st["screen"])
        # swipes / pinch on harbour (page must not scroll or zoom; the game's own list may scroll)
        c.swipe(w / 2, h * 0.8, w / 2, h * 0.2); c.swipe(w / 2, h * 0.2, w / 2, h * 0.8)
        c.swipe(w * 0.9, h / 2, w * 0.1, h / 2); c.swipe(w * 0.1, h / 2, w * 0.9, h / 2)
        c.pinch(w / 2, h / 2)
        m_h = c.metrics(); R["metrics_after_harbour_swipes"] = m_h
        c.shot(S("03b_harbour_after_swipes"))
        # --- 9x9: L11 (jump via SD_DEBUG.startLevel, then touch only)
        c.js("SD_DEBUG.startLevel(11)"); c.pump(1.0)
        st = c.dump(); sd = st["stepDump"]; n = sd["size"]
        R["L11_level"] = sd["level"]; R["L11_size"] = n
        c.shot(S("05_L11"))
        names = ["GridView", "BackButton", "HintButton", "NotesButton", "UndoButton", "EraseButton", "MistakesLabel",
                 "ObjectiveLabel"] + [f"Digit{d}" for d in range(1, 10)]
        rects_L11 = {k: c.rect(k) for k in names}
        geo = grid_geom(c, n); R["grid_geom"] = geo
        grid_box = {"x": geo["ox"], "y": geo["oy"], "w": geo["cp"] * n, "h": geo["cp"] * n}
        rects_L11["GridCells"] = grid_box
        chk("L11_controls_on_screen", all(on_screen(r, m0) for r in rects_L11.values()),
            off=[k for k, r in rects_L11.items() if not on_screen(r, m0)])
        R["touch_target_min_css"] = {k: round(min(r["w"], r["h"]), 1) for k, r in rects_L11.items() if r and k.startswith(("Digit", "Notes", "Undo", "Erase", "Hint", "Back"))}
        R["cell_css"] = round(geo["cp"], 2)
        # --- one tap = one digit
        emp = empties(sd); sol = sd["solution"]
        (r1, c1) = emp[0]
        x, y = cell_center(geo, r1, c1); c.tap(x, y)
        d0 = c.dump()["stepDump"]
        c.tap_node(f"Digit{sol[r1][c1]}")
        d1 = c.dump()["stepDump"]
        ch = changed_cells(d0["grid"], d1["grid"])
        chk("one_tap_one_digit", ch == [(r1, c1, 0, sol[r1][c1])] and len(d1["undo"]) == len(d0["undo"]) + 1 and d1["mistakes"] == d0["mistakes"],
            changed=ch, undo=[len(d0["undo"]), len(d1["undo"])])
        # --- Notes: one tap toggles exactly one note
        c.tap_node("NotesButton")
        sd = d1; emp = empties(sd)
        # pick an empty cell with >= 4 candidates for the legibility shot
        emp.sort(key=lambda rc: -len(candidates(sd, *rc)))
        (r2, c2) = emp[0]; cands = candidates(sd, r2, c2)
        idx = r2 * n + c2
        x, y = cell_center(geo, r2, c2); c.tap(x, y)
        a = c.dump()["stepDump"]
        c.tap_node(f"Digit{cands[0]}"); b = c.dump()["stepDump"]
        c.tap_node(f"Digit{cands[0]}"); b2 = c.dump()["stepDump"]
        bit = 1 << (cands[0] - 1)
        ok_on = b["notes"][idx] == a["notes"][idx] ^ bit and b["grid"] == a["grid"] and len(b["undo"]) == len(a["undo"]) + 1
        ok_off = b2["notes"][idx] == a["notes"][idx] and len(b2["undo"]) == len(a["undo"]) + 2
        others_same = all(b["notes"][k] == a["notes"][k] for k in range(n * n) if k != idx)
        chk("notes_one_tap_one_toggle", ok_on and ok_off and others_same,
            cell=[r2, c2], digit=cands[0], mask=[a["notes"][idx], b["notes"][idx], b2["notes"][idx]], undo=[len(a["undo"]), len(b["undo"]), len(b2["undo"])])
        # fast taps (150 ms apart) on several candidates: each lands once
        for d in cands: c.tap_node(f"Digit{d}", after=0.15)
        c.pump(0.6); fd = c.dump()["stepDump"]
        want = 0
        for d in cands: want |= 1 << (d - 1)
        chk("notes_fast_taps", fd["notes"][idx] == want, cands=cands, mask=fd["notes"][idx], want=want)
        # deselect: tap a cell far away (not given) so the notes cell isn't highlighted
        far = [rc for rc in empties(fd) if rc[0] // 3 != r2 // 3 and rc[1] // 3 != c2 // 3 and rc[0] != r2 and rc[1] != c2]
        c.tap_node("NotesButton")  # notes off
        if far: c.tap(*cell_center(geo, *far[0]))
        img = c.shot(S("06_L11_notes"))
        box = (geo["ox"] + c2 * geo["cp"], geo["oy"] + r2 * geo["cp"], geo["ox"] + (c2 + 1) * geo["cp"], geo["oy"] + (r2 + 1) * geo["cp"])
        crop = img.crop(tuple(int(v * dpr) for v in box))
        crop.resize((crop.width * 4, crop.height * 4), Image.NEAREST).save(S("06b_L11_notes_crop_x4"))
        comps = glyph_heights(img, box, dpr)
        hs_ = sorted(cw[0] for cw in comps)
        font_u = int(geo["cp_u"] / 3); font_css = font_u / geo["upc"]
        R["notes_legibility"] = {"cell": [r2, c2], "notes": cands, "cell_css": round(geo["cp"], 2), "font_units": font_u,
                                 "font_css": round(font_css, 2), "glyphs_found": len(comps),
                                 "ink_height_css_median": hs_[len(hs_) // 2] if hs_ else None, "ink_heights_css": hs_}
        chk("notes_legible_9px", font_css >= 9 and len(comps) >= len(cands) - 1, font_css=round(font_css, 2),
            ink_median=R["notes_legibility"]["ink_height_css_median"])
        # --- Undo: one tap undoes exactly one step
        u0 = c.dump()["stepDump"]
        c.tap_node("UndoButton"); u1 = c.dump()["stepDump"]
        snap = u0["undo"][-1]
        chk("undo_one_tap_one_step", len(u1["undo"]) == len(u0["undo"]) - 1 and
            [v for row in u1["grid"] for v in row] == snap["cells"] and u1["notes"] == snap["notes"],
            undo=[len(u0["undo"]), len(u1["undo"])], mask_before=u0["notes"][idx], mask_after=u1["notes"][idx])
        # --- Erase: select the notes cell, Erase clears it (one step)
        c.tap(*cell_center(geo, r2, c2)); e0 = c.dump()["stepDump"]
        c.tap_node("EraseButton"); e1 = c.dump()["stepDump"]
        chk("touch_erase", e1["notes"][idx] == 0 and len(e1["undo"]) == len(e0["undo"]) + 1, mask=[e0["notes"][idx], e1["notes"][idx]])
        # --- swipes on the grid screen (no page scroll / zoom; no stray placements)
        g0 = c.dump()["stepDump"]
        c.swipe(w / 2, h * 0.85, w / 2, h * 0.15); c.swipe(w / 2, h * 0.15, w / 2, h * 0.85)
        c.swipe(w * 0.95, h / 2, w * 0.05, h / 2); c.pinch(w / 2, h / 2)
        m_g = c.metrics(); R["metrics_after_grid_swipes"] = m_g
        g1 = c.dump()["stepDump"]
        R["grid_after_swipes_same"] = g1["grid"] == g0["grid"]
        # --- Hint panel by touch: Teach, Show last hint, Back, Reveal
        tok0 = c.dump()["profile"]["tokens"]
        emp = empties(g1); (r3, c3) = emp[-1]
        c.tap(*cell_center(geo, r3, c3))
        c.tap_node("HintButton"); st = c.dump()
        img = c.shot(S("07_hint_panel"))
        pb, hb = hint_buttons(c, img, dpr)
        R["hint_panel_1"] = {"panel": pb, "buttons": hb, "overlay": st and c.layout()["overlay"]}
        chk("hint_panel_opens_on_screen", c.layout()["overlay"] == "HintPanel" and pb is not None and on_screen(pb, m0) and len(hb) >= 3
            and all(on_screen(b_, m0) for b_ in hb), panel=pb, nbuttons=len(hb))
        teach, reveal, back = hb[-3], hb[-2], hb[-1]
        c.tap(teach["x"] + teach["w"] / 2, teach["y"] + teach["h"] / 2, after=0.8)
        st = c.dump(); step1 = st["stepDump"]["game_step"]
        chk("touch_teach", st["profile"]["tokens"] == tok0 - 1 and step1 is not None and c.layout()["overlay"] == "",
            tokens=[tok0, st["profile"]["tokens"]], step=step1)
        c.shot(S("08_after_teach"))
        c.tap_node("HintButton")
        img = c.shot(S("09_hint_panel_with_reshow")); pb2, hb2 = hint_buttons(c, img, dpr)
        rs = c.rect("ReshowHint")
        R["hint_panel_2"] = {"panel": pb2, "buttons": hb2, "ReshowHint": rs}
        chk("hint_panel2_on_screen", rs is not None and on_screen(rs, m0) and len(hb2) >= 4 and all(on_screen(b_, m0) for b_ in hb2), nbuttons=len(hb2))
        coins0 = st["profile"]["coins"]; tok1 = st["profile"]["tokens"]
        c.tap(rs["x"] + rs["w"] / 2, rs["y"] + rs["h"] / 2, after=0.8)
        st = c.dump()
        chk("touch_show_last_hint_free", st["profile"]["tokens"] == tok1 and st["profile"]["coins"] == coins0 and c.layout()["overlay"] == ""
            and st["stepDump"]["game_step"] == step1, tokens=[tok1, st["profile"]["tokens"]], coins=[coins0, st["profile"]["coins"]])
        c.tap_node("HintButton"); img = c.shot(S("09b_hint_panel3")); pb3, hb3 = hint_buttons(c, img, dpr)
        bk = hb3[-1]; c.tap(bk["x"] + bk["w"] / 2, bk["y"] + bk["h"] / 2)
        st = c.dump()
        chk("touch_hint_back", c.layout()["overlay"] == "" and st["profile"]["tokens"] == tok1, overlay=c.layout()["overlay"])
        # Reveal on the selected empty cell (r3,c3)
        c.tap(*cell_center(geo, r3, c3)); v0 = c.dump()["stepDump"]
        c.tap_node("HintButton"); img = c.shot(S("09c_hint_panel4")); pb4, hb4 = hint_buttons(c, img, dpr)
        rv = hb4[-2]; c.tap(rv["x"] + rv["w"] / 2, rv["y"] + rv["h"] / 2, after=0.8)
        st = c.dump(); v1 = st["stepDump"]
        chk("touch_reveal", v1["reveals"] == v0["reveals"] + 1 and v1["grid"][r3][c3] == sol[r3][c3] and st["profile"]["tokens"] == tok1 - 1,
            reveals=[v0["reveals"], v1["reveals"]], tokens=[tok1, st["profile"]["tokens"]])
        # --- Sound via settings by touch, then reload
        c.tap_node("BackButton"); c.pump(0.3)
        # harbour list scrolling by touch. (a) a swipe that STARTS ON A BUTTON (most of the list is buttons)
        mm = c.metrics(); hs = c.rect("HarbourScroll")
        img = c.shot(S("09d_harbour_before_scroll"))
        hb2 = [b_ for b_ in bands(img, dpr, hs["x"] + 4, hs["x"] + hs["w"] - 14, hs["y"], min(hs["y"] + hs["h"], h), "menu") if on_screen(b_, mm)]
        y_set0 = c.rect("SettingsButton")["y"]; b_ = hb2[min(2, len(hb2) - 1)]; scr0 = c.dump()["screen"]
        dist = min(150, b_["y"] + b_["h"] / 2 - 2)
        c.swipe(hs["x"] + hs["w"] * 0.5, b_["y"] + b_["h"] / 2, hs["x"] + hs["w"] * 0.5, b_["y"] + b_["h"] / 2 - dist, steps=20); c.pump(0.8)
        y_set1 = c.rect("SettingsButton")["y"]; scr1 = c.dump()["screen"]
        chk("harbour_list_scrolls_from_button_swipe", y_set1 < y_set0 - 20, settings_y=[round(y_set0, 1), round(y_set1, 1)],
            swipe_start=[round(hs["x"] + hs["w"] * 0.5), round(b_["y"] + b_["h"] / 2)], drag_css=round(dist), stray_press=scr1 != scr0)
        # (b) swipes that start on a non-button spot (label / gap) until harbour Settings is on screen
        swipes = 0
        while not on_screen(c.rect("SettingsButton"), mm) and swipes < 8:
            img = c.shot("/tmp/_qa8_h.png"); pxl = img.load()
            xs_ = [int((hs["x"] + hs["w"] * f) * dpr) for f in (0.06, 0.1, 0.15, 0.2, 0.25)]
            def free(yc):
                return all(not (60 < 0.299 * pxl[x_, int(yy * dpr)][0] + 0.587 * pxl[x_, int(yy * dpr)][1] + 0.114 * pxl[x_, int(yy * dpr)][2] < 160
                                and max(pxl[x_, int(yy * dpr)]) - min(pxl[x_, int(yy * dpr)]) < 40) for x_ in xs_ for yy in (yc - 3, yc, yc + 3))
            ys_ = [yy for yy in range(int(min(h, hs["y"] + hs["h"])) - 6, int(hs["y"] + 6), -2) if free(yy)]
            if not ys_: break
            y_start = ys_[0]
            c.swipe(hs["x"] + hs["w"] * 0.15, y_start, hs["x"] + hs["w"] * 0.15, max(1, hs["y"] + 2), steps=20); swipes += 1
            c.pump(0.8)
        R["harbour_settings_label_swipes_needed"] = swipes; R["harbour_settings_rect"] = c.rect("SettingsButton")
        c.shot(S("09e_harbour_scrolled_to_settings"))
        chk("harbour_settings_reachable_by_scroll", on_screen(c.rect("SettingsButton"), mm), label_swipes=swipes)
        c.tap_node("SettingsButton")   # harbour Settings
        s0 = c.dump()["profile"]["sound_on"]
        c.tap_node("SoundButton"); s1 = c.dump()["profile"]["sound_on"]
        c.shot(S("10_settings_sound_off"))
        R["reload_s"] = c.reload()
        s2 = c.dump()["profile"]["sound_on"]
        c.tap_node("SettingsButton"); c.shot(S("11_settings_after_reload"))
        chk("sound_off_persists_reload", s0 is True and s1 is False and s2 is False, sound=[s0, s1, s2])
        m_end = c.metrics(); R["metrics_end"] = m_end
        chk("no_zoom_no_scroll", all(metrics_ok(mm) for mm in (m0, m_h, m_g, m_end)) and m0["iw"] == w and m0["ih"] == h,
            boot=m0, after_harbour_swipes={k: m_h[k] for k in ("sx", "sy", "vvScale", "sh", "ih", "sw", "iw")},
            after_grid_swipes={k: m_g[k] for k in ("sx", "sy", "vvScale", "sh", "ih", "sw", "iw")})
        rects["LevelSelect"] = lvl
        chk("menu_controls_on_screen", all(on_screen(r, m0) for r in rects.values()), off=[k for k, r in rects.items() if not on_screen(r, m0)])
        R["rects_menu"] = rects; R["rects_L11"] = rects_L11
        R["errors"] = [l for l in c.logs if "ERROR" in l or "EXCEPTION" in l][:20]
    except Exception as e:
        import traceback; R["exception"] = traceback.format_exc(); print(R["exception"])
        try: c.shot(S("99_exception"))
        except Exception: pass
    finally:
        c.close()
    save(f"mobile_{tag}.json", R)
    print(json.dumps({k: v["result"] for k, v in C.items()}, indent=1))
    return R


# ------------------------------------------------------------------ rotation
def run_rotate(port, pw=390, ph=844, dpr=3):
    R = {"checks": {}}; C = R["checks"]
    def chk(name, ok, **ev): C[name] = {"result": "PASS" if ok else "FAIL", **ev}; return ok
    rt = "" if (pw, ph) == (390, 844) else f"{pw}x{ph}_"
    S = lambda nme: os.path.join(SHOTS, f"rotate_{rt}{nme}.png")
    c = CDP(port)
    def state():
        st = c.dump(); sd = st["stepDump"]; lay = c.layout()
        return {"grid": sd["grid"], "notes": sd["notes"], "mistakes": sd["mistakes"], "elapsed": sd["elapsed_ms"], "level": sd["level"],
                "undo": len(sd["undo"]), "step": sd["game_step"], "running": sd["timer_running"], "screen": st["screen"],
                "overlay": lay["overlay"], "css": lay["cssSize"], "compact": lay["compact"], "tokens": st["profile"]["tokens"], "coins": st["profile"]["coins"]}
    def css_is(a, wh):   # game cssSize = canvas px / DPR; fractional DPR (2.625) rounds to whole device px -> allow 1 CSS px
        return abs(a[0] - wh[0]) <= 1 and abs(a[1] - wh[1]) <= 1
    def controls_ok(m):
        names = ["GridView", "BackButton", "HintButton", "NotesButton", "UndoButton", "EraseButton", "MistakesLabel"] + [f"Digit{d}" for d in range(1, 10)]
        rr = {k: c.rect(k) for k in names}
        return [k for k, r in rr.items() if not on_screen(r, m)]
    try:
        c.emulate(pw, ph, dpr); R["boot_s"] = c.boot(DEBUG_URL)
        c.js("SD_DEBUG.startLevel(15)"); c.pump(1.0)   # L15 = 9x9 Beat the Tide: the level timer runs
        sd = c.dump()["stepDump"]; n = sd["size"]; sol = sd["solution"]
        geo = grid_geom(c, n)
        emp = empties(sd)
        for (r, cc) in emp[:2]:
            c.tap(*cell_center(geo, r, cc)); c.tap_node(f"Digit{sol[r][cc]}")
        # a note
        c.tap_node("NotesButton"); (rn, cn) = emp[3]; c.tap(*cell_center(geo, rn, cn))
        for d in candidates(c.dump()["stepDump"], rn, cn)[:3]: c.tap_node(f"Digit{d}")
        c.tap_node("NotesButton")
        # a paid Teach (before any wrong digit)
        c.tap_node("HintButton"); img = c.shot(S("00_panel")); pb, hb = hint_buttons(c, img, dpr)
        t = hb[-3]; c.tap(t["x"] + t["w"] / 2, t["y"] + t["h"] / 2, after=0.8)
        # one wrong digit -> mistakes 1
        (rw, cw) = emp[5]; wrong = next(d for d in range(1, 10) if d != sol[rw][cw])
        c.tap(*cell_center(geo, rw, cw)); c.tap_node(f"Digit{wrong}")
        c.pump(3.0)
        s0 = state(); c.shot(S("01_portrait_midrun")); t0 = time.time()
        R["before"] = {k: s0[k] for k in ("mistakes", "elapsed", "level", "undo", "step", "screen", "overlay", "css")}
        # rotate -> landscape
        c.emulate(ph, pw, dpr); c.pump(2.0)
        m1 = c.metrics(); s1 = state(); c.shot(S("02_landscape_midrun")); t1 = time.time()
        off1 = controls_ok(m1)
        chk("rotate_to_landscape_keeps_run", s1["grid"] == s0["grid"] and s1["notes"] == s0["notes"] and s1["mistakes"] == s0["mistakes"] == 1
            and s1["level"] == s0["level"] and s1["undo"] == s0["undo"] and s1["step"] == s0["step"] and s1["screen"] == "grid"
            and s0["running"] and s1["running"] and s0["elapsed"] > 2000 and s0["elapsed"] < s1["elapsed"] <= s0["elapsed"] + (t1 - t0) * 1000 + 1500,
            mistakes=s1["mistakes"], elapsed=[s0["elapsed"], s1["elapsed"]], running=[s0["running"], s1["running"]], level=s1["level"], css=s1["css"])
        chk("rotate_to_landscape_refits", css_is(s1["css"], [ph, pw]) and not off1 and metrics_ok(m1), css=s1["css"], off=off1, compact=s1["compact"])
        # back to portrait
        c.emulate(pw, ph, dpr); c.pump(2.0)
        m2 = c.metrics(); s2 = state(); c.shot(S("03_portrait_again")); t2 = time.time()
        off2 = controls_ok(m2)
        chk("rotate_back_keeps_run", s2["grid"] == s0["grid"] and s2["notes"] == s0["notes"] and s2["mistakes"] == 1 and s2["undo"] == s0["undo"]
            and s2["step"] == s0["step"] and s1["elapsed"] <= s2["elapsed"] <= s0["elapsed"] + (t2 - t0) * 1000 + 1500,
            elapsed=[s1["elapsed"], s2["elapsed"]])
        chk("rotate_back_refits", css_is(s2["css"], [pw, ph]) and not off2 and metrics_ok(m2), css=s2["css"], off=off2)
        # with the hint panel open
        c.tap_node("HintButton"); c.pump(0.5)
        p0 = state(); img = c.shot(S("04_portrait_panel")); pb0, hb0 = hint_buttons(c, img, dpr); c.pump(1.5); p0b = state()
        c.emulate(ph, pw, dpr); c.pump(2.0)
        m3 = c.metrics(); p1 = state(); img = c.shot(S("05_landscape_panel")); pb1, hb1 = hint_buttons(c, img, dpr)
        chk("rotate_with_panel_keeps_state", p1["overlay"] == "HintPanel" and p1["grid"] == s0["grid"] and p1["notes"] == s0["notes"]
            and p1["mistakes"] == 1 and p1["tokens"] == p0["tokens"] and p1["coins"] == p0["coins"] and p1["step"] == s0["step"]
            and not p1["running"] and abs(p1["elapsed"] - p0["elapsed"]) <= 100 and p0b["elapsed"] == p0["elapsed"],
            overlay=p1["overlay"], elapsed_paused=[p0["elapsed"], p0b["elapsed"], p1["elapsed"]], running=p1["running"])
        chk("rotate_with_panel_refits", css_is(p1["css"], [ph, pw]) and pb1 is not None and on_screen(pb1, m3) and len(hb1) == len(hb0) >= 4
            and all(on_screen(b_, m3) for b_ in hb1) and metrics_ok(m3), panel=pb1, nbuttons=[len(hb0), len(hb1)])
        c.emulate(pw, ph, dpr); c.pump(2.0)
        m4 = c.metrics(); p2 = state(); img = c.shot(S("06_portrait_panel_again")); pb2, hb2 = hint_buttons(c, img, dpr)
        chk("rotate_back_with_panel", p2["overlay"] == "HintPanel" and p2["grid"] == s0["grid"] and p2["mistakes"] == 1 and not p2["running"]
            and pb2 is not None and on_screen(pb2, m4) and len(hb2) == len(hb0) and all(on_screen(b_, m4) for b_ in hb2), nbuttons=len(hb2))
        # Back to grid by touch after the rotations; the panel buttons still work
        bk = hb2[-1]; c.tap(bk["x"] + bk["w"] / 2, bk["y"] + bk["h"] / 2); c.pump(1.2)
        p3 = state(); c.shot(S("07_after_back"))
        chk("panel_back_after_rotation", p3["overlay"] == "" and p3["running"] and p3["grid"] == s0["grid"] and p3["elapsed"] > p2["elapsed"],
            elapsed=[p2["elapsed"], p3["elapsed"]])
        R["errors"] = [l for l in c.logs if "ERROR" in l or "EXCEPTION" in l][:20]
    except Exception:
        import traceback; R["exception"] = traceback.format_exc(); print(R["exception"])
        try: c.shot(S("99_exception"))
        except Exception: pass
    finally:
        c.close()
    save(f"rotate{'' if not rt else '_' + rt[:-1]}.json", R)
    print(json.dumps({k: v["result"] for k, v in C.items()}, indent=1))


# ------------------------------------------------------------------ desktop 1280x800 (no emulation, mouse)
def run_desktop(port):
    R = {"checks": {}}; C = R["checks"]
    def chk(name, ok, **ev): C[name] = {"result": "PASS" if ok else "FAIL", **ev}; return ok
    S = lambda nme: os.path.join(SHOTS, f"desktop_{nme}.png")
    c = CDP(port, window_size=(1280, 800))
    try:
        c.send("Page.navigate", {"url": "about:blank"}); c.pump(0.5)
        wid = c.send("Browser.getWindowForTarget")["windowId"]
        for _ in range(3):
            iw, ih = c.js("[innerWidth, innerHeight]")
            b = c.send("Browser.getWindowBounds", {"windowId": wid})["bounds"]
            c.send("Browser.setWindowBounds", {"windowId": wid, "bounds": {"width": b["width"] + 1280 - iw, "height": b["height"] + 800 - ih}}); c.pump(0.3)
        R["boot_s"] = c.boot(DEBUG_URL); m = c.metrics(); R["metrics"] = m
        chk("desktop_viewport_1280x800_no_emulation", m["iw"] == 1280 and m["ih"] == 800 and m["dpr"] == 1 and not m["touch"], metrics=m)
        c.shot(S("01_title")); R["layout"] = c.layout()
        c.js("SD_DEBUG.startLevel(11)"); c.pump(1.2)
        img = c.shot(S("02_L11"))
        names = ["GridView", "BackButton", "HintButton", "NotesButton", "UndoButton", "EraseButton", "MistakesLabel", "ObjectiveLabel"] + [f"Digit{d}" for d in range(1, 10)]
        rr = {k: c.rect(k) for k in names}
        sd = c.dump()["stepDump"]; geo = grid_geom(c, sd["size"])
        gb = {"x": geo["ox"], "y": geo["oy"], "w": geo["cp"] * 9, "h": geo["cp"] * 9}
        rr["GridCells"] = gb; R["rects"] = rr; R["layout_L11"] = c.layout()
        # bottom border row of the grid must be drawn (thick line colour 2d4a5a) inside the viewport
        px = img.load(); yb = int(gb["y"] + gb["h"]) ; xs = range(int(gb["x"]) + 5, int(gb["x"] + gb["w"]) - 5, 7)
        border_rows = [y for y in range(yb - 3, min(800, yb + 3)) if sum(1 for x in xs if abs(px[x, y][0] - 0x2d) < 25 and abs(px[x, y][2] - 0x5a) < 25) > 0.8 * len(xs)]
        chk("desktop_not_clipped", all(on_screen(r, m) for r in rr.values()) and bool(border_rows) and metrics_ok(m),
            off=[k for k, r in rr.items() if not on_screen(r, m)], grid=gb, bottom_border_rows=border_rows)
        # compare with run7 desktop shot of 718bfec
        ref = Image.open(os.path.join(OUT, "..", DESKTOP_REF)).convert("RGB")
        R["ref_size"] = ref.size
        if ref.size == img.size:
            from PIL import ImageChops
            diff = ImageChops.difference(ref, img).convert("L"); bbox = diff.getbbox()
            hist = diff.point(lambda v: 255 if v > 40 else 0).histogram()[255]
            R["diff_vs_run7"] = {"bbox": bbox, "pixels_gt40": hist, "fraction": round(hist / (1280 * 800), 4)}
            diff.point(lambda v: 255 if v > 40 else 0).save(S("02c_diff_vs_run7"))
        Image.fromarray if False else None
        side = Image.new("RGB", (img.width + ref.width, max(img.height, ref.height)), "white"); side.paste(ref, (0, 0)); side.paste(img, (ref.width, 0))
        side.save(S(f"02b_side_by_side_ref_vs_{BUILD}"))
        # hint smoke: 3 paid Teaches all different; Show last hint again free
        st = c.dump(); tok = st["profile"]["tokens"]; coins = st["profile"]["coins"]
        if tok < 3: c.js("SD_DEBUG.setTokens(3)"); tok = 3   # setup only
        steps = []; spent = []
        for k in range(3):
            hb_ = c.rect("HintButton"); c.click(hb_["x"] + hb_["w"] / 2, hb_["y"] + hb_["h"] / 2)
            img = c.shot(S(f"03_hint_panel_{k+1}")); pb, bb = hint_buttons(c, img, 1)
            t = bb[-3]; t0 = c.dump()["profile"]
            c.click(t["x"] + t["w"] / 2, t["y"] + t["h"] / 2, after=0.8)
            st = c.dump(); steps.append(st["stepDump"]["game_step"]); spent.append((t0["tokens"], st["profile"]["tokens"], t0["coins"], st["profile"]["coins"]))
            c.shot(S(f"04_teach_{k+1}"))
        distinct = len({json.dumps(s, sort_keys=True) for s in steps}) == 3 and all(s for s in steps)
        chk("desktop_3_paid_teaches_distinct", distinct and all(a - b == 1 and cc == dd for a, b, cc, dd in spent), steps=steps, spent=spent)
        hb_ = c.rect("HintButton"); c.click(hb_["x"] + hb_["w"] / 2, hb_["y"] + hb_["h"] / 2)
        c.shot(S("05_panel_reshow"))
        rs = c.rect("ReshowHint"); p0 = c.dump()["profile"]
        c.click(rs["x"] + rs["w"] / 2, rs["y"] + rs["h"] / 2, after=0.8)
        st = c.dump(); p1 = st["profile"]
        c.shot(S("06_after_reshow"))
        chk("desktop_reshow_free", rs is not None and p1["tokens"] == p0["tokens"] and p1["coins"] == p0["coins"] and st["stepDump"]["game_step"] == steps[-1],
            tokens=[p0["tokens"], p1["tokens"]], coins=[p0["coins"], p1["coins"]])
        # harbour list with the mouse: click-and-drag on a button, then normal clicks, then the wheel
        c.js("SD_DEBUG.show('harbour')"); c.pump(1.0)
        hs = c.rect("HarbourScroll"); img = c.shot(S("07_harbour"))
        bb = bands(img, 1, hs["x"] + 4, hs["x"] + hs["w"] - 14, hs["y"], min(hs["y"] + hs["h"], 800), "menu")
        bb = [b_ for b_ in bb if on_screen(b_, m)]
        R["harbour_bands"] = bb
        trow = min(bb, key=lambda b_: b_["h"])   # the T1-T4 row is the shortest band (Resume/Level/Quick/Classic are taller)
        def tier(): return c.dump()["profile"]["classic_tier"]
        def tx(k): return trow["x"] + trow["w"] * (2 * k - 1) / 8
        ty = trow["y"] + trow["h"] / 2
        def mdrag(x, y, dy, steps=10):
            c.send("Input.dispatchMouseEvent", {"type": "mouseMoved", "x": x, "y": y}); c.pump(0.03)
            c.send("Input.dispatchMouseEvent", {"type": "mousePressed", "x": x, "y": y, "button": "left", "clickCount": 1}); c.pump(0.05)
            for k in range(1, steps + 1):
                c.send("Input.dispatchMouseEvent", {"type": "mouseMoved", "x": x, "y": y + dy * k / steps, "button": "left", "buttons": 1}); c.pump(0.016)
            c.send("Input.dispatchMouseEvent", {"type": "mouseReleased", "x": x, "y": y + dy, "button": "left", "clickCount": 1}); c.pump(0.6)
        sy = lambda: c.rect("SettingsButton")["y"]
        t0 = tier(); y0 = sy(); k = 2 if t0 != 2 else 3
        mdrag(tx(k), ty, -(trow["h"] / 2 + 15)); t1 = tier(); y1 = sy(); scr1 = c.dump()["screen"]
        R["mouse_drag_off_button"] = {"tier": [t0, t1], "settings_y": [y0, y1], "screen": scr1}
        k2 = 3 if t1 != 3 else 4
        mdrag(tx(k2), ty, -4, steps=4); t2 = tier()      # small mouse jitter inside the button = click
        c.click(tx(1), ty); t3 = tier()
        hb_ = c.rect("BackButton")
        chk("desktop_mouse_drag_then_clicks_work", scr1 == "harbour" and t1 == t0 and t2 == k2 and t3 == 1,
            drag_off_button=R["mouse_drag_off_button"], jitter_click_tier=t2, click_tier=t3)
        # wheel over the list
        cx_, cy_ = hs["x"] + hs["w"] / 2, hs["y"] + min(hs["h"], 800 - hs["y"]) / 2
        y0 = sy()
        c.send("Input.dispatchMouseEvent", {"type": "mouseWheel", "x": cx_, "y": cy_, "deltaX": 0, "deltaY": 300}); c.pump(0.8)
        y1 = sy()
        c.send("Input.dispatchMouseEvent", {"type": "mouseWheel", "x": cx_, "y": cy_, "deltaX": 0, "deltaY": -300}); c.pump(0.8)
        y2 = sy(); c.shot(S("08_harbour_after_wheel"))
        R["wheel"] = {"settings_y": [y0, y1, y2], "list_overflows": y0 + 40 > 800}
        chk("desktop_mouse_wheel_scrolls", y1 < y0 - 20 and abs(y2 - y0) < 2, settings_y=[round(y0, 1), round(y1, 1), round(y2, 1)])
        c.click(tx(2), ty); chk("desktop_click_after_wheel", tier() == 2)
        R["errors"] = [l for l in c.logs if "ERROR" in l or "EXCEPTION" in l][:20]
        chk("desktop_no_console_errors", not R["errors"], errors=R["errors"])
    except Exception:
        import traceback; R["exception"] = traceback.format_exc(); print(R["exception"])
    finally:
        c.close()
    save("desktop.json", R)
    print(json.dumps({k: v["result"] for k, v in C.items()}, indent=1))


# ------------------------------------------------------------------ release boot check (no SD_DEBUG in release)
def run_release(port, tag="390x844"):
    w, h = map(int, tag.split("x")); dpr = DPR[tag]
    R = {"url": RELEASE_URL, "viewport": tag, "checks": {}}; C = R["checks"]
    def chk(name, ok, **ev): C[name] = {"result": "PASS" if ok else "FAIL", **ev}; return ok
    S = lambda nme: os.path.join(SHOTS, f"release_{tag}_{nme}.png")
    c = CDP(port)
    try:
        c.emulate(w, h, dpr)
        try: R["boot_s"] = c.boot(RELEASE_URL, timeout=90); booted = True
        except RuntimeError: booted = False
        img = c.shot(S("01_title")); m = c.metrics(); R["metrics"] = m
        R["sd_debug_present"] = c.js("typeof window.SD_DEBUG !== 'undefined' || typeof window.SD_QA !== 'undefined'")
        chk("release_boots_title", booted, boot_s=R.get("boot_s"), logs=c.logs[:8])
        chk("release_no_debug_hooks", R["sd_debug_present"] is False)
        chk("release_no_zoom_scroll", metrics_ok(m) and m["iw"] == w and m["ih"] == h, metrics=m)
        # tap Play: first slate band in the title panel (cream box)
        pb = cream_bbox(img, dpr); bb = bands(img, dpr, pb["x"] + 8, pb["x"] + pb["w"] - 8, pb["y"], pb["y"] + pb["h"], "menu") if pb else []
        R["title_buttons"] = bb
        if bb: c.tap(bb[0]["x"] + bb[0]["w"] / 2, bb[0]["y"] + bb[0]["h"] / 2); c.pump(1.0)
        img2 = c.shot(S("02_after_play_tap"))
        changed = cream_bbox(img2, dpr) is None   # harbour has no cream title panel
        m2 = c.metrics()
        chk("release_play_tap_reaches_harbour", changed and metrics_ok(m2), title_buttons=len(bb))
        # tap the first harbour list button (Level 1/20) -> grid screen (harbour list starts below the harbour art)
        hb = [b_ for b_ in bands(img2, dpr, 4, w - 14, h * 0.45, h, "menu")]
        if hb: c.tap(hb[0]["x"] + hb[0]["w"] / 2, hb[0]["y"] + hb[0]["h"] / 2); c.pump(1.5)
        img3 = c.shot(S("03_after_level_tap"))
        # grid screen: the cream/white board (fffdf7) covers a big square area
        pxl = img3.load(); W3, H3 = img3.size
        board_px = sum(1 for y in range(0, H3, 6) for x in range(0, W3, 6) if pxl[x, y] == (255, 253, 247))
        R["board_pixels_sampled"] = board_px
        chk("release_level1_tap_opens_grid", board_px > 0.15 * (W3 // 6) * (H3 // 6) and metrics_ok(c.metrics()), board_frac=round(board_px / ((W3 // 6) * (H3 // 6)), 3))
        # harbour drag-scroll in the release (no hooks: measured on screenshots). Back to the harbour first.
        c.tap(30, 20, after=1.0)   # grid Back (top-left)
        imgA = c.shot(S("04_harbour_before_drag"))
        bA = bands(imgA, dpr, 4, w - 14, h * 0.45, h, "menu")
        b0 = bA[0]; D = 100
        c.drag(b0["x"] + b0["w"] * 0.3, b0["y"] + b0["h"] / 2, 0, -D, steps=15); c.pump(0.5)
        imgB = c.shot(S("05_harbour_after_button_drag"))
        bB = bands(imgB, dpr, 4, w - 14, h * 0.2, h, "menu")
        # the band that was 2nd (Quick) should now be ~D higher; no grid opened (no big board area)
        pxl = imgB.load(); W3, H3 = imgB.size
        board_frac = sum(1 for y in range(0, H3, 6) for x in range(0, W3, 6) if pxl[x, y] == (255, 253, 247)) / ((W3 // 6) * (H3 // 6))
        shifts = sorted(round(a["y"] - b["y"], 1) for a in bA for b in bB if abs(a["h"] - b["h"]) < 2 and 80 <= a["y"] - b["y"] <= 120)
        R["release_drag"] = {"bands_before": bA, "bands_after": bB, "shifts": shifts, "board_frac": round(board_frac, 3)}
        chk("release_harbour_button_drag_scrolls_no_press", bool(shifts) and abs(max(set(shifts), key=shifts.count) - D) <= 3 and board_frac < 0.05,
            shifts=shifts[:6], board_frac=round(board_frac, 3))
        R["errors"] = [l for l in c.logs if "ERROR" in l or "EXCEPTION" in l][:20]
        chk("release_no_console_errors", not R["errors"], errors=R["errors"])
    except Exception:
        import traceback; R["exception"] = traceback.format_exc(); print(R["exception"])
    finally:
        c.close()
    save(f"release_{tag}.json", R)
    print(json.dumps({k: v["result"] for k, v in C.items()}, indent=1))


# ------------------------------------------------------------------ run 9: harbour touch scroll (TouchScroll)
def run_harbour(tag, port):
    w, h = map(int, tag.split("x")); dpr = DPR[tag]
    R = {"viewport": tag, "checks": {}}; C = R["checks"]
    def chk(name, ok, **ev): C[name] = {"result": "PASS" if ok else "FAIL", **ev}; return ok
    S = lambda nme: os.path.join(SHOTS, f"{tag}_h_{nme}.png")
    c = CDP(port)
    def sy():
        r = c.rect("SettingsButton"); return r["y"] if r else None
    def snap():
        d = c.dump(); return {"screen": d["screen"], "profile": d["profile"], "overlay": c.layout()["overlay"]}
    def harbour_bands():
        hs = c.rect("HarbourScroll"); img = c.shot("/tmp/_qa9_%s.png" % tag); mm = c.metrics()
        bb = bands(img, dpr, hs["x"] + 4, hs["x"] + hs["w"] - 14, hs["y"], min(hs["y"] + hs["h"], h), "menu")
        return hs, [b_ for b_ in bb if on_screen(b_, mm) and b_["y"] >= hs["y"] - 0.5]
    def to_top():
        hs, bb = harbour_bands()
        b_ = bb[0]
        c.drag(b_["x"] + b_["w"] * 0.3, b_["y"] + b_["h"] / 2, 0, min(h - 2 - (b_["y"] + b_["h"] / 2), 400), steps=20)
        c.pump(0.4)
    try:
        c.emulate(w, h, dpr); R["boot_s"] = c.boot(DEBUG_URL)
        c.tap_node("PlayButton"); c.pump(0.5)
        hs, bb = harbour_bands(); R["bands_top"] = bb
        lay = c.layout(); R["layout"] = lay
        img = c.shot(S("00_harbour_top"))
        # ---------- (a) drag that starts on a button scrolls by ~the drag distance and presses nothing
        res_a = []
        for i, b_ in enumerate(bb[:4]):
            to_top(); hs, bbn = harbour_bands(); b_ = bbn[i]
            cy = b_["y"] + b_["h"] / 2
            D = min(120, cy - hs["y"] - 2, cy - 2)
            s0 = snap(); y0 = sy()
            c.drag(b_["x"] + b_["w"] * 0.3, cy, 0, -D, steps=15)
            y1 = sy(); s1 = snap()
            if i == 0: c.shot(S("01_after_button_drag_up"))
            moved = y0 - y1
            res_a.append({"button_band": i, "drag_css": round(D, 1), "settings_moved_css": round(moved, 1),
                          "screen": [s0["screen"], s1["screen"]], "profile_same": s0["profile"] == s1["profile"]})
        chk("a_button_drag_scrolls_no_press", all(abs(r_["settings_moved_css"] - r_["drag_css"]) <= 3 and r_["screen"] == ["harbour", "harbour"]
                                                  and r_["profile_same"] for r_ in res_a), drags=res_a)
        # drag down (back) on a button, and up-then-back-to-start (net 0) on a button: no press either
        hs, bbn = harbour_bands(); b_ = bbn[1]; s0 = snap(); y0 = sy()
        c.drag(b_["x"] + b_["w"] * 0.3, b_["y"] + b_["h"] / 2, 0, 60, steps=10); y1 = sy(); s1 = snap()
        chk("a_button_drag_down_scrolls_no_press", s1["screen"] == "harbour" and s1["profile"] == s0["profile"] and abs((y1 - y0) - 60) <= 3,
            moved=round(y1 - y0, 1))
        to_top(); hs, bbn = harbour_bands(); b_ = bbn[1]; s0 = snap(); y0 = sy(); cx_, cy_ = b_["x"] + b_["w"] * 0.3, b_["y"] + b_["h"] / 2
        c.send("Input.dispatchTouchEvent", {"type": "touchStart", "touchPoints": [{"x": cx_, "y": cy_, "id": 1}]}); c.pump(0.03)
        for k in list(range(1, 11)) + list(range(9, -1, -1)):
            c.send("Input.dispatchTouchEvent", {"type": "touchMove", "touchPoints": [{"x": cx_, "y": cy_ - 5 * k, "id": 1}]}); c.pump(0.016)
        c.send("Input.dispatchTouchEvent", {"type": "touchEnd", "touchPoints": []}); c.pump(0.5)
        s1 = snap(); y1 = sy()
        chk("a_drag_out_and_back_no_press", s1["screen"] == "harbour" and s1["profile"] == s0["profile"] and abs(y1 - y0) <= 1,
            screen=s1["screen"], settings_y=[round(y0, 1), round(y1, 1)])
        # ---------- (b) tap with jitter on a tier button (T2..T4): pressed => classic_tier changes; >threshold => scroll, no press
        jit = []
        for j in (3, 6, 9, 10, 10.5, 11, 12, 15, 20, 30):
            to_top(); hs, bbn = harbour_bands(); trow = bbn[2]
            tier0 = c.dump()["profile"]["classic_tier"]; k = 2 if tier0 != 2 else 3
            tx = trow["x"] + trow["w"] * (2 * k - 1) / 8; ty = trow["y"] + trow["h"] / 2
            s0 = snap(); y0 = sy()
            c.drag(tx, ty, 0, -j, steps=4, dt=0.02, settle=0.6)
            s1 = snap(); y1 = sy()
            pressed = s1["profile"]["classic_tier"] == k
            jit.append({"jitter_css": j, "pressed": pressed, "scrolled_css": round(y0 - y1, 1) if not pressed else 0.0, "screen": s1["screen"],
                        "other_state_same": {kk: v for kk, v in s1["profile"].items() if kk != "classic_tier"} == {kk: v for kk, v in s0["profile"].items() if kk != "classic_tier"}})
        R["jitter"] = jit
        pressed_max = max([r_["jitter_css"] for r_ in jit if r_["pressed"]], default=None)
        scroll_min = min([r_["jitter_css"] for r_ in jit if not r_["pressed"]], default=None)
        R["measured_threshold_css"] = [pressed_max, scroll_min]
        chk("b_jitter_3_6_9_press", all(r_["pressed"] for r_ in jit if r_["jitter_css"] in (3, 6, 9)),
            results={r_["jitter_css"]: r_["pressed"] for r_ in jit if r_["jitter_css"] in (3, 6, 9)})
        chk("b_jitter_12plus_scroll_not_press", all((not r_["pressed"]) and abs(r_["scrolled_css"] - r_["jitter_css"]) <= 2 and r_["screen"] == "harbour"
                                                    and r_["other_state_same"] for r_ in jit if r_["jitter_css"] >= 12),
            results={r_["jitter_css"]: [r_["pressed"], r_["scrolled_css"]] for r_ in jit if r_["jitter_css"] >= 12})
        # horizontal jitter (threshold is vertical-only): 9 px sideways still presses
        to_top(); hs, bbn = harbour_bands(); trow = bbn[2]; tier0 = c.dump()["profile"]["classic_tier"]; k = 4 if tier0 != 4 else 1
        tx = trow["x"] + trow["w"] * (2 * k - 1) / 8; ty = trow["y"] + trow["h"] / 2
        c.drag(tx, ty, 9, 0, steps=4, dt=0.02, settle=0.6)
        chk("b_horizontal_jitter_9_press", c.dump()["profile"]["classic_tier"] == k)
        # ---------- (c) fling and long drag reach the bottom; Settings / Tasks / Buy tappable
        to_top(); hs, bbn = harbour_bands()
        y0 = sy(); b_ = bbn[-1]
        span = min(b_["y"] + b_["h"] / 2 - hs["y"] - 2, hs["h"] * 0.8)
        c.drag(b_["x"] + b_["w"] * 0.3, b_["y"] + b_["h"] / 2, 0, -span, steps=4, dt=0.008, settle=0.05)
        y_rel = sy(); c.pump(1.0); y_later = sy()
        R["fling"] = {"span_css": round(span, 1), "settings_y": [round(y0, 1), round(y_rel, 1), round(y_later, 1)], "momentum_css": round(y_rel - y_later, 1)}
        flings = 1; mm = c.metrics()
        while not on_screen(c.rect("SettingsButton"), mm) and flings < 10:
            hs, bbn = harbour_bands(); b_ = bbn[-1] if bbn else None
            if not b_: break
            span = min(b_["y"] + b_["h"] / 2 - hs["y"] - 2, hs["h"] * 0.8)
            c.drag(b_["x"] + b_["w"] * 0.3, b_["y"] + b_["h"] / 2, 0, -span, steps=4, dt=0.008, settle=0.5); flings += 1
        R["flings_to_bottom"] = flings
        c.shot(S("02_bottom_after_flings"))
        chk("c_fling_reaches_settings", on_screen(c.rect("SettingsButton"), mm), flings=flings, momentum_css=R["fling"]["momentum_css"])
        # at the bottom: one more drag doesn't move further (clamped)
        hs, bbn = harbour_bands(); yb = sy()
        b_ = bbn[0]; c.drag(b_["x"] + b_["w"] * 0.3, b_["y"] + b_["h"] / 2, 0, -80, steps=10); ya = sy()
        R["clamp_at_bottom"] = [round(yb, 1), round(ya, 1)]
        # tap Settings at the bottom
        c.tap_node("SettingsButton"); st = c.dump()["screen"]
        chk("c_settings_tappable_at_bottom", st == "settings", screen=st)
        c.tap_node("SettingsBack"); c.pump(0.4)
        # long slow drag: earn 3 stars first (L1 solved through the normal input path) so "Buy (3 stars)" is enabled
        c.js("SD_DEBUG.startLevel(1)"); c.pump(0.8); c.js("SD_DEBUG.solve()"); c.pump(1.5)
        c.js("SD_DEBUG.show('harbour')"); c.pump(0.8)
        p0 = c.dump()["profile"]; R["stars_after_L1"] = p0.get("stars")
        drags = 0
        while not on_screen(c.rect("SettingsButton"), mm) and drags < 10:
            hs, bbn = harbour_bands(); b_ = bbn[-1]
            c.drag(b_["x"] + b_["w"] * 0.3, b_["y"] + b_["h"] / 2, 0, -(b_["y"] + b_["h"] / 2 - hs["y"] - 2), steps=40, dt=0.02); drags += 1
        R["long_drags_to_bottom"] = drags
        img = c.shot(S("03_bottom_after_long_drags"))
        chk("c_long_drag_reaches_settings", on_screen(c.rect("SettingsButton"), mm), drags=drags)
        # Buy: right-hand small button in the Tasks rows; find the first enabled (slate) one right of centre
        hs = c.rect("HarbourScroll"); pxl = img.load()
        xr = hs["x"] + hs["w"] * 0.82
        buy = None; run_ = 0
        lx = hs["x"] + hs["w"] * 0.3   # left side of a Tasks row is the task label (light background)
        for yy in range(int(hs["y"]) + 2, int(min(h, hs["y"] + hs["h"])) - 2):
            cpx = pxl[int(xr * dpr), int(yy * dpr)]; l = pxl[int(lx * dpr), int(yy * dpr)]
            slate = 60 < 0.299 * cpx[0] + 0.587 * cpx[1] + 0.114 * cpx[2] < 140 and max(cpx) - min(cpx) < 40
            light = 0.299 * l[0] + 0.587 * l[1] + 0.114 * l[2] > 170
            if slate and light:
                if run_ == 0: start_ = yy
                run_ = yy - start_ + 1; gap_ = 0
            elif run_:
                gap_ += 1      # button text crosses the sample column: tolerate short gaps
                if gap_ > 4: run_ = 0
            if run_ >= 20: buy = start_ + 10; break
        R["buy_tap_y"] = buy
        s0 = c.dump()["profile"]
        if buy: c.tap(xr, buy, after=0.8)
        s1 = c.dump()["profile"]; c.shot(S("04_after_buy_tap"))
        R["buy"] = {"stars": [s0.get("stars"), s1.get("stars")], "tasks_before": {k_: v for k_, v in s0.items() if "task" in k_}, "tasks_after": {k_: v for k_, v in s1.items() if "task" in k_}}
        chk("c_buy_tappable", buy is not None and s1 != s0 and (s1.get("stars", 0) < s0.get("stars", 0) or R["buy"]["tasks_before"] != R["buy"]["tasks_after"]),
            stars=R["buy"]["stars"])
        # ---------- (d) drags on grid / digit pad / hint panel
        c.js("SD_DEBUG.startLevel(11)"); c.pump(1.0)
        sd = c.dump()["stepDump"]; n = sd["size"]; geo = grid_geom(c, n); sol = sd["solution"]
        emp = empties(sd)
        g0 = c.dump()["stepDump"]
        (ra, ca), (rb, cb) = emp[0], emp[-1]
        xa, ya_ = cell_center(geo, ra, ca); xb, yb_ = cell_center(geo, rb, cb)
        c.drag(xa, ya_, xb - xa, yb_ - ya_, steps=20)          # drag across the grid
        c.drag(xb, yb_, 0, -geo["cp"] * 4, steps=12)            # vertical swipe on the grid
        g1 = c.dump()["stepDump"]
        chk("d_grid_drag_no_action", g1["grid"] == g0["grid"] and g1["notes"] == g0["notes"] and len(g1["undo"]) == len(g0["undo"]) and g1["mistakes"] == g0["mistakes"],
            undo=[len(g0["undo"]), len(g1["undo"])])
        # pad: select an empty cell, drag from Digit1 to Digit9 (off the start button) -> nothing placed
        (rc, cc) = emp[1]; c.tap(*cell_center(geo, rc, cc))
        d1 = c.rect("Digit1"); d9 = c.rect("Digit9")
        p0_ = c.dump()["stepDump"]
        c.drag(d1["x"] + d1["w"] / 2, d1["y"] + d1["h"] / 2, (d9["x"] - d1["x"]), (d9["y"] - d1["y"]), steps=15)
        dp = c.rect("DigitPad") or d1
        gx, gy = cell_center(geo, 4, 4)   # pad -> into the grid (left in landscape, up in portrait)
        c.drag(d1["x"] + d1["w"] / 2, d1["y"] + d1["h"] / 2, gx - (d1["x"] + d1["w"] / 2), gy - (d1["y"] + d1["h"] / 2), steps=15)
        p1_ = c.dump()["stepDump"]
        # then a plain tap on another empty cell must not place a locked digit
        (re_, ce_) = emp[2]; c.tap(*cell_center(geo, re_, ce_)); p2_ = c.dump()["stepDump"]
        chk("d_pad_drag_no_action", p1_["grid"] == p0_["grid"] and len(p1_["undo"]) == len(p0_["undo"]) and p1_["mistakes"] == p0_["mistakes"]
            and p2_["grid"] == p0_["grid"], undo=[len(p0_["undo"]), len(p1_["undo"]), len(p2_["undo"])])
        # pad tap with 6 px jitter still places exactly one (correct) digit
        c.tap(*cell_center(geo, rc, cc)); q0 = c.dump()["stepDump"]; dd = c.rect(f"Digit{sol[rc][cc]}")
        c.drag(dd["x"] + dd["w"] / 2, dd["y"] + dd["h"] / 2, 0, -6, steps=4, dt=0.02, settle=0.6); q1 = c.dump()["stepDump"]
        chk("d_pad_jitter_tap_places_one", changed_cells(q0["grid"], q1["grid"]) == [(rc, cc, 0, sol[rc][cc])] and len(q1["undo"]) == len(q0["undo"]) + 1,
            changed=changed_cells(q0["grid"], q1["grid"]))
        # hint panel: drag on Teach (off the button) -> no teach; jitter tap 6 px -> teach; Back still works
        c.tap(*cell_center(geo, *emp[3])); c.tap_node("HintButton"); img = c.shot(S("05_hint_panel")); pb, hb = hint_buttons(c, img, dpr)
        t = hb[-3]; tok0 = c.dump()["profile"]["tokens"]
        c.drag(t["x"] + t["w"] / 2, t["y"] + t["h"] / 2, 0, -(t["h"] + 20), steps=10)
        st1 = c.dump(); ov1 = c.layout()["overlay"]
        img = c.shot(S("06_hint_panel_after_drag")); pb2, hb2 = hint_buttons(c, img, dpr); t2 = hb2[-3]
        c.drag(t2["x"] + t2["w"] / 2, t2["y"] + t2["h"] / 2, 0, -6, steps=4, dt=0.02, settle=0.8)
        st2 = c.dump(); ov2 = c.layout()["overlay"]
        chk("d_hint_panel_unaffected", st1["profile"]["tokens"] == tok0 and ov1 == "HintPanel" and pb2 == pb and len(hb2) == len(hb)
            and st2["profile"]["tokens"] == tok0 - 1 and ov2 == "" and st2["stepDump"]["game_step"] is not None,
            tokens=[tok0, st1["profile"]["tokens"], st2["profile"]["tokens"]], overlay=[ov1, ov2])
        m_end = c.metrics(); R["metrics_end"] = m_end
        chk("no_zoom_no_scroll_during_drags", metrics_ok(m_end), metrics=m_end)
        R["errors"] = [l for l in c.logs if "ERROR" in l or "EXCEPTION" in l][:20]
        chk("no_console_errors", not R["errors"], errors=R["errors"])
    except Exception:
        import traceback; R["exception"] = traceback.format_exc(); print(R["exception"])
        try: c.shot(S("99_exception"))
        except Exception: pass
    finally:
        c.close()
    save(f"harbour_{tag}.json", R)
    print(json.dumps({k: v["result"] for k, v in C.items()}, indent=1))
    return R


if __name__ == "__main__":
    mode = sys.argv[1]
    port = int(sys.argv[3]) if len(sys.argv) > 3 else 9330
    if mode == "mobile": run_mobile(sys.argv[2], port)
    elif mode == "rotate":
        if len(sys.argv) > 3:   # rotate WxH port
            pw_, ph_ = map(int, sys.argv[2].split("x")); run_rotate(int(sys.argv[3]), pw_, ph_, DPR.get(sys.argv[2], 3))
        else: run_rotate(int(sys.argv[2]) if len(sys.argv) > 2 else 9340)
    elif mode == "desktop": run_desktop(int(sys.argv[2]) if len(sys.argv) > 2 else 9350)
    elif mode == "harbour": run_harbour(sys.argv[2], port)
    elif mode == "release": run_release(int(sys.argv[2]) if len(sys.argv) > 2 else 9360)
