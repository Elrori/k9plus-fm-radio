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

from radio_control import MAX_TUNE_HZ, open_control_socket, send_mode, send_tune, validate_frequency_hz


STEP_SMALL = 0.1
STEP_LARGE = 0.5


def _send(sock: socket.socket, bind_addr: str, frequency_hz: int) -> None:
    del bind_addr
    send_tune(sock, frequency_hz)


def _clamp_to_protocol(mhz: float) -> float:
    return max(0.0, min(MAX_TUNE_HZ / 1_000_000, round(mhz * 10) / 10))


def _interactive(start_mhz: float, bind_addr: str) -> None:
    try:
        import msvcrt
    except ImportError:
        sys.exit("Interactive mode requires Windows (msvcrt).")

    sock = open_control_socket(bind_addr)

    freq = _clamp_to_protocol(start_mhz)
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
                freq = _clamp_to_protocol(freq + step)
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
    parser.add_argument("--mode", choices=("audio", "bypass"),
                        help="also switch the Ethernet output mode")
    args = parser.parse_args()

    if args.interactive:
        start = args.frequency if args.frequency is not None else args.freq
        _interactive(start, args.bind)
        return

    if args.frequency is None and args.mode is None:
        parser.error("frequency argument required in one-shot mode")

    sock = open_control_socket(args.bind)
    frequency_hz = None
    phase_increment = None
    if args.frequency is not None:
        frequency_hz = round(args.frequency * 1_000_000)
        try:
            validate_frequency_hz(frequency_hz)
        except ValueError as error:
            raise SystemExit(str(error)) from error
        phase_increment = send_tune(sock, frequency_hz)
    if args.mode is not None:
        send_mode(sock, args.mode == "bypass")
    sock.close()
    if frequency_hz is not None:
        print(f"TUNE_SENT frequency={frequency_hz}Hz phase_increment={phase_increment}")
    if args.mode is not None:
        print(f"MODE_SENT mode={args.mode}")


if __name__ == "__main__":
    main()
