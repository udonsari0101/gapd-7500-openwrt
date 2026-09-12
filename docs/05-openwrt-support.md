# Current OpenWrt and LiBwrt support review

Updated: 2026-09-12 (Asia/Seoul)

## Source snapshots

| Source | Branch | Commit | GAPD-7500 definition |
|---|---|---|---|
| [OpenWrt](https://github.com/openwrt/openwrt) | `main` | `9f62ca8ff14d701928b425b53d0093de80eb0df6` | No upstream definition; tracked local port applies cleanly |
| [LiBwrt](https://github.com/LiBwrt/LibWrt) | `25.12-nss` | `0fd5daca26aed9cab74b4141690deb5d997383f1` | Present under `qualcommax/ipq60xx` |

The public GAPD support originated in [LiBwrt PR
207](https://github.com/LiBwrt/LibWrt/pull/207). It is a fork-specific port, not
an official OpenWrt release target. This repository now carries a reviewed
official-tree port patch rather than claiming that OpenWrt upstream supports
the device.

## LiBwrt device definition

The current `lg_gapd-7500` recipe uses:

- `Device/FitImage` and `Device/UbiFit`;
- `ipq6000-lg-gapd-7500.dts`;
- 128 KiB erase blocks and 2 KiB pages;
- Qualcomm FIT configuration `config@cp03-c1`;
- `ipq-wifi-lg_gapd-7500` and `kmod-switch-rtl8367b` packages;
- normal `factory.ubi` and `sysupgrade.bin` generation;
- an initramfs FIT/uImage when `CONFIG_TARGET_ROOTFS_INITRAMFS=y`.

These are OpenWrt-native artifacts. The recipe does not create the signed FIMS
container required by the historical stock updater.

## DTS and hardware coverage

The current DTS:

- identifies IPQ6018 with 512 MiB RAM;
- uses the Qualcomm SMEM partition parser rather than inventing fixed offsets;
- enables `serial0` at 115200 8N1;
- enables QPIC NAND with 2 KiB pages and 4-bit ECC per 512 bytes;
- maps QCA8075 PHY addresses 1, 2, and 3 to `lan1`, `lan2`, and `wan`;
- exposes only `lan1 lan2` as LAN and `wan` as WAN in `02_network`;
- selects an `LG-GAPD-7500` ath11k calibration variant and includes a packaged
  board file.

The DTS contains no explicit RTL8367RB node, management-bus wiring, port map, or
CPU-port definition. Merely installing `kmod-switch-rtl8367b` does not prove the
external switch is initialized. PR 207 documented unresolved RTL8367RB-managed
ports; no current source evidence establishes that all physical ports are now
working.

## Official-tree port result

The tracked official OpenWrt patch converts the fork-specific NSS dataplane to
the current IPQ6018 EDMA/PPE DSA binding, packages the public GAPD BDF, carries
the QCA8075 LED and Wi-Fi MAC rules, and retains lowercase OpenWrt SMEM names.
It also refuses GAPD sysupgrade in both the image-check and write-dispatch
functions.

The patched tree compiled successfully as Linux 6.18.44. Its DTB and assembled
root filesystem passed offline inspection, including an exact BDF SHA-256
match. The resulting initramfs also passed an actual-device RAM boot: LAN1,
HTTP/SSH, two ath11k PHYs, and both radio state machines were verified.

## Actual RAM-boot findings and current defects

The actual OpenWrt RAM boot exposes `0:art` and `0:appsblenv` in `/proc/mtd`.
Stock Linux used uppercase display names, but applying those names to OpenWrt
was incorrect. The uppercase local patch prevented creation of
`cal-ahb-c000000.wifi.bin`; ath11k then failed to load calibration data and no
wireless PHY appeared. The official port must retain lowercase OpenWrt names.

More importantly, current LiBwrt groups GAPD with devices that call generic
`nand_do_upgrade`. It has no GAPD-specific handling for the observed
`rootfs/rootfs_1`, `BOOTCONFIG`, `BOOTCONFIG1`, or `Boot act` behavior.
`patches/0001-gapd-7500-caldata-and-sysupgrade-safety.patch` therefore makes
both image checking and the platform upgrade function fail closed on GAPD. The
patch is intentionally restrictive: it allows a RAM experiment image to be
built without presenting an accidental working sysupgrade path.

## Installation-path assessment

| Route | Current evidence | Preconditions | Brick risk | Recovery status |
|---|---|---|---|---|
| Stock shell/root | Current factory-test command injection executes bounded root commands; Dropbear exists behind the firewall | Keep use volatile/read-only unless separately authorized | Low for inventory; high once writing | Read-only path established |
| Hidden maintenance interface | Hidden login/pages and unauthenticated EJ/file/factory-test defects are confirmed live | No stock updater use; retain sanitized evidence only | Low while read-only | Not a recovery loader |
| Vendor FIMS update | Strong historical code evidence and public author report | Complete accepted package, protocol and signature understanding | High when an update is served | Not established |
| Inactive A/B slot | Exact factory UBI was written and manually boot-verified before both BOOTCONFIG copies selected it | Keep original backups and UART gate; rollback write remains untested | Controlled high risk | Passed on this device |
| RAM initramfs | Official OpenWrt booted on the actual device; LAN1, HTTP/SSH, and two ath11k PHYs passed | Additional LED, USB, WAN/LAN2 and over-the-air Wi-Fi tests | Low while RAM-only | First official-tree RAM boot passed |
| External NAND programmer | 128 MiB SLC NAND identified | Correct hardware, pinout, voltage, ECC/OOB-aware double dump | High physical risk; potentially strongest recovery | Equipment/procedure not verified |
| Bootloader modification | APPSBL is redundant in the public layout | Full dump, reverse engineering, external recovery | Extreme | Prohibited at current phase |

The inactive-slot row records the completed, explicitly authorized 2026-09-12
installation. It is not standing authorization for another write or device.

The actual running 1.06.08 executables match neither the historical public
rootfs nor the local 1.07.16 update candidate. Those images remain format and
code-history references only. Current-device conclusions come from the live
inventory and the verified host backups.
