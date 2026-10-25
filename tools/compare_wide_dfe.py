"""Same-input screening model; not an RTL proof or calibrated RF SNR."""
import argparse
import json
from pathlib import Path
import numpy as np

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("capture", type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
bits = np.unpackbits(np.frombuffer(args.capture.read_bytes()[64:], np.uint8),
                     bitorder="little")[:4_800_000]
rf = bits.astype(float)*2-1
c = np.array([int(s, 16) for s in (root/"mem/wide_fir_q16.mem").read_text().split()])
c = np.where(c >= 2**17, c-2**18, c)/65536

def moving_average(x, r):
    cs = np.r_[0j, np.cumsum(x)]
    return (cs[r:]-cs[:-r])/r

def psd(z):
    n = 8192
    z = z[200:]
    k = len(z)//n
    z = z[:k*n].reshape(k, n)
    return np.mean(abs(np.fft.fftshift(np.fft.fft(z*np.hanning(n), axis=1), axes=1))**2, axis=0)

results = {}
for target in (87.5e6, 96.8e6):
    lo = target-200000
    inc = round(lo/240e6*2**32)
    phase = ((np.arange(len(rf), dtype=np.uint64)*inc) & 0xffffffff) >> 22
    mixed = rf*np.exp(-2j*np.pi*phase/1024)
    variants = {}
    for name, r in (("old", 40), ("new", 20)):
        v = mixed
        for _ in range(3):
            v = moving_average(v, r)
        v = v[::r]
        if name == "new":
            v = np.convolve(v, c, mode="valid")[1::2]
        # Same DC gain as RTL: 32767*64000/2**24 IQ8 units.
        v *= 32767*64000/2**24
        q = np.clip(np.floor(v.real), -128, 127) + 1j*np.clip(np.floor(v.imag), -128, 127)
        p, error = psd(q), psd(q-v)
        f = np.fft.fftshift(np.fft.fftfreq(8192, 1/6e6))
        band = abs(f-200000)<100000
        guard = (abs(f-200000)>200000) & (abs(f-200000)<450000)
        variants[name] = dict(
            channel_over_local_median_db=float(10*np.log10(np.mean(p[band])/np.median(p[guard]))),
            quantization_error_below_local_noise_db=float(10*np.log10(np.median(p[guard])/np.mean(error[band]))),
            clip_fraction=float(np.mean((q.real<=-128)|(q.real>=127)|(q.imag<=-128)|(q.imag>=127))))
    results[str(target)] = variants
dest = root/"build/sim_wide/same_input.json"
dest.write_text(json.dumps(results, indent=2))
print(json.dumps(results, indent=2))
