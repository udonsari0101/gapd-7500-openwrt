# Reproducible GAPD-7500 OpenWrt builds

Updated: 2026-09-13 (Asia/Seoul)

## Official OpenWrt port

This is now the primary build path.

| Item | Pinned value |
|---|---|
| Source | `https://github.com/openwrt/openwrt.git` |
| Base commit | `9f62ca8ff14d701928b425b53d0093de80eb0df6` |
| Port patch | `patches/official-openwrt/0001-qualcommax-add-LG-GAPD-7500-support.patch` |
| Patched source tree | `94fa35b23dae1987967bc8696a5c07c832e870b2` |
| Config seed | `configs/openwrt-gapd-7500.config` |
| Feed lock | `configs/openwrt-feeds.lock` |
| Target/device | `qualcommax/ipq60xx` / `lg_gapd-7500` |
| Build filesystem | Native WSL2 ext4 |

From the Windows repository root (replace the path with your checkout):

```powershell
wsl.exe -d Ubuntu-22.04 -- bash `
  /mnt/c/path/to/gapd-7500-openwrt/scripts/build/build-openwrt-gapd-7500.sh
```

The script verifies the binary patch SHA-256, refuses an unexpected or dirty
source tree, pins all feeds, installs only the LuCI feed selection and required
dependencies, and uses an absolute Linux-only `PATH`. The sanitized `PATH`
prevents GNU `find -execdir` from rejecting relative Windows entries such as
`Files/Common` during `package/install`.

After building, the script checks the BDF in the assembled root filesystem,
parses the FIT directly, recomputes its kernel/DTB CRC32 and SHA-1 values,
decompresses the kernel, checks both RAM ranges, and verifies that the factory
UBI fits the known slot/PEB geometry. It reports new sizes and SHA-256 values and
copies initramfs, factory UBI, `SHA256SUMS`, FIT details, and build metadata to
the ignored `artifacts/openwrt-gapd-7500-release` directory. The sysupgrade
image is intentionally not exported.

Fresh builds are not currently byte-for-byte reproducible. A 2026-09-13 rebuild
used the same OpenWrt tree, feed commits, config, DTB, kernel volume, and rootfs
file tree, but APK installed-database package-size fields differed by a few
bytes. This changed SquashFS compression and therefore the outer image hashes.
Set `GAPD_REQUIRE_TESTED_HASHES=1` only when a controlled build is expected to
match the hardware-tested reference exactly; it will fail on any byte-level
difference. Normal source builds validate their structure and report their own
hashes. `scripts/release/prepare-tested-release.ps1` separately accepts only the
two preserved, hardware-tested binaries.

### Verified host output

| Property | Value |
|---|---|
| File | `openwrt-qualcommax-ipq60xx-lg_gapd-7500-initramfs-uImage.itb` |
| Size | 14,802,824 bytes (`0xe1df88`) |
| SHA-256 | `7618dda664005f2360bc786565bf8d4e69a2f5532739df39a0817515607f5400` |
| Kernel | ARM64 Linux 6.18.44, gzip |
| FIT config | `config@cp03-c1` |
| Kernel load/entry | `0x41000000` / `0x41000000` |
| Compressed/uncompressed payload | 14,774,130 / 23,547,912 bytes |
| Uncompressed end | `0x42675008` |
| TFTP buffer | `0x44000000-0x44e1df88` |
| DTB | 27,299 bytes, model `LG-GAPD-7500` |
| GAPD BDF | 65,640 bytes; SHA-256 `7d283ff5677c35009dc07b9f816f4a64fa80ab224db3610c74ef5370f4421fbb` |

The generated DTB was decompiled and checked for the QCA8075 mapping:
PHY 1/port 2 is `lan1`, PHY 2/port 3 is `lan2`, and PHY 3/port 4 is `wan`.
The root filesystem also contains lowercase `0:art` calibration extraction,
lowercase `0:appsblenv`, port LED rules, Wi-Fi MAC derivation, and both
`platform_check_image` and `platform_do_upgrade` GAPD refusal paths.

The same artifact was transferred to `0x44000000`; U-Boot reported
`filesize=e1df88` and whole-file CRC32 `51f3304e`, then booted it successfully.
The actual device reported OpenWrt SNAPSHOT `r0-9f62ca8`, Linux 6.18.44,
`rootfs_type=initramfs`, and a tmpfs root. LAN1, HTTP/SSH, two ath11k PHYs, and
both radio state machines passed. USB, LEDs, WAN/LAN2 traffic, over-the-air
Wi-Fi traffic, and the unresolved RTL8367RB topology remain unverified.

## Historical LiBwrt build and RAM boot

The earlier build remains useful as actual-device evidence:

| Item | Value |
|---|---|
| Source commit | LiBwrt `0fd5daca26aed9cab74b4141690deb5d997383f1` |
| Config | `configs/libwrt-gapd-7500.config` |
| Safety patch | `patches/0001-gapd-7500-caldata-and-sysupgrade-safety.patch` |
| Initramfs size | 18,129,564 bytes (`0x114a29c`) |
| Initramfs SHA-256 | `9ca834d6d2d520f8b03039be55fb5b8f1bf7d4f197992d931aec10637ac0e657` |
| Kernel | Linux 6.12.103 |
| Uncompressed end | `0x42930008` |

That image passed U-Boot FIT verification and booted to a tmpfs root on the
actual router. LAN1, LuCI, and SSH worked. Wi-Fi did not: the former local patch
changed OpenWrt's lowercase `0:art` name to uppercase and prevented calibration
extraction. The tracked LiBwrt patch has been corrected to retain lowercase
partition names and now changes only the two sysupgrade refusal paths.

Neither build creates an accepted LG/Davolink FIMS update. No factory image,
sysupgrade image, or raw UBI file is a verified stock-web-updater input.
