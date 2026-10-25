# HDSDR ExtIO（K9+ FM 6 MS/s）

`ExtIO_K9Plus_FM_6M.dll`把FPGA在UDP/50003发送的`K9IQ` v2数据交给HDSDR：

- 输入：6 MS/s、有符号I8/Q8交错、每包720个复数样本；
- 输出给HDSDR：ExtIO type 3、有符号I16/Q16交错；
- 丢失少量UDP包时按样本索引补零，避免后续样本错位；
- DLL使用约15 Hz截止频率的复数直流阻断器，抑制I8量化造成的中心固定峰；
- HDSDR改变LO时，通过UDP/50001向FPGA发送`K9TU`调谐命令；
- 默认控制广播地址为`192.168.10.255`，可用环境变量
  `K9PLUS_CONTROL_HOST`覆盖。

构建32位DLL：

```powershell
.\ExtIO\build_extio.ps1
```

把`ExtIO\Release\ExtIO_K9Plus_FM_6M.dll`复制到32位HDSDR安装目录，重新启动
HDSDR并选择`K9+ FM 6M / UDP IQ8`。HDSDR声明有效带宽为4.8 MHz，硬件采样率为
6 MHz；初始中心频率95 MHz，可在0～120 MHz内调谐。

2026-10-25新DFE采用CIC /20与63tap补偿抗混叠FIR /2，平坦通带±2.4MHz。
flags bit2标识此模式，旧DLL仍能接收新位流；新的DLL收窄声明的有效带宽。

运行HDSDR前应关闭`k9fm_sdr.py`等占用UDP/50003的程序。Windows通常会把广播
包复制给多个`SO_REUSEADDR`套接字，但独占运行更便于判断丢包和性能。
