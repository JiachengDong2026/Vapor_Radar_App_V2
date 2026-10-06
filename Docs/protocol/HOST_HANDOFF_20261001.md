> 2026-10-04：已将2026-10-02上板验证的DLIA精度版本同步至正式V2，当前ID/profile为0101/00040101。历史构建记录保留；本次范围及验证见[同步记录](../MERGE_MANIFEST_20261004.md)。

# 上位机开发对接说明（双低速 ADC 集成版）

版本：2026-10-01。对象：XCKU11P 完整系统、FX3 GP01、六传感器、双 AD4630/DLIA、双 WMS/DAC。本文是当前联调入口，线协议仍为 VLP 1.0。详细字节格式见 [协议正文](FPGA_HOST_PROTOCOL_V1.0.md)，双 ADC 硬件差异见 [双 AD4630 修订](../INTEGRATION_REVISION_20260928_DUAL_AD4630.md)。文中地址为十六进制，配置值注明单位；R/W 表示寄存器操作，不是可直接发送的 ASCII 指令。

2026-10-02隔离候选源码补充：DLIA模块版本升为0x0101，参考采用插值，低通改为四阶1kHz。下表增加候选版本核验；2026-10-01的BIT路径、哈希与板测记录保留为历史，不能用于确认新算法已下载。候选版本与验证边界见[精度修订](../INTEGRATION_REVISION_20261002_DLIA_PRECISION.md)。

## 1. 版本、设备和联调边界

- PC 连接 CON23，Windows 使用 Cypress 驱动与 CyUSB.dll。应用 VID:PID 为 `04B4:00F1`，Bulk OUT=`0x02`，Bulk IN=`0x86`，配置/接口/alternate=`1/0/0`。
- EP0 vendor IN `0xB1`，value/index=0，读取32字节，前4字节应为 ASCII `GP01`；只匹配 VID/PID 不足以确认固件。`0xB0` 同样读32字节用于诊断。
- FPGA 上电或重下载会复位系统并中断输出；EEPROM 已装配固件的板卡在 FPGA 释放 FX3 reset 后枚举应用。若出现 BootLoader，不能当作应用连接成功。
- 本次新 BIT 位于外部测试目录 `E:/Documents/Vapor_Lc_App_Test/formal_build_20260930/full_build/vapor_lidar_top.bit`，SHA256=`776945fd2bf31ec2b7f5da824367aedc66d3f2bef5fbfb5dc996ebf4d720e844`。
- 用户已确认本轮暂不处理 PTB210 超时和 AI8 设备报警；保留驱动、解析及质量标志，不伪造在线值，不自动改仪表参数。HMP、电机不在本次验收范围。
- 2026-10-01 初次新 BIT 已真实下载，USB 83116帧CRC全部正确。但该次错误使用缺少 WMS 初始化的测试计划：RAW缺失、DLIA每路仅4096点异常前缀、WMS/DAC未启用。此记录不能证明完整采集或DAC通过；以外部后续完整启动复测报告为准。

连接后至少读取以下版本，发现不匹配应拒绝套用本配置：

| 地址 | 期望值 | 含义 |
|---|---|---|
| 0x4000 / 0x4100 | 0x00200101 / 0x00210101 | 两路共享 AD4630 |
| 0x4018 / 0x4118 | 0x00011800 | 24位有符号码 |
| 0x5000 / 0x5100 | 0x00300101 / 0x00310101 | 2026-10-02隔离候选DLIA模块0x0101；历史模块末字为0x0100 |
| 0x5024 / 0x5124 | 0x00040101 | 候选双路1MHz四阶1kHz低通；2026-10-01历史BIT为0x00020101 |
| 0x6600 | 0x00460200 | AI8 schema 2 |

## 2. USB 收包与命令

使用唯一的后台 IN 接收循环，持续读取，包括等待命令应答、停机排空时。Control Center 与上位机不可同时占用端点。一次读取可能是半帧或多帧，不能按 USB 返回边界拆 VLP。

