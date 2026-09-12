# Hidden web surface and security audit

Updated: 2026-09-12 (Asia/Seoul)

## Scope and publication boundary

This audit covers one owner-controlled GAPD-7500 on the directly connected
Ethernet segment. OpenWrt installation is postponed. The current objective is
to document the hidden stock-management surface and reach a verified state from
which a RAM-only OpenWrt upload could later be performed safely.

Published evidence intentionally excludes the device administrator password,
session cookies, CAPTCHA answers, device identifiers, the deterministic hidden
password formula, and ready-to-run state-changing payloads. Raw captures and
working notes remain under ignored `.work` and `artifacts` paths.

The previously analyzed rootfs images are an older public dump and a 1.07.16
update candidate. The actual router identifies its running image as
`1.06.08 (2024-04-08 11:22:43)`. Live BusyBox, `dvbox`, and `lgu_topaz` hashes
match neither local image, so only findings tagged `VERIFIED-DEVICE` are
current-device facts.

## Current verified access state

- [VERIFIED-DEVICE] The Windows route watcher directs only
  `192.168.219.1/32` through the GAPD Ethernet interface while Wi-Fi retains the
  default route.
- [VERIFIED-DEVICE] Normal administrator login succeeds on TCP 80.
- [VERIFIED-DEVICE] A hidden/superuser web session was established without
  storing its plaintext derived password.
- [VERIFIED-DEVICE] An exact wired-interface TCP connect scan found only TCP
  80 open. A source-IP-restricted runtime firewall rule temporarily exposed the
  existing Dropbear listener and was then removed; TCP 22 is again unreachable.
- [VERIFIED-DEVICE] The unauthenticated factory-test handler executed a
  bounded command as root. This was used only for volatile `/tmp` scripts,
  read-only inventory, and host-side backups; no persistent router setting or
  flash object was changed.
- [VERIFIED-DEVICE] No firmware image or OpenWrt artifact has been sent to the
  router.

## Recovered hidden routes

The stock `lgu_topaz` binary constructs most route names one byte at a time at
startup and stores encrypted page bodies in its data section. Emulating only the
string-construction routine recovered the following handler patterns.

| Route pattern | Purpose or evidence | Current-device result |
|---|---|---|
| `/_@hid_transit.asp` | Hidden/superuser login transition | Hidden session verified |
| `/_@upgrade_h.asp` | Local firmware-upload page | GET 200; 3,479 bytes |
| `/ap_fm_ch.cgi*` | Multipart firmware-upload action | Not invoked |
| `/**/syslogdl.cgi*` | System-log download action | Not invoked |
| `/_@ip_version_h.asp` | Hidden IP-version page | GET 200; 1,573 bytes |
| `/_@ipv6_setting_h.asp` | Hidden IPv6 configuration page | GET 200; 19,555 bytes |
| `/_@iot_info_h.asp` | Hidden IoT firmware information/removal page | GET 200; 2,412 bytes |
| `/ap_auth_sta.asp*` | Authentication-station handler | Static only |
| `/ap_radius_mac.asp*` | RADIUS MAC handler | Static only |
| `/ap_hidden_radio.asp*` | Hidden-radio handler | Handler matched; empty GET body |
| `/ap_hidden_ssid.asp*` | Hidden-SSID handler | Static only |
| `/ap_join_status.asp*` | Join-status handler | Static only |
| `/dv_devinfo.cgi*` | Device-information handler | Static only |
| `/ap_basic_lan.asp*` | Hidden LAN handler | Static only |
| `/ap_resv_ports.asp*` | Reserved-port handler | Static only |
| `/ap_e@vofldk_basic.asp*` | Hidden credential/basic handler | Static only |
| `/ap_acs_auth_show.asp*` | ACS authentication display handler | Static only |
| `/ap_hidden_selfrestart.asp*` | Hidden scheduled-restart handler | Static only |
| `/ap_hidden_healthcheck.asp*` | Hidden health-check handler | Static only |
| `/ap_hidden_provision_result.asp*` | Hidden provisioning-result handler | Static only |
| `/dvctrl.cgi*` | Vendor device-control handler | Not invoked |
| `/dvtst.cgi*` | Vendor test handler | Not invoked |
| `/dv_factst.cgi*` | Vendor factory-test handler | Root command injection confirmed; bounded volatile/read-only use only |
| `/cgi-bin/ckwiring.cgi?*` | Wiring-check handler | Not invoked |

