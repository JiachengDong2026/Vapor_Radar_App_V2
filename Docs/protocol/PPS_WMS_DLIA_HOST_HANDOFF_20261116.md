# PPS—WMS—DLIA 单次同步扫描：上位机对接规范

日期：2026-11-16。开发基线：`4b7e9eb`，包含最新正式整机代码及 DLIA 2～8 阶 SOS 扩展。本功能先在外部 Test 工作树验证，再复制至正式源码。验证范围与结果见[修订记录](../INTEGRATION_REVISION_20261116_PPS_WMS_DLIA.md)。本文描述源码接口，历史发布 BIT 不包含此次功能，现有 Qt 界面也不会自动增加这些控件。

## 1. 两种工作方式

每个 WMS 通道独立选择，复位默认 **0：原连续扫描**。

| 模式 | 行为 | DLIA 行为 |
|---|---|---|
| 0 连续扫描 | 沿用原 WMS 连续锯齿扫描及 PHASE_MODE | 沿用原周期边界、滤波历史和连续处理 |
| 1 PPS 单次同步扫描 | 一个合格 PPS 启动一个完整锯齿周期，结束后写入等待电平，等下一次 PPS | 扫描起点清滤波历史和抽取计数，仅处理本次扫描窗口中的 ADC 样本，结束后封帧排空 |

PPS 模式不会在一个 PPS 后连续执行多次扫描，也不将 ADC/DAC 采样时钟锁相到 PPS。PPS 到达时通道必须已经 armed；忙时不排队、不补触发、不重启当前扫描。扫描时间超过 PPS 周期或输出堵塞时，后续 PPS 可能被跳过并累计计数。

两路接收同一个 PPS，分别判断就绪，允许一通道连续、另一通道 PPS。**没有双通道“全部就绪才共同触发”的门控**：任一路未就绪不阻止另一路启动。要求同次采集时，上位机应核对两路 LAST_PPS_SEQ 相等；要求 DAC 实际起点一致时，还须使用一致的 DAC SPI 时序、初始化状态及可用性。

## 2. 接线与 PPS 有效资格

复用已有 TIME 输入，不新增引脚：EPSILON GPIO2 配置为 1PPS Output，接 CON22 SMA 中心，参考地接外壳。设备 GPIO 高电平约 4.8～5 V，板上 CON22 经 SN74LVC1T45 转为 FPGA 1.8 V，**不可把设备 5 V 信号直接接 FPGA GPIO**。保持高阻输入，不加 50 Ω 并联终端。接线、设备保存配置流程和资料依据见[GNSS PPS 接口](../integration/GNSS_PPS_DM422_20261027.md)。

触发沿沿用 TIME 设置，默认上升沿（TIME `0x1024`）；TIME 必须启用且系统时钟正常。连续三个 PPS 间隔在 nominal ±1% 内才合格，因此冷启动至少需要四个有效沿，第四个沿可触发。短毛刺、异常间隔、超时或时钟异常撤销资格，重新连续合格后恢复。具体 TIME 校准/超时规则沿用现有接口。

频率合格与 UTC 历元确认是两件事：PPS 扫描不要求 UTC 锚定；没有 UTC 锚点时仍可使用 100 MHz 本地单调 tick。旧数据帧 time_sync 标志只表示原同步状态，不表示 UTC 已确认。不得直接用最新串口时间或电脑时间推算某个 PPS 的绝对秒号。

PPS 失效本身不会提前截断已经开始的扫描；完成当前扫描后等待合格 PPS，不自动回退连续扫描。全局/DAC 禁用、时钟不可用或 WMS 停止属于另一个中止路径。

## 3. 能力识别与协议兼容

