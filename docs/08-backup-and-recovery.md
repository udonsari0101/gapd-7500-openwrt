# Backup and recovery gate

Updated: 2026-09-12 (Asia/Seoul)

The inactive-slot installation is complete. The original stock slot and raw
BOOTCONFIG backups are preserved, the UART/TFTP initramfs path is proven, and a
guarded stock-slot rollback script is prepared. The final rollback write and
stock reboot have not been executed.

## Current facts

- [VERIFIED-DEVICE] The boot medium is 128 MiB SLC NAND.
- [VERIFIED-DEVICE] Secure Boot was reported Off by the observed boot chain.
- [VERIFIED-DEVICE] The normal path prints `boot access disabled`; the approved
  gated path reached U-Boot and booted both the historical LibWrt initramfs and
  the official-tree OpenWrt initramfs. The router now runs the official build
  persistently from the previously inactive slot.
- [VERIFIED-DEVICE] The device now boots persistent OpenWrt with `Boot act=1`.
- [VERIFIED-DEVICE] Stock firmware version 1.06.08 boots normally.
- [VERIFIED-DEVICE] Current `/proc/mtd` exposes physical `mtd0` through `mtd19`
  with a total size of 128 MiB, including `rootfs`, `rootfs_1`, both
  BOOTCONFIG copies, APPSBLENV, APPSBL copies, ART, DVCFG, and USER.
- [VERIFIED-DEVICE] After the slot switch, the bootloader/SMEM view presents
  installed OpenWrt as `mtd16/rootfs`; the preserved physical stock slot is
  presented as `mtd17/rootfs_1` and retains its original SHA-256.
- [VERIFIED-DEVICE] Actual APPSBL analysis explains the lock: `bootdelay_`
  bypasses it. `bootdelay_=1` is currently retained as the recovery gate.
- [VERIFIED-DEVICE] The stock Linux kernel has no usable kexec path.
- [VERIFIED-DEVICE] UART plus TFTP loaded and booted the pinned initramfs.
- [UNVERIFIED] Reset-button recovery, USB recovery, automatic A/B rollback, and
  the prepared stock-slot rollback write have not been demonstrated.

`Boot act=0` alone is insufficient to choose a partition to overwrite. Its
meaning must be correlated with `/proc/boot_info`, the mounted UBI device,
kernel command line, and a controlled slot-change observation.

## Completed read-only inventory

The following were collected from the actual 1.06.08 router through bounded
root command execution. Raw records remain ignored because they contain device
identity values.

```sh
cat /proc/mtd
cat /proc/cmdline
cat /proc/cpuinfo
dmesg
mount
df -h
ip addr
ip link
find /proc/boot_info -maxdepth 3 -type f -print
cat /sys/class/ubi/ubi*/mtd_num
ubinfo -a
```

Secrets, MAC addresses, serial numbers, and calibration content remain outside
Git. Only sanitized command output and hashes may be committed.

The actual DT model is IPQ6018/AP-CP03-C1 with 512 MiB physical RAM. The stock
FIT uses `config@cp03-c1`, and the active kernel volume was extracted from the
verified mtd16 backup for offline comparison.

## Backup result

The exact names and MTD indices must come from the current device. The minimum
set includes:

- complete raw NAND with OOB/ECC information where the chosen tool supports it;
- `0:SBL1`, `0:MIBIB`;
- `0:BOOTCONFIG`, `0:BOOTCONFIG1`;
- both QSEE, DEVCFG, RPM, and CDT copies;
- `0:APPSBLENV`, `0:APPSBL`, `0:APPSBL_1`;
- `0:ART` and every Wi-Fi BDF/calibration source;
- `rootfs`, `rootfs_1`, and every UBI volume;
- device configuration/user partitions.

At 2026-09-09, all 20 physical MTD character devices were streamed directly to
an ignored host directory. The set totals 134,217,728 bytes.

- `mtd0` through `mtd18`: exact `/proc/mtd` size, successful TFTP completion,
  and matching router-side/PC SHA-256. This includes both rootfs slots,
  bootloader/configuration copies, APPSBLENV, and ART.
- `mtd19 USER`: exact-size successful TFTP capture, but not accepted as a
  consistent backup. Its qcalog/iotpg volumes were mounted read-write and a
  second live hash confirmed that it changed during collection.
- The private manifest records every filename, size, SHA-256, and acceptance
  state without placing raw partitions or identifiers in Git.

