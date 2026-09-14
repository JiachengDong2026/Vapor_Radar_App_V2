# V1.2 -> V1.3 版本变更说明

责任分工不变，本次只冻结新的多源数据通路。

1. DILA 正式输出由 `msg_stream` 改为 `bulk_stream`。
2. DILA 每 WMS 周期的两条谐波曲线使用 DILA_BLOCK V2，并默认按 256 点/fragment 分片。
3. DILA0/1 各自独立 bulk FIFO，至少缓存 2 个最大 fragment。
4. 七个低速传感器各自独立 `msg_stream` + 独立 FIFO。
5. 项目负责人实现 `sensor_hub`（message-locked RR）和系统 `stream_arbiter`（priority + RR + burst cap）。
6. 禁止任何 beat-level 多源交错。
7. 公共基线升级为 `COMMON_INTERFACE_SPEC_V1.1` / `FPGA下位机Verilog开发指南_V1.1`。
