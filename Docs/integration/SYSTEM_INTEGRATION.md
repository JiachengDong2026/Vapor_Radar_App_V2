> 正式归档：2026-09-23。本文源于2026-09-16集成版本；旧文中的Test专用、V2只读和当轮未上板描述属于当时记录。当前目录、六路既有实测及本轮离线边界以[正式集成修订](../INTEGRATION_REVISION_20260923.md)为准。

# 完整系统集成说明：20260916 传感器实测合入版

本版根目录 `E:/Documents/Vapor_Lc_App_Test/integrated_20260916`，完整工程在 `lead_system`，兄弟目录包含固定的common/member1/member2/member3源码。V2严格只读。最终构建结论以 `COMPLETION.md` 和本版reports为准；旧版时序与bit哈希仅见HISTORICAL_SYSTEM_INTEGRATION.md，不沿用于本版。

## 组成与接口

完整top包含AD4630、ADC3660、双路DILA、双路WMS/AD5791、七路传感器、步进控制、21页寄存器、VLP命令/数据、FX3 GPIF。SYS=100MHz，正式GPIF=50MHz。Qt不在范围内。

| lane/source/page | 设备 | 本版物理接口 | 验证状态 |
|---|---|---|---|
|0/0040/6000|PTB210|CON25 RS232A|用户报告独立实测通过|
|1/0041/6100|HMP|CON19共享RS485|尚未实测；复位禁用|
|2/0042/6200|EPSILON|CON14 MAIN RS232，921600/8N1|用户报告通信通过，室内无天线未验证定位|
|3/0043/6300|BMP390|共享I2C，0x76|用户报告独立实测通过|
|4/0044/6400|SHT45|共享I2C，0x44|用户报告独立实测通过|
|5/0045/6500|TFA1500-L|CON21 TTL及LF输入|用户报告独立实测通过|
|6/0046/6600|AI8 AI-8288|CON19共享RS485|用户报告独立实测通过|
|0047/6700|电机|原GPIO分配|尚未实测；复位禁用|

EPSILON的RS232B RX=AP19、TX=AP16均为设备收发；RS422端口释放并TX保持空闲。不引入独立测试工程的PC调试复用，完整系统PC数据出口为CON23 FX3 USB bulk（OUT02、IN86），串口助手不能直接读取该USB接口。

## AI8与共享RS485

RD105已从物理top和bank移除，旧source/page分配由AI8承接，ID_VERSION=0x00460200，TLV schema=2。能力位14表示AI8。主机必须根据ID/schema识别设备，不按旧RD105字段解析。

HMP和AI8在单根CON19总线上通过事务级仲裁复用，包括发送、接收、超时、重试和静默等待。共享FPGA UART配置固定19200/8N1；HMP实机默认可能8N2，接入前须外部配置为19200/8N1。默认地址HMP=240、AI8=1；同总线上从机地址必须不同。仲裁不会自动修改从机通信参数。未接HMP时保持禁用，不要广播启用所有传感器。

AI8当前机型8通道，本版默认只轮询地址1/通道1。温度raw=0.1℃/LSB。设温采用FC10后FC03读回；仅当匹配时confirmed_count增加。SENSOR_ACTION17的值仍为signed微摄氏度（40℃=40000000），完整raw范围也可写6650再commit。设温不会写入控制运行状态。寄存器和字段详见AI8_INTEGRATION_REPORT.md、ACTION_CONTROLLER.md。

EPSILON启用后先被动接收有效FDILink，约2.5秒未收到有效帧才执行恢复握手；不执行fsave/freboot或固定输出频率写入。NAV精度、GNSS定位和UTC同步仍需接天线后检验。

## 配置与数据路径

所有驱动复位后默认禁用，通过VLP配置/START启用。EPSILON为P1流，其余传感器P2；FIFO与hub/packetizer保留背压与丢包计数。I2C只有一个物理master，BMP390和SHT45经仲裁共享。能力位0..15依次为ADC0/1、DILA0/1、WMS0/1、DAC0/1、PTB210、HMP、EPSILON、BMP390、SHT45、TFA1500、AI8、电机；表示已实现，不代表实物在线。

命令decoder、action与status poller经事务仲裁访问21页crossbar。cfg错误码沿用地址5、只读6、范围7、忙8、超时9。动作最长2秒，decoder3秒；设温最终结果可读664C/6654，不能仅看WRITE shadow返回成功。

CLOCK RESET_MASK bits0..5为ADC/DILA、WMS/DAC、传感器、电机、stream/packetizer、USB/GPIF。复位先排空响应/数据；时间戳与系统诊断持久保存。FX3 FLAG A被观察到后锁存link_ready，它不是实时USB在线标志。FPGA内部复位与FX3物理reset分别控制。

AD4630保留四lane SDR、1MSPS、SCK25MHz、配置SPI5MHz及两SYS周期CS hold；ADC3660保留50MHz DDR采样CDC；DAC请求上限20MHz、实际SYS100下最高16.666666MHz。正式验收需要本版完整route和pad checker，不能引用独立工程时序替代。
