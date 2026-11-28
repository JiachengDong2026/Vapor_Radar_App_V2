# AI-8288 扫描固件验收记录 · 2026-11-28

## 版本及接口

422Laptop3 (`LAPTOP-422-03`) 的固件 `origin/HEAD` 指向 `main`。本轮从 `0ed60bd34a21bfab251bc32b48af91ea40903ac3` 开始，在 `Winter-And-You-Gone/ai8-scan-board-verification` 交付。为保留该机程序发布目录中 `dab6d5d` 版本的参数邮箱，将位于基线之后的 `45380ab`、`dab6d5d` 快进整合。扫描修改 `1fd025e`，`7662ec4` 修正 Vivado 对含空格工作树路径的文件列表解析。最终实现输入版本 `11864af624d715af4ed367877942878e6a77ea0e` 同时覆盖 USB FIFO 双向 Gray 同步器的保持修复。原主工作树保留。

上位机依据为 VaporView `5c24158b0deb0c35a0e534396ee982caa45997c5` 的 `docs/fpga_pending_firmware_adaptation.md`。与此次 fetch 后 `origin/main` 的文件 blob 相同 (`a9faa1e42e1adec2135d168f9a0b23268fabd8ff`)。宇电 AI-8 系列手册第 7 节（印刷页 38–44）给出 RS485 通讯、PV/SP 等地址、合并状态字的奇偶通道位置及写入限制。FPGA 的扫描周期和缓存接口定义见[扫描接口修订](AI8_SCAN_CONTRACT_20261114.md)，参数事务地址范围及独立读回规则见[参数邮箱](AI8_PARAMETERS_20261116.md)。

## 验收结果

| 项目 | 结果与证据 |
|---|---|
| 静态检查和公共模块 | `check_baseline.py` 输出 `BASELINE_STATIC_CHECK_PASS`。Vivado 2025.1 build 6140274，公共 behavioral 仿真、综合和报告入口输出 `PREDEV_COMMON_V12_VIVADO_CHECK_DONE`。 |
| 全量回归 | `alltests/results.json` 中 119/119 项 XSim PASS。最终加强的 `tb_ai8_scan` 在 `window/` 独立重跑 PASS。 |
| 复位、能力、主机写回 | XSim `tb_ai8_scan` 在首次配置写入前读取 `0x6668=1`、`0x6604=0`、`0x66FC=0x0F`。在显式单通道模式执行 AI8 软复位后再读 `1`，随后禁用态写 `1` 并读回。 |
| 默认扫描、周期、缓存 | `tb_ai8_scan` 跳过 `0x6668` 写入，2 MHz 逻辑时钟、`0x662C=1 ms`，连续两轮 CH1–CH8。检查实际 FC03 地址、schema3 通道号、CH1 完成间隔 2000–2010 拍。第二轮 CH4 注入超时，检查缓存及后续推进。经 `0x6698` 逐路选取 `0x66A0..0x66B4`，与同一条记录中的质量、PV/SP、SV/OP、状态和 64 位时间戳比对。 |
| 扫描交错命令 | XSim `tb_ai8_parameters` 验证 CH5 参数读写、独立读回、不匹配、互斥、超时及取消。`tb_ai8_parameter_uart` 验证 UART/Modbus。`tb_ai8_scan` 在扫完 CH8 的间隙定向设 CH7、独立读回后检查下一路为 CH1。 |
| 单通道 | `tb_ai8_scan` 验证显式单通道下 `0x661C=8` 后首个 SP 地址为 7。旧板验收要求使用未声明 Ai8Scan 的镜像及上位机实际命令记录，待取得相应设备。 |
| 现场 | 只读 JTAG 清点得到唯一电缆 `13620207920cf6`、唯一器件 `xcku11p_0`、IDCODE `04A4E093`。Vivado 目标 `xcku11p-ffva1156-2-i`。Windows 看到了 Xilinx USB Cable，但 GP01 FX3 `04B4:00F1` 的 WinUSB 接口枚举为 0。PCB 修订、当前 SRAM 镜像、输出及 AI-8 型号、接线和实测温度待核实。 |

## 现场续验

按现场负责人更正的顺序，在 422Laptop3 接好数据 USB，先经 JTAG 将签核 BIT 加载至 SRAM。确认 DONE/EOS 后枚举 FX3 并独占接口，先读 `0x6668`，然后读取能力、扫描配置、可读设温、输出及采集状态。首轮跳过主机模式写入，留存多轮 schema3 原帧，按通道、计数及完成时间戳与寄存器窗口配对。选安全的已接通道做可恢复的设温和参数页读写，核对独立读回并恢复所有暂改项。另测 AI8 软复位和主机写 `1` 后读回。SRAM 重配与实际断电启动分别记录。上表及原始枚举日志记录的是早期只读清点。

