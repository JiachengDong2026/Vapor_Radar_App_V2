> 正式归档：2026-09-23。本文源于2026-09-16集成版本；旧文中的Test专用、V2只读和当轮未上板描述属于当时记录。当前目录、六路既有实测及本轮离线边界以[正式集成修订](../../INTEGRATION_REVISION_20260923.md)为准。

# Member 3 integration contract, revision 2.0 — 2026-09-16

`rtl/member3_sensor_bank.v` is the single integration top. Lane order is PTB210, HMP, EPSILON, BMP390, SHT45, TFA1500, AI8. Each lane owns an independent 256-beat (1024 payload-byte) standard msg FIFO. Flattened lane k occupies `[k*WIDTH+:WIDTH]`. The bank arbitrates the two internal I2C clients and the shared HMP/AI8 RS485 link. The lead sensor_hub owns arbitration of the seven output message streams.

Use external common `timestamp_now`, `time_sync_valid`, `time_sync_seq`. PTB/HMP/EPSILON/TFA serial timestamps are captured at the first response/frame start bit; BMP390 captures an optional synchronized INT edge or burst-read start; SHT45 captures measurement-command acceptance. AI8 is an explicit exception: its seven sequential reads are published as one complete snapshot and the timestamp records result publication, including failed-poll diagnostics that retain prior values. It is not the acquisition time of every AI8 field. AI8 captures the sync-valid flag on the same clock as the publication timestamp and carries that snapshot into its record. `gnss_time_tag` is unsigned microseconds since 1970-01-01 00:00:00 UTC, and its valid pulse lasts one sys_clk. It is data received over UART, not an assertion of precise alignment to an external PPS edge. `sync_event_pulse` must already be in sys_clk domain. The bank has no permanent local time counter.

HMP and AI8 use physical bank ports `rs485_rxd`, `rs485_txd`, `rs485_de`, routed to CON19. Shared mode fixes the FPGA UART at 19200/8N1 and owns each request through response, timeout and retries. Default addresses are HMP240 and AI8 1; keep configured addresses distinct. Both devices default disabled. HMP hardware validation remains outstanding. AI8 page6600/source0046 uses protocol version2 and explicit SP shadow/commit plus exact readback confirmation; see [AI8 integration](../AI8_INTEGRATION_REPORT.md).

Physical I2C ports are `scl_i,sda_i` and `scl_drive_low,sda_drive_low`. Top-level IOBUF output data is 0 and tri-state control is the complement of drive_low. Both lines need pullups; neither is driven high. Baseline bus rate is 100 kHz, single master, with 20 ms transaction timeout. A bad initial bus condition receives nine recovery clocks and STOP; the request reports an error and the driver retries initialization. A transaction containing write bytes and read bytes uses a repeated START and retains ownership throughout. SHT conversion waits release ownership.

All 0x6000–0x66ff device pages respond only to their page and validate unknown/unaligned accesses. CONTROL bits are enable0, soft-reset1, commit2, clear-FIFO3, with per-device support and validation. ERROR is W1C; hardware errors should prevail over clearing. Dynamic baud configuration is allowed only while disabled for PTB/EPS/HMP/AI8; EPS also rejects changes during recovery cleanup, and shared HMP/AI8 reject baud/format values other than 19200/8N1. TFA has its own stop/drain/silence/apply FSM. BMP configuration has true shadow values, applied on enable or commit. Commit restarts BMP initialization and repeats calibration upload before further samples. Nonshadow driver settings apply while disabled or at their documented safe boundary. Clear FIFO is a stream discontinuity and should be coordinated by the system with downstream consumers.

Status outputs are `device_online[6:0]` and `device_error`, `device_drop_count`, `device_fifo_level`, each 7×32 bits. They are normal same-clock outputs, not hierarchical inspection. Standard message metadata is held stable under backpressure. Whole-record space is reserved before the first beat; lack of space increments the record drop counter once. A FIFO stall alone is not a dropped sample.

## BMP390 page 0x6300

Address 0x76/0x77; default OSR0, ODR5 (6.25 Hz), IIR0, PWR0x33. Full legal OSR0..5 per channel, ODR0..17, IIR register bits3:1, power bits5:4/1:0 are supported. Device ERR register is checked after programming; an invalid OSR/ODR combination sets DEVICE_REPORTED_ERROR and prevents samples until a new committed configuration. Pressure/temperature can be individually enabled, and sleep power mode suppresses polling. Raw reads always burst six bytes at 0x04..0x09 for shadow coherency. Header address/data pairs are not combined into an invalid sequential multibyte write.

