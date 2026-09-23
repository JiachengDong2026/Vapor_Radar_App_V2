> 正式归档：2026-09-23。本文源于2026-09-16集成版本；旧文中的Test专用、V2只读和当轮未上板描述属于当时记录。当前目录、六路既有实测及本轮离线边界以[正式集成修订](../../INTEGRATION_REVISION_20260923.md)为准。

# Modbus/HMP/RD105 implementation contract

All driver state uses `sys_clk`; UART RX alone is asynchronous and passes through the reused two-flop ASYNC_REG synchronizer. Configuration/time inputs must already be synchronous. Driver ports match MODBUS_HANDOFF and member3_sensor_bank. Public source IDs remain HMP0041/RD1050046; msg1100, cycleFFFFFFFF. Each driver owns an independent256-beat message FIFO with whole-record reservation and visible drop count. No host UI or device programming is performed by the test scripts.

## RTU transport

`modbus_rtu_master` snapshots slave/function/address/quantity/write bytes, baud/format, timeout and retry limit on req_valid+req_ready. It supports03 and10,1–16 registers, slave1–247,8-bit data, none/even/odd parity and1/2 stop bits. Payload byte0 occupies bus[7:0]. Reply read_data starts with the first register's first wire byte in[7:0]. Request settings cannot change an active transfer. `done` is one sys_clk pulse; error/read_data remain available after it. Driver consumers are always ready for that pulse.

Error values:0 success,1 timeout,2 CRC,3 slave/function/length/echo mismatch,4 Modbus exception,5 UART/inter-character error,6 invalid request. `attempt_error_pulse/attempt_error` records each failed attempt even if a later retry succeeds. Exception response code is exposed by the master. Exception frames are not retried; other wire/timeout failures obey retry_limit. Both device drivers use200ms response/quiet timeout and one retry (two attempts maximum). Successful retries can therefore coexist with a sticky diagnostic bit from the first failed attempt.

CRC16 uses initFFFF, reflectedA001, low CRC byte on wire first; full-reply residue must be zero.03 validates byte count and total reply length;10 validates echoed address and quantity. Extra/truncated bytes fail. An inter-character gap over1.5 characters fails. The3.5-character idle duration is computed from baud and complete start/data/parity/stop length using a fractional half-bit accumulator. Because uart_rx reports at the midpoint of the final stop bit, an additional half-bit compensates before accepting a complete frame or starting the next request. Model assertions check actual full-stop-to-next-start spacing.

RS485 DE asserts before any start bit with a1us+1clock guard, stays through final stop, then releases after the same guard. RX echo is masked while DE is high. The shared TX/RX UARTs communicate internally over byte handshakes; no sensor-specific register is embedded in the master. RD105 uses the same engine over separate TTL TX/RX, with DE unconnected.

## Configuration

Only exact full32-bit pages6100/6600 respond. Outside pages return ready=error=0. Unknown, unaligned, RO and reserved-bit writes error; all RW registers honor byte strobes. Common CONTROL bit0 enable, bit1 soft reset, bit2 commit, bit3 clear FIFO. Each CONTROL write supplies its desired enable state. ERROR is W1C with new hardware events taking priority.

Baud/address/format/poll/mask/channel changes require disabled state. Shadow pressure/target can be written during operation. Commit snapshots it, sets pending, and queues a complete10 write after the current polling transaction group. A duplicate pending commit errors. Only a matching CRC-valid device acknowledgment promotes pending to active; failure clears pending but leaves active unchanged. A stopped driver can store pending until later enabled. A read of shadow never masquerades as confirmed hardware state. Disable aborts the local UART transaction and releases DE; no incomplete response is published. Soft reset clears configuration, pending, FIFOs and counters.

HMP format register uses the official Vaisala enum0=8N1,1=8N2,2=8E1,3=8E2,4=8O1,5=8O2; default1. Baud1.2k–115.2k is additionally bounded by sys_clk/16. Setting the local serial parameters does not reprogram device serial settings; configure both ends consistently.

Local read-only extensions for both pages: +40 confirmed active pressure/target, +44 completed sample-record count, +48 acknowledged write count. These do not change frozen offsets. HMP active pressure initially0 means no acknowledged compensation write has occurred (write_count0), not a claim of0hPa in the device. RD active target is also refreshed by a valid target read.

## Timestamp and TLV

The timestamp is captured on the first UART start pulse of the measurement response, after the unavoidable input synchronizer latency. It is never replaced by end-of-frame or FIFO drain time. Time-sync state is captured with it. HMP RH/T use one four-register transaction. RD target/actual/error are separate transactions; the sample timestamp is the actual-temperature response's first byte. A driver does not create a private free-running timestamp counter.

Payload starts with version1/count, then standard tag/type/length/value TLVs. HMP emits requested RH0100/T0101 as F32 bit patterns and device-error0002 as U32. RD emits target0014 I32 microC, actual0015 I32 microC when valid, then device-error0002 U32. RD invalid actual values omit the actual TLV, set DATA_FORMAT and stream device-error flag; stale temperature is not emitted as valid. HMP NaN/Inf bits remain recognizable F32 with device-error flag and sticky DEVICE_REPORTED_ERROR. Standard flags: bit0 timestamp-valid, bit2 captured time-sync, bit3 previous record dropped, bit4 device/measurement error.
