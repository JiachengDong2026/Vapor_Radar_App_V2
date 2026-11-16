# SDFM300 测距模块接口与迁移记录

2026-11-15：当前设备为 SDFM300 300 米型号，替换旧 TFA1500-L。本文覆盖设备线束、串口、寄存器、动作及上行距离语义。历史板测、旧 BIT 和旧采集文件不构成新设备验收。

## 设备规范来源

原始说明书：`D:/Project/说明书/SDFM300-600-1500 激光测距模块 说明书.docx`。已只读核对全文及表格；未修改原件。其 SHA256 为 963464778b5b8e6079170e6eaac820e861e36e5db9bd7ae3cd145bd7e6672344。

- 90% 反射率量程 0.05–300 m；10% 反射率 0.05–100 m。软件/RTL按型号最大300 m限制，不能推断低反射目标可达300 m。
- 默认 UART 460800 baud、8N1，上电主动输出；测量频率由反射信号自动切换 1 kHz/50 Hz，主机没有固定频率设置。
- 支持波特率仅 9600、19200、38400、115200、230400、256000、460800。RTL 的 BAUD 只配置本地接收器，设备必须预先由外部工具设置为相同波特率；RTL不发送修改设备波特率命令。
- 无信号强度、温度字段。说明书提供序列号、版本、波特率及切换IIC命令，当前生产驱动仅接收距离，不实现这些设备配置/查询。旧启停、高低频模式、自检及单次测量命令已撤回。

## 电气连接

设备为1.25 mm 5P：pin1 VCC接外部9–36 VDC，pin2电源GND，pin3串口GND接CON21-4，pin4 TX(SCL)接CON21-1（板载接收），pin5 RX(SDA)可接CON21-2（本镜像TX恒高，无命令）。不得沿用旧6针线束或把设备电源接普通FPGA GPIO。

保留板载UART经过电平转换的FPGA管脚：RX AN14、TX AP14、接口EN AK16，均沿用LVCMOS18约束。EN是板载接口使能，保持1；SDFM300没有旧Power_EN设备引脚，CON21-3不得接为设备供电/使能。说明书没有给出UART逻辑电压，接线前须核对设备电平与板载转换接口兼容性，不把9–36 V电源电压当串口电平。旧独立低频输入CON11-4/AP13已从顶层端口、管脚约束及CDC例外删除；没有新的低频UART。

## 设备串口帧

固定4字节：`5C distance_low distance_high checksum`，距离为u16小端厘米；`checksum=~((low+high)&0xff)&0xff`，不含帧头。原文 `5C 02 11 EC` =4354 cm=43.54 m=43540 mm；`5C FF FF 01` 表示无回波。SDFM1500的5字节/24位距离格式不适用本次型号。

解析器接受5..30000 cm，乘10形成u32毫米；0..4、30001..65534与FFFF均计为无效，清DISTANCE_VALID，不更新LAST_DISTANCE且不发距离记录。校验正确的无效帧仍计RX_FRAME_COUNT并刷新ONLINE。校验错误单独计数；UART帧错误清当前帧；残帧超时清解析状态；校验位为5C且校验失败时可作为下一帧头重同步。时间戳和同步标记捕获帧头UART起始位。默认字节间隔超时10 ms、在线超时1 s，允许50 Hz输出。

## FPGA寄存器与动作

source_id仍为0x0045，页0x6500，ID_VERSION升级为`0x00450200`。CONTROL默认0：bit0本地接收使能，bit1软复位（复位后禁用、恢复默认波特率及计数），bit3清FIFO；bit2 COMMIT及其他位返回RANGE。启用或禁用不发送串口命令，禁用清ONLINE/DISTANCE_VALID，已排队记录仍可排出。清FIFO是流中断，由调用者协调下游。

STATUS采用公共位定义：ENABLED bit0，READY bit1恒1，CFG_PENDING bit2恒0，BUSY bit3恒0，ONLINE bit4，FIFO_AFULL bit5，OVERFLOW bit6，ERROR bit7，TIME_SYNC bit8。ONLINE只代表近期收到校验正确的帧；DISTANCE_VALID表示最近有效距离状态，二者不同。ERROR为W1C，硬件新错误优先。

| 地址 | 字段 | 访问与语义 |
|---|---|---|
| 0x6510 | BAUD | RW，默认460800，禁用时可改，7档白名单，启用时BUSY=8 |
| 0x651C | LAST_DISTANCE_MM | RO，最后有效毫米距离；无效/掉线时保留历史值 |
| 0x6520 | DISTANCE_VALID | RO，最近距离有效；无回波、越界、禁用、超时后0 |
| 0x6528 | RX_FRAME_COUNT | RO，校验正确的完整帧（含无回波/越界） |
| 0x652C | CHECKSUM_ERR_COUNT | RO |
| 0x6530 | INVALID_COUNT | RO，FFFF或型号量程外 |
| 0x6534 | FIFO_LEVEL | RO，32位beat数量 |
| 0x6538 | DROP_COUNT | RO，整条记录丢弃次数 |
| 0x653C | TIMEOUT_TICKS | RW，非0，默认SYS_CLK_HZ |
| 0x6540 | TIMEOUT_COUNT | RO，残帧或在线超时事件 |
| 0x6548 | GAP_TICKS | RW，非0，默认SYS_CLK_HZ/100 |
| 0x655C | FORMAT_ERR_COUNT | RO，UART格式错误 |

`0x6514/18/24/44/4C/50/54/58`均为已撤回地址，读写返回BAD_ADDRESS=5。其他未定义或未对齐地址同样返回5，RO写返回6，范围错返回7。SENSOR_ACTION 32/33对所有参数返回UNSUPPORTED=13，且没有配置总线写及UART副作用；通用enable、clear FIFO、soft reset、W1C仍可使用，COMMIT不适用。

## 上行及存储兼容

VLP1外层布局、CRC、source_id `0x0045`、frame_type `0x10`、msg_id `0x1100`、cycle_id `FFFFFFFF` 保持不变。载荷仍12字节：

| 载荷偏移 | 字节 | 含义 |
|---|---|---|
| 0..3 | 01 00 01 00 | schema u16=1，count u16=1 |
| 4..7 | 13 00 03 04 | tag0x0013，U32，length4 |
| 8..11 | distance_mm LE32 | 毫米，合法50..300000，步长10 |

43.54 m对应载荷`01 00 01 00 13 00 03 04 14 AA 00 00`。主机不能再乘10。无回波不生成伪样本/FFFF距离TLV，不把LAST_DISTANCE历史值标为新鲜；通过DISTANCE_VALID、INVALID_COUNT及health检测失效。flags bit0=时间戳有效，bit2=帧头时同步状态，bit3=此前整条记录丢弃。无强度/温度TLV。保留完整记录所需空间；FIFO不足整包丢弃并累计drop，背压时元数据与数据稳定。

本仓库host分析器、Qt参考界面、协议示例输出当前型号SDFM300；既有VLP/BIN容器不改版本/布局。外部VaporView仓库独立维护，其新raw记录type6、CSV的`sdfm300_distance_m,sdfm300_valid`不改变FPGA VLP格式，也不在本仓库实现。历史type1..5和旧板测名称保留为历史证据。

## 离线验证与生成

本轮不打开Hardware Manager，不访问JTAG或USB硬件，不烧录或下载。新BIT及报告保留在仓库外。可复现命令与实测结论见 `SDFM300_BUILD_20261115.md`。静态检查不替代仿真与实现时序签核。
