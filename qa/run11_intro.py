#!/usr/bin/env python3
"""QA run 11 (a795a1a): PKD studio intro checks. Raw CDP headless Chrome, CPU throttling explicitly off (rate 1).
Usage: QA_BUILD=a795a1a QA_RUN=run11_a795a1a QA_DEBUG_PORT=8070 /tmp/qav/bin/python qa/run11_intro.py MODE WxH PORT [URL]
MODE: natural | skip_touch | skip_mouse | skip_key | sdk  (390x844 = mobile emulation DPR 3 touch; others = desktop window DPR 1 mouse)
In-page instrumentation (added before any page script): performance.now() timestamps for every console line, every
window.SD_CG call (loadingStop / gameplay / request), every CrazyGames SDK call (mock SDK served for sdk.crazygames.com in
mode sdk, via ?cgsdk=1), and the first non-silent audio sample (AnalyserNode tapped on every connect() to a destination)."""
import os, sys, json, time, base64, io, subprocess, tempfile, shutil, urllib.request
os.environ.setdefault("QA_BUILD", "a795a1a"); os.environ.setdefault("QA_RUN", "run11_a795a1a"); os.environ.setdefault("QA_DEBUG_PORT", "8070")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mobile_qa as M
import websocket
from PIL import Image

MODE, TAG, PORT = sys.argv[1], sys.argv[2], int(sys.argv[3])
URL = sys.argv[4] if len(sys.argv) > 4 else M.DEBUG_URL
SRC = sys.argv[5] if len(sys.argv) > 5 else "debug"
W, H = map(int, TAG.split("x")); MOBILE = TAG == "390x844"
OUT = os.path.join(M.OUT, "intro"); os.makedirs(OUT, exist_ok=True)
NAME = f"{SRC}_{MODE}_{TAG}" + ("_early" if os.environ.get("SKIP_AT") == "hooks" else "")
FR = os.path.join(OUT, NAME + "_frames"); shutil.rmtree(FR, ignore_errors=True); os.makedirs(FR)
NAVY = (0x1E, 0x1B, 0x3A)

INSTR = r"""
(function(){
  var T = function(){ return Math.round(performance.now()*10)/10; };
  var E = window.__qaEv = [];
  function rec(kind, what){ E.push({t: T(), kind: kind, what: String(what).slice(0, 300)}); }
  window.__qaRec = rec;
  ['log','info','warn','error','debug'].forEach(function(k){
    var o = console[k].bind(console);
    console[k] = function(){ try { rec('console.'+k, Array.prototype.map.call(arguments, String).join(' ')); } catch(e){}; return o.apply(null, arguments); };
  });
  ['touchstart','touchend','pointerdown','pointerup','mousedown','mouseup','keydown','keyup'].forEach(function(k){
    document.addEventListener(k, function(e){ rec('dom.'+k, (e.target && (e.target.id || e.target.tagName)) + ' trusted=' + e.isTrusted); }, true); });
  window.addEventListener('error', function(e){ rec('window.error', e.message); }, true);
  window.addEventListener('unhandledrejection', function(e){ rec('unhandledrejection', e.reason); });
  // SD_CG glue wrapper (catches every call the game makes into the page glue)
  var real;
  Object.defineProperty(window, 'SD_CG', { configurable: true, get: function(){ return real; }, set: function(v){
    real = v;
    ['loadingStop','gameplay','request'].forEach(function(k){
      var f = v[k]; v[k] = function(){ rec('SD_CG.'+k, JSON.stringify(Array.prototype.slice.call(arguments))); return f.apply(v, arguments); };
    });
  }});
  // audio: tap an analyser on every connection to a destination node
  var an = window.__qaAn = [];
  var oc = AudioNode.prototype.connect;
  AudioNode.prototype.connect = function(dest){
    try { if (dest instanceof AudioDestinationNode) { var a = this.context.createAnalyser(); a.fftSize = 2048; oc.call(this, a); an.push(a); rec('audio.connect', this.constructor.name); } } catch(e){}
    return oc.apply(this, arguments);
  };
  var buf = new Float32Array(2048), firstSound = null;
  setInterval(function(){
    for (var i = 0; i < an.length; i++) { an[i].getFloatTimeDomainData(buf); var m = 0; for (var j = 0; j < buf.length; j++) { var v = Math.abs(buf[j]); if (v > m) m = v; }
      if (m > 1e-4) { rec('audio.sound', m.toFixed(5)); if (firstSound === null) firstSound = T(); } }
  }, 20);
  var ctxState = '';
  setInterval(function(){ try { var s = (window.__sdAudioCtxs||[]).map(function(c){return c.state;}).join(','); if (s !== ctxState) { ctxState = s; rec('audio.ctx', s); } } catch(e){} }, 50);
})();
"""
MOCK_SDK = r"""
(function(){
  function rec(w){ if (window.__qaRec) window.__qaRec('CGSDK', w); }
  window.CrazyGames = { SDK: {
    environment: 'crazygames',
    init: function(){ rec('init'); return Promise.resolve(); },
    game: { loadingStart: function(){ rec('loadingStart'); }, loadingStop: function(){ rec('loadingStop'); },
            gameplayStart: function(){ rec('gameplayStart'); }, gameplayStop: function(){ rec('gameplayStop'); },
            happytime: function(){ rec('happytime'); } },
    ad: { requestAd: function(t, cb){ rec('requestAd:' + t); setTimeout(function(){ cb && cb.adFinished && cb.adFinished(); }, 200); },
          hasAdblock: function(){ rec('hasAdblock'); return Promise.resolve(false); } },
    data: { getItem: function(k){ return localStorage.getItem(k); }, setItem: function(k, v){ localStorage.setItem(k, v); },
            removeItem: function(k){ localStorage.removeItem(k); } }
  } };
})();
"""

