> 正式归档：2026-09-23。本文源于2026-09-16集成版本；旧文中的Test专用、V2只读和当轮未上板描述属于当时记录。当前目录、六路既有实测及本轮离线边界以[正式集成修订](../INTEGRATION_REVISION_20260923.md)为准。

# cfg error reason extension, revision 1.4 — 2026-09-16

Each register slave now retains the existing `cfg_error` bit and appends a four-bit `cfg_error_code` output. The reason is meaningful on `cfg_valid && cfg_ready && cfg_error`; successful transfers carry zero. It uses the VLP command response enumeration, not the unrelated per-module ERROR register bitmask.

| Code | Meaning | Producer |
|---|---|---|
| 5 | ERR_BAD_ADDRESS | Unknown/unmapped/unaligned register or page |
| 6 | ERR_READ_ONLY | Write to a valid read-only register |
| 7 | ERR_RANGE | Unsupported numeric value, reserved bits or invalid parameter combination |
| 8 | ERR_BUSY | Otherwise legal access rejected because an operation/configuration is active |
| 9 | ERR_TIMEOUT | Register crossbar/command/action completion deadline |
| 10 | ERR_DEVICE_OFFLINE | Reserved for a slave that explicitly rejects this transaction as offline |
| 11 | ERR_NOT_READY | Example: starting a disabled stepper |
| 12 | ERR_PROTOCOL | Explicit transaction protocol failure |
| 13 | ERR_UNSUPPORTED | Explicit unsupported operation |
| 14 | ERR_COMMIT_REJECTED | Action completion lacks the required new device ACK |
| 15 | ERR_INTERNAL | Error bit asserted with reason zero at the crossbar |

Address/RO classification has priority over parameter validation; an invalid parameter remains RANGE even if the device is also busy. Slave reasons are emitted from the same rejection logic as `cfg_error`, so changing a register rule does not require a second register map in the command decoder. A device's background sample/communication timeout remains its status/error condition; it is not automatically a cfg transaction timeout.

`reg_ctrl_crossbar.slave_error_code[N*4-1:0]` uses nibble k for slot k and emits `cfg_error_code[3:0]`. Its own missing-page/alignment rejection returns5 and deadline returns9. `cfg_bus_arbiter.m_error_code` is distributed only to the granted master's nibble in `s_error_code[N*4-1:0]`. `cmd_decoder.cfg_error_code` supplies READ/WRITE/MASK response status. `action_controller.cfg_error_code` is preserved in `action_status` and then returned by the decoder; opcode/source/sequence retain the original command identity.

Member1 emits four nibbles in ADC0/ADC1/DILA0/DILA1 order; member3 emits seven in PTB/HMP/EPS/BMP/SHT/TFA/RD order. Member2's channel and dual wrappers merge the active page into one four-bit reason because page selection is exclusive. The leader top connects each physical slave slot to that member's corresponding nibble. The status poller consumes the existing error bit; it does not convert background polling into command responses.

Older instantiations using named ports may omit the new output only if they do not need reasons. A command/action master must connect its new reason input; tying it to a generic5 is allowed only in legacy verification fixtures modeling a generic error. No generic fallback is used by the real system. Sequential writes retain earlier successful shadow writes if a later transfer fails, and no AUTO_COMMIT is issued after that failure. This extension does not change register addresses or message formats; it restores the already documented distinct VLP response codes.

Directed validation: `scripts/run_cfg_errors.py` runs the real decoder→arbiter→crossbar→stepper/time path plus existing controller/decoder/register/clock tests. The leader's final GPIF50 top regression additionally attempts read-only ID writes on all21 pages and real range failures on member modules. See `reports/CFG_ERROR_VALIDATION.md` for final evidence.

## Revision 1.4: registered crossbar transactions

The crossbar now captures the complete request and a one-hot page selection, then captures the selected slave's completion before acknowledging the master. For an immediately ready slave, edge E0 captures the request, E1 commits the slave transfer and stores its response, and E2 completes the upstream handshake. Request capture never acknowledges a write. An invalid address instead stores code5 at E0 and completes upstream at E1 without asserting any slave valid. Addresses, port widths and error-code values are unchanged.

Masters keep valid and all request fields stable through the upstream completion edge. After that edge they may keep valid high and present another transaction; the crossbar accepts it in its next IDLE cycle, without requiring valid to fall. The arbiter continues to hold its grant until completion or withdrawal. Registered request fields remain unchanged during slave wait; registered response data, error and reason remain unchanged through upstream completion even if the slave changes its outputs. Slave valid is deasserted throughout RESPONSE, so each completed request has exactly one slave handshake.

Withdrawing valid before a sampling edge cancels the pending upstream transaction and immediately suppresses slave valid and upstream ready. The crossbar returns to IDLE at that edge. Withdrawal after a slave completion cannot roll back the already committed operation, but its stored response is discarded rather than delivered to a later master. A delayed slave must discard uncommitted internal calculation state when its valid is withdrawn; it must not attach an old calculation to a later request. Reset clears the pipeline and timeout counter.

The timeout counter starts at zero when the request is captured. ISSUE cycles with count less than TIMEOUT_CYCLES-1 may complete; the terminal cycle suppresses slave valid even if a late slave ready appears, then stores code9 and increments timeout_count once. The upstream response follows one cycle later. Arbitration wait is outside this counter; command/action master deadlines include arbitration plus crossbar latency and may therefore expire first under contention. A canceled master must be isolated from subsequent grants; longer global deadlines are not assumed.

`tb_reg_ctrl_crossbar` covers all21 pages, invalid addresses, error fallback, latched fields, response retention, exactly-once writes, withdrawal before capture/during ISSUE/after commit, deadline late-ready, reset and continuous valid. `tb_cfg_crossbar_pipeline` covers 48 continuously queued transactions across three masters plus cancellation before grant, during ISSUE, after slave commit and at the deadline. `tb_cfg_error_paths` verifies real decoder→arbiter→crossbar→stepper/time response codes with the new latency.
