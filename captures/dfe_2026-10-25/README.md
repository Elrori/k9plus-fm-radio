# DFE same-input comparison snapshot

`frontend_snapshot.k9raw` is the 2026-10-25 live capture used for the DFE
screening model. It contains 12,003,840 chronological 1-bit samples at
240 MS/s (0.050016 s), packed LSB-first after the 64-byte K9RAW1 header.
The capture utility verified 1,042 packets with no loss or FIFO overflow.
The 89.949311 MHz tuning label is metadata only: capture is before the NCO,
so this is a wideband snapshot, not a channel-selected recording.

SHA-256: `DEB1D001B87E0BC3D4456F6F60A832F70E60B699575C14F07639D3AD6C52A150`.

From the repository root:

```powershell
python scripts/gen_coeffs.py
python tests/verify_wide_dfe.py
python tools/compare_wide_dfe.py captures/dfe_2026-10-25/frontend_snapshot.k9raw
```

The model uses the first 20 ms. It is a floating-point screening model with
IQ8 quantization, not a bit-exact model of the complete RTL chain. The reported
channel/guard ratios are not calibrated RF SNR or SINAD. Results are preserved
under `tests/results/dfe_2026-10-25/`.
