"""Unified K9+ FM receiver with 6 MHz spectrum and waterfall display."""

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
from matplotlib.widgets import Button, RadioButtons, Slider, TextBox
import numpy as np

from k9fm_receiver import BiquadHighpass, BiquadLowpass
from radio_control import MAX_TUNE_HZ, open_control_socket, send_tune, validate_frequency_hz


AUDIO_PORT = 50_000
IQ_PORT = 50_003
AUDIO_RATE = 48_000
IQ_RATE = 6_000_000
AUDIO_HEADER = struct.Struct("<4sBBHIIII")
IQ_HEADER = struct.Struct("<4sBBHIIIQI")
IQ_HEADER_BYTES = 32
IQ_DATA_BYTES = 1440
IQ_SAMPLES_PER_PACKET = IQ_DATA_BYTES // 2
IQ_BATCH_PACKETS = 32


class ReceiverState:
    def __init__(self) -> None:
        self.lock = threading.Lock()
        self.playback: deque[float] = deque(maxlen=AUDIO_RATE * 2)
        self.audio_display: deque[float] = deque(
            [0.0] * (AUDIO_RATE // 10), maxlen=AUDIO_RATE // 10
        )
        self.station_hz = 0
        self.audio_sequence: int | None = None
        self.audio_lost = 0
        self.rf_ones = 0.0
        self.rf_transitions = 0.0
        self.channel_average = 0
        self.channel_peak = 0
        self.last_audio = 0.0

        self.iq_buffer = np.zeros(1 << 20, dtype=np.complex64)
        self.iq_write = 0
        self.iq_total = 0
        self.iq_sequence: int | None = None
        self.iq_sample_index: int | None = None
        self.iq_lost = 0
        self.iq_overflow = 0
        self.last_iq = 0.0

    def append_audio(self, pcm: np.ndarray, sequence: int, station_hz: int,
                     status: int, flags: int) -> None:
        values = pcm.astype(np.float32) / 32768.0
        with self.lock:
            if self.audio_sequence is not None:
                self.audio_lost += max(0, (sequence - self.audio_sequence - 1) & 0xFFFFFFFF)
            self.audio_sequence = sequence
            self.station_hz = station_hz
            if flags & 1:
                self.rf_ones = (status >> 16) / 65535.0
                self.rf_transitions = (status & 0xFFFF) / 65535.0
            elif flags & 4:
                self.channel_average = status >> 16
                self.channel_peak = status & 0xFFFF
            self.playback.extend(values.tolist())
            self.audio_display.extend(values.tolist())
            self.last_audio = time.monotonic()

    def append_iq_batch(self, values: np.ndarray, sequence: int, sample_index: int,
                        station_hz: int, overflow: int, lost: int) -> None:
        with self.lock:
            self.iq_lost += lost
            self.iq_sequence = sequence
            self.iq_sample_index = sample_index
            self.station_hz = station_hz
            self.iq_overflow = overflow
            count = values.size
            first = min(count, self.iq_buffer.size - self.iq_write)
            self.iq_buffer[self.iq_write:self.iq_write + first] = values[:first]
            rest = count - first
            if rest:
                self.iq_buffer[:rest] = values[first:]
            self.iq_write = (self.iq_write + count) % self.iq_buffer.size
            self.iq_total += count
            self.last_iq = time.monotonic()

    def latest_iq(self, count: int) -> np.ndarray | None:
        with self.lock:
            if self.iq_total < count:
                return None
            start = (self.iq_write - count) % self.iq_buffer.size
            if start + count <= self.iq_buffer.size:
                return self.iq_buffer[start:start + count].copy()
            first = self.iq_buffer.size - start
            return np.concatenate((self.iq_buffer[start:], self.iq_buffer[:count-first]))


def audio_receive_loop(state: ReceiverState, bind: str, stop: threading.Event) -> None:
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 4 * 1024 * 1024)
    sock.bind((bind, AUDIO_PORT))
    sock.settimeout(0.25)
    try:
        while not stop.is_set():
            try:
                payload, _ = sock.recvfrom(2048)
            except socket.timeout:
                continue
            if len(payload) < AUDIO_HEADER.size:
                continue
            magic, version, flags, count, sequence, station, rate, status = \
                AUDIO_HEADER.unpack_from(payload)
            if (magic != b"K9FM" or version != 1 or rate != AUDIO_RATE or
                    len(payload) != AUDIO_HEADER.size + count * 2):
                continue
            pcm = np.frombuffer(payload, "<i2", count=count,
                                offset=AUDIO_HEADER.size).copy()
            state.append_audio(pcm, sequence, station, status, flags)
    finally:
        sock.close()


