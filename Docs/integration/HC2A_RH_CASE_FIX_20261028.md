> 历史开发记录（2026-10-28）。该修正版已于 2026-11-13 正式合入 V2，当前交付、HCD2 签名及实板验证范围以[最新说明](../LOWER_COMPUTER_RELEASE_20261113.md)为准。下文“未合入/未上板”为当时状态。

# HC2A humidity unit compatibility fix (2026-10-28)

The physical HC2A (device type020, firmware V1.2-1) returned a 104-byte RO-ASCII RDD answer with 19 fields, valid checksum 0x23, 47.80%RH and 21.76 degrees C. Its RH unit is `%rh`; the candidate accepted only `%RH`. Read-only diagnostics reported failure bit12 (field/unit), zero UART errors, zero checksum errors and zero timeouts. Original capture: ../../../../diagnostic_01/poll_15s/hc2a_reply.bin in the task workspace.

This fix accepts the two observed/documented exact RH unit spellings `%RH` and `%rh`. Other unit spellings, frame/checksum/address/type checks, numeric validity/ranges and the existing Celsius formats remain unchanged. UART stays 19200/8N1 on CON11 pin13 TX, pin15 RX; TFA1500 and AI8 retain their interfaces. No probe settings are written. The compatible acquisition ID remains 0x00410106; diagnostic signature changes to HCD2 (0x48434432) to identify this fixed build.

tb_hc2a_real_reply replays the captured answer byte-for-byte, including the 0xB0 Celsius symbol, lower-case RH unit and fixed-width device name. It verifies learned address00, RH/T TLV values and diagnostics. The original uppercase example remains a separate regression. Checksum-fault, timeout, invalid-unit, malformed-frame and multi-device regressions must continue to pass.

Development and implementation stay in rh_case_fix_01 outside V2. Implementation may reuse the successfully reviewed diagnostic routed design as an incremental physical reference after fresh RTL synthesis. The runner verifies reference SHA256 and unchanged constraint/build-script inputs; all existing setup/hold, route, DRC, pin timing and CDC gates remain active. Physical reuse is explicitly recorded, and is not represented as a fresh placement. This is a volatile hardware validation candidate; no Flash or V2 merge is performed here.