- WMS0：BASE=`0x2000`，source=`0x0010`；WMS1：BASE=`0x2100`，source=`0x0011`。
- 读取 `0x2084` / `0x2184`，必须得到 **`0x50505301`**（PPS API v1）。旧固件未知地址时隐藏 PPS 功能，不继续写新地址。
- 既有模块 ID、VLP1 版本、source/message ID、全局 capability word 均不增加版本位；仅凭旧 WMS ID 或 TIME ID 不能判断支持 PPS 扫描。
- 沿用 VLP1 READ_REG=`0x0002`、WRITE_REG=`0x0003`、START_ACQ=`0x0006`、STOP_ACQ=`0x0007`，无需新增命令号。完整帧头、CRC、字节序见[主协议](FPGA_HOST_PROTOCOL_V1.0.md)。
- 本实现的 PPS 采集路径要求正式双 AD4630 接口。legacy ADC3660 路径不会给出 PPS trigger_ready。

## 4. WMS 新增寄存器

均为 32 位、小端、字节地址。以下 offset 加 BASE。建议全字读写，WRITE flags=0，不对这些字段使用 AUTO_COMMIT。RO 字段不应进行 masked write。

| Offset | WMS0 / WMS1 | 名称 | 权限 / 复位值 | 定义 |
|---|---|---|---|---|
| 4C | 204C / 214C | TRIGGER_MODE | RW / 0 | 0 连续；1 PPS 单次；其他值拒绝 |
| 50 | 2050 / 2150 | IDLE_LEVEL | RW / 0 | signed Q1.31 等待电平 |
| 54 | 2054 / 2154 | TRIGGER_STATUS | RO | 下表状态位 |
| 58 | 2058 / 2158 | TRIGGER_COUNT | RO / 0 | 接受的 PPS 次数 |
| 5C | 205C / 215C | MISSED_COUNT | RO / 0 | WMS 已使能但不能接受的合格 PPS 次数 |
| 60 | 2060 / 2160 | LAST_PPS_SEQ | RO / 0 | 最近一次被接受的 TIME PPS 序号 |
| 64 / 68 | 2064/68 / 2164/68 | LAST_PPS_TICK_LO/HI | RO / 0 | 最近被接受 PPS 的 64 位本地 tick |
| 6C / 70 | 206C/70 / 216C/70 | ACTUAL_START_TICK_LO/HI | RO / 0 | 最近首个扫描样本写入 DAC 完成的 tick |
| 74 / 78 | 2074/78 / 2174/78 | ACTUAL_END_TICK_LO/HI | RO / 0 | 等待电平写入 DAC 完成；传输丢失中止时为检测终止 tick |
| 7C | 207C / 217C | COMPLETED_COUNT | RO / 0 | 非 WMS 中止且扫描结束、DLIA 已排空的次数 |
| 80 | 2080 / 2180 | ABORTED_COUNT | RO / 0 | WMS 中止且收尾完成的次数 |
| 84 | 2084 / 2184 | TRIGGER_API | RO / 50505301 | 能力标识 |
| 88 | 2088 / 2188 | REJECTED_COUNT | RO / 0 | WMS 已使能时收到的不合格 PPS 次数 |

TRIGGER_MODE 和 IDLE_LEVEL 是**立即生效的停机配置**，不是原波形 shadow：WMS CONTROL.bit0 必须为 0，且无活动/收尾扫描、波形流水、待发送数据、pending commit 或参数计算。否则返回 BUSY=8，原值不变。写完不需要再 commit 这两个字段。模式切换不会自动清除历史计数、cycle_id 或时间戳。

所有新增计数按 U32 回绕，WMS 全局复位/被允许的软复位清零，不支持 W1C。WMS 软复位还将模式和等待电平恢复为 0，清除 configured，必须重新提交波形参数。

### TRIGGER_STATUS 位定义

| bit | 名称 | 解释 |
|---|---|---|
| 0 | armed | 已启用且配置有效、DAC 可用/空闲、等待电平已写入、DLIA/ADC 就绪、无 pending/扫描；具备接收资格 |
| 1 | burst_busy | 本次扫描或 DLIA 收尾尚未完成 |
| 2 | burst_active | 正在调度本次 DDS 扫描；它不是物理 DAC 窗口的严格边界 |
| 3 | end_seen | 本次已经到达 DAC 等待电平或检测到传输中止；保持至下次接受触发 |
| 4 | idle_written | 已完成等待电平数字写入，不是电压测量结果 |
| 5 | dlia_trigger_ready | DLIA 配置/数据管线与 ADC 采集接口可开始新扫描 |
| 6 | pps_qualified | 当前 TIME PPS 周期资格有效，与 UTC 锚点无关 |
| 7 | scan_aborted | 本次/上次 WMS 扫描中止；下次接受 PPS 清零 |
| 31:8 | reserved | 0 |

