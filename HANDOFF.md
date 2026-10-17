# K9+ FM radio handoff

Last updated: 2026-10-17 15:25 (Asia/Shanghai)

## LATEST STATE -- READ THIS FIRST

Work was stopped at the user's request because the current Codex quota was
nearly exhausted.  The FPGA is left running the latest volatile JTAG image and
was restored to **96.8 MHz** after an interrupted scan.  Do not ask the user to
change resistors at this point; the next work is software/DSP evaluation.

### Hardware/front-end state

- Board/baseboard: Colorlight K9+ / XI050CD-style, XC7A50T-FGG484-1.
- Ethernet cable is in the RJ45 behind **U11**.  JTAG and Ethernet are live.
- Antenna is a telescopic whip.
- User's latest DC readings: `VBIAS=1.189 V`, `RF_N=1.189 V`,
  `RF_P=1.191 V`.
- Current passive changes: RF_P-to-VBIAS resistor is **1 kOhm** (was 51 Ohm),
  and **1 MOhm RF_P-to-3.3 V** has been added.  The user does not want further
  soldering unless a large benefit is demonstrated.
- Known stations from the user: 95.0, 96.0, 96.8 MHz; 96.0 is a silent station.

### Most important result from the last session

Network tuning now works without recompiling.  The original RGMII receive path
was marginal because it sampled the U11 bus without the board-specific input
delay.  PacketMon proved the Windows machine sent correct UDP/50001 frames,
then FPGA telemetry showed DV/preamble but failed SFD/header checks.  The exact
BigPig XI050CD reference was cloned under `hardware/bigpig-xilinx` and showed
that this board requires **12 IDELAYE2 taps** on RXD[3:0] and RXCTL plus a
200 MHz IDELAYCTRL reference.  The current RTL implements that value.  After
programming, the live diagnostic was:

```
station=95000000Hz missing=0
seen=dv,55,sfd,etype_hi,etype_ok,udp,magic,tune
```

The command is:

```
python host\tune_radio.py 95.0 --bind 169.254.172.8
```

The custom parser searches each received frame for `K9TU`, then consumes the
little-endian frequency and NCO phase increment.  It does not depend on fixed
IP-header offsets.  The command is sent four/eight times for resilience.

### Current programmed build

- `build/k9plus_fm_radio.bit`: 2,192,121 bytes, built 2026-10-17 15:18:55.
- SHA-256: `99020B5DB52041AFA8007359E2FB8D2F52A71E19A50646C1861B62D5B586C96E`
- Route timing: WNS `+0.395 ns`, WHS `+0.028 ns`; all specified constraints met.
- DRC: zero errors; 24 DSP pipeline performance warnings (not correctness
  errors).
- Latest live check after restoring 96.8 MHz: zero missing UDP packets,
  station metadata `96800000`, and all RX diagnostic stages through `tune` set.
- The image is only loaded by JTAG unless someone explicitly programs flash.

### DSP/software changes already in this build

- Effective RF sampling is 240 MS/s (120 MHz DDR).
- The complex channel FIR was narrowed from 100 kHz to **85 kHz one-sided**
  (about 170 kHz total) in `scripts/gen_coeffs.py`.
- `audio_post.sv` DC tracker was changed from shift 12 to shift 7, giving an
  approximate 60 Hz high-pass, followed by 50 us FM de-emphasis.
- The host player has a fourth-order Butterworth low-pass; default cutoff is
  6 kHz and can be changed without rebuilding, for example:
  `python host\k9fm_receiver.py --lowpass 4500`.
- `host/scan_radio.py` was added for automatic fine scanning.  A bug in its
  receive-queue drain was fixed, but the final scan was interrupted at the
  user's request and therefore has no completed ranking yet.

### Captures made with the current build

All had zero packet loss and are under `build/captures/`:

| File | Station | Duration | Raw PCM RMS | Notes |
| --- | ---: | ---: | ---: | --- |
| `fm_95p0_raw.wav` | 95.0 MHz | 12 s | 7311.7 | Strong program; large LF/audio energy |
| `fm_96p0_silent.wav` | 96.0 MHz | 12 s | 665.0 | Useful quiet-carrier/noise reference; narrow ~21.45 kHz component |
| `fm_96p8_raw.wav` | 96.8 MHz | 12 s | 6931.6 | Strong program; peaks include ~58/116/233/588 Hz |

Band-energy analysis showed the 96.0 silent carrier is roughly 18--22 dB below
the active stations through most of the audio band.  This is evidence that the
receiver is locking to real FM carriers and that much of the active-station
energy is modulation, not just a flat noise floor.  The user's previous
subjective report was still "music faint/very noisy", so listening comparison
of 4.5/6 kHz low-pass settings is still required.

### Immediate next actions (no hardware changes)

1. Run the repaired fine scan one range at a time, unbuffered, and retain the
   table:
   `python -u host\scan_radio.py --start 94.70 --stop 95.30 --step 0.05 --seconds 0.8`
   and similarly `96.50..97.10`.  Restore 95.0 or 96.8 afterwards.