def iq_receive_loop(state: ReceiverState, bind: str, stop: threading.Event) -> None:
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 32 * 1024 * 1024)
    sock.bind((bind, IQ_PORT))
    sock.settimeout(0.25)
    expected_sequence: int | None = None
    expected_sample: int | None = None
    try:
        while not stop.is_set():
            packed = bytearray()
            batch_lost = 0
            last_sequence = last_sample = last_station = last_overflow = 0
            packet_count = 0
            while packet_count < IQ_BATCH_PACKETS and not stop.is_set():
                try:
                    payload, _ = sock.recvfrom(2048)
                except socket.timeout:
                    break
                if len(payload) != IQ_HEADER_BYTES + IQ_DATA_BYTES:
                    continue
                magic, version, flags, header_bytes, sequence, station, rate, \
                    sample_index, overflow = IQ_HEADER.unpack_from(payload)
                if (magic != b"K9IQ" or version != 2 or not flags & 2 or
                        header_bytes != IQ_HEADER_BYTES or rate != IQ_RATE):
                    continue
                if expected_sequence is not None:
                    sequence_gap = (sequence - expected_sequence) & 0xFFFFFFFF
                    sample_gap = max(0, sample_index - expected_sample) // IQ_SAMPLES_PER_PACKET
                    batch_lost += max(sequence_gap, sample_gap)
                expected_sequence = (sequence + 1) & 0xFFFFFFFF
                expected_sample = sample_index + IQ_SAMPLES_PER_PACKET
                packed.extend(payload[IQ_HEADER_BYTES:])
                last_sequence = sequence
                last_sample = expected_sample
                last_station = station
                last_overflow = overflow if flags & 1 else 0
                with state.lock:
                    state.iq_compensated = bool(flags & 4)
                packet_count += 1
            if not packed:
                continue
            pairs = np.frombuffer(packed, dtype=np.int8).reshape(-1, 2)
            iq = pairs[:, 0].astype(np.complex64)
            iq.imag = pairs[:, 1]
            state.append_iq_batch(iq, last_sequence, last_sample, last_station,
                                  last_overflow, batch_lost)
    finally:
        sock.close()


