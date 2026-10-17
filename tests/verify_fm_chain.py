"""Verify that the RTL chain recovers the 1 kHz modulation from 1-bit FM."""

from __future__ import annotations

from pathlib import Path

import numpy as np


ROOT = Path(__file__).resolve().parents[1]
PCM = ROOT / "build" / "sim_fm" / "pcm.txt"


def main() -> None:
    samples = np.loadtxt(PCM, dtype=np.float64)
    assert 500 <= samples.size <= 620, samples.size
    # Discard startup/filter transient, remove any residual DC, then window.
    samples = samples[120:]
    samples -= np.mean(samples)
    rms = float(np.sqrt(np.mean(samples * samples)))
    assert rms > 500.0, rms
    spectrum = np.abs(np.fft.rfft(samples * np.hanning(samples.size)))
    frequency = np.fft.rfftfreq(samples.size, 1.0 / 48000.0)
    spectrum[frequency < 300.0] = 0.0
    peak_index = int(np.argmax(spectrum))
    peak_hz = float(frequency[peak_index])
    mask = (frequency >= 800.0) & (frequency <= 1200.0)
    tone = float(np.max(spectrum[mask]))
    other = spectrum.copy()
    other[(frequency >= 700.0) & (frequency <= 1300.0)] = 0.0
    spur = float(np.max(other))
    assert 850.0 <= peak_hz <= 1150.0, peak_hz
    assert tone > spur * 2.0, (tone, spur)
    print(
        f"FM_CHAIN_PASS samples={samples.size + 120} "
        f"peak={peak_hz:.1f}Hz rms={rms:.1f} tone_spur={tone/spur:.1f}"
    )


if __name__ == "__main__":
    main()
