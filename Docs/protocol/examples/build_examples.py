"""Rebuild small examples from saved files only. Never accesses USB/hardware.

Usage: python -B build_examples.py PATH_TO_fx3_gpif_debug_20260918
Writes only beside this script; imports the existing offline analysis read-only.
"""
import hashlib
import importlib.util
import json
from pathlib import Path
import struct
import sys

sys.dont_write_bytecode = True
from vlp_reference import StreamParser, describe, pack_ping, pack_read, pack_write


def sha(data):
    return hashlib.sha256(data).hexdigest()


def write_json(path, data):
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False, allow_nan=False) + '\n',
                    encoding='utf-8')


def main():
    source = Path(sys.argv[1]).resolve()
    output = Path(__file__).resolve().parent
    capture_dir = source / 'reports' / 'sensor_six_60s_01'
    sys.path.insert(0, str(source / 'host'))
    spec = importlib.util.spec_from_file_location('existing_sensor_analysis', source / 'host' / 'analyze_sensors.py')
    analysis = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(analysis)

    golden = []
    requests = [('ping', pack_ping(), 'Generated from integrated RTL; echo=ASCII PING.'),
                ('read_system_0000', pack_read(0, 5, 2), 'Byte-equal to commands/read_system.bin; five registers starting at byte address 0x0000.'),
                ('enable_ptb210', pack_write(0x6004, [1], 1009), 'Byte-equal to reports/sensor_six_60s_01/request_1009.bin. Bytes only; no execution.')]
    assert requests[1][1] == (source / 'commands' / 'read_system.bin').read_bytes()
    assert requests[2][1] == (capture_dir / 'request_1009.bin').read_bytes()
    for name, raw, provenance in requests:
        parser = StreamParser(word_padding=False)
        frame, = parser.feed(raw)
        golden.append(dict(name=name, provenance=provenance, bytes=len(raw),
                           sha256=sha(raw), frame_hex=raw.hex(' '), decoded=describe(frame)))
    recorded = []
    for name, path in [('ping_response', source / 'reports' / 'continuous_capture_01' / 'ping_response_seq1.bin'),
                       ('read_response', capture_dir / 'response_1002.bin'),
                       ('enable_ptb_response', capture_dir / 'response_1009.bin')]:
        raw = path.read_bytes()
        parser = StreamParser(word_padding=False)
        frame, = parser.feed(raw)
        recorded.append(dict(name=name, origin=str(path.relative_to(source)),
                             frame_hex=raw.hex(' '), bytes=len(raw), sha256=sha(raw),
                             decoded=describe(frame)))
    write_json(output / 'golden_vectors.json', dict(protocol='VLP 1.0',
        note='Offline bytes only. Recorded response timestamps/cycles are observations, not fixed response expectations; match request sequence/source/message. Recorded READ response sequence is 1002, whereas read_system golden request sequence is 2.',
        requests=golden, recorded_responses=recorded))

    selected = []
    found = set()
    wanted = {0x40, 0x42, 0x43, 0x44, 0x45, 0x46}
    metadata = False
    parser = StreamParser()
    full_sha = hashlib.sha256()
    full_bytes = 0
    with (capture_dir / 'bulk_in.bin').open('rb') as capture:
        while True:
            chunk = capture.read(65536)
            if not chunk:
                break
            full_sha.update(chunk)
            full_bytes += len(chunk)
            for frame in parser.feed(chunk):
                h = frame.header
                select = False
                if h['kind'] == 2 and h['sequence'] in (1002, 1009):
                    select = True
                if h['kind'] == 0x10 and h['source'] in wanted:
                    padded = frame.raw + b'\0' * (-len(frame.raw) % 4)
                    # Only small candidate frames are expanded to analysis JSON.
                    if h['source'] not in found or (h['source'] == 0x43 and not metadata):
                        decoded = analysis.analyze(padded)['frames'][0]
                        if decoded['classification'] in ('valid_sample', 'flagged_sample') and h['source'] not in found:
                            found.add(h['source'])
                            select = True
                        elif decoded['classification'] == 'metadata' and not metadata:
                            metadata = True
                            select = True
                if select:
                    selected.append(frame)
    assert not parser.finish()
    assert parser.discarded_bytes == 0 and not parser.buffer
    assert found == wanted and metadata
    sample = bytearray()
    provenance = []
    for frame in selected:
        raw = frame.raw + b'\0' * (-len(frame.raw) % 4)
        provenance.append(dict(example_offset=len(sample), original_offset=frame.offset,
                               padded_bytes=len(raw), sha256=sha(raw)))
        sample.extend(raw)
    (output / 'capture_example.bin').write_bytes(sample)
    summary = analysis.analyze(bytes(sample))
    assert summary['stream_integrity_ok']
    assert all(summary['sources']['0x%04X' % src]['sensor_records'] for src in wanted)
    summary['provenance'] = dict(original_file=str((capture_dir / 'bulk_in.bin').resolve()),
        original_bytes=full_bytes, original_sha256=full_sha.hexdigest(),
        original_parser_statistics=parser.statistics(), selected_frames=provenance,
        selection='Original byte order, first structurally decoded sample for each of six sensors (AI8 is flagged, not healthy), first BMP390 metadata, and actual READ/WRITE replies at seq1002/1009. Noncontiguous excerpts concatenated without changing bytes; sequence gaps are intentional. Sample timing is unsuitable for rate/loss statistics.')
    write_json(output / 'capture_example_summary.json', summary)
    print(json.dumps(dict(example_bytes=len(sample), example_frames=len(selected),
                          original_bytes=full_bytes, original_frames=parser.frame_count,
                          six_sources_present=found == wanted,
                          all_six_healthy=summary['all_six_have_valid_samples'])))


if __name__ == '__main__':
    main()
