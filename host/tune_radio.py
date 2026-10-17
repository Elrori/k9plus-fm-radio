"""Tune the K9+ receiver over broadcast UDP without rebuilding the FPGA.

One-shot mode:
    python host\\tune_radio.py 96.8

Interactive mode (up/down arrow keys):
    python host\\tune_radio.py --interactive [--freq 96.8]
    Up / Down        +/- 0.1 MHz
    Shift-Up / Shift-Down  +/- 0.5 MHz (Windows: PgUp/PgDn)
    q or Ctrl-C      quit
"""

from __future__ import annotations

import argparse
import socket
import struct
import sys
import time


SAMPLE_RATE = 240_000_000
PORT = 50_001
FM_MIN_MHZ = 88.0
FM_MAX_MHZ = 108.0
STEP_SMALL = 0.1
STEP_LARGE = 0.5


def _send(sock: socket.socket, bind_addr: str, frequency_hz: int) -> None:
    phase_increment = round(frequency_hz / SAMPLE_RATE * 2**32)
    payload = struct.pack("<4sII", b"K9TU", frequency_hz, phase_increment)
    for _ in range(8):
        sock.sendto(payload, ("255.255.255.255", PORT))
        time.sleep(0.02)


def _clamp(mhz: float) -> float:
    return max(FM_MIN_MHZ, min(FM_MAX_MHZ, round(mhz * 10) / 10))


def _interactive(start_mhz: float, bind_addr: str) -> None:
    try:
        import msvcrt
    except ImportError:
        sys.exit("Interactive mode requires Windows (msvcrt).")

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    sock.bind((bind_addr, 0))

    freq = _clamp(start_mhz)
    _send(sock, bind_addr, round(freq * 1_000_000))

    print(f"Interactive tuner  (Up/Down=0.1 MHz  PgUp/PgDn=0.5 MHz  q=quit)")
    print(f"Current: {freq:.1f} MHz", end="\r", flush=True)

    try:
        while True:
            ch = msvcrt.getwch()
            step = 0.0

            if ch in ("\xe0", "\x00"):
                # extended key prefix — read the scan code
                scan = msvcrt.getwch()
                if scan == "H":       # Up arrow
                    step = STEP_SMALL
                elif scan == "P":     # Down arrow
                    step = -STEP_SMALL
                elif scan == "I":     # PgUp (large step up)
                    step = STEP_LARGE
                elif scan == "Q":     # PgDn (large step down)
                    step = -STEP_LARGE
            elif ch in ("q", "Q", "\x03", "\x1b"):
                break

            if step != 0.0:
                freq = _clamp(freq + step)
                _send(sock, bind_addr, round(freq * 1_000_000))
                print(f"Current: {freq:.1f} MHz   ", end="\r", flush=True)
    except KeyboardInterrupt:
        pass
    finally:
        sock.close()
        print(f"\nStopped at {freq:.1f} MHz")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("frequency", type=float, nargs="?",
                        help="FM frequency in MHz (one-shot or interactive start)")
    parser.add_argument("--interactive", "-i", action="store_true",
                        help="enter interactive arrow-key tuning mode")
    parser.add_argument("--freq", type=float, default=96.8,
                        help="starting frequency for --interactive (default 96.8 MHz)")
    parser.add_argument("--bind", default="169.254.172.8",
                        help="source IPv4 on the wired adapter")
    args = parser.parse_args()

    if args.interactive:
        start = args.frequency if args.frequency is not None else args.freq
        _interactive(start, args.bind)
        return

    if args.frequency is None:
        parser.error("frequency argument required in one-shot mode")

    frequency_hz = round(args.frequency * 1_000_000)
    if not (FM_MIN_MHZ * 1_000_000 <= frequency_hz <= FM_MAX_MHZ * 1_000_000):
        raise SystemExit(f"frequency must be in {FM_MIN_MHZ}..{FM_MAX_MHZ} MHz")

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    sock.bind((args.bind, 0))
    _send(sock, args.bind, frequency_hz)
    sock.close()
    phase_increment = round(frequency_hz / SAMPLE_RATE * 2**32)
    print(f"TUNE_SENT frequency={frequency_hz}Hz phase_increment={phase_increment}")


if __name__ == "__main__":
    main()
