"""Generate deterministic NCO and 960 ksample/s channel-filter memories."""

from __future__ import annotations

import math
from pathlib import Path

import numpy as np


ROOT = Path(__file__).resolve().parents[1]
MEM = ROOT / "mem"


def write_twos_complement(path: Path, values: np.ndarray, bits: int) -> None:
    mask = (1 << bits) - 1
    width = (bits + 3) // 4
    path.write_text(
        "".join(f"{int(value) & mask:0{width}x}\n" for value in values),
        encoding="ascii",
    )


def lowpass(num_taps: int, cutoff_hz: float, sample_rate: float) -> np.ndarray:
    n = np.arange(num_taps, dtype=np.float64) - (num_taps - 1) / 2
    fc = cutoff_hz / sample_rate
    h = 2.0 * fc * np.sinc(2.0 * fc * n)
    h *= np.kaiser(num_taps, 7.5)
    h /= np.sum(h)
    return h


def main() -> None:
    MEM.mkdir(parents=True, exist_ok=True)
    phase = 2.0 * math.pi * np.arange(1024) / 1024.0
    sine = np.rint(np.sin(phase) * 32767.0).astype(np.int64)
    write_twos_complement(MEM / "sine_q15_1024.mem", sine, 16)

    # Weak-signal mono mode: a slightly narrower 170 kHz total IF bandwidth
    # rejects more adjacent-channel/threshold noise than the original 200 kHz.
    taps = lowpass(101, 85_000.0, 960_000.0)
    quantized = np.rint(taps * (1 << 18)).astype(np.int64)
    quantized[(len(quantized) - 1) // 2] += (1 << 18) - int(np.sum(quantized))
    write_twos_complement(MEM / "channel_fir_q18.mem", quantized, 20)

    print(f"generated {len(sine)} NCO entries")
    print(f"generated {len(quantized)} FIR taps, q18 sum={int(np.sum(quantized))}")


if __name__ == "__main__":
    main()
