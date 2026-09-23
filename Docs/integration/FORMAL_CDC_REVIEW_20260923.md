# 正式工程 CDC 审查（2026-09-23）

结论：本轮正式工程布局布线结果的跨时钟路径**按实际结构审查通过**，没有新增未审查的规则、时钟对或端点。工具报告仍有 136 条 Critical，不能描述为“CDC 零 Critical”。本结论覆盖当前源码和本轮 routed.dcp，不自动豁免后续版本。

## 逐端点结果

当前 CDC 报告共 146 条；逐条比较规则、严重性、源/目标时钟、CDC 类型、同步级数、时序例外和源/目标引脚，146/146 与已独立审查的 2026-09-17 集成基线完全一致。没有仅按数量接受警告。

| 类型 | 数量 | 本轮结构核对 |
|---|---:|---|
| CDC-10 Critical | 4 | ADC monitor/queue/capture 和 GPIF 的异步复位请求；实际接收域分别保留 3/2/3/16 级 ASYNC_REG 同步释放链，逐级直接连接且内部路径仍受时序检查 |
| CDC-13 Critical | 132 | ADC u_word_cdc FIFO 分布式 RAM 到 u_capture_fifo RAM 的数据路径；每条实际 primitive、引脚、fanin 和时钟均符合预审结构，均保留 20 ns datapath-only 上界，最小余量 18.043 ns |
| CDC-6 Warning | 2 | ADC FIFO 两个 Gray 指针总线；两个方向各 9 位均核对两级 ASYNC_REG 与直接连接，含综合合并为 binary MSB 的第 9 位 |
| CDC-3 Info | 8 | 工具识别的一位 ASYNC_REG 同步器；报告全字段与已审基线完全一致 |

FIFO 数据按有效性和指针所有权传递，不逐数据位加同步器。源 FIFO 保留注册 Gray 指针、双级指针同步、注册 empty/full 与 valid/ready 门控；接收侧要求 word_valid 和 tag_valid 同时有效。本次静态核对的 8 个相关 RTL 源文件与已审集成输入逐字节相同。

另外独立核对了 PTB210、HMP、AI8、EPSILON 及 TFA 的 HF/LF 共六条 UART 接收链：实际原始物理端口进入第一级，两级均为 ASYNC_REG，第二级由第一级直接驱动，内部路径受时序检查。共享 RS485 的 HMP/AI8 分别同步同一原始 RX，没有在同步器前加入所有权选择器。HMP 的结构检查不表示 HMP 已经实板验收。

## 实际布线和约束

导出的 14 条 bus-skew 约束与集成基线逐条一致，全部满足 10 ns 上界，最小余量 8.539 ns。ADC read pointer skew 为 0.733 ns（余量 9.267 ns），write pointer 为 0.578 ns（余量 9.422 ns）。两方向约束均覆盖全部 9 位。

完整实现结果为 WNS +0.331 ns、WHS +0.005 ns；check_timing 的 unconstrained internal endpoints 和 missing input delays 都为 0。唯一无输出延迟项是转发时钟 FPGA_GPIF_PCLK。DRC 有 920 条 Warning，无 Critical Warning/Error；110 项原构建输入哈希校验一致。当前检查器读入最终 DCP，未修改设计、约束或 checkpoint，正常退出并打印：

```text
FORMAL_CDC_NETLIST_REVIEW_PASS memory_entries=132 reset_entries=4
```

## 可复现审查

正式 `fpga/scripts` 保存三个小型文件：`review_cdc.py`、`review_cdc_netlist.tcl`、`cdc_endpoint_baseline.json`。基线 JSON 保存全部 146 条完整比较元组及原报告哈希，不保存庞大 Vivado 工程。脚本没有本机 Test 绝对路径。以下命令中的构建目录应替换为自己的外部输出路径，在仓库根执行：

```powershell
$cdcBuild = 'E:/Documents/Vapor_Lc_App_Test/formal_bit_build'
$cdcRepo = (Get-Location).Path
python -B fpga/scripts/review_cdc.py --baseline fpga/scripts/cdc_endpoint_baseline.json --current "$cdcBuild/full_build/cdc.rpt" --output "$cdcBuild/cdc_review"
if ($LASTEXITCODE -ne 0) { throw 'CDC endpoint inventory requires review' }
Push-Location "$cdcBuild/cdc_review"
try {
    vivado -mode batch -nojournal -log "$cdcBuild/cdc_review/netlist.log" -source "$cdcRepo/fpga/scripts/review_cdc_netlist.tcl" -tclargs "$cdcBuild/full_build/routed.dcp" "$cdcBuild/cdc_review"
    if ($LASTEXITCODE -ne 0) { throw 'CDC netlist structure check failed' }
} finally { Pop-Location }
```

parser 拒绝缺失报告、任何元组变化和仓库内输出；已验证“Critical 总数不变但端点改变”会失败。Tcl 随后检查实际端点结构，导出 bus-skew 和 resolved XDC；审查者还须核对当前 bus-skew 数值、约束覆盖、源码更改与完整实现结果，不能只凭端点清单一致就批准新 RTL。主构建包装器的自动 pass 也不代替此项 CDC 结构审查。

本机本轮证据保存在 `E:/Documents/Vapor_Lc_App_Test/formal_merge_20260923/cdc_review`，总表为 `FINAL_CDC_REVIEW.json`；该目录不提交生成报告。用于识别结果的 SHA256：

| 对象 | SHA256 |
|---|---|
| 集成基线 cdc.rpt | `7600cf7018b242e08eb8c455428947b4d3908115e7e5eba3b473c6a25847ef97` |
| 本轮 cdc.rpt | `42973e610a8edadf706bbf504092c076ed87da63d3fc44e42333326bfb5343d8` |
| 本轮 routed.dcp | `4ccd8590491303d2032ee22e9d18d8fe801e19c72d33e8657e2628c87835254e` |

三个审查文件在完整构建退出之后才加入正式工程，原构建 manifest 不包含这些新增审查工具；它们属于构建后补充记录，不应冒充原始综合输入。未进行新实板操作，也没有扩大既有 RAM/PING/传感器测试的硬件验收范围。
