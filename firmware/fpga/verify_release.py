"""Verify the archived FPGA BIT and its source inputs without changing hardware."""
import hashlib
import json
from pathlib import Path


def main():
    repo = Path(__file__).resolve().parents[2]
    release = repo / 'firmware/fpga/releases/20261113_hc2a_rhfix'
    expected_hash, bit_name = (release / 'SHA256SUMS').read_text().strip().split()
    failures = []
    bit = release / bit_name
    if not bit.is_file() or hashlib.sha256(bit.read_bytes()).hexdigest() != expected_hash:
        failures.append(bit_name)
    inputs = json.loads((release / 'source_inputs_lf.json').read_text())
    for name, expected in inputs.items():
        path = repo / name
        if not path.is_file():
            failures.append(name)
            continue
        data = path.read_bytes().replace(b'\r\n', b'\n')
        if hashlib.sha256(data).hexdigest() != expected:
            failures.append(name)
    if failures:
        raise SystemExit('RELEASE_VERIFY_FAIL: ' + ', '.join(failures))
    print(f'RELEASE_VERIFY_PASS bit=1 source_inputs={len(inputs)} (LF normalized)')


if __name__ == '__main__':
    main()
