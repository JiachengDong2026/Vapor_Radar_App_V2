# 六传感器 payload 与温控确认协议

核对日期：2026-09-19。依据封存 `integrated_20260916/member3_uart_sensors/rtl`、`lead_system/rtl`、`common_baseline/fpga/rtl/include`，对照当前 `fx3_gpif_debug_20260918/host/analyze_sensors.py`、`bmp_compensation.py`、`plot_six_sensors.py` 以及六路实测摘要。本文件只描述已实现接口；本次未操作硬件，未修改 V2、封存源码或现有解码脚本。

## 1. 分流及公共规则

表内 offset 均从 **VLP payload 第一个字节**开始；EPS 的内部数据另以 D 表示。整数均为小端，I32 为二进制补码；不能将传感器线上 Modbus 的大端寄存器直接当作 VLP 字段端序。

| 设备 | source_id | frame_type | message_id | payload schema | FPGA寄存器页 / ID_VERSION |
|---|---|---|---|---|---|
| PTB210 | 0x0040 | 0x10 | 0x1100 | 1 | 0x6000 / 0x00400100 |
| EPSILON | 0x0042 | 0x10 | 0x1200 | 无TLV，完整FDILink帧 | 0x6200 / 0x00420101 |
| BMP390 | 0x0043 | 0x10 | 0x1100 | 1 | 0x6300 / 0x00430101 |
| SHT45 | 0x0044 | 0x10 | 0x1100 | 1 | 0x6400 / 0x00440101 |
| TFA1500-L | 0x0045 | 0x10 | 0x1100 | 1 | 0x6500 / 0x00450100 |
| AI8 | 0x0046 | 0x10 | 0x1100 | 2 | 0x6600 / 0x00460200 |

0x0041 为未接入的 HMP；0x0046 当前必须按 AI8 schema 2 处理，不能套旧 RD105 schema 1。上述数据 `cycle_id=0xFFFFFFFF`。health `(type,msg)=(0x12,0x1400)/(0x12,0x1401)/(0x11,0x1402)` 不是测量样本。

TLV record：offset 0 为 schema U16，offset 2 为 count U16；offset 4 起每项是 `tag U16, type U8, length U8, value[length]`，value 之后补零到四字节边界。常用 type：3=U32，7=I32，11=原始字节；标量 length=4。按 tag 解析并验证长度、类型、count 和 padding，勿把示例的固定 offset 当作永远不变的结构，尤其 AI8 有可选项、BMP有两类记录。

外层 flags：bit0=时间戳有效，bit2=采样时捕获的同步状态，bit3=之前发生记录丢弃，bit4=设备/测量状态异常。bit0 不保证设备无报警或 GNSS 有效；bit3 不是本条数值必坏，应保留数据并标明连续性损失。具体 bit4：PTB 将任意 sticky ERROR 映射到此位；SHT heater 非零置位；AI8 离线/报警/HOST[9:8]非零置位。不能只看 CRC 判全正常。保留 raw flags、错误位和计数器增量。

## 2. PTB210 压力

payload 固定12字节、schema=1、count=1：

| TLV header offset | value offset | tag/type/length | 内容及换算 |
|---:|---:|---|---|
| 4 | 8 | 0x0012 / I32 / 4 | pressure_mPa；Pa=值/1000，hPa=值/100000 |

这里 mPa 是毫帕，宏名 `PRESSURE_MPA` 不表示 MPa。实测原值101459000对应101459 Pa、1014.59 hPa。原始串口文本已由 FPGA 转为整数；上位机不再解析 ASCII。

## 3. BMP390 校准与原始采样

本板有效 I2C 地址为 **0x77**（FPGA地址0x6310）；0x76只是RTL复位默认值，芯片 ID 读回0x60。`0x6338 COMPENSATION_MODE` 当前只支持0，FPGA不输出已补偿的 Pa/℃。

