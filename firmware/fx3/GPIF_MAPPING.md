# Vapor FX3 transport mapping, revision 1.1, GP01 diagnostic build

This mapping supersedes any earlier logical CTL assignment; hardware net names and FPGA package pins are unchanged. The implementation retains the Cypress synchronous two-address-bit Slave FIFO waveform table. GP01 also corrects the DQ32 GPIF_BUS_CONFIG from 0x10AF to 0x10AC: PIN_COUNT=0 selects 47 pins for DQ32, PCLK and 13 CTLs. This agrees with the installed official SDK 1.3.5 configuration. The older bundled reference uses 0x10AF. GP01 was validated on 2026-09-18 by a PING round trip and 154 CRC-valid frames with no observed PIB/DMA errors in that capture. The isolated cause of the older INVALID_STATE report was not separately proven.

See README.md for B0/B1 diagnostics and the external SDK build dependency. Mapping version remains 0x00010001 because endpoint/socket/CTL assignments are unchanged; B1 returns the distinct GP01 build marker.

| FX3 signal | GPIO | CTL | Direction from FX3 | Meaning |
|---|---:|---:|---|---|
| SLCS# | 17 | 0 | Input | Active-low chip select |
| SLWR# | 18 | 1 | Input | Active-low write strobe |
| SLOE# | 19 | 2 | Input | Active-low DQ output enable |
| SLRD# | 20 | 3 | Input | Active-low read strobe |
| TX_READY | 21 | 4 | Output | Thread 0 not full, high means space |
| RX_READY | 22 | 5 | Output | Thread 3 not empty, high means data |
| TX_WATERMARK | 23 | 6 | Output | Thread 0 above write-space watermark, high permits burst |
| PKTEND# | 24 | 7 | Input | Assert with last SLWR# and last data word |
| RX_WATERMARK | 25 | 8 | Output | Thread 3 above read-data watermark |
| Reserved | 26,27 | 9,10 | Input | Not used |
| A1 | 28 | 11 | Input | FIFO address bit 1 |
| A0 | 29 | 12 | Input | FIFO address bit 0 |
| PCLK | 16 | — | Input | FPGA-generated 50 MHz clock (validated) |

USB OUT endpoint 0x02 / UIB producer socket 2 feeds PIB consumer socket 3, selected with address 3. PIB producer socket 0, selected with address 0, feeds USB IN endpoint 0x86 / UIB consumer socket 6. DQ is 32-bit little endian. USB bulk byte counts must be a multiple of four; the upper transport protocol carries the true payload length and any final padding. The GPIF bus itself has no byte enables.

Each direction uses four 16 KiB automatic DMA buffers. AUTO_SIGNAL callbacks count buffers/errors; the CPU does not copy or commit payload buffers. SuperSpeed endpoint burst length is 16; High/Full Speed use one packet per burst. The standard example development USB identity remains 04B4:00F1.

The four flag selectors are 16, 19, 20 and 23 (thread 0 ready, thread 3 ready, thread 0 partial, thread 3 partial). CTRL_DIRECTION is 0x00011500 because each CTL occupies two direction bits. CTRL_POLARITY is 0x000001FF; the four flags are high for available data/space and low for full/empty/partial. CTRL_DEFAULT is 0x0000FE8F, leaving all four flags low while inactive. All flag meanings are dedicated to their thread and do not follow FIFO address changes.

CyU3PGpifSocketConfigure sets watermark 12 and burst argument 1 on threads 0 and 3. For a 32-bit bus, AN65974 section 8.3 gives:

- After sampling the write partial flag low, at most `watermark - 4 = 8` further write words are allowed.
- After sampling the read partial flag low, `watermark - 1 = 11` data words remain available at DQ, and SLRD# can continue for at most `watermark - 3 = 9` cycles because the read pipeline already contains two words.
- The full write flag has three-cycle latency; a master samples its updated state on the fourth edge after the final write. The empty read flag has two-cycle latency; a master samples it on the third edge after the final read.
- After entering the near-boundary region, use isolated read/write pulses with enough idle cycles for those flags to settle. Do not wait only for a partial flag to reassert: a short USB OUT packet can begin below the watermark.

The FPGA implementation uses a conservative isolated read and additional flag-settling cycles. DQ has two-cycle read latency from SLRD#, and three-cycle latency after a changed address. At 100 MHz, FX3 clock-to-DQ is at most 7 ns, clock-to-flag at most 8 ns, input setup 2 ns, strobe/address hold 0.5 ns, data hold 0 ns, and SLOE# release-to-high-Z at most 8 ns. Board routing/skew budgets must be added to these device limits.

PKTEND# must be low on the same write edge as the final data word and SLWR#. A separate PKTEND# assertion while SLWR# is high requests a zero-length packet and is not the normal short-packet termination sequence. Hold FIFO address constant through the commit and allow the FPGA's post-commit guard interval before another transaction. A DMA buffer boundary is handled by the hardware; do not read or write based on a stale ready flag during buffer switching.

GPIF_CONFIG stays 0x80000380: external clock source, synchronous mode, and SYNC_SPEED=1 for 50–100 MHz. DLL stays disabled. FX3 system clock is set above 400 MHz as required for 32-bit/100 MHz operation. The same firmware supports a 50 MHz FPGA PCLK without changing the waveform or flags; clock frequency must remain stable during an active transfer.

Evidence: Cypress AN65974 Rev. *N, pages 4 (signals), 6–9 (read/write/PKTEND timing), 11–13 (flag latency), 17–20 (watermark formulas and boundary handling); CYUSB301X datasheet pin table explicitly lists GPIO28/CTL11/A1 and GPIO29/CTL12/A0; SDK 1.3.1 `gpif_regs.h` defines the two-bit direction fields and selectors. Document reference mirror: https://github.com/NEGU93/CYUSB3KIT-003_with_SP605_xilinx at 53b78e72b7d1eb38f149856dd5333ce447d5d584. SDK source/library hashes are recorded in `SDK_PROVENANCE.json`; application/reference hashes are in `SOURCE_PROVENANCE.json` and `gp01_changes.json`. Vendor code and libraries are supplied externally; see README.md.
