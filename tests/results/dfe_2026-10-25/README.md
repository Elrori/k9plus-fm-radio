# Experimental HDSDR DFE validation — 2026-10-25

Baseline: `d1064b1` (atomic IQ CDC). This is an experimental branch, not a
validated sensitivity fix or a replacement recommendation for stable firmware.

## Change

The HDSDR stream previously used CIC3 /40 directly into IQ8. It now uses
CIC3 /20 followed by a 63-tap symmetric compensation/anti-alias FIR /2.
Output stays at 6 MS/s IQ8 with unchanged nominal center gain. The useful
passband is +/-2.4 MHz. UDP v2 flag bit 2 identifies the compensated path;
the Python viewer avoids applying the old CIC display correction twice.
ExtIO advertises 4.8 MHz useful bandwidth. The FPGA FM audio path is unchanged.

## Completed checks

- `sim_wide.ps1`: 512 complex outputs match independent integer convolution
  exactly, including impulse, random/full-scale input and input-valid gaps.
- `sim_iq.ps1`: packet format, compensated flag and payload verification pass.
- `sim_fm.ps1`: existing FM regression passes, 571 samples, tone bin 957.9 Hz.
- ExtIO Win32 Release build: zero compiler warnings/errors.
- Full Vivado 2019.1 implementation: DRC zero errors; WNS +0.082 ns,
  WHS +0.013 ns, all user-specified timing constraints met.
- Resources: 7,593 LUTs, 9,388 FFs, 102 DSP48 blocks (120 available).
- BIT SHA-256:
  `49A2A9B512FF0E9C786B461674665975EB0B86A90BFBE3C978EE6BAC00569C15`.
- Volatile JTAG programming succeeded. Two live captures of 5,000 IQ packets
  each had no loss, sample-index gaps, FIFO overflow or IQ8 clipping.
  Both identified the new DFE with flags=6. Original LO 89.949311 MHz restored.
- Flash was not changed. Reboot restores the previous Flash firmware.

## Evidence and interpretation

- `response.json`: coefficient-response calculation, not a measured RF sweep.
  Passband is within 0.002 dB; final decimator stopband is below -84 dB.
  The first CIC still admits aliases: worst relative rejection is about 36 dB
  over the useful passband. Do not claim 84 dB system alias rejection.
- `same_input.json`: same raw input through old/new floating-point screening
  models. No material improvement for 96.8 MHz near the LO; IQ8 quantization
  error is approximately 30 dB below the local noise estimate.
- `live_96p8.json`: post-change channel/local-median ratio 1.44 dB, versus
  1.42 dB in the earlier live baseline. This is effectively unchanged.
- `live_87p5.json`: post-change ratio 10.82 dB, versus 10.01 dB earlier.
  These were different-time program captures; do not attribute the difference
  to the DFE. Ratios include noise power and are not calibrated RF SNR.

The raw snapshot and reproduction commands are committed under
`captures/dfe_2026-10-25/`. Full build logs, timing reports and old/new bitstreams
remain in the ignored local `build/` directory, not in this commit. The repository
tracks the rebuilt ExtIO DLL according to its existing distribution convention.

## Outstanding before promotion

- Complete NCO -> CIC -> FIR -> IQ bit-exact chain regression.
- RF passband sweep and out-of-band blocker/alias injection measurements.
- Longer live stress test and cold-boot test after any later Flash programming.
- Decide whether the bandwidth improvement justifies 102 DSPs and small timing
  margins. Measure weak-signal performance with a controlled source.
- Identify whether the strong 95.987 MHz signal is external or board coupling,
  then verify the suspected analog blocking mechanism by a controlled A/B.

Hardware suggestions in `hardware/FRONTEND_ACTION_PLAN_2026-10-25.md` are
unimplemented proposals, not claims that the user's circuit has been modified.
