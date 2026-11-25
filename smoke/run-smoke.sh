#!/bin/bash
# Runs inside the emulator step: pushes the arm64 runner + packs and prints SMOKE PASS/FAIL lines.
adb push smoke-arm64 /data/local/tmp/smoke >/dev/null && adb shell chmod 755 /data/local/tmp/smoke
for f in packs/*.so t.ppm; do adb push "$f" /data/local/tmp/ >/dev/null; done
t() { # name, check-file, command...
  local n=$1 chk=$2; shift 2
  out=$(adb shell "cd /data/local/tmp && rm -f $chk; ./smoke $* 2>&1; echo RC=\$?; [ -s $chk ] && echo FILE_OK" | tr -d '\r')
  echo "$out" | tail -6
  if echo "$out" | grep -q "RC=0" && { [ "$chk" = "-" ] || echo "$out" | grep -q FILE_OK; }; then echo "SMOKE PASS $n"; else echo "SMOKE FAIL $n"; fi
}
t ffmpeg-mp3 s.mp3 ./libffmpeg_engine.so ffmpeg -nostdin -hide_banner -f lavfi -i sine=d=1 -c:a libmp3lame -y s.mp3
t ffprobe - ./libffprobe_engine.so ffprobe -hide_banner s.mp3
t ffmpeg-x264 v.mp4 ./libffmpeg_engine.so ffmpeg -nostdin -hide_banner -f lavfi -i testsrc=d=1:s=320x240 -c:v libx264 -y v.mp4
adb shell "[ -f /data/local/tmp/libmagick_engine.so ]" && t magick-resize t.png ./libmagick_engine.so magick t.ppm -resize 20x20 t.png || echo "SMOKE SKIP magick (no pack)"
adb shell "[ -f /data/local/tmp/libbusybox_engine.so ]" && t busybox - ./libbusybox_engine.so busybox echo busybox-ok || echo "SMOKE SKIP busybox (no pack)"
exit 0
