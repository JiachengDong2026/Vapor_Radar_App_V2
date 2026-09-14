# Vapor_Radar_App_V2

机载三维水汽激光雷达 FPGA 下位机工程。

本项目面向基于 **TDLAS-WMS** 的机载原位水汽检测与水汽遥测系统，负责 FPGA 侧的激光调制控制、双 ADC 数据采集、数字锁相解调（DILA）、多传感器接入、统一时间同步、数据汇聚以及 USB 上位机通信。

目标 FPGA 为 **Xilinx XCKU11P-2FFVA1156I**，开发环境为 **Xilinx Vivado**，RTL 统一使用 **Verilog-2001**。

---

## 1. 项目当前状态

当前仓库已完成公共 RTL 与公共验证基础设施的整理，可以作为三个成员并行开发的统一基线。

当前公共基线包括：

- 统一工程常量、`source_id`、`msg_id`、TLV 类型与标签；
- 统一 32-bit `sample_stream` / `msg_stream` / `bulk_stream` 数据平面；
- 统一 32-bit `cfg_bus`；
- CDC 基础模块；
- 同步 FIFO、异步 FIFO 与三类 stream FIFO；
- 公共仿真 BFM、stream checker、WMS/time stub；
- 公共 behavioral regression；
- 公共 RTL OOC synthesis、timing、CDC 与 utilization 检查入口。

当前 `fpga/rtl/` 主要是**公共基础设施**。ADC/DILA、WMS/DAC、全部传感器驱动以及负责人保留的系统级模块，将按照 V1.3 任务书继续开发并逐步合入。

> **注意**
>
> `fpga/rtl/common/clk_rst_mgr.v` 与 `fpga/rtl/common/system_timebase.v` 目前仍属于前置开发参考实现，不在 V1.2 公共 RTL synthesis smoke test 的正式公共模块列表中。最终 `clk_rst_mgr`、`time_sync_core`、顶层时钟/复位与时间同步由项目负责人按照任务书和开发指南完成。

---

## 2. 文档版本与优先级

仓库中几个版本号对应不同层面的规范：

| 内容 | 当前基线 | 作用 |
|---|---|---|
| FPGA 开发与联调规范 | **V1.1** | RTL 设计原则、数据流、寄存器、协议、时间同步、模块接口 |
| 详细架构与硬件接口方案 | **V1.1** | 系统架构、设备连接、接口与管脚分配 |
| 三成员任务书 | **V1.3** | 成员责任、交付边界、成员之间的冻结接口 |
| 公共 RTL 基线 | **V1.2** | 当前 `fpga/rtl/common`、公共头文件、BFM、checker 与 regression |

推荐按照下面的顺序阅读：

1. [`Docs/下位机需求分析.md`](Docs/下位机需求分析.md)
2. [`Docs/FPGA下位机Verilog开发指南_V1.1.md`](Docs/FPGA下位机Verilog开发指南_V1.1.md)
3. [`Docs/FPGA下位机详细架构与接口分配方案_V1.1.md`](Docs/FPGA下位机详细架构与接口分配方案_V1.1.md)
4. [`Docs/【任务书】三成员任务书_V1.3/00_任务分配总览与集成边界_V1.3.md`](Docs/【任务书】三成员任务书_V1.3/00_任务分配总览与集成边界_V1.3.md)
5. 自己对应的成员任务书
6. `Docs/【资料】FPGA设备接入手册/` 中对应设备的官方手册
7. `Docs/【资料】电路板资料/` 中的原理图、UCF 与硬件资料

规范冲突时：

- **责任归属与成员交付边界**：以 V1.3 任务书为准；
- **内部接口、寄存器、协议与开发规则**：以开发指南及后续冻结修改为准；
- **物理连线与 FPGA 管脚**：以原理图和 UCF 为准；
- **设备原生协议、电气及时序**：以设备官方手册为准；
- RTL 中的公共位宽、ID 和寄存器宏必须引用仓库公共头文件，不要在成员模块中重新手写一套常量。

如果文档与已冻结公共头文件出现新的冲突，不要自行修改协议或重新分配 ID，应先由项目负责人统一确认和升级版本。

---

## 3. 项目任务分工

