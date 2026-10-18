"""Capture lossless packed 240 MS/s 1-bit RF snapshots over UDP/50002.

The FPGA is returned to audio mode even when capture fails.  A capture is only
reported as PASS when packet sequence, sample index and FPGA FIFO overflow are
all clean.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import socket
import struct
import time
from datetime import datetime, timezone
from pathlib import Path

from radio_control import SAMPLE_RATE, open_control_socket, send_mode, send_tune, validate_frequency_hz


RAW_PORT = 50_002
PACKET_HEADER = struct.Struct("<4sBBHIIIQI")
FILE_HEADER = struct.Struct("<8sIIIIIIQQIIII")
RAW_BYTES_PER_PACKET = 1440
SAMPLES_PER_PACKET = RAW_BYTES_PER_PACKET * 8


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("frequency", type=float, help="FM frequency in MHz")
    parser.add_argument("--seconds", type=float, default=0.25,
                        help="minimum RF duration to save (default: 0.25)")
    parser.add_argument("--output", type=Path, required=True,
                        help="output .k9raw path")
    parser.add_argument("--bind", default="169.254.172.8",
                        help="IPv4 address of the wired adapter")
    parser.add_argument("--timeout", type=float, default=3.0,
                        help="seconds without a raw packet before failure")
    args = parser.parse_args()

    frequency_hz = round(args.frequency * 1_000_000)
    try:
        validate_frequency_hz(frequency_hz)
    except ValueError as error:
        raise SystemExit(str(error)) from error
    if args.seconds <= 0:
        raise SystemExit("--seconds must be positive")

    target_bytes = (round(args.seconds * SAMPLE_RATE) + 7) // 8
    target_packets = (target_bytes + RAW_BYTES_PER_PACKET - 1) // RAW_BYTES_PER_PACKET
    args.output.parent.mkdir(parents=True, exist_ok=True)

    rx = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    rx.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 16 * 1024 * 1024)
    rx.bind(("0.0.0.0", RAW_PORT))
    rx.settimeout(args.timeout)
    control = open_control_socket(args.bind)

    raw = bytearray()
    first_sequence = first_sample_index = None
    expected_sequence = expected_sample_index = None
    received_packets = missing_packets = 0
    last_overflow = 0
    started = time.monotonic()
    error = None
    try:
        send_mode(control, False)
        send_tune(control, frequency_hz)
        time.sleep(0.15)
        send_mode(control, True)

        while received_packets < target_packets:
            payload, _ = rx.recvfrom(2048)
            if len(payload) != 32 + RAW_BYTES_PER_PACKET:
                continue
            magic, version, flags, header_bytes, sequence, tuned_hz, rate, sample_index, overflow = \
                PACKET_HEADER.unpack_from(payload)
            if magic != b"K9RF" or version != 1 or header_bytes != 32:
                continue
            if tuned_hz != frequency_hz or rate != SAMPLE_RATE:
                continue
            if first_sequence is None:
                first_sequence = sequence
                first_sample_index = sample_index
                expected_sequence = sequence
                expected_sample_index = sample_index
            if sequence != expected_sequence:
                missing_packets += (sequence - expected_sequence) & 0xFFFFFFFF
                error = f"packet gap: expected {expected_sequence}, received {sequence}"
                break
            if sample_index != expected_sample_index:
                error = f"sample-index gap: expected {expected_sample_index}, received {sample_index}"
                break
            if flags & 1 or overflow != 0:
                error = f"FPGA raw FIFO overflow: {overflow} byte(s)"
                last_overflow = overflow
                break
            raw.extend(payload[32:])
            received_packets += 1
            last_overflow = overflow
            expected_sequence = (sequence + 1) & 0xFFFFFFFF
            expected_sample_index = sample_index + SAMPLES_PER_PACKET
    except socket.timeout:
        error = "timeout waiting for UDP/50002 K9RF packets"
    finally:
        send_mode(control, False)
        control.close()
        rx.close()

    if error is not None:
        if args.output.exists():
            args.output.unlink()
        raise SystemExit("RAW_CAPTURE_FAIL " + error)

    sample_count = len(raw) * 8
    header = FILE_HEADER.pack(
        b"K9RAW1\0\0", FILE_HEADER.size, SAMPLE_RATE, frequency_hz, 1,
        first_sequence, RAW_BYTES_PER_PACKET, first_sample_index, sample_count,
        received_packets, missing_packets, last_overflow, 0,
    )
    args.output.write_bytes(header + raw)
    digest = hashlib.sha256(header + raw).hexdigest().upper()
    metadata = {
        "format": "K9RAW1",
        "captured_utc": datetime.now(timezone.utc).isoformat(),
        "frequency_hz": frequency_hz,
        "sample_rate_hz": SAMPLE_RATE,
        "bit_order": "LSB-first; chronological; IDDR Q1 then Q2",
        "first_packet_sequence": first_sequence,
        "first_sample_index": first_sample_index,
        "sample_count": sample_count,
        "duration_seconds": sample_count / SAMPLE_RATE,
        "received_packets": received_packets,
        "missing_packets": missing_packets,
        "fifo_overflow_bytes": last_overflow,
        "sha256": digest,
    }
    sidecar = args.output.with_suffix(args.output.suffix + ".json")
    sidecar.write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    elapsed = time.monotonic() - started
    print(
        f"RAW_CAPTURE_PASS file={args.output} packets={received_packets} "
        f"samples={sample_count} duration={sample_count/SAMPLE_RATE:.6f}s "
        f"wall={elapsed:.3f}s sha256={digest}"
    )


if __name__ == "__main__":
    main()
