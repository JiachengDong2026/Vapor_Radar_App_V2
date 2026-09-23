"""Offline VLP1 sensor/health analysis. Never opens USB or writes device registers.

Input files are concatenated in argument order before parsing; USB transfer
boundaries have no framing meaning. Uses analyze_capture for VLP validation.
"""
import argparse
import collections
import hashlib
import json
import math
from pathlib import Path
import struct

from analyze_capture import analyze as analyze_vlp

SOURCES = {0x40: 'PTB210', 0x41: 'HMP', 0x42: 'EPSILON', 0x43: 'BMP390',
           0x44: 'SHT45', 0x45: 'TFA1500', 0x46: 'AI8'}
EXPECTED = [0x40, 0x42, 0x43, 0x44, 0x45, 0x46]
ERRORS = ['timeout', 'protocol_or_crc', 'fifo_overflow', 'device_not_ready',
          'config_range', 'cdc_or_internal', 'device_reported_error', 'data_format']
TAGS = {1: 'device_status', 2: 'device_error', 3: 'raw_frame', 4: 'sample_counter',
        5: 'device_time_raw', 0x10: 'temperature_mC', 0x11: 'humidity_milli_pct',
        0x12: 'pressure_mPa', 0x13: 'distance_mm', 0x14: 'target_temperature_uC',
        0x15: 'actual_temperature_uC', 0x460: 'pv_raw', 0x461: 'sp_raw',
        0x462: 'sv_raw', 0x463: 'op_raw', 0x464: 'alarm', 0x465: 'control',
        0x466: 'host_status', 0x467: 'set_result'}
FORMATS = {1: 'B', 2: 'H', 3: 'I', 4: 'Q', 5: 'b', 6: 'h', 7: 'i', 8: 'q',
           9: 'f', 10: 'd', 13: 'B'}


def parse_stream(data):
    """Keep valid complete frames while explicitly accounting for every lost byte."""
    frames, issues = [], []
    offset = 0
    while offset < len(data):
        if len(data) - offset < 40:
            issues.append(dict(offset=offset, bytes=len(data)-offset, issue='trailing_partial_header'))
            break
        if data[offset:offset+4] != b'VLP1' or data[offset+4:offset+6] != b'\x01\x00' or data[offset+7] != 10:
            next_offset = data.find(b'VLP1', offset+1)
            stop = next_offset if next_offset >= 0 else len(data)
            issues.append(dict(offset=offset, bytes=stop-offset, issue='unframed_bytes'))
            offset = stop
            continue
        total = struct.unpack_from('<I', data, offset+8)[0]
        payload_len = struct.unpack_from('<I', data, offset+36)[0]
        if total != 44 + payload_len or total < 44:
            issues.append(dict(offset=offset, bytes=1, issue='invalid_length'))
            offset += 1
            continue
        padded = (total+3) & ~3
        if offset+padded > len(data):
            issues.append(dict(offset=offset, bytes=len(data)-offset,
                               issue='trailing_partial_frame', expected_bytes=padded))
            break
        try:
            frame = analyze_vlp(data[offset:offset+padded])['frames'][0]
        except ValueError as error:
            issues.append(dict(offset=offset, bytes=padded, issue=str(error)))
            offset += padded
            continue
        frame.update(offset=offset, index=len(frames)+1)
        frames.append(frame)
        offset += padded
    return frames, issues