These are MTD character-device reads, not OOB-aware `nanddump` images. A second
host-side copy, OOB/ECC-aware full-NAND dump, and restoration test remain
mandatory before any flash installation. They are not required merely to
inspect or attempt a no-write RAM boot, but their absence must remain visible.

## RAM-boot evidence and next-image gate

- [PASS] The 18,129,564-byte initramfs FIT structure and its outer SHA-256 plus
  internal kernel/DTB CRC32 and SHA-1 values were independently verified.
- [PASS] Load `0x41000000`, entry `0x41000000`, uncompressed end `0x42930008`,
  and stock TFTP buffer `0x44000000-0x4514a29c` do not overlap and lie in the
  actual RAM map.
- [PASS] Wi-Fi Internet and the wired `/32` route remain separate. On LAN2,
  the watcher reports L2 success and U-Boot-to-host ping passed.
- [PASS] The local GAPD build blocks sysupgrade and the host TFTP server pins
  exact size, SHA-256, requested name, source address, and client address.
- [PASS-ROLLED-BACK] The one-time APPSBLENV marker and procd software reboot
  were tested on the actual router. The marker suppressed the lock message,
  stock boot completed, and the marker was then deleted and verified absent.
- [PASS] This U-Boot emits no autoboot prompt, but a single SPACE sent after
  the exact console-ready signature reached `IPQ6018#`.
- [PASS-HISTORICAL] During the earlier RAM-only experiment, `bootdelay_` was
  removed in U-Boot RAM and `saveenv` persisted its deletion. The persistent
  install later saved `bootdelay_=1` as its recovery gate.
- [PASS] Router RX, LAN2 PHY1, Windows link, bidirectional ARP, and bounded ping
  were proven in one live U-Boot session.

The approved RAM boot passed FIT hashes and reached LibWrt init complete with
`/` on tmpfs. No stock rootfs or UBI volume is mounted. The pre-boot static
neighbor and `192.168.219.1/32` were removed when LibWrt changed to
`192.168.1.1`; Wi-Fi again owns the original gateway route. A private rollback
state covers the remaining temporary Windows address and original DHCP state.
No flash write occurred.

The new official OpenWrt candidate passes the same host-side gates:

- [PASS-HOST] Exact size 14,802,824 bytes and SHA-256
  `7618dda664005f2360bc786565bf8d4e69a2f5532739df39a0817515607f5400`.
- [PASS-HOST] FIT kernel/DTB CRC32 and SHA-1 values independently recomputed.
- [PASS-HOST] Load/entry `0x41000000`, uncompressed end `0x42675008`, and
  transfer range `0x44000000-0x44e1df88` do not overlap and remain below
  `0x4a100000`.
- [PASS-HOST] The assembled root filesystem contains the public GAPD BDF with
  the expected SHA-256, lowercase `0:art`, and two-stage sysupgrade refusal.
- [PASS-DEVICE] U-Boot transferred 14,802,824 bytes, reported
  `fileaddr=44000000` / `filesize=e1df88`, and matched host CRC32 `51f3304e`.
- [PASS-DEVICE] `bootm` reached OpenWrt SNAPSHOT `r0-9f62ca8` / Linux 6.18.44
  with `rootfs_type=initramfs`, `/` on tmpfs, LAN1, HTTP/SSH, and two ath11k
  PHYs. No kernel failed/error line was observed.
- [PENDING-DEVICE] USB, LEDs, WAN/LAN2 traffic, over-the-air Wi-Fi traffic, and
  RTL8367RB behavior remain unverified.

## Requirements for any future flash write

- all mandatory backups accepted and restored on external tooling or a spare
  device, where feasible;
- current active/inactive slot mapping verified rather than inferred;
- exact writer, target MTD/UBI object, erase geometry, and expected post-write
  hashes documented;
- boot-selection change and rollback trigger understood;
- ART/calibration and bootloader partitions excluded from the write plan;
- a recovery method independent of the partition being changed;
- explicit user authorization for the exact write command.

The device/hash/slot gates were applied to the completed inactive-slot
installation, but an OOB-aware dump, external-programmer restore, and executed
stock rollback were not available. The user explicitly authorized proceeding
with that residual risk. These missing items remain mandatory evidence before
treating recovery as fully verified, and the 2026-09-12 authorization does not
authorize later writes. See `13-persistent-openwrt-install.md`.

## Worst-case recovery

An external NAND programmer may become the only recovery method if both rootfs
slots or boot configuration are damaged while U-Boot remains locked. That path
requires board-level identification, safe voltage isolation, correct NAND/OOB
handling, and two matching full dumps before desoldering or in-circuit writes.
It has not been prepared or authorized.
