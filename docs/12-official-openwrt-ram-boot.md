# Official OpenWrt actual-device RAM boot

Updated: 2026-09-09 (Asia/Seoul)

## Scope and artifact

This was an explicitly approved, RAM-only test on the owner-controlled
GAPD-7500. No `sysupgrade`, `mtd`, `nandwrite`, `ubiformat`, `ubiupdatevol`, or
OpenWrt payload write was performed.

| Property | Verified value |
|---|---|
| Image | `openwrt-qualcommax-ipq60xx-lg_gapd-7500-initramfs-uImage.itb` |
| Bytes | 14,802,824 (`0xe1df88`) |
| SHA-256 | `7618dda664005f2360bc786565bf8d4e69a2f5532739df39a0817515607f5400` |
| Host CRC32 | `51f3304e` |
| TFTP address | `0x44000000` |
| FIT config | `config@cp03-c1` |
| Boot command | `bootm 0x44000000#config@cp03-c1` |

Before the controlled reboot, the current 524,288-byte APPSBLENV was copied to
the ignored backup directory and its device/PC SHA-256 values matched. The
one-time `bootdelay_=1` console gate was removed in U-Boot RAM and one
`saveenv` persisted that removal before temporary network values were set.
`bootdelay_` and `defenv` were both verified absent after OpenWrt started.

## Transfer and boot evidence

The one-shot server accepted only the pinned filename, source/client pair,
byte count, and SHA-256. U-Boot reported `fileaddr=44000000`,
`filesize=e1df88`, and whole-range CRC32 `51f3304e`. A second CRC check directly
before `bootm` also matched. FIT hash verification passed, Linux started, init
completed, no kernel panic occurred, and control did not return to U-Boot.

## Actual-device result

| Check | Result |
|---|---|
| Model / board | `LG-GAPD-7500` / `lg,gapd-7500` |
| OpenWrt | SNAPSHOT `r0-9f62ca8`, `qualcommax/ipq60xx` |
| Kernel | Linux 6.18.44 |
| Root | `rootfs_type=initramfs`; `/` is tmpfs |
| Management | HTTP 200 and TCP 22 at `192.168.1.1` |
| Ethernet | Connected LAN1 reports up |
| Calibration partition | Lowercase `0:art` present |
| Environment partition | Lowercase `0:appsblenv` present |
| Wi-Fi driver | `ath11k`/`ath11k_ahb` loaded |
| Wi-Fi PHY/radios | `phy0` and `phy1`; 5 GHz and 2.4 GHz radios both up |
| Kernel failure scan | No `failed` or `error` dmesg line |

The initramfs contains no configured Wi-Fi AP/client interface, so radio and
PHY initialization is verified but over-the-air traffic is not. USB, LEDs,
WAN/LAN2 traffic, and the unresolved RTL8367RB topology also remain untested.

## Host cleanup

After init completed, the temporary `192.168.219.100/24` address, exact
`192.168.219.1/32` route, static U-Boot neighbor, ICMP rule, UDP 69 rule, and
one-shot listener were removed. Ethernet retains only `192.168.1.100/24` with
no default route. Wi-Fi remains the sole Internet/default route, and
`192.168.219.1:80` again resolves through Wi-Fi.

This validated the official-tree port as a RAM-boot candidate. Persistent
installation was separately authorized and completed on 2026-09-12; see
[`13-persistent-openwrt-install.md`](13-persistent-openwrt-install.md).
