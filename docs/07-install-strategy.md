# Installation strategy and evidence gates

Updated: 2026-09-12 (Asia/Seoul)

The owner explicitly authorized persistent installation on 2026-09-12. The
inactive-slot procedure passed on the actual device; it is recorded in
`13-persistent-openwrt-install.md` and pinned helpers are under
`scripts/device`. Generic sysupgrade remains deliberately disabled.

| Candidate path | Evidence now | What is missing | Risk now |
|---|---|---|---|
| Stock shell/root | Live factory-test injection executes bounded root commands; Dropbear is source-filtered | No need to expose SSH for the current read-only phase | Low while volatile/read-only |
| Hidden maintenance UI | Hidden routes plus public EJ/file/factory-test vulnerabilities are confirmed live | Vendor remediation and responsible evidence handling | Low while read-only |
| Vendor FIMS update | Historical code verifies a signed outer package and FIT sections | Genuine full package, accepted signature chain, and recovery | High |
| Inactive A/B slot | Factory UBI written, manually booted, then selected with both BOOTCONFIG copies | Preserve exact backups and recovery gate | Passed on this device |
| RAM initramfs | Official OpenWrt boot passed on the actual device; LAN1, HTTP/SSH, and two ath11k PHYs verified | Additional peripheral and traffic tests | Lowest candidate; first official RAM boot passed |
| External NAND programmer | NAND type/capacity are known | Exact package/pinout, voltage isolation, ECC/OOB workflow, double dump | High physical risk |
| Bootloader modification | Redundant APPSBL appears in historical layout | Full reverse engineering and independent restore path | Extreme; prohibited |

The preferred first experiment was a RAM-only initramfs boot. An approved
live test confirmed that `defenv` suppresses `boot access disabled`, but the
bootloader emits no autoboot prompt and silently continues to stock. The
prompt-gated helper correctly sent nothing. The marker was removed through the
stock environment tool after boot and verified absent. A signature-triggered
single-byte test keyed to the console-ready signature subsequently reached the
prompt. The marker removal was persisted before temporary U-Boot network values
were set; those network values were not saved.

LAN1 had no U-Boot carrier. LAN2 brought PHY1 and the Windows USB NIC up at
1 Gbit/s. A private, reversible ActiveStore neighbor handled a Windows
`SendARP` interoperability issue; bounded U-Boot ping and host packet capture
then agreed on one echo request and one reply. The pinned TFTP server's
validation-only mode passed without opening UDP 69.

Secure Boot Off and FIT compatibility do not make the stock web updater safe.
The reviewed route loaded one pinned TFTP image into RAM at `0x44000000`.
The one-shot server verified SHA-256 and U-Boot verified the complete range by
CRC32; this APPSBL has no live `hash` or `iminfo` command. The FIT's
`config@cp03-c1` was subsequently executed with explicit approval. LibWrt
reached init complete with `/` on tmpfs and no kernel panic. No NAND/MTD/UBI
write or saved environment change occurred. Wi-Fi failed in that historical
image because the uppercase ART extraction path was incorrect.

The replacement official OpenWrt initramfs retains lowercase `0:art`, includes
the GAPD BDF, and passed both offline verification and an actual-device RAM
boot. LAN1, HTTP/SSH, two ath11k PHYs, and both radio state machines work; no
wireless AP/client interface was configured, so over-the-air traffic was not
proven by that RAM boot. A later persistent test created both AP interfaces,
but an external client still did not see the temporary SSIDs. The reproducible
build exports the exact hardware-tested initramfs and factory UBI; sysupgrade
is omitted and the platform code rejects it at both dispatch stages.

The completed write used the device/hash/slot preflights and the user's explicit
authorization. The stronger external-programmer, OOB-dump, and tested-restore
items in `08-backup-and-recovery.md` were not completed; that residual recovery
risk remains explicit. Future writes require a fresh preflight and approval.
