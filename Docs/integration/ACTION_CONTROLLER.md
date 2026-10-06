> 正式归档：2026-09-23。本文源于2026-09-16集成版本；旧文中的Test专用、V2只读和当轮未上板描述属于当时记录。当前目录、六路既有实测及本轮离线边界以[正式集成修订](../INTEGRATION_REVISION_20260923.md)为准。

# Action controller

`rtl/action_controller.v` consumes completion handshakes from cmd_decoder: hold action_valid with code/source/args until action_ready; action_status is then final. Requests are latched once. It is a separate cfg master; a single command writer must remain serialized while it performs read-modify-write operations. Read-only status polling can share the arbiter. cfg_valid/address/write/data/strb remain stable under backpressure. Withdrawing action_valid cancels operations not yet issued; earlier accepted writes cannot be rolled back.

Default CFG_TIMEOUT is2048 ticks; total ACTION_TIMEOUT is200000000 ticks (2 s at100 MHz). The decoder should use300000000 ticks so the controller terminates first. cfg_error maps toERR_BAD_ADDRESS(5), bus or operation timeout to9, failed preflight toERR_NOT_READY(11), missing HMP/AI8 write ACK toERR_COMMIT_REJECTED(14). Unknown actions returnUNSUPPORTED(13), unsupported sources4 and invalid values7. Errors may occur after earlier writes; the controller does not claim transaction rollback.

## Masks and source disambiguation

Frozen mask bits use source_id&0x3F. Broadcast sourceFFFF and SYSTEM source0001 address acquisition modules: WMS0/1 bits16/17, ADC0/1 bits32/33, DILA0/1 bits48/49, sensors0040..0046 bits0..6, stepper0047 bit7 for RESET/CLEAR only. WMS bits represent a WMS+DAC pair. An all-ones mask expands to the supported operation-specific mask. Other unknown bits are rejected before writes. For an explicitly addressed module, the mask can contain only that module's bit.

This frozen mapping aliases TIME0002 with EPSILON0042, SYSTEM0001 with HMP0041 and STREAM0050 with WMS0010. TIME RESET/CLEAR therefore requires explicit source0002; broadcast bit2 means EPSILON. A broadcast module reset does not reset the controller/system itself. Global soft reset remains a direct SYSTEM CONTROL register operation. STREAM0050 can issue SET_STREAM_MASK but COMMIT/RESET/START/STOP do not map it to WMS0. This disambiguation prevents accidental cross-module actions without changing frozen IDs.

## START and STOP

START/STOP source masks select coherent ADC/WMS/DILA channel groups: selecting any of a channel's WMS, ADC or DILA bits controls the complete corresponding channel. Sensor bits separately select periodic sources. Options and reserved words currently must be zero.

START checks every selected channel before its first write: ADC ready and no pending commit; DILA STATUS.bit1 ready and no pending commit (bit4 is not required); DAC ready, not busy and no pending commit; WMS_ACT_HZ nonzero. It then preserves other SYSTEM CONTROL bits and enables global_enable at0004, followed by ADC0/1, DILA0/1, DAC0/1, WMS0/1, then selected sensors. It never implicitly commits waveform parameters.

STOP disables selected WMS first, then ADC, DILA, DAC and sensors. It emits one-cycle `stop_flush[1:0]`, waits at least2048 ticks and then waits for selected `channel_datapath_idle[1:0]` and, if sensors were selected, `sensor_datapath_idle`. It does not clear data FIFOs. Global enable remains available for independent motor/control work. The top must include internal ADC/DILA idle, RAW framer banks and downstream transport in the idle inputs. Shared sensor idle may conservatively wait for other sensor records as well.

`acquisition_running` mirrors WMS and sensor CONTROL writes made by this controller. Direct register writes and external global watchdog gating are not visible to that mirror; system status should combine it with global_enable and/or polled physical module status. `busy` indicates an executing command, including STOP drain.

## COMMIT, RESET, CLEAR and MASK

WMS COMMIT snapshots original WMS enable, disables WMS, allows16 ticks for its pipeline, waits DAC ready/idle, commits DAC, waits DAC ready/pending clear, commits WMS, waits WMS pending clear, then restores original WMS enable. WMS STATUS.ready also requires enabled DAC transport, so it must not gate a disabled pre-start commit. A failure leaves the partially completed configuration and WMS stopped; it never restores a failed waveform automatically.

