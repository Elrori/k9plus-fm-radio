"""Compare weak-signal FM DSP choices on a K9RAW1 hardware capture.

This is intentionally NumPy-only so it can run in the same environment as the
host utilities.  It models the important floating-point equivalents of the
FPGA path: quadrature mixing, CIC3 decimation to 960 kS/s, channel FIR,
correlation-vector decimation to 48 kS/s, and phase discrimination.
"""

from __future__ import annotations

import argparse
import json
import math
import struct
from pathlib import Path

import numpy as np


HEADER = struct.Struct("<8sIIIIIIQQIIII")


class MovingSum:
    def __init__(self, length: int) -> None:
        self.length = length
        self.history = np.zeros(length - 1, dtype=np.complex128)

    def process(self, values: np.ndarray) -> np.ndarray:
        joined = np.concatenate((self.history, values))
        prefix = np.empty(joined.size + 1, dtype=np.complex128)
        prefix[0] = 0.0
        np.cumsum(joined, out=prefix[1:])
        output = prefix[self.length:] - prefix[:-self.length]
        self.history = joined[-(self.length - 1):].copy()
        return output


def lowpass(taps: int, cutoff_hz: float, rate_hz: float) -> np.ndarray:
    n = np.arange(taps, dtype=np.float64) - (taps - 1) / 2
    h = 2.0 * cutoff_hz / rate_hz * np.sinc(2.0 * cutoff_hz / rate_hz * n)
    h *= np.kaiser(taps, 7.5)
    return h / np.sum(h)


def load_header(path: Path) -> tuple[dict[str, int], int]:
    with path.open("rb") as source:
        fields = HEADER.unpack(source.read(HEADER.size))
    if fields[0] != b"K9RAW1\0\0" or fields[1] != HEADER.size:
        raise ValueError("not a K9RAW1 capture")
    return {
        "sample_rate_hz": fields[2],
        "sample_count": fields[8],
    }, fields[1]


