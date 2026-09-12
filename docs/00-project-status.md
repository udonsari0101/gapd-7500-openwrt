# Project status

Updated: 2026-09-12 (Asia/Seoul)

## Current phase

Duplicate-subnet routing and all four physical transition tests are complete.
The stock web/security surface, actual 1.06.08 runtime, physical MTD layout,
U-Boot access gate, and LiBwrt initramfs have been analyzed. Approved
APPSBLENV gate/reboot experiments were performed with rollback. The exact
console-ready UART trigger reached the U-Boot prompt. LAN2, bounded host ping,
hash-pinned TFTP, and a RAM-only LibWrt boot passed. A GAPD-7500 port was then
applied to pinned official OpenWrt, built successfully, and host-verified. The
official initramfs was then transferred, CRC-verified in U-Boot, and RAM-booted
successfully on the actual router. On 2026-09-12, the exact factory UBI was
written to the inactive physical rootfs slot, manually booted and verified,
then selected through both redundant BOOTCONFIG copies. Two later unattended
software reboots selected `Boot act=1` and reached persistent OpenWrt without
UART input.

## Verified host and network

- [VERIFIED-DEVICE] The current PowerShell session is elevated only for
  reversible ActiveStore address/route cleanup and verification.
- [VERIFIED-DEVICE] Wi-Fi owns the only IPv4
  default route through the unrelated Wi-Fi router.
- [VERIFIED-DEVICE] The Realtek USB adapter is `Ethernet 12`, with
  `192.168.219.100/24` and no default route.
- [VERIFIED-AUTOMATION] Only `192.168.219.1/32` is directed
  over Ethernet after adapter, address, Wi-Fi default-route, and target L2
  checks pass. It currently reaches OpenWrt.
- [VERIFIED-DEVICE] A 2026-09-09 status snapshot passed `1.1.1.1:443` through
  Wi-Fi and target TCP 80 through Ethernet.
- [VERIFIED-DEVICE] The 2026-09-09 05:49 KST post-build check again found one
  Wi-Fi default route, no stale stock `/32`, a 1 Gbit/s wired link at
  `192.168.1.100/24`, Internet TCP 443, and LibWrt HTTP 200 plus TCP 22.
- [VERIFIED-DEVICE] Disconnect removes the ActiveStore `/32`; reconnect waits
  for link, exact IPv4, and L2 readiness before restoring it.
- [VERIFIED-DEVICE] The scheduled watcher has startup/logon triggers. A full
  Windows reboot test remains pending.

## Actual-router findings

- [VERIFIED-DEVICE] The stock runtime captured before the RAM boot was
  `1.06.08 (2024-04-08 11:22:43)`. Its BusyBox, `dvbox`, and `lgu_topaz` hashes
  match neither the historical dump nor the local 1.07.16 update candidate.
- [VERIFIED-DEVICE] The router currently runs official-tree OpenWrt SNAPSHOT
  `r0-9f62ca8` / Linux 6.18.44 from NAND with SquashFS and UBIFS overlay.
- [VERIFIED-DEVICE] Normal and hidden web login transitions succeeded, and the
  hidden pages were mapped without invoking the stock firmware upload action.
- [VERIFIED-DEVICE] Public EJ chaining, offline CAPTCHA inversion,
  deterministic hidden authentication, arbitrary first-token file disclosure,
  a memory-corruption/service-denial condition, and factory-test command
  injection are confirmed. Long-token file reads will not be repeated.
- [VERIFIED-DEVICE] Factory-test command injection executes bounded commands as
  root. It was limited to `/tmp`, read-only inventory, host-side backups, and
  reversible runtime firewall checks.
- [VERIFIED-DEVICE] A source-restricted Dropbear rule was opened and removed.
  TCP 22 is again unreachable; no password guessing or persistent key install
  occurred.
- [VERIFIED-DEVICE] Kernel, DT, `/proc/mtd`, UBI, mounts, RAM, active mtd16
  rootfs, and boot environment were captured from the actual router.
- [VERIFIED-DEVICE] All 20 physical MTD devices were streamed to the host.
  mtd0-18 have exact sizes and matching live/PC SHA-256. Mounted qcalog/iotpg
  changed mtd19 during collection, so USER is marked non-consistent.
- [VERIFIED-DEVICE] Router `/tmp` scripts and result chunks were removed. TCP
  22 is closed and no Ncat process remains.

The earlier APPSBLENV experiments were rolled back. The persistent installation
later saved `bootdelay_=1` as a recovery gate, wrote the inactive rootfs slot,
and changed both BOOTCONFIG copies. Bootloader and ART/calibration were not
written; the original stock rootfs hash remains preserved.

## OpenWrt and RAM-boot readiness

- [VERIFIED-REFERENCE] The historical local `.bin` is raw SquashFS, not UBI or
  a complete signed FIMS package. Neither it nor LiBwrt factory/sysupgrade
  output is valid stock-updater input.
- [VERIFIED-SOURCE] LiBwrt commit `0fd5daca...` provides the GAPD target, but
  lacks explicit RTL8367RB topology and GAPD-specific A/B sysupgrade.
