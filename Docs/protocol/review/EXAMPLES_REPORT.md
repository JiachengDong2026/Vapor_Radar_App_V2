# EXAMPLES_REPORT

日期：2026-09-19。交付范围只包含 `examples/` 与本报告；未改动 RTL、实测源目录、固件或硬件状态。

## 来源核对

- `fx3_gpif_debug_20260918/host/SensorRun.cs`：CRC 算法、header、READ/WRITE 参数、response 校验、IN 四字节对齐、host 1 MiB 单帧策略。
- 同目录 `analyze_capture.py`：40 字节 header、total=44+payload、CRC 覆盖和 padding。
- 同目录 `analyze_sensors.py`：小样本传感器字段及健康分类；重建时 import 前禁用 Python bytecode，未在源目录写 `__pycache__`。
- `integrated_20260916/lead_system/rtl/vlp_cmd_rx.v` 与 `vapor_lidar_top.v`：默认 4096 字节命令缓存、错误候选逐字节恢复。
- 同目录 `cmd_decoder.v`：READ 最大 1021、simple WRITE 布局/限制、PING echo、response source/sequence/message/status 与成功 READ layout。
- commands/read_system.bin 与 reports/sensor_six_60s_01/request_1009.bin：生成请求逐字节一致。
- 已保存的 ping_response_seq1.bin、response_1002.bin、response_1009.bin：真实 response golden，不执行任何请求。

## 已完成验证

```powershell
python -B examples/build_examples.py E:/Documents/Vapor_Lc_App_Test/fx3_gpif_debug_20260918
python -B examples/test_vlp_reference.py
python -B examples/vlp_reference.py examples/capture_example.bin --chunk-size 7
```

Python 3.13.5 下，离线 unittest 共 13 项全部通过。覆盖 CRC 标准 check vector、golden、所有单切分位置、1/3/7/39/40/43/64/127/16384 字节输入块、粘包、坏 CRC 后恢复、坏外层帧内完整帧恢复、长度/版本/补零错误、合法伪长帧等待与 EOF/调用方超时恢复、discard budget、响应三字段及 READ 地址/count 匹配、非零 status、命令长度与地址边界。另外验证 1 字节 PING 的 total=45/wire=48/补零不计入 CRC，并验证默认 IN 上限 8236 可通过、8237 非法长度后可恢复下一帧。

参考 parser 的默认单帧限制已按当前集成 IN 最大 payload=8192 配置为 8236 字节；这是当前实现上限。已有 SensorRun 使用 1 MiB 是较宽松的 host 策略，不作为本示例默认或协议能力。所有 pack 命令函数均返回包含 GPIF 四字节对齐补零的 wire bytes；三个 golden 命令原本均对齐，字节未改变。

完整源 capture 共 7,278,076 字节、91,087 帧，增量 CRC/对齐扫描无丢弃、无错误、无尾部残留。仅将 9 帧共 656 字节复制到小样本，不导出完整大体积解析 JSON。每个摘录帧在 summary 中列出源文件偏移、摘录偏移、字节长度和 SHA-256。样本保留六路数据、BMP metadata 和两条实际响应。

## 不能误读的结果

AI8 样本 `flags=0x11`、`host_status=0x200`、online=true，但原分析器判为 flagged_sample；因此 summary 的 `all_six_have_valid_samples=false` 是应保留的实测结果。BMP390 原始 ADC 未换算为 Pa/°C。EPSILON 通信 CRC 正确不表示定位有效。摘录不是连续采集，不能用于推断采样率或序号丢失。

示例仅验证协议编解码与保存文件，不包含真实 USB 收发、CyUSB/libusb 绑定、设备发现、连接重试/超时策略、写入原子性或线程安全。parser 恢复策略是 host 参考实现，不代表 FPGA 每项错误策略完全相同；CRC 正确才输出帧。传感器完整解码保留在 summary 与原 analyzer，参考 CLI 输出 payload hex 和响应 essentials。未运行新的硬件回归或 Vivado，因本任务没有 RTL/固件修改或硬件授权需求。
