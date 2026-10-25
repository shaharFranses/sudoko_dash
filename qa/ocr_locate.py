"""Colour-agnostic UI text locator for the art build (run 10+): tesseract TSV on two binarised masks
(dark ink on light, light ink on dark) -> text lines with boxes in CSS px."""
import subprocess, tempfile, os, re
from PIL import Image, ImageOps, ImageChops, ImageFilter

def _tsv(img, psm=11):
    with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as f: img.save(f.name)
    out = subprocess.run(["tesseract", f.name, "-", "--psm", str(psm), "tsv"], capture_output=True, text=True, env=dict(os.environ, OMP_THREAD_LIMIT="1")).stdout
    os.unlink(f.name); rows = []
    for ln in out.splitlines()[1:]:
        p = ln.split("\t")
        if len(p) == 12 and p[11].strip() and float(p[10]) > 30:
            rows.append(dict(block=int(p[2]), par=int(p[3]), line=int(p[4]), x=int(p[6]), y=int(p[7]), w=int(p[8]), h=int(p[9]), conf=float(p[10]), text=p[11]))
    return rows

def lines(img, dpr, region=None, down=None):
    """-> [{'text','x','y','w','h'}] in CSS px. down: optional downscale so text is ~30-60 px tall for tesseract."""
    x0, y0, x1, y1 = region or (0, 0, img.width / dpr, img.height / dpr)
    crop = img.crop((int(x0 * dpr), int(y0 * dpr), int(x1 * dpr), int(y1 * dpr)))
    s = (2.0 if dpr >= 2 else 3.0) / dpr   # tesseract input at 2x CSS px (3x at DPR 1)
    if s != 1.0: crop = crop.resize((int(crop.width * s), int(crop.height * s)), Image.LANCZOS)
    g = ImageOps.grayscale(crop)
    out = []
    # light text only counts inside dark fills (teal / terracotta buttons): dilate the dark mask and AND with light pixels
    # open at CSS scale (cheap): erase thin dark strokes (text), keep dark fills; then grow over the light text holes
    # saturated dark fills (teal / terracotta buttons) at CSS scale, closed so the light text holes are filled
    f = dpr * s; smallc = crop.convert("RGB").resize((max(1, int(crop.width / f)), max(1, int(crop.height / f))), Image.BILINEAR)
    hsv_s = smallc.convert("HSV").split()[1]; smallg = ImageOps.grayscale(smallc)
    fillm = ImageChops.multiply(hsv_s.point(lambda v: 255 if v > 90 else 0), smallg.point(lambda v: 255 if v < 160 else 0))
    region = fillm.filter(ImageFilter.MaxFilter(11)).filter(ImageFilter.MinFilter(11)).filter(ImageFilter.MinFilter(3)).resize(g.size, Image.NEAREST)
    light = ImageChops.multiply(g.point(lambda v: 255 if v > 200 else 0), region)
    # dark ink, minus teal (button borders boxed the text in and tesseract skipped it)
    r_, g_, b_ = crop.convert("RGB").split()
    teal = ImageChops.multiply(ImageChops.subtract(g_, r_).point(lambda v: 255 if v > 30 else 0), ImageChops.subtract(b_, r_).point(lambda v: 255 if v > 30 else 0))
    dark = ImageChops.subtract(g.point(lambda v: 255 if v < 120 else 0), teal)
    masks = (ImageOps.invert(dark), ImageOps.invert(light))
    for mask in masks:
        grp = {}
        for psm in (11, 6):
            for w_ in _tsv(mask, psm): grp.setdefault((psm, w_["block"], w_["par"], w_["line"]), []).append(w_)
        for ws in grp.values():
            ws.sort(key=lambda a: a["x"])
            # split a tesseract line where the gap between words is large (two buttons on one row)
            cur = [ws[0]]
            for a in ws[1:]:
                if a["x"] - (cur[-1]["x"] + cur[-1]["w"]) > 2.2 * max(a["h"], cur[-1]["h"]): out.append(cur); cur = [a]
                else: cur.append(a)
            out.append(cur)
    res = []
    for ws in out:
        xa = min(a["x"] for a in ws); ya = min(a["y"] for a in ws); xb = max(a["x"] + a["w"] for a in ws); yb = max(a["y"] + a["h"] for a in ws)
        k = dpr * s
        r = {"text": " ".join(a["text"] for a in ws), "x": x0 + xa / k, "y": y0 + ya / k, "w": (xb - xa) / k, "h": (yb - ya) / k}
        if not any(abs(r["x"] - q["x"]) < 3 and abs(r["y"] - q["y"]) < 3 and q["text"] == r["text"] for q in res): res.append(r)
    return sorted(res, key=lambda r: (round(r["y"] / 6), r["x"]))

def find(ls, pat, after_y=None):
    for l in ls:
        if re.search(pat, l["text"], re.I) and (after_y is None or l["y"] > after_y): return l
    return None

def ctr(r): return (r["x"] + r["w"] / 2, r["y"] + r["h"] / 2)
