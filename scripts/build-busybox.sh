#!/bin/bash
# busybox as an arm64 shared library (best effort — applets that re-exec themselves will not work).
source "$(dirname "$0")/env.sh"
BB_VER=${BB_VER:-1.36.1}
cd $WORK
fetch https://busybox.net/downloads/busybox-$BB_VER.tar.bz2 bb.tbz && tar xf bb.tbz && cd busybox-$BB_VER
make defconfig
# Turn off things bionic lacks or that make no sense inside an app.
# engines-6: FEATURE_SUID off — with it busybox calls setgid()/setuid() to «drop privileges» before every
# applet, and Android's app seccomp kills the process for that (SIGSYS): no output, «crash» (phone 19:06).
for o in FEATURE_SYSLOG SYSLOGD LOGGER KLOGD FEATURE_UTMP FEATURE_WTMP WALL LAST USERS WHO W RUNLEVEL LOGIN SU SULOGIN PASSWD CHPASSWD CRYPTPW MKPASSWD ADDUSER DELUSER ADDGROUP DELGROUP GETTY VLOCK \
  FEATURE_MOUNT_NFS MOUNT UMOUNT SWAPON SWAPOFF HWCLOCK RDATE NTPD ZCIP UDHCPD UDHCPC UDHCPC6 DHCPRELAY DUMPLEASES IFPLUGD ARPING ETHER_WAKE IFCONFIG ROUTE IP IPADDR IPLINK IPROUTE IPTUNNEL IPRULE IPNEIGH NAMEIF TUNCTL BRCTL VCONFIG NSLOOKUP TRACEROUTE TRACEROUTE6 PING PING6 \
  INETD TELNETD FTPD HTTPD TCPSVD UDPSVD NC_SERVER SSL_CLIENT FEATURE_WGET_HTTPS FEATURE_HTTPD_AUTH_MD5 \
  MKFS_EXT2 MKFS_VFAT MKFS_MINIX MKFS_REISER FSCK_MINIX FSCK MKE2FS TUNE2FS SETARCH LINUX32 LINUX64 ADJTIMEX CONSPY FBSET FBSPLASH DEVMEM I2CGET I2CSET I2CDUMP I2CDETECT I2CTRANSFER \
  NANDWRITE NANDDUMP UBIATTACH UBIDETACH UBIMKVOL UBIRMVOL UBIRSVOL UBIUPDATEVOL UBIRENAME SETSERIAL STTY SETCONSOLE OPENVT CHVT DEALLOCVT KBD_MODE LOADKMAP LOADFONT SETFONT SETKEYCODES SHOWKEY \
  INSMOD RMMOD LSMOD MODPROBE DEPMOD MODINFO MODPROBE_SMALL SEEDRNG SHA1SUM_HW FEATURE_SHA1_HWACCEL FEATURE_SHA256_HWACCEL TC TRACEROUTE PIVOT_ROOT SWITCH_ROOT CHROOT FEATURE_IPV6 LOADKMAP \
  ACPID BLKDISCARD BLKID BLOCKDEV FDFORMAT FDISK FINDFS FLOCK FREERAMDISK FSFREEZE IONICE LOSETUP LSPCI LSUSB MDEV MESG MKSWAP NSENTER UNSHARE RDEV READPROFILE RTCWAKE SCRIPT SETPRIV TASKSET UEVENT EJECT \
  FEATURE_SUID FEATURE_SUID_CONFIG FEATURE_SUID_CONFIG_QUIET \
  CRONTAB CROND MAKEDEVS MAN MICROCOM START_STOP_DAEMON RUNSV RUNSVDIR SV SVC SVOK SVLOGD CHPST ENVDIR ENVUIDGID SETUIDGID SOFTLIMIT HUSH FEATURE_SH_IS_HUSH; do
  sed -i "s/^CONFIG_$o=y/# CONFIG_$o is not set/" .config
done
set +o pipefail; yes "" | make oldconfig >/dev/null; set -o pipefail
# Self-healing: applets whose source does not compile against bionic are switched off one by one (up to 25 rounds).
BBMAKE="make CC=$CC AR=$AR STRIP=$STRIP CROSS_COMPILE= HOSTCC=gcc EXTRA_CFLAGS=-fPIC\ -O2"
for o in HOSTID IPCS IPCRM IPCALC NSENTER UNSHARE CONSPY ETHER_WAKE ARP ARPING; do sed -i "s/^CONFIG_$o=y/# CONFIG_$o is not set/" .config; done
set +o pipefail; yes "" | make oldconfig >/dev/null; set -o pipefail
ok=0
for round in $(seq 1 25); do
  if make -k -j$JOBS CC=$CC AR=$AR STRIP=$STRIP CROSS_COMPILE= HOSTCC=gcc EXTRA_CFLAGS="-fPIC -O2" busybox_unstripped > build.log 2>&1; then ok=1; break; fi
  bad=$(grep -oE '^[a-z_]+/[a-z0-9_/-]+\.c:[0-9]+:[0-9]+: error' build.log | cut -d: -f1 | sort -u)
  [ -n "$bad" ] || { echo "busybox: link/other failure"; tail -60 build.log; exit 1; }
  changed=0
  for f in $bad; do
    case $f in shell/hush.c) sed -i 's/^CONFIG_\([A-Z_]*HUSH[A-Z_]*\)=y/# CONFIG_\1 is not set/' .config; echo "busybox round $round: off hush (ash stays)"; changed=1; continue;; esac
    case $f in libbb/*|archival/libarchive/*|shell/*) echo "busybox: core file fails: $f"; grep -A3 "^$f" build.log | head -20; continue;; esac
    n=$(basename $f .c | tr 'a-z-' 'A-Z_')
    if grep -q "^CONFIG_$n=y" .config; then sed -i "s/^CONFIG_$n=y/# CONFIG_$n is not set/" .config; echo "busybox round $round: off $n ($f)"; changed=1
    else echo "busybox: no config for $f"; grep -A3 "^$f" build.log | head -12; fi
  done
  [ $changed = 1 ] || { tail -80 build.log; exit 1; }
  set +o pipefail; yes "" | make oldconfig >/dev/null; set -o pipefail
done
[ $ok = 1 ] || { echo "busybox: still failing after 25 rounds"; tail -60 build.log; exit 1; }
grep -E "^# CONFIG_[A-Z_0-9]+ is not set" .config | wc -l
grep -q "^CONFIG_FEATURE_SUID=y" .config && { echo "FEATURE_SUID still on"; exit 1; } || echo "FEATURE_SUID off"
bridge
BIOBJ=$(find . -mindepth 2 -maxdepth 2 -name built-in.o | sort)
BLIBS=$(find . -name lib.a | sort)
$CC $LDSO -o $OUT/libbusybox_engine.so -Wl,-soname,libbusybox_engine.so $WORK/bridge.o $BIOBJ -Wl,--start-group $BLIBS -Wl,--end-group -lm -llog -ldl
$STRIP --strip-unneeded $OUT/libbusybox_engine.so
check_so $OUT/libbusybox_engine.so
cp LICENSE $OUT/busybox-LICENSE
echo "$BB_VER" > $OUT/busybox.version
