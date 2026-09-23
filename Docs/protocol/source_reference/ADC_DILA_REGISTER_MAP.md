# Register map

32-bit byte addresses, four byte strobes, same-cycle cfg_ready. Only the owning 256-byte page responds; foreign pages return ready=error=rdata=0. Invalid offsets, unsupported writes and invalid values assert cfg_error and latch bad-config bit4. ADC0 base=0x4000, ADC1=0x4100, DILA0=0x5000, DILA1=0x5100.

CONTROL +04: bit0 enable (RW), bit1 soft reset pulse, bit2 commit pulse, bit3 clear pulse. Pulse bits read zero. A write with bit0=0 disables the channel; software must preserve enable when issuing an enabled commit (write5). Commit while already pending is rejected. Shadows can be written while pending, affecting only a subsequent commit.

## ADC pages

| Offset | Access | Meaning |
|---|---|---|
|00|RO|ID/version: 00200100 or 00210100|
|04|RW/pulse|CONTROL|
|08|RO|bit0 enable, bit1 initialized, bit2 commit pending, bit3 PHY busy, bit4 ready, bit5 FIFO>=240, bit6 overflow sticky, bit7 any error|
|0C|W1C|error bit0 timeout, bit2 dropped samples, bit4 bad cfg, bit7 initialization/frame alignment|
|10|RW shadow|Requested samples/s; ADC0 1000..1000000, ADC1 exactly12500000|
|14|RO|Actual samples/s|
|18|RO|00011800 (24-bit signed) or00011000 (16-bit signed)|
|1C|RW shadow|Expected samples per WMS cycle; zero disables DILA count check|
|20|RO|Capture FIFO level|
|24|W1C|Unified sample drop counter; write FFFFFFFF clears|
|28,2C|RO|Sample counter low/high (not latched; software may high/low/high retry)|
|30|RW shadow ADC0; fixed ADC1|ADC0 CNV width in100MHz ticks (2..20); ADC1 mode0210 only|
|34|RW shadow ADC0; RO ADC1|ADC0 BUSY timeout ticks40..1000000; ADC1 initialized|
|38|RO|ADC0 expected MODES80; ADC1 synchronization count|
|3C|RW|RAW stream enable bit0; immediate, default0|
|40|RO ADC1 only|SPI frequency5000000|

The PHY initializes at power-up even when acquisition enable is zero. ADC0 reset timing is conservative; ADC1 calibration timing follows the datasheet. ADC1 configuration does not provide hardware SPI readback or test-pattern selection in this revision.

## DILA pages

| Offset | Access | Meaning |
|---|---|---|
|00|RO|00300100 or00310100|
|04|RW/pulse|CONTROL|
|08|RO|bit0 enable, bit1 implementation ready, bit2 commit pending, bit4 enable, bit5 point level>=MAX_POINTS, bit6 overflow, bit7 any error, bit8 current time-sync valid|
|0C|W1C|error bit2 input/frame overflow, bit4 bad cfg, bit5 point lost due busy magnitude, bit6 filter saturation, bit7 sample error/invalid WMS phase|
|10|RW shadow|Independent reference frequency in mHz:1..1000000000; default1000000|
|14|RW shadow|1f phase offset, U32 turn|
|18|RW shadow|2f phase correction, U32 turn|
|1C|RW shadow|Requested output Hz;1..input_rate/8, default10000|
|20|RW shadow|MODE bit0 WMS reference (else independent), bit1 magnitude enable, bit2 LPF bypass. Bits31:3 rejected. Formats0/2 require bit1=1. Default3.|
|24|RO|LPF profile00020101 (1M) or00020102 (12.5M)|
|28|RO|Numeric descriptor20112E10: sample32, LUTQ1.17, coeff46 fractional, state16 fractional|
|2C|W1C|Input saturation count|
|30|W1C|Mixer saturation count|
|34|W1C|Filter saturation count|
|38|RO|Output point count|
|3C|RO|Total queued points in both banks|
|40|RW shadow|Fragment points1..256, default256|
|44|RO|Most recently computed fragment count|
|48|RO|Frame capacity drop count (soft reset clears)|
|4C|RO extension|Actual output Hz at most recent commit|
|50|RO extension|Committed decimation factor|
|54|RO extension|Committed independent-reference phase increment per100MHz tick|

The +4C/+50/+54 extensions occupy previously unused module offsets and do not alter frozen global IDs or widths. CLEAR empties data and resets arithmetic/cycle tracking; soft reset additionally clears counters/errors. Persistent loss or invalid phase marks partial output conservatively until the run is reset/cleared.

2026-09-16 configuration cause extension: ADC/DILA slaves append cfg_error_code[3:0]; member1_adc_dila appends cfg_error_code[15:0], with ADC0 in[3:0], ADC1[7:4], DILA0[11:8], DILA1[15:12]. All nibbles are zero outside a corresponding rejected transaction. Codes are5=unknown/unaligned address,6=read-only write,7=invalid range/reserved CONTROL bits,8=repeated commit while pending. CONTROL bits31:4 are rejected using the byte-strobe mask. Runtime acquisition timeout stays in ERROR status; it never turns a later configuration request into transaction timeout9. The lead bridge owns missing-response timeout9. Public register IDs/pages/stream widths are unchanged.

The frozen standalone member1_ad4630/member1_adc3660 projects remain their already-routed self-contained snapshots; they are not regenerated for unused telemetry/error-code ports. Current integration uses member1_adc_dila RTL and the exact declaration member1_adc_dila_ports.vh.