2. Compare live listening at `--lowpass 6000`, `4500`, and `3500`.  Select the
   widest cutoff that makes speech/music intelligible; this is likely a bigger
   improvement than more passive bias changes.
3. Use the three WAV captures for offline A/B processing before committing any
   FPGA rebuild.  Candidate: high-pass 70--100 Hz plus 4.5--6 kHz low-pass;
   optionally conservative STFT Wiener/spectral gating using the 96.0 capture
   as a noise reference.  Avoid aggressive gating that produces musical-noise
   artifacts.
4. Once RX control debugging is finished, restore packet metadata from
   `net_rx_debug` to `stats_sync` in `k9plus_fm_top.sv`, change packet flag byte
   from `0x02` back to `0x01` in `udp_audio_axis_tx.sv`, rebuild/program, and
   confirm RF ones/transition telemetry again.  Keep the RGMII IDELAY code.
5. Update README after the final audio choice.  Do not delete the captures or
   the cloned BigPig reference until the work is complete.

### Important caveats

- The current packet status word carries **RGMII RX debug**, flag bit `0x02`,
  instead of RF density statistics.  `probe_packets.py` decodes it correctly;
  `capture_audio.py` prints it as `fpga_drops`, which is only a display-label
  mismatch, not real packet loss or FPGA drops.
- `host/scan_radio.py` uses a content-dependent clarity score.  Treat its best
  frequency as a starting point and verify by ear; changing music/speech can
  bias a short measurement.
- The `hardware/bigpig-xilinx` directory is a sparse clone of the board vendor
  reference, not project RTL.  The key reference is
  `XI050CD/rgmii_loop/src/udp/gmii2rgmii.sv` with `P_IDELAY_TAPS=12`.

---

The sections below describe the earlier baseline and are retained for history.

## Outcome

The clean rebuild is programmed and operational on the Colorlight K9+ /
XI050CD-style baseboard. It receives the 1-bit LVDS RF stream, demodulates FM
mono in the FPGA, and sends 48 ksample/s signed PCM plus tuning metadata as
broadcast UDP through the RJ45 whose PHY is **U11**. The Windows receiver plays
the audio and displays waveform and spectrum.

The user confirmed the passive frontend is connected and measured:

- `VBIAS = 1.189 V`
- `RF_P = 1.189 V`
- `RF_N = 1.189 V`
- antenna: telescopic whip

These readings are in the intended 0.9--1.4 V safe-check range. Wiring remains
documented in `hardware/WIRING.md`.

## Frozen architecture

- FPGA: XC7A50T-FGG484-1; board clock W19 at 25 MHz.
- RF input: U4-8/J20 `RF_P`, U4-12/J21 `RF_N`, `IBUFDS` plus IDDR.
- RF rate: 240 MS/s effective (120 MHz DDR), avoiding the 200 MS/s Nyquist-zone
  overlap of the earlier experiment.
- Mode: broadcast FM mono. A hard-limited 1-bit stream retains FM crossing
  timing but discards the amplitude envelope needed for ordinary AM.
- Default station: 96.8 MHz (changed after 100.1 MHz sounded like pure noise);
  V18/V19 request -/+100 kHz and auto-repeat when held; U18 mutes.
- DSP: complex NCO mixer, CIC decimation, complex FIR channel filter,
  quadrature discriminator, 48 ksample/s audio decimation and de-emphasis.
- Ethernet: U11 RGMII only, 1 Gbit/s; PHY RXC is FPGA V4; PHY reset W22 is
  actively held high. TXC uses the same phase as the 125 MHz transmit data,
  matching the proven BigPig/XI050CD convention and PHY-side delay.
- MAC: `axis_gmii_tx.v` and `lfsr.v` are reused from
  `E:\doc\WORK_SPACE\mix\verilog-ethernet-anlogic\rtl` by `scripts/build.tcl`.

## Live hardware verification

1. The exact BigPig U11 reference image first established the board path:
   1 Gbit/s link, 5/5 pings to `192.168.1.210` below 1 ms, and ARP MAC
   `02-02-de-ad-be-ef`.
2. The integrated diagnostic image then emitted valid K9FM packets only after
   using U11, deasserting reset on W22, and using an unshifted RGMII TXC.
3. The final FM image produced:

   ```text
   LIVE_PACKET_PASS sender=('192.168.10.2', 50000) packets=30
   seq=1113..1142 missing=0 station=100100000Hz rate=48000Hz
   fpga_drops=0 pcm_min=-20750 pcm_max=19631 pcm_mean=-149.0 pcm_rms=6146.7
   ```

4. A six-second WAV capture produced:

   ```text
   CAPTURE_PASS packets=1123 missing=0 station=100100000Hz fpga_drops=0
   samples=287488 rms=6083.2 min=-25594 max=25781 wav=build/live_100p1.wav
   FFT_PEAKS 1193.5Hz 1476.2Hz 571.7Hz 694.7Hz 245.0Hz 254.9Hz 711.5Hz 522.6Hz
   ```

