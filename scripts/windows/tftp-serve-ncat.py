#!/usr/bin/env python3
"""Serve one hash-pinned TFTP file after Ncat forwards the initial RRQ."""

from __future__ import annotations

import argparse
import hashlib
import os
import socket
import struct
import sys
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--file", type=Path, required=True)
    parser.add_argument("--requested-name", required=True)
    parser.add_argument("--expected-sha256", required=True)
    parser.add_argument("--expected-bytes", type=int, required=True)
    parser.add_argument("--expected-client", required=True)
    parser.add_argument("--timeout", type=float, default=3.0)
    parser.add_argument("--retries", type=int, default=10)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    payload = args.file.read_bytes()
    actual_hash = hashlib.sha256(payload).hexdigest()
    if len(payload) != args.expected_bytes:
        raise ValueError(
            f"size mismatch: got {len(payload)}, expected {args.expected_bytes}"
        )
    if actual_hash.lower() != args.expected_sha256.lower():
        raise ValueError("SHA-256 mismatch")

    request = os.read(0, 2048)
    if len(request) < 4 or request[:2] != b"\x00\x01":
        raise ValueError("expected TFTP RRQ")
    fields = request[2:].split(b"\x00")
    filename = fields[0].decode("ascii", errors="strict")
    mode = fields[1].decode("ascii", errors="strict").lower()
    if filename != args.requested_name or mode != "octet":
        raise ValueError(f"unexpected request name={filename!r} mode={mode!r}")

    remote_address = os.environ.get("NCAT_REMOTE_ADDR")
    remote_port = os.environ.get("NCAT_REMOTE_PORT")
    local_address = os.environ.get("NCAT_LOCAL_ADDR")
    if not remote_address or not remote_port or not local_address:
        raise ValueError("Ncat did not provide UDP peer/local address metadata")
    if remote_address != args.expected_client:
        raise ValueError(f"refusing unexpected TFTP client {remote_address}")
    peer = (remote_address, int(remote_port))

    offset = 0
    block = 1
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as transfer:
        transfer.bind((local_address, 0))
        transfer.settimeout(args.timeout)
        while True:
            chunk = payload[offset : offset + 512]
            packet = struct.pack("!HH", 3, block) + chunk
            retry = 0
            while True:
                transfer.sendto(packet, peer)
                try:
                    while True:
                        response, response_peer = transfer.recvfrom(2048)
                        if response_peer != peer or len(response) < 4:
                            continue
                        opcode, response_block = struct.unpack("!HH", response[:4])
                        if opcode == 5:
                            raise RuntimeError("TFTP client returned an error packet")
                        if opcode == 4 and response_block == block:
                            break
                    break
                except socket.timeout:
                    retry += 1
                    if retry > args.retries:
                        raise TimeoutError(f"no ACK for TFTP block {block}")
            if block % 4096 == 0:
                print(
                    f"tftp_progress bytes={min(offset + len(chunk), len(payload))}",
                    file=sys.stderr,
                    flush=True,
                )
            if len(chunk) < 512:
                break
            offset += len(chunk)
            block = (block + 1) & 0xFFFF

    print(
        f"tftp_complete bytes={len(payload)} sha256={actual_hash}",
        file=sys.stderr,
        flush=True,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
