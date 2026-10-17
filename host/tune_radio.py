"""Tune the K9+ receiver over broadcast UDP without rebuilding the FPGA."""

from __future__ import annotations

import argparse
import socket
import struct
import time


SAMPLE_RATE = 240_000_000
PORT = 50_001


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("frequency", type=float, help="FM frequency in MHz")
    parser.add_argument("--bind", default="169.254.172.8",
                        help="source IPv4 on the wired adapter")
    args = parser.parse_args()
    frequency_hz = round(args.frequency * 1_000_000)
    if not 88_000_000 <= frequency_hz <= 108_000_000:
        raise SystemExit("frequency must be in 88..108 MHz")
    phase_increment = round(frequency_hz / SAMPLE_RATE * 2**32)
    payload = struct.pack("<4sII", b"K9TU", frequency_hz, phase_increment)
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    sock.bind((args.bind, 0))
    for _ in range(8):
        sock.sendto(payload, ("255.255.255.255", PORT))
        time.sleep(0.02)
    sock.close()
    print(f"TUNE_SENT frequency={frequency_hz}Hz phase_increment={phase_increment}")


if __name__ == "__main__":
    main()
