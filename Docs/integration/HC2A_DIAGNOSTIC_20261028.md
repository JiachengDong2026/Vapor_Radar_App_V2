> 历史开发记录（2026-10-28）。该修正版已于 2026-11-13 正式合入 V2，当前交付、HCD2 签名及实板验证范围以[最新说明](../LOWER_COMPUTER_RELEASE_20261113.md)为准。下文“未合入/未上板”为当时状态。

# HC2A raw UART diagnostic extension (2026-10-28)

Isolated diagnostic revision of the CON11 GPIO candidate. V2 and the original delivered candidate are unchanged. Acquisition ID 0x00410106 and its public data schema are retained; debug signature 0x48434431 at 0x614C uniquely identifies this diagnostic extension. The UART, parser, timing and polling behavior are unchanged.

All added registers are read-only. 0x6150 counts decoded UART bytes including CR; 0x6154 counts framing/parity error pulses. 0x6158 is the latest complete response snapshot descriptor: bit31 valid, bit9 overflow, bit8 UART error, bits7:0 byte length excluding CR. 0x6160..0x61FC expose 160 response bytes in little-endian words, zero after the valid length. Snapshot updates atomically after CR and survives acquisition disable; disable before reading to ensure all USB reads refer to one snapshot. A timeout retains the previous complete snapshot. Software reset clears all debug state.

0x615C retains the latest failed attempt reason bitmask: bit0 timeout, bit1 checksum, bit2 length<16, bit3 overflow, bit4 UART framing, bit5 bad opening brace, bit6 bad device identifier, bit7 address mismatch, bit8 bad RDD command, bit9 field count, bit10 missing RH, bit11 missing temperature, bit12 invalid field/unit, bit13 RH range, bit14 temperature range. Header failures do not also set field-parse reasons. A later successful sample does not clear this historical reason.

This revision adds no probe writes, new output pins, or enable defaults. It is for volatile FPGA debugging, not a flash or V2 release. The extended existing HC2A bench checks raw-byte content, snapshot length/flags, read-only access, checksum/timeout reasons and reset behavior; normal HC2A+AI8+TFA regressions and implementation gates must also pass before loading.