| 记录 | schema/count | payload长度 | TLV header/value offset | tag/type/length | 内容 |
|---|---|---:|---|---|---|
| 初始化校准 | 1/1 | 32 | 4 / 8 | 0x0100 / BYTES / 21 | 芯片0x31..0x45按地址升序的21字节；payload29..31为零padding |
| 压温双开采样 | 1/2 | 20 | 4 / 8 | 0x0101 / U32 / 4 | pressure_adc_raw，低24位有效，高8位零 |
| 同一双开采样 | 同上 | 同上 | 12 / 16 | 0x0102 / U32 / 4 | temperature_adc_raw，低24位有效，高8位零 |
| 单通道采样 | 1/1 | 12 | 4 / 8 | 压力0x0101或温度0x0102 / U32 / 4 | 由PWR低两位选择；不能要求永远有两项 |

0x0100是元数据，不应计为压力样本。启动/重新初始化后缓存同一设备、本次采集阶段的校准；在收到校准和对应温度原码前，不输出虚构的补偿压力。后接入流的主机可能错过初始化校准，当前没有独立“重发校准”命令。保留原码、校准及来源，避免跨设备/复位阶段套用。

校准21字节精确解析格式为 Python `'<HHbhhbbHHbbhbb'`，顺序 `t1,t2,t3,p1,p2,p3,p4,p5,p6,p7,p8,p9,p10,p11`；对应字节offset为0,2,4,5,7,9,10,11,13,15,16,17,19,20。H/U16无符号，h/I16及b/I8有符号。现有 `bmp_compensation.compensate(calibration, pressure_raw, temperature_raw)` 按 Bosch 附录返回 `(pressure_Pa, temperature_C)`；先求温度，再代入压力多项式。需要hPa再除100。主机补偿不等同于传感器精度/标定验收。

## 4. SHT45 温湿度

payload 固定28字节，schema=1、count=3：

| TLV header offset | value offset | tag/type | 内容及单位 |
|---:|---:|---|---|
| 4 | 8 | 0x0010 / I32 | temperature_mC，℃=值/1000 |
| 12 | 16 | 0x0011 / U32 | humidity_milli_pct，%RH=值/1000 |
| 20 | 24 | 0x0001 / U32 | 当前 heater 模式，0=关闭，1..6=加热模式 |

三个length均4。FPGA已验证原始两组CRC，执行 `floor(rawT*175000/65535)-45000` 和 `clamp(floor(rawRH*125000/65535)-6000,0,100000)`；不要把湿度值再按65535缩放。heater非零同时使外层bit4置位，须标为加热测量；常规环境温湿度显示应保留该标识。

## 5. TFA1500-L 距离

payload固定12字节、schema=1、count=1，header offset4、value offset8，tag=0x0013/type=U32/length=4，数值已经是 **mm**。HF原始距离由FPGA乘10；LF使用配置的比例。主机不能再统一乘10。checksum/格式/无效距离由解析器处理，只有 distance_pulse 形成测量记录；寄存器 LAST_DISTANCE 的历史值不能代替当前有效样本。

## 6. EPSILON FDILink与姿态

VLP payload 保留完整内帧；不能从 VLP offset0直接按AHRS浮点读数。

| VLP payload offset | 长度 | 内容 |
|---:|---:|---|
| 0 | 1 | 0xFC |
| 1 | 1 | FDILink message ID（与VLP 0x1200不同） |
| 2 | 1 | 内部数据长度L |
| 3 | 1 | 内部序号U8，回绕不代表VLP序号回绕 |
| 4 | 1 | header CRC8 |
| 5 | 2 | payload CRC16，**高字节在前** |
| 7 | L | 内部数据D，小端字段 |
| 7+L | 1 | 0xFD；VLP payload总长=L+8 |

CRC8覆盖内帧offset0..3，init=0，反射多项式0x8C；CRC16覆盖D，init=0、多项式0x1021、MSB-first。外层CRC通过后仍校验内部长度/结束符/两重CRC。当前RTL仅转发ID 0x40..0x7F中掩码允许的完整帧；默认全选。

姿态首选 **FDILink ID=0x41、L=48**，不是ID=0x40。以下 D offset 对应VLP payload offset加7：

| D offset | VLP payload offset | 类型 | 字段 | 单位 |
|---:|---:|---|---|---|
| 0/4/8 | 7/11/15 | 3×F32 | RollSpeed/PitchSpeed/HeadingSpeed | rad/s |
| 12/16/20 | 19/23/27 | 3×F32 | Roll/Pitch/Heading | rad；显示度=值×180/π |
| 24/28/32/36 | 31/35/39/43 | 4×F32 | Q1/Q2/Q3/Q4 | 无量纲，保留手册顺序 |
| 40 | 47 | I64 | 设备Timestamp | µs，设备自身时间语义 |

