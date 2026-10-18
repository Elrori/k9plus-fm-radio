"""Integrity gate for committed K9RAW1 hardware benchmark captures."""

from __future__ import annotations

import hashlib
import json
import struct
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CAPTURES = ROOT / "captures" / "raw_2026-10-18"
HEADER = struct.Struct("<8sIIIIIIQQIIII")


def main() -> None:
    checked = 0
    for sidecar in sorted(CAPTURES.glob("*.k9raw.json")):
        metadata = json.loads(sidecar.read_text(encoding="utf-8"))
        capture = Path(str(sidecar)[:-5])
        blob = capture.read_bytes()
        fields = HEADER.unpack_from(blob)
        digest = hashlib.sha256(blob).hexdigest().upper()
        assert fields[0] == b"K9RAW1\0\0" and fields[1] == HEADER.size
        assert fields[2] == 240_000_000
        assert fields[8] == (len(blob) - HEADER.size) * 8
        assert fields[10] == 0 and fields[11] == 0
        assert metadata["sample_count"] == fields[8]
        assert metadata["sha256"] == digest
        checked += 1
    assert checked == 1, checked
    print(f"RAW_CAPTURE_SET_PASS files={checked}")


if __name__ == "__main__":
    main()
