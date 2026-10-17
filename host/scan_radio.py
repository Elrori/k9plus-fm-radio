"""Tune a frequency range and rank received mono-FM audio quality."""

from __future__ import annotations

import argparse
import socket
import struct
import time

import numpy as np


HEADER = struct.Struct("<4sBBHIIII")
RATE = 48_000


def send_tune(sock: socket.socket, mhz: float) -> int:
    hz = round(mhz * 1_000_000)
    phase = round(hz / 240_000_000 * 2**32)
    packet = struct.pack("<4sII", b"K9TU", hz, phase)
    for _ in range(4):
        sock.sendto(packet, ("255.255.255.255", 50_001))
    return hz


def capture(sock: socket.socket, station: int, seconds: float) -> np.ndarray:
    end = time.monotonic() + seconds
    blocks = []
    while time.monotonic() < end:
        try:
            payload, _ = sock.recvfrom(2048)
        except socket.timeout:
            continue
        if len(payload) != HEADER.size + 512:
            continue
        magic, version, _flags, count, _seq, tuned, rate, _status = HEADER.unpack_from(payload)
        if magic == b"K9FM" and version == 1 and count == 256 and rate == RATE and tuned == station:
            blocks.append(np.frombuffer(payload, "<i2", count=256, offset=HEADER.size).copy())
    return np.concatenate(blocks).astype(np.float64) if blocks else np.empty(0)


def metrics(samples: np.ndarray) -> tuple[float, float, float, float]:
    samples -= np.mean(samples)
    rms = float(np.sqrt(np.mean(samples * samples)))
    n = min(32768, 1 << (len(samples).bit_length() - 1))
    spectrum = np.abs(np.fft.rfft(samples[-n:] * np.hanning(n))) ** 2
    hz = np.fft.rfftfreq(n, 1 / RATE)
    def power(low: float, high: float) -> float:
        return float(np.sum(spectrum[(hz >= low) & (hz < high)])) + 1e-20
    voice = 10 * np.log10(power(150, 4500))
    hiss = 10 * np.log10(power(7000, 15000))
    clarity = voice - hiss
    crest = float(np.max(np.abs(samples)) / max(rms, 1.0))
    score = clarity + min(12.0, 20 * np.log10(max(rms, 1.0) / 500.0))
    return rms, clarity, crest, score


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--start", type=float, required=True)
    parser.add_argument("--stop", type=float, required=True)
    parser.add_argument("--step", type=float, default=0.05)
    parser.add_argument("--seconds", type=float, default=0.8)
    parser.add_argument("--bind", default="169.254.172.8")
    args = parser.parse_args()

    tune = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    tune.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    tune.bind((args.bind, 0))
    audio = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    audio.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    audio.bind(("0.0.0.0", 50_000))
    audio.settimeout(0.1)

    results = []
    frequencies = np.arange(args.start, args.stop + args.step / 2, args.step)
    for mhz in frequencies:
        station = send_tune(tune, float(mhz))
        time.sleep(0.12)
        audio.setblocking(False)
        while True:
            try:
                audio.recvfrom(2048)
            except BlockingIOError:
                break
        audio.settimeout(0.1)
        samples = capture(audio, station, args.seconds)
        if len(samples):
            result = (float(mhz),) + metrics(samples)
            results.append(result)
            print(f"{mhz:7.3f} MHz rms={result[1]:7.1f} clarity={result[2]:6.2f}dB "
                  f"crest={result[3]:4.2f} score={result[4]:6.2f}")
        else:
            print(f"{mhz:7.3f} MHz no-data")
    audio.close()
    tune.close()
    if results:
        best = max(results, key=lambda row: row[4])
        print(f"SCAN_BEST frequency={best[0]:.3f}MHz score={best[4]:.2f}")


if __name__ == "__main__":
    main()
