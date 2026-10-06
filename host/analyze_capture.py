"""Validate a captured VLP1 stream offline. No USB access."""
from pathlib import Path
import collections
import hashlib
import json
import struct
import sys
import zlib


def analyze(data):
    offset = 0
    frames = []
    while offset < len(data):
        if len(data) - offset < 44:
            raise ValueError(f"Incomplete frame at byte {offset}")
        h = struct.unpack_from('<4sBBBBIIHHIQII', data, offset)
        magic, major, minor, kind, words, total, seq, src, msg, flags, ticks, cycle, payload_len = h
        if magic != b'VLP1' or (major, minor, words) != (1, 0, 10):
            raise ValueError(f"Invalid VLP1 header at byte {offset}")
        if total != 44 + payload_len or offset + total > len(data):
            raise ValueError(f"Invalid/incomplete length at byte {offset}")
        frame = data[offset:offset + total]
        received = struct.unpack_from('<I', frame, total - 4)[0]
        computed = zlib.crc32(frame[:-4])
        payload = frame[40:-4]
        frames.append(dict(index=len(frames) + 1, offset=offset, length=total,
                           kind=kind, sequence=seq, source=src, message=msg,
                           flags=flags, timestamp_ticks=ticks, cycle=cycle,
                           payload_hex=payload.hex(' '), crc_received=f'{received:08X}',
                           crc_computed=f'{computed:08X}', crc_ok=received == computed,
                           ping_seq1_ok=(received == computed and kind == 2 and seq == 1
                                         and src == 1 and msg == 0xFE
                                         and payload == b'\0\0\0\0PING')))
        padded = (total + 3) & ~3
        if offset + padded > len(data) or any(data[offset + total:offset + padded]):
            raise ValueError(f"Missing or nonzero word padding at byte {offset}")
        offset += padded
    return dict(bytes=len(data), sha256=hashlib.sha256(data).hexdigest(),
                frame_count=len(frames), crc_pass=sum(f['crc_ok'] for f in frames),
                crc_fail=sum(not f['crc_ok'] for f in frames),
                ping_seq1_count=sum(f['ping_seq1_ok'] for f in frames),
                message_counts=dict(collections.Counter(f"{f['kind']:02X}/{f['source']:04X}/{f['message']:04X}" for f in frames)),
                frames=frames)


if __name__ == '__main__':
    capture = Path(sys.argv[1]).resolve()
    result = analyze(capture.read_bytes())
    destination = capture.parent / (capture.stem + '_validation.json')
    destination.write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({k: v for k, v in result.items() if k != 'frames'}, indent=2))
    print('REPORT=' + str(destination))
    sys.exit(1 if result['crc_fail'] or not result['frame_count'] else 0)
