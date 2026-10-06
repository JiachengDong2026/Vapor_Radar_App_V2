> 正式归档：2026-09-23。本文源于2026-09-16集成版本；旧文中的Test专用、V2只读和当轮未上板描述属于当时记录。当前目录、六路既有实测及本轮离线边界以[正式集成修订](../INTEGRATION_REVISION_20260923.md)为准。

# AI8 integration and shared CON19 transactions

Scope: only the `integrated_20260916` snapshot. V2, previous integration snapshots and standalone releases are not modified. AI8 integration derives from the tested `member3_ai8/versions/serial_setpoint_20260916` driver. HMP remains available but disabled by default; its physical hardware validation is still outstanding.

## Modules and wiring

`member3_uart_sensors/rtl/ai8_modbus_rs485.v` replaces the former RD105 lane with the standard cfg/stream/error interface. PAGE is `0x6600`, SOURCE is `0x0046`, and identity is `0x00460200`: this is protocol version 2.0, not the old RD105 register/data meaning. Public definitions use `SRC_AI8` and `TLV_TAG_AI8_*`.

`ai8_poll_core.v` is the runtime-configurable port of the verified standalone poll/setpoint core. A successful poll reads SP/PV/SV/OP/alarm/control/host with seven FC03 single-register transactions and atomically publishes a snapshot. Odd channel alarm/control bytes are high bytes. Failed partial polls retain the previous complete values and publish communication diagnostics. No automatic startup write occurs.

AI8 grouped records intentionally use the completion/publication timestamp of the seven-read snapshot, rather than the first bit of an individual reply. No single response-start timestamp represents the entire group. At that publication edge, the core latches both `sample_ticks=now_ticks` and `sample_time_sync=time_sync_valid`; the wrapper uses this pair for the record timestamp and time-sync flag. The pair remains stable through sample backpressure, including failure/configuration diagnostic snapshots. A later change in global sync validity does not relabel an already published sample. HMP retains its single-response start timestamp semantics.

AI8 `CHANNEL_COUNT` defaults to 8 for the eight-channel instrument in this system. The underlying AI-8 V9.6 register map supports up to 96 channels at the same slave address (`0000h..005Fh` SP and `0600h..065Fh` PV). A deliberate wrapper parameter change can permit an expanded instrument; this release rejects channel 9 with default settings. AI8 slave addresses are 1–80 per the instrument manual; HMP remains 1–247. Defaults are AI8 address 1 and HMP address 240. The host must keep their configured slave addresses different.

Both wrappers have `SHARED_BUS=0` by default for standalone compatibility. Shared-bank instances set it to 1 and expose:

- `bus_request`: a waiting request or an in-flight master transaction needs ownership.
- `bus_busy`: the Modbus master is executing that transaction.
- `bus_grant`: permission to accept a request.

`rs485_transaction_arbiter.v` connects two clients, bit 0 HMP and bit 1 AI8. Inputs are `clk/rst_n`, two-bit `request/busy/txd/de`, and physical `uart_rxd`; outputs are two-bit `grant/rxd` and physical `uart_txd/rs485_de`. The bank connects only these physical outputs to CON19. Both receive engines may observe line activity; an ungranted master has `req_ready=0` and cannot accept another client's request or response transaction.

Ownership includes the entire request, DE turn-around, response, terminal quiet interval, timeout and all configured retries. It is not released merely because DE falls. Round-robin preference changes after the owner has deasserted request, busy and DE. Disabled/reset clients deassert those signals, permitting the other client to proceed. Each next master also observes the required silence before transmitting. The copied master retains the tested fixed 750/1750 us inter-character/inter-frame timing above 19200 baud and character-based timing at or below 19200.

Shared mode only accepts FPGA serial configuration 19200 baud, 8 data bits, no parity, 1 stop bit. Attempts to configure a different shared baud/format return cfg RANGE. This does not change the instrument's stored UART setting or send a configuration command. HMP must be configured externally to 19200/8N1 before it is enabled on this bus. Standalone HMP retains its original 19200/8N2 default. Both devices remain disabled after reset.