The embedded hidden-page map also links internal identifiers to route bodies:

```text
@h_000 -> _@hid_transit.asp
@h_001 -> ap_hidden_healthcheck.asp
@h_002 -> ap_hidden_provision_result.asp
@h_003 -> ap_e@vofldk_basic.asp
@h_004 -> ap_resv_ports.asp
@h_005 -> ap_acs_auth_show.asp
@h_006 -> ap_join_status.asp
@h_007 -> ap_hidden_ssid.asp
@h_008 -> ap_basic_lan.asp
@h_009 -> ap_hidden_selfrestart.asp
@h_010 -> ap_auth_sta.asp
@h_011 -> no mapped route in the recovered table
@h_012 -> ap_radius_mac.asp
@h_013 -> _@upgrade_h.asp
@h_014 -> _@iot_info_h.asp
@h_015 -> _@ipv6_setting_h.asp
@h_016 -> _@ip_version_h.asp
```

Direct requests for the internal `@h_NNN.asp` identifiers return 404. They are
encrypted-template identifiers, not externally registered paths.

## Vulnerability findings

### GAPD-WEB-01: public EJ allow-list bypass

Status: **confirmed on the current device**. Severity: **high**.

`/web/public_data.html?func=...` checks whether the decoded expression contains
the text of the expected CAPTCHA function, then passes the complete expression
to the generic EJ evaluator. A second registered EJ call can therefore be
chained into a request that still passes the substring check.

Read-only proofs returned a hidden-login token and selected non-secret UCI data
before authentication. The same EJ table contains state-changing and
command-launching functions, so impact is broader than the two safe proofs;
those paths have not been exercised through the public endpoint.

Recommended fix: parse exactly one function call, compare the parsed function
identifier to a strict allow-list, reject separators/trailing expressions, and
remove generic EJ evaluation from the public handler.

### GAPD-WEB-02: CAPTCHA can be inverted offline

Status: **confirmed on the current device**. Severity: **high as an
authentication-rate-limit bypass component**.

The CAPTCHA answer is six lowercase ASCII letters. Its image filename is a
SHA-256 digest of the answer plus a fixed string. The filename is disclosed to
the client, leaving only `26^6` candidates and allowing the answer to be found
offline without sending guesses to the router. A recovered answer was accepted
by the normal login flow.

Recommended fix: use a cryptographically random server-side challenge ID,
store the answer only server-side with a short expiry, rate-limit attempts, and
never derive a public asset name directly from the answer.

### GAPD-WEB-03: deterministic hidden/superuser credential

Status: **static derivation confirmed; hidden-session chain confirmed with a
normal administrator session**. Severity: **high**, with unauthenticated
preconditions still under review.

The stock code derives a hidden password deterministically from device identity
values rather than provisioning a random per-device secret. The derived value
was kept only in process memory, encrypted using the router's expected form
format, and accepted by the hidden transition handler.

Recommended fix: remove the deterministic support credential, use a random
per-device secret protected by hardware-backed storage where available, and
require an explicit local-presence or time-limited support authorization.

### GAPD-WEB-04: unauthenticated arbitrary file disclosure

Status: **confirmed on the current device**. Severity: **high**.

The registered `check_file_exist` EJ function passes an attacker-selected path
to `yfcat(path, "%s", buffer)` and returns the first whitespace-delimited token,
not necessarily the complete file. Combined with GAPD-WEB-01, it is reachable
from the public evaluator. A safe proof read the known non-secret
`/etc/openwrt_release` file before authentication: HTTP 200, 20 bytes, SHA-256
`99b9980770bc6610d00426932580c72feaaa39efae457e528169bd3b551425b0`.
Credential stores, private keys, calibration data, and other secrets were not
requested.

Recommended fix: remove filesystem reads from the public EJ table, canonicalize
and allow-list any unavoidable status-file paths, and run the web process with
least filesystem privilege.

### GAPD-WEB-05: unauthenticated memory corruption and HTTP-service denial

Status: **unsafe boundedness confirmed in the historical binary; transient
service outage confirmed on the current device**. Severity: **high**.

The historical AArch64 implementation reserves approximately 24 bytes between
the destination passed to `yfcat(path, "%s", buffer)` and its stack canary, with
no visible field width in the format. An unauthenticated current-device request
for a known read-only pseudo-file whose first token exceeds that space returned
an empty reply and made TCP 80 unavailable for approximately four seconds. The
service recovered automatically, and no router reboot was observed.

