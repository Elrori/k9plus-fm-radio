"""Compare the two possible IDDR sample orders using a committed raw capture."""

from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np


def measure(bits: np.ndarray, center_hz: float, swapped: bool) -> tuple[float, float]:
    if swapped:
        bits = bits.reshape(-1, 2)[:, ::-1].reshape(-1)
    count = len(bits) // 40 * 40
    samples = bits[:count].astype(np.float32) * 2.0 - 1.0
    phase = np.exp(-2j * np.pi * center_hz / 240_000_000 * np.arange(count))
    iq = (samples * phase).reshape(-1, 40).sum(axis=1)
    iq -= iq.mean()
    circularity = abs(np.mean(iq * iq)) / np.mean(abs(iq) ** 2)
    spectrum = abs(np.fft.fftshift(np.fft.fft(iq * np.hanning(len(iq)))))
    frequencies = np.fft.fftshift(np.fft.fftfreq(len(iq), 1 / 6_000_000))
    band = np.where((abs(frequencies) > 50_000) & (abs(frequencies) < 2_800_000))[0]
    peak = band[np.argmax(spectrum[band])]
    image = int(np.argmin(abs(frequencies + frequencies[peak])))
    rejection = 20 * np.log10((spectrum[peak] + 1e-12) / (spectrum[image] + 1e-12))
    return float(circularity), float(rejection)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("capture", type=Path)
    parser.add_argument("--center", type=float, default=94.8, help="MHz")
    parser.add_argument("--samples", type=int, default=4_000_000)
    args = parser.parse_args()
    packed = args.capture.read_bytes()[64:64 + (args.samples + 7) // 8]
    bits = np.unpackbits(np.frombuffer(packed, np.uint8), bitorder="little")[:args.samples]
    for swapped in (False, True):
        circularity, rejection = measure(bits, args.center * 1e6, swapped)
        print(f"swapped={swapped} circularity={circularity:.5f} peak_image_db={rejection:.2f}")


if __name__ == "__main__":
    main()
