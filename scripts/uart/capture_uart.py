#!/usr/bin/env python3
"""Receive-only UART capture for the GAPD-7500.

This program never calls a serial transmit API.  Its serial subclass also
rejects accidental calls to write(), writelines(), send_break(), or a request
to assert the break condition.
"""

from __future__ import annotations

import argparse
import sys
import time
from datetime import datetime
from pathlib import Path

try:
    import serial
except ImportError as exc:  # pragma: no cover - exercised only without pyserial
    raise SystemExit("pyserial is required: py -3 -m pip install pyserial") from exc

from sanitize_uart import sanitize_text


DEFAULT_PORT = "COM8"
DEFAULT_BAUD = 115200
READ_SIZE = 4096


def local_timestamp() -> str:
    return datetime.now().astimezone().isoformat(timespec="milliseconds")


class ReceiveOnlySerial(serial.Serial):
    """Serial port that refuses every explicit data/break transmit operation."""

    def write(self, data: bytes) -> int:  # type: ignore[override]
        raise RuntimeError("UART transmission is disabled by this receive-only logger")

    def writelines(self, lines) -> None:  # type: ignore[override]
        raise RuntimeError("UART transmission is disabled by this receive-only logger")

    def send_break(self, duration: float = 0.25) -> None:
        raise RuntimeError("UART break transmission is disabled")

    @serial.Serial.break_condition.setter
    def break_condition(self, level: bool) -> None:
        if level:
            raise RuntimeError("UART break transmission is disabled")
        serial.Serial.break_condition.fset(self, False)


class TimestampedTextSink:
    def __init__(self, output, console: bool, encoding: str = "utf-8") -> None:
        self.output = output
        self.console = console
        self.encoding = encoding
        self.pending = bytearray()

    def feed(self, data: bytes) -> None:
        self.pending.extend(data)
        while True:
            newline = self.pending.find(b"\n")
            if newline < 0:
                return
            line = bytes(self.pending[:newline]).rstrip(b"\r")
            del self.pending[: newline + 1]
            self._emit(line)

    def finish(self) -> None:
        if self.pending:
            self._emit(bytes(self.pending).rstrip(b"\r"))
            self.pending.clear()

    def _emit(self, raw_line: bytes) -> None:
        decoded = raw_line.decode(self.encoding, errors="backslashreplace")
        printable = "".join(
            char if char == "\t" or ord(char) >= 32 else f"\\x{ord(char):02x}"
            for char in decoded
        )
        line = f"{local_timestamp()} {sanitize_text(printable)}\n"
        self.output.write(line)
        self.output.flush()
        if self.console:
            sys.stdout.write(line)
            sys.stdout.flush()


def default_paths() -> tuple[Path, Path]:
    stamp = datetime.now().astimezone().strftime("%Y-%m-%d-%H%M%S")
    return (
        Path("artifacts") / "uart" / f"{stamp}-stock-boot.log.raw",
        Path("logs") / "uart" / f"{stamp}-stock-boot.txt",
    )


def parse_args() -> argparse.Namespace:
    raw_default, text_default = default_paths()
    parser = argparse.ArgumentParser(
        description="Receive-only GAPD-7500 UART logger (no serial writes)."
    )
    parser.add_argument("--port", default=DEFAULT_PORT)
    parser.add_argument("--baud", type=int, default=DEFAULT_BAUD)
    parser.add_argument("--raw-output", type=Path, default=raw_default)
    parser.add_argument("--text-output", type=Path, default=text_default)
    parser.add_argument("--encoding", default="utf-8")
    parser.add_argument(
        "--duration",
        type=float,
        default=None,
        help="stop after this many seconds; default is until Ctrl+C",
    )
    parser.add_argument("--quiet", action="store_true", help="do not mirror text to stdout")
    return parser.parse_args()


def open_receive_only(port: str, baud: int) -> ReceiveOnlySerial:
    receiver = ReceiveOnlySerial(
        port=None,
        baudrate=baud,
        bytesize=serial.EIGHTBITS,
        parity=serial.PARITY_NONE,
        stopbits=serial.STOPBITS_ONE,
        timeout=0.25,
        write_timeout=0,
        xonxoff=False,
        rtscts=False,
        dsrdtr=False,
    )
    # Establish inactive modem-control states before opening the device.
    receiver.dtr = False
    receiver.rts = False
    receiver.port = port
    receiver.open()
    return receiver


def main() -> int:
    args = parse_args()
    if args.duration is not None and args.duration <= 0:
        raise SystemExit("--duration must be greater than zero")

    args.raw_output.parent.mkdir(parents=True, exist_ok=True)
    args.text_output.parent.mkdir(parents=True, exist_ok=True)
    if args.raw_output.resolve() == args.text_output.resolve():
        raise SystemExit("raw and text output paths must be different")

    print("GAPD-7500 receive-only UART capture")
    print(f"Port: {args.port}; {args.baud} 8N1; flow control: none")
    print("TX policy: write, writelines, and break transmission are blocked")
    print(f"Raw:  {args.raw_output}")
    print(f"Text: {args.text_output}")

    receiver: ReceiveOnlySerial | None = None
    started = time.monotonic()
    try:
        receiver = open_receive_only(args.port, args.baud)
        with args.raw_output.open("xb") as raw_file, args.text_output.open(
            "x", encoding="utf-8", newline="\n"
        ) as text_file:
            text_file.write(
                f"{local_timestamp()} [CAPTURE-START] port={args.port} "
                f"baud={args.baud} format=8N1 flow=none direction=RX-only\n"
            )
            text_file.flush()
            sink = TimestampedTextSink(text_file, not args.quiet, args.encoding)
            try:
                while args.duration is None or time.monotonic() - started < args.duration:
                    waiting = receiver.in_waiting
                    data = receiver.read(min(max(waiting, 1), READ_SIZE))
                    if not data:
                        continue
                    raw_file.write(data)
                    raw_file.flush()
                    sink.feed(data)
            except KeyboardInterrupt:
                print("\nCapture interrupted by user.")
            finally:
                sink.finish()
                text_file.write(f"{local_timestamp()} [CAPTURE-END]\n")
                text_file.flush()
    except FileExistsError as exc:
        print(f"Refusing to overwrite existing capture: {exc.filename}", file=sys.stderr)
        return 2
    except serial.SerialException as exc:
        print(f"Serial error: {exc}", file=sys.stderr)
        return 3
    finally:
        if receiver is not None and receiver.is_open:
            receiver.close()

    print("Capture completed cleanly.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
