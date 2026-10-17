"""Create reproducible FM noise-reduction A/B WAV files using NumPy only."""

from __future__ import annotations

import argparse
import math
import wave
from pathlib import Path

import numpy as np


RATE = 48_000


def biquad(samples: np.ndarray, kind: str, cutoff: float, q_value: float) -> np.ndarray:
    omega = 2.0 * math.pi * cutoff / RATE
    cosine, sine = math.cos(omega), math.sin(omega)
    alpha = sine / (2.0 * q_value)
    a0 = 1.0 + alpha
    if kind == "lowpass":
        b0, b1, b2 = (1.0-cosine)/(2*a0), (1.0-cosine)/a0, (1.0-cosine)/(2*a0)
    else:
        b0, b1, b2 = (1.0+cosine)/(2*a0), -(1.0+cosine)/a0, (1.0+cosine)/(2*a0)
    a1, a2 = -2.0*cosine/a0, (1.0-alpha)/a0
    output = np.empty_like(samples)
    z1 = z2 = 0.0
    for index, value in enumerate(samples):
        result = b0*value + z1
        z1 = b1*value - a1*result + z2
        z2 = b2*value - a2*result
        output[index] = result
    return output


def bandlimit(samples: np.ndarray, highpass: float, lowpass: float) -> np.ndarray:
    output = biquad(samples, "highpass", highpass, 0.70710678)
    for q_value in (0.54119610, 1.30656296):
        output = biquad(output, "lowpass", lowpass, q_value)
    return output


def spectral_gate(samples: np.ndarray, strength: float = 1.25,
                  floor: float = 0.18) -> np.ndarray:
    size, hop = 2048, 512
    window = np.sqrt(np.hanning(size))
    starts = range(0, max(1, len(samples)-size+1), hop)
    frames = np.stack([np.fft.rfft(samples[start:start+size] * window) for start in starts])
    power = np.abs(frames) ** 2
    # Per-bin minimum statistics: stationary hiss is present in nearly every
    # frame, whereas speech/music components spend less time at one frequency.
    noise = np.percentile(power, 18.0, axis=0)
    gain = np.sqrt(np.maximum(1.0 - strength*noise[None, :]/(power+1e-12), floor**2))
    # Smooth across adjacent bins and time to avoid musical-noise speckles.
    gain[:, 1:-1] = (gain[:, :-2] + 2.0*gain[:, 1:-1] + gain[:, 2:]) / 4.0
    for index in range(1, len(gain)):
        gain[index] = 0.72*gain[index-1] + 0.28*gain[index]
    frames *= gain
    output = np.zeros(len(samples), dtype=np.float64)
    weight = np.zeros(len(samples), dtype=np.float64)
    for start, frame in zip(starts, frames):
        output[start:start+size] += np.fft.irfft(frame, size) * window
        weight[start:start+size] += window * window
    good = weight > 1e-8
    output[good] /= weight[good]
    return output


def write_wav(path: Path, samples: np.ndarray) -> None:
    peak = np.percentile(np.abs(samples), 99.99)
    if peak > 0:
        samples = samples * (0.92 * 32767.0 / peak)
    pcm = np.clip(np.rint(samples), -32768, 32767).astype("<i2")
    with wave.open(str(path), "wb") as output:
        output.setparams((1, 2, RATE, len(pcm), "NONE", "not compressed"))
        output.writeframes(pcm.tobytes())


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input")
    parser.add_argument("--prefix")
    args = parser.parse_args()
    source = Path(args.input)
    prefix = Path(args.prefix) if args.prefix else source.with_suffix("")
    with wave.open(str(source), "rb") as wav:
        if wav.getnchannels() != 1 or wav.getframerate() != RATE or wav.getsampwidth() != 2:
            raise SystemExit("input must be mono 48 kHz signed 16-bit PCM WAV")
        raw = np.frombuffer(wav.readframes(wav.getnframes()), "<i2").astype(np.float64)
    raw -= np.mean(raw)
    presets = {
        "wide": bandlimit(raw, 75.0, 6000.0),
        "clear": bandlimit(raw, 90.0, 4500.0),
    }
    presets["denoise"] = spectral_gate(presets["clear"])
    for name, samples in presets.items():
        path = Path(f"{prefix}_{name}.wav")
        write_wav(path, samples)
        print(f"WROTE {path} rms={np.sqrt(np.mean(samples**2)):.1f}")


if __name__ == "__main__":
    main()
