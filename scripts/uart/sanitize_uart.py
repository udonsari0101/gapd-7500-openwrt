#!/usr/bin/env python3
"""Sanitize device-specific or secret values from UART text logs."""

from __future__ import annotations

import argparse
import ipaddress
import re
from pathlib import Path


MAC_RE = re.compile(r"(?i)(?<![0-9a-f])(?:[0-9a-f]{2}[:-]){5}[0-9a-f]{2}(?![0-9a-f])")
LABELED_MAC_RE = re.compile(
    r"(?i)(\b(?:base\s*)?(?:mac|macaddr|hwaddr)(?:\s+address)?\s*[:=]\s*)"
    r"[0-9a-f]{12}\b"
)
SECRET_RE = re.compile(
    r"(?i)(\b(?:password|passwd|passphrase|psk|token|secret|credential|"
    r"authorization|cookie|session(?:id)?|serial(?:\s*(?:number|no\.?))?|sn)"
    r"\s*[:=]\s*)([^\s,;&#]+)"
)
URL_USERINFO_RE = re.compile(r"(?i)(https?://)([^/@\s:]+):([^/@\s]+)@")
URL_SECRET_QUERY_RE = re.compile(
    r"(?i)([?&](?:token|key|secret|password|passwd|session(?:id)?|auth)=)[^&#\s]+"
)
IPV4_RE = re.compile(
    r"(?<![0-9.])(?:25[0-5]|2[0-4]\d|1?\d?\d)"
    r"(?:\.(?:25[0-5]|2[0-4]\d|1?\d?\d)){3}(?![0-9.])"
)


def _redact_public_ipv4(match: re.Match[str]) -> str:
    value = match.group(0)
    address = ipaddress.ip_address(value)
    if (
        address.is_private
        or address.is_loopback
        or address.is_link_local
        or address.is_multicast
        or address.is_reserved
        or address.is_unspecified
    ):
        return value
    return "<REDACTED-PUBLIC-IP>"


def sanitize_text(text: str) -> str:
    """Return text with common UART-log secrets replaced."""

    text = MAC_RE.sub("<REDACTED-MAC>", text)
    text = LABELED_MAC_RE.sub(r"\1<REDACTED-MAC>", text)
    text = SECRET_RE.sub(r"\1<REDACTED>", text)
    text = URL_USERINFO_RE.sub(r"\1<REDACTED>:<REDACTED>@", text)
    text = URL_SECRET_QUERY_RE.sub(r"\1<REDACTED>", text)
    return IPV4_RE.sub(_redact_public_ipv4, text)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Create a sanitized UTF-8 copy of a UART text log."
    )
    parser.add_argument("input", type=Path, help="source text log")
    parser.add_argument("output", type=Path, help="sanitized destination")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    source = args.input.read_text(encoding="utf-8", errors="backslashreplace")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(sanitize_text(source), encoding="utf-8", newline="\n")
    print(f"Sanitized log written to {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
