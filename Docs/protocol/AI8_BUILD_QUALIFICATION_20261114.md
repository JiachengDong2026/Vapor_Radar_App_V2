# AI8 扫描镜像构建与同轮重新签核（2026-11-14）

结论：本轮新实现已生成可供后续实板测试的 BIT，未烧录、未实板验收。接口见 [AI8_SCAN_CONTRACT_20261114.md](AI8_SCAN_CONTRACT_20261114.md)。旧 HCD2 的硬件验收不覆盖本镜像。

## 来源与产物

- 网表源提交：`a40f2edb9ac39f8754f1f430563fa00424e869a4`；之后 `97e6748` 仅记录文档。本次只修改两个独立管脚 checker 的保守预算，RTL、XDC、综合/实现脚本均未改变。
- 工具：`D:/AMD_Enterprise/2025.1/Vivado/bin/vivado.bat`，2025.1 build 6140274；target 固定 `xcku11p-ffva1156-2-i`。
- BIT：`D:/Project/Test/ai8_current_qualification_20261114_a/vapor_lidar_top.bit`。
- SHA256：`b3de7ad484a442db20bc86e7e0425a6c912b5fc6a8d961e5c7103460c353adab`。
- 本轮 routed DCP：`D:/Project/Test/ai8_enterprise_full_20261114_c/full_build/routed.dcp`；SHA256 `2affd4944c29f27ccfc2f58954c3e8089e2875d66023830c2f0ba5ef0e2ebc19`。

## 许可证与检查器修复

原构建进程的 XILINXD_LICENSE_FILE、LM_LICENSE_FILE 均未设置。仅对子进程设置 XILINXD_LICENSE_FILE 指向现有授权文件后，Synthesis 与 Implementation 实际 checkout 均成功；未修改全局环境、授权文件或授权内容。Vivado_System_Edition 文本版本 2037.05、expiry permanent；实际成功 checkout 是使用可行性的证据。诊断和原环境记录仅留在 `D:/Project/Test/license_diag_20261114_a`，含可能敏感信息的原始 lmutil 输出不提交。

本轮 DAC setup 路径报告 uncertainty=0.312 ns，组成是 sqrt(0.071²+0.213²)/2 + 0.200；hold 为0.050 ns。系统 XDC 本来已说明 user uncertainty 外还叠加模型 jitter/phase。没有2020.2同一路径报告，不声称差异完全由工具版本引起。

DAC/AD4630 checker 固定边沿预算由0.250提高为0.350 ns，保留超界失败。DAC 每个间隔多扣0.100 ns；AD4630保留原pu归一，setup多扣0.100 ns、hold所需边界增加0.100 ns，均更保守。新增AD4630输出路径uncertainty guard。datasheet、flight/load/ppm、MCP、XDC均不改。没有移除检查或降低时钟约束。

## 可审计的同轮重新签核

原完整构建 c 轮完成本轮综合/布局/布线和hold修复，随后被旧DAC预算guard阻止。其 build_result.json 保持 pass=false，bit_sha256=null；原manifest和报告不覆盖，不冒称原脚本FULL_SYSTEM_BUILD_PASS。

根据本轮明确授权，仅对当前刚生成的实现独立重新签核，不通过resume-route入口复用历史实现。外部目录 `D:/Project/Test/ai8_current_qualification_20261114_a` 保存：

- qualification_seal.json：原source_inputs/build_inputs/build_result与synth/routed DCP哈希，以及两个checker原/新哈希和全部当前输入哈希。核对全部原综合输入，差异严格限定两个checker。
- qualify.tcl：从原构建脚本提取同一组最终门槛，打开只读本轮DCP，重新检查route完整性、timing、CDC、check_timing、DRC、pulse width、utilization、DAC和AD4630；写BIT前再次verify_seal.py。原manifest verify由独立显式差异封存检查替代，没有重写原manifest。
- qualification_retry.log：CURRENT_QUALIFICATION_GATES_PASS，进程退出0；写BIT后再次CURRENT_QUALIFICATION_SEAL_PASS。
- qualification_result.json、uncertainty_arcs.tsv、all_arcs.log：全部枚举240条相关路径（DAC80、ADC输出88、ADC输入72），最大uncertainty=0.312 ns，小于固定0.350预算；覆盖DAC两路五pad的rise/fall/min/max全部组合及ADC输出/输入路径。

## 签核结果与边界

| 项目 | 结果 |
|---|---|
| 内部时序 | WNS +0.007 ns；TNS 0；WHS +0.001 ns；THS 0 |
| DRC | 2633 Warning；0 Critical Warning；0 Error |
| check_timing | no_clock、unconstrained internal endpoints、no_input_delay等原要求均0；仅转发时钟FPGA_GPIF_PCLK无output delay |
| DAC管脚 | 最小裕量7.313 ns；失败0 |
| AD4630管脚 | 最小裕量3.773 ns；失败0 |
| CDC精确端点 | 2/2 exact_inventory_match：CDC-10 Critical 1条、CDC-3 Info 1条 |
| routed结构 | FORMAL_CDC_NETLIST_REVIEW_PASS memory_entries=0 reset_entries=1 |
| bus-skew | 12条10 ns约束全部满足，最小slack 7.798 ns |

CDC证据在 c 轮 `cdc_review`。Critical端点为power_count_reg[7]/C→u_clock/gpif_release_reg[0]/CLR，16级ASYNC_REG同步释放链、直接连接和级间时序已在本轮DCP复核。其余UART/Gray结构按现有脚本核对。当前AI8改动只在SYS域，未改跨域RTL或约束；12条bus-skew覆盖transport FIFO及计数器Gray路径，无新增未审端点。报告不是零Critical，独立结构审阅通过不等于硬件验收。

公共smoke综合完成：setup WNS8.439/TNS0；未布线hold WHS-0.089/THS-63.518，顶层I/O未指定delay，不能当成整机签核。公共CDC含2条CDC-6 Warning和32条CDC-15 Warning，分别为Gray同步/握手数据结构。整机结果以上表为准。

复用此前12项behavioral仿真（RTL未变），最终BASELINE_STATIC_CHECK_PASS。本轮没有历史stepper checker，不将旧STEPPER_TIMING记录当作本轮DM422管脚签核。板级flight/load/ppm仍为工程预算而非实测；内部时序裕量很小，新源码或工具变化必须重新验证。
