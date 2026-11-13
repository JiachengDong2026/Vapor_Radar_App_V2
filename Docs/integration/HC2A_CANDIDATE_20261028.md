> 历史开发记录（2026-10-28）。该修正版已于 2026-11-13 正式合入 V2，当前交付、HCD2 签名及实板验证范围以[最新说明](../LOWER_COMPUTER_RELEASE_20261113.md)为准。下文“未合入/未上板”为当时状态。

# HC2A GPIO Candidate Revision - 2026-10-28

This revision supersedes both the initial CON19 converter candidate and the intermediate CON21 replacement. The user requires TFA1500 to remain available. HC2A therefore uses a new dedicated UART on CON11 pin13 TX (AK13) and pin15 RX (AL13), both Bank88 LVCMOS33. TFA1500 keeps CON21 and CON11 pin4. AI8 retains CON19 RS-485.

The new `hc2a_roascii_uart` contains no RS-485 direction controller or shared-bus ownership. Lane1 remains the mutually exclusive HC2A/HMP logical humidity source 0x0041. HC2A ID_VERSION is 0x00410106; its page is 0x6100 and RH/T TLVs remain schema1. HMP pressure compensation/COMMIT is unsupported. TFA identity/page0x6500 and all seven stream lanes remain present. `HC2A_ENABLE=0` retains legacy HMP+AI8 and TFA, with the new GPIO TX idle high.

The TFA RTL and action-controller logic are unchanged from the prior baseline. The GPIO receive path uses the standard two-stage UART synchronizer; only the first capture has an asynchronous exception, and the second stage remains timed. The HC2A output retains the existing slow UART pad timing bound. Board pin constraints and routed-netlist CDC review are updated for the new port. The new package pins must be unique and meet LVCMOS33 in the routed design.

Development, simulation and implementation are isolated in `E:/Documents/Vapor_Lc_App_Test/hc2a_gpio_20261028_01`. Source files are not merged into V2, and no FPGA or probe has been programmed. Final test/build/input-preservation evidence is recorded in that task's `REPORT.md` and `final_result.json` after the full build completes. Earlier candidate results do not establish this revision's acceptance.

Wiring and host setup: [HC2A GPIO wiring and RO-ASCII usage](sensors/HC2A_ROASCII.md).

## Isolated diagnostic revision

2026-10-28: add read-only UART snapshot and detailed failure flags; see [diagnostic register specification](HC2A_DIAGNOSTIC_20261028.md). Original candidate and V2 are preserved. No parser acceptance criteria were changed.

## Physical HC2A RH unit compatibility fix

2026-10-28: physical firmware V1.2-1 returns `%rh`. Accept this alongside `%RH`; add the captured-frame regression and HCD2 diagnostic signature. See [evidence and scope](HC2A_RH_CASE_FIX_20261028.md).