用逐字节小端读取或 `struct.unpack_from`，这些字段相对 VLP payload并非4字节对齐。拒绝NaN/Inf进入普通曲线。现有 `plot_six_sensors.py` 读取 `<3f` 于D offset12，符合手册11.2.2；`analyze_sensors.py` 本身只保留raw payload，不直接输出三个姿态角。

ID0x40为56字节IMU：D0/4/8角速度rad/s，D12/16/20含重力加速度m/s²，D24/28/32磁场mG，D36 IMU温度℃、D40压力Pa、D44压力温度℃（以上F32），D48设备I64时间µs。若扩展显示须按内部ID和长度分派。

导航/时间状态：ID0x50且L=102时，D2为 **Filter_status U16**，D4为 **Filter_Update_status U16**，D6/D10为UTC秒/微秒U32；Filter_status bit3为UTC初始化。现有分析器的 `navigation_status_raw` 把D2/D4拼为U32，只是原始打包值，不是手册定义的单一导航状态字段。ID0x53且L=4的D2同为Filter_status；ID0x51且L=8的D0/D4为UTC秒/微秒。RAW值不是已有效UTC。当前实测UTC初始化均false；室内无GNSS天线应显示姿态和“GNSS/UTC未有效”，不能把通信正常或有姿态推断成定位、绝对时间有效。RTL进一步要求UTC秒>=946684800、微秒<1000000才发布对应时间标签。

### 6.1 位置与速度：MSG_INS/GPS，内部ID0x42

手册11.2.3定义内部数据长度 **L=72**、完整FDILink帧长80。以下全部offset从内部数据D开始，换成VLP payload offset统一加7。F32/F64均为IEEE-754小端浮点，数值可为负；不得按整数重解释或截断为无符号数。

| D offset | 长度/类型 | 字段顺序 | 单位与语义 |
|---:|---|---|---|
| 0/4/8 | 3×4/F32 | BodyVelocity_X/Y/Z | m/s，机体系速度 |
| 12/16/20 | 3×4/F32 | BodyAcceleration_X/Y/Z | m/s²，机体系加速度 |
| 24/28/32 | 3×4/F32 | Location_North/East/Down | m，上电为0，从坐标原点到当前的北/东/地向距离 |
| 36/40/44 | 3×4/F32 | Velocity_North/East/Down | m/s，NED速度 |
| 48/52/56 | 3×4/F32 | Acceleration_North/East/Down | m/s²，NED加速度 |
| 60 | 4/F32 | Pressure_Altitude | m，由气压计直接得到、未经融合的高度 |
| 64 | 8/I64 | Timestamp | µs，设备上电以来时间，MCU外部晶振时钟源（手册11.4.1） |

此0x42是内部消息ID；与VLP source_id=0x0042只是数值碰巧相同。Location_N/E/D是局部距离，**不是纬度/经度/海拔**。NED的Down向下为正；不能直接把Down显示成“海拔”。本消息自身没有导航有效位，必须关联同源当前0x50或0x53的Filter_status及状态时效。手册9.1.2明确：导航初始化完成后位置、速度、加速度值才有效；外部位置源也可能完成导航初始化，因此导航初始化与当前GNSS fix应分别显示。

### 6.2 融合经纬度、速度、UTC：MSG_SYS_STATE，内部ID0x50

手册11.2.4定义 **L=102**、完整FDILink帧长110；该消息包含本条自己的状态和数值，优先用于避免跨消息状态关联。表中D offset加7即VLP payload offset。