Host compensation is the implemented mode; COMPENSATION_MODE=1 is rejected. After each initialization, TLV tag0x0100 type BYTES length21 contains registers0x31..0x45, followed by three zero pad bytes. Calibration is retained until admitted to the output FIFO. Sample TLVs are tag0x0101 U32 raw pressure and tag0x0102 U32 raw temperature; only enabled fields are emitted. `source_id=0x0043` disambiguates device-specific tags. These raw values must never be interpreted as mPa/mC without Bosch compensation. POLL_INTERVAL_MS is 1..3600000; readiness polling accounts for the selected ODR.

## SHT45 page 0x6400

Address0x44 is read-only. REPEATABILITY 0/1/2 = high/medium/low, commandsFD/F6/E0 and waits9/5/2 ms. Startup sends soft reset94, waits2ms, reads serial89 and validates both CRC bytes (poly31, initFF). Serial is a 32-bit value in SERIAL_LO and zero in SERIAL_HI. Measurements validate both words before emitting anything. Temperature mC is `floor(raw*175000/65535)-45000`; humidity milli-percent is `clamp(floor(raw*125000/65535)-6000,0,100000)`.

Heater modes1..6 map to39,32,2F,24,1E,15 (200/110/20mW, long/short). Long waits1110ms and requires poll interval>=12000ms; short waits120ms and requires interval>=1300ms. This keeps duty cycle below10%. Set interval before setting heater mode. Samples carry DEVICE_STATUS equal to heater mode, plus flags bit4 while heating because normal environmental accuracy does not apply. Default heater off. Sensor supply/ambient temperature limits still apply as documented by Sensirion.

## EPSILON page 0x6200

Accept FDILink FC,ID,LEN,SEQ,CRC8,CRC16-high,CRC16-low,payload,FD. CRC8 reflected0x8C/init0 covers first4 bytes; CRC16 nonreflected0x1021/init0 covers payload. Length1..255. Forwarded messages contain the entire validated wire frame with msg_id0x1200. MASK_LO bitk selects ID0x40+k; MASK_HI bitk selects ID0x60+k. Other IDs are not aliased. Time extraction is independent of forwarding/filter settings.

UTC comes from ID50 length102 with Filter_status bit3 set, ID51 length8 only after a valid initialized status50/53, or ID59 length74 with raw-GNSS-status bit5 set. Subseconds must be<1000000 and Unix seconds>=946684800. Device uptime timestamps in40/41/42 are never used as UTC. 2500ms without a validated frame clears online and cached UTC qualification. An incomplete frame times out after10ms. A CRC-valid ID50/length102 also produces `nav_valid`, `nav_payload[815:0]`, and `nav_timestamp` independently of raw forwarding, ID masks, and UTC qualification.

This snapshot connects EPSILON to CON14 RS232B using `epsilon_rs232` at 921600/8N1; the former AUX RS422 path is unused. The driver starts disabled. On enable it listens passively for2500ms. If no valid FDILink frame is seen, it attempts one bounded, read-only recovery exchange per enable epoch:
```text
#fconfig
#fmsg
#fdeconfig
```
Each line ends in CRLF. The exchange does not change stored baud, stream selection or message rates and does not save or reboot the device. Any CRC-correct FDILink frame qualifies link health independently of forwarding masks. After a recovery command has started, disable/reset cleanup completes the active UART byte/line and exit sequence; this requires the clock, device power and physical transceiver to remain available. Device TX is used only for this protocol, without a debug-text formatter. SYNC/PPS wiring and the epoch-to-PPS association need system-level setup; this driver makes no unsupported physical phase claim.

## PTB210/TFA1500 reuse

PTB starts FORM0 then RESET, waits2s at boot/reset and parses hPa into signed mPa. Continuous mode is stopped with CR when switching to polling/disable; UART bytes complete their stop bit. Framing/parity errors invalidate the whole current numeric response. Runtime baud/format writes while enabled are rejected. Device ID hash remains0 because no serial query is implemented.

TFA retains the reviewed low-frequency assumptions as explicit configuration extensions: LF scale10mm/count, invalid-mask0, version-commandCB (E8 selectable), D6-first response payload. These correspond to inconsistencies in the supplied vendor sheet and need real-device confirmation. HF has a well-defined 5-byte record and 0x3FFFFF invalid marker. UART HF/command pins are on bank64 LVCMOS18 before board-level conversion; LF receive AP13 is LVCMOS33. Use the lead's checked physical constraints, not TTL connector voltage as FPGA IOSTANDARD.

## 2026-09-16: VLP configuration status sideband

The integration drivers now append cfg_error_code and the bank exposes seven packed four-bit reasons. See [CFG_ERROR_SIDEBAND.md](CFG_ERROR_SIDEBAND.md) for status codes, priority and compatibility. Frozen independent board snapshots are unchanged.
