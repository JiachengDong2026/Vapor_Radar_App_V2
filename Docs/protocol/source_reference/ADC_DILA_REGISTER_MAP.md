> 2026-11-16 PPS补充：WMS +4C=1选择PPS单次同步扫描，ADC页/DLIA页不新增地址。DLIA须MODE.bit0=1，ADC保持连续采样；按CNV锁存的实际DAC窗口标签筛选，窗口外数据正常丢弃。每次实际起点清SOS历史和抽取计数，正常终点封帧且不因等待态置partial，中止/错误另标。活动扫描中DLIA COMMIT返回BUSY=8，推荐停止排空后配置。自定义SOS采样率不匹配置ERROR.bit8并消费丢弃输入以完成收尾，匹配恢复前不接受新PPS。完整启动、停机和数据关联见[PPS对接规范](../PPS_WMS_DLIA_HOST_HANDOFF_20261116.md)。

> 2026-11-16：DLIA新增2～8阶主机SOS系数上传，扩展+60…+FC；完整字段、字节布局、原子提交和错误恢复以[SOS对接规范](../DLIA_SOS_HOST_HANDOFF_20261116.md)为准。默认内置profile保留，自定义profile为80000000|阶数。

> 2026-10-04：已将2026-10-02上板验证的DLIA精度版本同步至正式V2，默认ID/profile为0101/00040101。历史构建记录保留；本次范围及验证见[同步记录](../../MERGE_MANIFEST_20261004.md)。

> 2026-09-28 正式双AD4630版本以[双低速ADC修订](../../INTEGRATION_REVISION_20260928_DUAL_AD4630.md)为准；下列高速ADC页为历史源参考。

# Register map

32-bit byte addresses, four byte strobes, same-cycle cfg_ready. Only the owning 256-byte page responds; foreign pages return ready=error=rdata=0. Invalid offsets, unsupported writes and invalid values assert cfg_error and latch bad-config bit4. ADC0 base=0x4000, ADC1=0x4100, DILA0=0x5000, DILA1=0x5100.

CONTROL +04: bit0 enable (RW), bit1 soft reset pulse, bit2 commit pulse, bit3 clear pulse. Pulse bits read zero. A write with bit0=0 disables the channel; software must preserve enable when issuing an enabled commit (write5). Commit while already pending is rejected. Ordinary shadows can be written while pending, affecting only a subsequent commit; DLIA filter-upload registers reject writes while pending. DLIA commit cannot be combined with reset/clear.

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

2026-10-02 isolated precision revision: the DILA rows below describe module version0101 and the fourth-order filter. Earlier version0100 used profiles00020101/00020102. See [precision revision](../../INTEGRATION_REVISION_20261002_DLIA_PRECISION.md); the historical ADC notes above are unchanged.

| Offset | Access | Meaning |
|---|---|---|
|00|RO|00300101 or00310101 (source0030/0031, module version0101)|
|04|RW/pulse|CONTROL|
|08|RO|bit0 enable, bit1 implementation ready, bit2 commit pending, bit4 enable, bit5 point level>=MAX_POINTS, bit6 overflow, bit7 any error, bit8 current time-sync valid|
|0C|W1C|error bit2 input/frame overflow, bit4 bad cfg, bit5 point lost due busy magnitude, bit6 filter saturation, bit7 sample error/invalid WMS phase, bit8 custom SOS input-rate mismatch|
|10|RW shadow|Independent reference frequency in mHz:1..1000000000; default1000000|
|14|RW shadow|1f phase offset, U32 turn|
|18|RW shadow|2f phase correction, U32 turn|
|1C|RW shadow|Requested output Hz;1..input_rate/8, default10000|
|20|RW shadow|MODE bit0 WMS reference (else independent), bit1 magnitude enable, bit2 LPF bypass. Bits31:3 rejected. Formats0/2 require bit1=1. Default3.|
|24|RO|Built-in profile00040101 (1M) or00040102 (12.5M); custom SOS profile80000000 OR order|
|28|RO|Numeric descriptor20112E10: sample32, LUTQ1.17, coeff46 fractional, state16 fractional|
|2C|W1C|Input saturation count|
|30|W1C|Mixer saturation count|
|34|W1C|Filter saturation count: sum of saturation pulses from enabled sections (up to4)|
|38|RO|Output point count|
|3C|RO|Total queued points in both banks|
|40|RW shadow|Fragment points1..256, default256|
|44|RO|Most recently computed fragment count|
|48|RO|Frame capacity drop count (soft reset clears)|
|4C|RO extension|Actual output Hz at most recent commit|
|50|RO extension|Committed decimation factor|
|54|RO extension|Committed independent-reference phase increment per100MHz tick|
|58/5C|RW shadow / RO active|Legacy cutoff Hz; seven built-in choices; writing58 selects legacy mode for next commit|
|60/64|RW start / RO active|Write60=2..8 starts a fresh coefficient upload;0 selects legacy;64 reports active order|
|68..DC|RW shadow|30 full U32 words, packed four SOS sections x five signed48 Q2.46 coefficients|
|E0/E4|RW shadow|Design sample rate / cutoff in integer Hz|
|E8/EC|RO|Active design sample rate / declared cutoff Hz|
|F0|RO|SOS API ID534F5301|
|F4|RO|Upload flags; see SOS handoff|
|F8|RO|Successful configuration application generation|
|FC|RO|Current actual input sample rate Hz|

The +4C/+50/+54 extensions occupy previously unused module offsets and do not alter frozen global IDs or widths. CLEAR empties data and resets arithmetic/cycle tracking; soft reset additionally clears counters/errors. Persistent loss or invalid phase marks partial output conservatively until the run is reset/cleared.

The reference generator retains the1024-entry signed Q1.17 table with12-bit linear interpolation. The filter is now four pipelined SOS slots, with unused slots bypassed; the built-in four-order values remain bit exact. Arithmetic latency increases by6 clocks versus the two-slot revision. Custom mode requires a complete upload and matching actual sample rate; rate mismatch inhibits new samples and sets ERROR.bit8. MODE.bit2 bypasses all slots. See the SOS handoff for pole checks, atomic commits, odd-order placement, reset and settling behavior. Filter configuration writes are rejected while pending; this restriction does not change ordinary reference/output shadow-register behavior.

2026-09-16 configuration cause extension: ADC/DILA slaves append cfg_error_code[3:0]; member1_adc_dila appends cfg_error_code[15:0], with ADC0 in[3:0], ADC1[7:4], DILA0[11:8], DILA1[15:12]. All nibbles are zero outside a corresponding rejected transaction. Codes are5=unknown/unaligned address,6=read-only write,7=invalid range/reserved CONTROL bits,8=repeated commit while pending. CONTROL bits31:4 are rejected using the byte-strobe mask. Runtime acquisition timeout stays in ERROR status; it never turns a later configuration request into transaction timeout9. The lead bridge owns missing-response timeout9. Public register IDs/pages/stream widths are unchanged.

The frozen standalone member1_ad4630/member1_adc3660 projects remain their already-routed self-contained snapshots; they are not regenerated for unused telemetry/error-code ports. Current integration uses member1_adc_dila RTL and the exact declaration member1_adc_dila_ports.vh.