所有多字节字段小端。40字节头：`magic[4], major:u8, minor:u8, type:u8, header_words:u8, total_len:u32, sequence:u32, source:u16, msg:u16, flags:u32, tick:u64, cycle:u32, payload_len:u32`。magic=`56 4C 50 31`，版本1.0，header_words=10。`total_len=44+payload_len`；头和payload之后附4字节CRC，再补零到4字节边界。CRC-32/ISO-HDLC，反射多项式EDB88320，初值/终异或FFFFFFFF；校验只覆盖头和payload。最大IN基本帧8236字节。

| 类型 | 值 | 分发 |
|---|---|---|
| CMD / RESP | 0x01 / 0x02 | 主机请求 / 应答 |
| DATA | 0x10 | 测量数据 |
| EVENT / STATUS | 0x11 / 0x12 | 事件、健康状态，不能算作采样点 |
| PROTOCOL_ERROR | 0x7F | 请求错误 |

命令串行执行，以会话、sequence、source、msg联合匹配应答。建议等待上限10秒，同时保持IN接收；超时写操作可能已执行，先读回状态，不盲目重发。寄存器32位、地址按4字节对齐，命令target可用SYSTEM=`0x0001`。

| msg | 请求payload | 成功应答payload |
|---|---|---|
| 0x0002 READ_REG | addr:u32, count:u16, reserved:u16=0 | status:u32=0, addr:u32, count:u16, reserved:u16, data:u32[count] |
| 0x0003 WRITE_REG | addr:u32, count:u16, options:u16=0, data:u32[count] | status:u32=0 |

普通写成功只表示寄存器接受，不代表shadow已生效或外设已执行。CONTROL通常为bit0使能、bit1复位脉冲、bit2提交脉冲、bit3清理脉冲；`4`为禁用并提交，`5`为保持使能并提交。不要将只读/未映射地址纳入批读。错误枚举和动作命令见协议第6章。

可直接移植 [vlp_reference.py](examples/vlp_reference.py) 的拆包、CRC及命令构造，参见 [示例说明](examples/README.md)。该代码不访问USB，Qt侧需要自行实现唯一接收者、命令队列和重连状态机。

## 3. 数据来源、单位和质量

| 设备 | source / msg | 寄存器页 | 主机处理 |
|---|---|---|---|
| PTB210，CON25 | 0040 / 1100 | 6000 | tag0012，I32毫帕；Pa=原值/1000 |
| EPSILON，CON14 MAIN RS232 | 0042 / 1200 | 6200 | 完整FDILink；按内部packet ID解析IMU/姿态/导航 |
| BMP390，I2C | 0043 / 1100 | 6300 | tag0100为21字节校准，0101/0102为压温原码，主机补偿 |
| SHT45，I2C | 0044 / 1100 | 6400 | tag0010温度/1000℃，0011湿度/1000%RH |
| TFA1500-L，CON21 | 0045 / 1100 | 6500 | tag0013距离，单位mm，不再乘10 |
| AI8，CON19 RS485 | 0046 / 1100 | 6600 | schema2；PV/SP原码×0.1℃，区分通信成功与仪表报警 |
| ADC0 / ADC1，CON15 / CON16 | 0020 / 1000；0021 / 1000 | 4000 / 4100 | 两路24位、默认1MS/s |
| DLIA0 / DLIA1 | 0030 / 1001；0031 / 1001 | 5000 / 5100 | H1/H2或I/Q，根据format字段解码 |

传感器TLV：schema:u16、count:u16；每项tag:u16、type:u8、length:u8、value及4字节对齐填充。type3=U32、7=I32、11=bytes。按tag解码，不依赖固定次序。EPSILON不使用此TLV结构；内部帧和字段详见协议第10章。

BMP390启用前写`0x6310=0x77`（默认0x76不适用当前板），缓存本会话校准后用 [bmp_compensation.py](examples/bmp_compensation.py) 补偿；缺校准不得显示虚构压力。EPSILON通信正常不等于GNSS定位或UTC有效。AI8保留alarm、host_status、transport_error、exception；设温必须写后读回确认，详见协议AI8小节，不能将写寄存器ACK显示为“设温成功”。

