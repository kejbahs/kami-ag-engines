#!/bin/bash
# ffmpeg + ffprobe as two self-contained arm64 shared libraries (libx264 + libmp3lame inside). GPL build.
source "$(dirname "$0")/env.sh"
FF_VER=${FF_VER:-7.1.1}; LAME_VER=3.100
cd $WORK
fetch http://deb.debian.org/debian/pool/main/l/lame/lame_${LAME_VER}.orig.tar.gz lame.tgz
tar xf lame.tgz && cd lame-$LAME_VER
./configure --host=aarch64-linux-android --prefix=$PREFIX --enable-static --disable-shared --disable-frontend --disable-decoder --with-pic CC=$CC AR=$AR RANLIB=$RANLIB CFLAGS="-O2 -fPIC"
make -j$JOBS && make install
cd $WORK
git clone --depth 1 -b stable https://code.videolan.org/videolan/x264.git
cd x264
CC=$CC AR=$AR RANLIB=$RANLIB STRIP=$STRIP ./configure --prefix=$PREFIX --host=aarch64-linux-android --sysroot=$SYSROOT --enable-static --enable-pic --disable-cli --extra-cflags="-O2"
make -j$JOBS && make install
cd $WORK
fetch https://ffmpeg.org/releases/ffmpeg-$FF_VER.tar.xz ff.txz
tar xf ff.txz && cd ffmpeg-$FF_VER
./configure --prefix=$PREFIX --target-os=android --arch=aarch64 --cpu=armv8-a --enable-cross-compile \
  --cc=$CC --cxx=$CXX --ar=$AR --ranlib=$RANLIB --strip=$STRIP --nm=$NM --sysroot=$SYSROOT \
  --enable-pic --enable-static --disable-shared --disable-doc --disable-ffplay --disable-debug \
  --disable-indev=android_camera --enable-gpl --enable-libx264 --enable-libmp3lame --enable-zlib \
  --extra-cflags="-I$PREFIX/include -fPIC -O2" --extra-ldflags="-L$PREFIX/lib" \
  --pkg-config=pkg-config --pkg-config-flags=--static
make -j$JOBS
make install
bridge
LIBS=$(pkg-config --static --libs libavdevice libavfilter libavformat libavcodec libswresample libswscale libpostproc libavutil)
FFOBJ=$(ls fftools/ffmpeg*.o fftools/sync_queue.o fftools/thread_queue.o fftools/objpool.o 2>/dev/null | grep -v ffmpeg_g)
COMMON="fftools/cmdutils.o fftools/opt_common.o"
$CC $LDSO -o $OUT/libffmpeg_engine.so -Wl,-soname,libffmpeg_engine.so $WORK/bridge.o $FFOBJ $COMMON -L$PREFIX/lib $LIBS -lmp3lame -lz -lm -llog -ldl
$CC $LDSO -o $OUT/libffprobe_engine.so -Wl,-soname,libffprobe_engine.so $WORK/bridge.o fftools/ffprobe.o $COMMON -L$PREFIX/lib $LIBS -lmp3lame -lz -lm -llog -ldl
$STRIP --strip-unneeded $OUT/libffmpeg_engine.so $OUT/libffprobe_engine.so
check_so $OUT/libffmpeg_engine.so; check_so $OUT/libffprobe_engine.so
mkdir -p $OUT/ffmpeg-licenses; cp COPYING.GPLv2 $OUT/ffmpeg-licenses/ffmpeg-COPYING.GPLv2; cp $WORK/x264/COPYING $OUT/ffmpeg-licenses/x264-COPYING; cp $WORK/lame-$LAME_VER/COPYING $OUT/ffmpeg-licenses/lame-COPYING
echo "$FF_VER" > $OUT/ffmpeg.version
