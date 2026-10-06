# Register map

Frozen public offsets and widths come directly from the read-only public `register_map.vh`; none are changed. All values are 32 bits. WMS0/1 base=0x2000/0x2100; DAC0/1 base=0x3000/0x3100.

## Common

| Offset | Name | Access | Definition |
|---|---|---|---|
|00|ID_VERSION|RO|module ID[31:16], major=1[15:8], minor=3[7:0]|
|04|CONTROL|RW/strobe|bit0 enable; bit1 soft reset; bit2 commit; bit3 no-FIFO no-op; DAC only bit4 hardware clear; higher bits error|
|08|STATUS|RO|bit0 enabled, bit1 ready, bit2 config pending, bit3 busy, bit4 online, bit6 WMS overrun, bit7 sticky error, bit8 time sync|
|0C|ERROR|W1C|public CONFIG_RANGE bit4; WMS local UPDATE_OVERRUN bit8|

WMS IDs use frozen SRC_WMS0=0x0010/SRC_WMS1=0x0011. DAC default diagnostic module IDs 0x0012/0x0013 are local parameter defaults, **not new public stream source IDs**. DAC emits no stream records. Online/ready indicate completed local initialization, not acknowledged device presence. SPI has no ACK and readback is disabled.

## WMS

All RW waveform registers are shadow and apply together on commit.

|Offset|Name|Access|Reset|
|---|---|---|---|
|10|SAW_FREQ_MHZ (millihertz)|RW|100000|
|14|SAW_AMPL_Q31|RW|0x20000000|
|18|SAW_OFFSET_Q31|RW|0|
|1C|SINE_FREQ_MHZ (millihertz)|RW|1000000|
|20|SINE_AMPL_Q31|RW|0x10000000|
|24|SINE_PHASE_U32|RW|0|
|28|DAC_UPDATE_HZ_REQ|RW|100000|
|2C|DAC_UPDATE_HZ_ACT|RO|0 until commit|
|30|CYCLE_ID|RO|0|
|34|LAST_SCAN_TICK_LO|RO|0|
|38|LAST_SCAN_TICK_HI|RO|0|
|3C|SAT_COUNT|W1C|0|
|40|PHASE_MODE|RW shadow|1; bits0–1 only|
|44|UPDATE_OVERRUN_COUNT (local extension)|W1C|0|
|48|PERIOD_TICKS (local extension)|RO|1000|

LAST_SCAN_TICK is captured from timestamp_now on scan_start. Read high/low/high and retry on high change if coherent access across a scan is required. Requested rate zero, rate above transport capacity, zero saw frequency, saw increment rounding to zero, or saw/sine above actual Nyquist cause commit error. Zero sine frequency is valid. Signed amplitudes/offset accept the full Q1.31 range; clipping is counted, not rejected.

## DAC

All RW transport/mapping registers are shadow, including legacy entries that simply say RW in the task book. Commit applies them as one set while idle.

|Offset|Name|Access|Reset|
|---|---|---|---|
|10|DEVICE_CTRL|RW|0x312|
|14|CLEAR_CODE|RW|0x80000|
|18|MIN_CODE|RW|0|
|1C|MAX_CODE|RW|0xFFFFF|
|20|LAST_CODE|RO|0; init then 0x80000|
|24|SPI_CLK_HZ requested|RW|20000000|
|28|WRITE_COUNT|RO|0; counts completed sample writes, excludes initialization|
|2C|SPI_ERROR_COUNT|RO|0; no ACK/readback/timeout mechanism claimed|
|30|DEVICE_ID_RAW|RO|0; AD5791 has no ID register|
|34|GAIN_UQ2_30 (local extension)|RW|0x40000000 = 1|
|38|OFFSET_CODE_I32 (local extension)|RW|0|
|3C|SPI_CLK_HZ_ACT (local extension)|RO|16666666|
|40|MAX_UPDATE_HZ (local extension)|RO|609756|
|44|CLAMP_COUNT (local extension)|W1C|0|

Valid code limits and clearcode are 20 bits, min<=clear<=max. Gain is unsigned UQ2.30, range 0 through just below 4. Offset is signed integer DAC codes. SPI request must be 1..20,000,000 Hz. DEVICE_CTRL reserves bits31:10 and bit0; binary bit4 and RBUF bit1 must stay set for the implemented board mapping. LINCOMP accepts only documented codes 0,9,10,11,12. SDODIS/DACTRI/OPGND can be configured explicitly; they can intentionally disable/clamp analog output despite successful digital writes.
