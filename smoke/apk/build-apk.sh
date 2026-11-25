#!/bin/bash
# Builds smoke/apk → smoke.apk (debuggable, arm64-only so the emulator runs it under ARM translation).
set -euo pipefail
cd "$(dirname "$0")"
SDK=${ANDROID_HOME:-$ANDROID_SDK_ROOT}
BT=$(ls -d $SDK/build-tools/* | sort -V | tail -1)
PLAT=$(ls -d $SDK/platforms/android-* | sort -V | tail -1)
TC=$ANDROID_NDK_LATEST_HOME/toolchains/llvm/prebuilt/linux-x86_64
rm -rf b && mkdir -p b/classes b/dex b/lib/arm64-v8a
javac -source 1.8 -target 1.8 -bootclasspath $PLAT/android.jar -d b/classes $(find src -name '*.java') 2>&1 | grep -v warning || true
$BT/d8 --lib $PLAT/android.jar --min-api 26 --output b/dex $(find b/classes -name '*.class')
echo 'int kami_smoke_dummy(void) { return 0; }' > b/dummy.c
$TC/bin/aarch64-linux-android26-clang -shared -fPIC -o b/lib/arm64-v8a/libsmokedummy.so b/dummy.c
$BT/aapt2 link -o b/base.apk --manifest AndroidManifest.xml -I $PLAT/android.jar
(cd b/dex && zip -q ../base.apk classes.dex)
(cd b && zip -q -0 base.apk lib/arm64-v8a/libsmokedummy.so)
$BT/zipalign -p -f 4 b/base.apk b/aligned.apk
keytool -genkeypair -keystore b/k.jks -storepass smoke123 -keypass smoke123 -alias s -keyalg RSA -keysize 2048 -validity 30 -dname CN=smoke >/dev/null 2>&1
$BT/apksigner sign --ks b/k.jks --ks-pass pass:smoke123 --key-pass pass:smoke123 --out ../../smoke.apk b/aligned.apk
ls -l ../../smoke.apk
