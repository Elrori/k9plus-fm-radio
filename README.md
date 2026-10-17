# Colorlight K9+ 1-bit FM radio

Clean-room implementation for the Colorlight K9+ / XI050CD-style baseboard.
The FPGA LVDS input is used as a 1-bit RF comparator; recovered mono PCM and
status metadata are sent as broadcast UDP over the on-board RGMII PHY.

The selected architecture is FM, not AM. A zero-threshold 1-bit limiter keeps
FM phase/frequency information, while it destroys the amplitude envelope that
ordinary AM needs. The RF sample rate is 240 MS/s (IDDR at 120 MHz), which
covers 88--108 MHz without the spectral overlap present in the old 200 MS/s
experiment.

## Start here

1. Read [hardware/WIRING.md](hardware/WIRING.md) and wire the passive frontend.
2. Run `python scripts/gen_coeffs.py` once after changing DSP parameters.
3. Keep the reference checkout
   `E:\doc\WORK_SPACE\mix\verilog-ethernet-anlogic` in place. The build uses
   its proven `axis_gmii_tx.v` and `lfsr.v` Ethernet MAC sources.
4. Run `./sim_fm.ps1` and `./sim_udp.ps1`, then build with `./build.ps1`.
5. Only after checking the wiring voltages, program SRAM with `./program.ps1`.
6. Install `host/requirements.txt`, then start the host with
   `python host/k9fm_receiver.py`.

The host listens on UDP port 50000, plays 48 ksample/s mono audio, and displays
the waveform and audio spectrum. Packets use Ethernet and IPv4 broadcast, so a
static host address is not required for receive-only operation.

## Fixed board assignments

- FPGA: `xc7a50tfgg484-1`
- board clock: W19, 25 MHz
- RF differential pair: J20/J21 = U4 pins 8/12
- keys: V18/V19 tune -/+100 kHz; U18 mute
- RGMII: **U11 only**. The cable must be connected to the RJ45 behind U11;
  this design clocks its Ethernet transmit path from U11 RXC (FPGA V4).
- PHY reset: W22, driven high to deassert reset
- status LEDs: P17, V20, V22, U21

LED0/LED1 indicate RF/Ethernet clock lock. LED2 toggles at the recovered-audio
rate and LED3 lights while an Ethernet frame is being transmitted.

## Live-tested result (2026-10-17)

The complete bitstream has been programmed and tested through U11 at 1 Gbit/s.
The host received 30 consecutive radio packets with no missing sequence number
and no FPGA-reported drops. A separate six-second capture received 1123 packets
with no gaps and produced `build/live_100p1.wav`. The receiver is normally
started with:

```powershell
python host\k9fm_receiver.py --device 3
```

Use `python host\k9fm_receiver.py --list-devices` if the output device numbering
changes. `python host\probe_packets.py --count 30` performs a quick link and PCM
sanity check without audio playback. It also reports normalized raw-RF one and
transition densities, making saturation versus threshold noise visible. The
current build boots at 96.8 MHz; hold either tune key after about 0.5 seconds for
automatic 100 kHz stepping, so later station changes require no rebuild. The
earlier `live_100p1.wav` capture is retained as transport/debug evidence.

## Honest performance boundary

The passive R/C-only frontend has no FM preselector, gain, AGC, ESD clamp, or
specified analog comparator. Strong local stations can be intelligible and
clean enough for this experiment, but weak-signal sensitivity and blocker
immunity cannot be comparable to a commercial tuner. Packet transport and
non-silent structured PCM are verified; subjective reception quality still
depends on the local station, telescopic antenna placement, and RF environment.

See [HANDOFF.md](HANDOFF.md) for the current build/test state and exact next
actions.