ADC/DILA COMMIT preserves enable, writes CONTROL.bit2 and waits pending clear. HMP/AI8 commit first waits any previous pending operation, snapshots WRITE_ACK_COUNT(+48), commits, waits pending clear and verifies the ACK count advanced exactly once. Their active registers remain owned by the device drivers and change only after valid device acknowledgement. Other sensor commit pulses use their documented no-op/commit semantics and wait pending clear.

WRITE AUTO_COMMIT also uses this controller after every shadow write succeeds.
The decoder prevalidates source ownership across the complete range and permits
AUTO_COMMIT only within one supported 256-byte page. DAC30/31 pages map to
their owning WMS source and execute the same combined commit. Unsupported
or cross-page auto requests fail before the first write. Original WRITE response
identity is preserved. A timeout cancels controller execution but cannot retract
a device request already accepted; a later device ACK may still update active.

RESET writes CONTROL soft-reset with enable cleared, in WMS鈫扗AC鈫扐DC鈫扗ILA鈫抯ensor/stepper order. Busy motor reset may be rejected by the driver; stop motion first. CLEAR_ERROR writesFFFFFFFF to selected module ERROR registers, then SYSTEM error summary for a broadcast clear. SET_STREAM_MASK writes SYSTEM2C/30 for stream mask and34/50 for RAW mask, followed by ADC RAW_STREAM_ENABLE403C/413C. Only RAW ADC bits32/33 are valid. The four mask halves are sequential register writes; no unsupported atomic 128-bit update is claimed.

## Device action values

SENSOR_ACTION payload is `{u32 action,u32 value}`, with explicit sensor source0040..0046:

| action | Meaning | value |
|---:|---|---|
|1|Enable/disable|0/1|
|2|Commit, including ACK verification for HMP/AI8|0|
|3|Clear FIFO, preserving enable|0|
|4|Soft reset and disable|0|
|5|Clear error bits|W1C mask|
|16 (10h)|HMP pressure shadow at6134, then ACK-checked commit|IEEE754 F32 bits|
|17 (11h)|AI8 target shadow at6620, then ACK-checked commit|signed microdegrees C|
|32 (20h)|TFA range/mode at6514, wait driver ready|0 standby,1 low,2 high|
|33 (21h)|TFA low-rate command at6518|1 single,2 continuous,3 self-test,4 version|

TFA action33 confirms driver acceptance; its later device response is reported through normal records/status. Physical units and range enforcement belong to the existing device drivers.

MOTOR_ACTION source0047 (SYSTEM/broadcast also allowed): action1 sets signed relative target pulse count, enables global/motor and starts motion; response means accepted, not completed. Action2 STOP waits motor busy clear. Action3 zeros position while idle. Action4 enables/disables with value0/1. Actions2/3 require value0. Driver retains DM422 pulse/guard timing ownership.

TIME_ACTION source0002 (SYSTEM/broadcast also allowed): action1 enable0/1; action2 rearm/reset sync state with value0 and keep enabled; action3 choose rising0/falling1 edge; action4 set timeout1..3600000 ms; action5 W1C error mask. Rearm never resets the monotonic timestamp counter.

## Verification

`scripts/run_action_sim.tcl` uses a stateful cfg slave model and verifies preflight has zero write side effects, ordered start/stop, disabled/enabled WMS restoration, DAC busy wait, snapshot ACK accounting including an earlier pending HMP write, failed RD ACK preserving active value, sensor/mask/motor/time routes, W1C, malformed requests, downstream error, cfg/total timeout and request cancellation. `scripts/run_action_synth.tcl` checks the actual FPGA part and a100MHz/2ns I/O OOC budget. Full system route validation remains with the system owner.

## AI8 集成修订 20260916

source 0x0046、page 0x6600 在本版表示 AI8，ID_VERSION=0x00460200；旧 RD105 协议不能继续使用。SENSOR_ACTION action17 仍接受 signed 微摄氏度，40.0℃对应40000000。驱动在 FC10 写 SP 后追加 FC03 读回，只有相等时才增加 0x6648 confirmed_count；仅写回执不会使 Action 成功。设备停机状态不会因设温而改变，不写 Srun/At/Loc。完整 raw 范围通过 0x6650（signed raw，0.1℃/LSB）再 COMMIT；0x6620 微度入口只接受可表示且整除100000的值。读0x664c得到写/验证结果，0x6654记录requested/readback。

HMP和AI8共享CON19事务仲裁，默认地址分别240/1，FPGA共享串口固定19200/8N1；接HMP前须把仪器通信格式配置相符。HMP和电机仍待实物测试，START命令不要无差别启用未接设备。
