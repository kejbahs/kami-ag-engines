# kami-ag-engines

On-phone engines for the **Kami AG** Android app (arm64-v8a): ffmpeg + ffprobe (with x264 and LAME), ImageMagick 7
(PNG, JPEG, WebP, FreeType text, zlib), BusyBox, and **background removal** (U-2-Netp + ONNX Runtime — open source,
fully offline, no Google Play services).

- Each engine is a self-contained shared library (`lib<engine>_engine.so`) whose `main()` is called in-process by the app
  (Android 10+ blocks `exec()` of downloaded files, but allows loading a downloaded library). The bridge
  (`bridge/kami_engine_jni.c`) writes the exit code, never runs the app's atexit handlers (`_exit`), and reports fatal
  signals (incl. SIGSYS from Android's app seccomp) to `crash.txt`.
- Nothing is inside the APK: the app downloads each pack **only when Kamran taps it** in «ابزارهای محلی و مدل‌ها»,
  checks size + SHA-256 from `manifest.json`, keeps the previous version for one-tap rollback, and checks for a newer
  version only when he taps «بررسی نسخهٔ تازه».
- **Self-updating without anyone**: `.github/workflows/build-engines.yml` runs weekly (and on dispatch — the app's
  «ساخت نسخهٔ تازهٔ موتورها» button). It checks upstream versions (`scripts/upstream.py`); if nothing changed it stops
  (no release). Otherwise it builds all packs into a draft, tests them on an Android emulator — every engine twice
  (JNI harness + a real app process, `smoke/`), checking exit code AND output content — and publishes the new
  `engines-N` + `manifest.json` only if every test passed; a failed draft is deleted. Phone install stays manual.
- Licenses: ffmpeg pack GPL (x264, LAME); ImageMagick License; BusyBox GPL-2.0; U-2-Netp Apache-2.0, ONNX Runtime MIT,
  stb public domain. Build scripts in `scripts/`. No secrets in this repo.
