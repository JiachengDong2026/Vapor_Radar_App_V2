# LC 双路 TTL UART 接口修订，2026-10-27

> **2026-11-15现场确认**：两口分别连接原位、遥测两台温控，38400/8N1下均回复型号103、版本4370。0048/6800和0049/6900仍是原始UART桥，各台只使用本机内部通道1；实体身份不由桥ID推断。主机负责身份、采样、控制与读回，不新增FPGA协议引擎，现有RTL、桥默认115200、ID和BIT保持。实际应答支持`OK:`变体及末尾NUL，详见[两路TEC103接入](sensors/TEC103_GPIO_20261115.md)。

本修订在已恢复的 HMP+AI8 双设备版本之上新增 LC0/LC1 原始 UART。开发、仿真、综合和布局布线在 `E:/Documents/Vapor_Lc_App_Test/dual_lc_uart_20261027_01/` 进行，验证通过后才合并源码回 V2。生成文件留在测试目录。

## 范围和设备协议

提供两路独立全双工 UART，经现有 USB VLP READ_REG(0x02)/WRITE_REG(0x03) 收发原始字节。不会自动发送启动、使能、温度或电流命令，不解析厂家应答。LC 产品手册仅确认 TX1/RX1/GND TTL 接线，未提供命令表、默认波特率及明确的串口逻辑电压。115200/8N1 是本接口的可配置初值，不代表厂家默认值；实物通信必须按厂家的串口协议配置。

2026-11-15镜像仍保留CON19事务仲裁HMP/AI8/RD105三路（默认HC2A独立CON11、HMP槽不发送）、4A/6A页及extensions=0x3B。6A为legacy实验接口，不对应现场两台GPIO温控；现场上位机不呈现、不自动启用或发送此路径仪表事务。两个LC UART继续仅通过寄存器收发，地址及ID完全保持。桥是否存在以ID_VERSION判断，实体型号/在线以串口应答判断。[旧6A契约](../protocol/RD105_INTEGRATION_20261115.md)仅用于解释保留镜像。

## 管脚

| 通道 | FPGA 输出 TX -> LC RX1 | LC TX1 -> FPGA 输入 RX |
|---|---|---|
| LC0 / 原位 | CON11 pin5 / AM12 / LC_UART_TXD[0] | CON11 pin7 / AN12 / LC_UART_RXD[0] |
| LC1 / 遥测 | CON11 pin6 / AP11 / LC_UART_TXD[1] | CON11 pin8 / AP10 / LC_UART_RXD[1] |

四根 IO 均为 Bank88 的 LVCMOS33，CON11 不含 GND。两块 LC 的 GND 分别连接 FPGA 板 GND，例如 CON19 pin3；供电另接，禁止把 12/24V 或 5V 电源接到 GPIO。只有确认 LC 的串口兼容 3.3V 后才能直接接线，5V TTL 需加电平转换。两块 TX 不并接。LC 使用左下角 TX1/RX1/GND，右侧 RX2/TX2 用于显示模块。

本分配取代旧 V1.1 文档中 CON11 pin5/7 的 RD105 预留，pin6/8 也不再预留。模拟调制仍由 CON7/CON8 分别连接两个 LC 的 Input/GND，与串口独立。

## 地址和语义

LC0: source_id=0x0048，base=0x6800，ID_VERSION=0x00480100。
LC1: source_id=0x0049，base=0x6900，ID_VERSION=0x00490100。

兼容性：已撤回的历史RD105扩展曾使用source0x0048/base0x6800、ID=0x00480103；当前LC0的桥ID不同。现用2026-11-15镜像的HOST_EXTENSION_FLAGS.bit4为1，仅表示保留的legacy 6A实验接口，不能用于判断两台GPIO温控。软件必须核对桥ID并单独查询实体身份，不能沿用历史6800温控寄存器布局。