This is evidence of an unauthenticated memory-safety defect and service denial,
not evidence of code execution. Long-token files will not be requested again;
further work is static only. Recommended fix: replace the unbounded token read
with a size-aware API, reject arbitrary paths, and isolate/restart the worker
without exposing it through the public evaluator.

### GAPD-WEB-06: unauthenticated factory-test command injection

Status: **confirmed on the current device**. Severity: **critical**.

The unauthenticated `self_url` parameter of `/dv_factst.cgi` is incorporated
into a shell command. A two-second timing oracle confirmed shell evaluation,
and a short script fetched into `/tmp` executed as root. The live environment
uses `HOME=/`, allowing slash construction without embedding a raw slash in the
vulnerable parameter. The proof was then limited to read-only inventory,
ephemeral source-restricted firewall tests, and volatile file cleanup.

This path confirmed the live kernel, partition table, UBI layout, boot
environment, executable hashes, and backup stream. It also exposes an existing
Dropbear daemon behind the stock firewall. The administrator web password was
not accepted for root SSH, and no password guessing was attempted.

Separately, several registered EJ handlers reach `system`, `popen`, `yexecv`,
or `yexecl`. Most reviewed functions used fixed commands, numeric arguments,
or explicit validation. The DDNS renewal path uses argv-style `yexecl`; its
earlier shell-metacharacter hypothesis was rejected.

One DDNS test did make the single web worker wait for the DDNS client timeout.
The configuration was restored through the normal form and read back as
disabled. This false lead is retained to prevent repeating a disruptive test.

Recommended fix: remove the factory diagnostic handler from production,
strictly parse every argument without a shell, require an authenticated
local-presence mode for diagnostics, and run the web worker without root or
network-administration capability.

### GAPD-WEB-07: statically encrypted hidden pages are recoverable

Status: **confirmed against the historical binary**. Severity:
**informational by itself**.

All 17 embedded `@h_NNN.asp` page bodies use AES-128-CBC with a zero IV and a
constant key present in the same executable. They were decrypted offline with
valid PKCS#7 padding. This exposes the complete hidden forms and their UCI
references to anyone with the firmware; encryption must not be treated as an
authorization boundary.

## Actual-device boot and recovery evidence

- [VERIFIED-DEVICE] Kernel: Linux 4.4.60, IPQ6018/AP-CP03-C1, four AArch64
  cores, 512 MiB physical RAM; approximately 418 MiB is visible to Linux.
- [VERIFIED-DEVICE] Active boot command line selects physical `rootfs`
  (`mtd16`), and UART repeatedly reports `Boot act=0`.
- [VERIFIED-DEVICE] The complete physical MTD map is 128 MiB across `mtd0`
  through `mtd19`; UBI maps `ubi0` to `mtd16`, `ubi18` to DVCFG, and `ubi19`
  to USER.
- [VERIFIED-DEVICE] Exact-size host backups exist for all 20 physical MTD
  devices. `mtd0` through `mtd18` have matching device/PC SHA-256 values.
  `mtd19` is retained only as a live capture because mounted qcalog/iotpg
  writes changed its device hash during collection.
- [VERIFIED-DEVICE] Multi-block TFTP was verified in both directions using a
  978-byte round trip with matching SHA-256. Router-side transfers and scripts
  were confined to `/tmp` and removed afterward.
- [VERIFIED-DEVICE] The stock kernel has no usable `kexec` binary, applet, or
  enabled kernel path, so an in-Linux RAM boot is unavailable.
- [VERIFIED-DEVICE] The actual APPSBL is U-Boot 2016.01-svn420. Secure Boot is
  Off; `bootm`, `tftpboot`, and `crc32` are present. Live commands show that
  `hash` and `iminfo` are absent. Static analysis of the actual APPSBL shows
  that `bootdelay_` or the one-time `defenv` environment
  gate bypasses `boot access disabled`. An approved live gate test was
  performed, stock-booted, rolled back, and verified absent afterward.
- [VERIFIED-HOST] The historical 18,129,564-byte LiBwrt initramfs FIT has the expected
  `config@cp03-c1`, ARM64 gzip kernel, load/entry `0x41000000`, and independently
  matching kernel/DTB CRC32 and SHA-1 nodes. Loaded at the stock address
  `0x44000000`, its source range does not overlap the uncompressed kernel.