| 责任主体 | 主要负责内容 | 标准输出/交付边界 |
|---|---|---|
| **成员1** | AD4630、ADC3660、双 ADC capture/FIFO/CDC、DILA0/DILA1 及其子模块 | ADC `sample_stream`、DILA `bulk_stream` |
| **成员2** | WMS0/WMS1、锯齿/正弦发生、两路 AD5791、WMS→DAC 完整链路 | `scan_start` / `cycle_id` / `sine_phase`、DAC 物理接口 |
| **成员3** | UART、Modbus RTU、RS485、I²C、PTB210、HMP、EPSILON2、BMP390、SHT45、TFA1500-L、RD105 | 每个设备独立 `msg_stream` + FIFO |
| **项目负责人** | 时钟复位、统一时间同步、RAW 周期切帧、sensor_hub、stream arbiter、packetizer、命令/寄存器 crossbar、stepper、USB/FX3、top/XDC 与最终联调 | 系统级控制、数据汇聚、传输与整机集成 |

成员之间只通过已经冻结的标准接口连接。设备原生协议、SPI/UART/I²C 内部实现和模块内部状态机不得泄漏到其他成员模块。

---

## 4. 仓库结构

```text
Vapor_Radar_App_V2/
├── README.md
├── Docs/
│   ├── 下位机需求分析.md
│   ├── FPGA下位机Verilog开发指南_V1.1.md
│   ├── FPGA下位机详细架构与接口分配方案_V1.1.md
│   ├── 【任务书】三成员任务书_V1.3/
│   ├── 【开会】项目启动会资料_V1.2/
│   ├── 【资料】FPGA设备接入手册/
│   └── 【资料】电路板资料/
└── fpga/
    ├── rtl/
    │   ├── common/       # 公共 CDC、FIFO、stream FIFO、cfg_bus 等
    │   └── include/      # 全局宏、ID、寄存器地址、错误码
    ├── sim/
    │   └── common/       # BFM、checker、clock/time/WMS 仿真模型
    ├── tests/            # 公共 regression 与 synthesis smoke top
    ├── scripts/          # 静态基线检查脚本
    ├── reports/          # 公共基线检查/开发报告
    └── vivado_check.tcl  # Vivado 公共基线验证入口
```

后续成员模块建议继续按照开发指南的功能目录组织，例如：

```text
fpga/rtl/
├── adc/
├── dila/
├── wms/
├── dac/
├── sensors/
├── time/
├── control/
├── stream/
├── usb/
├── motor/
└── top/
```

---

## 5. 公共 RTL 使用规则

### 5.1 公共头文件

所有成员必须优先引用：

```text
fpga/rtl/include/project_defs.vh
fpga/rtl/include/stream_defs.vh
fpga/rtl/include/register_map.vh
fpga/rtl/include/error_codes.vh
```

其中：

- `project_defs.vh` 是**公共位宽、source ID、message ID 和共享协议常量的单一真源**；
- `stream_defs.vh` 只对标准 stream 宽度进行统一映射，不再独立维护另一套宽度；
- `register_map.vh` 统一定义模块 base address 与寄存器 offset；
- `error_codes.vh` 统一定义公共错误位。

禁止在成员 RTL 中重新定义已经存在的公共 ID、地址和数据宽度。

### 5.2 公共 CDC

```text
cdc_bit_sync.v
cdc_pulse_sync.v
cdc_bus_handshake.v
```

使用原则：

- 单 bit 状态跨域：`cdc_bit_sync`
- 单周期事件/脉冲跨域：`cdc_pulse_sync`
- 多 bit 低速配置跨域：`cdc_bus_handshake`
- 连续数据流跨域：使用异步 FIFO，不要直接逐 bit 同步数据总线

### 5.3 公共 FIFO

```text
sync_fifo.v
async_fifo_wrap.v
sample_stream_fifo.v
msg_stream_fifo.v
bulk_stream_fifo.v
```

所有 stream 均采用 `valid/ready` 握手。

当：

```text
valid = 1
ready = 0
```

表示**背压**，发送端必须保持当前 beat 的数据和 metadata 不变。

FIFO full 产生的 stall 不等于已经丢失数据。只有上游物理数据源或协议逻辑实际放弃了一条样点/记录时，才能累计对应的 `drop_count`。

---

## 6. 冻结的数据流接口

### 6.1 `sample_stream`

用于 ADC 原始样点等高速内部样点流：

```verilog
valid
ready
data[31:0]
flags[7:0]
```

ADC 原始样点**不逐点携带 timestamp**。

ADC 的时间信息按照 WMS 扫描周期由系统级 RAW framer 捕获和封装。

### 6.2 `msg_stream`

用于低速传感器、状态、事件等消息：

```verilog
valid
ready
data[31:0]
keep[3:0]
sof
last
source_id[15:0]
msg_id[15:0]
timestamp[63:0]
cycle_id[31:0]
flags[31:0]
```

