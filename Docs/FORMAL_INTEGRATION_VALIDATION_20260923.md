# 正式集成离线验证记录（2026-09-23）

## 范围与来源

本次将已调通的 PTB210、EPSILON MAIN RS232、BMP390、SHT45、TFA1500-L、AI-8 六路传感器，以及时钟复位、时间同步、命令/动作控制、消息汇聚、VLP、GPIF、FX3 和主机测试工具归入正式功能目录。完整顶层需要的 ADC/DILA、WMS/DAC、HMP 和电机代码随依赖保留，不能视为已经实板验收。

生产 RTL、头文件及 ROM 共 96 个映射文件与 `Test/integrated_20260916` 来源逐字节相同；正式编译清单选择 87 个 `.v` 文件。XDC 仅调整跨目录引用，未放宽时序约束。FX3 采用已实测 GP01、`GPIF_BUS_CONFIG=0x10AC`，从锁定的外部 SDK 与项目增量重建。

本次所有生成物及详细报告在 `E:/Documents/Vapor_Lc_App_Test/formal_merge_20260923`。用户明确板卡暂未连接，本次不包含新的烧录、USB 实物收发、温控设温或定位验证。历史六路 USB 实测见[接口修订](INTEGRATION_REVISION_20260923.md)。

## 验证环境与测试台修正

工具为 Vivado 2020.2、Python、Windows .NET Framework C# 编译器；器件为 XCKU11P-2FFVA1156I。构建使用正式目录中的源文件，全新综合和布局布线，不复用历史 routed checkpoint。

- 公共测试台修正时间戳读取的仿真调度竞争：起点和终点都在非阻塞赋值完成后采样，仍要求严格 20 周期。验证脚本先将默认仿真时长设为 0，再执行一次 `run all`，并检查完整日志，防止 Fatal 后继续运行产生假 PASS。
- 公共综合 smoke 保留全部 FIFO 等模块的可观察输入输出，避免关键逻辑被优化为空。
- `tb_seven_devices` 从旧 HMP/RD105 独立端口更新为实际 AI8/HMP 共享 RS485 模型。仍启用全部七路并检查在线、包数、背压稳定及 TFA 溢出，新增 AI8 schema2、共享总线双客户端进展和无额外写入断言。
- 六个旧测试台只迁移向量文件相对路径。回归使用统一 `work` 仿真库；完整传感器系统仿真按真实串口时序运行，运行限时按历史约 18 分钟的实测耗时调整，不压缩测试场景。

## 已完成的独立验证

| 检查 | 结果与证据 |
|---|---|
| 基线静态检查 | `BASELINE_STATIC_CHECK_PASS`，冻结 ID/位宽和基础结构一致 |
| 公共 behavioral simulation | `PREDEV_COMMON_V12_PASS`，日志无 Fatal/ERROR |
| 公共 OOC 综合及报告 | 完成 timing、CDC、check_timing、utilization；447 LUT、418 寄存器、0 latch。该 smoke 报告不能代替完整工程时序签核 |
| 模块和系统回归 | 79/79 项测试完成并通过，另加上述公共基线仿真；验收清单为 `regression_acceptance.json` |
| 七路测试台修复专项 | `SEVEN_DEVICES_CONCURRENT_PASS`，各路包数 19、11、64、4、14、358、2；93.62 秒完成 |
| 主机分析器 | 6 项 Python 单元测试通过 |
| VLP 协议参考 | 13 项测试通过 |
| 主机 C# 工具 | SensorRun、CaptureIn 编译通过；未访问硬件 |
| FX3 构建/回归 | 4 个应用源重建、194 个 SDK 依赖哈希、固件 API mock、官方状态图、ELF/IMG 等价及 checksum 验证全部通过 |

完整 `tb_vapor_sensor_integration` 实际运行 18 分 42 秒，在 436,003,235 ns 正常 `$finish`。收到 804 个 VLP 帧，各路包数为 20、12、99、5、15、416、3，CRC 全部通过；GNSS 标签 104 个、关联 PPS 2 个，背压覆盖 6,003,440 个周期。共享总线 HMP 12 次、AI8 21 次事务，无非请求写入。以上为设备模型仿真数据，不是实板数据。

原批量启动器为该项设置了 900 秒墙钟限时，因此原始 `regression_v2/results.json` 保留了一条启动器超时记录。Windows 子仿真进程继续运行并正常结束；最终验收单独检查了完整 PASS、全部无 Fatal/ERROR 及正常退出，不修改原始失败记录。另一条旧七路端口失败以修复后的专项复测结果替代。交付的回归脚本将每项限时改为 3600 秒，并要求正常 `$finish`，不以中间 PASS 代替完成。

FX3 镜像为 `fx3/vapor_fx3.img`，93,724 字节，SHA256：

```text
e705c3032aece44c2ef1890e45c9f6b5d5aa31fc6facc8ab02ddb2847e043dd5
```

该镜像与此前已上板 GP01 逐字节相同，容量没有优化，不能据此声称现有 EEPROM 容量问题已经解决。仓库保留项目增量、生成器、测试和依赖哈希；完整第三方 SDK、生成固件源码及二进制位于外部目录。

