#!/usr/bin/env python3
"""Weekly upstream check (engines-6, Kamran 2026-11-25 19:08 «موتورها بدون میوز آپدیت شوند»).
Finds the newest upstream ffmpeg (same major line), ImageMagick 7, BusyBox 1.x, ONNX Runtime (Android AAR) and the
U-2-Netp model, compares them with what the latest published manifest.json was built from, and writes
GITHUB_OUTPUT: changed=true|false, ff/im/bb/ort/u2sha + a Persian/English summary. Build+test+publish only run
when changed=true (or the run was started with force=true)."""
import hashlib, json, os, re, sys, urllib.request

def get(url, binary=False, token=False):
    h = {"User-Agent": "kami-ag-engines"}
    if token and os.environ.get("GH_TOKEN"): h["Authorization"] = "Bearer " + os.environ["GH_TOKEN"]
    with urllib.request.urlopen(urllib.request.Request(url, headers=h), timeout=60) as r:
        b = r.read(); return b if binary else b.decode("utf-8", "replace")

def vkey(v): return [int(x) for x in re.findall(r"\d+", v)]

cur = {}
try:
    m = json.loads(get(f"https://github.com/{os.environ.get('GITHUB_REPOSITORY','kejbahs/kami-ag-engines')}/releases/latest/download/manifest.json"))
    for e in m.get("engines", []):
        cur[e["id"]] = e.get("upstream", "")
        if e.get("model_sha256"): cur[e["id"] + "_model"] = e["model_sha256"]
except Exception as ex:
    print("no published manifest yet:", ex)

ff_cur = cur.get("ffmpeg", "7.1.1"); major = (ff_cur.split(".") + ["7"])[0]
html = get("https://ffmpeg.org/releases/")
ffs = sorted({x for x in re.findall(r"ffmpeg-(\d+\.\d+(?:\.\d+)?)\.tar\.xz", html)}, key=vkey)
ff_same = [v for v in ffs if v.split(".")[0] == major]
ff = ff_same[-1] if ff_same else ff_cur
ff_newer_major = [v for v in ffs if vkey(v)[0] > int(major)]

im = json.loads(get("https://api.github.com/repos/ImageMagick/ImageMagick/releases/latest", token=True))["tag_name"]
if not re.match(r"^7\.\d+\.\d+-\d+$", im): im = cur.get("magick", "7.1.2-36")

bbl = get("https://busybox.net/downloads/")
bbs = sorted({x for x in re.findall(r"busybox-(1\.\d+\.\d+)\.tar\.bz2\"", bbl)}, key=vkey)
bb = bbs[-1] if bbs else cur.get("busybox", "1.36.1")

meta = get("https://repo1.maven.org/maven2/com/microsoft/onnxruntime/onnxruntime-android/maven-metadata.xml")
ort = (re.search(r"<release>([0-9.]+)</release>", meta) or re.search(r"<latest>([0-9.]+)</latest>", meta)).group(1)

u2 = hashlib.sha256(get("https://github.com/danielgatis/rembg/releases/download/v0.0.0/u2netp.onnx", binary=True)).hexdigest()

new = {"ffmpeg": ff, "magick": im, "busybox": bb, "bgremove": "ort" + ort, "bgremove_model": u2}
diff = [f"{k}: {cur.get(k) or '—'} → {v}" for k, v in new.items() if cur.get(k) != v]
force = os.environ.get("FORCE", "false") == "true"
changed = bool(diff) or force
summary = ("; ".join(diff) if diff else "no upstream change") + (" (force)" if force else "")
if ff_newer_major: summary += f"; note: ffmpeg {ff_newer_major[-1]} exists (new major — not built automatically)"
print(json.dumps(new, indent=1)); print("CHANGED:", changed, "|", summary)
with open(os.environ.get("GITHUB_OUTPUT", "/dev/stdout"), "a") as o:
    o.write(f"changed={'true' if changed else 'false'}\nff={ff}\nim={im}\nbb={bb}\nort={ort}\nu2sha={u2}\nsummary={summary}\n")
