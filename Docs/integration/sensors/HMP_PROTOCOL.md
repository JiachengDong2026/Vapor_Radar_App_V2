> 正式归档：2026-09-23。本文源于2026-09-16集成版本；旧文中的Test专用、V2只读和当轮未上板描述属于当时记录。当前目录、六路既有实测及本轮离线边界以[正式集成修订](../../INTEGRATION_REVISION_20260923.md)为准。

# HMP protocol evidence and register implementation

Official Vaisala **HMP Series with MMP8 and TMP1 User Guide M212022EN-M**, publication2025-08-19, provides the missing word-order specification. Authoritative reader: https://docs.vaisala.com/r/M212022EN-M/en-US . Retained official HTML evidence is `docs/modbus_sources/hmp_float.html`, `hmp_configuration.html`, `hmp_measurement.html`, plus document metadata/TOC.

The manual explicitly places the least-significant16-bit word at the listed register and the most-significant word at address+1. Each register still sends its high byte first. For RH50.0 (F32 42480000), the wire bytes are00 00 42 48. The driver repacks bytes into42480000 without floating-point arithmetic. RH starts0000 and T0002, so03 address0000 quantity4 reads both atomically.

Pressure compensation is persistent F32 at0300, in hPa, default1013.25 (447D5000). CONTROL.commit writes this actual device register using10 quantity2 and low-word-first bytes50 00 44 7D. Only the matching acknowledgment updates +40 confirmed pressure. The default board image merely polls; it does not rewrite persistent compensation on boot. APPLY_ON_BOOT=1 is an explicit build option for exercising writes with SETPOINT.

Frozen page6100: +10 baud(default19200), +14 slave(default240), +18 format(default1=8N2), +1C poll interval(default1000ms), +20 measurement mask(default3, RH/T bits0/1 only), +24 latest RH F32, +28 latest T F32, +2C CRC errors, +30 timeouts, +34 pressure shadow, +38 FIFO words, +3C dropped records. Mask bits beyondRH/T are rejected as unsupported rather than silently ignored. Pressure rejects nonpositive/NaN/Inf bit patterns; device-specific validity is additionally enforced by the device response.

RS485 pins: FPGA TX AN16, RX AM17, DE/RE AN19, LVCMOS18 at the FPGA side of the onboard PHY. Sensor cable: RS485+→CON19 pin5, RS485−→CON19 pin1, GND→pin3. Device power and the termination/bias arrangement must follow its installation manual and as-built harness.

Only RH, temperature and pressure compensation are implemented; dew point/purge/heating/filter controls are not silently exposed. The supplied quick guide alone did not specify F32 word order; this implementation uses the full official encoding chapter. The full PDF transfer was unreliable, so incomplete `.partial` download is not used as validation evidence; the successfully retrieved official chapter HTML is the reference.
