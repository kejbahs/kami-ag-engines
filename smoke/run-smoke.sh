#!/bin/bash
# engines-6 smoke (inside the emulator step). Every engine is tested TWICE:
#   HX  = jni_harness: the real JNI entry from a 64 MB worker thread (fake JNIEnv), adb shell user
#   APP = smoke.apk: a real Android app process (ART + app seccomp + System.load from files/ + JNI from a
#         Java thread + killProcess) — the same way Kami AG's :engine process runs it.
# Each test checks the exit code AND the real output content. Any FAIL → exit 1 → nothing is published.
set -u
P=com.kami.ag.enginesmoke
T=/data/local/tmp
fails=0; passes=0
adb install -r -g smoke.apk || { echo "SMOKE FAIL install smoke.apk"; exit 1; }
adb push jni-harness-arm64 $T/hx >/dev/null; adb shell chmod 755 $T/hx
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
adb shell "run-as $P sh -c 'rm -rf files/job files/config; mkdir -p files/job files/config'"
for f in packs/*.so; do b=$(basename $f); adb shell "cat $T/$b | run-as $P sh -c 'cat > files/$b'"; done
if [ -d packs/config ]; then for f in packs/config/*; do b=$(basename $f); adb shell "cat $T/config/$b | run-as $P sh -c 'cat > files/config/$b'"; done; fi
for f in in/*; do b=$(basename $f); adb shell "cat $T/hxjob/$b | run-as $P sh -c 'cat > files/job/$b'"; done
adb shell "run-as $P ls -l files files/job" | head -30

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
  local name=$1 want=$2 re=$3 lib=$4; shift 4
  local args=""; for a in "$@"; do args="$args '$a'"; done
  echo "[$(date -u +%H:%M:%S)] start $name"
  local hx; hx=$(timeout 300 adb shell "cd $T && MAGICK_CONFIGURE_PATH=$T/config timeout 280 ./hx $T/$lib $T/hxjob $args 2>&1; echo HXEXIT \$?" | tr -d '\r')
  [ -n "$hx" ] || hx="RC timeout (no answer from adb in 300 s)"
  check "HX  $name" "$want" "$re" "$hx"
  { echo "$lib"; for a in "$@"; do echo "$a"; done; } > /tmp/args.txt
  adb push /tmp/args.txt $T/args.txt >/dev/null
  adb shell "am force-stop $P; cat $T/args.txt | run-as $P sh -c 'rm -f files/job/rc.txt files/job/out.txt files/job/err.txt files/job/crash.txt files/job/fail.txt; cat > files/job/args.txt'"
  timeout 60 adb shell "am start -n $P/.Smoke" >/dev/null 2>&1
  local i=0
  while [ $i -lt 480 ]; do
    timeout 20 adb shell "run-as $P sh -c '[ -s files/job/rc.txt ]'" && break
    sleep 0.5; i=$((i+1))
  done
  sleep 0.5
  echo "[$(date -u +%H:%M:%S)] app $name done after $i polls"
  local app; app=$(timeout 60 adb shell "run-as $P sh -c 'cd files/job; echo RC \$(cat rc.txt 2>/dev/null); echo CRASH \$(cat crash.txt 2>/dev/null); echo FAIL \$(cat fail.txt 2>/dev/null); echo STDOUT; cat out.txt 2>/dev/null; echo; echo STDERR; tail -c 1500 err.txt 2>/dev/null'" | tr -d '\r')
  check "APP $name" "$want" "$re" "$app"
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

if have libbgremove_engine.so; then
  t bgremove 0 "BGREMOVE OK 64x48 fg=([5-9]|[1-7][0-9])%" libbgremove_engine.so bgremove bg.ppm cut.png --mask mask.png
  if have libmagick_engine.so; then
    t bgremove-alpha 0 "TrueColorAlpha" libmagick_engine.so magick identify -verbose cut.png
  fi
  t bgremove-badinput nz "cannot read input image" libbgremove_engine.so bgremove nothere.jpg x.png
else echo "SMOKE FAIL bgremove (no pack)"; fails=$((fails+1)); fi

echo "SMOKE SUMMARY pass=$passes fail=$fails"
[ $fails -eq 0 ]
