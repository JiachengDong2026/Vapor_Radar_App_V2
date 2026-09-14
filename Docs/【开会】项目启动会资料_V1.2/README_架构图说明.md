# 架构图说明

当前 PNG 架构图仍可用于讲解设备、物理接口、成员责任和 USB 主链路。

但图中数据流细节以 `项目启动会讲解稿_V1.2.md` 为准：

- DILA/RAW ADC 正式走 `bulk_stream`；
- 低速传感器走 `msg_stream`；
- 每 source 独立 FIFO；
- DILA 分片；
- sensor_hub + stream_arbiter 两级仲裁。

后续若重绘架构图，应把上述 V1.1 数据通路直接画入图中。
