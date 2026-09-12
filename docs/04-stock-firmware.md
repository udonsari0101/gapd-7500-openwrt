# Stock firmware static analysis

Updated: 2026-09-09 (Asia/Seoul)

## Evidence boundary

The analyzed archive is the older public dump named
`gapd-7500-0ca0-ubi-rootfs.zip`. It is associated with the material shared in
[LiBwrt issue 206](https://github.com/LiBwrt/LibWrt/issues/206), but the local
file's provenance and authenticity have not been independently established.
It must not be treated as identical to the device's currently observed stock
version 1.06.08.

This separation is now confirmed by live hashes: the actual router's BusyBox,
`dvbox`, and `lgu_topaz` match neither this historical dump nor the separately
downloaded 1.07.16 update candidate. Current 1.06.08 facts therefore come from
the live inventory and private physical-MTD backups, not either extracted local
rootfs.

The original archive was not modified. Analysis copies and extracted files live
under ignored `.work/firmware` paths.

| Item | Size | SHA-256 |
|---|---:|---|
| `gapd-7500-0ca0-ubi-rootfs.zip` | 23,603,585 bytes | `5064376af28d4543494412324c6f59d8ad25e40d6bd8299effe63fe5359ad0de` |
| inner `gapd-7500-0ca0-ubi-rootfs.bin` | 23,871,488 bytes | `b9dbbd88168c0ec05867124f890cdeddfdf3878f7d7307605bc7dd5efe091ecb` |

## Container identification

Despite its name, the inner file is not a UBI image and is not a complete LG
firmware-update package. `file`, its `hsqs` magic, and `unsquashfs` identify it
as a little-endian SquashFS 4.0 filesystem compressed with XZ:

- filesystem byte count reported by SquashFS: 23,593,432;
- block size: 262,144 bytes;
- creation time: 2022-04-20 07:37:45 UTC;
- extracted result: 2,313 files, 134 directories, and 403 symlinks;
- the `/dev/console` character-device node was intentionally not reproduced on
  the Windows-mounted analysis path because extraction was unprivileged.

This explains why attempting to upload this `.bin` as a factory image would be
incorrect: it lacks the outer update container and kernel/FIT sections expected
by the stock updater.

## Vendor update chain found in the rootfs

The historical rootfs contains:

- `/usr/sbin/cwmpsslClient`, the TR-069/CWMP client;
- `/usr/sbin/fimsfw`, with the alternate command names `fimsfw_valid`,
  `fimsfw_extract`, and `fimsfw_updatebins`;
- `/usr/lib/libfimsfw.so`;
- `/sbin/sysupgrade` with Davolink-specific changes;
- `/lib/upgrade/platform.sh` and dual-slot helpers;
- `/sbin/fwslot_toggle.sh` and `/sbin/primaryboot`.

Static strings in `cwmpsslClient` show HTTPS ACS endpoints in the
`lgqps.com` domain, firmware URL/filename/size parameters, a download directory
under `/var/tmp/autoupgrade`, and this invocation:

```text
/sbin/sysupgrade -n -S -N %s
```

The stock `sysupgrade` performs `fimsfw_extract` as a fatal pre-check before its
normal platform check. This fatal check does not honor OpenWrt's `--force`
handling. Its next layer requires a FIT image with at least a UBI or Qualcomm
firmware section, demultiplexes the FIT, and calls `dumpimage -c`.

`libfimsfw.so` imports or references all of the following:

```text
secc_is_fims_pkg
sec_fims_pkg_is_valid
secc_fims_pkg_info_get
secc_update_bins_sign_check_only
secc_update_bins_sign
dvct_validate
dvct_bhash_extract
```

It also contains package-signature length, per-binary signature length,
binary-hash, `rootfs`, `rootfs_1`, `nfi0`, and `nfi1` handling. This is direct
evidence that the vendor path expects more than a raw UBI/SquashFS and performs
vendor-specific package and binary verification.

After FIT sections are flashed, the historical platform script calls
`fimsfw_updatebins`, selects the Linux layout, and updates both `0:BOOTCONFIG`
and `0:BOOTCONFIG1`. The included `fwslot_toggle.sh` changes the rootfs primary
boot flag and rewrites both boot-configuration partitions.

## Other relevant historical findings

- Dropbear, its init script, and a configuration for TCP 22 with password
  authentication are present in this older dump.
- [VERIFIED-DEVICE] Only TCP 80 was observed open on the current 1.06.08 device.
  Therefore the old Dropbear files do not establish current SSH reachability.
- The historical web page `setting_02.html` exposes upgrade schedule/status
  values sourced from TR-069 configuration; it does not expose a referenced
  local firmware-upload form.
- `cwmpsslClient` performs X.509 certificate verification. Redirecting DNS or
  imitating only the hostname is therefore not an established update method.

## Conclusions and next evidence needed

1. Neither this rootfs `.bin`, a LiBwrt `factory.ubi`, nor a LiBwrt
   `sysupgrade.bin` is established as acceptable input to the stock updater.
2. A complete, legitimately downloaded FIMS firmware package is required to
   map the outer header, signed regions, embedded FIT, and version fields.
3. Passive capture of a normal update check may establish DNS names, TLS
   endpoints, timing, and metadata, but does not by itself solve certificate or
   firmware-signature verification.
4. Current firmware 1.06.08 has now been inventoried and its physical MTD set
   captured privately. Findings from older binaries are still promoted only
   after a separate live reproduction or an exact current-binary match.

`scripts/firmware/analyze_image.sh` automates hashing, type detection, binwalk,
and read-only SquashFS/UBI extraction while refusing to overwrite an existing
analysis directory.
