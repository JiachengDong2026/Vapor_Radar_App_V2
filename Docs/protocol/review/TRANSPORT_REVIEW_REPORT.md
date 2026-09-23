## 传输协议子任务审查报告

日期：2026-09-19。交付：[TRANSPORT_COMMANDS.md](TRANSPORT_COMMANDS.md)。只读检查了源v2文档、封存集成FPGA RTL、当前FX3固件及已测主机工具；只创建本交付目录内文档，没有修改工程、固件、原始捕获或硬件。

### 已核实的交付重点

- 应用VID/PID=04B4:00F1，EP02 OUT和EP86 IN；固定40 B LE头；CRC在实际payload之后，CRC后零填充到4 B且不计帧长/CRC。
- CRC为ISO-HDLC，init/xorout FFFFFFFF，反射EDB88320；离线标准向量123456789=CBF43926。
- CMD完整帧≤4096 B，payload≤4052 B；IN payload≤8192 B。READ≤1021字，WRITE由ring限制为≤1011字。READ成功负载前导12 B，基本应答帧长56+4×count。
- RESP/7F回显请求sequence/source/msg；仅解析层错误使用7F，命令执行错误仍RESP02。不能仅以帧类型判成功。
- packetizer在每帧（含应答）后递增内部序号，而应答覆盖为主机请求seq。全流序号不是简单连续丢包计数。
- 接收解析器坏候选前进1 B重同步；超时约100 ms（100 MHz）。当前SensorRun为严格失败终止解析器，1 MiB上限不是硬件能力，生产主机应收紧至8236 B并添加恢复。
- GET capabilities FFFF为当前RTL常量，不能作为实物在线位图；扩展字bit0=RAW schema2。
- B0 word7高16=16384 B、低16=12，当前4000000C；计数是DMA buffer事件，不是VLP帧。B1=GP01，只读寄存器和phase快照；不是VLP。
- 已写明enum status、模块ERROR位图、FX3 last_error三种错误域区别；超时重试和顺序写不回滚语义；RAW分片schema2需独立处理，不能按USB边界重组。

### 证据优先级与限制

主要代码证据：FPGA `rtl/vlp_cmd_rx.v`、`cmd_decoder.v`、`data_packetizer.v`、`action_controller.v`、`adc_cycle_framer.v`、`vapor_lidar_top.v`；FX3 `src/cyfxslfifosync.c`、`src/cyfxslfifousbdscr.c`、`include/cyfxslfifosync.h`；实测工具 `host/SensorRun.cs`、`host/analyze_capture.py`、`host/generate_read_checks.py`。交付章节逐条列出精确行号。源v2指南仅用于命名及原始字段规范；冲突时采用封存RTL/当前实测固件。

未运行Vivado、未烧录或打开USB、未发送设备命令。本任务是交付说明，不修改RTL，因此未做工程回归，也不声称边界条件均经本次动态测试。DILA/事件/传感器详细payload与寄存器归主文档，不在本子任务重复定义。

### 本次离线验证结果

通过Python -B只读导入既有analyze_capture.analyze，对原始捕获重算全部CRC并验证长度/填充：continuous_capture_01 11680 B /154帧/154通过/0失败；auto_protocol_01 7816 B/103帧/103通过/0失败；sensor_six_60s_01 7278076 B/91087帧/91087通过/0失败。未写回捕获目录。首捕获第96帧PING seq1、source1、msgFE、status0、PING回显、CRC BFBEBCF3均通过。

确认只读请求样例read_system.bin为52 B，CRC DBB788C6，完整hex已放入协议章节，可作为主机codec的固定向量。
