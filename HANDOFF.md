# K9+ FPGA 1-bit FM 收音机交接单

## 6 MHz轻量统一上位机里程碑（2026-10-18 16:20，Asia/Shanghai）

- 新增并行6 MS/s复数IQ监视链，取自NCO混频后独立40:1 CIC，不改变原960 kS/s
  FM接收链；可显示中心频率两侧各约3 MHz。
- `K9IQ` v2使用UDP/50003，32字节头加1440字节I8/Q8数据，每包720点；负载
  96 Mbit/s、约8.3k包/s，均为旧I16/Q16方案的一半。音频、IQ和raw使用锁定到
  整帧结束的仲裁，音频在帧间优先。
- `host/k9fm_sdr.py`统一完成播放、调谐、频谱、瀑布、双击选台、音量、静音和
  四档音频滤波。主机以32包为批次转换/入环形缓冲，使用4×8192 FFT、1024个
  显示点和约6.7 Hz刷新，显著减少Python锁、NumPy分配和Matplotlib重绘。
- 状态栏使用归属于频谱Axes的文本对象，以兼容本机旧版Matplotlib/Tk的blit；
  已连续运行20秒并在运行中切换96.8→95.0 MHz，无动画回调异常。
- 收音效果以Initial commit为下限复核：统一上位机默认恢复为仅6 kHz低通、无
  额外高通、音量1.0；FPGA保留效果更好的相关向量预滤波鉴频。Initial仿真为
  RMS 21057.8、tone/spur 104.3，当前为RMS 21351.5、tone/spur 108.1；实采
  空白点PCM RMS还由约5495降到3972（约2.8 dB）。
- 新位流已经JTAG烧录。实板同时运行时，IQ 5000包和音频40包均零丢失，IQ FIFO
  零溢出；IQ包率约8197/s，量化范围约-77～77，无削顶。以太网未就绪时显示
  FIFO保持复位，消除了链路启动阶段的假overflow告警。
- raw bypass另完成0.010032秒、2,407,680点实板回归，零丢包；切回audio后IQ和
  音频流均自动恢复。
- 位流SHA-256：
  `2349534F3320B6EF8E810AF335B00927AB282A509B3CD5FA2A2893E56018C7CD`。
- 完整构建WNS +0.251 ns、WHS +0.037 ns；0个时序失败、0个DRC错误。资源为
  6323 LUT、6482 FF、3 RAMB36+4 RAMB18、10 DSP48。

## 最新里程碑（2026-10-18 09:08，Asia/Shanghai）

本节覆盖下方历史记录中的旧频率、旧位流哈希和“尚未烧录”等描述。

- 当前位流已经通过JTAG烧录，最后通过网口调到 **95.0 MHz**。无需重新编译：
  `python host\tune_radio.py 95.0 --bind 169.254.172.8`（UDP 50001）。
- 细扫确认电台中心正好位于95.000和96.800 MHz，音质问题不是NCO频偏造成的。
- UDP状态字轮流发送原始RF密度、RGMII RX状态和信道幅度；
  `host/probe_packets.py`可以同时解码。
- 实测：95.0音乐台信道约626/2183、PCM RMS约4438；96.0强静音载波约
  4224/8841、PCM RMS约275；94.7空白点约358/1124、PCM RMS约3972。
  传输、调谐和解调均正常，音乐台的射频载噪比才是当前主要瓶颈。
- `rtl/fm_discriminator.sv`现为复相关dot/cross分别CIC3抽取20:1后再做
  CORDIC atan2。空白点PCM RMS由约5495降至3972，改善约2.8 dB。
- `rtl/complex_fir.sv`在101个历史样本填满前不输出，避免启动未知值污染CIC。
- 当前实装前端：RF_P经1 kΩ接VBIAS、经1 MΩ接3.3 V；RF_N直连VBIAS；
  拉杆经1 nF C0G和100 Ω接RF_P。实测VBIAS/RF_N/RF_P为
  1.189/1.189/1.191 V。1 MΩ使占空比从约0.3变为约0.6，方向正确但略过量，
  不应直接删除。完整复现接线见 `hardware/WIRING.md`。
- 下一步门限试验是在现有1 MΩ前串470 kΩ，使总值约1.47 MΩ，以空白点
  `rf_ones=0.48～0.52`为目标；该470 kΩ当前尚未安装。之后再做96 MHz
  LC预选器，并视许可加入10～15 dB低噪声RF增益。
- 当前bypass构建通过仿真、布线、DRC和时序，未读取或依赖旧综合报告数值。
- 位流SHA-256：
  `4D109CBFA95E9F096F9440A3F5FD279E0F8FE2D73800903F690E7E5C338FDA29`；
  BIN：`334B85B44F93411FADE981CDCD62C9351C37E4623BCCC85BE52D5CE4D0DBDDE6`。

### 原始1-bit bypass里程碑（2026-10-18）

- 已加入上位机可切换的原始RF bypass：UDP/50001的`K9MD`命令选择audio或
  bypass；切换会等待当前以太网帧结束，不截断在途帧。
