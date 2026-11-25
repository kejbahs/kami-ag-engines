# Shared NDK settings (sourced).
set -euo pipefail
export NDK=${ANDROID_NDK_LATEST_HOME:-${ANDROID_NDK_HOME:-}}
[ -d "$NDK" ] || { echo "NDK not found"; exit 1; }
export API=26
export TC=$NDK/toolchains/llvm/prebuilt/linux-x86_64
export CC=$TC/bin/aarch64-linux-android$API-clang
export CXX=$TC/bin/aarch64-linux-android$API-clang++
export AR=$TC/bin/llvm-ar RANLIB=$TC/bin/llvm-ranlib STRIP=$TC/bin/llvm-strip NM=$TC/bin/llvm-nm READELF=$TC/bin/llvm-readelf
export SYSROOT=$TC/sysroot
export ROOT=$(pwd)
export PREFIX=$ROOT/build/prefix
export OUT=$ROOT/build/out
export WORK=$ROOT/build/work
mkdir -p $PREFIX/lib $PREFIX/include $OUT $WORK
export PKG_CONFIG_LIBDIR=$PREFIX/lib/pkgconfig
export PKG_CONFIG_PATH=
export JOBS=$(nproc)
CMAKE_ANDROID="-DCMAKE_TOOLCHAIN_FILE=$NDK/build/cmake/android.toolchain.cmake -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=$API -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=$PREFIX -DCMAKE_POSITION_INDEPENDENT_CODE=ON -DBUILD_SHARED_LIBS=OFF"
LDSO="-shared -Wl,--no-undefined -Wl,--wrap=exit -Wl,-z,max-page-size=16384 -Wl,--exclude-libs,ALL"
fetch() { # url file
  for i in 1 2 3; do curl -fsSL --retry 3 -o "$2" "$1" && return 0; sleep 5; done; return 1; }
bridge() { $CC -c -fPIC -O2 -fvisibility=default $ROOT/bridge/kami_engine_jni.c -o $WORK/bridge.o; }
check_so() { # lib.so — fail if it needs anything but Android system libs or lacks the JNI entry
  local f=$1
  echo "== $f"; ls -l $f
  $READELF -d $f | grep NEEDED || true
  bad=$($READELF -d $f | grep NEEDED | grep -vE '\[(libc|libm|libdl|liblog|libz|libandroid|libmediandk)\.so\]' || true)
  [ -z "$bad" ] || { echo "unexpected NEEDED: $bad"; exit 1; }
  $NM -D --defined-only $f | grep -q Java_com_kami_ag_engines_EngineNative_run || { echo "JNI entry missing"; exit 1; }
  $NM -D --defined-only $f | grep -q kami_engine_main || { echo "kami_engine_main missing"; exit 1; }
  $READELF -h $f | grep -q AArch64 || { echo "not arm64"; exit 1; }
}
