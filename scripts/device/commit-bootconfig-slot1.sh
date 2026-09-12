#!/bin/sh
set -e

. /lib/functions.sh
. /lib/functions/system.sh

IMAGE=${IMAGE:-/tmp/bootconfig-slot1.bin}
EXPECTED_OLD_SHA=5a0a92472ecef64b32621ce5503e7e7f45d4f1e9792e649b6d8287511c50e6f3
EXPECTED_NEW_SHA=629632b6e64c9db9d850fa7bf2973b1b8413cae0f01617fd6b212ad7b89348ad
EXPECTED_STOCK_SHA=4020f3c4d5b7169bd1e7ad3e56300c9d5aaa464a0f4c6abaefc94baf4475342f

fail() { echo "SLOT_SWITCH_FAIL: $*" >&2; exit 1; }

[ "${1:-}" = "--arm-bootconfig-slot1" ] || fail "arming switch absent"
[ "$(board_name)" = "lg,gapd-7500" ] || fail "unexpected board"
[ "$(ubus call system board | jsonfilter -e '@.rootfs_type')" = "squashfs" ] || fail "root is not persistent squashfs"
[ "$(cat /sys/class/ubi/ubi0/mtd_num)" = "17" ] || fail "manual boot is not using pre-switch mtd17/rootfs_1"
[ "$(wc -c < "$IMAGE")" = "524288" ] || fail "BOOTCONFIG image size mismatch"
[ "$(sha256sum "$IMAGE" | cut -d' ' -f1)" = "$EXPECTED_NEW_SHA" ] || fail "BOOTCONFIG image mismatch"
[ "$(sha256sum /dev/mtd16ro | cut -d' ' -f1)" = "$EXPECTED_STOCK_SHA" ] || fail "stock mtd16 mismatch"
grep -a -q 'bootdelay_=1' /dev/mtd12ro || fail "UART recovery gate missing"

bootconfig_sha="$(sha256sum /dev/mtd2ro | cut -d' ' -f1)"
bootconfig1_sha="$(sha256sum /dev/mtd3ro | cut -d' ' -f1)"
[ "$bootconfig_sha" = "$EXPECTED_OLD_SHA" ] || fail "BOOTCONFIG is not the original"
[ "$bootconfig1_sha" = "$EXPECTED_OLD_SHA" ] || [ "$bootconfig1_sha" = "$EXPECTED_NEW_SHA" ] || fail "BOOTCONFIG1 is unexpected"

if [ "$bootconfig1_sha" = "$EXPECTED_OLD_SHA" ]; then
	mtd write "$IMAGE" /dev/mtd3
	sync
	[ "$(sha256sum /dev/mtd3ro | cut -d' ' -f1)" = "$EXPECTED_NEW_SHA" ] || fail "BOOTCONFIG1 readback mismatch"
else
	echo "bootconfig1_already_verified=true"
fi

mtd write "$IMAGE" /dev/mtd2
sync
[ "$(sha256sum /dev/mtd2ro | cut -d' ' -f1)" = "$EXPECTED_NEW_SHA" ] || fail "BOOTCONFIG readback mismatch"
[ "$(sha256sum /dev/mtd3ro | cut -d' ' -f1)" = "$EXPECTED_NEW_SHA" ] || fail "BOOTCONFIG1 final mismatch"
[ "$(sha256sum /dev/mtd16ro | cut -d' ' -f1)" = "$EXPECTED_STOCK_SHA" ] || fail "stock mtd16 changed"

echo "slot1_persistent_selection_committed=true"
echo "rollback=restore_original_BOOTCONFIG_to_mtd3_then_mtd2"