| D offset | 长度/类型 | 字段 | 单位/说明 |
|---:|---|---|---|
| 0 | 2/U16 | System_status | 设备系统故障/报警位图，见6.4 |
| 2 | 2/U16 | Filter_status | 初始化与GNSS状态，见6.4 |
| 4 | 2/U16 | Filter_Update_status | 滤波量测更新有效位，见6.4 |
| 6 | 4/U32 | Unix_time | UTC秒，自1970-01-01 00:00:00 UTC |
| 10 | 4/U32 | Microseconds | 秒内微秒，必须<1000000 |
| 14 | 8/F64 | **Latitude** | WGS84纬度，**rad** |
| 22 | 8/F64 | **Longitude** | WGS84经度，**rad** |
| 30 | 8/F64 | Height | m；此字段表用词为“海拔” |
| 38/42/46 | 3×4/F32 | Velocity_north/east/down | m/s，北/东/地向速度 |
| 50/54/58 | 3×4/F32 | Body_acceleration_X/Y/Z | m/s²，机体系加速度 |
| 62 | 4/F32 | G_force | m/s²，估计重力加速度 |
| 66/70/74 | 3×4/F32 | Roll/Pitch/Heading | rad，范围分别[-π,π]、[-π/2,π/2]、[0,2π] |
| 78/82/86 | 3×4/F32 | Angular_velocity_X/Y/Z | rad/s，机体系角速度 |
| 90/94/98 | 3×4/F32 | Latitude/Longitude/Height_standard_deviation | **m**，不是rad或度 |

经纬度在线顺序为 **纬度在前、经度在后**；均乘180/π转为地图API通常需要的度，再按目标API要求排列，例如需要[longitude,latitude]时显式交换。保留double精度，并检查有限数、纬度范围[-π/2,π/2]、经度范围[-π,π]。这些范围是主机输入合理性检查，不能代替导航状态判断；(0,0)是合法地理坐标，也不能单靠“非零”判定位成功。

高度基准须保留原始字段名和来源：手册此表写Height为“海拔”，基础坐标章节5.7又描述椭球体高度；仅凭这两处文本不能确认已做哪个大地水准面转换。交付API宜名为 `height_m_raw` 并附消息来源，未进一步核定前不自动把它标成特定椭球高或正高，不自行添加/减去Geo_sep。

### 6.3 原始GNSS与独立位置/速度消息

MSG_RAW_GNSS（手册11.2.13，ID **0x59，L=74**，完整帧82字节）提供原始接收机输出，不与0x50融合结果混名。

| D offset | 长度/类型 | 字段 | 单位/说明 |
|---:|---|---|---|
| 0/4 | 2×4/U32 | Unix_time_stamp / Microseconds | UTC秒 / 秒内µs |
| 8/16/24 | 3×8/F64 | Latitude / Longitude / Height | 纬度rad / 经度rad / 高度m |
| 32/36/40 | 3×4/F32 | Velocity_north/east/down | m/s |
| 44/48/52 | 3×4/F32 | Latitude/Longitude/Height_standard_deviation | m |
| 56 | 4/F32 | Course | **度**，GPS航向；此项不能再乘180/π |
| 60 | 4/F32 | Geo_sep | m，手册描述“大地高与椭球高的高度差”；本文不推断其正负转换约定 |
| 64 | 4/F32 | Diff_age | s，差分龄期 |
| 68 | 4/F32 | Reserved4 | 保留 |
| 72 | 2/U16 | Status | 原始GNSS状态，位定义见下表 |

0x59 Status（手册11.4.7）bits3:0为GNSS fix枚举（与6.4表相同），bit4=多普勒速度有效，bit5=时间有效，bit6=外部GNSS，bit7=倾斜有效，bit8=航向有效，bit9=浮点模糊度航向，bits15:10保留。按字段分别检查有效位：时间使用bit5，速度使用bit4，航向使用bit8；不能以时间有效替代定位有效。位置fix=0/1不显示为有效定位，2仅标2D，不承诺高度有效。

| 内部ID / 手册节 | L / 完整帧长 | 精确D布局 | 说明 |
|---|---|---|---|
| 0x51 / 11.2.5 | 8 / 16 | D0 U32 Unix_time秒；D4 U32 Microseconds | 需关联Filter_status UTC初始化；没有自身valid位 |
| 0x53 / 11.2.7 | 4 / 12 | D0 U16 System_status；D2 U16 Filter_status | 没有Filter_Update_status字段 |
| 0x5A / 11.2.14 | 9 / 17 | D0 F32 HDOP；D4 F32 VDOP；D8 U8 GNSS_satellites | 精度因子及卫星数；不代替fix状态 |
| 0x5C / 11.2.16 | 32 / 40 | D0 F64 Latitude rad；D8 F64 Longitude rad；D16 F64 Height m；D24 F32 hAcc m；D28 F32 vAcc m | 纬度仍在经度前；自身无状态/时间字段 |
| 0x5D / 11.2.17 | 24 / 32 | D0/8/16三个F64 ECEF_X/Y/Z，m | 地心地固直角坐标，不能当经纬度 |
| 0x5F / 11.2.19 | 12 / 20 | D0/4/8三个F32 Velocity_north/east/down，m/s | NED速度；自身无状态/时间字段 |
| 0x60 / 11.2.20 | 12 / 20 | D0/4/8三个F32 Velocity_X/Y/Z，m/s | 机体系速度；自身无状态/时间字段 |

