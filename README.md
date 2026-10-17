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
| RF_P | U4-8 / FPGA J20 |
| RF_N | U4-12 / FPGA J21 |
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

拉杆天线 ── 1nF C0G ── 100Ω ──+── RF_P (U4-8 / J20)
                                 |
                                 +── 1kΩ ── VBIAS
                                 |
                                 +── 1MΩ ── 3.3V

RF_N (U4-12 / J21) ─────────────── VBIAS
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
.\build.ps1
.\program.ps1
python -m pip install -r host\requirements.txt
```

实时播放和频谱：

```powershell
python host\k9fm_receiver.py --device 3
```

如果声卡编号变化：

```powershell
python host\k9fm_receiver.py --list-devices
```

网口调谐示例：

```powershell
python host\tune_radio.py 95.0 --bind 169.254.172.8
python host\tune_radio.py 96.8 --bind 169.254.172.8
```

快速查看链路、占空比和信道幅度：

```powershell
python host\probe_packets.py --count 40
```

上位机频谱窗口按键：

| 按键 | 音频模式 |
|---:|---|
| 0 | 原始音频 |
| 1 | 75～6000 Hz 宽带 |
| 2 | 90～4500 Hz 清晰模式（默认） |
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

当前位流已通过 FM 仿真、布线、DRC 和时序检查；最终 WNS 为 +0.148 ns，
WHS 为 +0.019 ns，时序失败端点为 0。

## 下一阶段

按预期收益排序：

1. 将门限占空比从约 0.6 精调到 0.5，建议先把上拉总阻值试为 1.47 MΩ；
2. 在拉杆天线后增加以约 96 MHz 为中心的可调 LC 预选器；
3. 如果允许有源器件，在预选器后加入约 10～15 dB 的低噪声 RF 增益；
4. FPGA 侧继续尝试自适应信道带宽、PLL 型鉴频和相位脉冲抑制。

仅靠当前无增益、无预选的阻容前端，不能承诺商用收音机的灵敏度和抗阻塞
能力。详细历史、位流哈希和交接信息见 [HANDOFF.md](HANDOFF.md)。
