"""BMP390 host-side compensation of captured raw ADC samples.

Source: Bosch BMP390 datasheet BST-BMP390-DS002-07, Rev 1.7 (03/2021),
Table 24 and appendix sections 8.4--8.6, pages 55--56.
The calibration bytes are registers 0x31..0x45 in ascending order.
"""

import struct


def compensate(calibration_hex, pressure_raw, temperature_raw):
    """Return (pressure in Pa, temperature in degrees C).

    calibration_hex is a 21-byte hexadecimal string (spaces accepted), or
    bytes. Inputs must be unsigned 24-bit ADC counts from the same sensor.
    This is an offline physical-unit conversion, not a sensor accuracy test.
    """
    calibration = (bytes.fromhex(calibration_hex)
                   if isinstance(calibration_hex, str)
                   else bytes(calibration_hex))
    if len(calibration) != 21:
        raise ValueError("BMP390 calibration must contain exactly 21 bytes")
    for name, value in (("pressure_raw", pressure_raw),
                        ("temperature_raw", temperature_raw)):
        if isinstance(value, bool) or int(value) != value or not 0 <= value < 2**24:
            raise ValueError(name + " must be an unsigned 24-bit integer")

    t1, t2, t3, p1, p2, p3, p4, p5, p6, p7, p8, p9, p10, p11 = (
        struct.unpack("<HHbhhbbHHbbhbb", calibration)
    )
    t1 = t1 * 2.0**8
    t2 = t2 / 2.0**30
    t3 = t3 / 2.0**48
    p1 = (p1 - 2**14) / 2.0**20
    p2 = (p2 - 2**14) / 2.0**29
    p3 = p3 / 2.0**32
    p4 = p4 / 2.0**37
    p5 = p5 * 2.0**3
    p6 = p6 / 2.0**6
    p7 = p7 / 2.0**8
    p8 = p8 / 2.0**15
    p9 = p9 / 2.0**48
    p10 = p10 / 2.0**48
    p11 = p11 / 2.0**65

    delta = float(temperature_raw) - t1
    temperature_c = delta * t2 + delta * delta * t3
    temp2 = temperature_c * temperature_c
    temp3 = temp2 * temperature_c
    raw = float(pressure_raw)
    offset = p5 + p6 * temperature_c + p7 * temp2 + p8 * temp3
    linear = raw * (p1 + p2 * temperature_c + p3 * temp2 + p4 * temp3)
    nonlinear = raw * raw * (p9 + p10 * temperature_c) + raw * raw * raw * p11
    return offset + linear + nonlinear, temperature_c
