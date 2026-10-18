"""Verify the simulated K9IQ Ethernet/IPv4/UDP frame."""

from __future__ import annotations

import struct
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
FRAME = ROOT / "build" / "sim_iq" / "iq_axis_frame.hex"
HEADER = struct.Struct("<4sBBHIIIQI")


def checksum(data: bytes) -> int:
    if len(data) & 1:
        data += b"\0"
    total = sum((data[index] << 8) | data[index + 1]
                for index in range(0, len(data), 2))
    while total >> 16:
        total = (total & 0xFFFF) + (total >> 16)
    return (~total) & 0xFFFF


def main() -> None:
    frame = bytes(int(line, 16) for line in FRAME.read_text().splitlines())
    assert len(frame) == 1514, len(frame)
    assert frame[:6] == b"\xff" * 6
    assert frame[12:14] == b"\x08\x00"
    ip = frame[14:34]
    assert int.from_bytes(ip[2:4], "big") == 1500
    assert checksum(ip) == 0
    udp = frame[34:42]
    assert int.from_bytes(udp[0:2], "big") == 50003
    assert int.from_bytes(udp[2:4], "big") == 50003
    assert int.from_bytes(udp[4:6], "big") == 1480
    payload = frame[42:]
    magic, version, flags, header_bytes, sequence, tuned_hz, rate, \
        sample_index, overflow = HEADER.unpack_from(payload)
    assert (magic, version, flags, header_bytes) == (b"K9IQ", 2, 2, 32)
    assert (sequence, tuned_hz, rate, sample_index, overflow) == \
        (0, 96_800_000, 6_000_000, 0, 0)
    assert payload[32:] == bytes(index & 0xFF for index in range(1440))
    print("IQ_PACKET_PASS bytes=1514 iq_samples=720 format=I8/Q8 rate=6000000")


if __name__ == "__main__":
    main()
