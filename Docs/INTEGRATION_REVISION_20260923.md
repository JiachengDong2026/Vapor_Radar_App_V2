# FPGA 正式集成修订 2026-09-23

本修订将 `Test/integrated_20260916` 的完整系统 RTL、约束、仿真与 2026-09-19 上位机协议归入正式 V2 仓库。它优先于 V1.1 指南和 V1.3 任务书中关于旧 RD105、EPSILON RS422、GPIF 目标频率及历史验收状态的描述。未列出的冻结端口宽度、source ID 和 VLP1 帧格式继续沿用原规范。历史文件中的“V2只读”属于此前任务，本次合并已获用户授权。

## 正式目录与接口依据

| 内容 | 正式位置 |
|---|---|
| 完整顶层 | [vapor_lidar_top.v](../fpga/rtl/top/vapor_lidar_top.v) |
| 公共模块与全局定义 | `fpga/rtl/common`、`fpga/rtl/include` |
| 设备与数据链 | `fpga/rtl/sensors`、`adc`、`dila`、`wms`、`dac`、`motor` |
| 时钟、时间、控制、传输 | `fpga/rtl/clock`、`time`、`control`、`stream`、`usb` |
| 引脚和时序约束 | [系统XDC](../fpga/constraints/system/vapor_lidar_top.xdc)、`fpga/constraints/adc`、`fpga/constraints/wms_dac` |
| testbench、模型与向量 | `fpga/tests/{system,sensors,adc_dila,wms_dac}`、`fpga/sim` |
| FX3与主机源码 | `firmware/fx3`、`host` |
| 上位机精确协议 | [FPGA_HOST_PROTOCOL_V1.0.md](protocol/FPGA_HOST_PROTOCOL_V1.0.md) |
| 控制与内部接口 | [动作控制器](integration/ACTION_CONTROLLER.md)、[错误原因侧带](integration/CFG_ERROR_CODES.md)、[传感器bank](integration/sensors/INTEGRATION.md) |

生产构建使用 `fpga/rtl/clock/clk_rst_mgr.v`；原 `fpga/rtl/common/clk_rst_mgr.v` 仅保留供前期公共回归，不能将两者一起编译。全系统 SYS=100 MHz，GPIF=50 MHz。ROM `fpga/rtl/wms/sine_q31.mem` 随源代码保存，构建与仿真必须加载。ADC、DILA、WMS、DAC和电机仍是完整顶层依赖，接口实现存在不代表已经实物验收。

## 六路传感器与配置

| 设备 | source / page | 物理通道与本版约定 |
|---|---|---|
| PTB210 | 0040 / 6000 | CON25 RS232A |
| HMP，当前未接 | 0041 / 6100 | CON19共享RS485，默认地址240，保持禁用 |
| EPSILON | 0042 / 6200 | CON14 MAIN RS232，RX AP19、TX AP16，921600/8N1；不再走旧AUX RS422 |
| BMP390 | 0043 / 6300 | 共享I2C；实物地址0x77，RTL复位默认0x76 |
| SHT45 | 0044 / 6400 | 共享I2C，地址0x44 |
| TFA1500-L | 0045 / 6500 | CON21串口及LF输入 |
| AI8 AI-8288 | 0046 / 6600 | CON19共享RS485，默认地址1、通道1，19200/8N1 |
| 电机，未实测 | 0047 / 6700 | 保留原GPIO连接及禁用复位状态 |

BMP390须在禁用时写 `0x6310=0x77` 并读回，然后启用；重置该模块或重载BIT后重新配置。本次不改变RTL的0x76默认值，保持已调通完整系统行为。BMP上传原码及21字节标定系数，由主机按当前传感器本次标定补偿，不能将原码直接作为Pa或摄氏度。

AI8承接原0046/6600分配，`ID_VERSION=0x00460200`、MSG1100 payload schema=2，TLV0460..0467。旧 `SRC_RD105` / `REG_BASE_RD105` 仅为源码兼容别名，正式bank不实例化RD105。AI8温度raw为0.1℃/LSB；SENSOR_ACTION十进制17的value使用signed微摄氏度，40℃为40000000。设温须FC10写SP后FC03读回匹配，确认计数增加才视为成功；不会因设温自动写运行、自整定或锁定参数。

