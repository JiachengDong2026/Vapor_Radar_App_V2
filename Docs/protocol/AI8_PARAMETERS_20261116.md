# AI8 parameter mailbox — 2026-11-16

Source 0046 / base 6600 / ID 00460200 remains compatible with the eight-channel scan and directed SP interface. HOST_EXTENSION_FLAGS adds bit2 (Ai8Parameters), becoming 0x3F. Feature 66FC becomes 0x0F. Reset leaves the driver disabled. No hardware access is part of this change.

## Host contract

Matches VaporView FpgaDeviceExtensions.cpp and FpgaInstrumentService.cpp: instrument source 0x46, count=1, action=1 read or action=2 write-and-confirm. Address is the actual Modbus word address, without any additional channel offset. CH5 SP is 0004; CH5 PV is 0604. Data in the JSON transaction is two bytes, big endian; mailbox values themselves are numeric U16.

| Register | Access | Meaning |
|---|---|---|
|6680|WO full strobes|1 read, 2 FC10 write followed by FC03 verification|
|6684|RW|16-bit instrument address|
|6688|RW|16-bit raw write value|
|668C|RO|bit16 pending, bit17 done; bits15:8 exception,7:4 transport error,3:0 result|
|6690|RO|actual U16 readback, cleared on submit; zero on transfer failure|
|6694|RO|completion counter, increments once for success, failure or disable cancellation; wraps U32|

Address/value are immutable while pending. Command rejects disabled driver, an existing directed-SP command or parameter transaction, unsupported action/address/write permission, and partial command strobes. Directed-SP commit rejects pending parameter transactions. Local configuration ACK means acceptance only. Done and the completion counter are updated only on final completion. Result0 means successful read or exact independent write readback,1 initial write transfer failed,2 read/readback transfer failed,3 mismatch,5 disabled/cancelled. Transport codes retain the common Modbus definitions (1 timeout,2 CRC,3 protocol/echo,4 exception,5 UART,6 configuration). Parameter transactions and verification use zero retries; periodic scans and legacy directed SP retain their existing retry policy. A timeout/cancel cannot undo an instrument write already transmitted.

Disable completes a pending transaction once with result5/error6; local reset clears the mailbox and counter. Polling never changes parameter results or completion counter. Parameter operations never increment the legacy directed-SP confirmed counter. Single bus master serializes scanning and parameter work at START/GAP boundaries; the accepted address and operation are latched before transmission.

## Manual evidence and allowed commands

Repository manual `Docs/【资料】FPGA设备接入手册/6-AI-8+系列多回路智能温控器+使用说明（8xx8g+8xx8精度5以下）.pdf`, section7, printed pages38–44 (PDF39–45), documents FC03/06/10, channel address spacing 0x60, group addresses0800–083F, and globals0840–085F. Only FC03/10 are used. Loc can acknowledge a write without modifying the value (printed page43), making independent exact readback essential. Range clamping by the instrument is reported as mismatch, with actual value available.

Reads allow first eight channel words in each documented block0000–04DF, PV0600–0607, high-resolution PV0660–066F, alarm0680–0683, control06C0–06C3 and globals/groups0800–085F. Reserved address gaps are rejected. Manufacturer diagnostic globals may be read for compatibility with the current global page; they are not writable.

Writes allow the first eight words of channel blocks0000–047F, groups0800–083F and globals0844/0845/0846/084E/0850/0852. Srun0845 only accepts documented values0,15,9655 (manual printed page31). Addr0840, baud0841, parity/config084C, manufacturer fields0858–085F, measured values, identity and live status are not writable. This matches the current collector, which intentionally defers Addr/baud changes and displays manufacturer fields. No hardware-verified communication switchover is claimed. OP writes are conditional on instrument manual mode and may fail exact verification in auto mode; self-changing commands may likewise return mismatch and are never retried automatically.

No host mailbox adjustment is required. Host must keep count=1, capability/enable gating, completion-counter check, exact status0x20000 and write data equality checks. Page writes remain sequential transactions, not atomic page updates; partial failure must be reported and reconciled by reading the instrument. Existing native unit encodings remain unchanged.

