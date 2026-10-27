#!/bin/bash
# Build JioRouter AX6000 JIDU6J11 (6411/6111) firmware v8.
#   VARIANT=unifi ./build.sh   -> wired AP with openUF (UniFi), Tailscale inside ROM
#   VARIANT=stock ./build.sh   -> plain OpenWrt router + the same hardening
# Optional: CHECK_ONLY=1 stops after 'make defconfig' (quick sanity check).
set -euo pipefail

VARIANT="${VARIANT:-unifi}"
VERSION="${VERSION:-v1.0.1}"
case "$VARIANT" in unifi|stock) ;; *) echo "VARIANT must be unifi or stock" >&2; exit 1 ;; esac

HERE="$(cd "$(dirname "$0")" && pwd)"
PIN="$(cat "$HERE/openwrt.pin")"
WORK="${WORK:-$HERE/work-$VARIANT}"
OUT="$HERE/out/$VARIANT"

echo "==> OpenWrt main @ $PIN + $(ls "$HERE"/patches/*.patch | wc -l) JIDU6J11 patches, variant $VARIANT"
rm -rf "$WORK"; mkdir -p "$WORK"
git clone --filter=blob:none https://github.com/openwrt/openwrt.git "$WORK/openwrt"
cd "$WORK/openwrt"
git checkout -q "$PIN"
git -c user.name=v8-build -c user.email=v8@build am -q --3way "$HERE"/patches/*.patch
git log --oneline -7
grep -h '^LINUX_VERSION-6.18' target/linux/generic/kernel-6.18

./scripts/feeds update -a
./scripts/feeds install -a

cat "$HERE/configs/common.config" "$HERE/configs/$VARIANT.config" > .config
make defconfig

# Fail loudly if anything we rely on was dropped by defconfig.
need() { grep -q "^$1\$" .config || { echo "MISSING after defconfig: $1" >&2; exit 1; }; }
need 'CONFIG_TARGET_DEVICE_qualcommbe_ipq95xx_DEVICE_jiorouter_ax6000-jidu6j11-6411=y'
need 'CONFIG_PACKAGE_kmod-nft-bridge=y'
need 'CONFIG_PACKAGE_kmod-sched-act-police=y'
need 'CONFIG_PACKAGE_luci-ssl=y'
need 'CONFIG_PACKAGE_wpad-mbedtls=y'
need 'CONFIG_PACKAGE_tailscale=y'
if [ "$VARIANT" = unifi ]; then
	for p in lua lua-cjson luasocket lua-openssl luabitop libuci-lua tc-tiny; do need "CONFIG_PACKAGE_$p=y"; done
fi
[ "${CHECK_ONLY:-0}" = 1 ] && { echo "==> CHECK_ONLY: defconfig OK"; exit 0; }

# Image overlay: common hardening + the variant's files.
rm -rf files; mkdir -p files
cp -a "$HERE/files/common/." files/
cp -a "$HERE/files/$VARIANT/." files/
find files -name .keep -delete

if [ "$VARIANT" = unifi ]; then
	mkdir -p files/usr/bin files/usr/sbin
	ln -sf /opt/openuf/hook/syswrapper.sh files/usr/bin/syswrapper.sh
	ln -sf /opt/openuf/hook/openuf-cli.sh files/usr/bin/openuf
	ln -sf /opt/openuf/hook/openuf-convert.sh files/usr/sbin/openuf-convert
	ln -sf /opt/openuf/hook/openuf-deps.sh files/usr/sbin/openuf-deps
	chmod 755 files/opt/openuf/hook/*.sh files/opt/openuf/rrb/*.uc 2>/dev/null || true`n`tchmod 755 files/usr/lib/openuf/hook/*.sh files/usr/lib/openuf/rrb/*.uc 2>/dev/null || true
fi
chmod 755 files/etc/init.d/* files/etc/uci-defaults/* files/usr/bin/* files/usr/sbin/* 2>/dev/null || true

make download -j8 || make download -j1 V=s
make -j"$(nproc)" || make -j1 V=s

T=bin/targets/qualcommbe/ipq95xx
rm -rf "$OUT"; mkdir -p "$OUT"
cp -a $T/*jidu6j11-6411* $T/*jidu6j11-6111* "$OUT"/ 2>/dev/null || true
cp -a $T/*.manifest $T/sha256sums $T/*.buildinfo $T/profiles.json "$OUT"/ 2>/dev/null || true
tar -C $T -czf "$OUT/packages-$VARIANT.tar.gz" packages
for f in "$OUT"/*sysupgrade*.bin; do
	b=$(basename "$f")
	case "$b" in
		*6411*) dev="jidu6j11" ;;
		*6111*) dev="jidu6j11-6111" ;;
		*) dev="jidu6j11" ;;
	esac
	mv "$f" "$OUT/openwrt-qualcommbe-ipq95xx-$dev-$VERSION-$VARIANT.bin"
done
( cd "$OUT" && sha256sum *.bin *.itb 2>/dev/null > SHA256SUMS-$VERSION-$VARIANT.txt || true )
ls -l "$OUT"
