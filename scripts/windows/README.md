# Windows GAPD-7500 network automation

These scripts solve the duplicate-subnet case where both the Wi-Fi router and the
GAPD-7500 use `192.168.219.1/24`.

## Safety model

- The Wi-Fi default route is never modified.
- Any Ethernet default route is removed while automation is enabled and is saved
  for rollback.
- The target route is exactly `192.168.219.1/32`, on-link, and stored only in
  `ActiveStore`; it is never made persistent.
- The route is added only after the Ethernet adapter is `Up`, owns exactly
  `192.168.219.100/24`, Wi-Fi has a default route, and a source-bound ARP probe
  confirms `192.168.219.1` on the Ethernet L2 network.
- A one-second SYSTEM watcher removes the route when any prerequisite fails.
- Raw runtime snapshots, which can contain local MAC addresses, are kept under
  `%ProgramData%\GAPD-7500-Network\logs` and are not committed.

The scripts identify the adapter by its stable interface GUID after enablement.
Before enablement they use an explicitly supplied alias, the unique
`192.168.219.100` address, or the expected Realtek adapter description. This
avoids depending on an interface index that may change after a reboot.
If the USB NIC itself disappears, the saved interface index is used only to
find and remove stale routes; the adapter is reported as `NotPresent` and the
system remains in Wi-Fi fallback mode.

## Enable and rollback

Open **Windows PowerShell as Administrator** in the repository root:

```powershell
.\scripts\windows\enable-gapd-network.ps1 -EthernetAlias 'Ethernet 12'
```

Alternatively, double-click `enable-gapd-network-admin.bat`; it requests UAC
elevation and leaves the result visible. Double-click
`disable-gapd-network-admin.bat` for rollback.

Enablement is safe with the cable disconnected. In that case the scheduled
watcher is installed in Wi-Fi fallback mode and the `/32` remains absent until a
later link/address/L2 validation succeeds.

On a Korean Windows installation the alias may be localized. If auto-detection
finds the unique `192.168.219.100` adapter, omit `-EthernetAlias`:

```powershell
.\scripts\windows\enable-gapd-network.ps1
```

Check status without elevation:

```powershell
.\scripts\windows\get-gapd-network-status.ps1 -DetailedTests
```

Disable the watcher, remove the target route, and restore any Ethernet default
routes that were removed at enable time:

```powershell
.\scripts\windows\disable-gapd-network.ps1
```

`setup-target-network.ps1` and `rollback-target-network.ps1` are compatibility
wrappers for enable and disable.

## Four physical-state tests

Run these after putting the cables in the stated physical configuration. Each
command captures the required adapter, IP, route, neighbor, and `route print`
outputs plus both TCP checks.

```powershell
# Ethernet cable unplugged; automation may remain enabled.
.\scripts\windows\test-gapd-network-state.ps1 -Scenario Test1-WifiOnly

# Ethernet cable connected directly to GAPD-7500.
.\scripts\windows\test-gapd-network-state.ps1 -Scenario Test2-BothConnected

# Unplug the Ethernet cable while the watcher is running, then run:
.\scripts\windows\test-gapd-network-state.ps1 -Scenario Test3-EthernetDisconnected

# Reconnect the cable, wait about two seconds, then run:
.\scripts\windows\test-gapd-network-state.ps1 -Scenario Test4-EthernetReconnected
```

For Tests 1 and 3, the HTTP title must be visually identified as the Wi-Fi
router. For Tests 2 and 4, it must be the GAPD-7500 (`LG U+ CHGW Web` in the
known stock UI). The script logs the title but deliberately does not assume a
fixed Wi-Fi-router model.

## Hash-pinned initramfs TFTP server

`serve-gapd-initramfs.ps1` is a one-shot, read-only host server for the current
official OpenWrt GAPD initramfs candidate. It refuses a file unless both its
14,802,824-byte length and pinned SHA-256 match, requires the exact wired `/32`,
refuses an occupied UDP 69, and accepts only the requested filename from
`192.168.219.1`.

The Python helper answers the small RRQ through Ncat, then uses a native UDP
transfer socket so full 512-byte TFTP blocks are not truncated by Ncat's stdio
bridge. Every block requires an ACK and is retried on timeout. The helper passed
a loopback multi-block transfer with an identical SHA-256.

Do not start this server as an installation shortcut. It is for the separately
approved U-Boot RAM-boot sequence only, after the U-Boot console and Ethernet
port are proven. Starting the listener does not contact or alter the router;
the transfer begins only when U-Boot requests `gapd-initramfs.itb`.
Use `-ValidateOnly` to check the image, Ncat, source address, route, and UDP port
without opening a listener.

The pinned file is the host-verified official OpenWrt image documented in
`docs/06-openwrt-build.md`. The previously booted LiBwrt image no longer passes
this server's size/hash gate.
