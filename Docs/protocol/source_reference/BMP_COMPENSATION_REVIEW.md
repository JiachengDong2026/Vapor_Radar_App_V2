# BMP390 plotting compensation

Capture date: 2026-09-18; processing date: 2026-09-19. Offline processing only; no hardware access or firmware changes.

## Formula source

Bosch Sensortec BMP390 datasheet **BST-BMP390-DS002-07, Revision 1.7 (03/2021)**:

- Table 24: calibration registers 0x31 through 0x45, byte ordering and signedness.
- Appendix 8.4: calibration coefficient scaling, page 55.
- Appendix 8.5: temperature compensation, page 55.
- Appendix 8.6: pressure compensation, page 56.

Local original PDF: `E:/Documents/Vapor_Lc_App_Test/common_baseline/Docs/【资料】FPGA设备接入手册/3-MEMS bmp390.pdf`.

Verified local text extraction: `E:/Documents/Vapor_Lc_App_Test/project_audit/source_review/3-MEMS bmp390.txt`, SHA256 `cd0bad3ee3323d46d830cef6a06a64f63e59b9cba729bcd67cf309ecc1c1e853`.

An attempt to download the official Bosch BMP3 SensorAPI from `https://raw.githubusercontent.com/boschsensortec/BMP3_SensorAPI/master/bmp3.c` timed out. No compiled SensorAPI cross-check is claimed.

## Implementation and evidence

`host/bmp_compensation.py` exposes `compensate(calibration_hex, pressure_raw, temperature_raw)` and returns `(pressure_pa, temperature_c)` using Python double precision. Calibration is interpreted as little endian with the Table 24 signedness; the pressure formula uses the compensated temperature from the same sample.

The implementation follows the polynomial printed in the datasheet. An independent arithmetic check parsed coefficients with `int.from_bytes` rather than `struct.unpack`, used 60-digit Decimal arithmetic and evaluated the pressure polynomial in Horner form. Across all 60 captured valid samples the maximum difference was **2.9103830456733704e-11 Pa** and **0 degrees C** after conversion to double precision. Invalid calibration length and ADC values outside unsigned 24-bit range were also rejected. This checks the implementation against the documented polynomial, but is not an independently sourced SensorAPI comparison or a metrological calibration.

## Captured results

Input: `reports/sensor_six_60s_01/sensor_analysis.json`, capture SHA256 `dfd3602bbf5b19c44606c045c4aa3eaf2f999360b0d12252390d2302e6a9a5b2`.

Calibration metadata: `986d4c4bf9fd1c4d1706019349005a03fa800f08f5`.

| Item | Result |
|---|---:|
| Valid BMP390 samples | 60 |
| Raw pressure minimum / maximum | 6459904 / 6463488 |
| Raw temperature minimum / maximum | 8494848 / 8500224 |
| Compensated pressure minimum | 101514.80083488561 Pa |
| Compensated pressure maximum | 101533.71153079679 Pa |
| Compensated temperature minimum | 23.51960221887566 degrees C |
| Compensated temperature maximum | 23.615761432796717 degrees C |
| First sample pressure / temperature | 101524.05066707481 Pa / 23.606603474356234 degrees C |
| Last sample pressure / temperature | 101522.58156346585 Pa / 23.533339337445796 degrees C |

These values are suitable for plots labeled **BMP390 (host compensated)**. The saved capture remains raw. Do not treat agreement with a plausible atmospheric range as proof of absolute sensor accuracy.
