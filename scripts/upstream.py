#!/usr/bin/env python3
"""Weekly upstream check (engines-6, Kamran 2026-11-25 19:08 «موتورها بدون میوز آپدیت شوند»).
Finds the newest upstream ffmpeg (same major line), ImageMagick 7, BusyBox 1.x, ONNX Runtime (Android AAR) and the
U-2-Netp model, compares them with what the latest published manifest.json was built from, and writes
GITHUB_OUTPUT: changed=true|false, ff/im/bb/ort/u2sha + a Persian/English summary. Build+test+publish only run
when changed=true (or the run was started with force=true)."""
import hashlib, json, os, re, sys, time, urllib.request

def get(url, binary=False, token=False):
    h = {"User-Agent": "kami-ag-engines"}
    if token and os.environ.get("GH_TOKEN"): h["Authorization"] = "Bearer " + os.environ["GH_TOKEN"]
    last = None
    for wait in (0, 20, 60, 120):  # public mirrors (Maven Central, busybox.net) sometimes answer 429 to CI runners
        if wait: time.sleep(wait)
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=h), timeout=60) as r:
                b = r.read(); return b if binary else b.decode("utf-8", "replace")
        except Exception as ex:
            last = ex; print("retry", url, ex)
    raise last

def safe(label, fn, fallback):
    """One upstream source down must not stop the weekly check: keep what we have for that engine."""
    try: return fn()
    except Exception as ex:
        print(f"WARN {label}: {ex} — keeping {fallback}"); return fallback

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
html = safe("ffmpeg", lambda: get("https://ffmpeg.org/releases/"), "")
ffs = sorted({x for x in re.findall(r"ffmpeg-(\d+\.\d+(?:\.\d+)?)\.tar\.xz", html)}, key=vkey)
ff_same = [v for v in ffs if v.split(".")[0] == major]
ff = ff_same[-1] if ff_same else ff_cur
ff_newer_major = [v for v in ffs if vkey(v)[0] > int(major)]

im = safe("magick", lambda: json.loads(get("https://api.github.com/repos/ImageMagick/ImageMagick/releases/latest", token=True))["tag_name"], cur.get("magick", "7.1.2-36"))
if not re.match(r"^7\.\d+\.\d+-\d+$", im): im = cur.get("magick", "7.1.2-36")

bbl = safe("busybox", lambda: get("https://busybox.net/downloads/"), "")
bbs = sorted({x for x in re.findall(r"busybox-(1\.\d+\.\d+)\.tar\.bz2\"", bbl)}, key=vkey)
bb = bbs[-1] if bbs else cur.get("busybox", "1.36.1")

ORT_CUR = cur.get("bgremove", "ort1.20.0")[3:] or "1.20.0"
def ort_latest():
    path = "com/microsoft/onnxruntime/onnxruntime-android/maven-metadata.xml"
    try:  # Google's Maven Central mirror first; Maven Central rate-limits GitHub runners (429)
        meta = get("https://maven-central.storage-download.googleapis.com/maven2/" + path)
    except Exception:
        meta = get("https://repo1.maven.org/maven2/" + path)
    return (re.search(r"<release>([0-9.]+)</release>", meta) or re.search(r"<latest>([0-9.]+)</latest>", meta)).group(1)
ort = safe("onnxruntime", ort_latest, ORT_CUR)

U2_PIN = "309c8469258dda742793dce0ebea8e6dd393174f89934733ecc8b14c76f4ddd8"
u2 = safe("u2netp", lambda: hashlib.sha256(get("https://github.com/danielgatis/rembg/releases/download/v0.0.0/u2netp.onnx", binary=True)).hexdigest(), cur.get("bgremove_model", U2_PIN))

new = {"ffmpeg": ff, "magick": im, "busybox": bb, "bgremove": "ort" + ort, "bgremove_model": u2}
diff = [f"{k}: {cur.get(k) or '—'} → {v}" for k, v in new.items() if cur.get(k) != v]
force = os.environ.get("FORCE", "false") == "true"
changed = bool(diff) or force
summary = ("; ".join(diff) if diff else "no upstream change") + (" (force)" if force else "")
if ff_newer_major: summary += f"; note: ffmpeg {ff_newer_major[-1]} exists (new major — not built automatically)"
print(json.dumps(new, indent=1)); print("CHANGED:", changed, "|", summary)
with open(os.environ.get("GITHUB_OUTPUT", "/dev/stdout"), "a") as o:
    o.write(f"changed={'true' if changed else 'false'}\nff={ff}\nim={im}\nbb={bb}\nort={ort}\nu2sha={u2}\nsummary={summary}\n")