flags：bit0时间有效、bit1周期有效、bit2外部时间同步有效、bit3溢出、bit4设备错误、bit5部分数据、bit6配置变化、bit7原厂payload。图中保留异常样本标识，过期值标为历史值。tick为100MHz本地计数，1tick=10ns，不是UTC；用uint64存储并先相减再转秒。

## 4. 双 ADC 与谐波组包

两路共用AD4630 CNV/SCK和采样率，但有独立输入、FIFO、RAW和DLIA。ADC1已从CON17高速ADC改到CON16，不再是16位12.5MS/s。只通过ADC0的`4010`改共同频率；`4110/4130/4134`只读，`4140`未映射。

RAW格式0为I32（24位符号扩展）；格式1为U32。schema1头20字节：schema:u16、adc_bits:u16、rate:u32、count:u32、format:u32、reserved:u32，再接count个32位点。

RAW schema2头32字节：偏移0/2同上；4 rate:u32；8 total_samples:u32；12 format:u32；16 fragment_index:u16；18 fragment_count:u16；20 first_sample:u32；24 fragment_samples:u32；28 reserved:u32；32起为点。每片最多2040点。

DLIA schema2头32字节：0 schema:u16；2 format:u16；4 output_rate:u32；8 total_points:u32；12 fragment_index:u16；14 fragment_count:u16；16 first_point:u32；20 fragment_points:u32；24 bytes_per_point:u32；28 reserved:u32；32起为点。format0：I32 H1,H2，每点8字节；format1：I1,Q1,I2,Q2，每点16字节；format2再加H1,H2，共24字节。当前构建默认format0，MODE不是输出格式切换开关。

两类schema2布局不同。逐片先校验CRC，再按会话/source/msg/cycle/tick聚合，核验总点数、片号、首点、连续性、重复、格式及flags。PARTIAL/OVERFLOW周期即使片齐仍不是完整扫描。100Hz扫描、10kHz谐波输出时完整周期预期100点。

RAW电压需板卡前端配置。当前RLY5飞线2–3/5–6、两组S3 OFF、四外部反馈电阻未装、VREF标称5V、增益0.5、数字校正为1/0时：CON15=`N0×10/8388608 V`，CON16=`−N1×10/8388608 V`。第二路负号还原当前前端反相，不能用于所有板卡。界面提供独立增益/极性/校准设置并保存原码，不能为贴合信号发生器而擅改比例。

H1/H2为数字幅值，不直接套RAW电压系数，更不是浓度。低通混频没有额外×2补偿；气体浓度必须另做光路、功率、吸收模型及标气校准。可显示“每扫描周期2f最大值（数字幅值）”，不能标成已标定ppm。

## 5. WMS独立控制与DLIA参数页

WMS0/1页2000/2100，DAC0/1页3000/3100；两路分别配置。WMS `+10`锯齿mHz、`+14/+18`锯齿幅度/偏置I32 Q1.31、`+1C`正弦mHz、`+20`正弦幅度Q1.31、`+24`相位U32整圈、`+28/+2C`请求/实际更新率Hz、`+40`相位模式。100Hz=100000mHz，20kHz=20000000mHz；Q1.31不是伏特。

建议当前测试参数：100Hz扫描、20kHz正弦、500000次/s DAC更新；锯齿幅度107374182（约0.05）、正弦幅度21474836（约0.01）、偏置0；相位模式2。DAC控制0x312、clear=0x80000、范围0..0xFFFFF、gain=0x40000000（1倍）、offset=0。SPI请求20MHz，实际读回约16.667MHz。

**独立按钮不能调用通用START/STOP动作。** 动作控制器选择某路WMS/ADC/DLIA任一位会联动完整采集通道。独立启停应对对应页CONTROL读写，并保持全局使能；“停止采集”不应清全局或停止另一条WMS/DAC。DAC与WMS分开：若需要扫描标签而不需要模拟输出，可运行WMS但禁用对应DAC。

DLIA页5000/5100：`+10`独立参考mHz，`+14`1f相位、`+18`2f校正（U32整圈），`+1C`输出Hz，`+20`MODE。MODE bit0选择WMS参考、bit1幅值使能、bit2旁路低通；MODE2=独立参考+幅值+低通，MODE3=板上WMS参考+幅值+低通。读`+4C/+50`核验实际输出率/抽取因子，10kHz/1MS/s对应100。