armed 不要求 bit6 已经为 1：可先准备就绪，再等待 TIME 获得资格。是否接受某个沿还要在该沿检查 pps_qualified。通用 WMS STATUS 的 ready/busy 含原有配置语义，PPS 状态以上表为准。

配置错误沿用 VLP status 枚举：5 地址/对齐，6 只读，7 范围，8 忙；同时 WMS ERROR.bit4 置位。UPDATE_OVERRUN 沿用 ERROR.bit8。模块 ERROR 位掩码不能与 VLP status 枚举混用。PPS 未合格或漏接本身通过计数反映，不等价于配置写失败。

## 5. 扫描窗口、时间戳与参考相位

```text
合格 PPS → 接受并记录 PPS seq/tick → DDS/映射/SPI 延迟
         → 首样本 DAC SYNC 上升沿（ACTUAL_START）
         → 完整锯齿周期的 DAC 更新
         → 等待电平 DAC SYNC 上升沿（ACTUAL_END）
         → 排完带窗口标签的 ADC 数据及 DLIA/分帧输出 → busy=0
```

PPS 到首样本之间有数字流水和 SPI 延迟，不能把 PPS tick 当作实际扫描起点。新增时间戳按 DAC 样本事务完成时刻记录，phase/cycle 标签也来自该事务，避免把尚未写入 DAC 的 DDS 相位用于 ADC 解调。此处“实际”指数字接口完成，不含 DAC 模拟建立、激光器、探测器和模拟链路延迟。

ADC 保持连续 CNV 采样，在 CNV 时锁存时间戳、WMS cycle_id、当前已应用相位和窗口有效位；DLIA 仅接受 `[ACTUAL_START, ACTUAL_END)` 的有效窗口样本。与 DAC 起点同拍的 CNV 使用新标签，与终点同拍的 CNV 属于窗口外。窗口外样本正常丢弃，不触发“相位无效”错误，不等待下一次 PPS 才排空。RAW 可选上传仍沿用原连续采样契约，主机不可将 RAW 默认当作已经按 PPS 截断。

正常结束依靠第一条时间戳不早于终点的**窗口外 ADC 标签**，确认此前窗口内数据已按序经过输入 FIFO，再等待算术和分帧管线排空。不是固定等 512 个时钟。ADC 被停止且输入队列为空时也可结束，但按中止/不完整处理。

PPS 模式每次从锯齿相位 0 开始，首个正弦相位为已提交的 SINE_PHASE_U32；即使旧 PHASE_MODE 选择跨周期自由运行，PPS 单次扫描仍重置起始相位。DLIA 继续使用已配置的 1f phase offset 和 2f phase correction。

扫描长度由实际 DAC 更新周期和量化后的锯齿相位增量决定：`N_update = ceil(2^32 / saw_increment)`，`T_window = N_update × PERIOD_TICKS / 100000000`。最后一个扫描样本保持完整更新间隔后才写等待电平。不要只用请求频率浮点倒数推断准确 tick 数；以实际 START/END 回读为准。

例如请求锯齿100 Hz、DAC更新100 kHz，PERIOD_TICKS=1000、相位增量四舍五入为4294967；PPS每次从0开始，需要1001次更新才越过相位回绕，窗口为1001000 tick，即10.01 ms，而不是严格10.00 ms。主机应按整数计算或实读窗口设置期望样本数。

ADC 相位与 PPS 不会被强制重置。窗口采样数由连续 CNV 与窗口相对位置决定；非整数比例时可相差一个样本。DLIA 从每次窗口第一个有效样本重新计抽取，输出点数为实际被处理样本数除以抽取因子的向下取整。样本太少、无完整抽取点时可能没有 DLIA 数据帧，应结合触发/完成计数判断。

