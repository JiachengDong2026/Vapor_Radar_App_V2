> 2026-11-15：当前测距设备为[SDFM300](../Docs/integration/sensors/SDFM300.md)，0x0045距离毫米TLV兼容；0x6500 ID=0x00450200，旧模式/命令地址已撤回。历史BIT/板测名称仅代表当时设备。

> 2026-11-13：正式BIT默认使用HC2A（ID `0x00410106` / HCD2），旧六路HMP计划不能直接套用。请先阅读[最新下位机说明](../Docs/LOWER_COMPUTER_RELEASE_20261113.md)与[HC2A规范](../Docs/integration/sensors/HC2A_ROASCII.md)。电机窗口及Qt参考源码保留。

# 主机工具与 Qt 上位机参考实现

- **最新 Qt 上位机 V0.2.5**：[源码及构建](qt_monitor/README.md)、[正式开发对接](../Docs/protocol/QT_HOST_HANDOFF_20261011.md)。
- [BIN 数据存储说明](../Docs/protocol/BIN_STORAGE_FORMAT_V1.0.md)。
- 以下命令行工具与板测描述保留为历史六传感器联调参考，不代表最新 Qt 界面的行为。

# USB 六传感器联调工具

本目录保存已用于 GP01 六路采集的 C# 源码、Python VLP 分析器和测试计划。依赖 Windows .NET Framework 4、Cypress 驱动及本机 SDK 的 CyUSB.dll；Python 分析器仅使用标准库。仓库不分发 DLL 或 EXE。

## 离线构建和检查

在仓库根目录运行，SDK路径按实际安装位置修改：

```powershell
python -B host/build.py --cyusb 'D:/Program Files (x86)/Cypress/EZ-USB FX3 SDK/1.3/library/c_sharp/lib/CyUSB.dll' --output 'E:/Documents/Vapor_Lc_App_Test/formal_merge_20260923/host'
python -B -m unittest discover -s host -p 'test_*.py' -v
python -B Docs/protocol/examples/test_vlp_reference.py
```

构建/单元测试不访问硬件。

## 上板回归（连接板卡后执行）

先加载本次正式 FPGA BIT，再通过 Control Center 的 Program > FX3 > RAM 加载配套 GP01 IMG。运行采集工具前关闭 Control Center 的自动收发，避免两个程序消费同一队列。SensorRun要求唯一的04B4:00F1设备及匹配的GP01诊断。

```powershell
& 'E:/Documents/Vapor_Lc_App_Test/formal_merge_20260923/host/SensorRun.exe' 'E:/Documents/Vapor_Lc_App_Test/formal_merge_20260923/board_preflight_01' host/plans/sensor_preflight.txt
& 'E:/Documents/Vapor_Lc_App_Test/formal_merge_20260923/host/SensorRun.exe' 'E:/Documents/Vapor_Lc_App_Test/formal_merge_20260923/board_six_01' host/plans/sensor_six_60s.txt
python -B host/analyze_sensors.py 'E:/Documents/Vapor_Lc_App_Test/formal_merge_20260923/board_six_01/bulk_in.bin' --require-six
```

输出目录必须是新的目录。计划首先设置BMP390地址0x77，再依次使能SHT45、BMP390、PTB210、AI8、EPSILON和SDFM300，等待约60秒、读取计数，最后禁用各路。HMP、ADC、WMS/DAC和电机保持关闭；AI8没有设温写入。先确认传感器物理连接及电源。

SensorRun只允许限定的诊断读取、六路使能和BMP局部复位/地址选择，保存请求、应答及原始USB流。异常退出会尝试禁用已触及的设备；拔线等情况下清理可能失败，应检查终端报告和设备状态。CaptureIn是限时接收工具，可选发送通过白名单校验的READ_REG二进制请求。

工具退出成功仅表示捕获完成。验收还需要CRC、帧完整性、各路真实样本、错误/丢弃计数以及设备报警检查。既有2026-09-18板测证据为91087帧全部VLP CRC通过，不能代替新BIT的实板验收。本次板卡未连接，尚未运行上述上板命令。

完整格式和工程量单位见 [VLP协议](../Docs/protocol/FPGA_HOST_PROTOCOL_V1.0.md)；BMP390在FPGA上传原始ADC和标定，由bmp_compensation.py按Bosch公式补偿。


2026-10-27：`gnss_motor_control.py --bridge <VaporUsbBridge.exe> status` 可读PPS校准快照与DM422状态；`move --steps <signed1..5000> --hz <20..400>` 为显式有限运动，运行时发送真实心跳，退出释放。`anchor --seq <PPS序号> --utc-seconds <确认的UTC整秒>` 提交明确对应关系。连接和接口条件见 [整机说明](../Docs/integration/GNSS_PPS_DM422_20261027.md)。独立电机JTAG GUI不能用于此整机固件。

2026-11-10：新增简易窗口 `motor_panel.py`。双击 `start_motor_panel.cmd`，提供正反向有限点动、停止/禁用、错误及脉冲计数显示；启动和连接不发送运动。使用说明见 [电机窗口](../Docs/integration/MOTOR_PANEL_20261110.md)。
