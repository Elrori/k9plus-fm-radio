"""Response gates and independent integer-convolution vectors for wide FIR."""
from pathlib import Path
import json
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
out = ROOT / "build/sim_wide"
out.mkdir(parents=True, exist_ok=True)
(out / "mem").mkdir(exist_ok=True)
source = ROOT / "mem/wide_fir_q16.mem"
(out / "mem/wide_fir_q16.mem").write_bytes(source.read_bytes())
(out / "mem/wide_coeffs.vh").write_bytes((ROOT / "mem/wide_coeffs.vh").read_bytes())
c = np.array([int(s, 16) for s in source.read_text().split()], dtype=np.int64)
c = np.where(c >= 2**17, c - 2**18, c)
assert np.array_equal(c, c[::-1]) and c.sum() == 65536
f = np.linspace(0, 6e6, 12001)
h = abs(np.exp(-2j*np.pi*f[:, None]/12e6*np.arange(63)) @ (c/65536))
cic = abs(np.sinc(f/12e6)/np.sinc(f/240e6))**3
db = 20*np.log10(np.maximum(h*cic, 1e-15))
passband = db[f <= 2.4e6]
stopband = db[f >= 3.6e6]
assert max(abs(passband)) < 0.05
assert max(stopband) < -75
# First CIC decimation also aliases: report, do not confuse final FIR
# stopband attenuation with the rejection of the complete 240 MS/s chain.
alias_db = []
for offset in np.linspace(-2.4e6, 2.4e6, 961):
    for band in range(-10, 11):
        freq = offset + band*12e6
        if band == 0 or abs(freq) > 120e6:
            continue
        relative = abs((np.sinc(freq/12e6)/np.sinc(freq/240e6)) /
                       (np.sinc(offset/12e6)/np.sinc(offset/240e6)))**3
        alias_db.append(20*np.log10(max(relative, 1e-15)))
metrics = dict(passband_min_db=float(min(passband)),
               passband_max_db=float(max(passband)),
               final_decimator_stopband_max_db=float(max(stopband)),
               first_cic_worst_alias_relative_db=float(max(alias_db)))
(out / "response.json").write_text(json.dumps(metrics, indent=2))
rng = np.random.default_rng(27)
x = rng.integers(-8388608, 8388608, (1024, 2), dtype=np.int64)
x[:64] = 0
x[1] = [1000000, -2000000]
x[128:256] = 8388607
x[256:384] = -8388608
v = np.stack([np.convolve(x[:, j], c)[:len(x)][1::2] for j in range(2)], axis=1)
v = np.clip((v+32768) >> 16, -8388608, 8388607)
for name, arr in [("input", x), ("expected", v)]:
    (out / (name+".mem")).write_text("".join(
        f"{int(q)&0xffffff:06x}{int(i)&0xffffff:06x}\n" for i, q in arr))
print("WIDE_RESPONSE_PASS", json.dumps(metrics))
