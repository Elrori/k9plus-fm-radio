"""Capture K9FM UDP audio to WAV and print basic spectrum statistics."""

from __future__ import annotations

import argparse
import socket
import struct
import time
import wave

import numpy as np


HEADER = struct.Struct("<4sBBHIIII")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seconds", type=float, default=5.0)
    parser.add_argument("--output", default="capture.wav")
    args = parser.parse_args()

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind(("0.0.0.0", 50000))
    sock.settimeout(1.0)
    deadline = time.monotonic() + args.seconds
    blocks: list[np.ndarray] = []
    sequences: list[int] = []
    station = status = flags = 0
    while time.monotonic() < deadline:
        try:
            payload, _ = sock.recvfrom(2048)
        except socket.timeout:
            continue
        if len(payload) != HEADER.size + 512:
            continue
        magic, version, flags, count, seq, station, rate, status = HEADER.unpack_from(payload)
        if magic != b"K9FM" or version != 1 or count != 256 or rate != 48000:
            continue
        sequences.append(seq)
        blocks.append(np.frombuffer(payload, dtype="<i2", count=256, offset=HEADER.size).copy())
    sock.close()
    if not blocks:
        raise SystemExit("CAPTURE_FAIL no K9FM packets")

    pcm = np.concatenate(blocks)
    with wave.open(args.output, "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(48000)
        wav.writeframes(pcm.astype("<i2").tobytes())

    centered = pcm.astype(np.float64) - np.mean(pcm)
    nfft = min(131072, 1 << (len(centered).bit_length() - 1))
    window = np.hanning(nfft)
    spectrum = np.abs(np.fft.rfft(centered[-nfft:] * window))
    frequencies = np.fft.rfftfreq(nfft, 1 / 48000)
    spectrum[frequencies < 30] = 0
    peak_indices = np.argpartition(spectrum, -8)[-8:]
    peaks = sorted(((spectrum[i], frequencies[i]) for i in peak_indices), reverse=True)
    missing = sum(max(0, b-a-1) for a, b in zip(sequences, sequences[1:]))
    status_text = f"fpga_drops={status}"
    if flags & 1:
        status_text = (f"rf_ones={(status >> 16)/65535.0:.4f} "
                       f"rf_transitions={(status & 0xffff)/65535.0:.4f}")
    print(
        f"CAPTURE_PASS packets={len(sequences)} missing={missing} station={station}Hz "
        f"{status_text} samples={len(pcm)} rms={np.sqrt(np.mean(centered**2)):.1f} "
        f"min={pcm.min()} max={pcm.max()} wav={args.output}"
    )
    print("FFT_PEAKS " + " ".join(f"{freq:.1f}Hz" for _, freq in peaks))


if __name__ == "__main__":
    main()