## 完整实现和比特流

全新综合、布局布线及 `write_bitstream` 完成，Vivado 正常退出且输出 `FULL_SYSTEM_BUILD_PASS`。构建过程中 110 个原始输入哈希全部保持一致。

| 项目 | 最终结果 |
|---|---|
| Setup / Hold | WNS = 0.331 ns，WHS = 0.005 ns；均满足约束 |
| 路由 | 144,438 条可布线网络全部完成，routing errors = 0 |
| 时序完整性 | no_clock、未约束内部端点、输入延迟缺失、时钟/组合环等检查均为 0；唯一 no_output_delay 为已定义生成时钟的 `FPGA_GPIF_PCLK` |
| 脉宽 | 无违反项 |
| DAC 引脚 | 16.666666 MHz SPI，最小裕量 6.677 ns；采用 1 ns PCB skew、0.250 ns 边沿预算、100 ppm 容差 |
| AD4630 引脚 | 25 MHz SCK，最小裕量 2.858 ns；采用往返板级延迟 ≤2 ns、输出负载 10 pF、SDO负载 ≤5 pF |
| DRC | 无 Error/Critical Warning；保留 920 项 Warning：374 DPIP-2、255 DPOP-3、279 DPOP-4、11 RPBF-3、1 RTSTAT-10 |
| 资源 | 84,859 LUT、51,989 FF、310 RAMB36、347 DSP |

DRC 中 DSP 项是流水线优化建议；RPBF-3 涉及按固定方向使用的 inout 端口，RTSTAT-10 涉及 3 条没有可布线负载的内部网。这些保留告警不等于零告警，也没有通过修改严重级别或放宽原约束消除。最终 hold 裕量仅 0.005 ns，后续任何 RTL/约束变化都必须重新实现并复核，不能沿用本次结果。

比特流路径：

```text
E:/Documents/Vapor_Lc_App_Test/formal_merge_20260923/fpga/full_build/vapor_lidar_top.bit
```

大小 **23,581,028 字节**，SHA256：

```text
c405497efc4b7a329f1f72464739f54348c198229629096476c1ac47475b7f02
```

本次长构建直接运行正式 `run_full_build.tcl`。完成后才加入两个入口包装器、两个 CDC 审查脚本及紧凑端点基线，避免修改运行中的构建输入；原 110 个文件仍全部匹配，新增文件逐项列于 `post_build_source_verification.json`。包装器的仓库内输出/已有目录拒绝检查通过，安装后的回归入口已运行 `tb_vlp_cmd_rx` 并通过。新包装器用于后续全新构建，本次不能宣称由它启动。

源文件差异检查保留了原始 RTL 的末尾空行与厂商许可证空白，以维持来源字节；没有为消除格式提示修改已调通逻辑或厂商许可证。

## CDC 独立审查结论

本轮按实际 routed DCP 和 CDC 报告逐项复核后接受，**不属于零 Critical 报告**。146 条规则/严重度/时钟/端点/同步深度/例外字段与已审查基线精确匹配，无新增或消失记录。其中 CDC-10 Critical 4 条、CDC-13 Critical 132 条、CDC-6 Warning 2 条、CDC-3 Info 8 条。

- 132 条为 ADC 异步 FIFO 受指针和有效握手管理的 RAM 数据路径。逐个确认 RAM CLK→I、所属 FIFO、实际时钟及 20 ns datapath bound，最小数据路径裕量 18.043 ns。
- 4 条为组合复位请求后的异步置位、同步释放链。逐级核对 ASYNC_REG、直接 Q→D 和内部有效时序，链长分别为 3、2、3、16。
- 18 个 Gray 指针位均核对两级同步链及源寄存器，另核对 6 条 UART 接收同步链。
- 14 条 bus-skew 约束均满足 10 ns 要求，最小裕量 8.539 ns；解析后的约束语句与基线一致。

结构接受结论见[正式 CDC 审查记录](integration/FORMAL_CDC_REVIEW_20260923.md)，逐项证据见外部 `CDC_REVIEW.md`、`cdc_review/FINAL_CDC_REVIEW.json`、`netlist_endpoints.tsv`、`synchronizer_evidence.txt` 和 `bus_skew.rpt`。正式仓库保留审查脚本和紧凑参考端点清单；将来任何端点变化必须重新解释并做结构检查，不能只比较 Critical 总数。

## 子任务报告与复现入口

外部报告目录包括 `RTL_MERGE_REPORT.md`、`DOCS_MERGE_REPORT.md`、`FX3_MERGE_REPORT.md`、`SEVEN_DEVICES_TB_FIX_REPORT.md`、`BUILD_REVIEW.md`，以及逐文件来源清单和实际工具日志。各报告分别记录迁入、文档、固件和测试台工作的结论。

后续复现命令见[仓库 README](../README.md)、[FX3 构建说明](../firmware/fx3/README.md)和[主机工具说明](../host/README.md)。新板测需使用本轮产物，先核对 SHA256，再依次做 USB PING、逐路采集、六路并发及错误/丢弃计数检查。
