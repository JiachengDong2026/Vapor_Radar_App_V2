> 正式归档：2026-09-23。本文源于2026-09-16集成版本；旧文中的Test专用、V2只读和当轮未上板描述属于当时记录。当前目录、六路既有实测及本轮离线边界以[正式集成修订](../../INTEGRATION_REVISION_20260923.md)为准。

# Configuration error reason sideband — 2026-09-16

The seven integration sensor modules append `output [3:0] cfg_error_code` to their existing ports; the shared `modbus_sensor_driver` in `hmp_modbus_rs485.v` carries the same output. The existing `cfg_error` and acceptance/write behavior are unchanged. Constants are in `include/sensor_cfg_codes.vh`.

`cfg_error_code` is zero unless `cfg_ready && cfg_error` is true. The reason values are VLP command statuses from the main development guide section 5.5, not the per-device sticky error bitmap:

| Value | Meaning | Selection |
|---:|---|---|
| 0 | OK/inactive | Successful or unselected transaction |
| 5 | Bad address | Unknown register or unaligned address, read or write |
| 6 | Read-only | Write to a defined read-only register |
| 7 | Range | Invalid value, format, command, or active byte mask |
| 8 | Busy | Otherwise-valid operation prohibited by enable, transfer state or a pending commit |
| 9 | Timeout | Reserved for the bus timeout monitor; these local register pages respond immediately |

Priority is address, read-only, range, busy. If an enabled device receives an invalid baud value, it reports range 7; the same device receives busy 8 for an otherwise valid baud change. Device Modbus/UART/I2C transaction timeouts remain device diagnostics and do not become configuration timeout 9.

`member3_sensor_bank` appends the packed 28-bit output:

| Bits | Device |
|---|---|
| 3:0 | PTB210 |
| 7:4 | HMP |
| 11:8 | EPSILON |
| 15:12 | BMP390 |
| 19:16 | SHT45 |
| 23:20 | TFA1500 |
| 27:24 | RD105 |

`tb_sensor_cfg_error_codes` passes 150 directed transactions across all seven lanes: valid and inactive access, unknown/misaligned read/write, read-only writes, each device's range restrictions, busy versus range priority, pending Modbus commit, WSTRB masking, and rejected-write register retention. Run `scripts/run_cfg_error_codes.tcl`; evidence is `reports/cfg_error_codes.log`.

This change applies only to `member3_uart_sensors/rtl` and its include directory. The seven delivered independent board snapshots, XPRs, DCPs and BIT files were not changed or rebuilt. `reports/CFG_SIDEBAND_UPGRADE.json` binds each old/new driver hash; `scripts/verify_cfg_sideband_scope.py` removes only the new sideband declaration/classifier/connection and confirms all existing RTL tokens remain identical to each frozen board snapshot. The bank adds only seven four-bit connections. Final system builds consume the new integration interfaces; standalone snapshots continue using their validated original interfaces.
