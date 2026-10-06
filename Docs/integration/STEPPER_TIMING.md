> 正式归档：2026-09-23。本文源于2026-09-16集成版本；旧文中的Test专用、V2只读和当轮未上板描述属于当时记录。当前目录、六路既有实测及本轮离线边界以[正式集成修订](../INTEGRATION_REVISION_20260923.md)为准。

# DM422 motor timing — 2026-09-16 correction

Source: DM422 driver manual section 3.3, extracted at `project_audit/source_review/7-2-电机DM422驱动器说明书.txt`, lines 429–432. ENA must precede DIR by at least 5 ms; DIR must precede the PUL falling edge by at least 5 us; high and low pulse widths must each be at least 2.5 us.

START with a nonzero signed target asserts the independent ENA register and latches the requested direction. After the ENA wait, the direction register changes. A separate direction wait follows before the first pulse. Unchanged direction still receives both waits. The output enable does not decode the multibit FSM, avoiding decode glitches while phases change.

| Interval | Minimum SYS100MHz ticks | Lower bound after +100 ppm and 50 ns differential budget |
| --- | ---: | ---: |
| ENA to DIR | 500056 | 5,000,009.994 ns |
| DIR to first PUL active edge | 506 | 5,009.494 ns |
| Pulse high | 256 | 2,509.744 ns |
| Pulse low | 256 | 2,509.744 ns |

The controller waits before the leading pulse edge, so the manual's falling-edge direction requirement is also met for either supported pulse polarity. Pulse accounting remains one commanded pulse per leading logical edge; STOP completes its high and low intervals before releasing ENA. STOP in either guard exits without a pulse; STOP during ENA wait also preserves the previous direction. System or local disable uses the same stop behavior. Reset may abort a transaction immediately.

Constants scale at elaboration for `SYS_CLK_HZ` and include a 100 ppm fast-clock limit plus 50 ns for differential clock-to-pad propagation, board delay and edge uncertainty. The final routed checker must establish the three physical pads' min/max difference plus 1 ns board difference and 0.250 ns uncertainty is at most 50 ns, with 10 pF pad load. These are integration budgets, not measured PCB/cable properties. The driver wiring must match the configured pin polarity; default logical ENA assertion drives high.

At 100 MHz, the smallest period is 512 ticks. The maximum accepted frequency request is therefore `floor(100000000/512)=195312` Hz. Frequency writes use the existing sequential divider to calculate `period=floor(SYS_CLK_HZ/request)`, validate `period >= high_ticks + MIN_LOW`, then run the same divider again to calculate the integer actual-frequency readback `floor(SYS_CLK_HZ/period)`. The response occurs after both divisions; no variable combinational divider is added. Example: request 190000 Hz produces period 526 and readback 190114 Hz. Rejected writes preserve the previous frequency and period.

Registers and ports are unchanged. Register 0x6714 now explicitly reads actual integer Hz; 0x6718 high ticks defaults/minimum to 256 and 0x671c direction ticks defaults/minimum to 506 at 100 MHz. Each timing write checks the corresponding other interval. Error sideband meanings remain range=7, busy=8, not-ready=11.

Validation: `tb_stepper_ctrl` runs at a real nominal 100 MHz, checks conservative physical intervals, both directions, STOP in ENA/DIR/high/low phases, system disable, zero target, polarity, exact valid/invalid timing boundaries, quantized frequency readback and atomic rejection. `tb_cfg_error_paths`, `tb_action_controller`, and `tb_decoder_action` verify transaction compatibility. `scripts/check_stepper_route.tcl` independently opens the final full-top routed checkpoint, checks complete clock-to-pad paths, and writes `reports/stepper_pin_timing/pad_timing.txt`. Its observation constraints are not saved back to the routed design.

Motor checker API correction: Vivado2020.2 lacks reset_path. The dedicated analysis now uses reset_timing and restores board25/MMCM SYS100 plus motor observations; normal STA/CDC/skew reports must be saved first. It never saves the changed timing view. The final checker requires routed source/output nets. See project_audit/reports/CONSTRAINT_PRECHECK_REPORT.md.

Final routed validation passed on 2026-09-16 through the independent final review, which sources `check_stepper_pin_timing.tcl`. Total all-pad/edge/PVT difference including the board and uncertainty budgets is 5.397ns against the 50ns allocation. ENA-to-DIR, DIR-to-PUL, pulse-high and pulse-low margins are 54.597ns, 54.097ns, 54.347ns and 54.347ns; all four checks pass. The formal build and all 13 independent qualification gates passed with actual process exit 0, and the final DCP stayed unchanged. See motor evidence（历史来源：`E:/Documents/Vapor_Lc_App_Test/integrated_20260916/project_audit/reports/final_route_review/motor/pad_timing.txt`）, qualification（历史来源：`E:/Documents/Vapor_Lc_App_Test/integrated_20260916/project_audit/reports/final_route_review/qualification.json`）, and validation record（历史来源：`E:/Documents/Vapor_Lc_App_Test/integrated_20260916/lead_system/reports/STEPPER_TIMING_VALIDATION.md`）. These results establish the stated timing budgets, not electrical compatibility or hardware operation.
