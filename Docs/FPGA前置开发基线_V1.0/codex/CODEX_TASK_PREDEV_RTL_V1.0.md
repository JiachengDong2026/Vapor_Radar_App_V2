# TASK-PREDEV-001：成员开工前公共 RTL / 仿真基础设施

> 优先级：P0 / 三成员正式开发前完成  
> 工具：Xilinx Vivado  
> 语言：Verilog-2001  
> 目标器件：XCKU11P-2FFVA1156I  
> 原则：只开发“让三位成员可以立即独立开发和仿真”的最小公共基础，不提前实现正式系统功能。

---

## 0. 必读输入与最高优先级

开始前先阅读并遵守：

1. `docs/COMMON_INTERFACE_SPEC_V1.0.md`
2. `docs/REGISTER_MAP_FREEZE_V1.0.md`
3. `rtl/common/project_defs.vh`
4. `rtl/common/stream_defs.vh`
5. `rtl/common/register_map.vh`
6. `rtl/common/error_codes.vh`
7. 三成员任务书 V1.2
8. `FPGA下位机Verilog开发指南_V1.0.md`

优先级：本任务提供的 `COMMON_INTERFACE_SPEC_V1.0` 与 `REGISTER_MAP_FREEZE_V1.0` 为成员开工接口基线。若旧文档存在命名/地址冲突，**不要擅自兼容两套定义**；保留 V1.0 基线并在最终报告列出冲突。

禁止：

- 修改已冻结 `source_id/msg_id/register address/port width/phase encoding`；
- 提前实现 USB、FX3、packetizer、crossbar、正式 GNSS time sync、正式 WMS、正式 DILA；
- 使用 SystemVerilog `interface/struct/class`；
- 为了方便测试引入额外第三方依赖。

---

# 1. 需要实现的正式 RTL：`system_timebase_stub.v`

路径：

```text
rtl/common/system_timebase_stub.v
```

接口：

```verilog
module system_timebase_stub (
    input  wire        sys_clk,
    input  wire        rst_sys_n,
    output reg  [63:0] timestamp_now,
    output wire        time_sync_valid,
    output reg  [31:0] time_sync_seq
);
```

功能：

1. `rst_sys_n=0` 时 `timestamp_now=0`, `time_sync_seq=0`；
2. 复位释放后，每个 `sys_clk` 上升沿 `timestamp_now += 1`；
3. `time_sync_valid` 固定为 `1'b0`，明确表示这是本地自由运行 stub、并未 GNSS 同步；
4. `time_sync_seq` 固定保持 0；
5. 不实现校时、PPS、slew、jump；
6. 无 latch，无未定义输出；
7. 可综合；后续正式 `time_sync_core` 可以用相同的时间服务输出替换它。

验收：连续计数、复位行为正确、64-bit 无截断、Vivado synthesis 无 error/critical warning（由本模块引起）。

---

# 2. 仿真公共模块：`clock_reset_gen.v`

路径：

```text
sim/common/clock_reset_gen.v
```

用途：所有成员 testbench 可以统一实例化，不进入 synthesis sources。

建议接口：

```verilog
module clock_reset_gen #(
    parameter integer CLK_PERIOD_NS = 10,
    parameter integer RESET_CYCLES  = 20
)(
    output reg sys_clk,
    output reg rst_sys_n
);
```

要求：

- 产生默认 100 MHz `sys_clk`；
- 初始 `rst_sys_n=0`；
- 保持 `RESET_CYCLES` 个完整时钟周期后，只在安全时钟边界释放为 1；
- 不使用不可移植的 SystemVerilog 语法；
- 仅 simulation source。

---

# 3. 仿真公共 BFM：`cfg_bus_master_bfm.v`

路径：

```text
sim/common/cfg_bus_master_bfm.v
```

目的：让成员1/2/3用完全相同的方法测试寄存器，从源头消除对 `cfg_valid/cfg_ready` 时序的不同理解。

接口：

