# 2026-11-23 PPS / SOS / 启动观测 BIT

构建日期2026-11-23，归档日期2026-11-25；工具Vivado 2020.2，器件XCKU11P-2FFVA1156I。标签`fpga-20261123-start-outputs`，分支`codex/release-20261123-start-outputs`。

镜像包含两路DLIA 2～8阶SOS及截止频率配置、PPS单次WMS/DLIA扫描、CON11-12/14/16三路3.3V/10us启动观测，以及DLIA参考流水时序修复。功能、接线、验证及限制见[本版说明](../../../../Docs/LOWER_COMPUTER_RELEASE_20261123.md)。

| 项目 | 值 |
|---|---|
| BIT | [vapor_lidar_start_outputs_20261123.bit](vapor_lidar_start_outputs_20261123.bit) |
| 大小 | 23581028字节 |
| SHA256 | `21f786684b501f91d7254f68e9a207aeaecc0ce4c8d9d44ba176177406346b4a` |
| 建立时间 | WNS +0.009ns / TNS 0，失败端点0 |
| 保持时间 | WHS报告值0.000ns / THS 0，失败端点0 |
| 仿真 | 116/116项通过 |
| 上板状态 | 未下载、未烧录、未进行4.11实测 |

本目录BIT从已签核产物逐字节复制，未重写。`source_inputs.json`保留131项原始构建输入SHA256，`source_inputs_lf.json`只允许CRLF/LF差异；`regression_sources_lf.json`与`regression_results.json`绑定250项回归源和116项结果；`release.json`记录摘要和原始外部证据哈希。

在仓库根目录执行（仅校验文件，不操作硬件）：

```powershell
python -B firmware/fpga/releases/20261123_start_outputs/verify.py
```

请在本标签或版本分支核验。本BIT不包含GitHub main后续`0bfb750`的DLIA丢帧周期恢复修复；不同源码不能沿用本镜像的时序签核。原始报告/DCP保存在外部Test目录，仓库只保存镜像和校验资料。
