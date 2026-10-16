# 下位机能力扩展软件验证（2026-10-17）

同步基线：`origin/main=0f12988`，同步时本地干净，`git fetch origin --prune` 后 `git merge --ff-only origin/main` 确认已是最新版本。本轮仅修改下位机仓库，按用户要求只本地提交，不推送；VaporView 工作区保持原状。

功能与寄存器契约见 [交接文档](protocol/HOST_EXTENSIONS_20261017.md)。本记录描述软件验证，不是实板验收记录。

## 本机工具与构建边界

工具安装在用户授权的 `GPS/FPGA_Toolchain` 独立目录，未修改机器级 PATH：

- OSS CAD Suite 2026-10-16：Icarus 14.0 devel、Yosys 0.70+145、Verilator 5.053 devel。
- 辅助稳定版 Icarus 13.0。工具、依赖、日志、模拟可执行文件和中间工程均在 Git 仓库外，不作为项目源码提交。
- 没有可用的 Vivado 构建环境；AMD 官方下载需要登录，已请求可用安装/离线包路径，本轮未获得。没有完成 XCKU11P 实现、时序/DRC/CDC、BIT 生成或烧录。

本轮未修改 VaporView，因此未执行它的 `build/Release` C++/GUI 构建；下位机的正式验证输出按本仓库规则放在外部目录。

## 动态 HDL 验证

最终合并结果覆盖仓库全部 **92 个 testbench**：91 项有 Icarus 成功结果；`tb_vapor_sensor_integration` 用相同 testbench 在 Verilator 中通过。不是声称单次 Icarus 全量命令退出为 0。

全量 Icarus 初跑遇到两个包装器缺少依赖：`tb_ad4630_min` / `tb_ad4630_dual_min` 需要同一测试库中的母 testbench。修复回归入口的测试库链接后，两项复测均通过。旧测试使用了 `sequence` 标识符，因此 Icarus 采用 Verilog-2005，而非将旧 .v 全部强制解析成 SystemVerilog。

同一 USB 端到端用例在 Verilator 通过后，结束了两次重复的 Icarus 运行。它们的中止结果不计为通过，也不当成 DUT 的功能失败；最终汇总采用 Verilator 的正常 `$finish` 和成功断言。

主要新增与直接相关覆盖：

| 用例 | 实际检查 |
|---|---|
| `tb_ai8_scan_parameters` | 1..8 顺序轮询、schema 3/0468 通道号、单通道异常的零化无效快照与其他通道隔离、通道 8 设温、PID 参数读回、写锁不一致、无自动重发、禁用取消 |
| `tb_rd105_parameters` | 独立 0048/6800 身份、两寄存器 PID 的真实串口字节顺序、全部读回对照、写锁、设温不能仅凭 ACK 确认、禁用取消和范围拒绝 |
| `tb_rd105_sensor_bank` | 生产 bank / wrapper 的第三路 DE/TX、19200/地址 2、目标核验、独立上传 lane、其他设备不被启用 |
| `tb_rs485_three_way` | 三方轮转、整个请求/响应/等待期间的独占、背压/安静时间保持、复位 |
| `tb_epsilon_downlink` | ASCII 真正 UART 输出与原始应答、超时；1029 字节 RTCM CRC24Q；MAIN 0x73 五片和 CRC8/CRC16/序号逐字节对照；独立 correction UART；无效帧不产生 TX；busy/禁用/长度拒绝；禁用时不截断整帧 |
| `tb_dila_cutoff` | 七档截止频率、默认 1 kHz、范围与只读拒绝、周期内不切换、排空后周期边界原子提交 |
| 原有精度/采集用例 | `tb_dila_filter_precision`、reference/numeric、双 AD4630、ADC/RAW 排空、WMS/DAC、GPIF、完整命令/动作、时间和看门狗均有成功结果 |
| 原有传感器并发用例 | `tb_ai8_shared_bus`、`tb_sensor_bank_merge`、`tb_seven_devices` 通过，保留 HMP 默认/启用语义、原始六/七设备 CRC/质量及背压覆盖 |