| 偏移 | 访问 | 内容 |
|---|---|---|
| 0x00 | RO | ID_VERSION |
| 0x04 | RW | CONTROL：bit0 enable；bit1 本地复位；bit3 清收发 FIFO；其他位必须为0 |
| 0x08 | RO | STATUS：bit0 实际enabled；bit1 enabled且TX有空间；bit3 TX/RX忙或TX排队；bit5 RX接近满；bit6 sticky overflow；bit7 任意sticky错误；bit9 RX非空；bit10 TX满 |
| 0x0C | W1C | ERROR：bit2 RX FIFO overflow；bit7 parity/framing error |
| 0x10 | RW | baud_hz，300..SYS_CLK_HZ/16，正式100MHz时上限6250000 |
| 0x14 | RW | FORMAT：bit3:0 数据位7/8；bit5:4 校验0=None、1=Even、2=Odd；bit9:8 停止位1/2；其余位0 |
| 0x18 | WO | TX_DATA：一次完整32位写入，数值0..255，入队一个字节；读返回0 |
| 0x1C | RO/pop | RX_DATA：读出并弹出一个字节；bit7:0 data、bit8 parity error、bit9 framing error |
| 0x20 | RO | TX FIFO level，不含正在移位发送的一个字节 |
| 0x24 | RO | RX FIFO level |
| 0x28 | RO | 完成发送的字节数，不等同于对端确认 |
| 0x2C | RO | 接收到的字节数，包含 FIFO 满时丢弃的字节 |
| 0x30 | RO | RX FIFO 满导致的丢字节数，同时进入 SYSTEM total_drop_count |
| 0x34 | RO | parity error 计数 |
| 0x38 | RO | framing error 计数 |
| 0x3C | RO | 单个FIFO深度，正式为256字节 |

波特率和格式只允许在 CONTROL.enable=0 且空闲时修改，启用状态返回 BUSY(8)。上电 CONTROL=0、115200/8N1(FORMAT=0x108)，TX保持高。实际收发还要求 SYSTEM.global_enable=1。STATUS.bit4固定0：原始UART不能判断物理设备在线，不能把模块存在/启用当作LC已经应答。

CONTROL写0禁用、终止当前帧并清收发FIFO；写9清FIFO且保持启用，也会终止当前帧；写2本地复位并禁用，清错误和计数，保留波特率/格式。禁用SYSTEM.global_enable会终止传输并清FIFO，保留配置的enable位，重新启用SYSTEM后恢复接收。系统传感器复位域reset_mask.bit2复位两路LC，恢复全部上电初值；仅复位stream不影响LC。

所有写操作要求wstrb=0xF，非法值返回RANGE(7)，不存在/未对齐地址返回BAD_ADDRESS(5)，写只读返回READ_ONLY(6)。禁用状态写TX或读取空RX返回NOT_READY(11)，满TX写返回BUSY(8)，均无入队/出队副作用。RX满时保留最早256字节，丢弃新字节并计数。接收错误字节仍入队并带错误标记，调用者决定是否使用。清sticky错误与新错误同周期时，新错误优先。

VLP source 0x0048/0x0049只允许访问各自页；SYSTEM(1)/BROADCAST(0xFFFF)可访问两页。旧21页索引和状态bitmap位保持不变，LC0/LC1附加在索引21/22。状态事件source分别为0x0048/0x0049。通用采样START/STOP/COMMIT/RESET/CLEAR动作集合不扩展到LC，操作LC使用本页CONTROL；WRITE_REG不设置auto_commit位。不要对RX_DATA使用MASK_WRITE或多寄存器扫描，读取有出队副作用。

## 上位机操作示例

下面的9600/8N1仅演示流程，实际值以厂家协议为准。

