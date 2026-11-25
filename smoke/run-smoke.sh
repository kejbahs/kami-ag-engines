#!/bin/bash
# engines smoke (inside the emulator step): smoke.c dlopens each engine .so and runs its real main
# (kami_engine_main) under ARM translation. The JNI-thread path is exercised on the phone.
# Each test checks the exit code AND the real output content. Any FAIL → exit 1 → nothing is published.
set -u
P=com.kami.ag.enginesmoke
T=/data/local/tmp
fails=0; passes=0
adb push smoke-arm64 $T/smk >/dev/null; adb shell chmod 755 $T/smk
mkdir -p in
python3 - <<'PY'
open("in/t.ppm","wb").write(b"P6\n2 2\n255\n"+bytes([255,0,0, 0,255,0, 0,0,255, 255,255,255]))
w,h=64,48; px=bytearray()
for y in range(h):
    for x in range(w):
        px += bytes([220,40,40]) if 20<=x<44 and 12<=y<36 else bytes([30,160,40])
open("in/bg.ppm","wb").write(b"P6\n%d %d\n255\n"%(w,h)+bytes(px))
PY
adb shell "rm -rf $T/hxjob $T/config; mkdir -p $T/hxjob $T/config"
for f in packs/*.so; do adb push "$f" $T/ >/dev/null; done
if [ -d packs/config ]; then for f in packs/config/*; do adb push "$f" $T/config/ >/dev/null; done; fi
for f in in/*; do adb push "$f" $T/hxjob/ >/dev/null; done

have() { [ -f "packs/$1" ]; }

check() { # name want(0|nz) regex output
  local n=$1 want=$2 re=$3 out=$4
  local rc; rc=$(echo "$out" | grep -m1 '^RC ' | awk '{print $2}')
  echo "----- $n"; echo "$out" | head -c 1600; echo
  local rcok=0
  if [ "$want" = "nz" ]; then [ -n "$rc" ] && [ "$rc" != "0" ] && { [ "$rc" -lt 129 ] || [ "$rc" -gt 159 ]; } 2>/dev/null && rcok=1
  else [ "$rc" = "$want" ] && rcok=1; fi
  if [ $rcok = 1 ] && echo "$out" | grep -Eq -- "$re"; then echo "SMOKE PASS $n"; passes=$((passes+1))
  else echo "SMOKE FAIL $n (rc=$rc want=$want, expect /$re/)"; fails=$((fails+1)); fi
}

t() { # NAME WANT REGEX LIB ARGV…
  # CI path = smoke.c: dlopen the engine .so and call its real main via kami_engine_main (the same path that
  # passed in engines-5). On the x86_64 emulator arm64 code runs under ARM translation; the JNI-thread harness
  # and the app-process run crash/hang under that translation (runs 45696871637, 45701155472), so the
  # app-process run is informational only (APPINFO, not counted). The real JNI path is tested on the phone.
  local name=$1 want=$2 re=$3 lib=$4; shift 4
  local args=""; for a in "$@"; do args="$args '$a'"; done
  echo "[$(date -u +%H:%M:%S)] start $name"
  local out; out=$(timeout 300 adb shell "cd $T/hxjob && LD_LIBRARY_PATH=$T HOME=$T/hxjob TMPDIR=$T/hxjob MAGICK_CONFIGURE_PATH=$T/config MAGICK_TEMPORARY_PATH=$T/hxjob timeout 280 $T/smk $T/$lib $args 2>&1; r=\$?; echo; echo RC \$r" | tr -d '\r')
  [ -n "$out" ] || out="RC timeout (no answer from adb in 300 s)"
  # RC line is the LAST line we print; move it first for check()
  local rcl; rcl=$(echo "$out" | grep '^RC ' | tail -1)
  check "$name" "$want" "$re" "$rcl
$out"
}

if have libffmpeg_engine.so; then
  t ffmpeg-mp3 0 "Output #0, mp3" libffmpeg_engine.so ffmpeg -nostdin -hide_banner -f lavfi -i sine=d=1 -c:a libmp3lame -y s.mp3
  t ffprobe-mp3 0 "Audio: mp3" libffprobe_engine.so ffprobe -hide_banner s.mp3
  t ffmpeg-x264 0 "libx264" libffmpeg_engine.so ffmpeg -nostdin -hide_banner -f lavfi -i testsrc=d=1:s=320x240 -c:v libx264 -y v.mp4
  t ffprobe-h264 0 "Video: h264" libffprobe_engine.so ffprobe -hide_banner v.mp4
  t ffmpeg-badinput nz "No such file|Error opening input" libffmpeg_engine.so ffmpeg -nostdin -hide_banner -i nothere.mp4 -y x.mp3
else echo "SMOKE FAIL ffmpeg (no pack)"; fails=$((fails+1)); fi

if have libmagick_engine.so; then
  t magick-delegates 0 "Delegates \(built-in\):.*freetype.*png.*zlib" libmagick_engine.so magick -version
  t magick-png 0 "RC 0" libmagick_engine.so magick t.ppm -resize 20x20 t.png
  t magick-png-id 0 "PNG 20x20" libmagick_engine.so magick identify t.png
  t magick-text 0 "RC 0" libmagick_engine.so magick -size 200x60 xc:white -fill black -font /system/fonts/Roboto-Regular.ttf -pointsize 28 -annotate +10+42 "Kami AG" txt.png
  t magick-text-ink 0 "INK=1" libmagick_engine.so magick txt.png -colorspace gray -format "INK=%[fx:minima<0.5?1:0]" info:
else echo "SMOKE FAIL magick (no pack)"; fails=$((fails+1)); fi

if have libbusybox_engine.so; then
  t busybox-echo 0 "busybox-ok" libbusybox_engine.so busybox echo busybox-ok
  t busybox-sha 0 "[0-9a-f]{64} +t.ppm" libbusybox_engine.so busybox sha256sum t.ppm
  t busybox-wc 0 "[0-9]+ +[0-9]+ +[0-9]+ +t.ppm" libbusybox_engine.so busybox wc t.ppm
else echo "SMOKE FAIL busybox (no pack)"; fails=$((fails+1)); fi

tx() { # x86_64 twin (same source, same ORT version, native on the emulator)
  local name=$1 want=$2 re=$3; shift 3
  local args=""; for a in "$@"; do args="$args '$a'"; done
  echo "[$(date -u +%H:%M:%S)] start $name"
  local out; out=$(timeout 300 adb shell "cd $T/hxjob && LD_LIBRARY_PATH=$T/x86test timeout 280 $T/x86test/smk $T/x86test/libbgremove_engine.so $args 2>&1; r=\$?; echo; echo RC \$r" | tr -d '\r')
  [ -n "$out" ] || out="RC timeout"
  local rcl; rcl=$(echo "$out" | grep '^RC ' | tail -1)
  check "$name" "$want" "$re" "$rcl
$out"
}
if [ -d packs/x86test ]; then adb push packs/x86test $T/ >/dev/null; adb shell chmod 755 $T/x86test/smk; fi

if have libbgremove_engine.so; then
  if [ -d packs/x86test ]; then
    tx bgremove-x86twin 0 "BGREMOVE OK 64x48 fg=([5-9]|[1-7][0-9])%" bgremove bg.ppm cut.png --mask mask.png
  else echo "SMOKE FAIL bgremove (no x86_64 twin)"; fails=$((fails+1)); fi
  if have libmagick_engine.so; then
    t bgremove-alpha 0 "TrueColorAlpha" libmagick_engine.so magick identify -verbose cut.png
  fi
  t bgremove-badinput nz "cannot read input image" libbgremove_engine.so bgremove nothere.jpg x.png
else echo "SMOKE FAIL bgremove (no pack)"; fails=$((fails+1)); fi

echo "SMOKE SUMMARY pass=$passes fail=$fails"
[ $fails -eq 0 ]
