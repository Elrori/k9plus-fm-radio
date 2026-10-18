"""Verify the raw bypass Ethernet/IP/UDP payload emitted by RTL."""

import struct
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
FRAME = ROOT / "build" / "sim_raw" / "raw_axis_frame.hex"


def checksum(data: bytes) -> int:
    words = struct.unpack(f"!{len(data)//2}H", data)
    total = sum(words)
    total = (total & 0xFFFF) + (total >> 16)
    total = (total & 0xFFFF) + (total >> 16)
    return (~total) & 0xFFFF


frame = bytes(int(line, 16) for line in FRAME.read_text().splitlines())
assert len(frame) == 1514, len(frame)
assert frame[:6] == b"\xff" * 6
assert frame[12:14] == b"\x08\x00"
ip = frame[14:34]
assert checksum(ip) == 0
assert struct.unpack_from("!H", ip, 2)[0] == 1500
assert struct.unpack("!HHHH", frame[34:42]) == (50002, 50002, 1480, 0)
payload = frame[42:]
header = struct.unpack_from("<4sBBHIIIQI", payload)
assert header == (b"K9RF", 1, 0, 32, 0, 96_800_000, 240_000_000, 0, 0), header
assert payload[32:] == bytes((i & 0xFF) for i in range(1440))
print("RAW_PACKET_PASS bytes=1514 payload=1472 raw=1440")
