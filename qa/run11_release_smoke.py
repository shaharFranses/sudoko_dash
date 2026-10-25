#!/usr/bin/env python3
"""Run 11 step 9: gated release a795a1a boots, plays the PKD intro, reaches the title, and Play opens the Harbour (no debug hooks).
Usage: /tmp/qav/bin/python qa/run11_release_smoke.py WxH PORT"""
import os, sys, json, time
TAG, PORT = sys.argv[1], int(sys.argv[2])
URL = "http://127.0.0.1:8071/a795a1a/index.html"
sys.argv = ["x", "natural", TAG, str(PORT), URL, "release"]
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
src = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "run11_intro.py")).read().split('R = {"mode"')[0]
exec(src)
import ocr_locate as O
R = {"viewport": TAG, "url": URL, "checks": {}}; CK = R["checks"]
def chk(n, ok, **e): CK[n] = {"result": "PASS" if ok else "FAIL", **e}; print(n, CK[n]["result"], json.dumps(e, default=str)[:400])
c = None
try:
    c = C2(PORT, None if MOBILE else (W, H))
    if MOBILE: c.emulate(W, H, 3); dpr = 3
    else:
        c.send("Page.navigate", {"url": "about:blank"}); c.pump(0.5)
        wid = c.send("Browser.getWindowForTarget")["windowId"]
        for _ in range(4):
            iw, ih = c.js("[innerWidth, innerHeight]"); b = c.send("Browser.getWindowBounds", {"windowId": wid})["bounds"]
            if iw == W and ih == H: break
            c.send("Browser.setWindowBounds", {"windowId": wid, "bounds": {"width": b["width"] + W - iw, "height": b["height"] + H - ih}}); c.pump(0.3)
        dpr = 1
    c.send("Emulation.setCPUThrottlingRate", {"rate": 1})
    c.send("Page.addScriptToEvaluateOnNewDocument", {"source": INSTR})
    c.logs.clear(); t0 = time.time(); c.send("Page.navigate", {"url": URL})
    while time.time() - t0 < 150:
        c.pump(0.2)
        if any("[SD] intro finished" in l for l in c.logs) and any("[SD] title ready" in l for l in c.logs): break
    c.pump(2.0)
    E = c.js("JSON.parse(JSON.stringify(window.__qaEv||[]))")
    t_end = next((e["t"] for e in E if "[SD] intro finished" in e["what"]), None); t_title = next((e["t"] for e in E if "[SD] title ready" in e["what"]), None)
    R["t_ms"] = {"title_ready": t_title, "intro_finished": t_end}
    R["no_debug_hooks"] = c.js("typeof window.SD_DEBUG === 'undefined' && typeof window.__adsLog === 'undefined'")
    img = c.shot(os.path.join(OUT, f"release_{TAG}_title.png"))
    ls = O.lines(img, dpr, (0, 0, W, H)); txt = " | ".join(l["text"] for l in ls)
    errs = [e for e in E if e["kind"] in ("console.error", "window.error", "unhandledrejection")]
    early = [e for e in E if (e["kind"].startswith("SD_CG.")) and (t_end is None or e["t"] < t_end - 1)]
    chk("release_intro_then_title", t_end is not None and t_title is not None and "Play" in txt, t_ms=R["t_ms"], ocr=txt[:200])
    chk("release_no_debug_hooks", bool(R["no_debug_hooks"]))
    chk("release_no_sdk_calls_before_intro_end", not early, early=early)
    pl = O.find(ls, r"^Play$") or O.find(ls, r"Play")
    if pl:
        x, y = pl["x"] + pl["w"] / 2, pl["y"] + pl["h"] / 2
        if MOBILE: c.tap(x, y, after=1.5)
        else: c.click(x, y, after=1.5)
    img2 = c.shot(os.path.join(OUT, f"release_{TAG}_harbour.png")); t2 = " | ".join(l["text"] for l in O.lines(img2, dpr, (0, 0, W, H)))
    chk("release_play_opens_harbour", "Harbour" in t2, ocr=t2[:200])
    E = c.js("JSON.parse(JSON.stringify(window.__qaEv||[]))"); errs = [e for e in E if e["kind"] in ("console.error", "window.error", "unhandledrejection")]
    chk("release_no_console_errors", not errs, errors=errs[:5])
except Exception:
    import traceback; R["exception"] = traceback.format_exc(); print(R["exception"])
finally:
    if c: c.close()
    json.dump(R, open(os.path.join(OUT, f"release_smoke_{TAG}.json"), "w"), indent=1, default=str)
