# AI8 八路扫描接口方案（2026-11-14）

状态：源码已实现并通过相关 behavioral 仿真；新 BIT 已完成同轮重新签核并生成，尚未实板验收（见末节及 AI8_BUILD_QUALIFICATION_20261114.md）。现有 HCD2 BIT 仍为 0x29；本次源码能力为 0x2B。不得把源码能力用于判断当前已加载的旧镜像。

沿用 VaporView 现有 Ai8Scan/schema3 接口，不恢复通用参数事务或 RD105。

## 兼容接口

- GET_CAPABILITIES 扩展 word 由 0x29 改为 0x2B，仅增加 bit1；bit2/bit4 保持 0。
- 0x6668 SCAN_ENABLE：0/1，默认 0，只允许禁用态写。0 保留 0x661C 及 schema2；1 自动 CH1→CH8，成功和失败均推进，不能由主机停启模拟。
- 0x662C 表示完成一整轮后的等待毫秒数，刷新时间还包括串口事务及重试时间。
- schema3 每条包含 U32 TLV 0x0468 通道号 1..8；各路实际完成七次 FC03 后产生记录。失败也携带通道号及传输错误，不能上传其他路的旧值作为该路数据。
- 0x666C SET_CHANNEL：0 沿用 0x661C，1..8 指定设温通道；提交时锁存目标，pending 时禁止修改。写 ACK 后必须独立读回，扫描游标不能影响命令目标。此功能仅支持用户明确请求的原有设温操作。
- 0x6698 CACHE_CHANNEL：1..8，默认 1；0x66FC feature=0x0B（扫描、通道TLV、写后读回），参数事务位保持 0。

## 逐通道缓存和有效性

沿用历史缓存：0x66A0 bit0 通信在线、bit1 已收到结果、bits5:2 传输错误、bits13:6 异常码；0x66A4 为 SP/PV；0x66A8 为 SV/OP；0x66AC 为 host/control/alarm；0x66B0/B4 为最近结果 tick。增加 0x66B8 本路成功计数、0x66BC 本路失败计数，按 32 位回绕；复位清零。缓存选择只影响读窗口。

成功表示完整通信快照，不等于测量健康。失败结果在线位清零，数据无效；保留历史数据时不得标成当前测量。每路 schema3 SAMPLE_COUNTER 使用本路成功计数。扫描中仍保留模块聚合错误和聚合计数用于诊断。

alarm.bit0 为本路输入错误/超量程；bits1..4 为本路 HA/LA/dHA/dLA。host.bit8 为系统故障，host.bit9 为全局报警。这三者必须独立展示。测量有效要求成功快照、本路输入错误位为 0、系统故障位为 0；全局报警本身不能推导该路输入故障。阈值报警仍保留，不能用有效性代替报警。ERROR 帧标志保留聚合报警含义，上位机不能仅凭它将八路输入全部判坏。

不修改仪表 In/InP、输出参数或设温。两路实际接线编号尚未确认，其余通道的真实报警必须保留。

## DLIA 调查边界

已读代码显示 ADC 在 CNV 时把 WMS phase_valid 锁存到 capture_tag[192]，member1_adc_dila 将标签连同数据传入 DLIA。dila_core 在接受样本时对非零 sample_flags 或 WMS 模式下无效 phase 标签锁存 0x80 并标记 partial。WMS 未运行时 phase_valid 为 0；因此启动顺序是需要回归验证的触发条件，尚不能宣称现场就是此原因。不得放宽饱和、相位有效或完整周期判定。

## 验证和交付限制

覆盖真实八路地址及奇偶报警字节、六路报警不污染两路有效性、单路超时/CRC/异常后继续扫描、背压、复位、单通道兼容、设温目标锁存及独立读回。DLIA 覆盖无效相位、饱和、启动时序和完整周期边界。之后执行静态检查、相关 behavioral 仿真、综合/时序和 BIT 实现；生成物放仓库外 Test，禁止烧录。本方案不继承旧 BIT 实板验收结论。


2026-11-14 验证记录：

