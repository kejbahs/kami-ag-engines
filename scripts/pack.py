#!/usr/bin/env python3
"""Zip one built engine + its manifest entry; or merge entries into manifest.json.
usage: pack.py one OUT TAG RUN EID   -> OUT/dist/<zip> + OUT/dist/<eid>.entry.json
       pack.py merge DIR TAG          -> DIR/manifest.json from DIR/*.entry.json (fails unless ALL 4 engines are there)
"""
import glob, hashlib, json, os, sys, zipfile

repo = os.environ.get("GITHUB_REPOSITORY", "kejbahs/kami-ag-engines")
# id: (title, description, libs, commands, [(dir in OUT, prefix in zip)], license, min_app)
SPECS = {
  "ffmpeg": ("ffmpeg + ffprobe", "ویدیو و صدا: برش، تبدیل، فشرده‌سازی، استخراج صدا", ["libffmpeg_engine.so", "libffprobe_engine.so"],
             {"ffmpeg": "libffmpeg_engine.so", "ffprobe": "libffprobe_engine.so"}, [("ffmpeg-licenses", "licenses/")], "GPL-2.0-or-later (ffmpeg + x264 + LAME)", "0.6.1"),
  "magick": ("ImageMagick", "عکس: تبدیل، تغییر اندازه، PNG/JPEG/WebP، نوشتن متن با فونت، کار گروهی", ["libmagick_engine.so"],
             {"magick": "libmagick_engine.so", "convert": "libmagick_engine.so", "identify": "libmagick_engine.so", "mogrify": "libmagick_engine.so", "composite": "libmagick_engine.so", "montage": "libmagick_engine.so"},
             [("magick-config", "config/")], "ImageMagick License", "0.6.1"),
  "busybox": ("BusyBox", "ابزارهای اضافهٔ خط فرمان (awk، bc، sha256sum، wc، …)", ["libbusybox_engine.so"], {"busybox": "libbusybox_engine.so"},
              [("busybox-licenses", "licenses/")], "GPL-2.0", "0.6.1"),
  "bgremove": ("حذف پس‌زمینه (U-2-Netp)", "حذف پس‌زمینهٔ عکس کاملاً روی گوشی، بدون اینترنت و بدون سرویس‌های گوگل — مدل متن‌باز U-2-Netp با ONNX Runtime",
               ["libbgremove_engine.so", "libonnxruntime.so"], {"bgremove": "libbgremove_engine.so"},
               [("bgremove-config", "config/"), ("bgremove-licenses", "licenses/")], "Apache-2.0 (U-2-Netp) + MIT (ONNX Runtime) + public domain (stb)", "0.6.2"),
}
ORDER = ["ffmpeg", "magick", "busybox", "bgremove"]

def merge(d, tag):
    engines = [json.load(open(f)) for f in sorted(glob.glob(os.path.join(d, "*.entry.json")))]
    engines.sort(key=lambda e: ORDER.index(e["id"]) if e["id"] in ORDER else 9)
    ups = {e["id"]: e["upstream"] for e in engines}
    for e in engines:
        if e.get("model_sha256"): ups[e["id"] + "_model"] = e["model_sha256"]
    json.dump({"schema": 1, "tag": tag, "upstream": ups, "engines": engines}, open(os.path.join(d, "manifest.json"), "w"), ensure_ascii=False, indent=1)
    print("manifest:", [(e["id"], e["version"], e["size"]) for e in engines])
    missing = [i for i in ORDER if i not in ups]
    if missing: sys.exit("missing engines " + ",".join(missing) + " — no release")

def one(out, tag, run, eid):
    title, desc, libs, cmds, dirs, lic, min_app = SPECS[eid]
    vp = os.path.join(out, eid + ".version")
    if not os.path.exists(vp) or not all(os.path.exists(os.path.join(out, l)) for l in libs):
        sys.exit(eid + " not built")
    v = open(vp).read().strip()
    dist = os.path.join(out, "dist"); os.makedirs(dist, exist_ok=True)
    version = f"{v}-k{run}"
    zname = f"{eid}-{version}-arm64.zip"
    zp = os.path.join(dist, zname)
    with zipfile.ZipFile(zp, "w", zipfile.ZIP_DEFLATED) as z:
        for l in libs: z.write(os.path.join(out, l), l)
        for src, prefix in dirs:
            p = os.path.join(out, src)
            if os.path.isdir(p):
                for f in sorted(os.listdir(p)): z.write(os.path.join(p, f), prefix + f)
        if eid == "busybox" and os.path.exists(os.path.join(out, "busybox-LICENSE")):
            z.write(os.path.join(out, "busybox-LICENSE"), "licenses/busybox-LICENSE")
    data = open(zp, "rb").read()
    e = {"id": eid, "title": title, "description": desc, "version": version, "upstream": v,
         "min_app": min_app, "abi": "arm64-v8a", "file": zname,
         "url": f"https://github.com/{repo}/releases/download/{tag}/{zname}",
         "size": len(data), "sha256": hashlib.sha256(data).hexdigest(),
         "libs": libs, "commands": cmds, "license": lic}
    mp = os.path.join(out, eid + ".model")
    if os.path.exists(mp): e["model_sha256"] = open(mp).read().strip()
    json.dump(e, open(os.path.join(dist, eid + ".entry.json"), "w"), ensure_ascii=False, indent=1)
    print(eid, version, len(data), e["sha256"])

if sys.argv[1] == "merge": merge(sys.argv[2], sys.argv[3])
else: one(sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5])
