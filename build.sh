#!/bin/bash
# Build JioRouter AX6000 JIDU6J11 (6411/6111) firmware v8.
#   VARIANT=stock-fast    -> Recommended daily driver with native adblock-fast (~3MB RAM)
#   VARIANT=stock-adguard -> AdGuard Home variant (requires USB SSD)
#   VARIANT=unifi         -> Wired AP with openUF (UniFi), Tailscale inside ROM
# Optional: CHECK_ONLY=1 stops after 'make defconfig' (quick sanity check).
set -euo pipefail

VARIANT="${VARIANT:-stock-fast}"
VERSION="${VERSION:-v1.0.2}"
case "$VARIANT" in
	unifi|stock-fast|stock-adguard) ;;
	stock) VARIANT="stock-fast" ;;
	*) echo "VARIANT must be stock-fast, stock-adguard, or unifi" >&2; exit 1 ;;
esac

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

# Strip any UTF-8 BOM and Windows CRLF to prevent Makefile "missing separator" errors
cat "$HERE/configs/common.config" "$HERE/configs/$VARIANT.config" | sed -e 's/^\xef\xbb\xbf//' | tr -d '\r' > .config
make defconfig

# Fail loudly if anything we rely on was dropped by defconfig.
need() { grep -q "^$1\$" .config || { echo "MISSING after defconfig: $1" >&2; exit 1; }; }
need 'CONFIG_TARGET_DEVICE_qualcommbe_ipq95xx_DEVICE_jiorouter_ax6000-jidu6j11-6411=y'
need 'CONFIG_PACKAGE_kmod-nft-bridge=y'
need 'CONFIG_PACKAGE_kmod-sched-act-police=y'
need 'CONFIG_PACKAGE_luci-ssl=y'
need 'CONFIG_PACKAGE_wpad-mbedtls=y'
if [ "$VARIANT" = "stock-fast" ] || [ "$VARIANT" = "stock-adguard" ]; then
	[ "$VARIANT" = "stock-adguard" ] && need 'CONFIG_PACKAGE_adguardhome=y'
	[ "$VARIANT" = "stock-fast" ] && need 'CONFIG_PACKAGE_adblock-fast=y'
	[ "$VARIANT" = "stock-fast" ] && need 'CONFIG_PACKAGE_luci-app-adblock-fast=y'
	need 'CONFIG_PACKAGE_kmod-usb-storage=y'
	need 'CONFIG_PACKAGE_kmod-usb-storage-uas=y'
	need 'CONFIG_PACKAGE_kmod-fs-ext4=y'
	need 'CONFIG_PACKAGE_block-mount=y'
	need 'CONFIG_PACKAGE_e2fsprogs=y'
	need 'CONFIG_PACKAGE_kmod-usb-net-rndis=y'
	need 'CONFIG_PACKAGE_mwan3=y'
	need 'CONFIG_PACKAGE_luci-app-mwan3=y'
	need 'CONFIG_PACKAGE_luci-app-samba4=y'
	need 'CONFIG_PACKAGE_luci-app-sqm=y'
	need 'CONFIG_PACKAGE_kmod-nft-offload=y'
fi
if [ "$VARIANT" = unifi ]; then
	need 'CONFIG_PACKAGE_tailscale=y'
	for p in lua lua-cjson luasocket lua-openssl luabitop libuci-lua tc-tiny; do need "CONFIG_PACKAGE_$p=y"; done
fi
[ "${CHECK_ONLY:-0}" = 1 ] && { echo "==> CHECK_ONLY: defconfig OK"; exit 0; }

# Image overlay: common hardening + the variant's files.
rm -rf files; mkdir -p files
cp -a "$HERE/files/common/." files/
if [ "$VARIANT" = "stock-fast" ] || [ "$VARIANT" = "stock-adguard" ]; then
	[ -d "$HERE/files/stock-common" ] && cp -a "$HERE/files/stock-common/." files/
	[ -d "$HERE/files/$VARIANT" ] && cp -a "$HERE/files/$VARIANT/." files/
else
	[ -d "$HERE/files/$VARIANT" ] && cp -a "$HERE/files/$VARIANT/." files/
fi
find files -name .keep -delete
find files -type f -exec sed -i -e 's/^\xef\xbb\xbf//' -e 's/\r$//' {} + 2>/dev/null || true
chmod +x files/etc/uci-defaults/* 2>/dev/null || true
chmod +x files/usr/sbin/* 2>/dev/null || true
chmod +x files/etc/hotplug.d/*/* 2>/dev/null || true
chmod +x files/etc/init.d/* 2>/dev/null || true

if [ "$VARIANT" = unifi ]; then
	mkdir -p files/usr/bin files/usr/sbin
	ln -sf /opt/openuf/hook/syswrapper.sh files/usr/bin/syswrapper.sh
	ln -sf /opt/openuf/hook/openuf-cli.sh files/usr/bin/openuf
	ln -sf /opt/openuf/hook/openuf-convert.sh files/usr/sbin/openuf-convert
	ln -sf /opt/openuf/hook/openuf-deps.sh files/usr/sbin/openuf-deps
	chmod 755 files/opt/openuf/hook/*.sh files/opt/openuf/rrb/*.uc 2>/dev/null || true
	chmod 755 files/usr/lib/openuf/hook/*.sh files/usr/lib/openuf/rrb/*.uc 2>/dev/null || true
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
