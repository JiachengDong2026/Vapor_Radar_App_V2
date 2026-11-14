# HMP / AI8 双设备实测基线恢复（2026-10-27）

用户要求将 HMP 和 AI8 的控制与通信恢复为刚才实测通过的版本，并明确选择同时恢复 CON19 双设备仲裁、撤回 RD105 第三路接入。恢复源为 GitHub 同步前工作 HEAD `d2e2f8f7af1f3dbbb336e4706c000eedb3043faf`；本次工作建立在同步后的 `9f45e49` 之上，不整体回退 Git 分支。

## 当前接口

- HMP：source `0041`、page `6100`、identity `00410103`，FC03 读取 `0000..0003`，上传 schema 1 的 RH/T。共享模式固定 19200/8N1，默认地址 240；单独实例的 8N2 默认保持原样。压力补偿显式 COMMIT 与 ACK 计数语义恢复原实现。
- AI8：source `0046`、page `6600`、identity `00460200`，19200/8N1、默认地址 1。`661C` 在禁用态选择 1..8 中的一个通道，七次 FC03 形成完整快照，上传 schema 2。保留 COMMIT / SENSOR_ACTION 17 设温和独立读回确认；不提供自动扫描、schema 3、`6668/666C` 或 `6680..66FC` 扩展接口。
- CON19：HMP / AI8 两路完整 Modbus 事务仲裁，含响应、超时、重试及安静时间；默认均禁用，不在启用时自动写仪表配置。pins 1/2 为 B/−，pin 3 为信号地，pins 4/5 为 A/+。
- `member3_sensor_bank` 恢复七个 lane（PTB/HMP/EPS/BMP/SHT/TFA/AI8），顶层恢复原 21 页 crossbar、状态轮询和对应 stream 宽度。独立 source `0048` / page `6800` 不再映射，命令源及 action 18 支持撤回。`SRC_RD105` / `REG_BASE_RD105` 仅保留旧的 `0046/6600` 历史别名，生产 bank 在该位置实例化 AI8，不是另一台设备。旧 RD105 standalone 模块仅为旧测试与接口兼容保留。
- 扩展能力 word 从 `0x3F` 调整为 `0x29`（RAW schema 2、EPSILON 下行/RTCM、DLIA 截止频率），bit1/2/4 清零；公共宏、协议说明、命令黄金帧及其 CRC 同步调整。

## 保留的更新

EPSILON MAIN 下行邮箱、独立 correction TX、RTCM 包装/校验与 DLIA 截止频率档位保留。顶层与 bank 只为保留 EPSILON correction TX 增加相应端口/连线，HMP/AI8 物理接线和双设备仲裁来自恢复基线。其他 ADC/WMS/FX3/Qt 上位机文件不因本次恢复回退。

与已撤回接口绑定的 AI8 scan、RD105 parameters / sensor-bank、三方 RS485 仲裁测试撤下；原 HMP、AI8 poll/setpoint/shared-bus、七 lane 与配置原因码测试恢复。配置回归增加已撤回 AI8 地址和 page 6800 的拒绝检查，命令和顶层黄金向量使用当前 `0x29` 能力值。

## 实测证据与边界

此前板卡双设备采集得到 HMP 58 条、AI8 56 条有效记录，timeout/CRC/FIFO drop 增量均为 0。HMP 最新 21.9854°C、59.0100%RH；AI8 PV 22.4°C、SP 40.0°C。AI8 HOST `0200`，7 条 ALARM `20`、其余 `00`，设备报警标志未清除。首次短 USB 等待的采集中断，延长 USB 等待后完整复测通过，不能据此声称长期 USB 稳定性已验收。

原始记录位于 `E:/Documents/Vapor_Lc_App_Test/hmp_ai8_shared_20261027_01/`。本次恢复的是该次测试前 V2 的通信源码基线，整个当前工程仍包含其他新版功能；不是将既有 BIT 冒充当前组合源码的新构建，也不把之前实测扩大为当前完整组合版本已上板通过。本轮不写仪表参数、不重新烧录 FPGA。

