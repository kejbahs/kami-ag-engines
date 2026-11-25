# kami-ag-engines

On-phone engines for the **Kami AG** Android app (arm64-v8a): ffmpeg + ffprobe (with x264 and LAME), ImageMagick 7, BusyBox.

- Each engine is a self-contained shared library (`lib<engine>_engine.so`) whose `main()` is called in-process by the app
  (Android 10+ blocks `exec()` of downloaded files, but allows loading a downloaded library).
- Nothing is inside the APK: the app downloads each pack **only when Kamran taps it** in «ابزارهای محلی و مدل‌ها»,
  checks size + SHA-256 from `manifest.json`, keeps the previous version for one-tap rollback, and checks for a newer
  version only when he taps «بررسی نسخهٔ تازه».
- Built entirely in this repo's GitHub Actions with the Android NDK (`.github/workflows/build-engines.yml`). Packs are
  Release assets (no Actions artifacts). No secrets in this repo.
- Licenses: the ffmpeg pack is a GPL build (x264, LAME); ImageMagick License; BusyBox GPL-2.0. Build scripts in `scripts/`.