- bypass取自`IBUFDS + IDDR`之后、NCO之前，保持240 MS/s。每4个120 MHz
  周期把8个时间连续样本打成1字节，经4 KB XPM异步FIFO送到125 MHz网口域。
- UDP/50002使用标准MTU：32字节`K9RF`头加1440字节原始数据。包头带序号、
  调谐标签、采样率、64位样本索引和FIFO溢出计数。
- `host/capture_raw.py`自动完成调谐、模式切换、连续性验证和恢复audio模式；
  任一包缺失、样本索引跳变或FIFO溢出都会判失败并拒绝生成基准文件。
- 实板曾在95.0、96.0、96.8、94.7 MHz控制标签下分别采集0.250032秒，确认
  全部零丢包、零FIFO溢出。由于采样点在NCO前，四份数据并未按标签预选，
  信号覆盖重复，因此仓库当前只保留质量指标最好的一份宽带基准。
- `captures/raw_2026-10-18/fm_band_snapshot.k9raw`包含60,007,680样本、5209包
  和整个0～120 MHz第一Nyquist区，可在离线仿真中任意重调。文件头中的
  95.0 MHz仅为采集当时的控制寄存器值；数据及SHA-256见同目录说明和JSON。
- 新位流已通过FM链、旧UDP包和新增raw UDP包仿真，完整构建、布线及实板
  audio/bypass切换。当前板已恢复audio模式，最后调谐为95.0 MHz；恢复后8包
  实测零丢包。

### 后续可选实验：用ISERDESE2提高到480 MS/s

该实验已经完成可行性调研，但本里程碑**暂不实施**。当前工程并非低速采样：
`clk_rf=120 MHz`，由`IDDR`双沿取得两个连续样本，有效采样率已经是
**240 MS/s**。Dawsonjon/FPGA-radio从100 MS/s提升到200 MS/s的IDDR阶段已经
被本工程超过；可继续借鉴的是其后续“高速ISERDES采样、低速并行处理”架构。

推荐先做保守的480 MS/s版本：

```text
MMCM：240 MHz高速采样时钟 + 120 MHz并行逻辑时钟
  → ISERDESE2，DDR、DATA_WIDTH=4
  → 每个120 MHz周期输出4个连续1-bit样本
  → 4相NCO混频
  → 每周期处理4样本的CIC3，仍抽取到960 kS/s
  → 现有信道FIR、鉴频、48 kS/s音频和以太网链路
```

XC7A50T-1的Artix-7数据手册给出DDR LVDS接收最高950 Mb/s，ISERDESE2支持
DDR 4/6/8位并行输出，因此480 MS/s在器件标称数字接口能力内。不过这里采样的
是异步模拟过零信号，不是带数据眼的源同步LVDS，950 Mb/s不能视作ADC性能保证；
首版不要直接挑战800～950 MS/s。参考资料：

- Dawsonjon FPGA-radio：`https://github.com/dawsonjon/FPGA-radio`
- AMD Artix-7 DS181：
  `https://docs.amd.com/api/khub/documents/iAkxxTOk96ANLJqYf2hgrQ/content`
- AMD UG471/ISERDESE2：
  `https://docs.amd.com/api/khub/documents/IbGcnPFe6eF19RHma_Y~IA/content`

若输入噪声样本近似独立，240→480 MS/s的理想处理增益仅为
`10*log10(480/240)=3.01 dB`；实际还可能因LVDS门限噪声、相邻样本相关性、
时钟抖动、亚稳态和宽带干扰而更低。因此它是一个无需改焊接、兼具诊断价值的
小幅优化，不应被当作替代预选滤波器和RF增益的根治方案。

实施时必须同时修改并验证：

1. 用正确的`BUFIO/BUFR`或等效专用时钟路径驱动ISERDESE2，并约束其与
   J20/J21所在I/O bank、clock region及MMCM的放置关系；不能继续把RF输入简单
   设为全局false path后就假定高速采样可靠。
2. 将`nco_mixer_2x.sv`改为4相NCO/混频器，四个相位依次相差一个480 MS/s
   采样周期；每个120 MHz周期相位累加四次。
3. 将`cic3_decimator_2x.sv`改为精确的4样本look-ahead结构，并把抽取参数从
   125对调整为125组四样本，使输出仍为960 kS/s。重新核算累加位宽和缩放，
   保持后级FIR系数及48 kS/s链路不变。
4. 将RTL初始NCO常数、`host/tune_radio.py`、`host/scan_radio.py`和仿真中的
   RF采样率统一从240 MHz改为480 MHz，避免调谐频率整体错误。
5. 先做仿真和静态时序，再烧录；不需要改变现有天线、1 nF、100 Ω、1 kΩ和
   1 MΩ接线。

验收不能只凭“声音似乎变了”。在95.0、96.0静音台、96.8和94.7空白点各采集
同长度数据，对比240/480 MS/s两版的丢包、RF一密度/跳变密度、信道
`|I|+|Q|`、PCM RMS及主观音质。若目标台相对空白点改善接近2～3 dB，则保留；
若不足约1 dB，说明主要瓶颈仍在模拟前端，不值得继续冲击800 MS/s。

下方保留的是研发历史，遇到冲突时以上述最新里程碑和中文README为准。

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
