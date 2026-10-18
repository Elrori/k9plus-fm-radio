"""Shared UDP control helpers for the K9+ FM receiver."""

from __future__ import annotations

import socket
import struct
import time


SAMPLE_RATE = 240_000_000
CONTROL_PORT = 50_001


def open_control_socket(bind_addr: str) -> socket.socket:
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    sock.bind((bind_addr, 0))
    return sock


def send_tune(sock: socket.socket, frequency_hz: int) -> int:
    phase_increment = round(frequency_hz / SAMPLE_RATE * 2**32)
    payload = struct.pack("<4sII", b"K9TU", frequency_hz, phase_increment)
    for _ in range(8):
        sock.sendto(payload, ("255.255.255.255", CONTROL_PORT))
        time.sleep(0.02)
    return phase_increment


def send_mode(sock: socket.socket, bypass: bool) -> None:
    payload = struct.pack("<4sB3x", b"K9MD", int(bypass))
    for _ in range(8):
        sock.sendto(payload, ("255.255.255.255", CONTROL_PORT))
        time.sleep(0.02)