def cic_display_correction(frequency_hz: np.ndarray) -> np.ndarray:
    response = np.abs(np.sinc(frequency_hz / IQ_RATE)) ** 3
    return np.minimum(-20.0 * np.log10(np.maximum(response, 1e-3)), 12.0)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bind", default="0.0.0.0", help="UDP receive address")
    parser.add_argument("--control-bind", default="169.254.172.8",
                        help="wired-adapter IPv4 address used for tuning")
    parser.add_argument("--frequency", type=float, default=96.8, help="initial MHz")
    parser.add_argument("--device", help="sounddevice output index or substring")
    parser.add_argument("--no-audio", action="store_true")
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

    state = ReceiverState()
    stop = threading.Event()
    threads = [
        threading.Thread(target=audio_receive_loop, args=(state, args.bind, stop), daemon=True),
        threading.Thread(target=iq_receive_loop, args=(state, args.bind, stop), daemon=True),
    ]
    for thread in threads:
        thread.start()

    control = open_control_socket(args.control_bind)
    control_lock = threading.Lock()
    requested_hz = round(args.frequency * 1e6)
    try:
        validate_frequency_hz(requested_hz)
    except ValueError as error:
        raise SystemExit(str(error)) from error

    def tune_async(frequency_hz: int) -> None:
        try:
            validate_frequency_hz(frequency_hz)
        except ValueError:
            return
        def worker() -> None:
            with control_lock:
                send_tune(control, frequency_hz)
        threading.Thread(target=worker, daemon=True).start()

    tune_async(requested_hz)

    filter_state: dict[str, object] = {
        "highpass": None,
        "lowpass": BiquadLowpass(6000.0),
        "profile": "Initial 6k",
        "volume": 1.0,
        "mute": False,
    }
    stream = None
    if not args.no_audio:
        if sd is None:
            raise SystemExit("sounddevice is not installed; use --no-audio")

        def callback(outdata, frames, _time_info, _status) -> None:
            block = np.zeros(frames, dtype=np.float32)
            with state.lock:
                take = min(frames, len(state.playback))
                for index in range(take):
                    block[index] = state.playback.popleft()
            highpass = filter_state["highpass"]
            lowpass = filter_state["lowpass"]
            if highpass is not None:
                block = highpass.process(block)
            if lowpass is not None:
                block = lowpass.process(block)
            if filter_state["mute"]:
                block.fill(0.0)
            else:
                block *= float(filter_state["volume"])
            outdata[:, 0] = np.clip(block, -1.0, 1.0)

        device = int(args.device) if args.device and args.device.isdigit() else args.device
        stream = sd.OutputStream(samplerate=AUDIO_RATE, channels=1, dtype="float32",
                                 blocksize=512, callback=callback, device=device)
        stream.start()

    fft_size = 8192
    averages = 4
    display_bins = 1024
    waterfall_rows = 120
    window = np.hanning(fft_size).astype(np.float32)
    offsets = np.fft.fftshift(np.fft.fftfreq(fft_size, 1.0 / IQ_RATE))
    correction = cic_display_correction(offsets)
    waterfall = np.full((waterfall_rows, display_bins), -120.0, dtype=np.float32)

    figure = plt.figure(figsize=(13, 9))
    grid = figure.add_gridspec(3, 1, height_ratios=(3, 4, 1),
                              left=0.07, right=0.98, top=0.94, bottom=0.18, hspace=0.10)
    spectrum_axis = figure.add_subplot(grid[0])
    waterfall_axis = figure.add_subplot(grid[1], sharex=spectrum_axis)
    audio_axis = figure.add_subplot(grid[2])
    center_mhz = requested_hz / 1e6
    display_offsets = offsets.reshape(display_bins, -1).mean(axis=1) / 1e6
    x_mhz = center_mhz + display_offsets
    spectrum_line, = spectrum_axis.plot(x_mhz, np.full(display_bins, -120.0), lw=0.8)
    center_line = spectrum_axis.axvline(center_mhz, color="yellow", alpha=0.65, lw=0.8)
    spectrum_axis.set(ylabel="dBFS", ylim=(-115, 5))
    spectrum_axis.grid(True, alpha=0.22)
    image = waterfall_axis.imshow(
        waterfall, aspect="auto", origin="upper", interpolation="nearest",
        extent=(x_mhz[0], x_mhz[-1], waterfall_rows, 0), cmap="turbo",
        vmin=-105, vmax=-30,
    )
    waterfall_axis.set(ylabel="history", xlabel="RF frequency (MHz)")
    audio_count = 2400
    audio_x = np.arange(audio_count) * 1000.0 / AUDIO_RATE
    audio_line, = audio_axis.plot(audio_x, np.zeros(audio_count), lw=0.7)
    audio_axis.set(xlabel="audio time (ms)", ylabel="level", ylim=(-1, 1))
    # Keep this artist owned by an Axes.  Older Matplotlib/Tk releases crash
    # the blit loop when a returned Figure.text artist has axes=None.
    status_text = spectrum_axis.text(
        0.07, 0.955, "Waiting for K9FM/K9IQ...", fontsize=10,
        transform=figure.transFigure, clip_on=False,
    )

    tune_box = TextBox(figure.add_axes((0.07, 0.075, 0.10, 0.045)), "MHz ",
                       initial=f"{center_mhz:.3f}")
    tune_button = Button(figure.add_axes((0.18, 0.075, 0.06, 0.045)), "Tune")
    minus_1m = Button(figure.add_axes((0.25, 0.075, 0.055, 0.045)), "-1M")
    minus_100k = Button(figure.add_axes((0.31, 0.075, 0.06, 0.045)), "-100k")
    plus_100k = Button(figure.add_axes((0.375, 0.075, 0.06, 0.045)), "+100k")
    plus_1m = Button(figure.add_axes((0.44, 0.075, 0.055, 0.045)), "+1M")
    mute_button = Button(figure.add_axes((0.51, 0.075, 0.07, 0.045)), "Mute")
    volume_slider = Slider(figure.add_axes((0.62, 0.082, 0.20, 0.025)),
                           "Volume", 0.0, 1.5, valinit=1.0)
    profiles = RadioButtons(figure.add_axes((0.84, 0.035, 0.13, 0.105)),
                            ("Initial 6k", "Clear 4.5k", "Weak 3.5k", "Raw"), active=0)

    def requested_frequency() -> int | None:
        try:
            value = round(float(tune_box.text) * 1e6)
        except ValueError:
            return None
        return value if 0 <= value <= MAX_TUNE_HZ else None

    def submit_tune(_event=None) -> None:
        value = requested_frequency()
        if value is not None:
            tune_async(value)

    def step_tune(delta_hz: int) -> None:
        value = requested_frequency()
        if value is None:
            value = state.station_hz or requested_hz
        value = min(MAX_TUNE_HZ, max(0, value + delta_hz))
        tune_box.set_val(f"{value/1e6:.3f}")

    tune_box.on_submit(submit_tune)
    tune_button.on_clicked(submit_tune)
    minus_1m.on_clicked(lambda _event: step_tune(-1_000_000))
    minus_100k.on_clicked(lambda _event: step_tune(-100_000))
    plus_100k.on_clicked(lambda _event: step_tune(100_000))
    plus_1m.on_clicked(lambda _event: step_tune(1_000_000))
    mute_button.on_clicked(lambda _event: filter_state.update(mute=not filter_state["mute"]))
    volume_slider.on_changed(lambda value: filter_state.update(volume=float(value)))

    def select_profile(label: str) -> None:
        settings = {
            "Initial 6k": (0.0, 6000.0),
            "Clear 4.5k": (90.0, 4500.0),
            "Weak 3.5k": (100.0, 3500.0),
            "Raw": (0.0, 0.0),
        }
        high_hz, low_hz = settings[label]
        filter_state["highpass"] = BiquadHighpass(high_hz) if high_hz else None
        filter_state["lowpass"] = BiquadLowpass(low_hz) if low_hz else None
        filter_state["profile"] = label

    profiles.on_clicked(select_profile)

    def click_tune(event) -> None:
        if event.dblclick and event.inaxes in (spectrum_axis, waterfall_axis) and event.xdata:
            tune_box.set_val(f"{event.xdata:.3f}")

    figure.canvas.mpl_connect("button_press_event", click_tune)

    def key_control(event) -> None:
        if event.key == "left": step_tune(-100_000)
        elif event.key == "right": step_tune(100_000)
        elif event.key == "m": filter_state.update(mute=not filter_state["mute"])

    figure.canvas.mpl_connect("key_press_event", key_control)

    displayed_center = center_mhz

    def update(_frame):
        nonlocal displayed_center
        iq = state.latest_iq(fft_size * averages)
        if iq is not None:
            frames = iq.reshape(averages, fft_size) * window[None, :]
            transforms = np.fft.fftshift(np.fft.fft(frames, axis=1), axes=1)
            scale = max(float(np.sum(window)) * 128.0, 1.0)
            power = np.mean(np.abs(transforms / scale) ** 2, axis=0)
            with state.lock:
                compensated = getattr(state, "iq_compensated", False)
            spectrum = 10.0 * np.log10(np.maximum(power, 1e-14))
            if not compensated:
                spectrum += correction
            spectrum = spectrum.reshape(display_bins, -1).mean(axis=1)
            waterfall[:-1] = waterfall[1:]
            waterfall[-1] = spectrum
            spectrum_line.set_ydata(spectrum)
            image.set_data(waterfall)
            floor = float(np.median(spectrum))
            image.set_clim(floor - 8.0, floor + 52.0)

        with state.lock:
            station_hz = state.station_hz or requested_hz
            audio_values = np.asarray(state.audio_display, dtype=np.float32)
            audio_lost, iq_lost = state.audio_lost, state.iq_lost
            overflow = state.iq_overflow
            ones, transitions = state.rf_ones, state.rf_transitions
            channel_average, channel_peak = state.channel_average, state.channel_peak
            audio_age = time.monotonic() - state.last_audio if state.last_audio else 999.0
            iq_age = time.monotonic() - state.last_iq if state.last_iq else 999.0
        center = station_hz / 1e6
        if center != displayed_center:
            current_x = center + display_offsets
            spectrum_line.set_xdata(current_x)
            center_line.set_xdata([center, center])
            spectrum_axis.set_xlim(current_x[0], current_x[-1])
            image.set_extent((current_x[0], current_x[-1], waterfall_rows, 0))
            displayed_center = center
            figure.canvas.draw_idle()
        audio_line.set_ydata(audio_values[-audio_count:])
        status_text.set_text(
            f"K9+ {center:.3f} MHz | span 6 MHz | "
            f"audio={'LIVE' if audio_age < 1 else 'WAIT'} lost={audio_lost} | "
            f"IQ={'LIVE' if iq_age < 1 else 'WAIT'} lost={iq_lost} overflow={overflow} | "
            f"ones={ones:.3f} transitions={transitions:.3f} "
            f"channel={channel_average}/{channel_peak} | {filter_state['profile']} "
            f"{'MUTED' if filter_state['mute'] else ''}"
        )
        return spectrum_line, image, audio_line, center_line, status_text

    _anim = animation.FuncAnimation(figure, update, interval=150, blit=True,
                                    cache_frame_data=False)
    try:
        plt.show()
    finally:
        stop.set()
        control.close()
        for thread in threads:
            thread.join(timeout=1.0)
        if stream is not None:
            stream.stop()
            stream.close()


if __name__ == "__main__":
    main()
