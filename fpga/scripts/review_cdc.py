"""Parse every CDC row and compare exact endpoint/clock/rule tuples."""
from pathlib import Path
import argparse
import collections
import hashlib
import json
import re

FIELDS = ('id', 'severity', 'source_clock', 'destination_clock', 'cdc_type',
          'depth', 'exception', 'source', 'destination')


def parse(path):
    context = {}
    rows = []
    summary = {}
    for number, line in enumerate(path.read_text().splitlines(), 1):
        for heading, field in [('Source Clock:', 'source_clock'),
                               ('Destination Clock:', 'destination_clock'),
                               ('CDC Type:', 'cdc_type')]:
            if line.startswith(heading):
                context[field] = line[len(heading):].strip()
        match = re.match(r'^(CDC-\d+)\s+(Info|Warning|Critical)\s+(\d+)\s+', line)
        if match:
            summary[match[1]] = int(match[3])
        if re.match(r'^\s*\d+\s+CDC-', line):
            parts = re.split(r'\s{2,}', line.strip())
            if len(parts) != 8:
                raise ValueError(f'Unparsed CDC row {path}:{number}: {parts}')
            row, rule, severity, description, depth, exception, source, dest = parts
            rows.append(dict(context, id=rule, severity=severity, depth=int(depth),
                             exception=exception, source=source, destination=dest,
                             report_line=number, description=description))
    counts = dict(collections.Counter(r['id'] for r in rows))
    if not rows or counts != summary:
        raise ValueError(f'CDC parse incomplete: {counts} versus {summary}')
    return rows


def key(row):
    return tuple(row[field] for field in FIELDS)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--baseline', type=Path, required=True)
    parser.add_argument('--current', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--repo', type=Path, help='Repository root; inferred when installed in fpga/scripts')
    args = parser.parse_args()
    repo = (args.repo or Path(__file__).resolve().parents[2]).resolve()
    if not (repo/'fpga/scripts/full_sources.tcl').is_file():
        parser.error('Cannot identify formal repository; pass --repo or install in fpga/scripts')
    args.output = args.output.resolve()
    if args.output.is_relative_to(repo) or args.output in repo.parents:
        parser.error('CDC evidence must be outside the repository and its ancestors')
    if not args.current.is_file():
        parser.error(f'Current CDC report does not exist: {args.current}')
    if not args.baseline.is_file():
        parser.error(f'CDC baseline does not exist: {args.baseline}')
    if args.baseline.suffix.lower() == '.json':
        baseline = json.loads(args.baseline.read_text())
        if baseline.get('schema_version') != 1 or baseline.get('fields') != list(FIELDS):
            parser.error('Unsupported CDC baseline schema')
        if not baseline.get('rows') or any(len(row) != len(FIELDS) for row in baseline['rows']):
            parser.error('CDC baseline rows are empty or incomplete')
        source_report_sha256 = baseline['source_report']['sha256']
        if not re.fullmatch(r'[0-9a-f]{64}', source_report_sha256):
            parser.error('Invalid original CDC report SHA256')
        old = [dict(zip(FIELDS, row)) for row in baseline['rows']]
    else:
        old = parse(args.baseline)
        source_report_sha256 = hashlib.sha256(args.baseline.read_bytes()).hexdigest()
    args.output.mkdir(parents=True, exist_ok=True)
    report = {'baseline_sha256': hashlib.sha256(args.baseline.read_bytes()).hexdigest(),
              'baseline_source_report_sha256': source_report_sha256,
              'baseline_rows': old, 'status': 'unverified'}
    current = parse(args.current)
    before = collections.Counter(key(row) for row in old)
    after = collections.Counter(key(row) for row in current)
    added = after - before
    removed = before - after
    report.update(status='exact_inventory_match' if not added and not removed else 'endpoint_review_required',
                  current_sha256=hashlib.sha256(args.current.read_bytes()).hexdigest(),
                  actual_counts=dict(collections.Counter(row['id'] for row in current)),
                  severity_counts=dict(collections.Counter(row['severity'] for row in current)),
                  exact_matches=sum((before & after).values()), current_rows=current,
                  added=[dict(zip(FIELDS, row), copies=count) for row, count in added.items()],
                  removed=[dict(zip(FIELDS, row), copies=count) for row, count in removed.items()])
    lines = ['# Exact current report entries; no count-only waiver.', 'set cdc_entries {']
    for row in current:
        if row['severity'] == 'Critical':
            values = [row[x] for x in ('id', 'source_clock', 'destination_clock', 'source', 'destination')]
            if any('}' in str(value) or '{' in str(value) for value in values):
                raise ValueError('Unexpected Tcl brace in CDC report')
            lines.append('    {' + ' '.join('{' + str(value) + '}' for value in values) + '}')
    lines.append('}')
    (args.output/'cdc_entries.tcl').write_text('\n'.join(lines)+'\n')
    (args.output/'endpoint_comparison.json').write_text(json.dumps(report, indent=2)+'\n')
    print(json.dumps({k:v for k,v in report.items() if k not in ('baseline_rows','current_rows','added','removed')},indent=2))
    if report['status'] == 'endpoint_review_required':
        print('CDC_ENDPOINT_CHANGES_REQUIRE_STRUCTURAL_REVIEW')
        raise SystemExit(1)


if __name__ == '__main__':
    main()