当前每个 DLIA 周期银行最多容纳 **4096 点**，周期结束封帧后才开始输出；分片长度不会增加周期容量。主机配置时应保证最长扫描的点数不超过4096并留出采样计数量化余量。超出会丢点并标记错误，持续USB接收也不能消除单周期容量上限。

## 6. 等待电平与滤波器

IDLE_LEVEL 进入原 DAC 映射、GAIN_UQ2_30、OFFSET_CODE、MIN/MAX 钳位链路，不直接表示伏特。默认 Q1.31=0 对应默认映射中点 code `0x80000`，不保证物理输出 0 V。测试中的 `0x10000000` 在默认映射下得到 code `589823`。必须结合板卡量程和模拟标定配置；DAC 的 OPGND/DACTRI 等设置也可能使模拟输出与数字写入不同。

PPS 模式每次 ACTUAL_START 清除所有 SOS 节的 1f I/Q、2f I/Q 历史和抽取状态，保留已提交的系数和相位修正；各扫描从相同零初态开始。首段具有滤波建立瞬态，低截止频率/高阶时可能占据较长窗口，主机应按科学测量需要选择扫描长度及有效区间。不会自动预热滤波器，也不会自动补偿模拟群延迟。连续模式的滤波历史保留原行为。

2～8 阶与截止频率上传沿用[SOS 规范](DLIA_SOS_HOST_HANDOFF_20261116.md)。设计采样率必须等于实际 ADC 输入率（DLIA `+FC`），不是 DAC 更新率或 DLIA 输出率。PPS 扫描期间 DLIA COMMIT 返回 BUSY；等待态可按原约束提交，但主机推荐停止后统一配置，避免某次 PPS 因 pending 而漏接。WMS PPS 模式已使能时，即使尚未收到 PPS，WMS COMMIT 也返回 BUSY；先禁用并排空。

自定义 SOS 活动设计率与 ADC 实际率不一致时，DLIA ERROR.bit8 置位、停止使用错误系数处理新样本；窗口数据继续被消费以免阻塞收尾，本次标记 partial，恢复匹配前不重新 armed。处理步骤：停止 WMS并完成收尾，停止采集，配置 ADC、按新 Fs 生成并完整上传 SOS、commit、回读确认、W1C 清错误，再重新 START。COMPLETED_COUNT 只反映 WMS/排空完成，不保证样本、滤波或数据质量无误。

## 7. 推荐启动与模式切换流程

所有 R/W 均封装为 VLP 命令，source 可统一用 SYSTEM=`0x0001`，每条检查响应 status=0，并保持 Bulk IN 持续接收。WRITE flags=0；不要把下述语义伪代码直接作为 ASCII 发给 USB。

1. 读取两路 API；读回现有配置、错误和计数，保存会话基线。若旧采集仍在运行，先完成本节后述停机。
2. 确认 WMS/ADC/DLIA 已停止，WMS trigger busy=0、配置 pending=0，旧输入/输出队列已排空。DAC 应完成初始化。
3. 按原接口配置 DAC 传输/映射并 commit。设置共同 ADC 采样率并 commit；双 AD4630 共享时序更改要求两 ADC 都停止且 PHY 空闲。读取实际 Fs。
4. 配置两路 WMS 锯齿/正弦、幅值/偏置、相位、更新率等 shadow，并在禁用状态 commit；等待完成、检查 ERROR 和实际更新率。
5. 写 WMS TRIGGER_MODE=1、IDLE_LEVEL=目标 Q1.31。不要把模式与波形 shadow 混成一次自动提交。
6. 配置 DLIA：MODE.bit0 必须为 1（WMS 参考），通常 MODE=3；MODE=7 为绕过滤波的诊断用途。设置输出率、分片点数、相位补偿和需要的 SOS；commit 后读回 active/profile/generation。ADC EXPECTED_PER_CYCLE 推荐先设 0 关闭固定计数检查，确认稳定的整数采样关系后再使用非零值。
7. 保持数据接收及 STREAM/USB 使能；根据吞吐决定 RAW 开关。TIME 启用、PPS 沿和超时配置按现有 TIME 接口。调用 START_ACQ 启动需要的通道，它会按顺序启用完整 WMS/DAC/ADC/DLIA 通道，但不替代上述参数 commit。
8. 轮询两路 TRIGGER_STATUS.bit0=1，并观察 bit6 及 TIME 校准状态。等待合格 PPS，无需每秒发软件启动。
9. 持续接收 DLIA 帧，按 source、cycle_id、分片序号重组；读取每次扫描诊断快照并保存。若需 UTC，另行按 GNSS 规范确认并建立锚点。