本轮源码比对与仿真证据保存到 `E:/Documents/Vapor_Lc_App_Test/restore_hmp_ai8_20261027_01/`。`source_identity.json` 验证 HMP、AI8 wrapper/core、仲裁、Modbus master、UART RX/TX 和 record FIFO 与基线一致；bank/top 除保留的 EPSILON correction TX 外也与基线一致。`validation_inputs.json` 保存当前 95 个生产输入文件的 SHA256；`restoration_manifest.json` 及 `before/` 保存恢复前文件和哈希。

## 本轮离线验证

`check_baseline.py` 输出 `BASELINE_STATIC_CHECK_PASS`，`git diff --check` 通过。现有用户未跟踪资料的 11 个 SHA256 均与本轮同步前清单一致。

Vivado 2020.2 的以下 14 个 testbench 均有正常 `$finish` 与 PASS，详见外部 `rtl_results.json`、`regression/` 和 `bank_regression/`：

```text
tb_hmp_modbus_rs485       tb_ai8_poll
tb_ai8_setpoint           tb_ai8_sample_epoch
tb_ai8_shared_bus         tb_sensor_cfg_error_codes
tb_action_ai8             tb_cmd_decoder
tb_action_controller      tb_vapor_lidar_top
tb_rd105_uart             tb_epsilon_downlink
tb_dila_cutoff            tb_seven_devices
```

双设备回归覆盖完整事务仲裁、错误/超时、设温写后读回、FIFO 背压、禁用取消和时间同步标签。配置原因码回归通过 157 项检查，包含已撤回 AI8 地址和 RD105 页拒绝。顶层 USB/GPIF 仿真通过 73 个命令应答、21 页路由和只读保护、能力位黄金帧及 CRC 拒绝检查。七设备并发得到 packet counts `19,11,64,4,14,358,2`，验证 HMP/AI8 均有进展且轮询不触发设备写入；该用例刻意施加背压并确认 TFA 整包丢弃计数增长，不代表实际板测出现丢包。

另外 23 项 Python 检查通过：滤波系数 2 项、host sensor analyzer 8 项、VLP reference 13 项。保留的 EPSILON/DLIA 生产文件与同步后的 `9f45e49` 相同，并分别通过下行/RTCM 和滤波档位仿真。host analyzer 仍可解析历史扩展 schema，不代表当前 FPGA 声明或输出这些已撤回的能力。

`member3_sensor_bank` 在 XCKU11P-2 上完成 Vivado 2020.2 out-of-context 综合，正常输出 `HMP_AI8_BANK_SYNTH_PASS`，并确认 7 个 stream lane 与保留的 EPSILON correction TX 端口。综合 0 errors、0 critical warnings；综合阶段汇总 299 warnings，日志中的类别为未使用的 EPSILON 调试输出、无负载输入和常量优化，未出现 latch warning。资源为 30352 LUT、25503 寄存器、9 DSP。脚本、日志、资源报告和 DCP 均保存在上述外部目录，未纳入源码仓库。

首次外部综合脚本用了 Vivado 2020.2 不接受的 `read_verilog -include_dirs` 选项，未开始综合即退出；改为 project fileset 的 include_dirs 后重跑通过。保留 `bank_synth.log` 失败记录，成功结果为 `bank_synth_retry.log`、`synthesis_summary.json`。此脚本适配未修改生产 RTL。

本轮不执行完整顶层布局布线、时序/CDC 签核或 BIT 生成，未重跑全套 RTL 回归。上一轮公共 smoke 的综合后 hold 违例也不能因本次功能回归通过而视为已解决；之前的记录在外部 `github_sync_v2_20261027_01/REPORT.md`。


2026-11-14 源码修订：AI8 扫描/schema3 已按 `Docs/protocol/AI8_SCAN_CONTRACT_20261114.md` 实现；通用参数事务和 RD105 仍不支持。此修订不改变本文旧镜像的验收结论，新 BIT 尚受目标器件包缺失阻塞。
