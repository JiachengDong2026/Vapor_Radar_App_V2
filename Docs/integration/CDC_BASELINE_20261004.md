# 双低速ADC版本CDC基线归档

2026-10-04将正式检查基线从历史ADC3660版本更新为已上板双AD4630版本。该更新仅改变报告比对参考，不新增false-path、不隐藏Critical，也不放宽硬件约束。

来源报告：`E:/Documents/Vapor_Lc_App_Test/dlia_precision_20261002/build/full_build/cdc.rpt`，SHA256 `f0396544490bd6c36478c9e4a7c82b80a180431a3100d14dc157926b29c2f102`。

对应DCP SHA256：`b7e24e849caf99ee7c7ce5531c0619106e2dbe1381467d0c8fbe3b3310bc841b`。来源网表复核日志在该测试目录 `cdc_review/netlist_review.log`，成功标记 `FORMAL_CDC_NETLIST_REVIEW_PASS memory_entries=0 reset_entries=1`。

| 项目 | 来源→目标 | 复核 |
|---|---|---|
| CDC-10 Critical | power_count_reg[7]/C → u_clock/gpif_release_reg[0]/CLR | board25→gpif_raw；16级复位释放同步链均为ASYNC_REG，级间直接连接、有时序检查且slack非负 |
| CDC-3 Info | FPGA_GPIF_CTL[4] → link_sync_reg[0]/D | gpif_pclk→sys_raw；2级同步 |

两项均与2026-09-30已复核报告精确匹配。旧ADC3660异步Gray跨域在当前双AD4630系统时钟方案中不存在。UART端口两级同步和12条bus-skew约束满足情况参见来源 `cdc_review/REPORT.md`。这不是宣称CDC报告零告警，也不能替代未来修改后的网表复核。

本次正式JSON与上述已验证报告再次比对，结果 `exact_inventory_match`、2/2。输出位于外部 `formal_sync_20261004/cdc_review`；未来重新实现后仍应对新的cdc.rpt及routed.dcp执行端点比对和网表复核。
