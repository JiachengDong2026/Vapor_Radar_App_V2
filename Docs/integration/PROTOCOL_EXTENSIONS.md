> 正式归档：2026-09-23。本文源于2026-09-16集成版本；旧文中的Test专用、V2只读和当轮未上板描述属于当时记录。当前目录、六路既有实测及本轮离线边界以[正式集成修订](../INTEGRATION_REVISION_20260923.md)为准。

# 负责人协议实现与扩展记录

日期：2026-09-16。仅适用于 Test 中的实现，源 v2 目录规范未修改。

## RAW 周期分片

原指南 RAW schema 1 的 20 字节头没有 fragment 字段，但冻结 bulk 上限是 8192 字节。不能把长周期静默拆成多个伪完整 schema 1 周期。

本实现保留不超过 2043 点的 schema 1 原格式。较长周期采用 **RAW schema 2**，source_id、msg_id=0x1000、标准 bulk 端口及 VLP1 外层不变。旧解析器必须按 schema_version 跳过未知 payload；GET_CAPABILITIES 第 6 个数据字 bit0 表示支持 RAW schema 2。schema 版本独立于 VLP 帧版本。

| 偏移 | 类型 | RAW schema 2 字段 |
|---:|---|---|
| 0 | u16 | schema_version=2 |
| 2 | u16 | adc_bits |
| 4 | u32 | sample_rate_hz |
| 8 | u32 | total_sample_count，本周期实际存储的点数 |
| 12 | u32 | sample_format，0=signed32，1=unsigned32 |
| 16 | u16 | fragment_index，从 0 起 |
| 18 | u16 | fragment_count |
| 20 | u32 | first_sample_index |
| 24 | u32 | fragment_sample_count |
| 28 | u32 | reserved=0 |
| 32 | s32/u32[] | samples |

默认每 fragment 最多 2040 点，payload 最多 8192 字节。周期元数据来自 ADC FIFO 中保存的 capture_cycle_id/cycle_timestamp；不使用发送时的当前 WMS 周期。一个周期各分片共享时间戳、cycle_id 和聚合 flags。

每路两个完整周期 bank。建议系统 ADC0 每 bank 16384 点、ADC1 每 bank 131072 点，对应默认 1 MSPS/12.5 MSPS、100 Hz 扫描周期；系统集成时须核对实际采样率。超过 bank 容量保留前缀并置 OVERFLOW_SINCE_LAST/PARTIAL_DATA、累计丢点；两 bank 都占用则丢弃整个新周期，不在释放 bank 后接收该周期尾部。更低扫描频率可超过片上容量，必须查询丢点计数并调整配置。

RAW mask 关闭时完成当前已存储前缀并置 PARTIAL_DATA；重新打开时跳过已观察到的当前周期尾部，等待下一 capture cycle。STOP/flush 在最后一个有效 capture 标签样点后空闲 1024 个 sys_clk，再提交半周期，保留既有 FIFO 输出以便排空。

## VLP1 传输

固定 40 字节头，little endian，CRC32/ISO-HDLC：反射多项式 0xEDB88320、初始和最终异或均 0xFFFFFFFF。CRC 覆盖 header+实际 payload。CRC 后补 0 到 32 位 GPIF 边界，padding 不计 total_len/payload_len/CRC。RESP 和 PROTOCOL_ERROR 原样回显请求 sequence。

packetizer 先缓存一个完整 fragment，检查 SOF/LAST、连续 KEEP、稳定元数据和最大 payload，才输出头。非法 fragment 整体丢弃并累计 format_error_count。最后一个 beat 允许 KEEP=1/3/7/F；空 payload 通过 SOF=LAST=1、KEEP=0 表示。

命令最大完整帧 4096 字节（payload 最多 4052 字节）。接收 ring 保留错误候选，CRC/长度/版本失败后仅跳过候选 magic 第一个字节，重新扫描已接收内容；因此坏帧内部的有效完整命令仍可恢复。只有 CRC 已验证的命令才能触发 cfg_bus 或 action。接收超时为默认 10000000 sys_clk；等待响应背压时不会触发收帧超时。

## 已实现命令负载约定

READ/WRITE/MASKED、COMMIT、START/STOP、SET_STREAM_MASK 采用原指南字段。READ 成功返回 status/addr/count/reserved/data；失败仅返回 status。顺序多寄存器写遇到错误停止，之前已完成的写不会回滚；auto_commit 仅在全部写成功后执行。

原指南未给出以下具体 payload，负责人在 Test 中固定为：

