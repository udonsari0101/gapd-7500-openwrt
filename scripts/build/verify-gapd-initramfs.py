#!/usr/bin/env python3
"""Fail-closed verification for a GAPD-7500 initramfs FIT image."""

from __future__ import annotations

import argparse
import gzip
import hashlib
import struct
import sys
import zlib
from pathlib import Path


FDT_MAGIC = 0xD00DFEED
EXPECTED_CONFIG = "config@cp03-c1"
EXPECTED_LOAD = 0x41000000
DEFAULT_TRANSFER = 0x44000000
SAFE_RAM_END = 0x4A100000


def c_string(value: bytes) -> str:
    return value.split(b"\0", 1)[0].decode("ascii")


def parse_fdt(blob: bytes) -> dict[str, dict[str, bytes]]:
    if len(blob) < 40:
        raise ValueError("FDT is shorter than its header")

    header = struct.unpack_from(">10I", blob, 0)
    magic, total, struct_offset, strings_offset = header[:4]
    strings_size = header[8]
    if magic != FDT_MAGIC or total > len(blob):
        raise ValueError("invalid flattened device tree")

    strings = blob[strings_offset : strings_offset + strings_size]
    cursor = struct_offset
    stack: list[str] = []
    result: dict[str, dict[str, bytes]] = {}

    while True:
        token = struct.unpack_from(">I", blob, cursor)[0]
        cursor += 4
        if token == 1:
            end = blob.index(0, cursor)
            stack.append(blob[cursor:end].decode("ascii"))
            cursor = (end + 4) & ~3
            path = "/" + "/".join(part for part in stack if part)
            result.setdefault(path, {})
        elif token == 2:
            stack.pop()
        elif token == 3:
            length, name_offset = struct.unpack_from(">II", blob, cursor)
            cursor += 8
            value = blob[cursor : cursor + length]
            cursor = (cursor + length + 3) & ~3
            name_end = strings.index(0, name_offset)
            name = strings[name_offset:name_end].decode("ascii")
            path = "/" + "/".join(part for part in stack if part)
            result.setdefault(path, {})[name] = value
        elif token == 4:
            continue
        elif token == 9:
            return result
        else:
            raise ValueError(f"unknown FDT token {token} at 0x{cursor - 4:x}")


def cell(value: bytes) -> int:
    if len(value) != 4:
        raise ValueError(f"expected one 32-bit cell, got {len(value)} bytes")
    return struct.unpack(">I", value)[0]


def verify_hashes(tree: dict[str, dict[str, bytes]], image_path: str) -> None:
    payload = tree[image_path]["data"]
    children = sorted(path for path in tree if path.startswith(image_path + "/hash-"))
    algorithms: set[str] = set()
    for child in children:
        algorithm = c_string(tree[child]["algo"])
        expected = tree[child]["value"]
        if algorithm == "crc32":
            actual = struct.pack(">I", zlib.crc32(payload) & 0xFFFFFFFF)
        elif algorithm == "sha1":
            actual = hashlib.sha1(payload).digest()
        else:
            raise ValueError(f"unsupported FIT hash algorithm: {algorithm}")
        if actual != expected:
            raise ValueError(f"FIT hash mismatch at {child}")
        algorithms.add(algorithm)
        print(f"hash={child} algorithm={algorithm} match=true value={actual.hex()}")

    if algorithms != {"crc32", "sha1"}:
        raise ValueError(f"required FIT hashes are missing at {image_path}")


def verify(image: Path, transfer_address: int) -> None:
    blob = image.read_bytes()
    if len(blob) < 8 or struct.unpack_from(">I", blob, 4)[0] != len(blob):
        raise ValueError("FIT totalsize does not match the file length")
    tree = parse_fdt(blob)
    kernel_path = "/images/kernel-1"
    fdt_path = "/images/fdt-1"
    config_path = f"/configurations/{EXPECTED_CONFIG}"
    kernel = tree[kernel_path]
    dtb = tree[fdt_path]["data"]
    dtree = parse_fdt(dtb)

    default_config = c_string(tree["/configurations"]["default"])
    if default_config != EXPECTED_CONFIG:
        raise ValueError(f"unexpected default FIT config: {default_config}")
    if c_string(tree[config_path]["kernel"]) != "kernel-1":
        raise ValueError("FIT config does not select kernel-1")
    if c_string(tree[config_path]["fdt"]) != "fdt-1":
        raise ValueError("FIT config does not select fdt-1")
    if c_string(kernel["compression"]) != "gzip":
        raise ValueError("kernel payload is not gzip-compressed")
    if c_string(kernel["type"]) != "kernel":
        raise ValueError("FIT payload is not a kernel image")
    if c_string(kernel["arch"]) != "arm64" or c_string(kernel["os"]) != "linux":
        raise ValueError("FIT kernel architecture or OS is unexpected")

    compatible = [part.decode("ascii") for part in dtree["/"]["compatible"].split(b"\0") if part]
    if c_string(dtree["/"]["model"]) != "LG-GAPD-7500":
        raise ValueError("unexpected DT model")
    if compatible[:2] != ["lg,gapd-7500", "qcom,ipq6018"]:
        raise ValueError(f"unexpected DT compatible list: {compatible}")

    compressed = kernel["data"]
    uncompressed = gzip.decompress(compressed)
    load = cell(kernel["load"])
    entry = cell(kernel["entry"])
    destination_end = load + len(uncompressed)
    transfer_end = transfer_address + len(blob)
    overlaps = not (transfer_address >= destination_end or transfer_end <= load)

    if load != EXPECTED_LOAD or entry != EXPECTED_LOAD:
        raise ValueError(f"unexpected load/entry: 0x{load:x}/0x{entry:x}")
    if destination_end > SAFE_RAM_END:
        raise ValueError("uncompressed kernel leaves the observed safe RAM range")
    if transfer_address < EXPECTED_LOAD:
        raise ValueError("FIT transfer starts below the observed System RAM range")
    if destination_end > transfer_address:
        raise ValueError("uncompressed kernel reaches the TFTP buffer")
    if transfer_end > SAFE_RAM_END:
        raise ValueError("FIT transfer reaches the bootloader-reserved RAM boundary")
    if overlaps:
        raise ValueError("FIT transfer range overlaps the kernel destination")

    print(f"file={image}")
    print(f"file_bytes={len(blob)} sha256={hashlib.sha256(blob).hexdigest()}")
    print(f"config={default_config} model=LG-GAPD-7500")
    print(
        f"kernel_compressed_bytes={len(compressed)} "
        f"kernel_uncompressed_bytes={len(uncompressed)}"
    )
    print(f"load=0x{load:08x} entry=0x{entry:08x} destination_end=0x{destination_end:08x}")
    print(f"transfer_start=0x{transfer_address:08x} transfer_end=0x{transfer_end:08x}")
    print("memory_ranges_safe=true")
    verify_hashes(tree, kernel_path)
    verify_hashes(tree, fdt_path)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("image", type=Path)
    parser.add_argument("--transfer-address", type=lambda value: int(value, 0), default=DEFAULT_TRANSFER)
    args = parser.parse_args()
    try:
        verify(args.image, args.transfer_address)
    except (KeyError, OSError, EOFError, ValueError, struct.error, zlib.error) as error:
        print(f"verification failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