RX CDC paths for the top-level constraint audit are `u_member3/u_6/core/master/rx/rxd_meta_reg/D` (AI8) and `u_member3/u_1/core/transport/rx/rxd_meta_reg/D` (HMP).

## Units and setpoint confirmation

The user confirmed AI8 PV raw 244 means 24.4 degrees C. Therefore SP/PV/SV raw words are signed tenths of a degree C. OP retains the instrument's unsigned raw output units. The complete raw SP range is -9990 through 32000.

The existing ACTION 17-compatible cfg shadow at `6620h` is signed 32-bit microdegrees C. A value must be divisible by 100000 and convert into the raw range. A separate raw shadow at `6650h` covers the entire instrument range. Both write the same internal shadow. A valid commit latches the shadow; editing it during a command does not change that pending command.

Commit writes FC10 quantity 1 only to the selected channel SP register, high byte first, then reads the same address with FC03. Only exact readback increments `6648h` confirmed count. A locked instrument that echoes a write but leaves SP unchanged returns mismatch and does not increment that counter. No At, Srun, Loc, control or output register is written. SP confirmation does not claim that heating is running.

The command waits for the current full poll sample to be consumed. A pending command owns neither a partial UART byte nor a partially completed poll. Response status remains available in cfg; the shared master is free for another device between the write transaction and the readback transaction. A fresh full poll follows every command completion. Poll counters are separate from command confirmation counters.

| Result | Meaning |
|---|---|
| 0 | CONFIRMED: write succeeded and readback equals request. |
| 1 | WRITE_IO_ERROR: write communication failed; application of the value is unknown. |
| 2 | VERIFY_IO_ERROR: write reply succeeded but verification failed. |
| 3 | READBACK_MISMATCH: actual SP differs from the request. |
| 4 | RANGE_ERROR: unsupported raw value; no write. |
| 5 | CONFIG_ERROR/cancel: invalid core configuration, or pending operation cancelled by disable; transport error 6. |

Transport errors: 1 timeout, 2 CRC, 3 response format/identity, 4 Modbus exception, 5 frame/UART timing, 6 configuration. Exceptions are reported separately. Disable/soft reset can abort a local transaction but cannot undo a value already accepted by the instrument.

## AI8 cfg map

All offsets below are relative to `6600h`, aligned 32-bit accesses with byte strobes. Address/readonly/range errors take priority over BUSY. Baud, address, format, channel, interval, timeout and retries can be changed only while disabled.

| Offset | Access | Meaning |
|---|---|---|
| 00 | R | `00460200` identity/version. |
| 04 | RW | bit0 enable, bit1 soft reset, bit2 commit, bit3 clear FIFO. Commit requires enable bit set. |
| 08 | R | bit0 enable, 1 online, 2 pending, 3 master busy or pending, 4 sample valid, 5 almost full, 6 FIFO error, 7 any error, 8 time sync, 9 command result valid, 10 PV microdegree valid, 11 SP microdegree valid. |
| 0C | RW1C | Sticky common error bits. |
| 10/14/18/1C | RW | baud / slave / format / channel. Format 0=N1, 1=N2, 2=E1, 3=E2; shared mode allows only 0. |
| 20 | RW | Signed microdegree SP shadow; exact multiple of 100000. |
| 24 | R | PV signed microdegrees; zero when not representable, see status bit10. |
| 28 | R | `{host_status[15:0], control[7:0], alarm[7:0]}`. |
| 2C | RW | Poll interval ms, 1..3600000. |
| 30/34 | R | Final operation CRC/timeout counts. |
| 38/3C | R | FIFO level / dropped record count. |
| 40 | R | SP signed microdegrees; zero when not representable, see status bit11. |
| 44/48 | R | Complete successful poll count / confirmed setpoint count. |
| 4C | R | bit16 completed; bits15:8 exception; bits7:4 transport error; bits3:0 command result. |
| 50 | RW | Signed, sign-extended raw SP shadow, -9990..32000. |
| 54 | R | `{readback_raw[15:0], requested_raw[15:0]}`. |
| 58/5C | R | `{SP_raw,PV_raw}` / `{SV_raw,OP_raw}`. |
| 60/64 | RW | Timeout ms 1..65535 / retry limit 0..3. |

