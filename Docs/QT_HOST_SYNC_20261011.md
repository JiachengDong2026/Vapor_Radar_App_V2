# Qt 上位机正式源码同步报告

日期：2026-10-11。来源：`E:/Documents/Vapor_Lc_App_Test/qt_vapor_monitor_volts_20261009`，V0.2.5。目标：`host/qt_monitor`。

## 同步范围

- Qt 界面、工作线程、VLP解析与传感器/ADC/DLIA解码、绘图、C# USB桥接及源码测试。
- 六传感器、双 ADC/DLIA、独立 WMS/DLIA 控制、WMS 标称峰值 V 输入/回读、固定纵轴与 BIN 录制/回放。
- 新增可配置、仓库外输出的构建脚本、CTest入口、开发交接和BIN格式说明；复用仓库已有VLP解析示例。
- 对比结果：10个生产 C++/头文件和1个C#文件与来源逐字节相同。差异仅在构建、测试参数化及文档；没有修改FPGA、FX3、寄存器或线协议。
- 不包含 SDK、DLL、EXE、图像、日志、实时采集文件、比特流。本轮既存未跟踪的探测器PDF及tmp文件不纳入提交。

## 验证结果

所有构建、日志及截图位于 `E:/Documents/Vapor_Lc_App_Test/qt_formal_sync_20261011`。

| 验证 | 结果 |
|---|---|
| 正式路径 build.ps1，Qt/C++ + C# 编译与部署 | 通过，build.log |
| CTest protocol/ui/plot | 3/3通过，ctest.log；界面98项、绘图23项 |
| 2026-09-30黄金采集额外回归 | 379项通过，93,466帧、16,144,880字节，capture_test.log |
| FPGA静态基线 | BASELINE_STATIC_CHECK_PASS |
| Python VLP参考解析器 | 13项通过 |
| 仓库历史BIN示例读取 | 9帧、656字节，CRC/边界无错误 |
| 部署EXE离线启动及WMS页面截图 | 通过，formal_ui_tab3.png |

生产源码哈希比对记录见外部 `source_comparison.json`。历史采集回归只验证已存数据的解析和换算，不代表本次新采集。

本次没有运行实板 control_smoke，没有连接USB/JTAG或改变WMS输出。未运行Vivado完整检查：本轮无RTL变更。V0.2.5的V单位仍为标称换算，不增加模拟端标定证据；PTB210/AI8既有硬件问题未在本次解决。

开发入口：[Qt README](../host/qt_monitor/README.md)、[交接说明](protocol/QT_HOST_HANDOFF_20261011.md)、[BIN格式](protocol/BIN_STORAGE_FORMAT_V1.0.md)。