外部原始证据位于 `D:/Project/Test/ai8_boot_20261128/`。`inventory.log`、`usb-before.json`、`fx3-before.txt` 记录现场枚举，`window/` 包含最终缓存窗口及交错设温测试，`common3/` 保存公共报告。历史发布目录中旧 BIT 的哈希不能用作本次实现或实板的标识。

## 整机签核与 BIT

- `build4/build_result.json` 记录 `FULL_SYSTEM_BUILD_PASS`、退出码 0、构建期间输入变动 0 项。最终 282705/282705 条网线全部布通，routing errors 0。WNS +0.019 ns，TNS 0，WHS +0.010 ns，THS 0。DAC 管脚最小裕量 7.283 ns，AD4630 管脚最小裕量 3.585 ns。
- CDC 端点与项目基线精确匹配 2/2，含既有 CDC-10 Critical 复位路径和一条 CDC-3 Info。最终布线网表复核输出 `FORMAL_CDC_NETLIST_REVIEW_PASS memory_entries=0 reset_entries=1`。12 项 bus-skew 检查最小裕量 +7.991 ns。
- BIT 位于 `D:/Project/Test/ai8_boot_20261128/build4/full_build/vapor_lidar_top.bit`，SHA-256 为 `bb7a14bbfad71ea7f0ead787b9cee27ae04a30966186969814b26ca684034882`。首次实现 `build3` 在反向 FIFO 保持路径处停止，原始失败报告留存。修订脚本按 TX/RX 的源、目的时钟校验两个方向的 Gray 指针及同步级，本轮 `build4` 从源码重新综合、布局、布线并通过原有门槛。

## 现场续验结果（2026-11-28 北京时间 23:51–23:56）

**实板阻塞在 FPGA 配置启动阶段。** 负责人已连接 FX3 数据线。422Laptop3 上两次向目标 SRAM 下载签核 BIT，Vivado 两次均报 `Labtools 27-3165 End of startup status: LOW`。

| 核对项 | 实测及证据 |
|---|---|
| 交付标识 | 远端交付分支测前为 `04e369b1`。复算 build4 BIT 的 SHA-256 与上节一致。`source_inputs.json` 的 134 项输入逐项与 `11864af6` 对比均匹配（允许 Git 文本行尾转换）。原产物直接使用，基线静态检查再次通过。 |
| JTAG | Vivado 2025.1，电缆 `13620207920cf6`，单器件 `xcku11p_0`，IDCODE `04A4E093`。默认 6 MHz 下载报 EOS LOW。随后硬件读回 `CONFIG_STATUS=0x10801904`。3 MHz 重试后读回 `0x1080190C`，`BOOT_STATUS=0x00000000`。两次状态均为 EOS=0、内部 DONE=0、DONE pin=0、INIT_B pin=1、CRC/IDCODE/security/bad-packet 错误位均为 0。两次读数间 DCI_MATCH 由 0 变为 1。 |
| USB | 3 MHz 下载结束后 Windows 在场 USB 设备中可见 Xilinx JTAG 和 CH340，未出现 `04B4:00F1`。GP01 WinUSB 接口 GUID `{F8F79424-22D5-4531-AEAE-8EBE7CE62A3D}` 的 enabled 枚举为空。系统留有两条 FX3 历史记录，均为 `IsPresent=False`、驱动 `WinUSB/oem48.inf`。当前无法发起 GP01 控制传输或 VLP1 数据交换。 |
| 恢复镜像与退出状态 | 桌面发布指针指向 `2026-11-26_PPS_AI8参数_dab6d5d`，本次复算恢复 BIT 的 SHA-256 为 `870364e37d6a4471570289e3a8518edd88a4af6f26da1b33833b5afb61c6adbb`。同机既有 `D:/Project/FPGA_Programmer/logs/20261128_234816_675123/session.log` 显示该 BIT 在本次操作前也报 EOS LOW。23:56:08 下载进程退出，JTAG 已释放，最后目标配置未完成，无已确认运行的 SRAM 镜像。整个续验仅向 SRAM 尝试下载，Flash 和 FX3 EEPROM 均未写入。 |

实板首次模式读数、能力及采集/输出寄存器、原设温、连续八路帧、通道缓存/时间戳、整轮周期、显式模式写回、软复位及交错命令均未取得。没有发出主机测量、设温、输出或参数写命令，无法确认各路传感器的接线或温度。本次只识别到上述一台 JTAG 目标，旧板兼容性仍待具备相应设备时验证。

现场下一步是在负载安全时给 FPGA 主板完整断电再上电，确认主供电及配置跳线与曾成功的设置一致，随后重试同一 BIT 并读 DONE/EOS。原始证据位于 `D:/Project/Test/ai8_boot_20261128/board_2350/`，含 `hashes.json`、`source_check.json`、`program.log`、`retry3m.log`、`usb-post-retry.json`、`driver.json` 及 `fx3-after.txt`。
