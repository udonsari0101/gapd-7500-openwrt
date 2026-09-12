#!/bin/sh
set -e

. /lib/functions.sh
. /lib/functions/system.sh

IMAGE=${IMAGE:-/tmp/bootconfig-slot0-original.bin}
EXPECTED_SLOT0_SHA=5a0a92472ecef64b32621ce5503e7e7f45d4f1e9792e649b6d8287511c50e6f3
EXPECTED_SLOT1_SHA=629632b6e64c9db9d850fa7bf2973b1b8413cae0f01617fd6b212ad7b89348ad
EXPECTED_STOCK_SHA=4020f3c4d5b7169bd1e7ad3e56300c9d5aaa464a0f4c6abaefc94baf4475342f

fail() { echo "ROLLBACK_FAIL: $*" >&2; exit 1; }

[ "${1:-}" = "--arm-stock-slot-rollback" ] || fail "arming switch absent"
[ "$(board_name)" = "lg,gapd-7500" ] || fail "unexpected board"
[ "$(ubus call system board | jsonfilter -e '@.rootfs_type')" = "squashfs" ] || fail "root is not persistent squashfs"
[ "$(wc -c < "$IMAGE")" = "524288" ] || fail "original BOOTCONFIG size mismatch"
[ "$(sha256sum "$IMAGE" | cut -d' ' -f1)" = "$EXPECTED_SLOT0_SHA" ] || fail "original BOOTCONFIG mismatch"
[ "$(sha256sum /dev/mtd2ro | cut -d' ' -f1)" = "$EXPECTED_SLOT1_SHA" ] || fail "BOOTCONFIG is not slot 1"
[ "$(sha256sum /dev/mtd3ro | cut -d' ' -f1)" = "$EXPECTED_SLOT1_SHA" ] || fail "BOOTCONFIG1 is not slot 1"

# With Boot act=1, SMEM presents the preserved physical stock slot as mtd17.
[ "$(sha256sum /dev/mtd17ro | cut -d' ' -f1)" = "$EXPECTED_STOCK_SHA" ] || fail "preserved stock slot mismatch"
grep -a -q 'bootdelay_=1' /dev/mtd12ro || fail "UART recovery gate missing"

mtd write "$IMAGE" /dev/mtd3
sync
[ "$(sha256sum /dev/mtd3ro | cut -d' ' -f1)" = "$EXPECTED_SLOT0_SHA" ] || fail "BOOTCONFIG1 rollback readback mismatch"
mtd write "$IMAGE" /dev/mtd2
sync
[ "$(sha256sum /dev/mtd2ro | cut -d' ' -f1)" = "$EXPECTED_SLOT0_SHA" ] || fail "BOOTCONFIG rollback readback mismatch"

echo "stock_slot_selection_restored=true"
echo "reboot_required=true"