四阶精度版的H2相位仍为`2*参考phase + PHASE_2F_CORRECTION`，不随1f校正寄存器加倍。参考插值不新增流水，第二个biquad新增3clk=30ns；滤波器本身的低频群延迟由约0.225ms增至0.416ms，扫描包络与瞬态会更晚响应。MODE.bit2同时旁路两级；`+34`累计两级饱和事件。数据格式、标签时间戳和相位寄存器含义保持原定义。

**MODE2仅改变混频参考，不解除周期帧对WMS的依赖。** 必须让同路WMS持续产生扫描周期和有效标签；无WMS时RAW可能完全没有，DLIA会积满4096点并溢出，停止时吐出的前缀不代表连续解调通过。外部发生器即使设为相同20kHz也不等于与FPGA锁相，拍频/相位漂移应与算法故障区分。

修改参数采用shadow→commit→等待pending清零→读回实际值。禁止GUI轮询覆盖用户正在编辑的输入框。改采样率先停双ADC并排空，重配共同PHY，再重新提交双DLIA；固定低通profile不会随频率自动重新设计。参数页显示请求值、生效读回值、enable/pending/error及饱和/drop计数。

## 6. 推荐连接、采集和停止顺序

1. 打开USB唯一接收者，核对GP01与模块版本，读取状态和错误基线。新连接不等于冷启动：先读enable，避免擅自复位正在输出的DAC。
2. 冷启动时停用采集，初始化双DAC映射及SPI，提交并等待ready；配置双WMS上述参数，提交并核验实际500kHz。开启DAC（如需模拟输出）、全局`0004=1`、WMS `2004/2104=1`；检查WMS周期ID、DAC write_count持续增加。
3. 双ADC停止且PHY空闲后，共同时序通过ADC0配置1MS/s并提交；核对4014/4114=1000000、格式24位、ready=1。两路expected-per-cycle可设0关闭点数预期检查。
4. 配置双DLIA参考、相位、10kHz输出及MODE，逐路提交，检查pending清零且实际率正确。先开DLIA，再开ADC。
5. 传感器逐页启用，BMP地址先改0x77。按需启用PTB/AI8并保留已知问题；HMP保持禁用。等待首样本和质量检查。
6. 默认只连续上传谐波。短窗诊断RAW时，设置`0050=3`（raw mask高字bit0/1，即source bit32/33），并设置`403C/413C=1`；这不替代ADC使能。两路1MS/s原码仅样本体即8MB/s，持续满速需另做吞吐验收。
7. 停止时先停ADC，继续收包直到在途数据排空，再停DLIA并排空；清RAW enable及raw mask，按需停止传感器。默认保留global/WMS/DAC。若要关模拟输出，提供明确的DAC停止操作，并说明可能保留最后码，不保证自动归零。
8. 重连清旧半帧、分片缓存、pending请求和时间原点；重新读取实际状态。不要用历史“已启动”按钮状态推断板上状态。

## 7. 交付与验收检查表

交给上位机开发者：本文、[完整协议](FPGA_HOST_PROTOCOL_V1.0.md)、[双AD4630修订](../INTEGRATION_REVISION_20260928_DUAL_AD4630.md)、[寄存器附录](source_reference/WMS_DAC_REGISTER_MAP.md)、[ADC/DLIA附录](source_reference/ADC_DILA_REGISTER_MAP.md)及examples。附录旧高速ADC行以双AD4630修订覆盖。

联调保存：BIT哈希、GP01诊断、完整原始USB字节、命令/应答、配置读回、各源样本数、分片完整率、CRC/溢出/drop计数、最后硬件状态。区分程序退出0、协议完整、连续采样、模拟波形验证四种结论。DAC计数正常不证明CON7/CON8模拟波形正常，须示波器核验。

Qt建议：USB线程唯一读取；解析/落盘与界面解耦；图形10–20Hz刷新，显示降采样但原始数据保留。WMS0/1、DLIA0/1各自独立控制，操作进行中禁用重复提交；失败显示具体命令状态与模块错误，不清除历史证据。