def tlv_decode(payload, source):
    if len(payload) < 4:
        raise ValueError('missing TLV record header')
    schema, count = struct.unpack_from('<HH', payload)
    if schema != (2 if source == 0x46 else 1):
        raise ValueError('unexpected sensor schema %d' % schema)
    cursor, entries, values = 4, [], {}
    for _ in range(count):
        if cursor+4 > len(payload):
            raise ValueError('truncated TLV header')
        tag, kind, length = struct.unpack_from('<HBB', payload, cursor)
        expected_type = {1: 3, 2: 3, 4: 3, 0x10: 7, 0x11: 3, 0x12: 7,
                         0x13: 3, 0x14: 7, 0x15: 7}.get(tag)
        if source == 0x43 and tag in (0x100, 0x101, 0x102):
            expected_type = 11 if tag == 0x100 else 3
            if tag == 0x100 and length != 21:
                raise ValueError('BMP390 calibration must contain 21 bytes')
        if source == 0x46 and 0x460 <= tag <= 0x467:
            expected_type = 7 if tag <= 0x462 else 3
        if expected_type is not None and kind != expected_type:
            raise ValueError('unexpected type for known TLV tag %04X' % tag)
        cursor += 4
        raw = payload[cursor:cursor+length]
        if len(raw) != length:
            raise ValueError('truncated TLV value')
        cursor += length
        end = (cursor+3) & ~3
        if end > len(payload) or any(payload[cursor:end]):
            raise ValueError('missing or nonzero TLV padding')
        cursor = end
        if kind in FORMATS:
            fmt = '<'+FORMATS[kind]
            if struct.calcsize(fmt) != length:
                raise ValueError('wrong TLV scalar size')
            value = struct.unpack(fmt, raw)[0]
            if isinstance(value, float) and not math.isfinite(value):
                value = str(value)
        elif kind in (11, 12):
            value = raw.hex() if kind == 11 else raw.decode('ascii', errors='replace')
        else:
            raise ValueError('unknown TLV type %d' % kind)
        name = TAGS.get(tag, 'tag_%04X' % tag)
        if source == 0x43:
            name = {0x100: 'calibration_raw_21bytes', 0x101: 'pressure_adc_raw',
                    0x102: 'temperature_adc_raw'}.get(tag, name)
        elif source == 0x41:
            name = {0x100: 'humidity_pct', 0x101: 'temperature_C'}.get(tag, name)
        if name in values:
            raise ValueError('duplicate TLV tag %04X' % tag)
        values[name] = value
        entries.append(dict(tag='0x%04X' % tag, type=kind, length=length, name=name, value=value))
    if cursor != len(payload):
        raise ValueError('bytes remaining after TLV record')
    scales = {'temperature_mC': ('temperature_C', 1000),
              'humidity_milli_pct': ('humidity_pct', 1000),
              'pressure_mPa': ('pressure_Pa', 1000),
              'target_temperature_uC': ('target_temperature_C', 1000000),
              'actual_temperature_uC': ('actual_temperature_C', 1000000)}
    for name, (converted, divisor) in scales.items():
        if name in values:
            values[converted] = values[name]/divisor
    if source == 0x46:
        for name in ('pv', 'sp', 'sv'):
            if name+'_raw' in values:
                values[name+'_C'] = values[name+'_raw']/10
    return dict(schema=schema, tlv_count=count, tlvs=entries, values=values)


def crc8(data):
    result = 0
    for byte in data:
        result ^= byte
        for _ in range(8):
            result = (result >> 1) ^ (0x8c if result & 1 else 0)
    return result


def crc16(data):
    result = 0
    for byte in data:
        result ^= byte << 8
        for _ in range(8):
            result = ((result << 1) ^ (0x1021 if result & 0x8000 else 0)) & 0xffff
    return result


def epsilon_decode(raw):
    if len(raw) < 8 or raw[0] != 0xfc or raw[-1] != 0xfd or len(raw) != raw[2]+8:
        raise ValueError('invalid FDILink envelope/length')
    values = dict(fdilink_id='0x%02X' % raw[1], fdilink_sequence=raw[3],
                  payload_length=raw[2], header_crc_ok=crc8(raw[:4]) == raw[4],
                  payload_crc_ok=crc16(raw[7:-1]) == int.from_bytes(raw[5:7], 'big'),
                  payload_hex=raw[7:-1].hex())
    payload = raw[7:-1]
    if raw[1] == 0x50 and len(payload) == 102:
        values['navigation_status_raw'] = int.from_bytes(payload[2:6], 'little')
        values['utc_initialized'] = bool(payload[2] & 8)
        values['utc_seconds_raw'], values['utc_microseconds_raw'] = struct.unpack_from('<II', payload, 6)
    elif raw[1] == 0x53 and len(payload) == 4:
        values['utc_initialized'] = bool(payload[2] & 8)
    elif raw[1] == 0x51 and len(payload) == 8:
        values['utc_seconds_raw'], values['utc_microseconds_raw'] = struct.unpack('<II', payload)
    return dict(values=values, note='CRC-valid FDILink proves communication only. Indoor operation without an antenna may have no GNSS fix; position/time validity is not assumed.')


