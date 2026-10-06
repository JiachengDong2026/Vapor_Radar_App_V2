# FX3 GP01 固件

> 2026-10-04归档更新：本目录固件基线及重建数据不变。当前板已改为128KiB EEPROM启动，FPGA也已写入独立U2 Flash；2026-10-03完成一次完整断电自启动及USB采集验证，详见 [最新下位机同步记录](../../Docs/MERGE_MANIFEST_20261004.md)。下文的RAM加载、PMODE=Z11及“尚未验收”描述属于2026-09-23历史验证条件，不代表当前板卡仍需每次下载。曾出现一次首次冷启动失败，具体根因仍未确认。

本目录接入 2026-09-18 已上板的 GP01 固件。保留 32-bit GPIF、`GPIF_BUS_CONFIG=0x10AC`、50 MHz 外部 PCLK、USB OUT `0x02` / IN `0x86`、线程 3/0、每方向 4 个 16 KiB AUTO_SIGNAL DMA 缓冲和 B0/B1 只读诊断。禁止用旧集成版的 `0x10AF` 替换它。接口说明见 `GPIF_MAPPING.md`。

已验证的是 **RAM 加载**后的 PING 往返和一次 154 帧 CRC 校验；EEPROM 启动留待后续验证。持续高速、长期无丢帧及反复重连尚未验收。本次正式目录重编 IMG 与该实板版本逐字节相同；脚本不烧录、不访问 USB。

## 源码与许可

上板固件实质派生自 Cypress 同步 Slave FIFO 示例。`LICENSE-CYPRESS.txt` 保留其原始许可；该许可的 1.1、1.3、1.4 和 5.2 限制源码使用/披露，不能把整个 SDK 或官方示例当作开源代码公开分发。

因此本仓库只保存项目的 GP01 修改数据 `gp01_changes.json`、自写重建器、测试和来源哈希。修改数据使用字节偏移、删除长度及新增内容，不包含被删除的官方源码或不变上下文。构建时从用户自己取得、获许可使用的外部示例读取完整代码，在外部输出目录生成保留官方许可头的四个源文件，再核对其 SHA256 与上板源完全一致。官方 SDK、示例主体、ThreadX/FX3 库、工具链和构建产物不入库。项目修改不会扩大 Cypress 原始许可赋予的权利。

`SOURCE_PROVENANCE.json` 固定上板源/IMG 与官方状态表哈希；`SDK_PROVENANCE.json` 固定 194 项 SDK 1.3.1 依赖。来源记录用于验证版本，不代表第三方镜像授予额外分发许可。

## 从干净克隆构建（PowerShell）

需要 Python 3、ARM GCC/binutils、host GCC，以及外部 FX3 SDK **1.3.1 源码包**。2026-09-23 验证使用 Vitis 2020.2 所带 ARM GCC 9.2.0 与 Vivado 2020.2 所带 MinGW GCC 6.2.0。其他编译器未保证生成相同 IMG；变更工具链需重新验证。

