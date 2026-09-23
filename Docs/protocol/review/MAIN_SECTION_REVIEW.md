## 主章节交叉审查问题简报

审查日期：2026-09-19。范围：`sections/00_overview.md`、`30_status_registers.md`、`40_bringup.md`。只读对照封存FPGA RTL与当前实测工具；未修改被审查章节。以下只列建议修正的问题。

### 1. [P2] 区分采集启动掩码与状态队列的流掩码

位置：`00_overview.md:57`，`40_bringup.md:30`、`:32`，`30_status_registers.md:13`。

正文正确给出六路START/STOP mask=0x7D，但随后只说“stream_mask对应位启用”，没有说明状态队列的额外门控。真实top以 `stream_mask[1]` 控制整个P2事件队列，队列内包括SYSTEM_STATUS 0x1400、MODULE_STATUS 0x1401、MOTOR_STATUS 0x1300；TIME_SYNC_EVENT由bit2控制，P0错误事件不使用source mask。若开发者将六路掩码0x7D直接用于SET_STREAM_MASK，就会清bit1，静默丢弃系统/模块状态并增加gate drop，尽管HMP确实未启用。

建议明确：0x7D是六路采集动作掩码；六路联调保留stream_mask复位全1，或专门配置时保留bit1以接收管理状态。保留stream bit1不会自行启用HMP，HMP CONTROL仍为0。不要让状态帧“约每秒产生”被理解为无条件上传。

代码依据：`integrated_20260916/lead_system/rtl/vapor_lidar_top.v:888`（P0）、`:917`（P1）、`:946`（P2）；`rtl/status_manager.v:108`、`:112`、`:116`（P2内容）；`rtl/system_registers.v:165`（复位stream_mask全1）。

### 2. [P2] 连接流程必须在PING之前启动IN读取

位置：`40_bringup.md:7`。

该段顺序是B0/B1→发送PING/GET/READ→“先开启持续IN读取，再发送启用命令”。结合正文串行命令、逐命令等待响应的约定，按此顺序实现会在首个PING等待时没有接收者，无法完成握手。虽然overview已经要求持续接收，这个可执行联调流程应当自身无歧义。

建议改为“B0/B1成功后先启动持续IN接收循环，然后串行PING、GET_CAPABILITIES和READ；整个会话中保持接收”。依据：`fx3_gpif_debug_20260918/host/SensorRun.cs:75`～`:81`在发送后不断Pump等待response；FPGA响应和数据共用IN，`rtl/cmd_decoder.v:250`须应答下游接受后才command_done。

### 3. [P3] 给SYSTEM_STATUS中的error_summary和drop字段注明快照来源

位置：`30_status_registers.md:7`、`:28`、`:42`。

0x1400 payload的error_summary直接来自status_manager对“当前已轮询到的非SYSTEM页ERROR”的OR；0x000C则是system_registers自己的sticky累计summary，还合并clock/stream/USB/watchdog事件。二者使用同名，正文目前没有明确不可要求逐帧相等。同样，0x1400的total_drop_count是top total_drops原始汇总，而0x701C是可W1C清除的displayed_drop_count。清0x701C后不能要求状态帧同步归零。

建议在表后补一句：“状态帧为轮询/生成时快照；其error_summary不等同于0x000C sticky寄存器，total_drop_count也不等同于可清除的0x701C显示计数，禁止据不相等判协议错误。”

依据：`rtl/status_manager.v:61`～`:66`、`:115`；`rtl/system_registers.v:49`～`:59`、`:72`、`:105`、`:180`、`:184`、`:204`、`:235`；top `rtl/vapor_lidar_top.v:1246`。

## 最终合并版复核与修复确认

复核对象：2026-09-19生成的 `FPGA_HOST_PROTOCOL_V1.0.md` 与 `.docx`。采用python-docx只读检查，未操作硬件，未重复原始捕获CRC。

上述三项已进入合并版：Markdown第656/694行明确START mask与stream_mask区别；第669行把持续IN放在PING之前；第612行区分0x1400快照与0x000C/0x701C。Word中对应关键文本均存在。

本轮核对系统状态五类32 B/u32 schema表、seq回显和混合自增说明、CRC覆盖/填充、4096/4052/8192/8236长度边界、READ 12 B前导、1021/1011字上限、AI8 40000000的LE编码及普通写/commit/action确认流程，未发现新的字段数值错误。

### 合并输出中新增的问题（已通知主编制者）

1. **[P2] AI8表格被竖线拆列。** Markdown的DEVICE_ERROR表达式为反引号内 `HOST<<16 | CONTROL<<8 | ALARM`，未转义的两根竖线仍被Markdown/Word转换脚本当列分隔。36张表中第24张应有5列，Word实际全部生成7列，该字段被切成3格。建议用“按位OR”文本替代，避免简单`.split('|')`解析。其他35张表的行数/列数与Markdown一致。
2. **[P3] 内容索引不可点击。** Markdown内容索引15项都是纯文本，无内部链接；Word无任何bookmark、内部hyperlink或TOC域。若“索引可达”要求可跳转，需增加MD锚点链接和Word内部书签链接。
3. **[P2] 十六进制数字标记与总约定冲突。** Markdown第78行约定十六进制数值均带0x，但第108行frame_type写DATA=10/EVENT=11/STATUS=12；实际必须分别是0x10/0x11/0x12。命令首列000A/00FE和B0/B1裸常量也未带前缀。建议帧类型统一加0x、命令表明确“十六进制”、B0/B1常量加0x，以免按总约定生成十进制10的DATA帧。
