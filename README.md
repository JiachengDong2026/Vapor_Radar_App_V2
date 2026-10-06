# Vapor_Radar_App_V2

## 2026-10-04 最新同步
正式源码已同步已上板的双AD4630/DLIA精度版本：插值参考、四阶固定1kHz低通，ID `00300101/00310101`、1MS/s profile `00040101`。详见 [同步范围及复验](Docs/MERGE_MANIFEST_20261004.md)。构建、仿真和Flash导出产物统一放到外部 `Vapor_Lc_App_Test`；现有硬件参数与Git工作树状态不由同步操作重置。

以下2026-09-23记录保留为历史；最新验证范围以上述同步记录为准。

面向 Xilinx **XCKU11P-2FFVA1156I** 的水汽激光雷达下位机工程，使用 Verilog-2001 和 Vivado 2020.2。2026-09-23 将已完成六传感器 USB 联调的完整系统代码按功能目录归入正式仓库。

## 当前交付范围

已合入 PTB210、EPSILON MAIN RS232、BMP390、SHT45、TFA1500-L、AI-8 温控的驱动，配套时钟复位、统一时间、消息仲裁/缓存、VLP 封包、命令/寄存器及动作控制、USB GPIF 和 FX3 GP01 固件构建。

完整顶层仍包含 ADC/DILA、WMS/DAC、HMP和电机依赖，但这些链路尚未全部实板验收。不能把实现存在、仿真通过或比特流生成当成实物通过。当前设备默认禁用，由主机显式配置和启用。

历史2026-09-18六路并发板测约60秒，收到91087帧、7278076字节，全部VLP CRC通过。AI8仍有设备报警，EPSILON在无天线室内条件下未验证定位/UTC，详情见[正式集成修订](Docs/INTEGRATION_REVISION_20260923.md)。本轮板卡暂未连接，验证范围为离线仿真、构建和比特流生成。

## 规范入口

本次接口/接线及兼容性修订以[2026-09-23正式集成修订](Docs/INTEGRATION_REVISION_20260923.md)为优先补充，未变更部分沿用以下规范：

- [开发指南 V1.1](Docs/FPGA下位机Verilog开发指南_V1.1.md)
- [详细架构与接口分配 V1.1](Docs/FPGA下位机详细架构与接口分配方案_V1.1.md)
- [任务总览 V1.3](Docs/【任务书】三成员任务书_V1.3/00_任务分配总览与集成边界_V1.3.md)
- [上位机 VLP1 协议](Docs/protocol/FPGA_HOST_PROTOCOL_V1.0.md)
- [本次正式集成离线验证记录](Docs/FORMAL_INTEGRATION_VALIDATION_20260923.md)
- [动作控制与温度设置](Docs/integration/ACTION_CONTROLLER.md)
- [FX3依赖、许可、构建](firmware/fx3/README.md)
- [主机测试工具](host/README.md)

物理管脚以原理图和正式XDC为依据；全局ID/宽度由 `fpga/rtl/include` 统一定义。各传感器经过独立FIFO进入消息仲裁，32-bit stream采用valid/ready握手，背压期间保持数据和metadata。系统统一100MHz时间基准，GPIF为50MHz。

## 文件布局

```text
fpga/
  rtl/common, include          公共CDC/FIFO、宏、寄存器和错误码
  rtl/clock, time              时钟复位与统一时间
  rtl/control, stream          命令/寄存器/动作控制与数据汇聚
  rtl/sensors                  UART/RS485/I2C协议和传感器bank
  rtl/adc, dila, wms, dac       完整系统采集与调制依赖
  rtl/usb, motor, top          GPIF、电机及物理顶层
  constraints/system, adc, wms_dac
  tests/                      公共及四组testbench
  sim/                        公共BFM、设备模型、固定向量
  scripts/                    源清单、构建和回归入口
  vivado_check.tcl             公共仿真与综合检查
firmware/fx3/                  GP01自有增量、生成/编译及验证脚本
host/                          USB工具源码、六路计划与分析器
Docs/                          规范、协议、验证说明和原始资料
```

生产编译清单为 `fpga/scripts/full_sources.tcl` 与 `sources.json`，不会依赖Test目录的成员源码。`rtl/common/clk_rst_mgr.v` 是前期参考实现，生产构建只选择 `rtl/clock/clk_rst_mgr.v`，不可直接把所有RTL递归加入同一fileset。

## FPGA离线验证与构建

在仓库根目录运行。依赖Python 3.9+、Vivado 2020.2，Vivado需要该器件授权。Windows安装路径按本机修改。所有生成物写到外部 `Vapor_Lc_App_Test`，不提交Vivado工程、缓存、波形、BIT和DCP。