独立消息缺少自身状态时，必须保存关联的0x50/53及FPGA时间戳并标记关联新鲜程度；状态缺失/过期显示“状态未知”，不得沿用上一次会话的有效状态。手册未在这些字段表给出统一状态过期阈值，应作为上位机策略配置，不能冒称设备协议常量。

### 6.4 导航、UTC与GNSS有效状态

Filter_status（0x50 D2或0x53 D2）为U16；手册11.4.3：

| 位 | 手册名称/语义 |
|---:|---|
| 0 | Orientation_Filter_Initialised，姿态滤波器初始化 |
| 1 | Navigation_Filter_Initialised，导航初始化 |
| 2 | Heading_Initialised，航向初始化 |
| 3 | UTC_Time_Initialised，UTC初始化 |
| 7:4 | GNSS_Fix_Status，四位枚举 |
| 8 | Event_Occurred，保留 |
| 9 | Internal_GNSS_Enabled，内部GNSS使能 |
| 10 | Magnetic_Heading_Active，磁航向有效 |
| 11 | Velocity_Heading_Enabled，航向轨迹使能 |
| 12 | Atmospheric_Altitude_Enabled，气压高度使能 |
| 13/14/15 | External_Position/Velocity/Heading_Active，当前手册标保留 |

GNSS fix枚举（手册11.4.4）：

| 值 | 状态 |
|---:|---|
| 0 | NO_GPS，无GPS模块连接或GPS故障 |
| 1 | NO_FIX，GPS没有信号 |
| 2 | 2D_FIX，2D定位 |
| 3 | 3D_FIX，3D定位 |
| 4 | DGPS，DGPS/SBAS辅助 |
| 5 | RTK_FLOAT，RTK浮点解 |
| 6 | RTK_FIXED，RTK固定解 |
| 7 | STATIC，静态定点模式，通常用于基站 |
| 8 | PPP，精密单点定位 |
| 9 | RTK_DUAL，双天线均为RTK固定解 |
| 10..15 | 此手册未定义，保留raw并显示未知，不当成更高质量等级 |

System_status（0x50 D0或0x53 D0，手册11.4.2）：bit0系统故障、bit1加速度计故障、bit2陀螺仪故障、bit3磁力计故障、bit4气压计故障、bit5 GNSS故障；bit6/7/8/9分别加速度计/陀螺仪/磁力计/气压计超量程；bit10低温、bit11高温、bit12低压、bit13高压报警；bit14 GNSS天线未连接；bit15数据输出溢出报警。它是EPS自身状态，不同于VLP外层flags或FPGA寄存器ERROR。

Filter_Update_status（仅0x50 D4，手册11.4.8）每bit为1表示该量测更新有效：bit0加速度计、1磁力计、2 GPS位置、3 GPS速度、4 GPS航迹角、5 GPS双天线航向、6零位置、7零速度、8零角速度、9外部位置、10外部速度、11外部航向、12里程计速度、13 NHC零速度、14 NHC向心加速度、15保留。**量测更新有效位不是滤波器初始化位**，不能把“本条未做GPS更新”直接等同于融合导航无效；应按原义分别保存/展示。

实现上至少分开输出 `orientation_initialized`、`navigation_initialized`、`heading_initialized`、`utc_initialized`、`gnss_fix`、`system_status`、`filter_update_status`，而不是一个万能valid。融合位置/速度先要求导航已初始化并检查对应故障/当前数据；GNSS是否有fix、是否RTK、GPS更新是否有效分别呈现。UTC要求UTC初始化且秒内微秒合法；设备I64 Timestamp是上电运行µs，不可当Unix时间。当前室内无GNSS这组数据继续只作姿态显示，新增位置解码能力不代表已有有效位置验收。

