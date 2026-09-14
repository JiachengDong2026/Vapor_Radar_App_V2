# PREDEV Common V1.2 Static Review

Generation baseline: repository commit `a27b717bfa3a293c8a96db255c29b1aa5799ba07`.

## Checks completed in the generation environment

- Required-file presence check: PASS.
- Frozen width/ID consistency check: PASS.
- No stale 64-bit generic bulk-stream definition: PASS.
- No stale HMP `source_id=0x0020` in the common testbench: PASS.
- Formal sample-stream testbench contains no per-sample timestamp: PASS.
- Verilog `module/endmodule`, `begin/end`, `case/endcase`, `task/endtask`,
  `function/endfunction` structural-count heuristic: PASS.
- Python baseline checker syntax: PASS.

## Dynamic HDL verification status

Not executed in this environment because Vivado/xvlog/xsim, Icarus Verilog,
Verilator and Yosys are unavailable. Dynamic verification must be run in the
project Vivado environment with:

```text
vivado -mode batch -source fpga/vivado_check.tcl
```

Expected behavioral success marker:

```text
PREDEV_COMMON_V12_PASS
```

Expected script completion marker:

```text
PREDEV_COMMON_V12_VIVADO_CHECK_DONE
```