低速非 WMS 周期相关消息通常使用：

```text
cycle_id = 0xFFFF_FFFF
```

成员3各 sensor source 必须先进入**独立 FIFO**，项目负责人后续通过 `sensor_hub` 做 message-locked 仲裁。

### 6.3 `bulk_stream`

用于 ADC RAW 周期块、DILA 曲线等高速块数据：

```verilog
valid
ready
data[31:0]
keep[3:0]
sof
last
source_id[15:0]
msg_id[15:0]
timestamp[63:0]
cycle_id[31:0]
flags[31:0]
fragment_index[31:0]
fragment_count[31:0]
```

当前公共基线：

```text
内部数据字宽           32 bit
最大 msg payload      1024 B
最大 bulk fragment    8192 B
DILA 默认 fragment    256 points
```

---

## 7. 配置总线 `cfg_bus`

成员模块统一使用 32-bit 配置总线：

```verilog
input  wire        cfg_valid;
input  wire        cfg_write;
input  wire [31:0] cfg_addr;
input  wire [31:0] cfg_wdata;
input  wire [3:0]  cfg_wstrb;
output wire        cfg_ready;
output wire [31:0] cfg_rdata;
output wire        cfg_error;
```

公共目录中已经提供：

```text
fpga/rtl/common/cfg_bus_if.v
fpga/sim/common/cfg_bus_master_bfm.v
```

成员 testbench 应使用公共 BFM 验证：

- 正常读写；
- byte write strobe；
- 非法/未实现地址；
- reset 后默认值；
- 只读寄存器；
- 参数越界与 `cfg_error`。

最终所有模块由项目负责人通过 `reg_ctrl_crossbar` 统一连接。

---

## 8. 时间同步基本规则

系统逻辑基线：

```text
sys_clk       = 100 MHz
time tick     = 10 ns
timestamp     = 64 bit
cycle_id      = 32 bit
```

系统中最终只允许一个统一时间基准 `time_sync_core`。

成员模块不得各自维护独立的长期自由运行时间计数器。

开发阶段可以使用：

```text
fpga/sim/common/time_sync_stub.v
```

进行独立仿真。

ADC 原始数据按 WMS 扫描周期打时间戳；其他传感器按照各任务书规定的协议事件捕获 timestamp。

---

## 9. 公共仿真环境

公共仿真模块位于：

```text
fpga/sim/common/
```

当前包含：

```text
clock_reset_gen.v
time_sync_stub.v
wms_reference_stub.v
cfg_bus_master_bfm.v
sample_stream_sink.v
msg_stream_sink.v
bulk_stream_sink.v
```

`sample_stream_sink`、`msg_stream_sink` 和 `bulk_stream_sink` 不只是打印数据，还用于检查标准 `valid/ready` 行为和 backpressure 下的数据稳定性。

成员在自己的 testbench 中应优先复用这些公共组件，不要为同一种标准接口再写一套不兼容的 checker。

---

## 10. 快速开始

克隆仓库：

```bash
git clone https://github.com/JiachengDong2026/Vapor_Radar_App_V2.git
cd Vapor_Radar_App_V2
```

先运行公共静态基线检查：

```bash
python fpga/scripts/check_baseline.py
```

成功时应看到：

```text
BASELINE_STATIC_CHECK_PASS
```

在安装并配置好 Vivado 的环境中运行公共 HDL regression：

```bash
vivado -mode batch -source fpga/vivado_check.tcl
```

该脚本会执行：

- 公共 behavioral simulation；
- 公共 RTL out-of-context synthesis smoke test；
- timing summary；
- CDC report；
- `check_timing`；
- utilization report。

behavioral regression 成功标识：

```text
PREDEV_COMMON_V12_PASS
```

完整脚本执行结束标识：

```text
PREDEV_COMMON_V12_VIVADO_CHECK_DONE
```

生成的检查报告位于：

```text
fpga/reports/
```

> 仓库中的 `PREDEV_COMMON_V12_STATIC_REVIEW.md` 记录的是公共基线生成阶段的静态检查结果。动态 HDL 验证结果应以实际 Vivado 开发环境中的最新执行结果为准。

---

## 11. 成员开发与提交要求

每个成员提交模块时至少需要同时交付：

1. RTL 源码；
2. 独立 testbench；
3. 必要的设备仿真 model / protocol vector；
4. Vivado 仿真结果；
5. synthesis / timing / CDC 说明；
6. 接口说明；
7. 寄存器说明；
8. 硬件管脚/连接说明；
9. 已知问题与未覆盖项。

