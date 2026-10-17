"""Receive a few live K9FM datagrams and print integrity/audio statistics."""

from __future__ import annotations

import argparse
import socket
import statistics
import struct
import time


HEADER = struct.Struct("<4sBBHIIII")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--count", type=int, default=20)
    parser.add_argument("--timeout", type=float, default=10.0)
    args = parser.parse_args()

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind(("0.0.0.0", 50000))
    sock.settimeout(0.5)
    deadline = time.monotonic() + args.timeout
    sequences: list[int] = []
    samples: list[int] = []
    ones_values: list[float] = []
    transition_values: list[float] = []
    station = rate = status = flags = 0
    sender = None
    while len(sequences) < args.count and time.monotonic() < deadline:
        try:
            payload, sender = sock.recvfrom(2048)
        except socket.timeout:
            continue
        if len(payload) != HEADER.size + 512:
            continue
        magic, version, flags, count, sequence, station, rate, status = HEADER.unpack_from(payload)
        if magic != b"K9FM" or version != 1 or count != 256:
            continue
        sequences.append(sequence)
        samples.extend(struct.unpack_from("<256h", payload, HEADER.size))
        if flags & 1:
            ones_values.append((status >> 16) / 65535.0)
            transition_values.append((status & 0xffff) / 65535.0)
    sock.close()

    if not sequences:
        raise SystemExit("LIVE_PACKET_FAIL no valid UDP/50000 packet received")
    missing = sum(max(0, b - a - 1) for a, b in zip(sequences, sequences[1:]))
    mean = statistics.fmean(samples)
    rms = (statistics.fmean((sample - mean) ** 2 for sample in samples)) ** 0.5
    status_text = f"fpga_drops={status}"
    if flags & 1:
        ones = statistics.fmean(ones_values)
        transitions = statistics.fmean(transition_values)
        carrier_equivalent = transitions * 240e6 / 2
        status_text = (
            f"rf_ones_mean={ones:.4f} range={min(ones_values):.4f}..{max(ones_values):.4f} "
            f"rf_transitions_mean={transitions:.4f} "
            f"range={min(transition_values):.4f}..{max(transition_values):.4f} "
            f"transition_equiv={carrier_equivalent/1e6:.2f}MHz"
        )
    elif flags & 2:
        events = (status >> 8) & 0xff
        labels = ["dv", "55", "sfd", "etype_hi", "etype_ok", "udp", "magic", "tune"]
        seen = ",".join(label for bit, label in enumerate(labels) if events & (1 << bit)) or "none"
        status_text = (f"rx_frames={status & 0xff} max_index={(status >> 16) & 0xff} "
                       f"last_byte=0x{status >> 24:02x} seen={seen}")
    print(
        "LIVE_PACKET_PASS "
        f"sender={sender} packets={len(sequences)} seq={sequences[0]}..{sequences[-1]} "
        f"missing={missing} station={station}Hz rate={rate}Hz {status_text} "
        f"pcm_min={min(samples)} pcm_max={max(samples)} pcm_mean={mean:.1f} pcm_rms={rms:.1f}"
    )


if __name__ == "__main__":
    main()