START/STOP 的掩码仍按 `source_id & 0x3F`，选择对应 WMS/ADC/DLIA 任一位会控制完整通道。双通道可用 WMS 两位：`u64 mask=0x0000000000030000, u32 options=0, u32 reserved=0`。这是 START/STOP mask，**不要写成 STREAM 数据允许掩码**。

### 示例参数与操作

以下只示意已有停机/初始化状态下的 WMS0，ADC/DLIA/DAC 完整配置仍需按上面顺序执行：

```python
assert read32(0x2084) == 0x50505301
write32(0x2004, 0)            # WMS0 disabled；已有扫描先按下节排空
write32(0x2010, 100_000)      # saw = 100 Hz，寄存器单位 mHz
write32(0x201C, 1_000_000)    # sine = 1 kHz
write32(0x2028, 100_000)      # DAC 更新请求 100 kHz
write32(0x2004, 4)            # commit 且保持 disabled
wait_pending_clear_and_check_error(0x2000)
write32(0x204C, 1)
write32(0x2050, 0)            # Q1.31中点；物理电压取决于硬件
# ADC 实际 Fs=1 MHz，DLIA输出10 kHz，MODE=3，所有commit完成后：
start_acq(mask=0x0000000000010000)   # 仅通道0的完整采集链
wait_bit(0x2054, bit=0, value=1)
# 每个合格PPS约启动10 ms扫描；以实际END-START确认量化长度
# 主机持续接收，并核对帧/错误/计数，不逐PPS发START。
```

### 停止与返回连续模式

推荐有序停止：先仅写 WMS CONTROL=0，保持全局、DAC、ADC、DLIA 和 USB 接收可用；若扫描正在进行，会中止扫描、通过 DAC 写入等待电平并输出已有尾帧。等待 trigger busy=0 后调用原 STOP_ACQ 停完整通道。若希望保留一个完整周期，应在上一个扫描完成、下个 PPS 尚未来到时禁用 WMS，并检查计数确认没有竞争触发。

原 STOP_ACQ 可直接使用并已覆盖顶层仿真；活动扫描按中止收尾。由于原 STOP 可能先关闭 DAC/采集链，不能保证等待电平事务已物理完成，不能把 STOP ACK 显示成“模拟输出已归零”。传输中止时 ACTUAL_END 是逻辑终止 tick，只有正常等待电平完成时才对应真实数字写入。紧急停机/硬件安全输出仍使用既有专用设计。

停止/排空后写 `204C/214C=0`，按需要重新提交波形并 START，即恢复原连续模式；写 1 则下次 START 等 PPS。模式/等待电平写 BUSY 时继续检查排空状态，不强行软复位清掉未接收数据。软复位恢复模式 0，主机必须重新回读。

## 8. 上行数据、快照关联与存储

DLIA 保留 source `0030/0031`、msg `1001` 和现有 schema/分片结构，不额外插入 PPS seq 字段。正常完整扫描不会仅因进入等待态而标 partial；中止、样本错误、丢点/溢出或指定 expected count 不匹配时，应结合帧 partial（原 flags bit5）及模块 ERROR 识别异常。已经上传的分片不能在事后回写异常标志，应按整个 cycle 汇总判定。零点扫描可能无帧。

busy清零和COMPLETED_COUNT递增表示DLIA已将该次输出交给下游，不保证USB缓冲已经排空或主机已经收到全部VLP分片。主机须另外核对分片数量、序号、总点数与CRC，再把一次扫描标记为“接收完整”。