- RESET_MODULE/CLEAR_ERROR：u64 module_mask，采用 source_id & 0x3F 位映射。
- SENSOR_ACTION/MOTOR_ACTION/TIME_ACTION：u32 action，u32 value。具体 action 路由表随 action_controller 实现提交，不将设备私有协议暴露到 USB。
- PING：任意 payload，返回 u32 status + 原始 payload。
- GET_CAPABILITIES：空请求；返回 7 个 u32：status、能力位图、协议版本 0x00000100、TIME_CLK_HZ、最大 bulk payload 8192、最大命令帧 4096、扩展能力位图（bit0 RAW schema 2）。能力位含义应以最终系统接口说明为准。

2026-09-16 修订：保留 cfg_error 布尔错误并追加 cfg_error_code[3:0] 原因侧带。各slave直接区分地址5、只读6、范围7、忙8；crossbar超时返回9。原因经crossbar/arbiter/action/decoder原样传回VLP，错误码枚举不等于模块ERROR位掩码。21页ID写只读拒绝与9项真实范围错误均通过完整GPIF50命令测试；细节见 [CFG_ERROR_CODES.md](CFG_ERROR_CODES.md) 与 `reports/CFG_ERROR_VALIDATION.md`。各模块ERROR/STATUS仍用于设备运行诊断，不能将后台传感器轮询超时冒充为cfg事务超时。

## 动作控制器路由

实现与具体 action/value 取值见 [ACTION_CONTROLLER.md](ACTION_CONTROLLER.md)。START 先无副作用预检，再 SYSTEM enable→ADC→DILA→DAC→WMS；STOP 保留既有数据，先停 WMS，再停消费者，至少等待2048 tick与所选数据路径idle。WMS位代表WMS/DAC联合commit，执行停WMS→DAC idle→commit DAC→DAC ready→commit WMS→pending clear→恢复原enable。HMP/AI8成功必须有WRITE_ACK_COUNT增长。

冻结source_id&3F掩码存在别名。SYSTEM/FFFF广播掩码解释为采集源集合；TIME RESET/CLEAR须明确source0002，广播bit2表示EPSILON；STREAM0050不会被误路由为WMS0。全局系统软复位仍使用SYSTEM CONTROL寄存器，不包含在广播RESET_MODULE中。START/STOP选择WMS、ADC、DILA任一位会控制对应完整采集通道；options/reserved暂仅接受0。

## 2026-09-16 decoder 修订：范围预检与自动提交

READ/WRITE 在任何 cfg 读写前逐页验证完整地址范围的 source ownership。
例如 source0010 虽拥有20和30页，从20FC连续访问到3000仍经过无权访问的21..2F页，
整体返回ERR_BAD_SOURCE=4，且不产生任何cfg读写。SYSTEM/FFFF仍可执行普通跨页访问。
MASKED_WRITE仅检查单个对齐地址。末地址按最后一个被访问字节计算，FFFF为合法范围终点。

WRITE 的 AUTO_COMMIT(bit16) 现在仅允许**同一个256字节页内**的写入。
跨页返回ERR_OUT_OF_RANGE=7，无提交支持的页返回ERR_UNSUPPORTED=13，均在第一次写入前拒绝。
合法写入全部成功后，decoder将内部action切换为COMMIT(5)，使用以下精确source和单bit掩码：

| 写入页 | 内部action source | module_mask位 | 完成条件 |
|---|---|---|---|
|20、30 / 21、31|0010 / 0011|16 / 17|WMS/DAC联合提交、恢复原WMS enable|
|40 / 41|0020 / 0021|32 / 33|ADC pending清除|
|50 / 51|0030 / 0031|48 / 49|DILA pending清除|
|60..66|0040..0046|0..6|sensor pending清除；HMP61/AI866还必须ACK计数+1|

SYSTEM、TIME、时钟控制、STEPPER67、STREAM70、USB80等其余页不支持AUTO_COMMIT。
对DAC30/31页写入同样执行所属WMS的联合提交，不能直接脉冲DAC CONTROL.bit2。
USB响应保留原WRITE的msg_id、source_id、sequence，status反映整个action完成或失败。
总超时返回9并撤销内部action请求；已经完成的shadow写入或设备已接收的操作不会回滚。
超时后设备仍可能稍后ACK，主机应查询STATUS/ERROR/ACK_COUNT/active寄存器后决定下一步。

版本记录：本修订保留VLP1格式、冻结ID和cfg/action端口，收紧非法范围与自动提交语义。
25帧旧golden响应逐字节保持一致；其mock action模拟成功提交，真实顺序/ACK另由
`tb_decoder_action.v`验证，避免将旧mock寄存器CONTROL.bit2的保存行为视为硬件契约。


本版source0046更换为AI8（ID 00460200），MSG1100负载schema2，raw温度与状态标签0460..0467。原RD105解析不适用。AI8 ACK_COUNT仅在写后读回匹配时增长。详见AI8_INTEGRATION_REPORT.md。
