# GAPD-7500 persistent-install helpers

These helpers record the guarded procedure tested on the actual 1.06.08
GAPD-7500 on 2026-09-12. They are pinned to that device's partition hashes and
the exact official-tree OpenWrt build recorded in
[`../../docs/13-persistent-openwrt-install.md`](../../docs/13-persistent-openwrt-install.md).
They are not generic upgrade scripts.

- `install-inactive-openwrt.sh` writes only the verified inactive rootfs slot
  while running the official initramfs.
- `prepare-gapd-slot1-bootconfig.ps1` creates a 512 KiB slot-1 BOOTCONFIG from
  two matching slot-0 backups and proves that only byte offset 148 changed.
- `commit-bootconfig-slot1.sh` is run only after a manual boot of the new slot;
  it writes BOOTCONFIG1 first and BOOTCONFIG second, verifying each readback.
- `rollback-to-stock-slot.sh` restores the original BOOTCONFIG selection. Its
  checks were reviewed, but the rollback write itself was not executed because
  the installed OpenWrt boot succeeded.

Every mutating script requires an explicit arming argument. Keep the raw
partition backups outside Git, never substitute a sysupgrade image for the
factory UBI, and do not use these scripts on another firmware version or unit
without replacing every pinned measurement.
