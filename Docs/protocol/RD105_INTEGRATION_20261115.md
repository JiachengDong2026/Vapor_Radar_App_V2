# Legacy CON19 RD105 FPGA experiment (2026-11-15)

> **Field correction, 2026-11-15:** this document preserves the implemented CON19 RS485 experiment, not the two installed TTL controllers. Both installed modules reply TEC=103 / FPV=4370 through the existing LC0/LC1 raw UART bridges, pages6800/6900, CON11-5/7 and6/8, at38400/8N1. Each physical module uses its own internal channel1. The current field contract is [dual TEC103 GPIO UART](../integration/sensors/TEC103_GPIO_20261115.md); bridge IDs are not instrument identities. Field host software must not expose, automatically enable, or send instrument transactions through source004A/page6A00. The same BIT retains this legacy engine and capability bit4; it has not been removed or hard-disabled. The19200/address2 requirements below apply only to the legacy RS485 experiment and must not be imposed on the two installed GPIO modules.

This contract supersedes withdrawn RD105 mappings. Source **004A**, page **6A00**, ID_VERSION **004A0103**, msg **1100**; HOST_EXTENSION_FLAGS.bit4 is present (flags **0000003B**). LC0 remains 0048/6800/00480100, LC1 0049/6900; AI8 remains 0046/6600. HC2A remains 00410106, 614C=48434432 (HCD2), independent CON11 UART.

CON19 uses transaction round robin for HMP (when HC2A is not selected), AI8 and RD105, fixed **19200/8N1**. RD105 must be configured **externally** to RS485 baud enum 2 (19200), address **2**, before connection; factory RS485 is 9600/address1 and conflicts with AI8/address1. HMP is address240. Local FPGA configuration never changes physical instrument configuration. Use the existing board RS485 transceiver and A/B/common wiring; TTL UART pins are not RS485. No pin assignments change. Termination/bias/common reference and polarity must be checked on the actual installation. No board validation is claimed.

All drivers reset disabled. Enabling the RD105 driver only reads the instrument; it never sets temperature, output enable, mode or PID. FPGA disable/reset stops communication and cannot turn off an already enabled physical output. Instrument power-on output policy must be configured independently.

## Registers

Offsets are byte offsets from 6A00; all accesses aligned u32 with byte strobes unless a command requires full strobes.

| Offset | Access | Meaning |
|---|---|---|
|00|RO|004A0103|
|04|RW|CONTROL bit0 driver enable, bit1 local reset, bit2 commit target, bit3 clear FIFO; each write supplies desired enable|
|08|RO|STATUS bit0 enabled,1 online,2 target pending,3 busy,4 online mirror,5 FIFO almost full,6 overflow,7 errors,8 time synced|
|0C|W1C|sticky errors: bit0 timeout,1 wire/CRC/format,2 FIFO drop,4 configuration,6 device/command failure,7 invalid sample|
|10|RW disabled|19200 only in shared mode|
|14|RW disabled|station2 only in shared mode|
|18|RW disabled|protocol0=Modbus RTU/8N1|
|1C|RW disabled|selected target channel1..2; automatic polling always scans both|
|20|RW|selected target shadow I32 microdegrees C, -400000000..1000000000, divisible by10|
|24|RO|latest actual temperature (see 4C for its channel)|
|28|RO|instrument ERRORCODE, address0007 U16|
|2C|RW disabled|poll interval ms1..3600000, measured after a channel frame|
|30,34|RO|CRC / timeout attempt counters|
|38,3C|RO|FIFO words / whole-record drops|
|40|RO|last independently confirmed target commit (microdegrees C), initially0 with count0; polling and raw parameter writes never overwrite this value. Use the TLV target for live per-channel readings.|
|44,48|RO|completed sample count / confirmed target commit count|
|4C|RO|latest complete sample channel1..2|
|80|WO|full u32 command1 read,2 write then independent readback; other values rejected|
|84|RW|instrument start register,0..FFFF|
|88|RW|quantity1..16 (16-bit registers)|
|8C|RO|bit16 busy,17 done; bits15:8 Modbus exception,7:4 transport error,3:0 result|
|90|RO|completion counter, advances once on success/failure/cancel; wraps u32; local reset clears|
|C0..DC|RW|32 wire bytes write buffer; first Modbus big-endian byte in u32 bits7:0|
|E0..FC|RO|actual FC03 readback bytes, same packing; cleared when a new operation begins|

Parameter settings/buffer are immutable while pending. Disabled commands and duplicate target/parameter commands return BUSY. CONTROL commit requires enabled=1 and snapshots channel/value. A target ACK is followed by FC03 of the identical target address; only exact valid readback increments +48. Action completion checks that count. Parameter result0 means read success or write with exact readback,1 initial transfer failure,2 readback transfer failure,3 readback mismatch,5 disabled/cancelled. Transport errors:0 none,1 timeout,2 CRC,3 station/function/length/echo,4 exception,5 UART/frame timing,6 configuration. ACK alone never reports confirmed success. No write is retried automatically, including after a timeout; the host must reconcile state before issuing another write. Parameter reads/readback have zero automatic retries; periodic poll reads may retry once while retaining bus ownership through silence/timeout/retry. Command/action timeout does not undo an accepted instrument write: inspect pending, completion counters and actual readback before any new write. RTU timeout is200ms per attempt, with arbitration delays in addition. A failing channel advances to the other channel on the next poll.

Parameter reads support arbitrary non-wrapping spans1..16. Writes reject spans touching general0000 (factory reset),0002 (station),0008/0009 (TTL/RS485 baud), and RO instrument words0001/0003/0007/000C. Other writes use native manual wire units and require explicit host intent/range validation. A successful raw write does not promise an effect beyond exact readback, nor that heating is active. AUTOPID start may change immediately and fail equality; result3 reports actual state, never auto-repeats the start. Manual inconsistencies (e.g. MF501 int64 labeled quantity2) require manufacturer clarification; do not expose ambiguous fields as validated controls.

## Data and actions

Schema2 header u16 version2/count, TLV headers tag:u16/type:u8/length:u8, little endian. Every channel record includes 0480/U32 channel1..2,0014/I32 target microC,0015/I32 actual microC when valid,0002/U32 ERRORCODE,0481/I32 signed output duty raw (manual int64 PWMDUTY ±2000000, percent=raw/20000),0482/U32 output enable0/1. Native temperature int32 in 0.00001 C is multiplied by10; 999999999 and outside manual range are invalid and omitted. Invalid duty/enable suppress the channel record and set error. Timestamp/time-sync pair comes from actual-temperature reply first start bit. Flags bit0 timestamp valid,2 captured sync,3 prior drop,4 device/invalid-temperature error; cycle FFFFFFFF. No private timestamps. FIFO backpressure preserves data; overflow drops a complete new record.

SENSOR_ACTION (command000B), source004A: action1 enable/disable (arg0/1),2 commit current shadow,3 clear FIFO (local only),4 local soft reset,5 W1C error mask,17 set target microC then commit and await confirmed count. Historical parameter operation3 factory reset is rejected; SENSOR_ACTION3 is only the common FIFO clear. Other unsupported actions return status13. Dedicated instrument actions use the +80 transaction API; no implicit output activation.

Implementation/validation results are recorded separately in the build report after fresh implementation. This document specifies the final intended wire contract and is kept synchronized with the implementation during this task.
