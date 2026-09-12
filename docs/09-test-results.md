# Test results

Updated: 2026-09-13 (Asia/Seoul)

## Completed read-only baseline

| Check | Result |
|---|---|
| Wi-Fi default route | Pass; sole IPv4 default route uses Wi-Fi |
| Ethernet default route | Pass; none present |
| Existing target `/32` | Pass; none present |
| Ethernet address | Pass; `192.168.219.100/24` present |
| GAPD L2 presence | Pass; source-bound ARP succeeded on Ethernet |
| Internet `1.1.1.1:443` | Pass through Wi-Fi |
| `192.168.219.1:80` before enable | Pass through Wi-Fi |
| Wi-Fi-router HTTP fingerprint | `U+네트워크 관리자` |
| PowerShell parser | Pass for all seven routing scripts plus test helper |
| Watcher decision dry run | Pass; selected `EthernetTargetActive` and would add `/32` |
| Administrator guard | Pass; enable refused mutation in a non-elevated shell |
| Elevated watcher installation | Pass; scheduled task reported `Running` |
| Active target route | Pass; one ActiveStore `/32`, zero PersistentStore `/32` |
| TEST 2 Internet path | Pass; `1.1.1.1:443` via Wi-Fi source `192.168.219.105` |
| TEST 2 GAPD path | Pass; `.1:80` via Ethernet source `192.168.219.100` |
| TEST 2 HTTP identity | Pass; title `LG U+ CHGW Web` |
| TEST 1 Wi-Fi-only path | Pass; no `/32`; Internet and `.1:80` used Wi-Fi |
| TEST 1 HTTP identity | Pass; title `U+네트워크 관리자` |
| TEST 3 disconnect transition | Pass; watcher changed to fallback with `route=False` |
| TEST 3 Internet continuity | Pass; `1.1.1.1:443` remained on Wi-Fi |
| TEST 3 gateway return | Pass; `.1:80` used Wi-Fi and returned the Wi-Fi-router title |
| TEST 4 route restoration | Pass; ActiveStore `/32` restored, PersistentStore count 0 |
| TEST 4 Internet continuity | Pass; `1.1.1.1:443` remained on Wi-Fi |
| TEST 4 GAPD identity | Pass; Ethernet source `.100`, title `LG U+ CHGW Web` |

## Required physical transition tests

TEST 2 was completed at 2026-09-08 02:13 KST. Its raw log is
`C:\ProgramData\GAPD-7500-Network\logs\20260908-021242-408-Test2-BothConnected.log`.
Tests 1 and 3 were completed at 02:20 KST. Their corrected UTF-8 logs are:

- `C:\ProgramData\GAPD-7500-Network\logs\20260908-022020-278-Test1-WifiOnly.log`
- `C:\ProgramData\GAPD-7500-Network\logs\20260908-022020-384-Test3-EthernetDisconnected.log`

The watcher recorded `WifiFallback`, `l2=False`, `route=False`, and
`compliant=True` at 02:15:22, before the USB adapter became fully absent one
second later. Missing-adapter handling was then hardened to avoid repeated error
logging while preserving fail-closed cleanup.

TEST 4 completed at 02:29 KST. Its raw log is
`C:\ProgramData\GAPD-7500-Network\logs\20260908-022843-920-Test4-EthernetReconnected.log`.
The watcher first observed the returning adapter as `Disconnected`, then as Up
without the required address. It added the route only at 02:28:20 after the
address and L2 probe became ready, and reported a compliant active state at
02:28:22.

| Test | Expected | Current status |
|---|---|---|
| 1. Wi-Fi only | Internet via Wi-Fi; no Ethernet `/32`; `.1` is Wi-Fi router | **PASS** |
| 2. Wi-Fi + GAPD Ethernet | Internet via Wi-Fi; `/32` via Ethernet; `.1` is GAPD | **PASS** |
| 3. Unplug Ethernet | `/32` disappears within watcher cycle; `.1` returns to Wi-Fi router | **PASS** |
| 4. Reconnect Ethernet | L2 revalidated, `/32` restored; Internet remains Wi-Fi | **PASS** |

Run the exact commands in `scripts/windows/README.md`. The test helper records
all required inventory commands, both `Test-NetConnection` checks, route-selected
interfaces, and the HTTP title in a timestamped raw log under ProgramData.

## Official OpenWrt host verification

