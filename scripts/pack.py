#!/usr/bin/env python3
"""Zip each built engine + write manifest.json (name, version, size, sha256, min app version)."""
import hashlib, json, os, sys, zipfile
out, tag, run = sys.argv[1], sys.argv[2], sys.argv[3]
repo = os.environ.get("GITHUB_REPOSITORY", "kejbahs/kami-ag-engines")
dist = os.path.join(out, "dist"); os.makedirs(dist, exist_ok=True)
def ver(name):
    p = os.path.join(out, name + ".version")
    return open(p).read().strip() if os.path.exists(p) else None
specs = [
  ("ffmpeg", "ffmpeg + ffprobe", "ویدیو و صدا: برش، تبدیل، فشرده‌سازی، استخراج صدا", ["libffmpeg_engine.so", "libffprobe_engine.so"], {"ffmpeg": "libffmpeg_engine.so", "ffprobe": "libffprobe_engine.so"}, "ffmpeg-licenses", "GPL-2.0-or-later (ffmpeg + x264 + LAME)"),
  ("magick", "ImageMagick", "عکس: تبدیل، تغییر اندازه، کار گروهی روی عکس‌ها", ["libmagick_engine.so"], {"magick": "libmagick_engine.so", "convert": "libmagick_engine.so", "identify": "libmagick_engine.so", "mogrify": "libmagick_engine.so", "composite": "libmagick_engine.so", "montage": "libmagick_engine.so"}, "magick-config", "ImageMagick License"),
  ("busybox", "BusyBox", "ابزارهای اضافهٔ خط فرمان (awk، bc، wget ساده، …)", ["libbusybox_engine.so"], {"busybox": "libbusybox_engine.so"}, None, "GPL-2.0"),
]
engines = []
for eid, title, desc, libs, cmds, extra, lic in specs:
    v = ver(eid)
    if not v or not all(os.path.exists(os.path.join(out, l)) for l in libs):
        print("skip", eid, "(not built)"); continue
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
    engines.append({"id": eid, "title": title, "description": desc, "version": version, "upstream": v,
                    "min_app": "0.6.1", "abi": "arm64-v8a", "file": zname,
                    "url": f"https://github.com/{repo}/releases/download/{tag}/{zname}",
                    "size": len(data), "sha256": hashlib.sha256(data).hexdigest(),
                    "libs": libs, "commands": cmds, "license": lic})
    print(eid, version, len(data))
json.dump({"schema": 1, "tag": tag, "engines": engines}, open(os.path.join(dist, "manifest.json"), "w"), ensure_ascii=False, indent=1)
if not any(e["id"] == "ffmpeg" for e in engines): sys.exit("ffmpeg missing — no release")
