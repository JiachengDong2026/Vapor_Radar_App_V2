"""Offline unittest regression; no hardware or external libraries required."""
import hashlib
import json
from pathlib import Path
import struct
import unittest

from vlp_reference import (StreamParser, ResyncLimitError, crc32, pack_frame,
                           pack_ping, pack_read, pack_write, decode_response)

HERE = Path(__file__).resolve().parent


class ReferenceTests(unittest.TestCase):
    def test_crc_known_check(self):
        self.assertEqual(crc32(b'123456789'), 0xcbf43926)

    def test_golden(self):
        vectors = json.loads((HERE / 'golden_vectors.json').read_text(encoding='utf-8'))
        built = [pack_ping(), pack_read(0, 5, 2), pack_write(0x6004, [1], 1009)]
        for expected, item in zip(built, vectors['requests']):
            self.assertEqual(expected, bytes.fromhex(item['frame_hex']))
            self.assertEqual(hashlib.sha256(expected).hexdigest(), item['sha256'])
        for item in vectors['recorded_responses']:
            frame, = StreamParser().feed(bytes.fromhex(item['frame_hex']))
            self.assertEqual(decode_response(frame), item['decoded']['response'])
        read = vectors['recorded_responses'][1]['decoded']['response']
        self.assertEqual(read['values'], [0x00010101, 0, 0x92, 0xcf, 0x20260916])
        raw = bytes.fromhex(vectors['recorded_responses'][1]['frame_hex'])
        frame, = StreamParser().feed(raw)
        decode_response(frame, 1002, 1, 2, expected_address=0, expected_count=5)
        for kwargs in ({'expected_address': 4}, {'expected_count': 4}):
            with self.assertRaises(ValueError):
                decode_response(frame, **kwargs)

    def test_all_single_split_points(self):
        raw = pack_frame(2, 1, 1, 0xfe, b'\0' * 4 + b'hello', word_padding=True)
        for boundary in range(len(raw) + 1):
            parser = StreamParser()
            frames = parser.feed(raw[:boundary]) + parser.feed(raw[boundary:]) + parser.finish()
            self.assertEqual(len(frames), 1)
            self.assertEqual(decode_response(frames[0])['echo_hex'], b'hello'.hex())
            self.assertEqual(parser.discarded_bytes, 0)

    def test_real_capture_chunking_and_concatenation(self):
        raw = (HERE / 'capture_example.bin').read_bytes()
        expected = json.loads((HERE / 'capture_example_summary.json').read_text(encoding='utf-8'))
        self.assertEqual(hashlib.sha256(raw).hexdigest(), expected['sha256'])
        for chunk_size in (1, 3, 7, 39, 40, 43, 64, 127, 16384):
            parser = StreamParser(max_frame_bytes=1024)
            frames = []
            for offset in range(0, len(raw), chunk_size):
                frames.extend(parser.feed(raw[offset:offset + chunk_size]))
                self.assertLessEqual(len(parser.buffer), 1024)
            frames.extend(parser.finish())
            self.assertEqual(len(frames), expected['frame_count'])
            self.assertEqual(parser.discarded_bytes, 0)
            sources = {f.header['source'] for f in frames if f.header['kind'] == 0x10}
            self.assertEqual(sources, {0x40, 0x42, 0x43, 0x44, 0x45, 0x46})

    def test_bad_crc_and_junk_recover(self):
        good = pack_ping()
        bad = bytearray(good)
        bad[-1] ^= 0x80
        parser = StreamParser()
        frames = parser.feed(b'junk' + bad + good) + parser.finish()
        self.assertEqual([f.raw for f in frames], [good])
        self.assertEqual(parser.errors['crc_mismatch'], 1)
        self.assertEqual(parser.discarded_bytes, 4 + len(bad))

    def test_bad_outer_crc_keeps_embedded_valid_frame(self):
        good = pack_ping()
        outer = bytearray(pack_frame(0x10, 4, 0x42, 0x1200, good))
        outer[-1] ^= 1
        parser = StreamParser()
        frames = parser.feed(outer) + parser.finish()
        self.assertEqual([f.raw for f in frames], [good])
        self.assertEqual(frames[0].offset, 40)

    def test_bad_length_version_and_padding(self):
        good = pack_ping()
        for mode in ('length', 'version', 'padding'):
            bad = bytearray(pack_frame(0x10, 4, 0x42, 0x1200, b'x', word_padding=True))
            if mode == 'length':
                struct.pack_into('<I', bad, 8, 0xffffffff)
            elif mode == 'version':
                bad[4] = 2
            else:
                bad[-1] = 1
            parser = StreamParser(max_frame_bytes=1024)
            frames = parser.feed(bad + good) + parser.finish()
            self.assertEqual([f.raw for f in frames], [good])

    def test_incomplete_candidate_requires_eof_or_timeout(self):
        good = pack_ping()
        incomplete = pack_frame(0x10, 4, 0x42, 0x1200, b'x' * 512)[:40]
        for eof in (True, False):
            parser = StreamParser()
            self.assertEqual(parser.feed(incomplete + good), [])
            recovered = parser.finish() if eof else parser.expire_partial()
            self.assertEqual([f.raw for f in recovered], [good])
            self.assertEqual(parser.discarded_bytes, 40)

    def test_bounded_recovery(self):
        parser = StreamParser(max_frame_bytes=128, max_resync_bytes=16)
        with self.assertRaises(ResyncLimitError):
            parser.feed(b'X' * 1024)
        self.assertLessEqual(len(parser.buffer), 128)

    def test_response_matching_and_error_status(self):
        parser = StreamParser()
        raw = pack_frame(2, 17, 1, 3, struct.pack('<I', 7))
        frame, = parser.feed(raw)
        self.assertFalse(decode_response(frame, 17, 1, 3)['ok'])
        for kwargs in ({'expected_sequence': 18}, {'expected_source': 0x40}, {'expected_message': 2}):
            with self.assertRaises(ValueError):
                decode_response(frame, **kwargs)
        protocol_error, = StreamParser().feed(pack_frame(0x7f, 17, 1, 3, struct.pack('<I', 3)))
        self.assertFalse(decode_response(protocol_error)['ok'])

    def test_command_size_and_range_limits(self):
        self.assertEqual(len(pack_ping(echo=b'x' * 4052)), 4096)
        self.assertEqual(len(pack_write(0, [0] * 1011)), 4096)
        pack_read(0, 1021)
        for call in (lambda: pack_ping(echo=b'x' * 4053),
                     lambda: pack_write(0, [0] * 1012), lambda: pack_read(0, 1022),
                     lambda: pack_read(1, 1), lambda: pack_read(0xfffc, 2),
                     lambda: pack_write(0, [])):
            with self.assertRaises(ValueError):
                call()


    def test_one_byte_ping_has_wire_padding(self):
        raw = pack_ping(echo=b'x')
        self.assertEqual(len(raw), 48)
        self.assertEqual(struct.unpack_from('<I', raw, 8)[0], 45)
        self.assertEqual(struct.unpack_from('<I', raw, 36)[0], 1)
        self.assertEqual(raw[45:], b'\0' * 3)
        self.assertEqual(struct.unpack_from('<I', raw, 41)[0], crc32(raw[:41]))
        parser = StreamParser()
        frames = parser.feed(raw + pack_ping())
        self.assertEqual([f.payload for f in frames], [b'x', b'PING'])
        self.assertEqual(parser.discarded_bytes, 0)

    def test_default_in_frame_limit(self):
        parser = StreamParser()
        self.assertEqual(parser.max_frame_bytes, 8236)
        largest = pack_frame(0x10, 1, 0x42, 0x1200, b'x' * 8192, word_padding=True)
        self.assertEqual(len(parser.feed(largest)), 1)
        oversized = pack_frame(0x10, 2, 0x42, 0x1200, b'x' * 8193, word_padding=True)
        good = pack_ping()
        frames = parser.feed(oversized + good) + parser.finish()
        self.assertEqual([f.raw for f in frames], [good])
        self.assertEqual(parser.errors['invalid_length'], 1)
        self.assertEqual(parser.discarded_bytes, len(oversized))


if __name__ == '__main__':
    unittest.main(verbosity=2)
