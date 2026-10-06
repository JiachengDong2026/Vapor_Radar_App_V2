"""Offline protocol examples; no hardware access."""
import struct
import unittest
import zlib

from analyze_sensors import analyze, crc8, crc16


def frame(source, payload, msg=0x1100, kind=0x10, flags=1, sequence=1):
    raw = struct.pack('<4sBBBBIIHHIQII', b'VLP1', 1, 0, kind, 10,
                      44+len(payload), sequence, source, msg, flags,
                      sequence*100000000, 0xffffffff, len(payload))+payload
    raw += struct.pack('<I', zlib.crc32(raw))
    return raw+b'\0'*((-len(raw)) % 4)


def record(*entries, schema=1):
    payload = struct.pack('<HH', schema, len(entries))
    for tag, kind, value in entries:
        raw = value if isinstance(value, bytes) else struct.pack('<i' if kind == 7 else '<I', value)
        payload += struct.pack('<HBB', tag, kind, len(raw))+raw+b'\0'*((-len(raw)) % 4)
    return payload


def fdi(payload=b'\0'*8):
    header = bytes([0xfc, 0x51, len(payload), 7])
    return header+bytes([crc8(header)])+crc16(payload).to_bytes(2, 'big')+payload+b'\xfd'


class SensorAnalysisTests(unittest.TestCase):
    def test_six_sensors_and_units(self):
        raw = b''.join([
            frame(0x40, record((0x12, 7, 101325000))),
            frame(0x42, fdi(), msg=0x1200),
            frame(0x43, record((0x101, 3, 7777777), (0x102, 3, 8888888))),
            frame(0x44, record((0x10, 7, -12500), (0x11, 3, 55000), (1, 3, 0))),
            frame(0x45, record((0x13, 3, 1234))),
            frame(0x46, record((0x460, 7, -100), (0x461, 7, 250), (1, 3, 1), schema=2))])
        result = analyze(raw)
        self.assertTrue(result['all_six_have_valid_samples'])
        self.assertTrue(result['stream_integrity_ok'])
        self.assertEqual(result['sources']['0x0040']['latest_valid_values']['pressure_Pa'], 101325)
        self.assertEqual(result['sources']['0x0044']['latest_valid_values']['temperature_C'], -12.5)
        self.assertEqual(result['sources']['0x0046']['latest_valid_values']['pv_C'], -10)
        self.assertNotIn('pressure_Pa', result['sources']['0x0043']['latest_valid_values'])

    def test_metadata_and_diagnostics_are_not_samples(self):
        result = analyze(frame(0x43, record((0x100, 11, bytes(range(21)))))+
                         frame(0x50, record((0x13, 3, 123)))+
                         frame(0x40, struct.pack('<8I', 1, 0x60, 0x13, 0, 1, 0, 0, 0), msg=0x1401, kind=0x12))
        self.assertEqual(result['sources']['0x0043']['metadata_records'], 1)
        self.assertEqual(result['sources']['0x0043']['valid_samples'], 0)
        self.assertEqual(result['sources']['0x0040']['valid_samples'], 0)
        self.assertTrue(result['sources']['0x0040']['latest_health']['online'])
        self.assertEqual(result['classification_counts']['other_or_diagnostic'], 1)

    def test_ai8_timeout_not_fresh_data(self):
        result = analyze(frame(0x46, record((0x460, 7, 250), (0x461, 7, 250), (1, 3, 2), schema=2)))
        self.assertEqual(result['sources']['0x0046']['flagged_samples'], 1)
        self.assertEqual(result['sources']['0x0046']['valid_samples'], 0)
        self.assertEqual(result['sources']['0x0046']['values'], {})

    def test_outer_crc_and_inner_crc_failures(self):
        raw = bytearray(frame(0x45, record((0x13, 3, 1234))))
        raw[48] ^= 1
        result = analyze(bytes(raw))
        self.assertEqual(result['crc_fail'], 1)
        self.assertEqual(result['sources']['0x0045']['valid_samples'], 0)
        inner = bytearray(fdi())
        inner[7] ^= 1
        result = analyze(frame(0x42, bytes(inner), msg=0x1200))
        self.assertTrue(result['stream_integrity_ok'])
        self.assertEqual(result['sources']['0x0042']['invalid_records'], 1)

    def test_split_stream_and_partial_boundaries(self):
        raw = frame(0x45, record((0x13, 3, 1234)))
        result = analyze(b''.join([raw[:1], raw[1:39], raw[39:47], raw[47:]]))
        self.assertTrue(result['stream_integrity_ok'])
        result = analyze(b'junk'+raw+raw[:23])
        self.assertEqual(result['sources']['0x0045']['valid_samples'], 1)
        self.assertEqual(len(result['framing_issues']), 2)
        self.assertFalse(result['stream_integrity_ok'])

    def test_malformed_tlv_and_error_event(self):
        result = analyze(frame(0x45, record((0x13, 7, 1234))))
        self.assertEqual(result['sources']['0x0045']['invalid_records'], 1)
        result = analyze(frame(0x45, struct.pack('<8I', 1, 0x65, 5, 4, 0x81, 0, 0, 0), msg=0x1402, kind=0x11))
        self.assertEqual(result['sources']['0x0045']['latest_health']['error_names'], ['timeout', 'fifo_overflow'])


if __name__ == '__main__':
    unittest.main()
