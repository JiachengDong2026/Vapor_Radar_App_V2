import unittest
import numpy as np
from scipy.signal import butter, sosfreqz

from dlia_filter_coefficients import Q46, WORD_COUNT, generate_dlia_filter


class DliaFilterCoefficientTests(unittest.TestCase):
    def test_all_supported_orders_generate_complete_stable_banks(self):
        for order in range(2, 9):
            with self.subTest(order=order):
                result = generate_dlia_filter(1_000_000, 1250, order)
                self.assertEqual(len(result.sections_q46), 4)
                self.assertEqual(len(result.register_words), WORD_COUNT)
                for section in result.sections_q46[(order + 1) // 2:]:
                    self.assertEqual(section, (Q46, 0, 0, 0, 0))

    def test_rejects_invalid_rate_cutoff_and_order(self):
        for args in ((0, 100, 2), (1_000_000, 500_000, 2), (1_000_000, 0, 2), (1_000_000, 1000, 9),
                     (1_000_000, float('nan'), 2), (1_000_000, 1000, 2.5)):
            with self.subTest(args=args), self.assertRaises(ValueError):
                generate_dlia_filter(*args)

    def test_quantized_frequency_response_and_wire_roundtrip(self):
        for rate in (500_000, 1_000_000, 12_500_000):
            for cutoff in (100, 1250, 10000):
                for order in range(2, 9):
                    with self.subTest(rate=rate, cutoff=cutoff, order=order):
                        result = generate_dlia_filter(rate, cutoff, order)
                        active = result.sections_q46[:(order + 1) // 2]
                        for b0, b1, b2, a1, a2 in active:
                            self.assertEqual(b0 + b1 + b2, Q46 + a1 + a2)
                            self.assertTrue(all(abs(p) < 1 for p in np.roots([1, a1/Q46, a2/Q46])))
                        if order % 2:
                            self.assertEqual(active[-1][2], 0)
                            self.assertEqual(active[-1][4], 0)
                        rows = [[b0/Q46, b1/Q46, b2/Q46, 1, a1/Q46, a2/Q46] for b0,b1,b2,a1,a2 in active]
                        frequencies = np.array([0, cutoff/4, cutoff, cutoff*2, cutoff*4])
                        _, measured = sosfreqz(rows, worN=frequencies, fs=rate)
                        _, reference = sosfreqz(butter(order, cutoff, fs=rate, output='sos'), worN=frequencies, fs=rate)
                        np.testing.assert_allclose(measured, reference, atol=1e-4, rtol=1e-4)
                        raw = b''.join(word.to_bytes(4, 'little') for word in result.register_words)
                        decoded = tuple(int.from_bytes(raw[i:i+6], 'little', signed=True) for i in range(0, 120, 6))
                        self.assertEqual(decoded, sum(result.sections_q46, ()))


if __name__ == "__main__":
    unittest.main()
