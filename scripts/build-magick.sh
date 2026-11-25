#!/bin/bash
# ImageMagick 7 (magick / convert / identify / mogrify / composite / montage) as one arm64 shared library.
# Delegates inside: libpng, libjpeg-turbo, libwebp, freetype, zlib (system).
source "$(dirname "$0")/env.sh"
IM_VER=${IM_VER:-7.1.2-36}
cd $WORK
# engines-6 fix (phone test 2026-11-25: «NoEncodeDelegateForThisImageFormat PNG», Delegates: jpeg webp only):
# libpng16.pc and freetype2.pc say «Requires.private: zlib», but zlib comes from the NDK sysroot and had no
# .pc in PKG_CONFIG_LIBDIR — so pkg-config rejected png AND freetype (and zlib itself) silently.
mkdir -p $PREFIX/lib/pkgconfig
ZV=$(grep -m1 '#define ZLIB_VERSION' $SYSROOT/usr/include/zlib.h | cut -d'"' -f2)
cat > $PREFIX/lib/pkgconfig/zlib.pc <<PC
prefix=$SYSROOT/usr
Name: zlib
Description: zlib from the Android NDK sysroot
Version: ${ZV:-1.2.13}
Libs: -lz
Cflags:
PC
pkg-config --exists zlib && echo "zlib.pc ok ($(pkg-config --modversion zlib))"
fetch https://github.com/pnggroup/libpng/archive/refs/tags/v1.6.47.tar.gz png.tgz && tar xf png.tgz
cmake -S libpng-1.6.47 -B png-b $CMAKE_ANDROID -DPNG_SHARED=OFF -DPNG_STATIC=ON -DPNG_TESTS=OFF -DPNG_TOOLS=OFF -DPNG_EXECUTABLES=OFF && cmake --build png-b -j$JOBS && cmake --install png-b
fetch https://github.com/libjpeg-turbo/libjpeg-turbo/archive/refs/tags/3.1.0.tar.gz jpg.tgz && tar xf jpg.tgz
cmake -S libjpeg-turbo-3.1.0 -B jpg-b $CMAKE_ANDROID -DENABLE_SHARED=OFF -DENABLE_STATIC=ON -DWITH_TURBOJPEG=OFF && cmake --build jpg-b -j$JOBS && cmake --install jpg-b
fetch https://github.com/webmproject/libwebp/archive/refs/tags/v1.5.0.tar.gz webp.tgz && tar xf webp.tgz
cmake -S libwebp-1.5.0 -B webp-b $CMAKE_ANDROID -DWEBP_BUILD_ANIM_UTILS=OFF -DWEBP_BUILD_CWEBP=OFF -DWEBP_BUILD_DWEBP=OFF -DWEBP_BUILD_GIF2WEBP=OFF -DWEBP_BUILD_IMG2WEBP=OFF -DWEBP_BUILD_VWEBP=OFF -DWEBP_BUILD_WEBPINFO=OFF -DWEBP_BUILD_WEBPMUX=OFF -DWEBP_BUILD_EXTRAS=OFF && cmake --build webp-b -j$JOBS && cmake --install webp-b
fetch https://github.com/freetype/freetype/archive/refs/tags/VER-2-13-3.tar.gz ft.tgz && tar xf ft.tgz
cmake -S freetype-VER-2-13-3 -B ft-b $CMAKE_ANDROID -DFT_DISABLE_HARFBUZZ=ON -DFT_DISABLE_BROTLI=ON -DFT_DISABLE_BZIP2=ON -DFT_DISABLE_PNG=ON -DFT_REQUIRE_ZLIB=ON && cmake --build ft-b -j$JOBS && cmake --install ft-b
ls $PREFIX/lib $PREFIX/lib/pkgconfig || true
for m in zlib libpng16 freetype2 libjpeg libwebp; do pkg-config --static --exists $m || { echo "pkg-config cannot resolve $m"; pkg-config --static --print-errors --exists $m; exit 1; }; done
fetch https://github.com/ImageMagick/ImageMagick/archive/refs/tags/$IM_VER.tar.gz im.tgz && tar xf im.tgz
cd ImageMagick-$IM_VER
PKG_CONFIG="pkg-config --static" LIBS="-lsharpyuv -lm" ./configure --host=aarch64-linux-android --prefix=$PREFIX CC=$CC CXX=$CXX AR=$AR RANLIB=$RANLIB \
  CFLAGS="-O2 -fPIC -I$PREFIX/include" CPPFLAGS="-I$PREFIX/include" LDFLAGS="-L$PREFIX/lib" \
  --enable-static --disable-shared --with-pic --without-modules --disable-openmp --disable-opencl --without-x --without-perl \
  --without-magick-plus-plus --disable-docs --with-png --with-jpeg --with-webp --with-freetype --with-zlib \
  --without-xml --without-lcms --without-tiff --without-fontconfig --without-heic --without-jxl --without-raw --without-lzma \
  --without-bzlib --without-zstd --without-openexr --without-gslib --without-gvc --without-rsvg --without-wmf --without-djvu \
  --without-fftw --without-pango --without-raqm --without-jbig --without-dps --without-fpx --without-lqr --without-zip --without-uhdr
