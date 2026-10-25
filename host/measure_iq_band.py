"""Read current IQ and save continuity, amplitude and local spectral metrics.

Does not retune. A local-median noise estimate is not calibrated RF SNR.
"""
import argparse
import json
import socket
import struct
import time
from pathlib import Path
import numpy as np

p = argparse.ArgumentParser(description=__doc__)
p.add_argument("--packets", type=int, default=5000)
p.add_argument("--output", type=Path, required=True)
p.add_argument("--require-compensated", action="store_true")
a = p.parse_args()
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 32*1024*1024)
s.bind(("0.0.0.0", 50003))
s.settimeout(3)
header = struct.Struct("<4sBBHIIIQI")
chunks, overs, stations, flags_seen = [], [], set(), set()
previous = None
missing = gaps = 0
deadline = time.monotonic()+10
try:
    while len(chunks) < a.packets and time.monotonic() < deadline:
        packet, _ = s.recvfrom(2048)
        if len(packet) != 1472:
            continue
        magic, version, flags, size, seq, lo, rate, index, overflow = header.unpack_from(packet)
        if magic != b"K9IQ" or version != 2 or not flags & 2 or size != 32 or rate != 6000000:
            continue
        if previous is not None:
            missing += (seq-previous[0]-1) & 0xffffffff
            gaps += index != previous[1]+720
        previous = seq, index
        stations.add(lo)
        flags_seen.add(flags)
        overs.append(overflow)
        chunks.append(np.frombuffer(packet, np.int8, offset=32).copy())
finally:
    s.close()
if len(chunks) != a.packets or len(stations) != 1:
    raise SystemExit("Incomplete capture or LO changed during measurement")
x = np.concatenate(chunks).reshape(-1, 2).astype(float)
z = x[:, 0]+1j*x[:, 1]
z -= z.mean()
n = 32768
k = len(z)//n
ps = np.mean(abs(np.fft.fftshift(np.fft.fft(z[:k*n].reshape(k, n)*np.hanning(n), axis=1), axes=1))**2, axis=0)
f = np.fft.fftshift(np.fft.fftfreq(n, 1/rate))+lo
channels = {}
for target in [87500000, 95986600, 96800000]:
    if abs(target-lo) > 2.4e6:
        continue
    band = abs(f-target) < 100000
    guard = (abs(f-target) > 200000) & (abs(f-target) < 450000)
    peak = np.flatnonzero(band)[np.argmax(ps[band])]
    channels[str(target)] = dict(total_over_local_median_db=float(10*np.log10(np.mean(ps[band])/np.median(ps[guard]))),
                                peak_hz=float(f[peak]))
result = dict(packets=len(chunks), missing=missing, index_gaps=gaps, lo_hz=lo,
              flags=sorted(flags_seen), overflow_start=overs[0], overflow_end=overs[-1],
              min=float(x.min()), max=float(x.max()), std=x.std(axis=0).tolist(),
              circularity=float(abs(np.mean(z*z))/np.mean(abs(z)**2)),
              clip_fraction=float(np.mean((x == 127) | (x == -128))), channels=channels)
a.output.parent.mkdir(parents=True, exist_ok=True)
a.output.write_text(json.dumps(result, indent=2))
print(json.dumps(result, indent=2))
if missing or gaps or overs[-1] != overs[0]:
    raise SystemExit("Continuity/overflow check failed")
if a.require_compensated and any(not flags & 4 for flags in flags_seen):
    raise SystemExit("Compensated DFE flag missing")
