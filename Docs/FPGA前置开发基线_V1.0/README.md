# FPGA 成员开工前置开发基线 V1.0

本包分成两部分：

1. **项目负责人已完成、无需再写 RTL 的冻结工作**
   - `docs/COMMON_INTERFACE_SPEC_V1.0.md`
   - `docs/REGISTER_MAP_FREEZE_V1.0.md`
   - `docs/PREDEVELOPMENT_BASELINE_V1.0.md`
   - `rtl/common/*.vh` 公共定义

2. **交给 Codex 完成的最小 RTL/仿真任务**
   - `codex/CODEX_TASK_PREDEV_RTL_V1.0.md`

推荐使用顺序：先把 `docs/` 和 `rtl/common/*.vh` 合入项目主仓库，再把 Codex 任务书原样交给 Codex 执行。Codex 完成并通过测试后，即可让三个成员按 V1.2 任务书并行开工。