# CI gate: configure must really have enabled PNG, FreeType, zlib, JPEG and WebP.
for d in PNG FREETYPE ZLIB JPEG WEBP; do
  grep -qE "define (MAGICKCORE_)?${d}_DELEGATE 1" config/config.h MagickCore/magick-baseconfig.h 2>/dev/null || {
    echo "DELEGATE MISSING: $d"; grep -hE "_DELEGATE" config/config.h MagickCore/magick-baseconfig.h 2>/dev/null | head -40
    grep -iE "png|freetype|zlib" config.log | tail -40; exit 1; }
done
echo "delegates PNG FREETYPE ZLIB JPEG WEBP: configured"
make -j$JOBS
make install
bridge
MOBJ=$(find utilities -name '*magick*.o' | head -1)
[ -n "$MOBJ" ] || { echo "magick object not found"; find utilities -name '*.o'; exit 1; }
LIBS=$(pkg-config --static --libs MagickWand)
$CC $LDSO -o $OUT/libmagick_engine.so -Wl,-soname,libmagick_engine.so $WORK/bridge.o $MOBJ -L$PREFIX/lib $LIBS -lsharpyuv -lz -lm -llog -ldl
# symbol check BEFORE stripping: the real libpng / FreeType / zlib code is inside the library
# (nm output goes to a file first: «nm | grep -q» under pipefail fails with SIGPIPE when grep stops early)
$NM $OUT/libmagick_engine.so > $WORK/magick.syms
$NM -D $OUT/libmagick_engine.so > $WORK/magick.dsyms
for sym in png_create_write_struct FT_Init_FreeType jpeg_start_compress WebPEncode; do
  grep -q " [Tt] $sym$" $WORK/magick.syms || { echo "SYMBOL MISSING in libmagick_engine.so: $sym"; grep -c . $WORK/magick.syms; grep -i "png_create\|FT_Init" $WORK/magick.syms | head; exit 1; }
done
grep -qE " U (deflate|inflate)$" $WORK/magick.dsyms || { echo "zlib (system libz) not used"; exit 1; }
echo "symbols png/freetype/zlib/jpeg/webp: present"
$STRIP --strip-unneeded $OUT/libmagick_engine.so
check_so $OUT/libmagick_engine.so
mkdir -p $OUT/magick-config; cp $PREFIX/etc/ImageMagick-7/*.xml $OUT/magick-config/ 2>/dev/null || true
cp LICENSE $OUT/magick-config/ImageMagick-LICENSE
echo "$IM_VER" > $OUT/magick.version
