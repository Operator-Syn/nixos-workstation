#!/usr/bin/env python3
"""Pure helpers for the privileged Hermes audit report collector."""

from __future__ import annotations

import re
import sys


MAX_SECTION_BYTES = 65536
PRIVATE_KEY = re.compile(
    r"-----BEGIN ([A-Z0-9 ]+ )?PRIVATE KEY-----.*?-----END ([A-Z0-9 ]+ )?PRIVATE KEY-----",
    re.IGNORECASE | re.DOTALL,
)
SECRET_ASSIGNMENT = re.compile(
    r"(?i)(\b(?:bearer|token|password|passwd|api[_-]?key)\b\s*[=:]\s*[\"']?)([^\s,\"'}]+)"
)
SECRET_JSON = re.compile(
    r"(?i)(\"(?:bearer|token|password|passwd|api[_-]?key)\"\s*:\s*\")([^\"]*)(\")"
)


def redact_text(text: str) -> str:
    text = PRIVATE_KEY.sub("[REDACTED PRIVATE KEY BLOCK]", text)
    text = SECRET_ASSIGNMENT.sub(r"\1[REDACTED]", text)
    return SECRET_JSON.sub(r"\1[REDACTED]\3", text)


def bound_text(text: str, limit: int = MAX_SECTION_BYTES) -> str:
    encoded = text.encode("utf-8", errors="replace")
    if len(encoded) <= limit:
        return text
    return encoded[:limit].decode("utf-8", errors="ignore")


def redact_stream() -> int:
    sys.stdout.write(redact_text(sys.stdin.read()))
    return 0


def bound_stream() -> int:
    remaining = MAX_SECTION_BYTES
    emitted = bytearray()
    while chunk := sys.stdin.buffer.read(8192):
        if remaining > 0:
            emitted.extend(chunk[:remaining])
            remaining -= len(chunk[:remaining])
    sys.stdout.buffer.write(bytes(emitted).decode("utf-8", errors="ignore").encode("utf-8"))
    return 0


def main() -> int:
    command = sys.argv[1]
    if command == "redact":
        return redact_stream()
    if command == "bound":
        return bound_stream()
    raise SystemExit(f"unknown command: {command}")


if __name__ == "__main__":
    raise SystemExit(main())
