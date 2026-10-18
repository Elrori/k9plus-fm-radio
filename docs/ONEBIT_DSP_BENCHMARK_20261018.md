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

## Follow-up: configurable lag2 RTL and controlled correlation-filter A/B

Branch includes a **synthesizable** but deliberately **opt-in** change to
`rtl/fm_discriminator.sv`: `CORR_LAG=1` (default, exactly as before)
or `CORR_LAG=2`. The 2-sample phase-angle output is arithmetic-shifted
right by 1 to restore the original one-IF-sample Q28 frequency scale.
Existing top-level instantiation uses the unchanged default. No flash/FPGA
programming or top-level connection was changed.

A frozen copy of the pre-change master discriminator resides in
`tests/ref_fm_discriminator_20261018.sv`. In
`tests/tb_fm_discriminator_lag.sv`, the lag=1 modified RTL matches this
frozen source **cycle by cycle and bit by bit**, including valid and Q28.
Constant IF phase slopes of +10 kHz and -15 kHz independently checked
lag=1/2 normalization and polarity. GitHub Actions (Icarus Verilog) passed.
These checks are **unit-level**, not a routed Vivado timing sign-off or
end-to-end fixed-point reception test.

### Independent follow-up floating-point DSP cases

| RF FM stimulus | lag2 vs baseline | FIR16 vs baseline | FIR18 vs baseline | lag2+FIR18 vs baseline |
|---|---:|---:|---:|---:|
| 1 kHz audio, 0 dB CNR, ±75k | +1.85 dB | -0.24 dB | -0.39 dB | +1.43 dB |
| 5 kHz audio, 6 dB CNR, ±75k | +0.04 dB | +1.03 dB | **-4.36 dB** | -1.92 dB |
| 10 kHz audio, 6 dB CNR, ±75k | +0.33 dB | +2.39 dB | +1.36 dB | +2.68 dB |
| 15 kHz audio, 6 dB CNR, ±75k | +1.14 dB | +0.20 dB | +2.91 dB | -4.23 dB |
| 10 kHz audio, 12 dB CNR, ±75k | +1.87 dB | +5.08 dB | -2.35 dB | +3.19 dB |
| 15 kHz audio, 12 dB CNR, ±75k | +5.07 dB | +2.97 dB | +2.26 dB | **-8.67 dB** |

Here FIR16/18 are **241-tap** low-pass filters on the complex correlation
at 960 kS/s, **before** decimation by 20 and atan2. They are expensive
to implement in FPGA compared to CIC, and improvements are not uniformly
positive. Combining lag2 with FIR18 can make distortion much worse.

### Low-cost 3-tap CIC equalizer experiment

A shift/add-friendly real FIR on 48-kS/s complex correlation samples:
`[-a, 1+2a, -a]`, `a=1/8` or `1/4`, compensates the CIC3 droop.
In controlled 15-kHz / 6-dB CNR / ±75-kHz FM, relative SINAD:
`a=1/8` +2.03 dB; `a=1/4` +2.71 dB. At 5 kHz / 6 dB:
`a=1/8` -0.65 dB; `a=1/4` -1.38 dB.
Real 96.0-MHz quiet carrier RMS with a=1/4 **increases** from
0.002605 to 0.002931, and its >8-kHz band RMS rises from
0.000912 to 0.001653. This emphasizes high-frequency noise and should
not be the weak-signal default.

### Next gate / recommendation

**Keep default lag1 + CIC3 in the deployment.** Only the lag2 compile-time
candidate is implemented in the RTL branch, with baseline equivalence
checked. FIR16/18 and CIC equalizers remain offline experiments because
none exhibits reliable improvement across all modulations/conditions.

Meaningful whole-radio improvements require a longer matched real-data
capture with known program or reference modulation; the current 0.25-s
broadband unknown-audio snapshot cannot yield real weak-station audio SINAD.
Test lag2 with a controlled sweep and Vivado place/route before using it
on physical K9+ hardware.

CI includes real RF, known-tone synthetic, and RTL regression tests.
Successful run: `39088246070`.