class C2(M.CDP):
    def __init__(self, port, window_size=None):
        self.ud = tempfile.mkdtemp(prefix="sdqa_run11_%d_" % os.getpid())
        args = [M.CHROME, "--headless=new", f"--remote-debugging-port={port}", f"--user-data-dir={self.ud}",
                "--no-first-run", "--no-default-browser-check", "--use-angle=swiftshader", "--enable-unsafe-swiftshader",
                "--ignore-gpu-blocklist", "--hide-scrollbars", "--autoplay-policy=no-user-gesture-required", "about:blank"]
        if window_size: args.insert(1, f"--window-size={window_size[0]},{window_size[1]}")
        self.proc = subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        for _ in range(150):
            try:
                pages = [t for t in json.load(urllib.request.urlopen(f"http://127.0.0.1:{port}/json/list")) if t["type"] == "page"]
                if pages: break
            except Exception: pass
            time.sleep(0.2)
        self.ws = websocket.create_connection(pages[0]["webSocketDebuggerUrl"], suppress_origin=True, timeout=120)
        self.n = 0; self.logs = []; self.frames = []; self.fetch = False
        self.send("Runtime.enable"); self.send("Page.enable")
    def _event(self, m):
        meth = m.get("method")
        if meth == "Page.screencastFrame":
            p = m["params"]; ts = p["metadata"].get("timestamp", time.time())
            self.frames.append((ts, p["data"]))
            self.ws.send(json.dumps({"id": 10**7 + len(self.frames), "method": "Page.screencastFrameAck", "params": {"sessionId": p["sessionId"]}}))
            return
        if meth == "Fetch.requestPaused":
            p = m["params"]
            body = base64.b64encode(MOCK_SDK.encode()).decode()
            self.ws.send(json.dumps({"id": 2 * 10**7 + len(self.logs), "method": "Fetch.fulfillRequest", "params": {
                "requestId": p["requestId"], "responseCode": 200, "responseHeaders": [{"name": "Content-Type", "value": "application/javascript"}], "body": body}}))
            self.logs.append("QA mock SDK served for " + p["request"]["url"]); return
        super()._event(m)

