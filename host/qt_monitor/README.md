# VaporMonitor V0.2.5 上位机参考源码

2026-10-11 从外部测试工程 `qt_vapor_monitor_volts_20261009` 同步。供正式上位机开发人员参考、复用与继续开发；本次同步未重新进行实板验收。

## 功能与源码入口

| 文件 | 用途 |
|---|---|
| `src/mainwindow.cpp` | 中文界面、独立 WMS/DLIA 控制、参数输入与回读 |
| `src/traceplot.cpp` | 固定坐标、滚轮缩放、拖动平移、断线显示 |
| `src/worker.cpp` | 命令队列、版本检查、连接、采集、记录与回放 |
| `src/protocol.cpp` | VLP 拆包/CRC、六传感器解码、ADC/DLIA 分片重组 |
| `src/dlia_profile.h` | 可接受的 DLIA 滤波版本 |
| `bridge/VaporUsbBridge.cs` | CyUSB 收发与本机 IPC；不直接操作界面 |
| `tests/` | 离线单元测试与需显式执行的实板诊断源码 |

支持 PTB210、TFA1500-L、EPSILON、AI8、SHT45、BMP390，两路 AD4630、H1/H2 和峰值，以及双路 WMS/DAC。HMP、电机不在本界面范围。详细交接见 [正式上位机开发说明](../../Docs/protocol/QT_HOST_HANDOFF_20261011.md)。

## 依赖

- Windows x64，Qt 6.11.2 MinGW64（CMake 最低要求 Qt 6.5），MinGW 13.1，CMake 3.21+，Ninja。
- .NET Framework 4.x 的 `csc.exe`，合法安装的 Cypress FX3 SDK 中的 `CyUSB.dll`；实机连接还需 Cypress USB 驱动。
- 仓库仅含项目源码，不包含 Qt/MinGW/Cypress 的 DLL、SDK 或驱动；第三方组件许可归各自权利人。

## 构建

从仓库根目录执行，路径按成员电脑修改。输出必须在正式仓库外；本项目统一放到 `Vapor_Lc_App_Test`。

```powershell
$out = 'E:/Documents/Vapor_Lc_App_Test/qt_monitor_build'
./host/qt_monitor/build.ps1 -OutputRoot $out `
  -CyUsbDll 'D:/Program Files (x86)/Cypress/EZ-USB FX3 SDK/1.3/library/c_sharp/lib/CyUSB.dll'
```

可通过 `-QtRoot`、`-MingwRoot`、`-CMakeExe`、`-NinjaRoot`、`-CscExe` 覆盖工具路径。脚本生成 `build/` 与 `dist/`，默认部署运行库；`-SkipDeploy` 仅适用于已有运行依赖的开发环境。

运行 `$out/dist/VaporMonitor.exe`。交付运行包时复制整个 `dist`，不能只复制 EXE。打开程序不会自动开启 WMS；连接前关闭其他占用 USB 的软件。

## 离线验证

```powershell
$env:PATH = 'C:/Qt/6.11.2/mingw_64/bin;C:/Qt/Tools/mingw1310_64/bin;' + $env:PATH
& 'C:/Qt/Tools/CMake_64/bin/ctest.exe' --test-dir "$out/build" --output-on-failure
# 可选：仅用于原 2026-09-30 固定黄金采集文件（测试含固定帧数/数值断言）
& "$out/build/protocol_test.exe" 'E:/Documents/Vapor_Lc_App_Test/adc_s3_adjusted_20260930/capture/bulk_in.bin'
python -B Docs/protocol/examples/test_vlp_reference.py
```

CTest 包含 protocol/ui/plot，工作目录在外部构建目录，不访问硬件。未提供历史文件时会明确输出 `CAPTURE_SKIPPED`；显式指定不存在的文件会失败。`control_smoke`、`tests/bridge_probe.py` 和主程序 `--smoke-live` 会访问设备，部分会改变采集/输出，**不属于离线回归**。

## 电压与数据单位

WMS 锯齿和正弦幅度为标称峰值 V（Vpp 为其 2 倍），偏置为直流 V。按 DAC ±10 V 参考换算，界面除以 10 后下发归一化 Q1.31。默认 0.5 V/0.1 V 等价于旧界面的 0.05/0.01；`|偏置|+两个峰值≤9.5 V`。CON27/CON28 接中间 3–4、高阻负载时接口增益约 1，未校准时不能把设置值当实测电压。

ADC 电压换算绑定当前板卡前端及 RLY5 改线，详见交接文档；不能直接套用于未改线板卡。H1/H2 为数字幅值，H2 峰值尚未标定为气体浓度。BIN 保存 USB 原始流，见 [存储格式](../../Docs/protocol/BIN_STORAGE_FORMAT_V1.0.md)。

`protocol_test` 的采集文件参数用于指定上述固定黄金文件的实际存放路径，不接受任意数据作为等价黄金值。其他 BIN 可用 GUI 回放或 `Docs/protocol/examples/read_bin.py` 分析。USB 只读探针需显式传入 `--bridge <外部dist/VaporUsbBridge.exe> --output <外部新目录>`。
