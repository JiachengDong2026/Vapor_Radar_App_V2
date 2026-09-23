> 正式归档：2026-09-23。本文源于2026-09-16集成版本；旧文中的Test专用、V2只读和当轮未上板描述属于当时记录。当前目录、六路既有实测及本轮离线边界以[正式集成修订](../INTEGRATION_REVISION_20260923.md)为准。

# 完整系统上板与主机核对顺序

## 文件与物理接口

只使用COMPLETION.md列出的本版BIT和SHA256，避免误选旧独立工程位流。FPGA上电不会自动启用传感器采集或下发AI8温度/启动加热命令。FX3应用镜像位于firmware/vapor_fx3/output/vapor_fx3.img；本轮不自动烧录硬件。

完整系统使用CON23 USB bulk双向通信（OUT端点02，IN86），没有CDC串口ASCII终端。CON14为EPSILON设备，CON25为PTB210设备，不能同时并接PC串口发送端。调试工具应遵照VLP1打包，不发送独立测试工程的`SET 40.0`文本。

## 第一次只测试已验证传感器

1. 检查BIT哈希、供电/接线，HMP与电机暂不启用。按firmware/vapor_fx3文档加载FX3固件并验证枚举。
2. 用VLP PING与GET_CAPABILITIES确认双向bulk。READ 6600应返回00460200，区分新AI8与旧RD105。查看clock/link/error状态。link_ready仅表示本次FX3复位后观察到过DMA标志，不代表持续在线。
3. source SYSTEM0001，START module_mask使用低32位0000007D、高32位00000000（bits0,2,3,4,5,6对应PTB/EPS/BMP/SHT/TFA/AI8），options=0；HMP bit1不选，电机不在传感器START集合。具体payload顺序按ACTION_CONTROLLER/协议定义发送。
4. 接收source0040/42/43/44/45/46的数据和状态，核对CRC、序号、时间戳、错误/丢包计数。EPS无天线时通信正常不等于GNSS定位/UTC有效。
5. 单独验证AI8设温：SENSOR_ACTION对source0046，action=17、value=40000000表示40℃。仅最终动作返回0且6648确认计数增长、6654低/高16位requested/readback均400时认定成功。664C非零结果、返回14或9均需检查设备状态；停止状态不会由设温自动解除。

若HMP以后接CON19，先在仪器侧配置19200/8N1、地址240，AI8地址1，两者不得同址。其后再启用HMP bit1并检查共享总线。AI8为8通道型号，本版只轮询一个选定通道；更换通道需先禁用、写661C（1..8）、再启用。

ADC/WMS/FX3实物链路及全系统同时吞吐本轮未上板验证。先通过上述传感器链，再分通道配置ADC/WMS/DAC并观察模拟输出和真实采集，最后逐步提高吞吐，检查FIFO/drop及USB背压恢复。电机保持独立调试阶段，不能从传感器实测通过推断机械动作安全或已验收。