1. WRITE_REG(0x6804, 0)，禁用LC0。
2. WRITE_REG(0x6810, 9600)，WRITE_REG(0x6814, 0x108)。
3. WRITE_REG(0x0004, 1)，打开SYSTEM全局使能；这一步须结合原系统运行状态执行，避免覆盖其他CONTROL位。
4. WRITE_REG(0x6804, 1)，启用LC0。
5. 对厂家命令的每个字节重复WRITE_REG(0x6818, byte)。每次检查ACK和TX空间；不要将多个字节以连续地址写入。
6. READ_REG(0x6824, 1)查询RX数量，按数量重复READ_REG(0x681C, 1)，得到应答原始字节及错误标记。
7. LC1使用0x69xx地址独立操作；完成调试后WRITE_REG(0x6804,0)/WRITE_REG(0x6904,0)。

ACK仅说明字节已入队，TX_COUNT仅说明串行帧已发送。设备是否执行命令必须按厂家的应答协议判断。对超时的TX_DATA写入不能盲目重试，否则可能重复命令；对RX_DATA读取超时同样需要重建接收事务。

## 验证入口

`python fpga/scripts/check_baseline.py`

`python fpga/scripts/generate_lc_uart_vectors.py`

`python fpga/scripts/run_regression.py --output <外部新目录> --vivado-bin D:/Software/Vivado/Vivado/2020.2/bin tb_lc_uart_bridge tb_lc_uart_top tb_uart tb_vapor_lidar_top`

`python fpga/scripts/build.py --output <外部新目录> --vivado D:/Software/Vivado/Vivado/2020.2/bin/vivado.bat`

单元测试以独立位采样和位驱动检查8N1、7E2、8O1、同时收发、顺序、满FIFO、错误标记、非法访问和复位。顶层测试使用真实VLP帧/CRC和GPIF模型，从USB同时驱动两路UART环回，核对独立格式、RX出队、source访问范围和23页状态轮询。布局布线使用完整顶层，新增异步RX只例外到第一级ASYNC_REG，后续级保持时序分析；两个TX加入慢速输出时序约束。

完整结果、源码哈希和比特流路径由测试根目录REPORT.md记录。仿真通过不等于两块实物LC协议已经验证；本次不下载或固化FPGA，也不发送实际激光控制指令。


## 本次实现与时序收敛结果

90/90项RTL仿真、23/23项Python检查通过。首轮完整实现建立时间WNS=-0.064ns，因此未生成比特流；随后保持RTL、时钟、IO及不确定度约束不变，执行post-route AggressiveExplore和Explore布线，将建立时间收敛到+0.022ns。对唯一剩余的clock-fault Gray一级同步器保持违例执行局部布线修复：核对board25->sys_raw时钟、直接Gray源、两级ASYNC_REG及第二级正常时序，按Fast/Slow角推导物理互连延迟范围，仅重布一根网。

最终WNS=+0.022ns、WHS=+0.004ns、TNS=THS=0；294500个setup端点和294486个hold端点中违例为0。完整route/DRC/check_timing、DAC及AD4630管脚检查均通过后生成23,581,028字节的比特流。原有CDC条目与基线逐项一致：1个CDC-10和1个CDC-3；CDC-10为既有同步释放复位结构，需保留网表级复核，不能表述为“无CDC严重条目”。公共模块OOC烟雾报告仍有既有的综合阶段WHS=-0.087ns，该未布局报告不替代本次最终顶层的布局布线签核。

正式run_full_build.tcl增加相同的残余setup优化步骤，并将已有局部Gray保持修复严格扩展到上述clock_fault同步器。已有当前源码的routed.dcp需要继续收敛时，可用 `vivado -mode batch -source fpga/scripts/close_routed_timing.tcl -tclargs <当前构建routed.dcp> <外部新目录>`；只可使用已核对源码和约束哈希一致的本次检查点。该脚本保留与完整构建相同的最终检查门槛，不复用其他工程或历史RTL的检查点。

最终文件位于测试根目录的timing_closure_02/vapor_lidar_top.bit，SHA-256为`42ec394347236655d093f33a08a3dc8805fb24d44bd5d4703e8ac8aaa1a79040`。本次未下载、未固化到硬件，LC厂家命令及实物电平/波特率仍需按厂家资料确认。
