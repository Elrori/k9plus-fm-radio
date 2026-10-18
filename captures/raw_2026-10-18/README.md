# 2026-10-18 原始1-bit RF基准

本目录保存K9+实板在**现有外部电路完全不变**条件下，从`IBUFDS + IDDR`
之后、NCO之前直接取得的240 MS/s 1-bit数据。实装仍为拉杆天线、1 nF C0G、
100 Ω串联、RF_P到VBIAS 1 kΩ、RF_P到3.3 V 1 MΩ、RF_N直连VBIAS；采集时
VBIAS约1.189 V。

每份文件包含60,007,680个连续样本，时长0.250032秒，接收5209个UDP包；
全部满足包序号连续、样本索引连续、主机丢包为0、FPGA FIFO溢出为0。旁边的
JSON记录完整SHA-256和机器可读元数据。

| 文件 | 分析标签 | 一密度 | 跳变密度 | SHA-256 |
|---|---:|---:|---:|---|
| `fm_95p0.k9raw` | 95.0 MHz音乐台 | 0.578021 | 0.526754 | `F2524C7648DA9D438FE7A3F6B7C6588FEA4BF2BEFD3DAAFE8DC8D28282F606F3` |
| `fm_96p0_silent.k9raw` | 96.0 MHz静音载波 | 0.574562 | 0.527746 | `AE183B377B2A75F3D5BE85288C82A2527666DDCFCD918830AC97E784300B313A` |
| `fm_96p8.k9raw` | 96.8 MHz音乐台 | 0.574055 | 0.519636 | `E7982A9FF0F28614093F035678B7A0DBBC0D0B9FC737521930D5F4E7D8764AE5` |
| `blank_94p7.k9raw` | 94.7 MHz邻近空白点 | 0.577095 | 0.517796 | `93E6F1EB609591993E8C8B5BFC841A64C2136D1E023DB3C05AB818DC90A1F325` |

“分析标签”不是模拟预选：bypass位于NCO之前，所以每份文件都包含整个
0～120 MHz第一Nyquist区的同一类宽带输入，可在离线仿真中重新调到任意FM
频率。多份文件用于覆盖不同时刻的节目内容和输入噪声变化。

读取和解包：

```powershell
python host\read_k9raw.py captures\raw_2026-10-18\fm_95p0.k9raw
python host\read_k9raw.py captures\raw_2026-10-18\fm_95p0.k9raw --npy build\fm_95p0_bits.npy
```

二进制文件头为64字节、小端序，Python `struct`格式是
`<8sIIIIIIQQIIII`；其后每字节保存8个时间连续样本，LSB在前。一个IDDR
周期内先保存Q1，再保存Q2。后续任何算法比较必须使用同一输入片段，并同时
报告目标频道相对94.7空白点和96.0静音载波的改善，不能只比较音频响度。
