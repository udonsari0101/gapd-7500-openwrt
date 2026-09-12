# Windows duplicate-subnet networking

## Problem

The Internet Wi-Fi router and the directly connected GAPD-7500 both use
`192.168.219.1/24`. Windows therefore has two connected
`192.168.219.0/24` routes on separate L2 networks. A stale, more-specific
Ethernet `/32` route would also make the Wi-Fi gateway unreachable after cable
disconnect.

## Implemented policy

| Condition | `192.168.219.1/32` on Ethernet | Default route |
|---|---:|---|
| Ethernet Up, exact `192.168.219.100/24`, source-bound ARP succeeds | Present in `ActiveStore` | Wi-Fi only |
| Ethernet Down or cable disconnected | Absent | Wi-Fi only |
| Wrong/missing Ethernet IPv4 | Absent | Wi-Fi only |
| GAPD fails the wired L2 ARP probe | Absent | Wi-Fi only |
| Wi-Fi default route is missing | Absent (fail closed) | Not modified by these scripts |
| Conflicting `/32` exists on another interface | Absent on Ethernet; status is non-compliant | Not modified |

The watcher runs as SYSTEM from Task Scheduler at startup and logon, checks once
per second, and is configured for automatic restart. The interface GUID is saved
at enable time so an ifIndex change after reboot does not select the wrong NIC.
The route itself is deliberately non-persistent; after reboot it cannot appear
until the watcher revalidates link, address, Wi-Fi default route, and wired ARP.

Raw before/after snapshots are written beneath
`%ProgramData%\GAPD-7500-Network\logs`. They contain the complete outputs of:

```powershell
Get-NetAdapter
Get-NetIPConfiguration
Get-NetRoute -AddressFamily IPv4
Get-NetNeighbor -AddressFamily IPv4
route print -4
```

These raw logs may contain MAC addresses and therefore remain outside Git. The
sanitized baseline is in `logs/network/2026-09-08-baseline-sanitized.txt`.

## Rollback

`disable-gapd-network.ps1` stops and unregisters the scheduled task, removes the
Ethernet target `/32`, and restores any Ethernet default routes captured before
enablement. It archives the JSON rollback record under
`%ProgramData%\GAPD-7500-Network\history`.

Pre-existing target `/32` routes are captured for audit but intentionally not
restored: restoring one would recreate the exact stale-route hazard this
automation exists to prevent. No IP address, DHCP setting, DNS setting, Wi-Fi
route, or router configuration is changed.

## Important limitation

The current `192.168.219.100/24` address was DHCP-origin in the 2026-09-08
capture. The watcher verifies the address on every cycle and safely withholds the
route if a future DHCP lease differs. It does not silently convert the adapter to
static addressing.