提交前必须确认：

```bash
python fpga/scripts/check_baseline.py
```

仍然通过，并保证自己的修改没有破坏公共接口。

对于已经冻结的以下内容：

```text
stream 字段
cfg_bus
source_id
msg_id
register base/offset
timestamp/cycle_id 语义
物理管脚分配
```

成员不得自行修改。确需修改时，应先由项目负责人评估集成影响，并同步更新规范、公共头文件、testbench 和版本记录。

---

## 12. 三成员任务入口

### 成员1：双 ADC + DILA

任务书：

[`Docs/【任务书】三成员任务书_V1.3/01_成员1任务书_双ADC_DILA_V1.3.md`](Docs/【任务书】三成员任务书_V1.3/01_成员1任务书_双ADC_DILA_V1.3.md)

主要链路：

```text
AD4630 / ADC3660
        ↓
物理采集 + CDC/FIFO
        ↓
sample_stream
        ↓
DILA 1f / 2f
        ↓
bulk_stream
```

### 成员2：WMS + 双 DAC

任务书：

[`Docs/【任务书】三成员任务书_V1.3/02_成员2任务书_WMS_双DAC_V1.3.md`](Docs/【任务书】三成员任务书_V1.3/02_成员2任务书_WMS_双DAC_V1.3.md)

主要链路：

```text
配置参数
   ↓
WMS 锯齿 + 正弦
   ↓
DAC code
   ↓
AD5791
   ↓
激光驱动器
```

同时向系统提供：

```text
scan_start
cycle_id
sine_phase
wms_running
phase_valid
```

### 成员3：UART + 全部非 ADC 传感器

任务书：

[`Docs/【任务书】三成员任务书_V1.3/03_成员3任务书_UART_全部传感器_V1.3.md`](Docs/【任务书】三成员任务书_V1.3/03_成员3任务书_UART_全部传感器_V1.3.md)

主要链路：

```text
RS232 / RS422 / RS485 / UART / I2C
                 ↓
        公共 transport / protocol
                 ↓
           device driver
                 ↓
              TLV
                 ↓
       独立 msg_stream FIFO
                 ↓
          标准 msg_stream
```

成员3负责的设备包括 PTB210、HMP、EPSILON2、BMP390、SHT45、TFA1500-L 和 RD105。

---

## 13. 项目负责人保留模块

以下系统级功能由项目负责人开发或最终整合：

```text
clk_rst_mgr
time_sync_core
timestamp_capture
adc_cycle_framer
sensor_hub
stream_fifo / system buffering policy
stream_arbiter
data_packetizer
cmd_decoder
reg_ctrl_crossbar
status_manager
watchdog
stepper_ctrl
usb_fx3_gpif_if
vapor_lidar_top
vapor_lidar_top.xdc
FX3 firmware
USB endpoint / VLP1 protocol integration
Qt upper-computer integration
```

成员模块应通过标准接口与这些系统模块连接，不应直接依赖负责人模块内部实现。

---

## 14. 开发原则

本项目所有成员统一遵守以下原则：

- RTL 使用 **Verilog-2001**；
- `sys_clk` 逻辑开发基线为 **100 MHz**；
- 公共数据面统一为 **32 bit**；
- 所有 producer 使用 `valid/ready` 语义；
- backpressure 时必须保持数据和 metadata；
- 物理 ADC 数据源不得直接被下游 `ready` 反压；
- 高速跨时钟数据使用 async FIFO；
- FIFO 溢出/数据丢失必须可观测、可计数；
- 设备原生协议只能存在于对应 driver 内部；
- 不允许多个模块各自实现长期系统时间；
- 已冻结接口不得通过“临时适配”绕过规范；
- 模块必须先通过独立 testbench，再进入项目级集成。

---

## 15. 相关资料

项目会议资料：

[`Docs/【开会】项目启动会资料_V1.2/`](Docs/【开会】项目启动会资料_V1.2/)

设备官方资料：

[`Docs/【资料】FPGA设备接入手册/`](Docs/【资料】FPGA设备接入手册/)

电路板、原理图、UCF 与硬件资料：

[`Docs/【资料】电路板资料/`](Docs/【资料】电路板资料/)

---

## 16. 说明

本仓库处于持续开发阶段。

所有影响公共接口、数据格式、寄存器、ID、时间语义或硬件管脚的修改，都应同步更新对应规范与验证环境，避免出现“文档、RTL、testbench 三套定义不一致”的情况。

**先冻结接口，再并行开发；先独立验证，再进入系统集成。**