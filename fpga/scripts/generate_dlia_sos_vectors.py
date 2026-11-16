"""Generate custom-SOS cases and an independent integer arithmetic oracle."""
import argparse
import json
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'host'))
from dlia_filter_coefficients import generate_dlia_filter

COUNT = 2048


def rounded(value, fractional):
    return (1 if value >= 0 else -1) * ((abs(value) + (1 << (fractional-1))) >> fractional)


def clipped(value, bits):
    return max(-(1 << (bits-1)), min((1 << (bits-1))-1, value))


def generate(output):
    output.mkdir(parents=True, exist_ok=True)
    configs, expected, inputs, summary = [], [], [], []
    rng = random.Random(0x534f5301)
    for rate in (500000, 1000000, 12500000):
        for order in range(2, 9):
            for cutoff in (1250, 10000):
                design = generate_dlia_filter(rate, cutoff, order)
                configs += [rate, order, cutoff, *design.register_words]
                histories = [[0, 0, 0, 0] for _ in range(4)]
                saturated_count = 0
                for n in range(COUNT):
                    # Step, impulse, full-scale alternating and seeded noise.
                    sample = (100000000 if n < 512 else 0 if n < 1024 else
                              ((1 << 31)-1 if n%2 else -(1 << 31)) if n < 1280 else rng.randint(-(1 << 31), (1 << 31)-1))
                    inputs.append(sample & 0xffffffff)
                    value = rounded(sample * 131071, 17)  # phase-zero mixer I
                    mask = 0
                    for s, coefficients in enumerate(design.sections_q46):
                        b0,b1,b2,a1,a2 = coefficients
                        x1,x2,y1,y2 = histories[s]
                        x = value << 16
                        state_unclipped = rounded(b0*x + b1*x1 + b2*x2 - a1*y1 - a2*y2, 46)
                        state = clipped(state_unclipped, 48)
                        output_unclipped = rounded(state, 16)
                        value = clipped(output_unclipped, 32)
                        mask |= int(state != state_unclipped or value != output_unclipped) << s
                        histories[s] = [x, x1, state, y1]
                    saturated_count += mask.bit_count()
                    expected.append((mask << 32) | (value & 0xffffffff))
                summary.append(dict(rate=rate, order=order, cutoff=cutoff, samples=COUNT, saturation_pulses=saturated_count))
    for name, data, width in [('sos_config.hex', configs, 8), ('sos_input.hex', inputs, 8), ('sos_expected.hex', expected, 9)]:
        (output/name).write_text(''.join(f'{v:0{width}x}\n' for v in data), encoding='ascii')
    (output/'sos_summary.json').write_text(json.dumps(summary, indent=2)+'\n')
    print(f'SOS_VECTORS_PASS cases={len(summary)} samples={len(inputs)}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    generate(parser.parse_args().output)