| Check | Result |
|---|---|
| Patch applies to pinned `9f62ca8f...` | Pass; clean test worktree tree matched the built port tree |
| Full build | Pass; Linux 6.18.44, exit code 0 |
| BDF packaging | Pass; source, package build, and final rootfs SHA-256 match |
| DTB compile/decompile | Pass; model, SMEM NAND parser, EDMA/PPE, and ports 2/3/4 present |
| Base-files scripts | Pass; shell syntax, lowercase partition names, LED/MAC rules present |
| Sysupgrade safety | Pass; check and dispatch functions both return failure for GAPD |
| FIT structure | Pass; `config@cp03-c1`, ARM64 gzip kernel, expected DTB |
| FIT payload hashes | Pass; kernel and DTB CRC32/SHA-1 recomputed independently |
| RAM ranges | Pass; destination ends `0x42675008`, transfer ends `0x44e1df88` |
| Reproducible build script | Pass; pinned feeds, build, BDF/FIT checks, exact initramfs/factory hash gates |
| Actual official OpenWrt boot | **PASS**; FIT and CRC passed, Linux 6.18.44 reached init complete from tmpfs |
| Official LAN1 / management | **PASS**; LAN1 up, HTTP 200 and TCP 22 reachable at `192.168.1.1` |
| Official ath11k | **PASS (driver/PHY)**; two PHYs and two up radios, no failed/error log |
| Official Wi-Fi traffic | **NOT RUN**; no AP/client interface configured in initramfs |

The canonical host output is 14,802,824 bytes with SHA-256
`7618dda664005f2360bc786565bf8d4e69a2f5532739df39a0817515607f5400`.
The same file was hardware-tested in a RAM-only boot. U-Boot matched
`fileaddr=44000000`, `filesize=e1df88`, and CRC32 `51f3304e`; the device then
reported model `LG-GAPD-7500`, target `qualcommax/ipq60xx`, and
`rootfs_type=initramfs`. That RAM-only result preceded the persistent install.

## Persistent-install verification

| Check | Result |
|---|---|
| Factory UBI | 13,762,560 bytes; SHA-256 `fe306d8f...edb892b` |
| Inactive-slot write | Pass; 305 PEBs, zero bad PEBs |
| Kernel volume | Pass; SHA-256 `6fa0d471...9c99d5cf` |
| Rootfs volume | Pass; SHA-256 `bcca9159...d644a460` |
| Manual inactive boot | Pass; FIT CRC32 `2d655ac0`, hashes OK, init complete |
| BOOTCONFIG copies | Pass; both SHA-256 `629632b6...b89348ad` |
| Automatic boot | Pass twice; RX-only UART showed `Boot act=1` |
| Persistent root | Pass; `rootfs_type=squashfs`, UBIFS overlay mounted |
| Saved LAN config | Pass after reboot; `192.168.219.1/24` |
| Preserved stock slot | Pass; SHA-256 `4020f3c4...4475342f` |
| Recovery gate | Pass; raw APPSBLENV contains `bootdelay_=1` |
| Windows target route | Pass; ActiveStore `/32` uses Ethernet 12 |
| Internet route | Pass; `1.1.1.1:443` uses Wi-Fi |
| OpenWrt management | Pass; TCP 80 and SSH use Ethernet source `.100` |

The active-slot switch causes the SMEM parser to rename/reorder the rootfs
pair: after `Boot act=1`, installed OpenWrt appears as Linux `mtd16/rootfs` and
the preserved physical stock slot appears as `mtd17/rootfs_1`. This is a view
change, not an overwrite of the stock partition. A post-install electrical
power-loss cycle has not been observed; persistence is proven by the NAND
readbacks and two complete unattended software reboot cycles.

## 2026-09-13 functional follow-up

The persistent device passed password-only SSH authentication, public-key SSH,
LuCI HTTP 200, firewall4/nftables rule loading, LAN1 1 Gbit/s link, zero UBI bad
PEBs, and reversible power/2.4G/5G LED sysfs control. A copy of the exact built
sysupgrade image was tested only with `sysupgrade -T`; the port rejected it with
exit 1 as designed and the temporary file was removed.

Both ath11k radios created real AP interfaces for a short, reversible test. The
original wireless configuration was restored with matching before/after
SHA-256. A Windows client scan did not see either temporary SSID, so over-the-air
Wi-Fi remains unverified rather than passed. USB controllers are present but no
USB device was attached; WAN and LAN2 had no test cable; GPIO button hotplug is
loaded but no physical button was pressed. The detailed matrix is in
[`14-custom-build-test-report.md`](14-custom-build-test-report.md).