R = {"mode": MODE, "viewport": TAG, "src": SRC, "url": URL, "checks": {}}; CK = R["checks"]
def chk(n, ok, **ev):
    CK[n] = {"result": "PASS" if ok else "FAIL", **ev}; print(n, CK[n]["result"], json.dumps(ev, default=str)[:600]); return ok
def ev(c): return c.js("JSON.parse(JSON.stringify(window.__qaEv || []))") or []
def t_of(evs, sub):
    for e in evs:
        if sub in e["what"]: return e["t"]
    return None
def px(img, x, y): return img.getpixel((int(x), int(y)))
def near(a, b, tol=3): return all(abs(a[i] - b[i]) <= tol for i in range(3))

c = None
try:
    R["loadavg"] = os.getloadavg()
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
    R["cpu_throttling_rate"] = 1
    c.send("Page.addScriptToEvaluateOnNewDocument", {"source": INSTR})
    if MODE == "sdk":
        c.send("Fetch.enable", {"patterns": [{"urlPattern": "*sdk.crazygames.com*"}]})
        URL = URL + ("&" if "?" in URL else "?") + "cgsdk=1"; R["url"] = URL
    c.send("Page.startScreencast", {"format": "png", "everyNthFrame": 1})
    t_nav = time.time(); c.logs.clear()
    c.send("Page.navigate", {"url": URL})
    skip = None; t_dead = time.time() + 150
    while time.time() < t_dead:
        c.pump(0.05)
        title_ready = any("[SD] title ready" in l for l in c.logs); fin = any("[SD] intro finished" in l for l in c.logs)
        trig = any("QA hooks enabled" in l for l in c.logs) if os.environ.get("SKIP_AT") == "hooks" else title_ready
        if MODE.startswith("skip") and trig and skip is None:
            if fin: R["note"] = "intro already finished before title ready; cannot skip"; break
            r = c.rect("PlayButton") if os.environ.get("SKIP_AT") != "hooks" else None; R["play_rect"] = r
            x, y = (r["x"] + r["w"] / 2, r["y"] + r["h"] / 2) if r else (W / 2, H / 2)
            t_in = c.js("performance.now()")
            if MODE == "skip_touch":
                pt = {"x": x, "y": y, "radiusX": 2, "radiusY": 2, "force": 1, "id": 1}
                for _k in range(int(os.environ.get("TAPS", "1"))):
                    if _k: c.pump(0.3)
                    c.send("Input.dispatchTouchEvent", {"type": "touchStart", "touchPoints": [pt]}); c.pump(0.06)
                    c.send("Input.dispatchTouchEvent", {"type": "touchEnd", "touchPoints": []})
            elif MODE == "skip_mouse":
                c.send("Input.dispatchMouseEvent", {"type": "mouseMoved", "x": x, "y": y})
                c.send("Input.dispatchMouseEvent", {"type": "mousePressed", "x": x, "y": y, "button": "left", "clickCount": 1}); c.pump(0.06)
                c.send("Input.dispatchMouseEvent", {"type": "mouseReleased", "x": x, "y": y, "button": "left", "clickCount": 1})
            elif MODE == "skip_key":   # Enter = ui_accept: would press a focused Play if the key leaked through
                for typ in ("keyDown", "keyUp"):
                    c.send("Input.dispatchKeyEvent", {"type": typ, "key": "Enter", "code": "Enter", "windowsVirtualKeyCode": 13, "nativeVirtualKeyCode": 13,
                                                      **({"text": "\r"} if typ == "keyDown" else {})}); c.pump(0.06)
            skip = {"input": MODE, "at_css": [round(x, 1), round(y, 1)], "t_input_ms": t_in, "t_title_ready_ms": t_of(ev(c), "[SD] title ready"), "t_hooks_ms": t_of(ev(c), "QA hooks enabled")}
            try:
                nat = json.load(open(os.path.join(OUT, f"{SRC}_natural_{TAG}.json")))["state_after"]
            except Exception: nat = {}
            R["state_before_skip"] = {"screen": "title", "profile": nat.get("profile"), "note": "fresh-profile state from the natural run at this size (same build, fresh Chrome profile)"}
        if fin and title_ready:
            c.pump(2.0); break
    R["boot_wall_s"] = round(time.time() - t_nav, 1)
    c.send("Page.stopScreencast"); c.pump(0.3)
    E = ev(c); R["events"] = E
    t_end = t_of(E, "[SD] intro finished"); t_title = t_of(E, "[SD] title ready"); t_hooks = t_of(E, "QA hooks enabled") or t_of(E, "Godot Engine")
    t_godot = t_of(E, "Godot Engine")
    R["t_ms"] = {"godot_banner": t_godot, "first_autoload_log": t_hooks, "title_ready": t_title, "intro_finished": t_end}
    origin = c.js("performance.timeOrigin") / 1000.0
    # frames, timestamps relative to intro end
    rel = []
    for i, (ts, data) in enumerate(c.frames):
        tm = (ts - origin) * 1000.0; tr = None if t_end is None else round(tm - t_end, 1)
        fn = os.path.join(FR, f"f{i:03d}_{'%+07.0f' % tr if tr is not None else 'na'}ms.png")
        open(fn, "wb").write(base64.b64decode(data))
        img = Image.open(fn).convert("RGB"); w_, h_ = img.size
        corners = [px(img, 3, 3), px(img, w_ - 4, 3), px(img, 3, h_ - 4), px(img, w_ - 4, h_ - 4)]
        cen = px(img, w_ // 2, h_ // 2)
        navy_corners = all(near(k, NAVY, 3) for k in corners)
        rel.append({"i": i, "t_rel_intro_end_ms": tr, "file": os.path.relpath(fn, M.OUT), "corners": ["#%02X%02X%02X" % k for k in corners],
                    "centre": "#%02X%02X%02X" % cen, "navy_corners": navy_corners})
    R["frames"] = rel
    # stage classification
    pre = [f for f in rel if f["t_rel_intro_end_ms"] is not None and f["t_rel_intro_end_ms"] < -30]
    post = [f for f in rel if f["t_rel_intro_end_ms"] is not None and f["t_rel_intro_end_ms"] > 300]
    shots = {}
    img = c.shot(os.path.join(OUT, NAME + "_after.png")); shots["after"] = os.path.relpath(os.path.join(OUT, NAME + "_after.png"), M.OUT)
    st = c.dump(); R["state_after"] = {"screen": st.get("screen"), "profile": st.get("profile")}
    R["body_bg"] = c.js("getComputedStyle(document.body).backgroundColor")
    R["status_bg"] = c.js("(function(){var s=document.getElementById('status');return s?getComputedStyle(s).backgroundColor:null})()")
    R["ads_log"] = c.js("JSON.parse(JSON.stringify(window.__adsLog || []))")
    errs = [e for e in E if e["kind"] in ("console.error", "window.error", "unhandledrejection") or "SCRIPT ERROR" in e["what"] or e["what"].startswith("ERROR")]
    warns = [e for e in E if e["kind"] == "console.warn"]
    R["console_errors"] = errs; R["console_warnings"] = warns
    sdk_calls = [e for e in E if e["kind"].startswith("SD_CG.") or e["kind"] == "CGSDK"]
    R["sdk_calls"] = [{**e, "t_rel_intro_end_ms": None if t_end is None else round(e["t"] - t_end, 1)} for e in sdk_calls]
    sounds = [e for e in E if e["kind"] == "audio.sound"]
    R["audio"] = {"connects": [e for e in E if e["kind"] == "audio.connect"], "ctx": [e for e in E if e["kind"] == "audio.ctx"],
                  "first_sound_rel_ms": None if not sounds or t_end is None else round(sounds[0]["t"] - t_end, 1), "n_sound_samples": len(sounds)}
    # ---------- checks
    chk("intro_finished_logged", t_end is not None and t_title is not None, t_ms=R["t_ms"])
    chk("no_frame_data_warning", not any("pkd_intro" in e["what"] for e in warns), warns=[e["what"] for e in warns][:5])
    chk("title_after_intro", st.get("screen") == "title" and t_end is not None, screen=st.get("screen"))
    navy_pre = [f for f in pre if f["navy_corners"]]
    chk("loader_and_intro_bg_navy_1E1B3A", len(pre) > 0 and len(navy_pre) >= max(1, int(0.8 * len(pre))) and "30, 27, 58" in str(R["body_bg"]),
        pre_frames=len(pre), navy_pre=len(navy_pre), body_bg=R["body_bg"], status_bg=R["status_bg"],
        sample=[(f["t_rel_intro_end_ms"], f["corners"][0], f["centre"]) for f in pre[:: max(1, len(pre) // 8)]])
    early = [e for e in R["sdk_calls"] if e["t_rel_intro_end_ms"] is None or e["t_rel_intro_end_ms"] < 0]
    gp_early = [e for e in early if not (e["kind"] == "CGSDK" and e["what"] in ("init", "loadingStart", "hasAdblock"))]
    chk("no_sdk_gameplay_loading_calls_before_intro_end", len(gp_early) == 0, early_all=early, after=[e for e in R["sdk_calls"] if e not in early][:8])
    ads_early = [a for a in (R["ads_log"] or []) if isinstance(a, dict) and t_end is not None and a.get("t_ms", 1e12) < 0]
    chk("no_sound_before_intro_end", R["audio"]["first_sound_rel_ms"] is None or R["audio"]["first_sound_rel_ms"] >= 0, audio=R["audio"])
    chk("no_console_errors", len(errs) == 0, errors=errs[:5])
    if MODE == "natural":
        dur = None if (t_end is None or t_hooks is None) else round(t_end - t_hooks, 1)
        R["intro_ms_from_first_autoload_log"] = dur
        chk("intro_plays_full_length", dur is not None and dur >= 1800, intro_ms=dur, expected_ms=1930)
    if MODE.startswith("skip"):
        R["skip"] = skip
        dom = [e for e in E if skip is not None and e["kind"] in ("dom.touchstart", "dom.mousedown", "dom.keydown") and e["t"] >= skip["t_input_ms"] - 1]
        if skip is not None:
            skip["t_dom_event_ms"] = dom[0]["t"] if dom else None; skip["dom_event"] = dom[0]["kind"] if dom else None
            skip["cdp_dispatch_delay_ms"] = None if not dom else round(dom[0]["t"] - skip["t_input_ms"], 1)
        # latency from the input actually reaching the page (CDP dispatch can lag >1 s when the box is loaded)
        lat = None if (skip is None or t_end is None or not dom) else round(t_end - dom[0]["t"], 1)
        chk("skip_ends_intro", skip is not None and lat is not None and 0 <= lat <= 250, latency_ms_from_dom_event=lat, skip=skip,
            natural_would_end_ms_after_hooks=1930, ended_ms_after_hooks=None if t_hooks is None else round(t_end - t_hooks, 1))
        b4 = R.get("state_before_skip", {})
        same = b4.get("profile") == st.get("profile")
        chk("skip_does_not_press_play_or_title", st.get("screen") == "title" and same and not any(e["what"].startswith("[SD] grid") or "harbour" in e["what"].lower() for e in E if e["kind"] == "console.log" and t_end is not None and e["t"] >= t_end),
            screen_after=st.get("screen"), profile_unchanged=same)
        # input after skip works: the next tap/click on Play reaches the harbour
        r = c.rect("PlayButton"); x, y = r["x"] + r["w"] / 2, r["y"] + r["h"] / 2
        if MOBILE: c.tap(x, y, after=1.0)
        else: c.click(x, y, after=1.0)
        chk("title_input_works_after_skip", c.dump().get("screen") == "harbour", screen=c.dump().get("screen"))
    R["shots"] = shots
except Exception:
    import traceback; R["exception"] = traceback.format_exc(); print(R["exception"])
finally:
    if c: c.close()
    json.dump(R, open(os.path.join(OUT, NAME + ".json"), "w"), indent=1, default=str)
    print("wrote", NAME, {k: v["result"] for k, v in CK.items()})
