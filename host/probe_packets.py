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
    channel_avg_values: list[int] = []
    channel_peak_values: list[int] = []
    rx_debug_status = None
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
        elif flags & 2:
            rx_debug_status = status
        elif flags & 4:
            channel_avg_values.append((status >> 16) & 0xffff)
            channel_peak_values.append(status & 0xffff)
    sock.close()

    if not sequences:
        raise SystemExit("LIVE_PACKET_FAIL no valid UDP/50000 packet received")
    missing = sum(max(0, b - a - 1) for a, b in zip(sequences, sequences[1:]))
    mean = statistics.fmean(samples)
    rms = (statistics.fmean((sample - mean) ** 2 for sample in samples)) ** 0.5
    status_parts = []
    if ones_values:
        ones = statistics.fmean(ones_values)
        transitions = statistics.fmean(transition_values)
        carrier_equivalent = transitions * 240e6 / 2
        status_parts.append(
            f"rf_ones_mean={ones:.4f} range={min(ones_values):.4f}..{max(ones_values):.4f} "
            f"rf_transitions_mean={transitions:.4f} "
            f"range={min(transition_values):.4f}..{max(transition_values):.4f} "
            f"transition_equiv={carrier_equivalent/1e6:.2f}MHz"
        )
    if rx_debug_status is not None:
        events = (rx_debug_status >> 8) & 0xff
        labels = ["dv", "55", "sfd", "etype_hi", "etype_ok", "udp", "magic", "tune"]
        seen = ",".join(label for bit, label in enumerate(labels) if events & (1 << bit)) or "none"
        status_parts.append(f"rx_frames={rx_debug_status & 0xff} "
                            f"max_index={(rx_debug_status >> 16) & 0xff} "
                            f"last_byte=0x{rx_debug_status >> 24:02x} seen={seen}")
    if channel_avg_values:
        status_parts.append(f"channel_mag_avg={statistics.fmean(channel_avg_values):.1f} "
                            f"channel_mag_peak={max(channel_peak_values)}")
    status_text = "; ".join(status_parts) if status_parts else f"status={status} flags={flags}"
    print(
        "LIVE_PACKET_PASS "
        f"sender={sender} packets={len(sequences)} seq={sequences[0]}..{sequences[-1]} "
        f"missing={missing} station={station}Hz rate={rate}Hz {status_text} "
        f"pcm_min={min(samples)} pcm_max={max(samples)} pcm_mean={mean:.1f} pcm_rms={rms:.1f}"
    )


if __name__ == "__main__":
    main()
