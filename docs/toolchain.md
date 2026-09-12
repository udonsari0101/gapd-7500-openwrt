# Analysis and build toolchain

Updated: 2026-09-09 (Asia/Seoul)

## Host layout

- [VERIFIED-DEVICE] Windows host with WSL2 and Ubuntu 22.04.
- [VERIFIED-DEVICE] The Ubuntu distribution uses WSL version 2.
- [VERIFIED-DEVICE] Native WSL storage has approximately 952 GiB free at the
  time of setup; the Windows `C:` mount has approximately 179 GiB free.
- Source/build trees are kept on the native ext4 filesystem under
  `/home/yeappidw/gapd_7500_openwrt/.work`. This deliberately differs from a
  literal Windows `.work` directory because OpenWrt relies on Linux file modes,
  case sensitivity, symlinks, and high metadata throughput.
- Firmware inputs and extracted evidence remain in the repository's ignored
  Windows `.work/firmware` directory.

## Installed versions

| Tool | Version observed |
|---|---|
| Ubuntu kernel | WSL2 Linux 6.18.33.2 |
| Git | 2.34.1 |
| curl | 7.81.0 |
| wget | 1.21.2 |
| file | 5.41 |
| GNU binutils `strings` | 2.38 |
| xxd | 2021-10-22 |
| hexdump | util-linux 2.37.2 |
| jq | 1.6 |
| Python | 3.10.12 |
| pip | 26.2.1 |
| pipx | 1.0.0 |
| binwalk | 2.3.3 |
| squashfs-tools | 4.5 |
| mtd-utils | 2.1.4 |
| device-tree-compiler | 1.6.1 |
| U-Boot tools | 2022.01+dfsg-2ubuntu2.7 |
| OpenSSL | 3.0.2 |
| rsync | 3.2.7 |
| GCC | 11.4.0 |
| GNU Make | 4.3 |
| ubi-reader | 0.8.16 in a pipx environment |

The requested Debian packages were installed with `apt-get`; `ubi-reader` was
installed with `pipx install ubi-reader`. The installation added build tools
and upgraded normal Ubuntu dependencies. It did not modify the router.

## Source workspaces

| Tree | Branch | Commit at capture |
|---|---|---|
| LiBwrt/LibWrt | `25.12-nss` | `0fd5daca26aed9cab74b4141690deb5d997383f1` |
| openwrt/openwrt | local `gapd-official` | base `9f62ca8ff14d701928b425b53d0093de80eb0df6` |

The checked-out source is ignored and is not copied into this Git repository.
The LiBwrt and official OpenWrt feed resolutions are recorded separately in
`configs/libwrt-feeds.lock` and `configs/openwrt-feeds.lock`. The official port
itself is retained as a binary-capable format patch under
`patches/official-openwrt`.
