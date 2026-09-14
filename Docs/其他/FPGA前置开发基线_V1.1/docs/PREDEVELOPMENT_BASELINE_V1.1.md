# 成员开工前置基线 V1.1

本版本取代 V1.0。除原有公共接口外，正式冻结了多源并发数据通路。

## 已冻结

1. `cfg_bus`：统一寄存器总线；
2. `sample_stream`：ADC 样点级内部流；
3. `msg_stream`：低速/短消息流；
4. `bulk_stream`：DILA/RAW ADC 大块分片流；
5. WMS -> DILA phase/cycle reference；
6. `source_id/msg_id`；
7. 64-bit 时间戳；
8. 每源独立 FIFO 原则；
9. `sensor_hub` message-locked RR；
10. 系统 `stream_arbiter`：priority + RR + burst cap；
11. DILA V2 fragment schema，默认每 fragment 256 点、最大 payload 8192 B；
12. STREAM/BUFFER 和 DILA 新增寄存器。

## 成员开工规则

- 成员1：ADC 输出 `sample_stream`；DILA 正式输出改为 `bulk_stream`，每通道独立 FIFO/fragmenter。
- 成员2：WMS/DAC 接口无变化。
- 成员3：每个低速传感器拥有独立 `msg_stream` + 独立输出 FIFO；不得在成员内部把所有设备硬并到一条无仲裁总线。
- 项目负责人：实现 `sensor_hub`、系统 `stream_arbiter`、RAW bulk framer、packetizer 和 USB。

## 禁止事项

- 禁止多个 producer 直接驱动一套 stream wires；
- 禁止 arbiter 在一个消息/fragment 中途切换 source；
- 禁止 DILA 一个完整长周期不分片后长期占用系统总线；
- 禁止成员私自改变 fragment header、priority class 或公共 ID。
