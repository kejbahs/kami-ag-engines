#!/usr/bin/env python3
"""Zip one built engine + its manifest entry; or merge entries into manifest.json.
usage: pack.py one OUT TAG RUN EID   -> OUT/dist/<zip> + OUT/dist/<eid>.entry.json
       pack.py merge DIR TAG          -> DIR/manifest.json from DIR/*.entry.json (fails without ffmpeg)
"""
import glob, hashlib, json, os, sys, zipfile

repo = os.environ.get("GITHUB_REPOSITORY", "kejbahs/kami-ag-engines")
SPECS = {
  "ffmpeg": ("ffmpeg + ffprobe", "ویدیو و صدا: برش، تبدیل، فشرده‌سازی، استخراج صدا", ["libffmpeg_engine.so", "libffprobe_engine.so"], {"ffmpeg": "libffmpeg_engine.so", "ffprobe": "libffprobe_engine.so"}, "ffmpeg-licenses", "GPL-2.0-or-later (ffmpeg + x264 + LAME)"),
  "magick": ("ImageMagick", "عکس: تبدیل، تغییر اندازه، کار گروهی روی عکس‌ها", ["libmagick_engine.so"], {"magick": "libmagick_engine.so", "convert": "libmagick_engine.so", "identify": "libmagick_engine.so", "mogrify": "libmagick_engine.so", "composite": "libmagick_engine.so", "montage": "libmagick_engine.so"}, "magick-config", "ImageMagick License"),
  "busybox": ("BusyBox", "ابزارهای اضافهٔ خط فرمان (awk، bc، wget ساده، …)", ["libbusybox_engine.so"], {"busybox": "libbusybox_engine.so"}, None, "GPL-2.0"),
}

def merge(d, tag):
    engines = [json.load(open(f)) for f in sorted(glob.glob(os.path.join(d, "*.entry.json")))]
    order = {"ffmpeg": 0, "magick": 1, "busybox": 2}
    engines.sort(key=lambda e: order.get(e["id"], 9))
    json.dump({"schema": 1, "tag": tag, "engines": engines}, open(os.path.join(d, "manifest.json"), "w"), ensure_ascii=False, indent=1)
    print("manifest:", [(e["id"], e["version"], e["size"]) for e in engines])
    if not any(e["id"] == "ffmpeg" for e in engines): sys.exit("ffmpeg missing — no release")

def one(out, tag, run, eid):
    title, desc, libs, cmds, extra, lic = SPECS[eid]
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
        if extra and os.path.isdir(os.path.join(out, extra)):
            for f in sorted(os.listdir(os.path.join(out, extra))):
                z.write(os.path.join(out, extra, f), ("config/" if eid == "magick" else "licenses/") + f)
        if eid == "busybox" and os.path.exists(os.path.join(out, "busybox-LICENSE")):
            z.write(os.path.join(out, "busybox-LICENSE"), "licenses/busybox-LICENSE")
    data = open(zp, "rb").read()
    e = {"id": eid, "title": title, "description": desc, "version": version, "upstream": v,
         "min_app": "0.6.1", "abi": "arm64-v8a", "file": zname,
         "url": f"https://github.com/{repo}/releases/download/{tag}/{zname}",
         "size": len(data), "sha256": hashlib.sha256(data).hexdigest(),
         "libs": libs, "commands": cmds, "license": lic}
    json.dump(e, open(os.path.join(dist, eid + ".entry.json"), "w"), ensure_ascii=False, indent=1)
    print(eid, version, len(data), e["sha256"])

if sys.argv[1] == "merge": merge(sys.argv[2], sys.argv[3])
else: one(sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5])
