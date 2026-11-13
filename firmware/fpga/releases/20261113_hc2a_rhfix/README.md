# HC2A RH 修正版正式归档

归档日期：2026-11-13。原始构建：2026-10-28；最近使用该镜像的设备实测：2026-11-12。本次复制既有已验证镜像，没有重新生成或改写 BIT。

| 项目 | 值 |
|---|---|
| 器件 | Xilinx XCKU11P-2FFVA1156I |
| 工具 | Vivado 2020.2 |
| BIT | `vapor_lidar_hc2a_gpio_rhfix_20261028.bit` |
| 大小 | 23,581,028 bytes |
| SHA256 | `e5d0c1f691fd7a47cf83c108612f51d518f886ca57e7ca9a363f69c619c2f8a6` |
| HC2A ID / 诊断签名 | `0x00410106` / `0x48434432`（HCD2） |
| 原始实现 WNS / WHS | +0.079 ns / +0.003 ns |

源镜像在外部测试目录 `hc2a_gpio_20261028_01/rh_case_fix_01/deliverables/`。配套 `repo/` 的 128 个构建输入与同步后 V2 逐字节一致，覆盖 RTL、头文件、约束和构建脚本。`source_inputs.json` 保留当时输入的原始字节 SHA256；`source_inputs_lf.json` 为相同文本统一 LF 后的 SHA256，供 Windows Git 自动换行后的检出核验。`release.json` 记录来源和验证摘要。

在仓库根目录运行：

```powershell
python -B firmware/fpga/verify_release.py
Get-FileHash firmware/fpga/releases/20261113_hc2a_rhfix/vapor_lidar_hc2a_gpio_rhfix_20261028.bit -Algorithm SHA256
```

原构建执行全新 RTL 综合，使用已审查 HCD1 routed DCP 作增量物理参考，并非全新布局。最终布线、setup/hold、DRC、check_timing、脉宽及 ADC/DAC pad 检查通过；CDC 端点与基线一致并完成结构复核。存在 76 条增量流程工具 Critical Warning，详见[最新说明](../../../../Docs/LOWER_COMPUTER_RELEASE_20261113.md)，不宣称零工具告警。

该镜像通过 SRAM 临时加载使用；未将此版写入 FPGA Flash，断电后不能假定自动启动此版。归档不执行硬件下载、Flash/EEPROM 烧写、采集启用或运动控制。
