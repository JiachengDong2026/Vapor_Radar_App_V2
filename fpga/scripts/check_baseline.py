#!/usr/bin/env python3
from pathlib import Path
import re, sys

ROOT = Path(__file__).resolve().parents[2]
errors = []

required = [
    'fpga/rtl/include/project_defs.vh',
    'fpga/rtl/include/stream_defs.vh',
    'fpga/rtl/include/register_map.vh',
    'fpga/rtl/include/error_codes.vh',
    'fpga/rtl/common/cdc_bit_sync.v',
    'fpga/rtl/common/cdc_pulse_sync.v',
    'fpga/rtl/common/cdc_bus_handshake.v',
    'fpga/rtl/common/sync_fifo.v',
    'fpga/rtl/common/async_fifo_wrap.v',
    'fpga/rtl/common/sample_stream_fifo.v',
    'fpga/rtl/common/msg_stream_fifo.v',
    'fpga/rtl/common/bulk_stream_fifo.v',
    'fpga/rtl/common/cfg_bus_if.v',
    'fpga/sim/common/cfg_bus_master_bfm.v',
    'fpga/sim/common/sample_stream_sink.v',
    'fpga/sim/common/msg_stream_sink.v',
    'fpga/sim/common/bulk_stream_sink.v',
    'fpga/sim/common/wms_reference_stub.v',
    'fpga/sim/common/time_sync_stub.v',
    'fpga/tests/tb_predev_common.v',
    'fpga/tests/common_synth_smoke.v',
    'fpga/vivado_check.tcl',
]
for rel in required:
    if not (ROOT / rel).exists():
        errors.append(f'missing: {rel}')

proj = (ROOT/'fpga/rtl/include/project_defs.vh').read_text(encoding='utf-8')
stream = (ROOT/'fpga/rtl/include/stream_defs.vh').read_text(encoding='utf-8')
tb = (ROOT/'fpga/tests/tb_predev_common.v').read_text(encoding='utf-8')

def require(text, pattern, msg):
    if re.search(pattern, text, re.M) is None:
        errors.append(msg)

require(proj, r'`define\s+BULK_DATA_WIDTH\s+32\b', 'BULK_DATA_WIDTH must be 32')
require(proj, r'`define\s+SAMPLE_FLAGS_WIDTH\s+8\b', 'SAMPLE_FLAGS_WIDTH must be 8')
require(proj, r'`define\s+SRC_HMP\s+16\'h0041', 'SRC_HMP must be 0x0041')
require(proj, r'`define\s+SRC_EPSILON2\s+16\'h0042', 'SRC_EPSILON2 must be 0x0042')
require(proj, r'`define\s+SRC_DILA0\s+16\'h0030', 'SRC_DILA0 must be 0x0030')
require(proj, r'`define\s+MSG_DILA_BLOCK\s+16\'h1001', 'MSG_DILA_BLOCK must be 0x1001')
require(stream, r'`include\s+"project_defs\.vh"', 'stream_defs must include project_defs')
if re.search(r'BULK_STREAM_DATA_W\s+64', stream):
    errors.append('stale 64-bit bulk width found in stream_defs')
if '16\'h0020,16\'h1100' in tb.replace(' ', ''):
    errors.append('stale HMP source 0x0020 found in common TB')
if 'sample_timestamp' in tb:
    errors.append('per-sample timestamp leaked into formal sample_stream TB')

# Simple Verilog structural sanity checks (not a replacement for Vivado compile).
for p in list((ROOT/'fpga').rglob('*.v')) + list((ROOT/'fpga').rglob('*.vh')):
    text = p.read_text(encoding='utf-8')
    stripped = re.sub(r'//.*', '', text)
    stripped = re.sub(r'/\*.*?\*/', '', stripped, flags=re.S)
    mods = len(re.findall(r'\bmodule\b', stripped))
    endmods = len(re.findall(r'\bendmodule\b', stripped))
    if mods != endmods:
        errors.append(f'{p.relative_to(ROOT)}: module/endmodule mismatch {mods}/{endmods}')

if errors:
    print('BASELINE_STATIC_CHECK_FAIL')
    for e in errors:
        print(' -', e)
    sys.exit(1)

print('BASELINE_STATIC_CHECK_PASS')
print('Required files:', len(required))
print('Frozen IDs/widths and basic Verilog structure are consistent.')
