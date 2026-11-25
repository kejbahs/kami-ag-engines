#!/bin/bash
# engines-6 «حذف پس‌زمینه» pack — open source, fully on the phone (no Play services / ML Kit):
#   libbgremove_engine.so (tools/bgremove.c + bridge) + libonnxruntime.so (ONNX Runtime, MIT, from the
#   official Maven AAR) + config/u2netp.onnx (U-2-Netp, Apache-2.0). Every download is SHA-256 pinned
#   unless the weekly upstream check passed a NEW version (then its SHA is printed and recorded in the manifest).
source "$(dirname "$0")/env.sh"
ORT_VER=${ORT_VER:-1.20.0}
ORT_SHA=${ORT_SHA:-07a8f71ef890afed8c6087a56220e6d558a492804276ee2dd7cb7f6262242027}
U2_URL=${U2_URL:-https://github.com/danielgatis/rembg/releases/download/v0.0.0/u2netp.onnx}
U2_SHA=${U2_SHA:-309c8469258dda742793dce0ebea8e6dd393174f89934733ecc8b14c76f4ddd8}
STB=f58f558c120e9b32c217290b80bad1a0729fbb2c
cd $WORK
sha() { local got; got=$(sha256sum "$1" | cut -d' ' -f1); echo "$1 sha256=$got"; [ -z "$2" ] || [ "$got" = "$2" ] || { echo "SHA MISMATCH $1 (want $2)"; exit 1; }; }
# Google's public Maven Central mirror first (Maven Central answers GitHub runners with 429 at busy times).
ORT_PATH=com/microsoft/onnxruntime/onnxruntime-android/$ORT_VER/onnxruntime-android-$ORT_VER.aar
curl -fsSL --retry 2 -o ort.aar https://maven-central.storage-download.googleapis.com/maven2/$ORT_PATH \
  || curl -fsSL -o ort.aar https://repo1.maven.org/maven2/$ORT_PATH
[ "$ORT_VER" = "1.20.0" ] && sha ort.aar "$ORT_SHA" || sha ort.aar ""
rm -rf ort && mkdir ort && (cd ort && unzip -q ../ort.aar)
fetch "$U2_URL" u2netp.onnx; sha u2netp.onnx "$U2_SHA"
fetch https://raw.githubusercontent.com/nothings/stb/$STB/stb_image.h stb_image.h; sha stb_image.h 594c2fe35d49488b4382dbfaec8f98366defca819d916ac95becf3e75f4200b3
fetch https://raw.githubusercontent.com/nothings/stb/$STB/stb_image_write.h stb_image_write.h; sha stb_image_write.h cbd5f0ad7a9cf4468affb36354a1d2338034f2c12473cf1a8e32053cb6914a05
bridge
$CC -c -fPIC -O2 -I$WORK/ort/headers -I$WORK $ROOT/tools/bgremove.c -o $WORK/bgremove.o
$CC $LDSO -o $OUT/libbgremove_engine.so -Wl,-soname,libbgremove_engine.so $WORK/bridge.o $WORK/bgremove.o -lm -llog -ldl
$STRIP --strip-unneeded $OUT/libbgremove_engine.so
check_so $OUT/libbgremove_engine.so
cp ort/jni/arm64-v8a/libonnxruntime.so $OUT/libonnxruntime.so
$READELF -d $OUT/libonnxruntime.so | grep -E "NEEDED|SONAME"
bad=$($READELF -d $OUT/libonnxruntime.so | grep NEEDED | grep -vE '\[(libc|libm|libdl|liblog|libandroid)\.so\]' || true)
[ -z "$bad" ] || { echo "onnxruntime needs: $bad"; exit 1; }
mkdir -p $OUT/bgremove-config $OUT/bgremove-licenses
cp u2netp.onnx $OUT/bgremove-config/u2netp.onnx
fetch https://raw.githubusercontent.com/microsoft/onnxruntime/v$ORT_VER/LICENSE $OUT/bgremove-licenses/onnxruntime-LICENSE || echo "MIT License — ONNX Runtime (c) Microsoft Corporation" > $OUT/bgremove-licenses/onnxruntime-LICENSE
fetch https://raw.githubusercontent.com/xuebinqin/U-2-Net/master/LICENSE $OUT/bgremove-licenses/U-2-Net-LICENSE || echo "Apache License 2.0 — U-2-Net (Xuebin Qin)" > $OUT/bgremove-licenses/U-2-Net-LICENSE
tail -n 45 stb_image.h > $OUT/bgremove-licenses/stb-LICENSE
echo "ort$ORT_VER" > $OUT/bgremove.version
sha256sum u2netp.onnx | cut -d" " -f1 > $OUT/bgremove.model
ls -l $OUT/libbgremove_engine.so $OUT/libonnxruntime.so $OUT/bgremove-config
