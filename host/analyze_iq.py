"""Measure K9IQ DC offset, quadrature balance, and conjugate-image rejection."""

from __future__ import annotations

import argparse
import socket
import struct

import numpy as np


HEADER = struct.Struct("<4sBBHIIIQI")
PORT = 50_003
PACKET_SAMPLES = 720


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--samples", type=int, default=1 << 20)
    parser.add_argument("--timeout", type=float, default=5.0)
    args = parser.parse_args()

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 32 * 1024 * 1024)
    sock.bind(("0.0.0.0", PORT))
    sock.settimeout(args.timeout)
    chunks: list[np.ndarray] = []
    count = 0
    station = 0
    while count < args.samples:
        payload, _ = sock.recvfrom(2048)
        if len(payload) != 1472:
            continue
        magic, version, flags, header_bytes, _, station, rate, _, _ = \
            HEADER.unpack_from(payload)
        if magic != b"K9IQ" or version != 2 or not flags & 2 or \
                header_bytes != 32 or rate != 6_000_000:
            continue
        values = np.frombuffer(payload, np.int8, offset=32).reshape(-1, 2)
        chunks.append(values.copy())
        count += PACKET_SAMPLES
    sock.close()

    pairs = np.concatenate(chunks)[:args.samples].astype(np.float64)
    i_values, q_values = pairs[:, 0], pairs[:, 1]
    i_centered = i_values - i_values.mean()
    q_centered = q_values - q_values.mean()
    z = i_centered + 1j * q_centered
    circularity = abs(np.mean(z * z)) / np.mean(abs(z) ** 2)
    correlation = np.corrcoef(i_centered, q_centered)[0, 1]
    lag_correlations = [
        np.corrcoef(i_centered[max(0, lag):len(i_centered) + min(0, lag)],
                    q_centered[max(0, -lag):len(q_centered) - max(0, lag)])[0, 1]
        for lag in range(-4, 5)
    ]
    shifted_pairs = np.concatenate(chunks).reshape(-1)[1:-1].reshape(-1, 2)[:args.samples].astype(np.float64)
    shifted_i = shifted_pairs[:, 0] - shifted_pairs[:, 0].mean()
    shifted_q = shifted_pairs[:, 1] - shifted_pairs[:, 1].mean()
    shifted_z = shifted_i + 1j * shifted_q
    shifted_circularity = abs(np.mean(shifted_z * shifted_z)) / np.mean(abs(shifted_z) ** 2)
    shifted_correlation = np.corrcoef(shifted_i, shifted_q)[0, 1]
    covariance = np.mean(i_centered * q_centered)
    i_power = np.mean(i_centered * i_centered)
    q_residual = q_centered - covariance / i_power * i_centered
    q_corrected = q_residual * np.sqrt(i_power / np.mean(q_residual * q_residual))
    z_corrected = i_centered + 1j * q_corrected
    corrected_circularity = abs(np.mean(z_corrected * z_corrected)) / \
        np.mean(abs(z_corrected) ** 2)
    rho = np.mean(z * z) / np.mean(abs(z) ** 2)
    image_coefficient = rho / (1.0 + np.sqrt(max(0.0, 1.0 - abs(rho) ** 2)))
    z_widely_corrected = (z - image_coefficient * np.conj(z)) / \
        (1.0 - abs(image_coefficient) ** 2)

    fft_size = 1 << 20
    spectrum = np.abs(np.fft.fftshift(np.fft.fft(z[-fft_size:] * np.hanning(fft_size))))
    frequencies = np.fft.fftshift(np.fft.fftfreq(fft_size, 1 / 6_000_000))
    spectrum[np.abs(frequencies) < 20_000] = 0
    positive = np.where(frequencies > 50_000)[0]
    peak_index = positive[np.argmax(spectrum[positive])]
    image_index = int(np.argmin(abs(frequencies + frequencies[peak_index])))
    image_db = 20 * np.log10((spectrum[peak_index] + 1e-12) /
                             (spectrum[image_index] + 1e-12))
    corrected_spectrum = np.abs(np.fft.fftshift(
        np.fft.fft(z_corrected[-fft_size:] * np.hanning(fft_size))))
    corrected_image_db = 20 * np.log10(
        (corrected_spectrum[peak_index] + 1e-12) /
        (corrected_spectrum[image_index] + 1e-12)
    )
    widely_spectrum = np.abs(np.fft.fftshift(
        np.fft.fft(z_widely_corrected[-fft_size:] * np.hanning(fft_size))))
    widely_image_db = 20 * np.log10(
        (widely_spectrum[peak_index] + 1e-12) /
        (widely_spectrum[image_index] + 1e-12)
    )
    dc_relative_db = 20 * np.log10(
        (abs(i_values.mean() + 1j * q_values.mean()) + 1e-12) /
        (np.sqrt(np.mean(abs(z) ** 2)) + 1e-12)
    )

    print(
        f"IQ_ANALYSIS station={station} samples={len(z)} "
        f"mean_i={i_values.mean():.4f} mean_q={q_values.mean():.4f} "
        f"std_i={i_centered.std():.4f} std_q={q_centered.std():.4f} "
        f"corr={correlation:.5f} circularity={circularity:.5f} "
        f"shift1_corr={shifted_correlation:.5f} shift1_circularity={shifted_circularity:.5f} "
        f"lag_corr={','.join(f'{value:.3f}' for value in lag_correlations)} "
        f"corrected_circularity={corrected_circularity:.5f} "
        f"dc_relative_db={dc_relative_db:.2f} "
        f"positive_peak_hz={frequencies[peak_index]:.1f} "
        f"image_rejection_db={image_db:.2f} corrected_image_db={corrected_image_db:.2f} "
        f"widely_image_db={widely_image_db:.2f}"
    )


if __name__ == "__main__":
    main()