```verilog
module cfg_bus_master_bfm #(
    parameter integer TIMEOUT_CYCLES = 1000
)(
    input  wire        sys_clk,
    input  wire        rst_sys_n,
    output reg         cfg_valid,
    output reg         cfg_write,
    output reg  [31:0] cfg_addr,
    output reg  [31:0] cfg_wdata,
    output reg  [3:0]  cfg_wstrb,
    input  wire        cfg_ready,
    input  wire [31:0] cfg_rdata,
    input  wire        cfg_error
);
```

必须提供 Verilog task（名称固定）：

```text
cfg_write32(addr, data)
cfg_write_masked(addr, data, wstrb)
cfg_read32(addr, data_out)
cfg_expect32(addr, expected, mask)
```

行为要求：

1. task 只能通过 `cfg_valid && cfg_ready` 判定一次事务结束；
2. 等待期间保持请求字段稳定；
3. transaction 完成后下一拍撤销 `cfg_valid`；
4. 超过 `TIMEOUT_CYCLES` 必须打印明确错误并结束当前仿真（可 `$display` + `$finish`）；
5. 若 `cfg_error=1`：普通 read/write task 报错；可额外提供 `cfg_expect_error` 便于测试非法访问；
6. `cfg_expect32` 支持 mask 比较并在失败时打印 address/expected/actual/mask；
7. BFM 不得假设 slave 必须 1-cycle ready；必须覆盖 wait-state。

---

# 4. 仿真公共 stub：`wms_reference_stub.v`

路径：

```text
sim/common/wms_reference_stub.v
```

用途：成员1在成员2正式 WMS 尚未完成时开发 DILA。

接口名称必须与冻结的 WMS reference 一致：

```verilog
module wms_reference_stub #(
    parameter [31:0] SINE_PHASE_INC   = 32'h0100_0000,
    parameter integer SCAN_PERIOD_CYCLES = 10000
)(
    input  wire        sys_clk,
    input  wire        rst_sys_n,
    input  wire        enable,
    output reg         scan_start,
    output reg  [31:0] cycle_id,
    output reg  [31:0] sine_phase,
    output wire        phase_valid,
    output wire        wms_running
);
```

功能：

- `enable=0`：`wms_running=0`, `phase_valid=0`, `scan_start=0`；相位/周期保持；
- `enable=1`：每个 `sys_clk` 令 `sine_phase += SINE_PHASE_INC`；
- 每 `SCAN_PERIOD_CYCLES` 产生一次单拍 `scan_start`；
- `scan_start` 同拍先/同时形成新的 `cycle_id`，保证观察者看到的是新周期 ID；
- `phase_valid = wms_running = enable && rst_sys_n`；
- 使用自然 32-bit wrap；
- 这是仿真参考源，不实现锯齿、DAC、WMS 寄存器或真实波形幅值。

注意：该 stub 只服务成员1 DILA 开发，不能被综合进正式 bitstream。

---

# 5. 必须实现的自测 testbench

创建：

```text
sim/tests/
├── tb_system_timebase_stub.v
├── tb_cfg_bus_master_bfm.v
├── tb_wms_reference_stub.v
└── tb_common_predev_smoke.v
```

## 5.1 `tb_system_timebase_stub.v`

至少验证：

- reset 下为 0；
- release 后连续 1000 cycle 每拍 +1；
- `time_sync_valid==0`；
- `time_sync_seq==0`；
- 中途再次 reset 可以清零并重新计数。

## 5.2 `tb_cfg_bus_master_bfm.v`

自行写一个极小 dummy cfg slave，仅用于 BFM 自测。至少覆盖：

- 1-cycle ready write/read；
- 5-cycle delayed ready；
- masked write；
- readback；
- cfg_error；
- 在 ready 前检查 BFM 是否保持请求稳定。

不要把 dummy slave 放入正式 `rtl/`。

## 5.3 `tb_wms_reference_stub.v`

至少验证：

- disabled 时 valid/running 为 0；
- enabled 后 phase 按精确 increment 递增；
- phase 32-bit wrap；
- `scan_start` 单拍；
- 周期长度精确等于参数；
- cycle_id 每周期只 +1；
- reset 行为正确。

## 5.4 `tb_common_predev_smoke.v`

