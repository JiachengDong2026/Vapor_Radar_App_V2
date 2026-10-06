"""Independent integer recurrence and double-precision response checks."""
from pathlib import Path
import argparse
import json
import math
import re
import numpy as np
from scipy.signal import butter, sosfreqz, sosfilt

SOURCE = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
HERE = args.output.resolve()
if HERE.is_relative_to(SOURCE) or HERE in SOURCE.parents:
    parser.error('Generated vectors must stay outside the repository and its ancestors')
HERE.mkdir(parents=True, exist_ok=True)
lut_text = (SOURCE / "fpga/rtl/dila/dila_sine_lut.vh").read_text()
lut = [0] * 1024
for index, sign, value in re.findall(r"10'd(\d+): sine_lut =\s*(-?)18'sd(\d+)", lut_text):
    lut[int(index)] = int(sign + value)
assert lut[256] == 131071 and lut[768] == -131071
Q = 1 << 46

def rnd(value, shift):
    return (1 if value >= 0 else -1) * ((abs(value) + (1 << (shift-1))) >> shift)

def sine(phase):
    phase &= 0xffffffff
    cell, fraction = phase >> 22, (phase >> 10) & 4095
    return lut[cell] + rnd((lut[(cell+1) & 1023] - lut[cell]) * fraction, 12)

def mix(sample, phase):
    return [rnd(sample * sine(angle), 17) for angle in
            (phase + (1 << 30), phase, 2*phase + (1 << 30), 2*phase)]

def pack(values):
    return sum((int(value) & 0xffffffff) << (32*k) for k, value in enumerate(values))

class Biquad:
    def __init__(self, coef):
        self.coef = coef
        self.state = [[0]*4 for _ in range(4)]
    def step(self, values):
        outputs = []
        saturated = 0
        b0, b1, b2, a1, a2 = self.coef
        for k, sample in enumerate(values):
            x1, x2, y1, y2 = self.state[k]
            x = sample << 16
            raw_y = rnd(b0*x+b1*x1+b2*x2-a1*y1-a2*y2, 46)
            y = max(-(1 << 47), min((1 << 47)-1, raw_y))
            raw_out = rnd(y, 16)
            out = max(-(1 << 31), min((1 << 31)-1, raw_out))
            saturated |= int(y != raw_y or out != raw_out)
            self.state[k] = [x, x1, y, y1]
            outputs.append(out)
        return outputs, saturated

summary = {}
for rate in (1000000, 12500000):
    sos = butter(4, 1000, fs=rate, output="sos")
    coefs = []
    for section in sos:
        a1, a2 = [round(float(a)*Q) for a in section[4:]]
        b0 = round((Q+a1+a2)/4)
        coefs.append([b0, Q+a1+a2-2*b0, b0, a1, a2])
    stages = [Biquad(c) for c in coefs]
    count = rate*18//1000
    normal_count = rate//100
    normal = []
    mixed_history = []
    saturation_counts = [0, 0]
    with (HERE / f"filter_{rate}.hex").open("w") as stream:
        for n in range(count):
            if n < normal_count:
                phase = round(((n*20000/rate) % 1)*(1 << 32)) & 0xffffffff
                angle = 2*math.pi*n*20000/rate
                sample = round(4*131072 + 65536*math.cos(angle+.37) + 6554*math.cos(2*angle-.51))
            else:
                phase = 0
                sample = 2147483647 if n < rate*14//1000 else -2147483648
            mixed = mix(sample, phase)
            first, sat1 = stages[0].step(mixed)
            final, sat2 = stages[1].step(first)
            saturation_counts[0] += sat1
            saturation_counts[1] += sat2
            record = sample & 0xffffffff
            record |= phase << 32
            record |= pack(final) << 64
            record |= sat1 << 192
            record |= sat2 << 193
            stream.write(f"{record:049x}\n")
            if n < normal_count:
                normal.append(final)
                mixed_history.append(mixed)
    actual = np.asarray(normal, dtype=float)
    floating = sosfilt(sos, np.asarray(mixed_history), axis=0)
    tail = actual[rate*8//1000:]
    desired = np.array([65536/2*math.cos(.37), -65536/2*math.sin(.37),
                        6554/2*math.cos(-.51), -6554/2*math.sin(-.51)])
    h2 = 2*np.hypot(tail[:,2], tail[:,3])
    response = sosfreqz(sos, worN=[1000, 20000, 40000], fs=rate)[1]
    info = dict(coefs=coefs, count=count, saturation_counts=saturation_counts,
                response_db=(20*np.log10(abs(response))).tolist(),
                steady_mean_iq=tail.mean(axis=0).tolist(), ideal_iq=desired.tolist(),
                h2_peak_relative_error=float(np.max(abs(h2/6554-1))),
                h2_peak_to_peak=float(np.ptp(h2)),
                max_fixed_vs_float_lsb=float(np.max(abs(actual-floating))))
    assert info["h2_peak_relative_error"] < .002, info
    assert saturation_counts[1] > 0, info
    assert np.max(abs(actual-floating)) < 256, info
    summary[str(rate)] = info
(HERE / "numeric_summary.json").write_text(json.dumps(summary, indent=2))
print(json.dumps(summary, indent=2))
