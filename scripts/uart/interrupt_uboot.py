#!/usr/bin/env python3
"""Send one space only after the GAPD U-Boot autoboot prompt is observed."""

from __future__ import annotations

import argparse
import sys
import time
from datetime import datetime
from pathlib import Path

try:
    import serial
except ImportError as exc:  # pragma: no cover
    raise SystemExit("pyserial is required: py -3 -m pip install pyserial") from exc

from capture_uart import TimestampedTextSink, local_timestamp


def default_paths() -> tuple[Path, Path]:
    stamp = datetime.now().astimezone().strftime("%Y-%m-%d-%H%M%S")
    return (
        Path("artifacts") / "uart" / f"{stamp}-uboot-interrupt.raw",
        Path("logs") / "uart" / f"{stamp}-uboot-interrupt.txt",
    )


def parse_args() -> argparse.Namespace:
    raw_default, text_default = default_paths()
    parser = argparse.ArgumentParser(
        description=(
            "Capture COM8 and transmit exactly one space only after the literal "
            "U-Boot 'Hit any key' prompt is received."
        )
    )
    parser.add_argument("--port", default="COM8")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--duration", type=float, default=30.0)
    parser.add_argument("--raw-output", type=Path, default=raw_default)
    parser.add_argument("--text-output", type=Path, default=text_default)
    parser.add_argument("--quiet", action="store_true")
    parser.add_argument(
        "--arm-transmit",
        action="store_true",
        help="required safety acknowledgement; without it the port is not opened",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if not args.arm_transmit:
        print("Refusing to open UART without --arm-transmit.", file=sys.stderr)
        return 2
    if args.duration <= 0 or args.duration > 120:
        print("--duration must be greater than 0 and at most 120 seconds.", file=sys.stderr)
        return 2

    args.raw_output.parent.mkdir(parents=True, exist_ok=True)
    args.text_output.parent.mkdir(parents=True, exist_ok=True)
    if args.raw_output.resolve() == args.text_output.resolve():
        print("Raw and text output paths must differ.", file=sys.stderr)
        return 2

    port = serial.Serial(
        port=None,
        baudrate=args.baud,
        bytesize=serial.EIGHTBITS,
        parity=serial.PARITY_NONE,
        stopbits=serial.STOPBITS_ONE,
        timeout=0.1,
        write_timeout=1,
        xonxoff=False,
        rtscts=False,
        dsrdtr=False,
    )
    port.dtr = False
    port.rts = False
    port.port = args.port

    transmitted = False
    prompt_seen = False
    rolling = bytearray()
    started = time.monotonic()
    try:
        with args.raw_output.open("xb") as raw_file, args.text_output.open(
            "x", encoding="utf-8", newline="\n"
        ) as text_file:
            text_file.write(
                f"{local_timestamp()} [CAPTURE-START] port={args.port} "
                f"baud={args.baud} direction=RX+gated-single-byte-TX\n"
            )
            text_file.flush()
            sink = TimestampedTextSink(text_file, not args.quiet)
            port.open()
            while time.monotonic() - started < args.duration:
                waiting = port.in_waiting
                data = port.read(min(max(waiting, 1), 4096))
                if not data:
                    continue
                raw_file.write(data)
                raw_file.flush()
                sink.feed(data)
                rolling.extend(data)
                if len(rolling) > 2048:
                    del rolling[:-2048]
                if not transmitted and b"Hit any key" in rolling:
                    written = port.write(b" ")
                    port.flush()
                    if written != 1:
                        raise RuntimeError(f"expected one transmitted byte, got {written}")
                    transmitted = True
                    text_file.write(f"{local_timestamp()} [TX] one SPACE byte after exact prompt\n")
                    text_file.flush()
                if transmitted and b"IPQ6018#" in rolling:
                    prompt_seen = True
                    break
            sink.finish()
            text_file.write(
                f"{local_timestamp()} [CAPTURE-END] transmitted={transmitted} "
                f"prompt_seen={prompt_seen}\n"
            )
            text_file.flush()
    except FileExistsError as exc:
        print(f"Refusing to overwrite existing capture: {exc.filename}", file=sys.stderr)
        return 2
    except serial.SerialException as exc:
        print(f"Serial error: {exc}", file=sys.stderr)
        return 3
    finally:
        if port.is_open:
            port.close()

    if not transmitted:
        print("No exact autoboot prompt was observed; no byte was transmitted.", file=sys.stderr)
        return 4
    if not prompt_seen:
        print("The stop byte was sent, but the IPQ6018 prompt was not observed.", file=sys.stderr)
        return 5
    print("U-Boot prompt observed after one gated SPACE byte.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
