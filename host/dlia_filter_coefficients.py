"""Generate and pack DLIA Butterworth SOS coefficients for the FPGA register API."""
from __future__ import annotations

from dataclasses import dataclass
import argparse
import json
from pathlib import Path

from scipy.signal import butter

Q46 = 1 << 46
COEFFICIENTS_PER_SECTION = 5
SECTION_COUNT = 4
WORD_COUNT = SECTION_COUNT * COEFFICIENTS_PER_SECTION * 48 // 32


@dataclass(frozen=True)
class DliaFilter:
    sample_rate_hz: int
    cutoff_hz: int
    order: int
    sections_q46: tuple[tuple[int, int, int, int, int], ...]
    register_words: tuple[int, ...]


def _quantize(value: float) -> int:
    quantized = round(value * Q46)
    if not -(1 << 47) <= quantized < (1 << 47):
        raise ValueError("SOS coefficient does not fit signed Q2.46")
    return quantized


def _stable(a1: int, a2: int) -> bool:
    # Denominator is 1 + a1*z^-1 + a2*z^-2.
    return Q46 + a1 + a2 > 0 and Q46 - a1 + a2 > 0 and Q46 - a2 > 0


def generate_dlia_filter(sample_rate_hz: int, cutoff_hz: int, order: int) -> DliaFilter:
    if type(sample_rate_hz) is not int or not 0 < sample_rate_hz <= 0xffffffff:
        raise ValueError("sample_rate_hz must be positive")
    if type(order) is not int or not 2 <= order <= 8:
        raise ValueError("order must be from 2 through 8")
    if type(cutoff_hz) is not int:
        raise ValueError("cutoff_hz must be an integer number of hertz")
    if not 0 < cutoff_hz < sample_rate_hz / 2:
        raise ValueError("cutoff_hz must be between zero and the Nyquist frequency")

    sos = butter(order, cutoff_hz, btype="lowpass", fs=sample_rate_hz, output="sos")
    sections: list[tuple[int, int, int, int, int]] = []
    # Normalize every section to unity DC gain, avoiding tiny first-section
    # gains and >Q2.46 numerator coefficients in SciPy's default gain layout.
    # Put the one-pole section LAST so order=N activates ceil(N/2) sections.
    rows = sorted(sos, key=lambda row: (row[5] == 0, row[5]))
    for row in rows:
        a1, a2 = (_quantize(value / row[3]) for value in row[4:6])
        dc_numerator = Q46 + a1 + a2
        first_order = row[5] == 0
        if first_order:
            b0 = round(dc_numerator / 2)
            b1, b2 = dc_numerator - b0, 0
        else:
            b0 = round(dc_numerator / 4)
            b2, b1 = b0, dc_numerator - 2 * b0
        section = (b0, b1, b2, a1, a2)
        if any(not -(1 << 47) <= value < (1 << 47) for value in section):
            raise ValueError("Normalized numerator does not fit signed Q2.46")
        if not _stable(section[3], section[4]):
            raise ValueError("SOS became unstable after Q2.46 quantization")
        sections.append(section)

    identity = (Q46, 0, 0, 0, 0)
    if len(sections) > SECTION_COUNT:
        raise ValueError("filter requires more than four SOS sections")
    sections.extend([identity] * (SECTION_COUNT - len(sections)))

    payload = b"".join(value.to_bytes(6, "little", signed=True) for section in sections for value in section)
    words = tuple(int.from_bytes(payload[offset:offset + 4], "little") for offset in range(0, len(payload), 4))
    if len(words) != WORD_COUNT:
        raise AssertionError("coefficient bank packing produced an unexpected word count")
    return DliaFilter(sample_rate_hz, cutoff_hz, order, tuple(sections), words)


def register_writes(design: DliaFilter, base: int = 0x5000) -> list[tuple[int, list[int]]]:
    """Ordered WRITE_REG requests, WITHOUT commit/enable or USB/hardware access.

    Read capability 0x534f5301 at base+0xF0 and actual rate at base+0xFC first.
    Wait for each write ACK, read back, then separately commit and poll pending.
    """
    if base not in (0x5000, 0x5100):
        raise ValueError("base must select DLIA0 or DLIA1")
    return [(base + 0x60, [design.order]),
            (base + 0xE0, [design.sample_rate_hz, design.cutoff_hz]),
            (base + 0x68, list(design.register_words))]


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sample-rate", type=int, required=True)
    parser.add_argument("--cutoff", type=int, required=True)
    parser.add_argument("--order", type=int, required=True)
    parser.add_argument("--channel", type=int, choices=(0, 1), default=0)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    design = generate_dlia_filter(args.sample_rate, args.cutoff, args.order)
    data = dict(api_id="0x534f5301", sample_rate_hz=design.sample_rate_hz,
                cutoff_hz=design.cutoff_hz, order=design.order,
                sections_q46=design.sections_q46,
                writes=[dict(address=f"0x{address:04X}", words=[f"0x{v:08X}" for v in values])
                        for address, values in register_writes(design, 0x5000 + 0x100 * args.channel)])
    args.output.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
