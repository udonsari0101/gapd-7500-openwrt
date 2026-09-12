# Persistent OpenWrt installation on the actual GAPD-7500

Updated: 2026-09-12 (Asia/Seoul)

## Outcome

The owner explicitly authorized persistent installation. The exact official
OpenWrt factory UBI was written only to the inactive physical rootfs slot,
booted once without changing the active-slot flag, and selected permanently
only after that boot passed. Two later RX-only UART captures showed unattended
`Boot act=1` boots reaching OpenWrt.

The running system is OpenWrt SNAPSHOT `r0-9f62ca8`, Linux 6.18.44, with a
read-only SquashFS root and writable UBIFS overlay. The saved LAN address is
`192.168.219.1/24`. Windows retains Wi-Fi as its only default route and sends
only `192.168.219.1/32` over Ethernet 12.

## Pinned artifacts

| Artifact | Bytes | SHA-256 |
|---|---:|---|
| Factory UBI | 13,762,560 | `fe306d8fab0eb96c47649dadd3ee9fb731bdbbbcb587a45a5a8f00722edb892b` |
| Kernel volume, padded | 5,840,896 | `6fa0d471dbfa3a2755ec672f2d1c54128a54b0ab0139ef3b29cf1a4b9c99d5cf` |
| Rootfs volume, padded | 7,237,632 | `bcca9159a2a08c8cfe48731f194e91f6aa0973641c13bf6a8300814dd644a460` |
| Original BOOTCONFIG | 524,288 | `5a0a92472ecef64b32621ce5503e7e7f45d4f1e9792e649b6d8287511c50e6f3` |
| Slot-1 BOOTCONFIG | 524,288 | `629632b6e64c9db9d850fa7bf2973b1b8413cae0f01617fd6b212ad7b89348ad` |

The slot-1 BOOTCONFIG differs from the verified original at exactly byte offset
148: the little-endian `rootfs.primaryboot` value changed from 0 to 1. Start
magic `a0 a1 a2 a3`, eight entries, the `rootfs` entry, and end magic
`b0 b1 b2 b3` were checked before generation.

## Guarded sequence and evidence

1. Initramfs preflight reconfirmed the board, rootfs type, MTD map, factory UBI
   size/hash, both BOOTCONFIG hashes, and both rootfs-slot hashes.
2. `bootdelay_=1` was saved and read back as the UART recovery gate.
3. `ubiformat` wrote the factory UBI to inactive `mtd17/rootfs_1`. All 305 PEBs
   formatted with zero bad blocks.
4. The written UBI was attached and kernel/rootfs volumes matched the pinned
   hashes; active stock and both BOOTCONFIG copies remained unchanged.
5. U-Boot manually attached the inactive region using the measured
   `0x2620000@0x37a0000` boundary, read the kernel FIT, and matched CRC32
   `2d655ac0`. `bootm 0x44000000#config@cp03-c1` reached init complete with no
   panic.
6. Linux confirmed `rootfs_type=squashfs`, `/rom` on SquashFS, `/overlay` on
   UBIFS, and `ubi0` on pre-switch mtd17.
7. BOOTCONFIG1 was written and read back first, followed by BOOTCONFIG. Both
   matched the slot-1 hash.
8. Two reboots with a receive-only UART logger showed `Boot act=1`, FIT kernel
   and FDT hashes OK, kernel start, and the OpenWrt console. No stop byte or
   manual boot command was sent.
9. The saved LAN configuration survived reboot. The Windows watcher restored
   the Ethernet `/32`; target TCP 80 passed over Ethernet, while Internet TCP
   443 continued over Wi-Fi.

## Active-slot remapping

The Qualcomm SMEM/bootloader path presents the selected physical slot as
`rootfs`. Before the switch, stock was Linux `mtd16/rootfs` and the inactive
slot was `mtd17/rootfs_1`. After `Boot act=1`, installed OpenWrt appears as
Linux `mtd16/rootfs`, while the untouched physical stock slot appears as
`mtd17/rootfs_1`. The latter still matches SHA-256
`4020f3c4d5b7169bd1e7ad3e56300c9d5aaa464a0f4c6abaefc94baf4475342f`.

## Rollback

The original 512 KiB BOOTCONFIG image is stored in the ignored device-backup
directory. From running OpenWrt, `scripts/device/rollback-to-stock-slot.sh`
requires that exact file, both current slot-1 hashes, the preserved stock-slot
hash, and the UART recovery gate. It writes BOOTCONFIG1 first, verifies it, then
writes and verifies BOOTCONFIG. A reboot should then select `Boot act=0` and
the preserved stock image.

The rollback script was not executed because the OpenWrt boot succeeded, so
the final stock reboot remains unverified. If normal OpenWrt cannot start, the
saved `bootdelay_=1` gate and the already-proven UART/TFTP initramfs path are the
recovery route. ART, bootloader, and the preserved stock rootfs must never be
written during rollback.

An electrical power-loss cycle after installation has not been observed. NAND
and both BOOTCONFIG readbacks plus two unattended software reboots prove the
persistent boot selection, but a literal unplug/replug remains a separate
physical validation.

## Immediate operational follow-up

A fresh factory install starts without a root password, so set a new, unique
password before connecting additional clients or a WAN uplink. The current test
unit now has a root password; an actual password-only SSH login was rechecked on
2026-09-13 without storing the password in the repository or test log.

LAN1, LuCI/SSH, firewall rules, wireless PHY/AP creation, and the LED sysfs
control path have since been tested. Wi-Fi beacon/client traffic, WAN/LAN2 data
paths, USB devices, physical button events, a cold power cycle, and an executed
stock rollback remain unverified. See
[`14-custom-build-test-report.md`](14-custom-build-test-report.md).
