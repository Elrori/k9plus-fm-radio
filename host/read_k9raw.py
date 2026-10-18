"""Inspect or unpack a K9RAW1 packed 1-bit capture."""

from __future__ import annotations

import argparse
import struct
from pathlib import Path

import numpy as np


FILE_HEADER = struct.Struct("<8sIIIIIIQQIIII")


def load(path: Path) -> tuple[dict[str, int], np.ndarray]:
    blob = path.read_bytes()
    fields = FILE_HEADER.unpack_from(blob)
    if fields[0] != b"K9RAW1\0\0" or fields[1] != FILE_HEADER.size:
        raise ValueError("not a K9RAW1 capture")
    header = {
        "sample_rate_hz": fields[2], "frequency_hz": fields[3], "flags": fields[4],
        "first_sequence": fields[5], "packet_data_bytes": fields[6],
        "first_sample_index": fields[7], "sample_count": fields[8],
        "received_packets": fields[9], "missing_packets": fields[10],
        "fifo_overflow_bytes": fields[11],
    }
    packed = np.frombuffer(blob, dtype=np.uint8, offset=fields[1])
    bits = np.unpackbits(packed, bitorder="little")[: fields[8]]
    return header, bits


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("capture", type=Path)
    parser.add_argument("--npy", type=Path, help="optional unpacked uint8 NumPy output")
    args = parser.parse_args()
    header, bits = load(args.capture)
    print(header)
    print(f"ones={bits.mean():.6f} transitions={np.mean(bits[1:] != bits[:-1]):.6f}")
    if args.npy:
        np.save(args.npy, bits)


if __name__ == "__main__":
    main()