1. 从你有权使用的 SDK 安装包/存档准备外部 SDK。历史来源是 [nickdademo/cypress-fx3-sdk-linux](https://github.com/nickdademo/cypress-fx3-sdk-linux)，固定提交 `b142a1612d874e259f66cf171bf58c596bfe9dba`；完整克隆到仓库以外并检出此提交可提供下列目录。若通过 Git 取得，Windows 须设置 `-c core.autocrlf=false`，避免更改许可源文件字节/哈希。构建会核对所有依赖，错误版本会明确失败。
2. 外部 SDK 根目录应含 `FX3_SDK_1_3_1_SRC/sdk/firmware/{src,include}`、`firmware/common`、`firmware/u3p_firmware/inc`、`util/elf2img` 和 `license/license.txt`；示例目录含 `cyfxslfifosync.c`、`cyfxslfifousbdscr.c`、`cyfxslfifosync.h`、`cyfxgpif_syncsf.h`。完整同版本 SDK 的示例目录为 `firmware/slavefifo_examples/slfifosync`。两者也可来自分别保存的同版本目录。
3. 在正式仓库根目录配置本机路径并执行：

```powershell
$env:VAPOR_FX3_SDK = 'D:/Dependencies/cypress-fx3-sdk-linux'
$env:VAPOR_FX3_REFERENCE = "$env:VAPOR_FX3_SDK/firmware/slavefifo_examples/slfifosync"
$env:VAPOR_FX3_OUTPUT = 'D:/Builds/vapor-fx3-gp01'
$env:VAPOR_ARM_GCC = 'D:/Software/Vivado/Vitis/2020.2/gnu/aarch32/nt/gcc-arm-none-eabi/bin/arm-none-eabi-gcc.exe'
$env:VAPOR_HOST_GCC = 'D:/Software/Vivado/Vivado/2020.2/tps/mingw/6.2.0/win64.o/nt/bin/gcc.exe'
python -B firmware/fx3/build.py
python -B firmware/fx3/run_tests.py
```

以上依赖路径只是示例，应替换为本机目录；脚本没有 Test 工程绝对路径或隐式 SDK 默认值。也可使用 `--sdk`、`--reference`、`--output-dir`、`--arm-gcc`、`--host-gcc`。GCC 未指定时从 PATH 查找。所有生成源、对象、ELF、IMG、map、环境和哈希报告位于 `VAPOR_FX3_OUTPUT`，必须在仓库和依赖目录之外。`python -B` 避免在正式目录产生 Python 缓存。

本机已安装的 EZ-USB SDK 1.3.5 不会被自动选用：其 `fw_lib/1_3_1` 并不等于上述经过固定的源码重编依赖；直接切换库/启动文件将成为另一次固件迁移。

## 检查结果和产物

成功标记为 `FX3_GP01_SOURCE_RECONSTRUCTION_PASS`、`FX3_SDK_PROVENANCE_PASS`、`VAPOR_FX3_ARM_BUILD_PASS`、`FX3_FIRMWARE_API_REGRESSION_PASS`、`FX3_VENDOR_STATE_GRAPH_UNCHANGED_PASS`、`FX3_IMG_ELF_EQUIVALENCE_PASS`。mock 覆盖 SS/HS/FS、端点/DMA、复位/断连、clear-halt、诊断长度/方向及 flag 配置；它不模拟真实引脚时序。IMG 检查覆盖 ELF ARM 类型、加载段、BSS 零初始化、入口和 Cypress 累加校验和。

RAM 镜像是输出目录的 `vapor_fx3.img`，93724 字节；已上板基线 SHA256：`e705c3032aece44c2ef1890e45c9f6b5d5aa31fc6facc8ab02ddb2847e043dd5`。ELF 的调试路径随构建位置变化，其哈希可变而 IMG 保持相同。旧 SDK 在 GCC 9 下的 implicit-int / `__nop` 警告及 `.ARM.exidx` 的 sh_link 警告沿用上板构建，未在此次迁入中修改 SDK。

## RAM 加载与诊断

先加载配套正式 FPGA BIT，等待 FX3 BootLoader，再用 Cypress Control Center 的 Program → FX3 → RAM 加载 IMG。当前 PMODE=Z11；断电后 FPGA 和 FX3 都需重新加载。本构建脚本不执行这些硬件操作。

应用 USB 标识仍为开发用 `04B4:00F1`。Control IN 的 Vendor/Device 请求 `0xB1`，`wValue=wIndex=0`，读 32 字节；前 8 字节应为 `47 50 30 31 AC 10 00 00`（GP01、0x10AC）。B0/B1 返回 8 个小端 uint32，最多 32 字节，不是原子快照，也不会清错或复位 GPIF。

| 偏移 | B0 | B1 |
|---|---|---|
| 0 | mapping 0x00010001 | GP01 0x31305047 |
| 4 | active | BUS_CONFIG |
| 8 | PIB errors | WAVEFORM_CTRL_STAT |
| 12 | DMA errors | GPIF_STATUS |
| 16 | 最近错误 | 当前软件阶段 |
| 20 | OUT 生产缓冲数 | 最近 PIB 错误时阶段 |
| 24 | IN 生产缓冲数 | SMStart 前 PIB 错误数 |
| 28 | DMA/watermark 0x4000000C | SMStart 后 PIB 错误数 |

阶段值：0 初始、1 Load 中、2 Load 完成、3 SMStart 中、4 启动成功、5 停止中/已停止。OUT 计数增加不能单独证明 FPGA 收到并解析命令，需核对完整 PING 应答和 CRC。