本节字段来源为本地官方手册提取文本 `E:/Documents/Vapor_Lc_App_Test/project_audit/source_review/8-1-组合导航EPSILON使用手册V1.2_20250424.txt`：11.2.3–11.2.7（第2672行起）、11.2.13–11.2.20（第2869行起）、11.4.1–11.4.4（第3816行起）、11.4.7–11.4.8（第3957行附近起）及9.1初始化说明（第767行附近）。长度按各表末字段offset+size精确计算；本次未新增或更改EPS/主机解析代码。

## 7. AI8 schema 2

先检查0x6600=0x00460200。固定11个TLV，末尾可选2个温度TLV，因此count=11..13、payload长度92/100/108字节。每项length=4。

| header offset | value offset | tag | 类型 | 字段 |
|---:|---:|---|---|---|
| 4 | 8 | 0x0460 | I32 | PV原始I16符号扩展，0.1℃/count |
| 12 | 16 | 0x0461 | I32 | SP原始I16符号扩展，0.1℃/count |
| 20 | 24 | 0x0462 | I32 | SV原始I16符号扩展，0.1℃/count |
| 28 | 32 | 0x0463 | U32 | OP原始U16零扩展，保留raw，不臆定百分比 |
| 36 | 40 | 0x0464 | U32 | ALARM U8零扩展 |
| 44 | 48 | 0x0465 | U32 | CONTROL U8零扩展 |
| 52 | 56 | 0x0466 | U32 | HOST U16零扩展 |
| 60 | 64 | 0x0467 | U32 | SET_RESULT / COMMAND_STATUS（下文位图） |
| 68 | 72 | 0x0001 | U32 | DEVICE_STATUS，bit0 online，bits4:1 transport_error，bits12:5 exception |
| 76 | 80 | 0x0002 | U32 | DEVICE_ERROR：`HOST<<16`、`CONTROL<<8`、`ALARM`三者按位或 |
| 84 | 88 | 0x0004 | U32 | SAMPLE_COUNTER，完整成功轮询次数 |
| 92（若有） | 96 | 0x0014 | I32 | SP×100000，µ℃ |
| 前述之后 | 前述之后+4 | 0x0015 | I32 | PV×100000，µ℃ |

SP或PV只有在raw∈[-21474,21474]时才分别附带对应µ℃ TLV，以避免I32溢出。若没有SP可选项但有PV，PV header/value就在92/96。原始三个量除10显示℃，µ℃除1000000显示℃，禁止混用比例或当U16处理负温。

AI8每个样本为七次成功FC03读组成的完整快照，设备地址为SP=`0x0000+channel-1`、PV=`0x0600+channel-1`、SV=`0x0480+channel-1`、OP=`0x0360+channel-1`、ALARM=`0x0680+(channel-1)/2`、CONTROL=`0x06C0+(channel-1)/2`、HOST=`0x0851`。ALARM/CONTROL奇数通道取寄存器高字节、偶数取低字节。失败的部分轮询不会覆盖上一完整快照，但会发出离线失败记录；其数值可能陈旧，必须依DEVICE_STATUS隔离。成功样本计数不能当失败记录总计数。

通信可信条件：外层CRC及结构正确、DEVICE_STATUS bit0=1、transport_error=0、exception=0。设备健康另检查ALARM和HOST[9:8]。HOST bit8=系统故障、bit9=全局报警；不能仅凭bit9推断断线或具体通道。实测56条DEVICE_STATUS=1，HOST全为0x0200，ALARM为0或0x20，因此数值可显示但全保留 **flagged/全局报警**，并非通信失败。DEVICE_ERROR并非“零才正常”的通用错误码：正常CONTROL值也占其中一字节。

## 8. AI8温控写入、寄存器与返回确认

下表是已实现的协议说明，本次没有执行设温。FPGA页地址与前述AI8内部Modbus地址属于两层地址空间。

