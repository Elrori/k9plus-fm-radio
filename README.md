# Colorlight K9+ FPGA 1-bit FM 收音机

本项目使用 Colorlight K9+、XI050CD 类底板和 FPGA 内部 LVDS 输入实现
1-bit FM 接收机。天线信号由 LVDS 输入充当过零比较器采样，FPGA 完成数字
下变频、信道滤波、FM 解调和音频处理，再通过底板 U11 后方的千兆网口发送
48 kHz 单声道 PCM，由 Windows 上位机显示频谱并播放。

当前项目已达到第一个可用里程碑：

- 240 MS/s 1-bit RF 采样链路工作；
- 95.0、96.0 和 96.8 MHz 可以通过网口实时调谐，无需重新编译；
- U11 RGMII 收发稳定，连续实测 UDP 丢包数为 0；
- 95.0 和 96.8 MHz 已能收到音乐，但由于射频载噪比较低，底噪仍明显；
- 96.0 MHz 是本地强静音载波，解调输出很安静，证明数字链路在强信号下正常；
- 当前限制主要是天线、门限偏置、射频预选和增益，而不是音频低通。

## 当前硬件配置

### 板卡和引脚

| 功能 | 连接 |
|---|---|
| FPGA | `xc7a50tfgg484-1` |
| 板载时钟 | W19，25 MHz |
| RF_P | FPGA C2 / `exter_io2[32]` |
| RF_N | FPGA B2 / `exter_io2[33]` |
| 以太网 | **U11 后方的 RJ45** |
| PHY RXC | FPGA V4 |
| PHY 复位 | W22，高电平解除复位 |
| 按键 | V18/V19：减/加 100 kHz；U18：静音 |

### 当前实际已焊阻容前端

以下是当前里程碑对应的实际电路，不是后续设想：

```text
3.3V (U4-38) ── 1.8kΩ ──+── 1.0kΩ ── GND
                          |
                       VBIAS ≈ 1.189V
                          |
                    100nF || 1µF
                          |
                         GND

拉杆天线 ── 1nF C0G ── 100Ω ──+── RF_P (C2)
                                 |
                                 +── 1kΩ ── VBIAS
                                 |
                                 +── 1MΩ ── 3.3V

RF_N (B2) ───────────────────────── VBIAS
拉杆底座/回流 ──────────────────── GND
```

最近一次实测直流电压：

```text
VBIAS = 1.189V
RF_N  = 1.189V
RF_P  = 1.191V
```

1 MΩ 上拉是门限补偿的一部分：未安装时 FPGA 原始 1-bit 占空比约为 0.3，
安装后约为 0.6。因此不能简单删除它。后续建议在原 1 MΩ 前串联 470 kΩ，
把总阻值变成约 1.47 MΩ，再以 FPGA 遥测的 `rf_ones` 为准，将空白频点
占空比调到约 0.48～0.52。该 470 kΩ **当前尚未安装**。

完整接线、布局和安全注意事项见
[hardware/WIRING.md](hardware/WIRING.md)。物料表见
[hardware/bom.csv](hardware/bom.csv)。

## 数字信号链

```text
LVDS + IDDR 240MS/s
  → NCO 正交混频
  → CIC 抽取到 960kS/s
  → 101-tap 复数信道 FIR（±85kHz）
  → 复共轭相关的 dot/cross 分量分别 CIC3 抽取 20:1
  → CORDIC atan2 FM 鉴频（48kS/s）
  → 60Hz 高通、50µs 去加重
  → UDP/RGMII
```

关键改进是先对复相关向量滤波，再进行非线性的 `atan2`。空白频点
94.7 MHz 的 PCM RMS 从约 5495 降到约 3972，改善约 2.8 dB。

FPGA 在 UDP 状态字中轮流发送：

- 原始 RF 的 1 密度和跳变密度；
- RGMII 接收调试状态；
- 信道滤波后 `|I|+|Q|` 的平均值和峰值。

## 构建、烧录和运行

环境使用 Vivado 2019.1。Ethernet MAC 复用本机参考工程：

```text
E:\doc\WORK_SPACE\mix\verilog-ethernet-anlogic\rtl
```

在 PowerShell 中执行：

```powershell
cd E:\doc\WORK_SPACE\mix\fpga-radio\k9plus-fm-radio
python scripts\gen_coeffs.py
.\sim_fm.ps1
.\sim_udp.ps1
.\sim_raw.ps1
.\sim_iq.ps1
.\build.ps1
.\program.ps1
python -m pip install -r host\requirements.txt
```

