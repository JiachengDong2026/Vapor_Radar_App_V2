"""Verify this archived BIT, build inputs and regression sources; no hardware IO."""
import hashlib
import json
from pathlib import Path


def main():
    release = Path(__file__).resolve().parent
    repo = release.parents[3]
    expected_hash, bit_name = (release / 'SHA256SUMS').read_text().strip().split()
    bit = release / bit_name
    failures = []
    if not bit.is_file() or hashlib.sha256(bit.read_bytes()).hexdigest() != expected_hash:
        failures.append(bit_name)
    counts = []
    for manifest in ('source_inputs_lf.json', 'regression_sources_lf.json'):
        inputs = json.loads((release / manifest).read_text(encoding='utf-8'))
        counts.append(len(inputs))
        for name, expected in inputs.items():
            path = repo / name
            if not path.is_file():
                failures.append(name)
                continue
            data = path.read_bytes().replace(b'\r\n', b'\n')
            if hashlib.sha256(data).hexdigest() != expected:
                failures.append(name)
    results = json.loads((release / 'regression_results.json').read_text(encoding='utf-8'))
    if len(results) != 116 or not all(item['pass'] for item in results):
        failures.append('regression_results.json')
    if failures:
        raise SystemExit('RELEASE_VERIFY_FAIL: ' + ', '.join(sorted(set(failures))))
    print('RELEASE_VERIFY_PASS bit=1 build_inputs={} regression_sources={} tests=116 '
          '(LF normalized)'.format(*counts))


if __name__ == '__main__':
    main()
