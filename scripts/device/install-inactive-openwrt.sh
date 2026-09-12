#!/bin/sh
set -e

. /lib/functions.sh
. /lib/functions/system.sh

IMAGE=${IMAGE:-/tmp/openwrt-gapd-7500-factory.ubi}
CONFIG=/tmp/fw_env.gapd-install
EXPECTED_IMAGE_BYTES=13762560
EXPECTED_IMAGE_SHA=fe306d8fab0eb96c47649dadd3ee9fb731bdbbbcb587a45a5a8f00722edb892b
EXPECTED_MTD16_SHA=4020f3c4d5b7169bd1e7ad3e56300c9d5aaa464a0f4c6abaefc94baf4475342f
EXPECTED_MTD17_SHA=f4c7325fad04e63a2fd63dab57d82af8f20acff9e01c660a0b780c8f4f1445d6
EXPECTED_BOOTCONFIG_SHA=5a0a92472ecef64b32621ce5503e7e7f45d4f1e9792e649b6d8287511c50e6f3
EXPECTED_KERNEL_SHA=6fa0d471dbfa3a2755ec672f2d1c54128a54b0ab0139ef3b29cf1a4b9c99d5cf
EXPECTED_ROOTFS_SHA=bcca9159a2a08c8cfe48731f194e91f6aa0973641c13bf6a8300814dd644a460

fail() { echo "INSTALL_FAIL: $*" >&2; exit 1; }

[ "${1:-}" = "--arm-inactive-mtd17-write" ] || fail "arming switch absent"
[ "$(board_name)" = "lg,gapd-7500" ] || fail "unexpected board"
[ "$(ubus call system board | jsonfilter -e '@.rootfs_type')" = "initramfs" ] || fail "root is not initramfs"
grep -q '^mtd16: 02620000 00020000 "rootfs"$' /proc/mtd || fail "mtd16 map mismatch"
grep -q '^mtd17: 02620000 00020000 "rootfs_1"$' /proc/mtd || fail "mtd17 map mismatch"

for path in /sys/class/ubi/ubi[0-9]*/mtd_num; do
	[ -e "$path" ] || continue
	[ "$(cat "$path")" != "17" ] || fail "mtd17 is already UBI-attached"
done

[ "$(wc -c < "$IMAGE")" = "$EXPECTED_IMAGE_BYTES" ] || fail "image size mismatch"
[ "$(sha256sum "$IMAGE" | cut -d' ' -f1)" = "$EXPECTED_IMAGE_SHA" ] || fail "image SHA-256 mismatch"
[ "$(sha256sum /dev/mtd16ro | cut -d' ' -f1)" = "$EXPECTED_MTD16_SHA" ] || fail "active mtd16 mismatch"
[ "$(sha256sum /dev/mtd17ro | cut -d' ' -f1)" = "$EXPECTED_MTD17_SHA" ] || fail "inactive mtd17 mismatch"
[ "$(sha256sum /dev/mtd2ro | cut -d' ' -f1)" = "$EXPECTED_BOOTCONFIG_SHA" ] || fail "BOOTCONFIG mismatch"
[ "$(sha256sum /dev/mtd3ro | cut -d' ' -f1)" = "$EXPECTED_BOOTCONFIG_SHA" ] || fail "BOOTCONFIG1 mismatch"

printf '%s\n' '/dev/mtd12 0x0 0x40000 0x00020000 2' > "$CONFIG"
gate="$(fw_printenv -c "$CONFIG" -n bootdelay_ 2>/dev/null || true)"
[ -z "$gate" ] || [ "$gate" = "1" ] || fail "unexpected bootdelay_ value"
if [ "$gate" != "1" ]; then fw_setenv -c "$CONFIG" bootdelay_ 1; fi
[ "$(fw_printenv -c "$CONFIG" -n bootdelay_)" = "1" ] || fail "recovery gate readback failed"

ubiformat /dev/mtd17 -y -f "$IMAGE"
sync
ubiattach -m 17

ubinum=""
for path in /sys/class/ubi/ubi[0-9]*/mtd_num; do
	[ -e "$path" ] || continue
	if [ "$(cat "$path")" = "17" ]; then
		ubinum="${path#/sys/class/ubi/ubi}"
		ubinum="${ubinum%/mtd_num}"
		break
	fi
done
[ -n "$ubinum" ] || fail "written mtd17 did not attach"

kernel_sha="$(sha256sum "/dev/ubi${ubinum}_0" | cut -d' ' -f1)"
rootfs_sha="$(sha256sum "/dev/ubi${ubinum}_1" | cut -d' ' -f1)"
[ "$kernel_sha" = "$EXPECTED_KERNEL_SHA" ] || fail "kernel volume mismatch"
[ "$rootfs_sha" = "$EXPECTED_ROOTFS_SHA" ] || fail "rootfs volume mismatch"
ubidetach -m 17

[ "$(sha256sum /dev/mtd16ro | cut -d' ' -f1)" = "$EXPECTED_MTD16_SHA" ] || fail "active mtd16 changed"
[ "$(sha256sum /dev/mtd2ro | cut -d' ' -f1)" = "$EXPECTED_BOOTCONFIG_SHA" ] || fail "BOOTCONFIG changed"
[ "$(sha256sum /dev/mtd3ro | cut -d' ' -f1)" = "$EXPECTED_BOOTCONFIG_SHA" ] || fail "BOOTCONFIG1 changed"

echo "inactive_install_verified=true"
echo "written_target=mtd17/rootfs_1"
echo "active_stock_mtd16_preserved=true"
echo "bootconfig_unchanged=true"
echo "recovery_gate_present=true"
