# CODEX_TASK_PREDEV_002：FPGA公共基础RTL开发任务书

## 1. 项目背景

当前项目为机载水汽激光雷达 FPGA 下位机开发。

后续三个成员将并行开发：

-   双 ADC + DILA
-   WMS + 双 DAC
-   UART + 多传感器

为了保证各模块能够独立开发，需要提前完成公共 RTL 基础设施。

------------------------------------------------------------------------

## 2. 开发目标

完成以下公共模块：

1.  时钟与复位管理
2.  系统统一时间基准
3.  cfg_bus 配置接口
4.  sample_stream / msg_stream / bulk_stream 接口定义
5.  公共仿真测试环境
6.  WMS reference stub

完成后，成员无需等待系统集成即可开始模块开发。

------------------------------------------------------------------------

## 3. 开发环境

-   Vivado（位于目录D:\Software\Vivado\Vivado\2020.2\bin\unwrapped\win64.o）
-   Verilog

要求：

-   RTL 可综合
-   Testbench 可运行
-   无第三方依赖

------------------------------------------------------------------------

## 4. 文件目录要求

    rtl/
    ├── common/
    │   ├── clk_rst_mgr.v
    │   ├── system_timebase.v
    │   └── cfg_bus_if.v
    │
    ├── include/
    │   ├── project_defs.vh
    │   ├── stream_defs.vh
    │   ├── register_map.vh
    │   └── error_codes.vh
    │
    sim/
    ├── common/
    │   ├── clock_reset_gen.v
    │   ├── cfg_bus_master_bfm.v
    │   ├── sample_stream_sink.v
    │   ├── msg_stream_sink.v
    │   ├── bulk_stream_sink.v
    │   └── wms_reference_stub.v
    │
    tests/
    └── tb_predev_common.v
    
    reports/
    └── TASK-PREDEV-002-report.md

------------------------------------------------------------------------

# 5. 模块开发要求

## 5.1 clk_rst_mgr

功能：

提供系统统一时钟和复位。

输入：

-   clk_in
-   rst_in_n

输出：

-   sys_clk
-   sys_rst_n
-   init_done

要求：

-   reset 异步输入
-   reset 同步释放
-   输出稳定
-   支持后续 PLL 扩展

------------------------------------------------------------------------

## 5.2 system_timebase

功能：

产生统一 64 bit 时间戳。

接口：

``` verilog
input clk;
input rst_n;

output [63:0] timestamp;
```

要求：

系统时钟：

    100 MHz

时间精度：

    10 ns/tick

复位：

    timestamp = 0

------------------------------------------------------------------------

## 5.3 cfg_bus_if

功能：

提供统一寄存器配置接口。

接口：

``` verilog
input  [15:0] cfg_addr;
input         cfg_wr_en;
input  [31:0] cfg_wr_data;

input         cfg_rd_en;
output [31:0] cfg_rd_data;

output        cfg_ack;
output        cfg_error;
```

要求：

支持：

-   单周期写
-   单周期读
-   非法地址 error 返回

------------------------------------------------------------------------

## 5.4 Stream 接口定义

需要统一定义：

### sample_stream

用于：

-   ADC sample
-   内部采样数据

------------------------------------------------------------------------

### bulk_stream

用于：

-   DILA 曲线数据
-   RAW ADC block 数据

------------------------------------------------------------------------

### msg_stream

用于：

-   PTB210
-   HMP
-   EPSILON2
-   BMP390
-   SHT45
-   其他低速传感器

需要统一定义：

-   valid/ready
-   data
-   source_id
-   msg_id
-   timestamp
-   cycle_id
-   flags

------------------------------------------------------------------------

## 5.5 WMS reference stub

用于 DILA 开发测试。

输出：

-   scan_start
-   cycle_id
-   phase
-   phase_valid

要求：

模拟连续扫描：

    phase:
    0
    1
    2
    ...
    0xffffffff

固定周期产生：

-   scan_start
-   cycle_id++

------------------------------------------------------------------------

# 6. 仿真环境要求

需要提供：

## 6.1 clock/reset generator

生成：

-   100 MHz clock
-   reset sequence

------------------------------------------------------------------------

## 6.2 cfg_bus_master_bfm

提供：

``` verilog
cfg_write(addr,data);

cfg_read(addr,data);
```

用于模块寄存器测试。

------------------------------------------------------------------------

## 6.3 Stream sink

提供：

-   sample_stream_sink
-   msg_stream_sink
-   bulk_stream_sink

功能：

-   接收数据
-   检查 valid/ready
-   保存仿真结果
-   输出 log

------------------------------------------------------------------------

# 7. 测试要求

必须完成：

## Test 1：system_timebase

验证：

1000 个 clock 后：

timestamp 增加 1000。

------------------------------------------------------------------------

## Test 2：cfg_bus

验证：

-   写寄存器
-   读寄存器
-   非法地址处理

------------------------------------------------------------------------

## Test 3：WMS stub

验证：

-   phase 连续变化
-   cycle_id 正确递增
-   scan_start 周期正确

------------------------------------------------------------------------

## Test 4：stream handshake

验证：

当：

    ready = 0

时：

发送端保持：

-   valid
-   data
-   metadata

不变化。

------------------------------------------------------------------------

# 8. 禁止开发内容

本任务不开发：

-   USB3.1
-   FX3
-   packetizer
-   stream_arbiter
-   sensor_hub
-   ADC
-   DAC
-   正式 WMS
-   DILA
-   UART
-   顶层模块

------------------------------------------------------------------------

# 9. 最终交付

提交：

    rtl/
    sim/
    tests/
    reports/

报告：

    TASK-PREDEV-002-report.md

包含：

-   完成模块
-   仿真结果
-   Vivado版本
-   综合结果
-   已知问题

------------------------------------------------------------------------

# 10. 问题处理原则

一般问题：

-   编译错误
-   仿真失败
-   RTL bug

优先自行定位和修复。

以下情况需要同步：

-   公共接口冲突
-   硬件资料缺失
-   架构无法实现
-   需要修改协议

------------------------------------------------------------------------

# 11. 完成标准

满足：

-   Vivado 工程可打开
-   RTL 可综合
-   Testbench 通过
-   后续成员可以直接调用接口开发
