"""Measure repeatable noise/profile changes on 48 kHz K9+ WAV captures."""

from __future__ import annotations

import argparse
import json
import math
import sys
import wave
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "host"))
from enhance_audio import bandlimit, spectral_gate  # noqa: E402


def read_wav(path: Path) -> np.ndarray:
    with wave.open(str(path), "rb") as source:
        if source.getnchannels() != 1 or source.getframerate() != 48_000:
            raise ValueError(f"{path}: expected mono 48 kHz WAV")
        values = np.frombuffer(source.readframes(source.getnframes()), "<i2").astype(float)
    return values - np.mean(values)


def rms(values: np.ndarray) -> float:
    return float(np.sqrt(np.mean(values * values)))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("noise", type=Path, help="quiet-carrier/noise reference WAV")
    parser.add_argument("program", type=Path, nargs="+", help="program WAV capture(s)")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()

    sources = {"noise": read_wav(args.noise)}
    sources.update({path.stem: read_wav(path) for path in args.program})
    processed: dict[str, dict[str, np.ndarray]] = {}
    for name, values in sources.items():
        clear = bandlimit(values, 90.0, 4500.0)
        processed[name] = {
            "raw": values,
            "wide_6k": bandlimit(values, 75.0, 6000.0),
            "clear_4k5": clear,
            "narrow_3k5": bandlimit(values, 100.0, 3500.0),
            "offline_gate": spectral_gate(clear),
        }

    trim = 4096
    result: dict[str, object] = {"noise": str(args.noise), "captures": {}}
    noise_rms = {
        profile: rms(values[trim:-trim])
        for profile, values in processed["noise"].items()
    }
    for name, profiles in processed.items():
        capture: dict[str, object] = {}
        raw_rms = rms(profiles["raw"][trim:-trim])
        for profile, values in profiles.items():
            value = rms(values[trim:-trim])
            item: dict[str, float] = {
                "rms": value,
                "level_vs_raw_db": 20.0 * math.log10(value / raw_rms),
            }
            if name != "noise":
                raw_ratio = raw_rms / noise_rms["raw"]
                new_ratio = value / noise_rms[profile]
                item["program_to_noise_proxy_improvement_db"] = 20.0 * math.log10(
                    new_ratio / raw_ratio
                )
            capture[profile] = item
        result["captures"][name] = capture

    rendered = json.dumps(result, indent=2, ensure_ascii=False)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(rendered + "\n", encoding="utf-8")
    print(rendered)


if __name__ == "__main__":
    main()