def decode_health(frame, payload):
    msg = frame['message']
    if len(payload) != 32:
        raise ValueError('health payload must contain eight u32 words')
    words = struct.unpack('<8I', payload)
    if words[0] != 1:
        raise ValueError('unsupported health schema')
    if msg == 0x1400:
        return dict(schema=words[0], system_status=words[1], error_summary=words[2],
                    online_mask=words[3], event_drop_count=words[5],
                    total_drop_count=words[6], reset_reason=words[7])
    if msg == 0x1401:
        result = dict(schema=words[0], page=words[1], status=words[2], errors=words[3], present=bool(words[4]))
    else:
        result = dict(schema=words[0], page=words[1], errors=words[2], new_errors=words[3], status=words[4])
    result.update(enabled=bool(result['status'] & 1), online=bool(result['status'] & 16),
                  error_names=[name for bit, name in enumerate(ERRORS) if result['errors'] & (1 << bit)])
    return result


def analyze(data):
    frames, issues = parse_stream(data)
    sources = {source: dict(name=name, frames=0, crc_fail=0, sensor_records=0,
                            valid_samples=0, flagged_samples=0, metadata_records=0,
                            invalid_records=0, health_records=0, values={},
                            message_counts=collections.Counter()) for source, name in SOURCES.items()}
    counts = collections.Counter()
    for frame in frames:
        source, msg, kind = frame['source'], frame['message'], frame['kind']
        frame['source_name'] = SOURCES.get(source, 'other')
        stat = sources.get(source)
        if stat is not None:
            stat['frames'] += 1
            stat['message_counts']['%02X/%04X' % (kind, msg)] += 1
        frame['classification'] = 'other_or_diagnostic'
        if not frame['crc_ok']:
            frame['classification'] = 'crc_failure'
            if stat is not None:
                stat['crc_fail'] += 1
            counts[frame['classification']] += 1
            continue
        payload = bytes.fromhex(frame['payload_hex'])
        try:
            if (kind, msg) in ((0x12, 0x1400), (0x12, 0x1401), (0x11, 0x1402)):
                frame['classification'] = 'health'
                frame['decoded'] = decode_health(frame, payload)
                if stat is not None:
                    stat['health_records'] += 1
                    stat['latest_health'] = dict(frame['decoded'], timestamp_ticks=frame['timestamp_ticks'])
            elif stat is not None and kind == 0x10 and msg == (0x1200 if source == 0x42 else 0x1100):
                stat['sensor_records'] += 1
                decoded = epsilon_decode(payload) if source == 0x42 else tlv_decode(payload, source)
                frame['decoded'] = decoded
                values = decoded['values']
                reasons = []
                if not frame['flags'] & 1:
                    reasons.append('valid flag not set')
                if frame['flags'] & 16:
                    reasons.append('device error flag set')
                if frame['flags'] & 8:
                    reasons.append('overflow flag set')
                required = {0x40: ['pressure_mPa'], 0x44: ['temperature_mC', 'humidity_milli_pct'],
                            0x45: ['distance_mm'], 0x46: ['pv_raw', 'sp_raw', 'device_status']}.get(source, [])
                if any(name not in values for name in required):
                    raise ValueError('required sensor fields missing')
                if source == 0x42 and not (values['header_crc_ok'] and values['payload_crc_ok']):
                    raise ValueError('FDILink CRC failure')
                if source == 0x46:
                    status = values['device_status']
                    decoded['online'] = bool(status & 1)
                    decoded['transport_error'] = (status >> 1) & 15
                    decoded['exception_code'] = (status >> 5) & 255
                    if not decoded['online'] or decoded['transport_error'] or decoded['exception_code']:
                        reasons.append('AI8 offline/transport failure; numeric values may be stale')
                    if values.get('alarm', 0) or values.get('host_status', 0) & 0x300:
                        reasons.append('AI8 alarm/host error')
                metadata = source == 0x43 and 'calibration_raw_21bytes' in values
                if source == 0x43:
                    decoded['note'] = 'Pressure and temperature ADC counts are raw, not Pa or degrees C; Bosch calibration/compensation is not applied.'
                    if not metadata and not any(k in values for k in ('pressure_adc_raw', 'temperature_adc_raw')):
                        raise ValueError('BMP390 sample has no ADC fields')
                frame['classification'] = 'metadata' if metadata else ('flagged_sample' if reasons else 'valid_sample')
                frame['health_reasons'] = reasons
                stat['metadata_records' if metadata else ('flagged_samples' if reasons else 'valid_samples')] += 1
                if not metadata and not reasons:
                    stat.setdefault('first_sample_ticks', frame['timestamp_ticks'])
                    stat['last_sample_ticks'] = frame['timestamp_ticks']
                    stat['latest_valid_values'] = values
                    for name, value in values.items():
                        if isinstance(value, (int, float)) and not isinstance(value, bool):
                            summary = stat['values'].setdefault(name, dict(count=0, min=value, max=value, last=value))
                            summary.update(count=summary['count']+1, min=min(summary['min'], value), max=max(summary['max'], value), last=value)
        except (ValueError, TypeError, struct.error) as error:
            frame['classification'] = 'invalid_record'
            frame['decode_error'] = str(error)
            if stat is not None:
                stat['invalid_records'] += 1
        counts[frame['classification']] += 1
    for stat in sources.values():
        stat['health_assessment'] = ('valid_samples_observed' if stat['valid_samples'] else
                                     'flagged_data_only' if stat['flagged_samples'] else 'no_valid_sample_observed')
        if (stat.get('latest_health', {}).get('online') is False and stat['valid_samples'] and
                stat['latest_health']['timestamp_ticks'] >= stat.get('last_sample_ticks', 0)):
            stat['health_assessment'] = 'samples_observed_but_latest_health_offline'
        span = stat.get('last_sample_ticks', 0)-stat.get('first_sample_ticks', 0)
        stat['sample_span_seconds_at_100MHz'] = span/100000000
        if span > 0 and stat['valid_samples'] > 1:
            stat['observed_rate_Hz'] = (stat['valid_samples']-1)*100000000/span
    crc_fail = sum(not frame['crc_ok'] for frame in frames)
    return dict(bytes=len(data), sha256=hashlib.sha256(data).hexdigest(), frame_count=len(frames),
                crc_pass=len(frames)-crc_fail, crc_fail=crc_fail, framing_issues=issues,
                stream_integrity_ok=bool(frames) and not issues and not crc_fail,
                classification_counts=dict(counts),
                all_six_have_valid_samples=all(sources[source]['valid_samples'] for source in EXPECTED),
                sources={'0x%04X' % source: stat for source, stat in sources.items()}, frames=frames)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('captures', nargs='+', type=Path, help='Raw binary chunks in stream order')
    parser.add_argument('--output', type=Path)
    parser.add_argument('--require-six', action='store_true', help='Fail exit status unless all six sensors have valid samples')
    args = parser.parse_args()
    data = b''.join(path.read_bytes() for path in args.captures)
    result = analyze(data)
    result['input_files'] = [str(path.resolve()) for path in args.captures]
    destination = args.output or args.captures[0].with_name(args.captures[0].stem+'_sensors.json')
    destination.write_text(json.dumps(result, indent=2, ensure_ascii=False, allow_nan=False)+'\n', encoding='utf-8')
    print(json.dumps({key: value for key, value in result.items() if key != 'frames'}, indent=2, ensure_ascii=False))
    print('REPORT='+str(destination.resolve()))
    return int(not result['stream_integrity_ok'] or result['classification_counts'].get('invalid_record', 0) > 0 or
               (args.require_six and not result['all_six_have_valid_samples']))


if __name__ == '__main__':
    raise SystemExit(main())
