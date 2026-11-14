> 2026-11-15：当前测距设备为[SDFM300](../../Docs/integration/sensors/SDFM300.md)，0x0045距离毫米TLV兼容；0x6500 ID=0x00450200，旧模式/命令地址已撤回。历史BIT/板测名称仅代表当时设备。

# FPGA 正式发布文件

当前版本：[2026-11-13 HC2A RH 修正版](releases/20261113_hc2a_rhfix/README.md)。

本目录只保存明确要求归档的正式 BIT、校验和及精简来源清单。可维护源码位于 `fpga/`，最新使用与验证说明见 [下位机说明](../../Docs/LOWER_COMPUTER_RELEASE_20261113.md)。

- 发布目录按归档日期与功能命名；BIT 保留原始构建日期，避免把归档日期误认为重新综合日期。
- 每个 BIT 必须有 SHA256、对应源码输入清单、构建及实板验证边界。
- 不放 Vivado 工程、DCP、缓存、波形、完整报告、临时诊断镜像或原始采集数据；这些文件保留在外部 `Vapor_Lc_App_Test`。
- 本目录是 `.gitignore` 中通用 `*.bit` 规则的精确例外。新增发布需显式增加对应路径，不能放开所有构建产物。
- FPGA BIT 与 `firmware/fx3` 的 FX3 USB 桥固件是不同程序，不能互相替代。
