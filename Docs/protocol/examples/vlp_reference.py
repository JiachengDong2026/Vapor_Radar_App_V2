"""Offline VLP 1.0 reference; Python 3.9+, standard library, no device access.

Integers and CRC are little endian. USB read boundaries are not frame boundaries.
GPIF wire frames have zero padding to a four-byte boundary in both directions.
This reference deliberately implements only PING, READ_REG and simple WRITE_REG.
"""
import argparse
from collections import Counter, deque
from dataclasses import dataclass
import json
from pathlib import Path
import struct
import zlib

HEADER = struct.Struct('<4sBBBBIIHHIQII')
MAGIC = b'VLP1'
MAX_COMMAND_BYTES = 4096  # vlp_cmd_rx default BUFFER_BYTES in integrated top.
MAX_IN_FRAME_BYTES = 8236  # 40-byte header + 8192-byte payload + 4-byte CRC.
SOURCES = {0x40: 'PTB210', 0x41: 'HMP', 0x42: 'EPSILON', 0x43: 'BMP390',
           0x44: 'SHT45', 0x45: 'TFA1500', 0x46: 'AI8'}


def crc32(data):
    """CRC-32/ISO-HDLC; check('123456789') == 0xCBF43926."""
    return zlib.crc32(data) & 0xffffffff


def pack_frame(kind, sequence, source, message, payload=b'', flags=0,
               timestamp_ticks=0, cycle=0, word_padding=False):
    payload = bytes(payload)
    header = HEADER.pack(MAGIC, 1, 0, kind, 10, 44 + len(payload), sequence,
                         source, message, flags, timestamp_ticks, cycle, len(payload))
    body = header + payload
    result = body + struct.pack('<I', crc32(body))
    return result + (b'\0' * (-len(result) % 4) if word_padding else b'')


def _command(message, sequence, source, payload):
    if 44 + len(payload) > MAX_COMMAND_BYTES:
        raise ValueError('command exceeds integrated FPGA 4096-byte RX buffer')
    return pack_frame(1, sequence, source, message, payload, word_padding=True)


def pack_ping(sequence=1, echo=b'PING', source=1):
    return _command(0xfe, sequence, source, bytes(echo))


def _register_range(address, count):
    if not 0 <= address <= 0xffff or address % 4 or not 1 <= count <= 0xffff:
        raise ValueError('requires aligned 16-bit byte address and nonzero count')
    if address + 4 * count > 0x10000:
        raise ValueError('register range exceeds 16-bit address space')


def pack_read(address, count=1, sequence=2, source=1):
    _register_range(address, count)
    if count > 1021:
        raise ValueError('READ_REG count exceeds RTL response RAM limit of 1021')
    return _command(2, sequence, source, struct.pack('<II', address, count))


def pack_write(address, values, sequence=3, source=1):
    """Simple WRITE_REG, count <= 1011, option bits zero; no automatic commit.

    Packing bytes does not send them. Register permissions are checked by FPGA.
    A failing multiword write can have already changed earlier words.
    """
    values = tuple(values)
    _register_range(address, len(values))
    return _command(3, sequence, source,
                    struct.pack('<II', address, len(values)) +
                    struct.pack('<%dI' % len(values), *values))


@dataclass(frozen=True)
class Frame:
    offset: int
    raw: bytes  # Header + payload + CRC, excluding outer word padding.

    @property
    def header(self):
        fields = HEADER.unpack_from(self.raw)
        return dict(zip(('magic', 'major', 'minor', 'kind', 'header_words', 'total',
                         'sequence', 'source', 'message', 'flags', 'timestamp_ticks',
                         'cycle', 'payload_length'), fields))

    @property
    def payload(self):
        return self.raw[40:-4]


class ResyncLimitError(ValueError):
    pass