Signed 32-bit microdegrees cannot represent raw values above 21474. No truncated/wrapped value is exposed: raw values are always available, microdegree cfg reads return zero with validity clear, and corresponding optional microdegree TLVs are omitted. A raw shadow outside the microdegree representable range reads back as zero at offset20; use raw offset50 to read it exactly.

## Stream protocol version 2

Records use the existing sensor TLV message `1100h`, SOURCE `0046h`, and record header schema version 2. Each of the following fields uses a four-byte little-endian TLV value. Temperature raw values are sign extended to I32. Exact macro tags are shared with the host definitions.

| Tag | Type | Field |
|---|---|---|
| 0460/0461/0462 | I32 | PV / SP / SV raw signed tenths C. |
| 0463 | U32 | OP raw. |
| 0464/0465/0466 | U32 | alarm / control / host status. |
| 0467 | U32 | command status, same packing as cfg offset4C. |

Common DEVICE_STATUS carries `{reserved, exception[7:0], transport_error[3:0], online}`. Common DEVICE_ERROR contains the instrument host/control/alarm word; sensor alarms are independent of communication online status. SAMPLE_COUNTER carries complete successful polls. TARGET_TEMP_UC and ACTUAL_TEMP_UC are included only when representable, giving 13 TLVs/108 bytes normally and fewer at extreme values. Stale diagnostic snapshots retain previous values and clear online, with the error flag set. Downstream backpressure preserves every presented stream beat; FIFO overflow drops a whole new record and reports drop count/error instead of mixing snapshots.

## Validation

Independent bit-level BFMs perform UART framing and CRC checks without reusing DUT UART/CRC logic. `ai8_hmp_bus_bfm.v` dispatches addresses 1 and 240 on one physical serial wire and supports setpoint/verification faults and HMP timeout/CRC/exception injection.

Commands from `member3_uart_sensors`:

```powershell
python scripts/run_ai8_sim.py tb_ai8_sample_epoch tb_ai8_poll tb_ai8_setpoint tb_ai8_shared_bus
```

- `tb_ai8_poll`: PASS, 3 serial/channel configurations, 53 requests each, 300.5655 ms simulated. Covers positive/negative samples, SP versus SV, odd/even channel mapping, atomic data, retries/CRC/timeout/exception/recovery, 500/800 us high-speed gaps, invalid configuration, sample backpressure and reset.
- `tb_ai8_setpoint`: PASS, 16 command scenarios, 863.1645 ms simulated. Covers address80/channel96 core capability, raw boundaries and rejections, locked echo/readback mismatch, write and verification failures, response/sample backpressure, invalid-config response progress, reset mid-write and read-only restart.
- `tb_ai8_shared_bus`: PASS, 4.721018 s simulated. Covers both real wrappers sharing one wire, grant/DE exclusion, ungranted req_ready inhibition, retries/timeouts retaining ownership, fair subsequent service, version2 stream records, µC/raw conversion and overflow avoidance, cfg guards, confirmed count, locked/failed verification, FIFO backpressure/whole-record drops, queued command disable cancellation, and soft-reset ownership release while HMP continues.
- `tb_ai8_sample_epoch`: PASS; checks both sync-valid states at the publication edge, deliberate live-sync changes during held samples, the configuration-error publication path and reset. The shared-wrapper regression additionally flips global sync between core publication and wrapper consumption and verifies the resulting record timestamp/flag pair; its existing stream-backpressure checks cover those fields.
- `tb_modbus_rtu_master` and `tb_hmp_modbus_rs485`: PASS after the shared-bus changes, retaining standalone master behavior and the HMP standalone 8N2 default. Final shared regression was rerun after cfg-error priority fixes and passed.

The bank integration owner additionally reported its final 152-case cfg sideband regression PASS, including RANGE priority for illegal AI8 CONTROL bits and enabled HMP shared baud/format violations, plus the focused multi-device bank/AI8-setpoint smoke PASS.

Logs are in `member3_uart_sensors/reports/tb_*.log`; explicit TEST_PASS markers are required. The full bank, GPIF50 interface, constraints and implementation are validated separately by the integration workflow. These behavioral tests are not a claim of HMP hardware validation or automatic control/heating activation.