| FPGA地址 | 属性 | 精确语义 |
|---|---|---|
| 0x6600 | RO | ID_VERSION=0x00460200 |
| 0x6604 | RW | bit0 enable；bit1本地复位；bit2 commit；bit3清FIFO。写入同时给出期望enable |
| 0x6608 | RO | bit0 enabled；**bit1 online**；bit2 pending；bit3 bus_busy或pending；**bit4单周期sample_valid**；bit5 afull；bit6 overflow；bit7任意sticky错误；bit8 time_sync；bit9 result_valid；bit10 PV可表为µ℃；bit11 SP可表为µ℃ |
| 0x660C | W1C | sticky错误位图 |
| 0x6610/14/18/1C | RW，禁用时 | baud/slave/serial_format/channel；当前共享总线19200/8N1，slave1..80，wrapper通道1..8 |
| 0x6620 | RW | I32 shadow目标µ℃；值须≥-999000000且为100000整数倍；I32可表示的最大合法倍数2147400000 |
| 0x6624 | RO | 最近PV µ℃；不可表示时0，须查STATUS bit10 |
| 0x6628 | RO | HOST左移16、CONTROL左移8，与ALARM按位或组合 |
| 0x662C | RW，禁用时 | interval_ms，1..3600000；完成轮询后的间隔，不是严格采样周期 |
| 0x6630/34/38/3C | RO | CRC错误数 / 超时数 / FIFO level / drop count |
| 0x6640 | RO | 最近成功轮询SP µ℃；不可表示时0，须查STATUS bit11；不是shadow |
| 0x6644 | RO | 在线完整样本记录数 |
| 0x6648 | RO | 成功FC10写入并FC03读回相等的确认计数 |
| 0x664C | RO | COMMAND_STATUS，下文位图 |
| 0x6650 | RW | I32符号扩展的shadow raw；合法-9990..32000，单位0.1℃；超出µ℃可表示范围时0x6620读回0，应使用raw |
| 0x6654 | RO | 高16位last_readback，低16位last_requested；两者各按I16解释 |
| 0x6658 | RO | 高16位SP，低16位PV；各I16 |
| 0x665C | RO | 高16位SV(I16)，低16位OP(U16) |
| 0x6660/64 | RW，禁用时 | timeout_ms=1..65535；retry_limit=0..3 |

serial_format=0/1/2/3对应8N1/8N2/8E1/8E2；当前共享总线只能0且baud只能19200。影子目标可在运行时写，传输/地址/通道/轮询/超时/重试配置要禁用。范围是RTL接受范围，界面可另按仪表及实验范围限制，不能误认为整个RTL范围都适合实物温控。

普通寄存器流程：先读0x6648确认数和pending；写0x6620（例如40000000表示40℃）或0x6650（400）只更新shadow；再向0x6604写5（enable+commit，full-word）。commit快照shadow并清result_valid。禁止以4代替5：AI8拒绝“commit但enable=0”；pending时再次commit返回BUSY。写shadow后尚未commit不会写外部仪表。两个影子入口互相更新表示，应选择一个使用。

普通WRITE_REG count=1成功响应只表示本地cfg写入被接受，**不能显示“温度设置成功”**。commit后核心先FC10写选中通道SP，再FC03读同一SP；两次传输校验正确且readback=requested才增加0x6648。主机等待pending=0且COMMAND_STATUS bit16=1，再要求result=0、确认计数相比基线加1（32位回绕）、0x6654请求和读回等于此次目标。没有主机事务ID嵌入SET_RESULT，主机必须串行关联本次请求并保存基线。0x6640是下次成功完整轮询刷新，可能晚于设置确认；实际PV达到目标是另一个过程。

COMMAND_STATUS与TLV0x0467：bits3:0=result，bits7:4=transport_error，bits15:8=exception，bit16=result_valid，bits31:17=0。result=0成功；1=写事务失败；2=读回事务失败；3=读回不匹配；4=核心范围错误；5=配置错误或禁用中止。result_valid=0时result=0不表示成功。transport_error=0成功、1超时、2CRC、3地址/功能/长度/echo不匹配、4Modbus异常、5UART/间隔错误、6无效请求。设备异常码、result、外层VLP命令status、sticky ERROR是不同编码空间。

禁用会中止pending请求并置result_valid=1/result=5/transport_error=6，不保证物理设备此前未接受写入；失败/超时结果也不等同于SP绝未变化，应通过后续读回确认。core不会因设置成功直接刷新轮询SP/PV缓存。