5. After 100.1 MHz was reported as pure noise, the boot frequency was changed
   to 96.8 MHz and reprogrammed. The new image reported 30/30 packets with no
   gaps (`station=96800000Hz`, `fpga_drops=0`, PCM RMS 6137.2). A second
   six-second capture received 1123 packets with no gaps and is saved as
   `build/live_96p8.wav`.

6. Offline comparison found the two captures nearly identical despite the
   3.3 MHz tuning change: RMS 0.1856/0.1879 FS, spectral flatness 0.508/0.504,
   correlation decaying to near zero within 16 samples, and peak prominence
   10.7/10.6 dB. Together with the reported lack of response when touching the
   whip, this identifies shaped LVDS threshold noise rather than received FM.
   The frontend prescription was therefore revised from a 51 ohm shunt to 1
   kohm plus a 70--80 cm ground counterpoise.

7. A diagnostic build now embeds normalized raw-RF one density and transition
   density in the status word (`flags & 1`). Host probe/capture/receiver tools
   decode and display both. This build is complete but must not be programmed
   while the user is physically modifying the powered-down frontend.

The packet sequence and FPGA drop counter prove stable transport during these
captures. The non-flat audio spectrum proves structured demodulated PCM rather
than an all-zero stream, but listening quality remains a subjective/local-RF
check. The receiver was launched on Windows output device 3 (Realtek speakers).

## Final build evidence

- Vivado 2019.1; target `xc7a50tfgg484-1`.
- Timing: WNS `+0.221 ns`, TNS `0`; WHS `+0.044 ns`, THS `0`; all constraints
  met.
- Routing: 5886/5886 routable nets complete; 0 routing errors.
- DRC: 0 errors/critical warnings; 24 DSP pipeline performance suggestions.
- Utilization: 3522 LUTs, 2784 FFs, 4 RAMB18s, 10 DSP48 blocks.
- `sim_fm.ps1`: 576 PCM samples; recovered 1 kHz tone at the 947.4 Hz FFT bin;
  RMS 21057.8; tone/max-spur ratio 104.3.
- `sim_udp.ps1`: legacy raw-frame serializer test passes exact 590-byte frame,
  Ethernet FCS, IPv4 checksum, UDP metadata, and 256 PCM samples. The final AXI
  packetizer/MAC path is additionally covered by the successful live captures.

Artifacts:

- `build/k9plus_fm_radio.bit`, 2,192,121 bytes, SHA-256
  `D54EB17EA3F9784DAECA54C8814934ECDBF484525689551955957B70807E625E`
- `build/k9plus_fm_radio.bin`, 2,192,012 bytes, SHA-256
  `1702E03DB63E46863A4FA994AB83B89D233D5122FB3BA9FBEE6F91404506C007`
- `build/live_96p8.wav`, 575,020 bytes, SHA-256
  `0C8E18D634534D62EC02933B02DB10708508859E483AEFC5985E8183FEBCA0E4`
- `build/live_100p1.wav`, 575,020 bytes, SHA-256
  `B794F75E962FF279B921A8FAF0FA534D8F42703E06E8EF4C6F7D58AC4D4DCD3F`

## On-wire protocol

- Destination MAC: broadcast; source MAC: `02:4b:39:2b:01:01`.
- IPv4 source/destination: `192.168.10.2` / `255.255.255.255`.
- UDP source/destination port: 50000 / 50000.
- Payload: 24-byte little-endian `K9FM` v1 header followed by 256 signed
  little-endian 16-bit samples at 48 ksample/s.
- Host receive-only operation requires no static IPv4 address. The temporary
  test address was removed and the Windows adapter was restored to DHCP.

## Reproduce

```powershell
cd E:\doc\WORK_SPACE\mix\fpga-radio\k9plus-fm-radio
python scripts\gen_coeffs.py
.\sim_fm.ps1
.\sim_udp.ps1
.\build.ps1
.\program.ps1
python -m pip install -r host\requirements.txt
python host\probe_packets.py --count 30
python host\capture_audio.py --seconds 6 --output build\live_100p1.wav
python host\k9fm_receiver.py --list-devices
python host\k9fm_receiver.py --device 3
```

If no packets arrive, check the cable is on the RJ45 behind **U11** before
changing RTL. U13 is not the active port in this design. Windows Firewall may
also need to allow Python on the Ethernet network.

## Remaining engineering boundary

The digital pipeline and Ethernet transport are working. The principal limit is
now analog: an Artix-7 LVDS input is not a characterized RF ADC/comparator, and
an R/C-only whip input has no gain, AGC, ESD clamp, or useful 88--108 MHz
preselector. A strong local station may sound good, but commercial-tuner
sensitivity and blocker immunity cannot honestly be promised under the stated
no-LNA/no-inductor constraint. Next optimization should therefore begin with a
subjective listen at 96.8 MHz, antenna placement, and tuning to the strongest
local station; only then adjust DSP gain/filtering if required.