## Validation

Targeted Vivado results and final implementation evidence are recorded below when available. No physical temperature parameters, output state, USB, JTAG or Flash were accessed.

- Static: `python fpga/scripts/check_baseline.py` => BASELINE_STATIC_CHECK_PASS.
- Vivado2025.1 targeted run `D:/Project/Test/ai8_params_20261116_b/results.json`: nine tests PASS (parameters, scan, setpoint, shared_bus, cfg_cache, poll, sample_epoch, action_ai8, hc2a_ai8_independent). First run exposed changed legacy retry behavior; fixed by applying zero retries only to parameter transactions.
- Expanded mailbox tests and sensor-bank/RD105 compatibility: `D:/Project/Test/ai8_params_20261116_c/results.json`, four PASS. Includes busy shadow/command/legacy-commit exclusion, rejected RO/reserved addresses and illegal Srun value.
- Pin-level parameter CH5 test: `D:/Project/Test/ai8_params_uart_20261116_b/results.json`, PASS. Uses actual UART and existing fault-injecting slave BFM for success, locked mismatch, write timeout/CRC/exception, verification timeout/CRC/exception, held samples/responses and reset. Only parameter selection inputs are forced; serial response and master completion are not forced. Initial test expectation used the even-channel alarm byte; corrected to the documented odd-channel high byte for CH5.
- Public entry `fpga/vivado_check.tcl` attempted in `D:/Project/Test/ai8_params_common_20261116_a`, stalled in launch_simulation and was stopped. Same public test independently passed via run_regression.py (`ai8_params_common_sim_20261116_a`). Original common synthesis/report section executed with that checked simulation log through an external wrapper (`ai8_params_common_synth_20261116.tcl`), yielding PREDEV_COMMON_V12_VIVADO_CHECK_DONE in `ai8_params_common_20261116_b.log`. These are synthesis smoke reports, not routed signoff: WNS8.439ns, WHS-0.089ns before routing.

## Final build qualification

Fresh build `D:/Project/Test/ai8_params_full_20261116_b`: FULL_SYSTEM_BUILD_PASS, returncode0, changed_inputs=[], build_result.pass=true. Target xcku11p-ffva1156-2-i, Vivado2025.1 build6140274. Existing license configured only in the child process. Initial a attempt was intentionally stopped before final header organization; no result from a is used. The b build completed synthesis, placement, routing, built-in post-route setup closure, all final gates and bitstream generation without RTL/constraint edits or historical checkpoint reuse.

- BIT: `D:/Project/Test/ai8_params_full_20261116_b/full_build/vapor_lidar_top.bit`
- SHA256: `ecfed68345c0e54e286fe4dff41706bc58ec018315d6db2f39fbc8eb331e9578` (independently checked with Get-FileHash).
- Routed WNS +0.019ns / TNS0; WHS +0.010ns / THS0; pulse-width checks pass.
- Route complete; DRC2629 warnings, zero Critical Warning/Error. Required check_timing categories pass; only the existing forwarded FPGA_GPIF_PCLK no_output_delay exemption remains.
- DAC minimum margin7.179ns; AD4630 minimum margin2.290ns; both independent pin timing checkers PASS.
- CDC exact inventory match2/2: CDC-10 Critical1 and CDC-3 Info1. Current routed structural review PASS, memory_entries0/reset_entries1; existing reset release chain reviewed, no new CDC endpoints. Evidence: `cdc_review/endpoint_comparison.json`, `netlist.log`, `netlist_endpoints.tsv` under the build directory.
- All12 bus-skew constraints MET, minimum slack8.593ns (`cdc_review/bus_skew.rpt`).

This is offline qualification only. No USB/JTAG, board programming, live parameter changes or output activation occurred. VaporView workspace was read only. Generated artifacts/logs are not committed. Parameter protocol acceptance is based on the supplied original manual and offline BFM; physical full-page validation remains outstanding.

## PPS release integration, 2026-11-26

Integrated on PPS continuous discipline release `0ed60bd`. GET advertises `0x3F` and the AI8 feature register returns `0x0F`. The WMS discipline registers retain their existing offsets on the WMS pages.