Verilator 的 USB 端到端实际结果：

```text
TOP_SENSOR_CONFIG_GPIF_PASS
TOP_SEVEN_FIRST_FRAMES_PASS time=288003235000
SHARED_RS485_PROGRESS_PASS hmp=12 ai8=21 writes=0/0
tb_vapor_sensor_integration_PASS frames=807 counts=20,12,99,5,15,416,3 CRC=all
tags=104 taggedPPS=2 stallCycles=6003452 nearWrites=0
```

该用例正常 `$finish` 于约 436 ms 仿真时间；Verilator 运行约 190 秒。Icarus 的传感器 bank 合并和七设备并发用例分别约 631/644 秒，期间核对实际进程、CPU 和日志增长，没有以“存在 PID”代替最终结果。

## 结构和 Python 验证

- `python -B fpga/scripts/check_baseline.py`：`BASELINE_STATIC_CHECK_PASS`。
- Yosys 加载生产 source manifest、Xilinx primitive 库，`hierarchy -check -top vapor_lidar_top`、`proc`、`opt_clean`、`check -assert`、`select -assert-none t:$dlatch` 均成功；`Found and reported 0 problems`。初轮发现 RD105 wrapper 的方向使能线未接出，修复后以生产 bank 动态测试及最终结构检查共同确认。
- `python -B fpga/scripts/test_lpf_profiles.py`：2 项通过。14 种标称采样率/截止频率组合全部量化极点在单位圆内，DC 增益精确为 1，截止点约 -3.0103 dB；默认系数逐位保留。
- `python -B host/test_analyze_sensors.py`：8 项通过，包括 schema 3 通道范围和快照隔离、独立 RD105、旧六设备与单位/CRC/无效记录分类。
- `python -B Docs/protocol/examples/test_vlp_reference.py`：13 项通过，包括分片、坏 CRC、恢复、长度上限和旧黄金帧。
- `git diff --check` 通过；未进行任何真实设备参数写入、连接凭据导出或 GUI 配置修改。

## 可复验命令

从下位机仓库执行；输出目录必须是仓库外的新目录：

```powershell
$toolBin = 'X:/Project/GPS/FPGA_Toolchain/oss-cad-suite/bin'
$env:PATH = "$toolBin;$toolBin/../lib;" + $env:PATH
python -B fpga/scripts/check_baseline.py
python -B fpga/scripts/run_regression.py --iverilog-bin $toolBin --output X:/Project/GPS/FPGA_Verification/recheck_new
python -B fpga/scripts/test_lpf_profiles.py
python -B host/test_analyze_sensors.py
python -B Docs/protocol/examples/test_vlp_reference.py
```

本轮还实际执行了以下结构检查和 Verilator C++ 模型编译（工程/脚本留在外部验证目录）：

```powershell
yosys.exe -Q -T -s X:/Project/GPS/FPGA_Verification/synthesis_20261017/full_top.ys
cmake --build X:/Project/GPS/FPGA_Verification/verilator_probe_20261017/build --parallel 4
```

Verilator 可执行文件运行时 cwd 使用含 `sensor_commands.hex` 和 ROM 向量的外部 `work` 目录。它由正式 RTL、正式 BFM 和同一 `tb_vapor_sensor_integration.v` 生成，没有删除断言或更改业务期望。外部 `delivery_results_20261017.json` 保存 92 项结果来源，`delivery_source_inputs_20261017.json` 保存验证输入 SHA256。

## 尚不能声称完成的事项

AI8 资料没有恢复出厂命令，保持明确不支持；不能通过模块复位或批量写猜测默认值代替。VaporView/SkyCore 尚未适配本次新增能力。RD105 实体共享总线设置、EPSILON MAIN 固件是否接受 0x73 输入/独立 RTCM 口接线及 GNSS 实际应用、DLIA 板上幅频和时序等均需按交接清单实测。开源检查通过不等于 Vivado 实现或硬件验收通过。