- [VERIFIED-DEVICE] The RAM boot exposes SMEM names `0:art` and
  `0:appsblenv`. The earlier uppercase local patch is wrong for OpenWrt and
  caused the ath11k caldata request to fail. Its sysupgrade refusal remains the
  required safety behavior.
- [VERIFIED-BUILD] The initramfs ITB is 18,129,564 bytes with SHA-256
  `9ca834d6d2d520f8b03039be55fb5b8f1bf7d4f197992d931aec10637ac0e657`.
- [VERIFIED-HOST] FIT config `config@cp03-c1`, load/entry, gzip expansion range,
  and kernel/DTB CRC32/SHA-1 values passed. Loading at the stock
  `0x44000000` buffer does not overlap the kernel destination.
- [VERIFIED-DEVICE] The stock Linux kernel has no usable kexec route.
- [VERIFIED-DEVICE] Actual APPSBL is U-Boot 2016.01-svn420 with Secure Boot Off,
  TFTP, `bootm`, and `crc32`. Live commands proved that `hash` and `iminfo` are
  absent despite earlier static indications. The `defenv` one-time marker or a
  `bootdelay_` variable bypasses `boot access disabled`.
- [VERIFIED-DEVICE] `bootdelay_=1`, used by the stock `dwlee` script, bypassed
  the console lock. One SPACE sent only after the exact console-ready signature
  reached the actual `IPQ6018#` prompt.
- [VERIFIED-DEVICE] During the earlier RAM-only experiment, `bootdelay_` was
  removed and temporary network values were not saved. The persistent install
  later saved `bootdelay_=1` as its recovery gate.
- [VERIFIED-DEVICE] LAN1 had no U-Boot carrier. LAN2 brought PHY1 up at
  1 Gbit/s full duplex and the Windows USB adapter up at 1 Gbit/s.
- [VERIFIED-DEVICE] A private ActiveStore neighbor was required because Windows
  observed valid U-Boot ARP replies but did not initially accept them through
  `SendARP`. After the reversible neighbor entry, U-Boot ping passed with one
  captured echo request and one reply.
- [VERIFIED-DEVICE] One TFTP request loaded 18,129,564 bytes at `0x44000000`.
  U-Boot reported `fileaddr=44000000`, `filesize=114a29c`, and whole-range
  CRC32 `724a9e30`, matching the host file.
- [VERIFIED-HOST] The one-shot server pinned the requested name, client, byte
  count, and SHA-256. It reported one complete transfer and then exited. The
  source-restricted UDP firewall rule was removed; no listener remains.
- [VERIFIED-BUILD] Official OpenWrt commit `9f62ca8f...` plus the tracked GAPD
  port patch builds Linux 6.18.44 and a 14,802,824-byte initramfs with SHA-256
  `7618dda664005f2360bc786565bf8d4e69a2f5532739df39a0817515607f5400`.
- [VERIFIED-HOST] The official image contains the 65,640-byte GAPD ath11k BDF
  with SHA-256 `7d283ff5...4421fbb`; DTB port mappings, lowercase `0:art` and
  `0:appsblenv`, LED/MAC rules, and two-stage sysupgrade refusal are present.
- [VERIFIED-HOST] The official FIT selects `config@cp03-c1`; its kernel and DTB
  hashes match. The uncompressed kernel ends at `0x42675008`, while the
  `0x44000000` transfer range ends at `0x44e1df88`, so the ranges do not
  overlap and remain below the bootloader-reserved boundary.
- [VERIFIED-DEVICE] U-Boot received exactly 14,802,824 bytes at `0x44000000`,
  reported `filesize=e1df88`, and computed whole-file CRC32 `51f3304e`, matching
  the host artifact before `bootm` was sent.
- [VERIFIED-DEVICE] The official image booted as model `LG-GAPD-7500`, target
  `qualcommax/ipq60xx`, with `rootfs_type=initramfs` and `/` on tmpfs. LAN1,
  HTTP, and SSH are reachable at `192.168.1.1`.
- [VERIFIED-DEVICE] ath11k loaded two PHYs and the expected firmware without a
  failed/error kernel log. Both radios report up; no AP/client interface is
  configured in this initramfs, so over-the-air traffic remains untested.

The approved `bootm` passed FIT kernel/DTB CRC32 and SHA-1 checks and started
LibWrt 25.12.2 / Linux 6.12.103. `rootfs_type=initramfs`, `/` is tmpfs, LuCI
returns HTTP 200, TCP 22 is open, and the connected physical port appears as
`lan1` at 1 Gbit/s. ath11k is not operational because caldata was not created.
No flash, MTD/UBI, calibration, boot-selection, or saved-environment write
accompanied the RAM boot. See
[`08-backup-and-recovery.md`](08-backup-and-recovery.md) and
[`11-hidden-web-and-security-audit.md`](11-hidden-web-and-security-audit.md).

The official image has now passed both RAM boot and persistent NAND boot.
Power/2.4G/5G LED control and AP-interface creation were also exercised and
restored. USB devices, WAN/LAN2 traffic, physical buttons, over-the-air Wi-Fi,
and the unresolved RTL8367RB topology still require targeted hardware tests.
The installed build continues to reject generic sysupgrade. See
[`13-persistent-openwrt-install.md`](13-persistent-openwrt-install.md) and
[`14-custom-build-test-report.md`](14-custom-build-test-report.md).
