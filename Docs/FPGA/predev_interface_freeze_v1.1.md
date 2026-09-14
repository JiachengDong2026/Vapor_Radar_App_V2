# FPGA 公共流接口冻结规范 V1.1

本文件是后续 ADC/DILA、WMS/DAC、UART/Sensor 开发使用的唯一公共流接口参考。除发布新的接口版本外，不得修改下列位宽、字段语义和传输规则。

## 1. 通用握手规则

三类流均使用 `valid/ready` 握手。仅在时钟上升沿 `valid && ready` 时完成一个 beat；当 `valid=1 && ready=0` 时，生产者必须保持数据和全部 sideband 字段不变。

固定公共位宽：

| 字段 | 位宽 |
|---|---:|
| `source_id` | 16 |
| `msg_id` | 16 |
| `timestamp` | 64 |
| `cycle_id` | 32 |
| `flags` | 32 |

## 2. sample_stream

`sample_stream` 仅用于 ADC 样点级内部传输，不直接进入低速消息路径。

必需字段为 `valid`、`ready`、`data[31:0]` 和 `timestamp[63:0]`。一次握手传输一个样点。已接受样点的 timestamp 必须单调不减；生产者不得因下游背压而静默覆盖未发送数据。

## 3. msg_stream

`msg_stream` 用于 HMP、EPSILON 等低速传感器消息、状态和事件，不得承载 DILA 或 RAW ADC 大块数据。

必需字段为 `valid`、`ready`、`data[31:0]`、`source_id[15:0]`、`msg_id[15:0]`、`timestamp[63:0]` 和 `flags[31:0]`。多 beat 消息使用实现方既有的首尾标记；一条消息内的元数据必须保持不变。连续接收消息的 timestamp 必须单调不减。

## 4. bulk_stream

`bulk_stream` 专用于 DILA 曲线、RAW ADC 周期数据等大块数据。一个 `frame_start ... frame_end` 区间表示一个独立 fragment，不能当作普通 `msg_stream` 处理。

必需字段为 `valid`、`ready`、`data`、`source_id[15:0]`、`msg_id[15:0]`、`timestamp[63:0]`、`cycle_id[31:0]`、`frame_start`、`frame_end`、`fragment_index[31:0]` 和 `fragment_count[31:0]`。一个 frame 内 `source_id`、`msg_id`、`timestamp`、`cycle_id`、`fragment_index` 和 `fragment_count` 必须保持不变。

## 5. ID 规则

- `source_id` 标识数据生产者，完整 16 位必须端到端保留，禁止截断成 8 位。
- `msg_id` 标识 payload 类型，完整 16 位必须端到端保留，禁止截断成 8 位。
- 当前公共验证使用 HMP `source_id=0x0020, msg_id=0x1100`，EPSILON `source_id=0x0021, msg_id=0x1200`，DILA 示例 `source_id=0x0030, msg_id=0x2000`。

## 6. timestamp 规则

timestamp 是 64 位公共时间基准快照。生产者应在消息或 fragment 建立时锁存 timestamp；同一 frame 内不得变化。接收端对连续记录执行单调不减检查，即 `timestamp_next >= timestamp_previous`。回绕不属于 V1.1 的正常运行场景。

## 7. cycle_id 规则

cycle_id 是 32 位 WMS 扫描周期编号。同一 WMS 周期产生的所有相关 fragment 使用相同 cycle_id；每次新的扫描周期递增一次，按 32 位自然回绕。与 WMS 周期无关的数据使用其模块规范指定的保留值。

## 8. fragment 规则

fragment_index 从 0 开始且必须小于 fragment_count。同一逻辑记录的 fragment 必须按 `0, 1, ..., fragment_count-1` 连续发送，不允许跳号、重复或在完成前重新从 0 开始。最后一个 fragment 完成后，下一条逻辑记录重新从 0 开始。每个 fragment 必须具有完整且不嵌套的 `frame_start ... frame_end` 边界；单 beat fragment 可同时置位二者。

## 9. WMS 冻结参考接口

仿真参考源输出 `scan_start`、`phase_valid`、`cycle_id[31:0]` 和 `phase[31:0]`。phase 每个有效时钟递增 1，按 32 位自然回绕；回绕时产生单拍 scan_start，并令 cycle_id 递增。