帧 cycle_id 仍是 WMS 周期号，不等于 PPS seq；漏接 PPS 不生成虚假的 WMS 周期。用新寄存器建立 `通道、PPS seq/tick、WMS cycle_id、START/END tick` 关联。PPS 模式旧 WMS LAST_SCAN_TICK 仍是 DDS 调度时刻；物理窗口使用新增 ACTUAL_START/END，数据帧周期时间戳使用实际起点。

新增 WMS 寄存器没有 TIME 那样的读锁存功能。刚接受 PPS 时 START/END 可能还保留上次值，不得在 busy=1 时拼成完整记录。推荐：

若在首个扫描样本真正写入前就中止，ACTUAL_START还可能保留上次值，即使busy已经清零也不能使用；同一未复位的单调tick段内应检查`START >= LAST_PPS_TICK`且`END >= START`，不满足则将该次记录为“接受后未形成有效窗口”，不关联旧帧。中止的END还须按前述传输状态区分数字写入终点与逻辑终止时刻。

```python
while True:
    before = read_counts_and_status(base) # accepted/completed/aborted、busy
    if before.busy: continue
    record = read_cycle_seq_and_ticks(base)
    after = read_counts_and_status(base)
    if not after.busy and before == after:
        # 再要求本次完成/中止计数已推进；未扫描的全0不作为扫描记录
        save_record(record, after)
        break
```

计数、cycle_id、PPS seq 都按 U32 模运算；发生复位须创建新的会话段，不跨复位推断连续性。快照只有“最近一次”信息，主机需在下一次扫描前及时读取并记录；若期间跨过多次完成，无法从这些寄存器恢复所有丢失记录。两路是否同 PPS 必须比较 LAST_PPS_SEQ，不能仅比较各自 cycle_id。

BIN 原始 VLP 字节流格式不变。建议额外保存 JSON/CSV 旁车：软件/固件版本与新 BIT 哈希、API、模式、全部 WMS/DAC/ADC/DLIA active 配置、SOS 系数及设计 Fs/Fc、等待电平、TIME 配置和资格、每次扫描关联快照、计数增量、错误、主机接收时间及 UTC 锚点依据。当前 Qt 不会自动保存这些新增字段；不能仅凭 WRITE ACK 恢复配置。见[BIN 规范](BIN_STORAGE_FORMAT_V1.0.md)。

## 9. 背压、异常和联调检查

| 现象 | 检查与处理 |
|---|---|
| armed=0 | CONTROL/全局使能、WMS配置、DAC初始化、idle_written、DLIA MODE.bit0/pending/实际Fs、ADC使能/共享时序、旧输出队列 |
| armed=1但不扫描 | PPS接线/有效沿、TIME启用/资格、REJECTED_COUNT；先等足连续合格间隔 |
| MISSED_COUNT增长 | 扫描/排空是否跨越下一PPS、USB接收是否持续、两路是否分别就绪、配置pending |
| 两路周期号不同 | 检查各自PPS seq及missed计数；独立通道可能漏接，不能按cycle_id强配对 |
| COMPLETED增长但数据异常 | 检查DLIA ERROR、partial、饱和/丢点、输出抽取因子、窗口样本数；完成计数不是测量合格计数 |
| 模式/等待电平写BUSY | 禁用WMS并等扫描/流水/配置排空，再写；不要一边enabled一边修改 |
| STOP等不到ACK | 持续读IN，查看队列和模块状态；命令超时不表示所有停止写均失败 |

USB 背压不能拉长模拟扫描，已有缓冲不足时仍可能丢数据并报错；它可以延长排空 busy，从而拒绝后续 PPS。必须持续 Bulk IN，不要等一秒后才集中读取。现场验证应联合观察 PPS、DAC SYNC/输出和 ADC CNV，测量起点延迟、两路偏差、扫描长度、滤波建立与模拟链路延迟。本次离线测试不等价于 PPS 电气、模拟波形、绝对时间精度或实板测量验收。