```powershell
python -B fpga/scripts/check_baseline.py
$env:VAPOR_BUILD_ROOT = 'E:/Documents/Vapor_Lc_App_Test/formal_build'
& 'D:/Software/Vivado/Vivado/2020.2/bin/vivado.bat' -mode batch -nojournal -log "$env:VAPOR_BUILD_ROOT/common.log" -source fpga/vivado_check.tcl
python -B fpga/scripts/run_regression.py --output 'E:/Documents/Vapor_Lc_App_Test/formal_regression' --vivado-bin 'D:/Software/Vivado/Vivado/2020.2/bin'
python -B fpga/scripts/build.py --output 'E:/Documents/Vapor_Lc_App_Test/formal_bit_build' --vivado 'D:/Software/Vivado/Vivado/2020.2/bin/vivado.bat'
```

先创建日志的父目录；完整构建包装器要求新输出目录，只接受全新构建，不复用历史routed checkpoint。综合无锁存、完整布线、setup/hold、DRC、check_timing、时钟脉宽和ADC/DAC pad检查通过后才写出 `full_build/vapor_lidar_top.bit`。CDC报告需按具体端点审查：已保留的ADC异步FIFO/reset路径不能仅按Critical数量自动判定新增故障或豁免。

完成实现后，从仓库根执行以下 CDC 复核，输出目录按本次构建修改。端点清单比较通过后，仍须运行实际 DCP 结构检查并检查 `bus_skew.rpt` 的全部约束；包装器的 `pass` 只代表实现检查，输出会同时标明 `cdc_review_required`。

```powershell
$repoRoot = (Get-Location).Path
$bitBuild = 'E:/Documents/Vapor_Lc_App_Test/formal_bit_build'
$cdcReview = 'E:/Documents/Vapor_Lc_App_Test/formal_cdc_review'
python -B fpga/scripts/review_cdc.py --baseline fpga/scripts/cdc_endpoint_baseline.json --current "$bitBuild/full_build/cdc.rpt" --output $cdcReview
if ($LASTEXITCODE -ne 0) { throw 'CDC endpoint comparison requires review' }
Push-Location $cdcReview
try {
    & 'D:/Software/Vivado/Vivado/2020.2/bin/vivado.bat' -mode batch -nojournal -log netlist.log -source "$repoRoot/fpga/scripts/review_cdc_netlist.tcl" -tclargs "$bitBuild/full_build/routed.dcp" $cdcReview
    if ($LASTEXITCODE -ne 0) { throw 'CDC netlist structure check failed' }
} finally { Pop-Location }
```

任何端点变化都会使比较器失败，需要针对变化重新审查；不得直接更新基线以消除差异。完整审查标准及本次结果见[验证记录](Docs/FORMAL_INTEGRATION_VALIDATION_20260923.md)。

回归覆盖UART/I2C/Modbus、CRC错误和恢复、AI8设温写后读回、消息背压、命令错误、复位、时间、GPIF收发及完整传感器汇聚；ADC/DILA/WMS/DAC回归也随依赖保留。仿真成功要求无Fatal/ERROR且有完成标记。公共基线旧测试的采样竞争与失败后继续打印PASS的问题已修复。

## 上板配置要点

- PC主接口：CON23 USB，应用04B4:00F1，OUT 0x02、IN 0x86。
- EPSILON MAIN：CON14，921600/8N1；PTB210：CON25。
- AI8：CON19 RS485，19200/8N1，地址1、通道1。HMP暂未接，保持禁用。
- TFA1500-L：CON21及LF输入；BMP390/SHT45：共享I2C。
- BMP390复位默认0x76，实物为0x77：禁用时写0x6310=0x77并读回，再启用。主机六路计划包含此步骤。
- AI8使用schema2、原始温度0.1摄氏度/LSB；ACTION17的value单位为微摄氏度。独立测试串口的ASCII SET指令不适用于完整USB系统。

当前USB Boot需先加载FPGA BIT，再把配套GP01 IMG下载FX3 RAM。EEPROM扩容及冷启动仍待验证，不能把RAM成功写成EEPROM已通过。新比特流请按产物SHA256核对，防止选到独立工程或旧集成文件。

## 提交规则

源代码、ROM/仿真向量、构建入口、简明验证报告及规范同步提交。FX3官方SDK/示例主体由使用者从本地合法安装的依赖重建，仓库仅保存项目自有增量和哈希，不盲目上传SDK或库。修改公共接口、管脚、消息格式或寄存器时，同步更新Docs、头文件与验证；遵循根AGENTS.md。