def wideband_metrics(path: Path) -> dict[str, object]:
    """Measure blockers without materializing the whole 60 Msnapshot."""
    header, offset = load_header(path)
    rate = header["sample_rate_hz"]
    fft_size = 262_144
    byte_size = fft_size // 8
    window = np.hanning(fft_size)
    accumulated = np.zeros(fft_size // 2 + 1, dtype=np.float64)
    blocks = 0
    with path.open("rb") as source:
        source.seek(offset)
        while True:
            packed = source.read(byte_size)
            if len(packed) != byte_size:
                break
            values = np.unpackbits(np.frombuffer(packed, np.uint8), bitorder="little")
            values = values.astype(np.float64) * 2.0 - 1.0
            values -= np.mean(values)
            spectrum = np.fft.rfft(values * window)
            accumulated += np.abs(spectrum) ** 2
            blocks += 1
    power = accumulated / blocks
    frequency = np.fft.rfftfreq(fft_size, 1.0 / rate)
    fm_mask = (frequency >= 88e6) & (frequency <= 108e6)
    reference = float(np.median(power[fm_mask]))
    order = np.argsort(power[fm_mask])[::-1]
    fm_indices = np.flatnonzero(fm_mask)
    peaks: list[dict[str, float]] = []
    for index in fm_indices[order]:
        if all(abs(frequency[index] - item["frequency_hz"]) > 150e3 for item in peaks):
            peaks.append({
                "frequency_hz": float(frequency[index]),
                "peak_over_median_bin_db": float(10.0 * np.log10(power[index] / reference)),
            })
        if len(peaks) == 8:
            break
    channels: dict[str, float] = {}
    for center_mhz in (94.7, 95.0, 96.0, 96.8):
        center = center_mhz * 1e6
        channel = (frequency > center - 100e3) & (frequency < center + 100e3)
        guard = ((frequency > center - 500e3) & (frequency < center + 500e3) & ~channel)
        channels[f"{center_mhz:.3f}_mhz"] = float(10.0 * np.log10(
            np.sum(power[channel]) / (np.mean(power[guard]) * np.count_nonzero(channel))
        ))
    return {
        "fft_resolution_hz": float(rate / fft_size),
        "averaged_blocks": blocks,
        "peaks": peaks,
        "channel_power_over_local_guard_db": channels,
    }


def downconvert(path: Path, frequency_hz: float, seconds: float) -> np.ndarray:
    header, offset = load_header(path)
    rate = header["sample_rate_hz"]
    count = min(header["sample_count"], int(seconds * rate))
    byte_count = (count + 7) // 8
    stages = [MovingSum(250), MovingSum(250), MovingSum(250)]
    outputs: list[np.ndarray] = []
    sample_index = 0
    decimation_phase = 249
    chunk_bytes = 1 << 17
    oscillator_step = np.exp(-2j * np.pi * frequency_hz / rate)
    with path.open("rb") as source:
        source.seek(offset)
        remaining = byte_count
        while remaining:
            packed = np.frombuffer(source.read(min(chunk_bytes, remaining)), np.uint8)
            remaining -= packed.size
            bits = np.unpackbits(packed, bitorder="little")
            if sample_index + bits.size > count:
                bits = bits[:count - sample_index]
            rf = bits.astype(np.float64) * 2.0 - 1.0
            local_phase = oscillator_step ** sample_index
            oscillator = local_phase * np.power(oscillator_step, np.arange(rf.size))
            filtered = rf * oscillator
            for stage in stages:
                filtered = stage.process(filtered)
            first = (decimation_phase - sample_index) % 250
            outputs.append(filtered[first::250])
            sample_index += rf.size
    return np.concatenate(outputs)


def moving_sum(values: np.ndarray, length: int) -> np.ndarray:
    prefix = np.empty(values.size + 1, dtype=np.complex128)
    prefix[0] = 0.0
    np.cumsum(values, out=prefix[1:])
    return prefix[length:] - prefix[:-length]


def discriminate(iq: np.ndarray, clip_radians: float | None) -> np.ndarray:
    correlation = iq[1:] * np.conj(iq[:-1])
    # CIC3, decimate 20.  Discarding startup and choosing the exact phase do
    # not affect the steady-state comparison made here.
    for _ in range(3):
        correlation = moving_sum(correlation, 20)
    phase = np.angle(correlation[19::20])
    if clip_radians is not None:
        phase = np.clip(phase, -clip_radians, clip_radians)
    return phase


def metrics(samples: np.ndarray) -> dict[str, float]:
    samples = samples[200:] - np.mean(samples[200:])
    rms = float(np.sqrt(np.mean(samples * samples)))
    abs_samples = np.abs(samples)
    return {
        "rms_rad": rms,
        "peak_rad": float(np.max(abs_samples)),
        "p95_rad": float(np.percentile(abs_samples, 95)),
        "p99_rad": float(np.percentile(abs_samples, 99)),
        "crest_db": float(20.0 * np.log10(np.max(abs_samples) / (rms + 1e-30))),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("capture", type=Path)
    parser.add_argument("--seconds", type=float, default=0.10)
    parser.add_argument("--frequencies", default="94.7,95.0,96.0,96.8")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()

    report: dict[str, object] = {
        "capture": str(args.capture),
        "seconds": args.seconds,
        "note": "Floating-point screening model; dB values are same-input A/B, not RF sensitivity claims.",
        "stations": {},
    }
    print("measuring wideband blockers", flush=True)
    report["wideband"] = wideband_metrics(args.capture)
    for frequency_mhz in (float(item) for item in args.frequencies.split(",")):
        print(f"downconverting {frequency_mhz:.3f} MHz", flush=True)
        baseband = downconvert(args.capture, frequency_mhz * 1e6, args.seconds)
        station: dict[str, object] = {}
        for bandwidth_khz in (85, 75, 65):
            taps = lowpass(101, bandwidth_khz * 1000.0, 960_000.0)
            iq = np.convolve(baseband, taps, mode="valid")
            baseline = discriminate(iq, None)
            base_metrics = metrics(baseline)
            variants: dict[str, object] = {"unlimited": base_metrics}
            for limit in (0.75, 0.65, 0.55):
                limited = discriminate(iq, limit)
                item = metrics(limited)
                item["rms_change_db"] = 20.0 * math.log10(
                    item["rms_rad"] / base_metrics["rms_rad"]
                )
                variants[f"limit_{limit:.2f}_rad"] = item
            station[f"channel_{bandwidth_khz}_khz"] = variants
        report["stations"][f"{frequency_mhz:.3f}_mhz"] = station

    rendered = json.dumps(report, indent=2, ensure_ascii=False)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(rendered + "\n", encoding="utf-8")
    print(rendered)


if __name__ == "__main__":
    main()