class StreamParser:
    """Incremental CRC-validating parser with bounded pending data and recovery.

    max_frame_bytes includes header and CRC, not alignment padding. The default
    8236 matches this integrated IN path (8192-byte payload plus 44 bytes).
    Override only when the actual producer requires another bound. Rejected
    candidates advance ONE byte so an embedded valid frame can be recovered.
    max_resync_bytes limits consecutive discarded bytes; valid frames reset it.
    Errors are counted; only the last 64 diagnostic entries are retained.

    A plausible incomplete length waits for data: use expire_partial() after an
    application timeout, or finish() at EOF. No wall clock or retry policy here.
    Returned frame lists can grow with caller input; keep feed chunks moderate.
    After ResyncLimitError discard this parser and decide how to reopen/recover.
    """
    def __init__(self, max_frame_bytes=MAX_IN_FRAME_BYTES, max_resync_bytes=1 << 20,
                 word_padding=True):
        if max_frame_bytes < 44 or max_resync_bytes < 1:
            raise ValueError('invalid parser limits')
        self.max_frame_bytes = max_frame_bytes
        self.max_resync_bytes = max_resync_bytes
        self.word_padding = word_padding
        self.buffer = bytearray()
        self.offset = 0
        self.consecutive_discarded = 0
        self.discarded_bytes = 0
        self.frame_count = 0
        self.errors = Counter()
        self.recent_errors = deque(maxlen=64)

    def _discard(self, count, reason):
        self.errors[reason] += 1
        self.recent_errors.append(dict(offset=self.offset, bytes=count, reason=reason))
        del self.buffer[:count]
        self.offset += count
        self.discarded_bytes += count
        self.consecutive_discarded += count
        if self.consecutive_discarded > self.max_resync_bytes:
            raise ResyncLimitError('resynchronization discard budget exhausted')

    def _drain(self, eof=False):
        frames = []
        while self.buffer:
            if len(self.buffer) < 4:
                if eof:
                    self._discard(len(self.buffer), 'trailing_bytes')
                break
            if self.buffer[:4] != MAGIC:
                next_magic = self.buffer.find(MAGIC, 1)
                count = next_magic if next_magic >= 0 else len(self.buffer) - 3
                self._discard(count, 'unframed_bytes')
                continue
            if len(self.buffer) < 40:
                if eof:
                    self._discard(1, 'partial_header')
                    continue
                break
            header = HEADER.unpack_from(self.buffer)
            total, payload_length = header[5], header[12]
            if header[1:3] != (1, 0) or header[4] != 10:
                self._discard(1, 'unsupported_header')
                continue
            if total < 44 or total > self.max_frame_bytes or total != payload_length + 44:
                self._discard(1, 'invalid_length')
                continue
            aligned = (total + 3) & ~3 if self.word_padding else total
            if len(self.buffer) < aligned:
                if eof:
                    self._discard(1, 'partial_frame')
                    continue
                break
            expected = struct.unpack_from('<I', self.buffer, total - 4)[0]
            if crc32(self.buffer[:total - 4]) != expected:
                self._discard(1, 'crc_mismatch')
                continue
            if any(self.buffer[total:aligned]):
                self._discard(1, 'nonzero_padding')
                continue
            frames.append(Frame(self.offset, bytes(self.buffer[:total])))
            del self.buffer[:aligned]
            self.offset += aligned
            self.frame_count += 1
            self.consecutive_discarded = 0
        return frames

    def feed(self, data):
        """Accept arbitrary fragments/concatenation, returning complete frames."""
        data = memoryview(data)
        limit = (self.max_frame_bytes + 3) & ~3
        result = []
        cursor = 0
        while cursor < len(data):
            take = min(len(data) - cursor, limit - len(self.buffer))
            if take <= 0:
                raise RuntimeError('parser made no progress within buffer limit')
            self.buffer.extend(data[cursor:cursor + take])
            cursor += take
            result.extend(self._drain())
        return result

    def expire_partial(self):
        """Caller-declared timeout: discard current candidate and resume search."""
        if self.buffer:
            self._discard(1, 'caller_timeout')
        return self._drain()

    def finish(self):
        """Signal EOF, account for trailing bytes and recover complete inner frames."""
        return self._drain(eof=True)

    def statistics(self):
        return dict(frames=self.frame_count, consumed_bytes=self.offset,
                    pending_bytes=len(self.buffer), discarded_bytes=self.discarded_bytes,
                    errors=dict(self.errors), recent_errors=list(self.recent_errors))


def decode_response(frame, expected_sequence=None, expected_source=None,
                    expected_message=None, expected_address=None, expected_count=None):
    """Validate response identity/status and essential PING/READ/WRITE layout.

    CRC/framing must have been validated by StreamParser. A matching sequence
    alone is insufficient: match source and message too; data/event frames may
    occur between request and response. Nonzero status means failure even when
    frame kind is 0x02. Kind 0x7f is a parser/protocol error response.
    """
    h, payload = frame.header, frame.payload
    if h['kind'] not in (2, 0x7f) or len(payload) < 4:
        raise ValueError('not a complete response')
    for key, expected in (('sequence', expected_sequence), ('source', expected_source),
                          ('message', expected_message)):
        if expected is not None and h[key] != expected:
            raise ValueError('response %s does not match request' % key)
    status = struct.unpack_from('<I', payload)[0]
    result = dict(status=status, ok=h['kind'] == 2 and status == 0)
    if not result['ok']:
        result['detail_hex'] = payload[4:].hex()
        return result
    if h['message'] == 0xfe:
        result['echo_hex'] = payload[4:].hex()
    elif h['message'] == 2:
        if len(payload) < 12:
            raise ValueError('truncated successful READ_REG response')
        address, count = struct.unpack_from('<II', payload, 4)
        if not 1 <= count <= 1021 or len(payload) != 12 + count * 4:
            raise ValueError('READ_REG response length/count mismatch')
        if expected_address is not None and address != expected_address:
            raise ValueError('READ_REG response address does not match request')
        if expected_count is not None and count != expected_count:
            raise ValueError('READ_REG response count does not match request')
        result.update(address=address, count=count,
                      values=list(struct.unpack_from('<%dI' % count, payload, 12)))
    elif h['message'] == 3 and len(payload) != 4:
        raise ValueError('WRITE_REG success response must contain only status')
    else:
        result['detail_hex'] = payload[4:].hex()
    return result


def describe(frame):
    h = frame.header
    h.pop('magic')
    result = dict(offset=frame.offset, **h, source_name=SOURCES.get(h['source'], 'other'),
                  payload_hex=frame.payload.hex(' '),
                  crc_hex='%08X' % struct.unpack_from('<I', frame.raw, len(frame.raw) - 4)[0])
    if h['kind'] in (2, 0x7f):
        result['response'] = decode_response(frame)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('capture', type=Path)
    parser.add_argument('--chunk-size', type=int, default=4093)
    args = parser.parse_args()
    if args.chunk_size < 1:
        parser.error('--chunk-size must be positive')
    stream = StreamParser()
    with args.capture.open('rb') as capture:
        while True:
            chunk = capture.read(args.chunk_size)
            if not chunk:
                break
            for frame in stream.feed(chunk):
                print(json.dumps(describe(frame), ensure_ascii=False))
    for frame in stream.finish():
        print(json.dumps(describe(frame), ensure_ascii=False))
    print(json.dumps({'parser_statistics': stream.statistics()}))
    return int(stream.discarded_bytes != 0 or stream.frame_count == 0)


if __name__ == '__main__':
    raise SystemExit(main())
