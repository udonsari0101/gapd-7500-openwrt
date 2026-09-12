# UART capture and current safety boundary

Updated: 2026-09-09 (Asia/Seoul)

## Verified wiring and console state

- [VERIFIED-DEVICE] The PCB has a four-pin through-hole header marked `UART`.
- [VERIFIED-DEVICE] With the board viewed from the `UART` marking toward `JP1`,
  the pins are numbered 1 through 4 from left to right.
- [VERIFIED-DEVICE] Pin 2 is the router TX output.
- [VERIFIED-DEVICE] Pin 4 is ground.
- [VERIFIED-DEVICE] CH343 is available as `COM8` and the boot output decodes at
  115200 baud, 8 data bits, no parity, 1 stop bit, and no flow control.
- [VERIFIED-DEVICE] U-Boot prints `boot access disabled`.
- [VERIFIED-DEVICE] Actual APPSBL analysis shows that `bootdelay_` bypasses the
  lock. If `defenv` exists, U-Boot removes it from the RAM environment and also
  skips the lock, providing a recoverable one-time gate.
- [VERIFIED-HARDWARE] CH343 TXD to router RX is proven: the gated one-byte
  interrupt reached U-Boot and later bounded commands returned at `IPQ6018#`.

The current safe physical boundary is:

```text
GAPD Pin 2 (router TX)      -> CH343 RXD
GAPD Pin 4 (ground)         -> CH343 GND
GAPD router RX              -> CH343 TXD (functionally verified)
CH343 VCC                   -> disconnected
```

Never connect CH343 VCC to the router. Do not move TXD between unidentified
pins while powered. The approved, gated transmit trigger has now produced the
`IPQ6018#` prompt; further writes still require an explicit command boundary.

## Receive-only Python capture

`scripts/uart/capture_uart.py` never calls a serial transmit API. Its serial
class additionally rejects `write`, `writelines`, and break transmission. Raw
bytes go to an ignored `artifacts/uart` path, while a timestamped and
automatically sanitized UTF-8 rendering goes to `logs/uart`.

Check that `COM8` exists, then start the logger before applying router power:

```powershell
[System.IO.Ports.SerialPort]::GetPortNames()
py -3 scripts\uart\capture_uart.py
```

Stop it with Ctrl+C after the boot log becomes quiet. Custom destinations and a
fixed capture interval are also supported:

```powershell
py -3 scripts\uart\capture_uart.py `
  --duration 120 `
  --raw-output artifacts\uart\stock-boot.log.raw `
  --text-output logs\uart\stock-boot.txt
```

The raw file is the evidence source. The text copy redacts common MAC-address,
serial-number, credential, token, URL-secret, and public-IP patterns. Review the
sanitized file manually before committing it because no automatic sanitizer can
recognize every vendor-specific secret.

An existing text capture can be sanitized separately:

```powershell
py -3 scripts\uart\sanitize_uart.py input.txt logs\uart\sanitized.txt
```

## PuTTY fallback

PuTTY can receive the same output using Connection type `Serial`, Serial line
`COM8`, Speed `115200`, Data bits `8`, Stop bits `1`, Parity `None`, and Flow
control `None`. Enable session logging to an ignored path under
`artifacts/uart`.

PuTTY is not logically receive-only: a keypress can request transmission. It is
acceptable only while the CH343 TXD wire remains physically disconnected. Do
not type into the PuTTY terminal, and sanitize any text copy before it is added
to Git.

## Gated U-Boot interrupt helper

`scripts/uart/interrupt_uboot.py` is separate from the receive-only logger. It
refuses to open COM8 unless `--arm-transmit` is supplied, transmits nothing
until the literal `Hit any key` text is received, then sends exactly one SPACE
byte. Success additionally requires the actual `IPQ6018#` prompt. Captures are
written without overwriting existing files.

The helper was run during an approved actual-router procd reboot. It captured
6,493 raw bytes, including U-Boot 2016.01-svn420 and `Boot act=0`, but this
build emitted no `Hit any key` text. It therefore sent zero bytes and stock
boot continued. The temporary `defenv` marker was deleted after boot and its
absence was verified.

The first approved early trigger sent one SPACE after the U-Boot version line,
before console-device initialization, and did not interrupt boot. A later test
used the stock `dwlee` marker `bootdelay_=1` and sent one SPACE only after the
exact `Err: serial@78B1000` console-ready signature. That combination reached
the actual `IPQ6018#` prompt.

At the prompt, `bootdelay_` was removed from RAM and its deletion was persisted
with one successful NAND environment save. Temporary U-Boot IP values were set
and read back without another save. No TFTP or boot command was sent. Blind key
spam and additional power cycles are not part of the plan.

LAN2 maps to the working U-Boot path observed as PHY1 at 1 Gbit/s full duplex.
A bounded RAM-only `netretry=no` ping completed and the prior value was restored
without `saveenv`. LAN1 had no carrier in the same U-Boot session.

The pinned initramfs was later transferred to `0x44000000`. `fileaddr`,
`filesize`, and whole-range CRC32 matched the host artifact. This APPSBL has no
live `hash` or `iminfo` command, so host/server SHA-256 plus U-Boot CRC32 form
the pre-execution integrity evidence. No `bootm` command has been sent.
