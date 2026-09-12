# GAPD-7500 hardware notes

Updated: 2026-09-08 (Asia/Seoul)

## Confirmed on this unit

- [VERIFIED-DEVICE] Model: LG U+ / Davolink GAPD-7500.
- [VERIFIED-DEVICE] Boot log identifies an IPQ6018-class platform, four AArch64
  CPU cores, 512 MiB DDR3, and 128 MiB NAND.
- [VERIFIED-DEVICE] The boot interface is NAND and the observed boot log reports
  Secure Boot as Off.
- [VERIFIED-DEVICE] U-Boot is `2016.01-svn420`, built 2020-07-20, and prints
  `boot access disabled`.
- [VERIFIED-DEVICE] The UART footprint is a four-pin through-hole header. With
  the `UART` marking on the left and `JP1` on the right, Pin 2 is router TX and
  Pin 4 is GND.
- [VERIFIED-DEVICE] Pin 2 is connected to CH343 RXD, Pin 4 to GND, and router RX
  to CH343 TXD. Adapter VCC remains disconnected. Gated commands proved RX.
- [VERIFIED-DEVICE] A remaining pin was reported at 3.3 V, but the measurement
  lacks a recorded pin number and powered/unpowered comparison. It does not
  identify router RX.

## Source/community hardware mapping

- [VERIFIED-SOURCE] The reviewed LiBwrt DTS targets IPQ6018 and QPIC NAND with
  2 KiB pages and 4-bit ECC per 512 bytes.
- [COMMUNITY] Public porting material identifies QCN5021 (2.4 GHz), QCN5052
  (5 GHz), QCA8075 PHYs, and an RTL8367RB external switch.
- [UNVERIFIED-CURRENT-DEVICE] The RTL8367RB management bus, CPU port, and full
  front-panel port mapping have not been traced on this PCB.

No probe should be driven into either unknown UART pin. A voltage reading alone
cannot distinguish a pulled-up RX input from a supply pin; powered and unpowered
resistance/continuity observations must be recorded first.
