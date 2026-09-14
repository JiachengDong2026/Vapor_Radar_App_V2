# FPGA 前置开发基线 V1.1

V1.1 是三名成员正式开工的数据流接口基线，取代 V1.0。

主要变化：

- `msg_stream` 仅用于低速消息；
- 新增 `bulk_stream`，用于 DILA 曲线和 RAW ADC；
- DILA 每 WMS 周期输出两条谐波曲线，可按 256 点分片；
- 每数据源独立 FIFO；
- sensor_hub 采用消息级 RR；
- 系统 stream arbiter 采用优先级 + 同级 RR + burst cap 防 starvation；
- 更新 DILA/STREAM 寄存器。