`program.ps1`只写入FPGA易失配置；确认功能正常后，用下面的命令写入板载
MX25L12845G 128 Mbit SPI Flash、回读校验，并触发一次从Flash重新配置：

```powershell
.\program_flash.ps1
```

脚本使用XI050CD厂商提供的`Flash_Write_Protect_Cancel.bit`解除写保护，随后由
Vivado完成擦除、写入和VERIFY。只有日志出现
`K9PLUS_FM_FLASH_PROGRAM_VERIFY_PASS`才表示固化校验成功。

统一上位机（音频、调谐、6 MHz频谱和瀑布）：

```powershell
python host\k9fm_sdr.py --device 3 --control-bind 169.254.172.8
```

宽带显示数据来自独立的6 MS/s复数IQ流，覆盖中心频率两侧各约3 MHz；双击
频谱或瀑布中的频率即可调谐。左右方向键每次移动100 kHz，`M`切换静音。
界面还集成音量和原始/6 kHz/4.5 kHz/3.5 kHz四档音频选择。旧的轻量音频
程序仍保留为`host/k9fm_receiver.py`。统一上位机默认使用与Initial commit一致的
仅6 kHz低通（无额外高通）和1.0音量；4.5/3.5 kHz作为弱信号可选档。

如果声卡编号变化：

```powershell
python host\k9fm_receiver.py --list-devices
```

网口调谐示例：

```powershell
python host\tune_radio.py 95.0 --bind 169.254.172.8
python host\tune_radio.py 96.8 --bind 169.254.172.8
```

调谐控制不再限制为88～108 MHz，FPGA和全部上位机工具接受控制协议可表示的
0～4294.967295 MHz。实际RF采样率为240 MS/s，因此0～120 MHz是唯一的第一
Nyquist区；更高频率仍可下发，但会按240 MHz周期折叠到相应混叠频率。

### 原始1-bit bypass采集

上位机可通过UDP/50001发送`K9MD`命令，在正常48 kS/s音频模式和原始RF
bypass模式之间切换，无需重新编译。手动切换命令为：

```powershell
python host\tune_radio.py --mode bypass
python host\tune_radio.py --mode audio
```

通常直接使用自动采集脚本；它会先调谐、进入bypass、校验连续性、保存文件，
并在成功或失败后都恢复音频模式：

```powershell
python host\capture_raw.py 95.0 --seconds 0.25 `
  --output captures\raw_2026-10-18\fm_band_snapshot.k9raw
