"""Check live 6 MS/s K9IQ continuity and sample range."""

from __future__ import annotations

import argparse
import socket
import struct
import time

import numpy as np


PORT = 50_003
HEADER = struct.Struct("<4sBBHIIIQI")
DATA_BYTES = 1440
SAMPLES = DATA_BYTES // 2


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bind", default="0.0.0.0")
    parser.add_argument("--count", type=int, default=2000)
    parser.add_argument("--timeout", type=float, default=3.0)
    args = parser.parse_args()
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 32 * 1024 * 1024)
    sock.bind((args.bind, PORT))
    sock.settimeout(args.timeout)
    expected_sequence = expected_sample = None
    missing = received = overflow = 0
    minimum, maximum = 127, -128
    started = time.monotonic()
    try:
        while received < args.count:
            payload, _ = sock.recvfrom(2048)
            if len(payload) != 32 + DATA_BYTES:
                continue
            magic, version, flags, header_bytes, sequence, station, rate, \
                sample_index, overflow = HEADER.unpack_from(payload)
            if (magic != b"K9IQ" or version != 2 or not flags & 2 or
                    header_bytes != 32 or rate != 6_000_000):
                continue
            if expected_sequence is not None:
                sequence_gap = (sequence - expected_sequence) & 0xFFFFFFFF
                sample_gap = max(0, sample_index - expected_sample) // SAMPLES
                if sequence_gap != sample_gap:
                    raise SystemExit(
                        "IQ_PROBE_FAIL sequence/sample-index disagreement: "
                        f"packets={sequence_gap} samples={sample_gap}"
                    )
                missing += sequence_gap
            values = np.frombuffer(payload, np.int8, offset=32)
            minimum = min(minimum, int(values.min()))
            maximum = max(maximum, int(values.max()))
            expected_sequence = (sequence + 1) & 0xFFFFFFFF
            expected_sample = sample_index + SAMPLES
            received += 1
    finally:
        sock.close()
    elapsed = time.monotonic() - started
    print(
        f"IQ_PROBE_PASS packets={received} missing={missing} overflow={overflow} "
        f"station={station} rate={rate} min={minimum} max={maximum} "
        f"packets_per_second={received/elapsed:.1f}"
    )


if __name__ == "__main__":
    main()
