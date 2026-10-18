# 2026-10-18 原始1-bit RF基准

本目录保存K9+实板在**现有外部电路完全不变**条件下，从`IBUFDS + IDDR`
之后、NCO之前直接取得的240 MS/s 1-bit数据。实装仍为拉杆天线、1 nF C0G、
100 Ω串联、RF_P到VBIAS 1 kΩ、RF_P到3.3 V 1 MΩ、RF_N直连VBIAS；采集时
VBIAS约1.189 V。

保留的文件包含60,007,680个连续样本，时长0.250032秒，接收5209个UDP包；
满足包序号连续、样本索引连续、主机丢包为0、FPGA FIFO溢出为0。旁边的JSON
记录完整SHA-256和机器可读元数据。

| 文件 | 分析标签 | 一密度 | 跳变密度 | SHA-256 |
|---|---:|---:|---:|---|
| `fm_band_snapshot.k9raw` | 宽带快照（采集时控制标签95.0 MHz） | 0.578021 | 0.526754 | `F2524C7648DA9D438FE7A3F6B7C6588FEA4BF2BEFD3DAAFE8DC8D28282F606F3` |

“控制标签”不是模拟预选：bypass位于NCO之前，所以该文件包含整个0～120 MHz
第一Nyquist区，可在离线仿真中重新调到任意FM频率。最初也在96.0、96.8、
94.7 MHz标签下采集并验证过三份文件；它们只是其他时刻的同类宽带输入，不能
作为独立的逐台基准，因此已去重。

读取和解包：

```powershell
python host\read_k9raw.py captures\raw_2026-10-18\fm_band_snapshot.k9raw
python host\read_k9raw.py captures\raw_2026-10-18\fm_band_snapshot.k9raw --npy build\fm_band_bits.npy
```

二进制文件头为64字节、小端序，Python `struct`格式是
`<8sIIIIIIQQIIII`；其后每字节保存8个时间连续样本，LSB在前。一个IDDR
周期内先保存Q1，再保存Q2。后续任何算法比较必须使用同一输入片段，并同时
在同一原始片段内同时解调目标台、96.0静音载波和邻近空白频点，报告相对改善，
不能只比较音频响度。