动作路径：lead `action_controller.v` 的COMMIT和AI8 SENSOR_ACTION设温路径会先保存0x6648+1，执行commit、等待pending清零，再检查确认计数。计数不符合返回VLP status=14；动作超时等另报对应命令状态。WRITE_REG的AUTO_COMMIT会转入该动作等待；它与普通count=1本地写ACK语义不同。上位机仍应读取0x664C/54保留详细结果。旧 `MODBUS_INTERFACE.md` 描述的RD105“ACK即active/禁用可排队”不适用于当前AI8。

## 9. 其余传感器寄存器检索

所有地址为字节地址，单字U32。各页公共+00 ID、+04 CONTROL、+08 STATUS、+0C ERROR；ERROR是W1C。只读快照推荐使用完整合法范围，越界可能使整条READ返回错误。在线位除AI8外为STATUS bit4；enable bit0、afull bit5、overflow bit6、error bit7、sync bit8。bit1/2/3按设备解释，禁用后online可能保留历史状态（PTB）。

| 设备 | 可连续读范围/字数 | 专用offset→含义 |
|---|---|---|
| PTB | 0x6000..6038 / 15 | +10 baud；+14 UART格式；+18 poll_ms；+1C mode；+20压力mPa；+24帧数；+28解析错误数；+2C timeout_ms；+30 ID_HASH固定0；+34 FIFO；+38 drop |
| EPS | 0x6200..623C / 16 | +10 baud；+14/+18 ID0x40..5F/60..7F掩码；+1C raw_forward；+20 good_frames；+24 CRC计数；+28 sync事件数；+2C最后内部ID；+30/+34最近有效GNSS时间标签µs低/高字；+38 FIFO；+3C drop |
| BMP | 0x6300..6340 / 17 | +10 I2C地址；+14 poll_ms；+18 OSR；+1C ODR；+20 IIR；+24 PWR；+28 chip_id；+2C压力ADC；+30温度ADC；+34 I2C错误数；+38 compensation_mode=0；+3C FIFO；+40 drop |
| SHT | 0x6400..643C / 16 | +10固定I2C0x44；+14 poll_ms；+18 repeatability；+1C heater；+20 rawT；+24 rawRH；+28 CRC错误数；+2C I2C错误数；+30 serial低字；+34 serial高字固定0；+38 FIFO；+3C drop |
| TFA | 0x6500..655C / 24 | +10 baud；+14 mode；+18 command（读0）；+1C距离mm；+20距离有效；+24 APD温度raw；+28帧数；+2C checksum错误；+30无效帧数；+34 FIFO；+38 drop；+3C timeout_ticks；+40超时数；+44 silence_ticks；+48 gap_ticks；+4C LF比例；+50 LF mask；+54设备status raw；+58 version命令；+5C格式错误数 |

CRC/解析错误为历史诊断，不应由单个非零sticky位推出所有当前数据失效。禁用、复位、清FIFO和enable的外部行为各不相同：enable可触发设备初始化/测量命令，不能把寄存器写1叫“纯被动读取”。

## 10. 时间戳和显示建议

六路共用100MHz FPGA tick，1 tick=10ns；`(tick-t0)/1e8`为相对秒。保存U64原值，JavaScript应使用BigInt或先减t0，不能长期用Number存绝对U64。设备内部EPS µs时间与FPGA tick是两个时域。

| 源 | 当前RTL捕获时刻 |
|---|---|
| PTB210 | 响应第一个UART起始脉冲 |
| EPSILON | 完整FDILink帧起始0xFC字节的UART起始脉冲 |
| TFA1500-L | 解析帧首字节的UART起始脉冲 |
| BMP390 | 优先此前捕获的INT上升沿；否则raw读取I2C请求被接受时；校准记录为校准发布时 |
| SHT45 | 启动本次测量的I2C请求被接受时 |
| AI8 | 七次读取完成、完整快照发布时；失败记录为失败完成时 |

时间戳适合共同时间轴，但六设备的物理采样时刻与延迟并不相同。当前60秒记录实测：PTB57、EPS44629（其中AHRS3053）、BMP60样本+1元数据、SHT61、TFA42137、AI8 56 flagged样本。全部91087外层帧CRC通过、无framing issue；这一结论不消除AI8报警或赋予EPS GNSS有效性。
