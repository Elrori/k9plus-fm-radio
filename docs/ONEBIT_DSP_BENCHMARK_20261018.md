# K9+ 1-bit FM DSP baseline / A-B benchmark (2026-10-18)

## Scope and verification

The RF input is the committed `captures/raw_2026-10-18/fm_band_snapshot.k9raw`, SHA256
`F2524C7648DA9D438FE7A3F6B7C6588FEA4BF2BEFD3DAAFE8DC8D28282F606F3`.
It contains 60,007,680 continuous 240 MS/s samples (0.250032 s), one-density
0.57802053, no lost packets and no FIFO overflow. Verified in GitHub Actions.

The DSP algorithm model reproduces the nominal NCO mixing / CIC3 /250 transfer
function, Q18 101-tap Kaiser complex FIR, filtered conjugate product with
CIC3 /20, atan2 and the approximate 48-kHz audio HPF/de-emphasis.

It is **not bit-exact to RTL** (NCO ROM/address truncation, fixed-point CIC/FIR
rounding, arithmetic saturation and clocks are not reproduced).

## Real RF, equal processing and nominal gain normalization

Values below are differences in output **RMS level (dB)** versus the existing
lag=1/CIC3/20 model. Positive numbers mean *higher output energy*, NOT necessarily
more useful audio or noise. For blank and unknown-program stations, the reference
content is unknown; none of these numbers is an actual audio SINAD improvement.

| Frequency | 70k FIR | lag=2 | lag=4 | FIR correlator, 241 tap |
|---|---:|---:|---:|---:|
| 94.7 MHz blank | -0.62 | +0.52 | +3.39 | +0.42 |
| 95.0 MHz program | -0.27 | +0.47 | +2.88 | +0.40 |
| 96.0 MHz strong quiet carrier | +1.19 | -0.55 | **-2.69** | -0.02 |
| 96.8 MHz program | -0.59 | +0.47 | +3.02 | +0.79 |

On 96.0 MHz the output RMS is 0.0026054258 (baseline), 0.0024448687
(lag=2), 0.0019109656 (lag=4). Thus lag4 is -2.69 dB on *this quiet carrier*.

The >8-kHz **band RMS** change from a 241-tap/16-kHz correlation FIR is
-2.96 dB on 96 MHz, but **+1.68 dB** on 95 MHz program and **+2.14 dB**
on 96.8 MHz program. Do not interpret this as station SNR without ground truth.

## Synthetic 95-MHz known-reference test

Comparison against an injected 1-kHz to 15-kHz sinusoidal FM tone,
peak deviation ±75 kHz, input Gaussian noise filtered around the carrier
with 5-MHz bandwidth. CNR is RF carrier power divided by *integrated 5-MHz
analog-noise power at the comparator*. Numbers are **output SINAD in dB**
from a least-squares sine fit over a common 48-kHz processed window.

| Modulation / RF CNR | Baseline | lag2 | lag4 | FIR correlation |
|---|---:|---:|---:|---:|
| 1 kHz / 0 dB | 39.948 | 41.800 | 46.803 | 39.711 |
| 1 kHz / 6 dB | 52.868 | 53.921 | 55.702 | 52.693 |
| 5 kHz / 6 dB | 43.216 | 43.260 | 42.549 | 44.243 |
| 10 kHz / 6 dB | 32.337 | 32.670 | 28.106 | 34.722 |
| 10 kHz / 12 dB | 38.869 | 40.735 | 29.917 | 43.946 |
| 15 kHz / 12 dB | 27.425 | 32.498 | 12.694 | 30.390 |

The lag4 advantage for 1-kHz modulation is **not broadband**: relative to the
baseline it loses about 4.23 dB at 10 kHz/6 dB CNR and 14.73 dB at 15 kHz/12 dB.
The 70-kHz channel FIR is risky at ±75-kHz frequency deviation; at 1 kHz/0 dB
it reduces synthesized SINAD from 39.948 dB to 24.318 dB. Do not enable a narrow
IF solely because it makes unknown real-program output quieter.

## Decision

- **Do not change the main FPGA bitstream or default lag=1 DSP yet.**
- The only directly measured narrow-condition improvement here is ~2.7 dB
  less output RMS on the strong quiet 96-MHz signal using lag4; this is not
  a universal audio SNR gain.
- A selectable lag2 discriminator and selectable FIR dot/cross smoothing are
  plausible experiments, but require fresh full-band, controlled modulation
  distortion, weak-station listening, and fixed-point/timing verification.
- To claim a whole-radio audio SNR gain on 95.0/96.8 MHz, obtain a known
  reference modulation or repeated aligned captures with equivalent
  RF conditions. A 0.25-s unknown music recording alone cannot separate
  the desired audio from the receiver noise.

## Reproduction

```bash
python -m pip install numpy scipy
python tests/bench_1bit_real.py
python tests/bench_1bit_synthetic.py
```

CI (real + synthetic): GitHub Actions run `39087362584`.