- [VERIFIED-HOST] The replacement official OpenWrt initramfs is 14,802,824
  bytes with SHA-256 `7618dda6...f5400`; its BDF, FIT hashes, DTB, and RAM ranges
  pass offline verification.
- [VERIFIED-DEVICE] That exact official image was transferred to RAM, matched
  U-Boot CRC32 `51f3304e`, and booted OpenWrt SNAPSHOT `r0-9f62ca8` / Linux
  6.18.44 from a tmpfs root. LAN1, HTTP/SSH, and two ath11k PHYs passed.

An inaccessible empty tmpfs mount entry from an earlier root-home probe had no
process users. The later controlled stock reboot removes volatile mount state;
a fresh full mountinfo capture has not yet been repeated.

## Route-to-upload readiness gate

The hidden upload form is **not** an OpenWrt installation path. Static analysis
shows that the stock updater requires the vendor FIMS package/signature chain;
uploading `factory.ubi`, `sysupgrade.bin`, or the initramfs ITB there would be
unsafe.

The historical route-to-upload gate progressed through one explicitly approved
LibWrt RAM boot. Completed evidence is:

1. current `/proc/cmdline`, `/proc/mtd`, UBI, mount, RAM, DT, and boot
   environment were recorded from the actual router;
2. the recovery-critical physical MTD set through `mtd18` was backed up with
   exact sizes and independent device/PC SHA-256 agreement;
3. the volatile transfer path and the host's hash-pinned one-shot TFTP server
   were tested without an OpenWrt image transfer;
4. the actual APPSBL console gate and FIT load/entry/range were reviewed;
5. approved gate tests reached U-Boot and persisted marker removal before
   RAM-only network values were set;
6. LAN2 PHY/link, U-Boot-to-host ping, and the hash-pinned server's
   validation-only mode passed;
7. one pinned initramfs was transferred to RAM and its U-Boot size, metadata,
   and whole-range CRC32 matched the host artifact;
8. an explicitly approved `bootm` passed FIT hashes and reached LibWrt init
   complete from a tmpfs root;
9. no MTD/UBI payload, calibration data, or boot-selection change was made;
   the temporary network values were never saved to the environment.

The prompt-gated UART helper captured 6,493 bytes but transmitted zero because
this build does not print an autoboot prompt. An approved follow-up used the
stock `bootdelay_` marker and transmitted one SPACE after the exact
console-ready signature, reaching `IPQ6018#`. The marker was deleted and its
removal persisted before temporary network values were set.

The router now runs the corrected official OpenWrt port persistently from the
previously inactive NAND slot. LAN1, HTTP, and SSH are reachable at
`192.168.219.1`; ath11k created two PHYs. The Windows watcher directs only the
target `/32` over Ethernet and keeps Internet on Wi-Fi. Exact private captures,
link-layer addresses, and raw rollback images remain ignored from Git.

The factory diagnostic `dvtst.cgi` contains commands that add or remove a broad
`TELNMS` accept rule, but it first requires `/tmp/mode_factory`. A read-only
GAPD-WEB-04 probe returned no content for that path, confirming the factory-mode
marker is absent on the current device. That CGI is therefore not being used as
the shell-enablement path.

## Exact wired management-port observation

At 2026-09-09 00:00 Asia/Seoul, a TCP connect scan was bound to the validated
wired source address and interface. TCP 80 was open, TCP 22 was filtered, and
TCP 21, 23, 53, 443, 2323, 5000, 5555, 7547, 8080, 8443, 8888, and 9000 were
closed. This rules out a currently exposed SSH, Telnet, HTTPS, CWMP, or common
alternate web-management listener; any reversible support-shell transition
must originate through the authenticated HTTP surface or an already-present
local management mechanism.

At 2026-09-09 02:33, a second status snapshot confirmed Wi-Fi still owned the
only default route and passed `1.1.1.1:443`, while the target TCP 80 request used
the wired source. TCP 22 was unreachable from the wired source after rollback,
and no Ncat listener remained.

The broad file-collection experiment is closed. Short responses from
`/proc/mtd`, `/etc/config/dropbear`, and the firewall configuration represented
only their first whitespace token, not full file captures. The long-token
pseudo-file test caused the transient outage described in GAPD-WEB-05 and will
not be repeated.
