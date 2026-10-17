"""Check simulated Ethernet/IP/UDP frame layout and CRC."""

from __future__ import annotations

import struct
import zlib
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
FRAME = ROOT / "build" / "sim_udp" / "frame.hex"


def internet_checksum(data: bytes) -> int:
    if len(data) & 1:
        data += b"\0"
    total = sum(struct.unpack(f"!{len(data)//2}H", data))
    total = (total & 0xFFFF) + (total >> 16)
    total = (total & 0xFFFF) + (total >> 16)
    return (~total) & 0xFFFF


def main() -> None:
    frame = bytes(int(line, 16) for line in FRAME.read_text().splitlines())
    assert len(frame) == 590, len(frame)
    assert frame[:7] == b"\x55" * 7 and frame[7] == 0xD5
    body, received_fcs = frame[8:-4], frame[-4:]
    expected_fcs = struct.pack("<I", zlib.crc32(body) & 0xFFFFFFFF)
    assert received_fcs == expected_fcs, (received_fcs.hex(), expected_fcs.hex())
    assert body[:6] == b"\xff" * 6
    assert body[12:14] == b"\x08\x00"
    ip = body[14:34]
    assert internet_checksum(ip) == 0
    assert struct.unpack_from("!H", ip, 2)[0] == 564
    udp = body[34:42]
    assert struct.unpack("!HHHH", udp) == (50000, 50000, 544, 0)
    payload = body[42:]
    magic, version, flags, count, sequence, tune, rate, drops = struct.unpack_from(
        "<4sBBHIIII", payload
    )
    assert (magic, version, flags, count, sequence, tune, rate, drops) == (
        b"K9FM", 1, 0, 256, 0, 100_100_000, 48_000, 0
    )
    samples = struct.unpack_from("<256h", payload, 24)
    assert samples == tuple(range(-128, 128))
    print("UDP_PACKET_PASS bytes=590 crc=" + received_fcs.hex())


if __name__ == "__main__":
    main()