将 `clock_reset_gen + system_timebase_stub + wms_reference_stub` 同时实例化，运行至少 3 个 scan period，证明公共模块可以一起编译运行，无 module/name/include 冲突。

---

# 6. Vivado / Verilog 要求

- Vivado 工程语言：Verilog；
- 所有正式/仿真代码必须兼容 Verilog-2001；
- `default_nettype none` 可使用，但若使用必须在文件结尾恢复，避免污染第三方文件；
- 不新增 IP Core；
- 不要求建立正式板级 XDC；这些模块无外部物理引脚；
- `system_timebase_stub.v` 必须作为 synthesis source 独立通过语法/综合；
- `sim/common/*` 与 `sim/tests/*` 仅作为 simulation source。

---

# 7. 交付目录

最终必须形成：

```text
predev_common/
├── rtl/
│   └── common/
│       └── system_timebase_stub.v
├── sim/
│   ├── common/
│   │   ├── clock_reset_gen.v
│   │   ├── cfg_bus_master_bfm.v
│   │   └── wms_reference_stub.v
│   └── tests/
│       ├── tb_system_timebase_stub.v
│       ├── tb_cfg_bus_master_bfm.v
│       ├── tb_wms_reference_stub.v
│       └── tb_common_predev_smoke.v
├── scripts/
│   └── run_predev_tests.tcl
└── reports/
    └── TASK-PREDEV-001-final-report.md
```

另外必须复用项目负责人提供的：

```text
rtl/common/project_defs.vh
rtl/common/stream_defs.vh
rtl/common/register_map.vh
rtl/common/error_codes.vh
```

**不要复制后再改一套不同版本。**

---

# 8. 自动测试脚本

创建 `scripts/run_predev_tests.tcl`，目标是在 Vivado batch 模式下：

1. 创建临时 in-memory/project；
2. 加入公共 header、RTL、simulation files；
3. 逐个运行四个 testbench；
4. 任何一个 test FAIL 则脚本返回失败；
5. 对 `system_timebase_stub.v` 做一次综合/elaboration sanity check；
6. 不生成/提交大型 `.runs/.cache/.sim` 临时目录。

若环境里存在 `xvlog/xelab/xsim`，允许脚本调用对应 flow；但最终报告必须写明实际执行命令与 Vivado 版本。

---

# 9. 验收标准（全部满足才可 DONE）

- [ ] 4 个要求文件全部存在；
- [ ] 4 个 testbench 全部 PASS；
- [ ] `cfg_bus_master_bfm` 覆盖 wait-state / error / masked write；
- [ ] `wms_reference_stub` 的 phase、scan period、cycle_id 都有自动断言式检查；
- [ ] `system_timebase_stub` 可综合；
- [ ] 未修改冻结 header 中的 ID/地址/位宽；
- [ ] 无 SystemVerilog-only 语法；
- [ ] 无新增第三方依赖/IP；
- [ ] 最终报告列出所有新增/修改文件；
- [ ] 最终报告明确写出 `PASS/FAIL`、测试数量、失败数量、Vivado 版本；
- [ ] 发现任何公共规范矛盾时已经在报告“Open Issues”列出，未私自改变规范。

---

# 10. 不属于本任务的内容

本任务完成后立即停止，不要顺手继续开发：

- 正式 `clk_rst_mgr`；
- 正式 `time_sync_core` / GNSS PPS 对时；
- WMS 正式 RTL；
- ADC / DAC / DILA；
- UART / sensors；
- `reg_ctrl_crossbar`；
- `sensor_hub`；
- `stream_arbiter`；
- packetizer / VLP1；
- FX3 / GPIF / USB；
- top-level；
- 板级 XDC。

---

# 11. Codex 执行策略

直接完成任务，不要在可自行判断的问题上反复询问负责人。

遇到语法错误、仿真失败、testbench 失败或 Vivado 集成问题：

1. 先定位根因；
2. 修改代码/测试；
3. 重新运行；
4. 必要时多轮调试直至通过；
5. 只有属于外部 Vivado 缺失、权限问题、输入规范真正互相矛盾且无法兼容时，才在最终报告中标为 BLOCKED/Open Issue。

不得以“需要确认”代替可以从冻结规范直接确定的实现。