```

bypass取样点位于`IBUFDS + IDDR`之后、NCO之前。240 MS/s bitstream按LSB
优先打包，原始数据率30 MB/s；FPGA通过4 KB异步FIFO跨到125 MHz以太网域，
在UDP/50002发送。每个标准MTU数据报包含32字节`K9RF`头和1440字节原始
数据，即11520个样本。头中包含包序号、调谐标签、采样率、首样本索引和FIFO
溢出计数。`capture_raw.py`发现任何包缺失、样本索引跳变或FIFO溢出都会失败，
不会把有缺口的数据伪装成仿真基准。

正常音频模式还会在UDP/50003发送`K9IQ`宽带显示包：每包32字节头和1440字节
有符号I8/Q8交错数据，共720个6 MS/s复数样本。显示负载为96 Mbit/s，且
上位机每32包批量转换并写入环形缓冲，避免逐包加锁。该流只用于频谱/瀑布显示，
不会进入或改变原有960 kS/s信道滤波、FM鉴频和48 kS/s音频链。进入raw bypass
时暂停`K9IQ`，避免与240 MS/s原始抓取争用带宽。

### HDSDR 接入

仓库的`ExtIO`目录提供32位`ExtIO_K9Plus_FM_6M.dll`，可把同一条6 MS/s
`K9IQ`流直接送入HDSDR，并随HDSDR本振调谐FPGA。安装和构建步骤见
[`ExtIO/README.md`](ExtIO/README.md)。2026-10-25已修复IQ跨时钟FIFO启动时
多写一个旧字节造成的I/Q错位。最终版本使用16位`{Q8,I8}`原子FIFO，从结构上
禁止冷启动落在半个复数样本上；断电重启后94.8 MHz实采的圆度误差为0.00024，
故意错位后为0.78571，峰值镜像抑制约71.5 dB。DLL另有约15 Hz的复数直流
阻断器，用于去除I8量化形成的频谱中心固定峰。

`K9RAW1`文件的64字节自描述头、读取方法和首批实板数据见
[`captures/raw_2026-10-18/README.md`](captures/raw_2026-10-18/README.md)。

快速查看链路、占空比和信道幅度：

```powershell
python host\probe_packets.py --count 40
```

上位机频谱窗口按键：

| 按键 | 音频模式 |
|---:|---|
| 0 | 原始音频 |
| 1 | 75～6000 Hz 宽带 |
| 2 | 90～4500 Hz 清晰模式 |
| 3 | 100～3500 Hz 弱信号窄带 |

## 里程碑实测

2026-10-17 的代表性数据：

| 频率 | 状态 | 信道平均/峰值 | PCM RMS |
|---:|---|---:|---:|
| 94.7 MHz | 邻近空白点 | 约 358 / 1124 | 约 3972 |
| 95.0 MHz | 音乐台 | 约 626 / 2183 | 约 4438 |
| 96.0 MHz | 强静音载波 | 约 4224 / 8841 | 约 275 |
| 96.8 MHz | 音乐台 | 约 532 / 1666 | 约 5790（早期鉴频版本） |

95 MHz 相对空白点的信道幅度优势只有约 4.9 dB，已经接近 FM 门限区，
所以会出现明显的阈值噪声。96 MHz 强载波能够安静解调，说明 NCO、FIR、
鉴频、音频和以太网链路工作正常。

当前bypass位流已通过FM/UDP仿真、布线、DRC和时序检查。

### 6 MHz频谱/瀑布里程碑（2026-10-18）

- FPGA新增与原接收链并行的240 MS/s→6 MS/s复数CIC监视通道，中心两侧各显示
  约3 MHz；原960 kS/s信道滤波与48 kS/s音频路径保持不变；
- 显示支路改用I8/Q8，6 MS/s负载由192降到96 Mbit/s；每包由360增至720点，
  包率由约16.7k降到约8.3k/s。上位机以32包为一批接收，并将FFT从
  8×16384降为4×8192、显示刷新降至约6.7 Hz；
- 实板同时验证5000个IQ包和40个音频包均零丢失，IQ FIFO零溢出，IQ范围约
  -77～77，无8位削顶；
- raw bypass实板回归采集2,407,680点、零丢包，退出后IQ和音频均自动恢复；
- 新位流已固化到MX25L12845G、通过回读VERIFY并从Flash重启。SHA-256：
  `2349534F3320B6EF8E810AF335B00927AB282A509B3CD5FA2A2893E56018C7CD`；
- 布线后WNS为+0.251 ns、WHS为+0.037 ns，所有时序约束满足，DRC无错误。

## 下一阶段

按预期收益排序：

1. 将门限占空比从约 0.6 精调到 0.5，建议先把上拉总阻值试为 1.47 MΩ；
2. 增加对准目标台的可调预选器，并抑制实测 95.9866 MHz 强阻塞；
3. 如果允许有源器件，在预选器后加入约 10～15 dB 的低噪声 RF 增益；
4. FPGA 侧继续尝试自适应信道带宽、PLL 型鉴频和相位脉冲抑制。

仅靠当前无增益、无预选的阻容前端，不能承诺商用收音机的灵敏度和抗阻塞
能力。详细历史、位流哈希和交接信息见 [HANDOFF.md](HANDOFF.md)。

## 数字算法剩余空间（实采 A/B）

同一份 240 MS/s 原始位流与现有 WAV 的定量复核表明：可选的 4.5 kHz
播放滤波有约 1.7～2.0 dB 净 program/noise 改善；切到 3.5 kHz 弱信号档
约为 2.1～2.4 dB。现有相关向量鉴频已经消除了大角度相位脉冲，继续限幅在
实采数据上是 0.00 dB，因此没有加入无效逻辑。保持音质的数字算法现实剩余
空间约 1～3 dB；接受窄带、谱门伪影和 480 MS/s 风险时，激进上限约 4～6 dB。

原始宽带谱还检测到 95.9866 MHz 强载波，它在 1-bit 比较器之前压制弱台，
是 95.0/96.8 MHz 接收效果的主要限制。完整 dB 预算、实验门槛和可重复命令见
[DSP_OPTIMIZATION.md](DSP_OPTIMIZATION.md)。
