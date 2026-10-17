"""Receive, play and display Colorlight K9+ FM audio UDP packets."""

from __future__ import annotations

import argparse
import math
import socket
import struct
import threading
import time
from collections import deque

import matplotlib.animation as animation
import matplotlib.pyplot as plt
import numpy as np


PORT = 50_000
RATE = 48_000
HEADER = struct.Struct("<4sBBHIIII")


class BiquadLowpass:
    """Two-section fourth-order Butterworth low-pass for live hiss reduction."""

    def __init__(self, cutoff: float) -> None:
        self.sections = []
        cosine = math.cos(2.0 * math.pi * cutoff / RATE)
        sine = math.sin(2.0 * math.pi * cutoff / RATE)
        for q_value in (0.5411961001, 1.3065629649):
            alpha = sine / (2.0 * q_value)
            a0 = 1.0 + alpha
            self.sections.append([
                (1.0 - cosine) / (2.0 * a0),
                (1.0 - cosine) / a0,
                (1.0 - cosine) / (2.0 * a0),
                -2.0 * cosine / a0,
                (1.0 - alpha) / a0,
                0.0,
                0.0,
            ])

    def process(self, block: np.ndarray) -> np.ndarray:
        output = block
        for section in self.sections:
            b0, b1, b2, a1, a2, z1, z2 = section
            filtered = np.empty_like(output)
            for index, value in enumerate(output):
                result = b0 * value + z1
                z1 = b1 * value - a1 * result + z2
                z2 = b2 * value - a2 * result
                filtered[index] = result
            section[5] = z1
            section[6] = z2
            output = filtered
        return output


class SharedAudio:
    def __init__(self, seconds: int = 4) -> None:
        self.lock = threading.Lock()
        self.playback: deque[float] = deque(maxlen=RATE * seconds)
        self.display: deque[float] = deque([0.0] * (RATE * seconds), maxlen=RATE * seconds)
        self.station_hz = 0
        self.sequence = -1
        self.lost_packets = 0
        self.fpga_drops = 0
        self.rf_ones = 0.0
        self.rf_transitions = 0.0
        self.last_packet = 0.0

    def append(self, pcm: np.ndarray, sequence: int, station_hz: int,
               status: int, flags: int) -> None:
        values = (pcm.astype(np.float32) / 32768.0).tolist()
        with self.lock:
            if self.sequence >= 0:
                self.lost_packets += max(0, sequence - self.sequence - 1)
            self.sequence = sequence
            self.station_hz = station_hz
            if flags & 1:
                self.rf_ones = (status >> 16) / 65535.0
                self.rf_transitions = (status & 0xffff) / 65535.0
                self.fpga_drops = 0
            else:
                self.fpga_drops = status
            self.last_packet = time.monotonic()
            self.playback.extend(values)
            self.display.extend(values)


def receive_loop(shared: SharedAudio, bind: str, stop: threading.Event) -> None:
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind((bind, PORT))
    sock.settimeout(0.25)
    try:
        while not stop.is_set():
            try:
                payload, _address = sock.recvfrom(2048)
            except socket.timeout:
                continue
            if len(payload) < HEADER.size:
                continue
            magic, version, flags, count, sequence, station, rate, status = HEADER.unpack_from(payload)
            if magic != b"K9FM" or version != 1 or rate != RATE or count != 256:
                continue
            expected = HEADER.size + 2 * count
            if len(payload) != expected:
                continue
            pcm = np.frombuffer(payload, dtype="<i2", count=count, offset=HEADER.size).copy()
            shared.append(pcm, sequence, station, status, flags)
    finally:
        sock.close()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bind", default="0.0.0.0", help="local IPv4 address (default: all)")
    parser.add_argument("--device", help="sounddevice output index or substring")
    parser.add_argument("--no-audio", action="store_true", help="display only")
    parser.add_argument("--lowpass", type=float, default=6000.0,
                        help="fourth-order audio low-pass cutoff in Hz; 0 disables")
    parser.add_argument("--list-devices", action="store_true")
    args = parser.parse_args()

    try:
        import sounddevice as sd
    except ImportError:
        sd = None
    if args.list_devices:
        if sd is None:
            raise SystemExit("sounddevice is not installed")
        print(sd.query_devices())
        return

    shared = SharedAudio()
    stop = threading.Event()
    receiver = threading.Thread(target=receive_loop, args=(shared, args.bind, stop), daemon=True)
    receiver.start()

    stream = None
    lowpass = BiquadLowpass(args.lowpass) if 0 < args.lowpass < RATE / 2 else None
    if not args.no_audio:
        if sd is None:
            raise SystemExit("sounddevice is not installed; use --no-audio or install requirements")

        def callback(outdata, frames, _time_info, _status) -> None:
            block = np.zeros(frames, dtype=np.float32)
            with shared.lock:
                take = min(frames, len(shared.playback))
                for index in range(take):
                    block[index] = shared.playback.popleft()
            if lowpass is not None:
                block = lowpass.process(block)
            outdata[:, 0] = block

        device = int(args.device) if args.device and args.device.isdigit() else args.device
        stream = sd.OutputStream(samplerate=RATE, channels=1, dtype="float32",
                                 blocksize=512, callback=callback, device=device)
        stream.start()

    fft_size = 8192
    window = np.hanning(fft_size)
    frequencies = np.fft.rfftfreq(fft_size, 1.0 / RATE)
    figure, (wave_axis, spectrum_axis) = plt.subplots(2, 1, figsize=(11, 7))
    wave_count = 2400
    wave_x = np.arange(wave_count) * 1000.0 / RATE
    wave_line, = wave_axis.plot(wave_x, np.zeros(wave_count), lw=0.8)
    wave_axis.set(xlabel="time (ms)", ylabel="level", ylim=(-1.0, 1.0))
    spectrum_line, = spectrum_axis.plot(frequencies, np.full_like(frequencies, -120.0), lw=0.8)
    spectrum_axis.set(xlabel="audio frequency (Hz)", ylabel="dBFS", xlim=(0, 20_000), ylim=(-120, 3))
    spectrum_axis.grid(True, alpha=0.25)
    figure.tight_layout()

    def update(_frame):
        with shared.lock:
            values = np.asarray(shared.display, dtype=np.float64)
            station = shared.station_hz
            lost = shared.lost_packets
            drops = shared.fpga_drops
            rf_ones = shared.rf_ones
            rf_transitions = shared.rf_transitions
            age = time.monotonic() - shared.last_packet if shared.last_packet else 999.0
        wave_line.set_ydata(values[-wave_count:])
        transform = np.fft.rfft(values[-fft_size:] * window)
        scale = max(np.sum(window) / 2.0, 1.0)
        spectrum_line.set_ydata(20.0 * np.log10(np.maximum(np.abs(transform) / scale, 1e-6)))
        state = "LIVE" if age < 1.0 else "NO UDP"
        wave_axis.set_title(
            f"K9+ FM {station/1e6:.1f} MHz | {state} | lost={lost} "
            f"ones={rf_ones:.3f} transitions={rf_transitions:.3f} "
            f"LP={args.lowpass:g}Hz drop={drops}"
        )
        return wave_line, spectrum_line

    _anim = animation.FuncAnimation(figure, update, interval=50, blit=False, cache_frame_data=False)
    try:
        plt.show()
    finally:
        stop.set()
        receiver.join(timeout=1.0)
        if stream is not None:
            stream.stop()
            stream.close()


if __name__ == "__main__":
    main()