HMP与AI8通过完整Modbus事务仲裁共享CON19，覆盖超时与重试；不能同时驱动总线。设备地址必须不同；HMP将来接入前需配置成与总线相同的19200/8N1。EPSILON启用后先被动接收约2.5秒，无有效FDILink帧才尝试一次只读恢复序列，不执行保存或重启设备命令。PC主数据出口是CON23 FX3 USB，独立串口调试top未纳入正式顶层。

## 传输与兼容性

应用USB VID/PID=04B4:00F1，Bulk OUT=0x02、IN=0x86；先启动持续IN接收，再发送PING或配置命令。FPGA采用VLP1固定40字节头、小端、CRC32/ISO-HDLC，CRC之后补零至4字节边界，补零不计入帧长或CRC。最大CMD基本帧4096字节，最大DATA payload8192字节。GP01 FX3基线镜像SHA256为 `e705c3032aece44c2ef1890e45c9f6b5d5aa31fc6facc8ab02ddb2847e043dd5`，固件源码与构建说明归入 `firmware/fx3`。

配置原因侧带保留原cfg_error并增加4位cfg_error_code；地址5、只读6、范围7、忙8、超时9直接传至VLP应答。这是错误枚举，不能与模块ERROR位掩码或FX3诊断错误域混用。长RAW周期使用schema2分片，短RAW保留schema1；外层VLP版本与payload schema相互独立。完整字段、自动提交与掩码别名规则见[协议](protocol/FPGA_HOST_PROTOCOL_V1.0.md)及[实现扩展](integration/PROTOCOL_EXTENSIONS.md)。

六路启用集合mask为0x7D，不含HMP。START/STOP的source掩码、stream_mask与寄存器页号含义不同，不得混用；能力位0xFFFF只表示已实现模块。已完成的历史60秒实板测试使用逐路寄存器写入路径，不自动证明所有START/STOP异常路径已板测。

## 已有实测与本次验证边界

2026-09-18既有六路并发记录持续约60秒，共7,278,076字节、91,087个VLP帧；全部外层CRC通过，未发现帧结构问题。各源记录为PTB57、EPSILON44,629（其中AHRS3053）、BMP60测量+1标定、SHT61、TFA42,137、AI8 56。这个数量是一次观测，不能作为速率或吞吐保证；ADC满速USB吞吐尚未实测。

AI8记录始终带HOST=0x0200全局报警，其中4条ALARM=0x20，必须保留报警显示；采集通信通过不等于设备无报警。EPSILON室内无天线，GNSS位置精度、有效UTC及外部PPS关联未验收。历史系统/事件drop为778，在稳定并发期间未增加，各传感器drop为0。HMP未接，ADC/DILA、WMS/DAC及电机不在这批板测通过范围。

历史实测FPGA BIT SHA256为 `99ef3e1a7605c793d0d22c871f53ac751db18127e6a79aad7919c644d617f46f`。该哈希仅用于来源追溯，不能当成本次新构建BIT的身份。本次用户明确暂未接板，执行离线回归和正式BIT构建，不进行烧录、温控写入或新增实物验收。本次产物与报告保存在 `E:/Documents/Vapor_Lc_App_Test/formal_merge_20260923`，新的BIT身份、时序和验证结论以本轮实际构建清单为准。

## 版本记录

- 2026-09-16：完整系统纳入AI8、EPSILON MAIN RS232、共享RS485与配置原因侧带，完成模型及实现回归。
- 2026-09-18：既有六路USB并发记录取得上述实物通信证据，报警与未验证项目保留。
- 2026-09-19：上位机协议1.0和离线VLP示例封存。
- 2026-09-23：按功能目录正式合并，维持已调通RTL行为；同步头文件、约束路径、testbench路径、接口规范及本轮离线边界。