- `check_baseline.py`：BASELINE_STATIC_CHECK_PASS（使用指定 runtime Python，带 -B）。
- Vivado 2025.1：tb_ai8_scan、tb_ai8_poll、tb_ai8_sample_epoch、tb_ai8_setpoint、tb_ai8_shared_bus、tb_ai8_cfg_cache、tb_dila_quality、tb_dila_core 通过。
- 新扫描测试在 Modbus 事务完成接口注入独立响应，检查八路七次真实地址计算、独立 PV/报警/计数、失败清零并继续、schema3 通道 TLV、扫描期间设温和独立读回目标；UART/CRC/共享仲裁由既有针脚级回归覆盖。新扫描测试不等同于八路实物测试。
- 测试产物：`D:/Project/Test/ai8_scan_20261114_a`、`ai8_scan_20261114_c`、`dlia_quality_20261114_a`。b 轮扫描 testbench 曾在提交已被接受后检查 BUSY，修正为接受前检查后 c 轮通过。
- 公共综合与整机实现均已尝试，分别见 `D:/Project/Test/ai8_common_20261114_a/common.log` 和 `D:/Project/Test/ai8_full_20261114_a/build.log`。均因目标 part 不存在停止。已执行 `get_parts -quiet *ku11*` 返回空，当前安装有 876 个其他 part；不是 PATH 问题。尚未取得目标综合、时序、CDC 或新 BIT 结果。
- DLIA 本轮未修改质量判定。双通道新回归确认无效捕获相位（即使实时相位已有效）触发 0x80 且不输出有效点；正常标签通过；饱和触发 0x80、饱和计数和 partial。现场缺少原始样本，仍不能证明具体触发分支或硬件故障。

缓存计数在模块复位时清零，普通禁用/重新启用保留；schema2 原有全局 SAMPLE_COUNTER 语义保持不变。缓存是历史诊断，停用后不得仅凭缓存在线位认定设备当前在线。扫描传输失败的数据和报警字段为零且 online=0，表示未知，不表示仪表无报警；不能把失败记录当成清除真实报警的证据。

补充回归：tb_predev_common、tb_action_ai8、tb_hc2a_ai8_independent、tb_hc2a_ai8_tfa 均通过（b 轮各自测试结果为 PASS）。
最终扫描回归见 `D:/Project/Test/ai8_scan_20261114_d`，增加了同一报警寄存器中相邻通道不同报警字节的检查，PASS。

## 2026-11-14 Enterprise 构建续验

源提交：`a40f2edb9ac39f8754f1f430563fa00424e869a4`。使用 `D:/AMD_Enterprise/2025.1/Vivado/bin/vivado.bat`，Vivado 2025.1 build 6140274；Python 为 Codex runtime 显式路径。RTL/约束/脚本输入未改变，复用此前 12 项仿真结果。

用户补装器件包后，目标 `xcku11p-ffva1156-2-i` 已能创建工程。此前缺包阻碍已解除，但实际综合许可证 checkout 失败：`Common 17-348` 报告 Synthesis feature could not be found，随后 `Common 17-345` 报告 Synthesis/device xcku11p 无有效授权。整机综合与独立公共 smoke 综合均复现；没有更换 target 或放宽检查。

本轮外部证据目录：
- `D:/Project/Test/ai8_enterprise_full_20261114_b/build.log`、`build_result.json`：整机脚本返回 1，changed_inputs=[]，bit_sha256=null。
- `D:/Project/Test/ai8_enterprise_common_20261114_b/synth_only.log`：同一目标的公共 smoke 综合授权失败。
- 公共完整入口停留在 XSim 启动且没有结果；确认综合授权阻碍后终止本轮进程，不将此次仿真记为通过。此前公共仿真 PASS 仍有效。

结果：综合未完成，布局布线、DRC、时序、CDC 均未进入；WNS/TNS 无结果，BIT 文件和 SHA256 不存在。下一步需配置覆盖该器件和 Synthesis 的有效许可证后重新执行原构建脚本。不继承旧 BIT 实板验收，本轮未操作硬件。

## 2026-11-14 最终续验结果

许可证搜索路径已通过仅进程环境修正解决；本轮实现完成，DAC/AD4630独立checker采用更保守0.350ns预算后，同轮重新签核生成BIT。原失败build_result保持不变。详细来源、BIT路径/SHA256、时序、DRC、CDC和限制见 [AI8_BUILD_QUALIFICATION_20261114.md](AI8_BUILD_QUALIFICATION_20261114.md)。此节取代前文“尚无BIT”的当前状态描述，前文失败记录保留追溯。
